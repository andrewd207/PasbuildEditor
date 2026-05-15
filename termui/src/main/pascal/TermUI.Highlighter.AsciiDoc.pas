{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Highlighter.AsciiDoc;

{$mode objfpc}{$H+}

{ AsciiDoc syntax highlighter for TTextEditor.

  Assign an instance to TTextEditor.Highlighter.  Prepare does a single
  full-document pass to classify every line (handling multi-line code blocks,
  tables, etc.).  GetSpans then returns color spans for one line without
  re-scanning the whole document.

  Line color scheme mirrors the existing TAsciiDocViewer:
    H1            bright cyan
    H2            bright yellow + underline
    H3            bright green
    H4            green
    Code          bright black (dim)
    Code fence    bright black
    Rule          bright black
    Bullet marker bright yellow, rest: inline markup
    Comment       bright black
    Paragraph     inline markup

  Inline markup within paragraphs and bullet text:
    *word*        bright white (bold-ish)
    _word_        underline
    `word`  +word+ cyan (mono)  }

interface

uses
  Classes, SysUtils, TermUI.Terminal, TermUI.Control.Editor, TermUI.StringUtils;

type
  TAsciiDocHighlighter = class(TTextHighlighter)
  private
    type TLineKind = (
      lkBlank,
      lkH1, lkH2, lkH3, lkH4,
      lkPara,
      lkBullet,
      lkCode,
      lkCodeFence,
      lkRule,
      lkComment,
      lkAttribute,
      lkTable
    );

  private
    FKinds:     array of TLineKind;
    FKindCount: Integer;

    function  KindOf(ARow: Integer): TLineKind;
    procedure AddInlineSpans(const ALine: string; AStartCol: Integer;
      var ASpans: TTextSpanArray; var ACount: Integer);
    procedure AppendSpan(var ASpans: TTextSpanArray; var ACount: Integer;
      ACol, ALen: Integer; AFG: TColor; AUnderline: Boolean);
  public
    procedure Prepare(ALines: TStrings); override;
    procedure GetSpans(ARow: Integer; const ALine: string;
      out ASpans: TTextSpanArray); override;
  end;

implementation

uses Math;

{ ── Span helpers ── }

procedure TAsciiDocHighlighter.AppendSpan(var ASpans: TTextSpanArray;
  var ACount: Integer; ACol, ALen: Integer; AFG: TColor; AUnderline: Boolean);
begin
  if ALen <= 0 then Exit;
  if ACount >= Length(ASpans) then
    SetLength(ASpans, Max(8, Length(ASpans) * 2));
  ASpans[ACount].Col       := ACol;
  ASpans[ACount].Len       := ALen;
  ASpans[ACount].FG        := AFG;
  ASpans[ACount].BG        := clDefault;
  ASpans[ACount].Underline := AUnderline;
  Inc(ACount);
end;

{ Walk ALine from AStartCol (0-based byte offset into ALine+1) and emit spans
  for *bold*, _italic_, `mono` / +mono+ inline markup. }
procedure TAsciiDocHighlighter.AddInlineSpans(const ALine: string;
  AStartCol: Integer; var ASpans: TTextSpanArray; var ACount: Integer);
var
  I, SpanStart: Integer;
  InBold, InItal, InMono: Boolean;
  Ch: Char;
  FG: TColor;
  UL: Boolean;
begin
  InBold := False; InItal := False; InMono := False;
  I := AStartCol + 1;  { 1-based index into ALine }
  while I <= Length(ALine) do
  begin
    Ch := ALine[I];
    if Ch in ['*', '_', '`', '+'] then
    begin
      { Determine new state }
      case Ch of
        '*': InBold := not InBold;
        '_': InItal := not InItal;
        '`', '+': InMono := not InMono;
      end;
      { Emit a 1-char span for the marker itself in dim }
      AppendSpan(ASpans, ACount, I - 1, 1, clBrightBlack, False);
      Inc(I);
      { Emit run of plain chars until next marker or end, with current style }
      SpanStart := I - 1;  { 0-based }
      while (I <= Length(ALine)) and not (ALine[I] in ['*', '_', '`', '+']) do
        Inc(I);
      if InBold  then FG := clBrightWhite
      else if InMono then FG := clCyan
      else           FG := clDefault;
      UL := InItal;
      AppendSpan(ASpans, ACount, SpanStart, I - 1 - SpanStart, FG, UL);
    end
    else
      Inc(I);
  end;
end;

{ ── Prepare: full-document line classification ── }

function TAsciiDocHighlighter.KindOf(ARow: Integer): TLineKind;
begin
  if (ARow >= 0) and (ARow < FKindCount) then
    Result := FKinds[ARow]
  else
    Result := lkPara;
end;

procedure TAsciiDocHighlighter.Prepare(ALines: TStrings);
var
  I, EqCount: Integer;
  S:          string;
  InCode:     Boolean;
  InTable:    Boolean;
begin
  FKindCount := ALines.Count;
  SetLength(FKinds, FKindCount);
  InCode  := False;
  InTable := False;

  for I := 0 to ALines.Count - 1 do
  begin
    S := ALines[I];

    { Code fence }
    if S = '----' then
    begin
      FKinds[I] := lkCodeFence;
      InCode    := not InCode;
      Continue;
    end;

    if InCode then
    begin
      FKinds[I] := lkCode;
      Continue;
    end;

    { Table fence }
    if S = '|===' then
    begin
      FKinds[I] := lkTable;
      InTable   := not InTable;
      Continue;
    end;
    if InTable then
    begin
      FKinds[I] := lkTable;
      Continue;
    end;

    { Comment }
    if CopyNeutral(S, 0, 2) = '//' then
    begin
      FKinds[I] := lkComment;
      Continue;
    end;

    { Attribute line e.g. [source,pascal] }
    if (Length(S) > 0) and (S[1] = '[') then
    begin
      FKinds[I] := lkAttribute;
      Continue;
    end;

    { Blank }
    if Trim(S) = '' then
    begin
      FKinds[I] := lkBlank;
      Continue;
    end;

    { Headings: count leading '=' chars }
    EqCount := 0;
    while (EqCount < Length(S)) and (S[EqCount + 1] = '=') do
      Inc(EqCount);
    if (EqCount >= 1) and (EqCount <= 4) and
       (EqCount < Length(S)) and (S[EqCount + 1] = ' ') then
    begin
      case EqCount of
        1: FKinds[I] := lkH1;
        2: FKinds[I] := lkH2;
        3: FKinds[I] := lkH3;
        4: FKinds[I] := lkH4;
      end;
      Continue;
    end;

    { Horizontal rule }
    if (Length(S) >= 3) and (S = StringOfChar('-', Length(S))) then
    begin
      FKinds[I] := lkRule;
      Continue;
    end;

    { Bullet }
    if (Length(S) >= 2) and (S[1] in ['*', '-', '.']) and (S[2] = ' ') then
    begin
      FKinds[I] := lkBullet;
      Continue;
    end;

    FKinds[I] := lkPara;
  end;
end;

{ ── GetSpans: per-line span generation ── }

procedure TAsciiDocHighlighter.GetSpans(ARow: Integer; const ALine: string;
  out ASpans: TTextSpanArray);
var
  Kind:  TLineKind;
  Count: Integer;
  Len:   Integer;
begin
  ASpans := nil;
  Count  := 0;
  Len    := Length(ALine);
  if Len = 0 then Exit;

  Kind := KindOf(ARow);

  SetLength(ASpans, 8);

  case Kind of
    lkH1:
      AppendSpan(ASpans, Count, 0, Len, clBrightCyan, False);

    lkH2:
      AppendSpan(ASpans, Count, 0, Len, clBrightYellow, True);

    lkH3:
      AppendSpan(ASpans, Count, 0, Len, clBrightGreen, False);

    lkH4:
      AppendSpan(ASpans, Count, 0, Len, clGreen, False);

    lkCode:
      AppendSpan(ASpans, Count, 0, Len, clBrightBlack, False);

    lkCodeFence:
      AppendSpan(ASpans, Count, 0, Len, clBrightBlack, False);

    lkRule:
      AppendSpan(ASpans, Count, 0, Len, clBrightBlack, False);

    lkComment:
      AppendSpan(ASpans, Count, 0, Len, clBrightBlack, False);

    lkAttribute:
      AppendSpan(ASpans, Count, 0, Len, clBrightBlack, False);

    lkTable:
      AppendSpan(ASpans, Count, 0, Len, clBrightBlack, False);

    lkBullet:
      begin
        { Marker character + space in bright yellow, rest with inline markup }
        AppendSpan(ASpans, Count, 0, 2, clBrightYellow, False);
        AddInlineSpans(ALine, 2, ASpans, Count);
      end;

    lkPara:
      AddInlineSpans(ALine, 0, ASpans, Count);

    lkBlank: ;
  end;

  SetLength(ASpans, Count);
end;

initialization
  RegisterHighlighter(TAsciiDocHighlighter, '.adoc;.asciidoc');

end.
