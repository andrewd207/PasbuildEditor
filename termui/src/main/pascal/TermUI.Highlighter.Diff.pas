{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Highlighter.Diff;

{$mode objfpc}{$H+}

{ Unified-diff / patch syntax highlighter for TTextEditor.

  Recognizes the format produced by `git diff`, `diff -u`, and `svn diff`:

    diff --git a/foo b/foo     header        bright yellow fg
    index abc..def 100644      header        bright yellow fg
    --- a/foo                  old-file hdr  bright magenta fg
    +++ b/foo                  new-file hdr  bright magenta fg
    @@ -1,3 +1,4 @@            hunk header   bright cyan fg
     context line              context       default
    -removed line              removed       red bg
    +added line                added         green bg
    \ No newline at end of...  meta          bright black fg

  Intra-line refinement: when a contiguous run of '-' lines is immediately
  followed by an equal-count run of '+' lines, pair them 1:1 and compute a
  common-prefix/common-suffix diff.  The base for the whole line is the
  256-color dark green/dark red (xterm 22 / 52).  The differing middle is
  overlaid with the standard ANSI green/red, which reads as a lighter
  highlight against the darker base.

  Spans use 0-based codepoint columns (as required by TTextEditor).  The
  intra-line refinement operates on bytes — correct for ASCII content
  (the overwhelming majority of source-code diffs).  Multi-byte UTF-8 inside
  a paired changed region will fall back to the whole-line tint.
}

interface

uses
  Classes, SysUtils, TermUI.Terminal, TermUI.Control.Editor;

type
  TDiffLineKind = (dlkOther, dlkHeader, dlkOldFile, dlkNewFile, dlkHunk,
                   dlkContext, dlkDel, dlkAdd, dlkNoNewline);

  TDiffRange = record
    Col: Integer;   { 0-based codepoint offset within the line }
    Len: Integer;
  end;
  TDiffRangeArray = array of TDiffRange;

  TDiffHighlighter = class(TTextHighlighter)
  private
    FKind:    array of TDiffLineKind;
    FIntra:   array of TDiffRangeArray;  { intra-line "changed" ranges (one entry per - or + line) }
    FCount:   Integer;

    procedure ClassifyLine(const S: string; out Kind: TDiffLineKind);
    procedure PairBlocks(ALines: TStrings; ADelStart, ADelEnd,
      AAddStart, AAddEnd: Integer);
    procedure AppendSpan(var ASpans: TTextSpanArray; var ACount: Integer;
      ACol, ALen: Integer; AFG, ABG: TColor);
  public
    procedure Prepare(ALines: TStrings); override;
    procedure GetSpans(ARow: Integer; const ALine: string;
      out ASpans: TTextSpanArray); override;
    function  Name: string; override;
  end;

implementation

uses Math;

procedure TDiffHighlighter.AppendSpan(var ASpans: TTextSpanArray;
  var ACount: Integer; ACol, ALen: Integer; AFG, ABG: TColor);
begin
  if ALen <= 0 then Exit;
  if ACount >= Length(ASpans) then
    SetLength(ASpans, Max(8, Length(ASpans) * 2));
  ASpans[ACount].Col       := ACol;
  ASpans[ACount].Len       := ALen;
  ASpans[ACount].FG        := AFG;
  ASpans[ACount].BG        := ABG;
  ASpans[ACount].Underline := False;
  Inc(ACount);
end;

procedure TDiffHighlighter.ClassifyLine(const S: string; out Kind: TDiffLineKind);
var
  L: Integer;
begin
  L := Length(S);
  Kind := dlkOther;
  if L = 0 then Exit;

  { Order matters: '---' / '+++' (file headers) must be checked before '-' / '+' (hunk lines). }
  if (L >= 3) and (S[1] = '-') and (S[2] = '-') and (S[3] = '-') then
    Kind := dlkOldFile
  else if (L >= 3) and (S[1] = '+') and (S[2] = '+') and (S[3] = '+') then
    Kind := dlkNewFile
  else if (L >= 2) and (S[1] = '@') and (S[2] = '@') then
    Kind := dlkHunk
  else if (L >= 2) and (S[1] = '\') and (S[2] = ' ') then
    Kind := dlkNoNewline
  else if S[1] = '-' then
    Kind := dlkDel
  else if S[1] = '+' then
    Kind := dlkAdd
  else if S[1] = ' ' then
    Kind := dlkContext
  else if (Pos('diff ',   S) = 1) or
          (Pos('index ',  S) = 1) or
          (Pos('old mode',S) = 1) or
          (Pos('new mode',S) = 1) or
          (Pos('deleted file', S) = 1) or
          (Pos('new file',     S) = 1) or
          (Pos('rename ',      S) = 1) or
          (Pos('similarity ',  S) = 1) or
          (Pos('dissimilarity ', S) = 1) or
          (Pos('copy ',        S) = 1) or
          (Pos('Binary files ', S) = 1) or
          (Pos('===',          S) = 1) or
          (Pos('Index: ',      S) = 1) then
    Kind := dlkHeader;
end;

{ UTF-8 codepoint count of the first ABytes bytes of S. Counts each byte that
  is NOT a UTF-8 continuation byte (10xxxxxx). For pure ASCII this equals ABytes. }
function Utf8Count(const S: string; ABytes: Integer): Integer;
var
  I: Integer;
  B: Byte;
begin
  Result := 0;
  if ABytes > Length(S) then ABytes := Length(S);
  for I := 1 to ABytes do
  begin
    B := Byte(S[I]);
    if (B and $C0) <> $80 then Inc(Result);
  end;
end;

{ Pair the Del block [ADelStart..ADelEnd] with the Add block [AAddStart..AAddEnd].
  Only pairs 1:1 when counts match; otherwise leaves intra-line data empty. }
procedure TDiffHighlighter.PairBlocks(ALines: TStrings; ADelStart, ADelEnd,
  AAddStart, AAddEnd: Integer);
var
  N, I, DLen, ALen, PfxBytes, SfxBytes, MaxSfx: Integer;
  DLine, ALine: string;
  DColStart, AColStart, DColLen, AColLen: Integer;
begin
  N := ADelEnd - ADelStart + 1;
  if N <> (AAddEnd - AAddStart + 1) then Exit;

  for I := 0 to N - 1 do
  begin
    DLine := ALines[ADelStart + I];
    ALine := ALines[AAddStart + I];
    { Drop leading '-' / '+' marker (1 byte) }
    DLen := Length(DLine) - 1;
    ALen := Length(ALine) - 1;
    if (DLen <= 0) or (ALen <= 0) then Continue;

    { Common prefix (bytes), starting after the marker }
    PfxBytes := 0;
    while (PfxBytes < DLen) and (PfxBytes < ALen) and
          (DLine[2 + PfxBytes] = ALine[2 + PfxBytes]) do
      Inc(PfxBytes);

    { Common suffix (bytes), not overlapping the prefix }
    SfxBytes := 0;
    MaxSfx := Min(DLen, ALen) - PfxBytes;
    while (SfxBytes < MaxSfx) and
          (DLine[1 + DLen - SfxBytes] = ALine[1 + ALen - SfxBytes]) do
      Inc(SfxBytes);

    { Fully identical (shouldn't happen in a real diff) — no intra spans }
    if (PfxBytes = DLen) and (PfxBytes = ALen) then Continue;
    { Whole line differs — no point overlaying }
    if (PfxBytes = 0) and (SfxBytes = 0) then Continue;

    { Convert byte offsets to codepoint columns. Col is 0-based from line start,
      so add 1 for the leading +/- marker. }
    DColStart := 1 + Utf8Count(DLine, 1 + PfxBytes) - 1;
    DColLen   := Utf8Count(DLine, Length(DLine) - SfxBytes) -
                 Utf8Count(DLine, 1 + PfxBytes);
    AColStart := 1 + Utf8Count(ALine, 1 + PfxBytes) - 1;
    AColLen   := Utf8Count(ALine, Length(ALine) - SfxBytes) -
                 Utf8Count(ALine, 1 + PfxBytes);

    if DColLen > 0 then
    begin
      SetLength(FIntra[ADelStart + I], 1);
      FIntra[ADelStart + I][0].Col := DColStart;
      FIntra[ADelStart + I][0].Len := DColLen;
    end;
    if AColLen > 0 then
    begin
      SetLength(FIntra[AAddStart + I], 1);
      FIntra[AAddStart + I][0].Col := AColStart;
      FIntra[AAddStart + I][0].Len := AColLen;
    end;
  end;
end;

procedure TDiffHighlighter.Prepare(ALines: TStrings);
var
  I: Integer;
  DelStart, DelEnd, AddStart, AddEnd: Integer;
begin
  FCount := ALines.Count;
  SetLength(FKind,  FCount);
  SetLength(FIntra, FCount);
  for I := 0 to FCount - 1 do
  begin
    ClassifyLine(ALines[I], FKind[I]);
    FIntra[I] := nil;
  end;

  { Walk and pair adjacent Del/Add runs }
  I := 0;
  while I < FCount do
  begin
    if FKind[I] = dlkDel then
    begin
      DelStart := I;
      while (I < FCount) and (FKind[I] = dlkDel) do Inc(I);
      DelEnd := I - 1;
      if (I < FCount) and (FKind[I] = dlkAdd) then
      begin
        AddStart := I;
        while (I < FCount) and (FKind[I] = dlkAdd) do Inc(I);
        AddEnd := I - 1;
        PairBlocks(ALines, DelStart, DelEnd, AddStart, AddEnd);
      end;
    end
    else
      Inc(I);
  end;
end;

function TDiffHighlighter.Name: string;
begin
  Result := 'Diff';
end;

procedure TDiffHighlighter.GetSpans(ARow: Integer; const ALine: string;
  out ASpans: TTextSpanArray);
var
  Count, Len, J: Integer;
  K: TDiffLineKind;
  CharLen: Integer;
begin
  ASpans := nil;
  Count  := 0;
  Len    := Length(ALine);
  if Len = 0 then Exit;
  if (ARow < 0) or (ARow >= FCount) then Exit;

  SetLength(ASpans, 8);
  K := FKind[ARow];
  CharLen := Utf8Count(ALine, Len);

  case K of
    dlkHeader:
      AppendSpan(ASpans, Count, 0, CharLen, clBrightYellow, clDefault);
    dlkOldFile:
      AppendSpan(ASpans, Count, 0, CharLen, clBrightMagenta, clDefault);
    dlkNewFile:
      AppendSpan(ASpans, Count, 0, CharLen, clBrightMagenta, clDefault);
    dlkHunk:
      AppendSpan(ASpans, Count, 0, CharLen, clBrightCyan, clDefault);
    dlkNoNewline:
      AppendSpan(ASpans, Count, 0, CharLen, clBrightBlack, clDefault);
    dlkDel:
      begin
        AppendSpan(ASpans, Count, 0, CharLen, clBrightWhite, clBrick);
        for J := 0 to High(FIntra[ARow]) do
          AppendSpan(ASpans, Count,
            FIntra[ARow][J].Col, FIntra[ARow][J].Len,
            clBrightWhite, clRed);
      end;
    dlkAdd:
      begin
        AppendSpan(ASpans, Count, 0, CharLen, clBrightWhite, clForestGreen);
        for J := 0 to High(FIntra[ARow]) do
          AppendSpan(ASpans, Count,
            FIntra[ARow][J].Col, FIntra[ARow][J].Len,
            clBrightWhite, clGreen);
      end;
    dlkContext, dlkOther:
      ;  { no styling }
  end;

  SetLength(ASpans, Count);
end;

initialization
  RegisterHighlighter(TDiffHighlighter, '.diff;.patch');

end.
