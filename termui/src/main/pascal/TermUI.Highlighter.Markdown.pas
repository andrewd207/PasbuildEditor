{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Highlighter.Markdown;

{$mode objfpc}{$H+}

{ Markdown syntax highlighter for TTextEditor.

  Prepare does a single full-document pass to detect fenced code blocks
  (``` or ~~~).  GetSpans then returns color spans for one line.

  Color scheme:
    ATX heading  # … ######    bright cyan (H1), bright yellow (H2),
                                bright green (H3+)
    Setext H1 (===)             bright cyan
    Setext H2 (---)             bright yellow
    Fenced code fence           bright black
    Code line (inside fence)    bright black
    Indented code (4+ spaces)   bright black
    Block quote  >              yellow (marker), default (rest)
    Ordered/unordered list      bright yellow (marker), default (rest)
    Horizontal rule             bright black
    HTML comment <!-- ... -->   bright black
    Bold   **…** / __…__        bright white
    Italic *…*  / _…_           default + underline
    Inline code `…`             cyan
    Link text [label](url)      bright blue (label), bright black (url)
    Image alt ![alt](url)       bright blue (alt),   bright black (url)
}

interface

uses
  Classes, SysUtils, TermUI.Terminal, TermUI.Control.Editor;

type
  TMarkdownHighlighter = class(TTextHighlighter)
  private
    FInFence:    array of Boolean;  { True when line i is inside any fence }
    FFenceLang:  array of string;   { highlighter name for fence-content line; '' = dim }
    FCount:      Integer;
    FEmbedded:   TStringList;       { name -> TTextHighlighter, owned }

    procedure AppendSpan(var ASpans: TTextSpanArray; var ACount: Integer;
      ACol, ALen: Integer; AFG: TColor; AUnderline: Boolean = False);
    procedure AddInlineSpans(const ALine: string; AStartCol: Integer;
      var ASpans: TTextSpanArray; var ACount: Integer);
    function  EmbeddedHL(const AName: string): TTextHighlighter;
  public
    constructor Create; override;
    destructor  Destroy; override;
    procedure Prepare(ALines: TStrings); override;
    procedure GetSpans(ARow: Integer; const ALine: string;
      out ASpans: TTextSpanArray); override;
    function  Name: string; override;
  end;

implementation

uses Math;

constructor TMarkdownHighlighter.Create;
begin
  inherited;
  FEmbedded := TStringList.Create;
  FEmbedded.OwnsObjects := True;
  FEmbedded.Sorted      := True;
end;

destructor TMarkdownHighlighter.Destroy;
begin
  FEmbedded.Free;
  inherited;
end;

function TMarkdownHighlighter.EmbeddedHL(const AName: string): TTextHighlighter;
var
  I: Integer;
begin
  I := FEmbedded.IndexOf(AName);
  if I >= 0 then
    Result := TTextHighlighter(FEmbedded.Objects[I])
  else
    Result := nil;
end;

procedure TMarkdownHighlighter.AppendSpan(var ASpans: TTextSpanArray;
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

{ Walk ALine from AStartCol (0-based byte offset) and emit spans for inline
  markup: **bold**, __bold__, *italic*, _italic_, `code`,
  [label](url), ![alt](url). }
procedure TMarkdownHighlighter.AddInlineSpans(const ALine: string;
  AStartCol: Integer; var ASpans: TTextSpanArray; var ACount: Integer);
var
  Len, I, Start, End_: Integer;
  Ch: Char;
begin
  Len := Length(ALine);
  I   := AStartCol + 1;  { 1-based }
  while I <= Len do
  begin
    Ch := ALine[I];

    { Image: ![alt](url) }
    if (Ch = '!') and (I + 1 <= Len) and (ALine[I + 1] = '[') then
    begin
      Start := I;
      Inc(I, 2);  { skip ![ }
      while (I <= Len) and (ALine[I] <> ']') do Inc(I);
      End_ := I;  { position of ] }
      AppendSpan(ASpans, ACount, Start - 1, End_ - Start + 1, clBrightBlue);
      if (I + 1 <= Len) and (ALine[I + 1] = '(') then
      begin
        Inc(I);  { skip ] }
        Start := I;
        while (I <= Len) and (ALine[I] <> ')') do Inc(I);
        AppendSpan(ASpans, ACount, Start - 1, I - Start + 1, clBrightBlack);
      end;
      if I <= Len then Inc(I);
      Continue;
    end;

    { Link: [label](url) }
    if Ch = '[' then
    begin
      Start := I;
      Inc(I);
      while (I <= Len) and (ALine[I] <> ']') do Inc(I);
      End_ := I;
      AppendSpan(ASpans, ACount, Start - 1, End_ - Start + 1, clBrightBlue);
      if (I + 1 <= Len) and (ALine[I + 1] = '(') then
      begin
        Inc(I);  { skip ] }
        Start := I;
        while (I <= Len) and (ALine[I] <> ')') do Inc(I);
        AppendSpan(ASpans, ACount, Start - 1, I - Start + 1, clBrightBlack);
      end;
      if I <= Len then Inc(I);
      Continue;
    end;

    { Inline code: `...` }
    if Ch = '`' then
    begin
      Start := I;
      Inc(I);
      { handle `` fences }
      if (I <= Len) and (ALine[I] = '`') then Inc(I);
      while (I <= Len) and (ALine[I] <> '`') do Inc(I);
      if (I + 1 <= Len) and (ALine[I + 1] = '`') then Inc(I);
      AppendSpan(ASpans, ACount, Start - 1, I - Start + 1, clCyan);
      Inc(I);
      Continue;
    end;

    { Bold: **…** }
    if (Ch = '*') and (I + 1 <= Len) and (ALine[I + 1] = '*') then
    begin
      Start := I;
      Inc(I, 2);
      while (I + 1 <= Len) and not ((ALine[I] = '*') and (ALine[I + 1] = '*')) do
        Inc(I);
      if I + 1 <= Len then Inc(I, 2);
      AppendSpan(ASpans, ACount, Start - 1, I - Start, clBrightWhite);
      Continue;
    end;

    { Bold: __…__ }
    if (Ch = '_') and (I + 1 <= Len) and (ALine[I + 1] = '_') then
    begin
      Start := I;
      Inc(I, 2);
      while (I + 1 <= Len) and not ((ALine[I] = '_') and (ALine[I + 1] = '_')) do
        Inc(I);
      if I + 1 <= Len then Inc(I, 2);
      AppendSpan(ASpans, ACount, Start - 1, I - Start, clBrightWhite);
      Continue;
    end;

    { Italic: *…* (single) }
    if (Ch = '*') and ((I = 1) or (ALine[I - 1] <> '*')) then
    begin
      Start := I;
      Inc(I);
      while (I <= Len) and (ALine[I] <> '*') do Inc(I);
      if I <= Len then Inc(I);
      AppendSpan(ASpans, ACount, Start - 1, I - Start, clDefault, True);
      Continue;
    end;

    { Italic: _…_ (single) }
    if (Ch = '_') and ((I = 1) or (ALine[I - 1] <> '_')) then
    begin
      Start := I;
      Inc(I);
      while (I <= Len) and (ALine[I] <> '_') do Inc(I);
      if I <= Len then Inc(I);
      AppendSpan(ASpans, ACount, Start - 1, I - Start, clDefault, True);
      Continue;
    end;

    Inc(I);
  end;
end;

procedure TMarkdownHighlighter.Prepare(ALines: TStrings);
var
  I, J:      Integer;
  S, Tag:    string;
  InFence:   Boolean;
  FenceChar: Char;
  FenceLang: string;
  Needed:    TStringList;
  HL:        TTextHighlighter;
begin
  FCount := ALines.Count;
  SetLength(FInFence,   FCount);
  SetLength(FFenceLang, FCount);
  InFence   := False;
  FenceChar := '`';
  FenceLang := '';

  if FEmbedded = nil then
  begin
    FEmbedded := TStringList.Create;
    FEmbedded.OwnsObjects := True;
    FEmbedded.Sorted      := True;
  end;

  Needed := TStringList.Create;
  try
    Needed.Sorted := True;
    Needed.Duplicates := dupIgnore;

    for I := 0 to ALines.Count - 1 do
    begin
      S := ALines[I];
      FInFence[I]   := InFence;
      FFenceLang[I] := '';
      if InFence then
        FFenceLang[I] := FenceLang;

      { Detect fence open/close: ``` or ~~~ at line start }
      if (Length(S) >= 3) and
         ((S[1] = '`') or (S[1] = '~')) and
         (S[2] = S[1]) and (S[3] = S[1]) then
      begin
        if not InFence then
        begin
          FenceChar   := S[1];
          InFence     := True;
          FInFence[I] := False;
          FFenceLang[I] := '';
          Tag := LowerCase(Trim(Copy(S, 4, Length(S) - 3)));
          if (Tag = 'pascal') or (Tag = 'pas') or (Tag = 'objectpascal') then
            FenceLang := 'Pascal'
          else
            FenceLang := '';
          if FenceLang <> '' then
            Needed.Add(FenceLang);
        end
        else if S[1] = FenceChar then
        begin
          InFence   := False;
          FenceLang := '';
        end;
      end;
    end;

    { Sync FEmbedded: remove no-longer-needed, add newly needed }
    for I := FEmbedded.Count - 1 downto 0 do
      if Needed.IndexOf(FEmbedded[I]) < 0 then
        FEmbedded.Delete(I);
    for I := 0 to Needed.Count - 1 do
      if FEmbedded.IndexOf(Needed[I]) < 0 then
      begin
        HL := FindHighlighterByName(Needed[I]);
        if Assigned(HL) then
          FEmbedded.AddObject(Needed[I], HL);
      end;
  finally
    Needed.Free;
  end;

  for J := 0 to FEmbedded.Count - 1 do
    TTextHighlighter(FEmbedded.Objects[J]).Prepare(ALines);
end;

function TMarkdownHighlighter.Name: string;
begin
  Result := 'Markdown';
end;

procedure TMarkdownHighlighter.GetSpans(ARow: Integer; const ALine: string;
  out ASpans: TTextSpanArray);
var
  Len, Count, Level, I: Integer;
  Ch: Char;
  HL: TTextHighlighter;
begin
  ASpans := nil;
  Count  := 0;
  Len    := Length(ALine);
  if Len = 0 then Exit;

  SetLength(ASpans, 16);

  { Inside a fenced code block }
  if (ARow >= 0) and (ARow < FCount) and FInFence[ARow] then
  begin
    if FFenceLang[ARow] <> '' then
    begin
      HL := EmbeddedHL(FFenceLang[ARow]);
      if Assigned(HL) then
      begin
        HL.GetSpans(ARow, ALine, ASpans);
        Exit;
      end;
    end;
    AppendSpan(ASpans, Count, 0, Len, clBrightBlack);
    SetLength(ASpans, Count);
    Exit;
  end;

  { Fence line (``` or ~~~) }
  if (Len >= 3) and ((ALine[1] = '`') or (ALine[1] = '~')) and
     (ALine[2] = ALine[1]) and (ALine[3] = ALine[1]) then
  begin
    AppendSpan(ASpans, Count, 0, Len, clBrightBlack);
    SetLength(ASpans, Count);
    Exit;
  end;

  { Indented code block: 4+ leading spaces or a tab }
  if (Len >= 4) and (ALine[1] = ' ') and (ALine[2] = ' ') and
     (ALine[3] = ' ') and (ALine[4] = ' ') then
  begin
    AppendSpan(ASpans, Count, 0, Len, clBrightBlack);
    SetLength(ASpans, Count);
    Exit;
  end;
  if ALine[1] = #9 then
  begin
    AppendSpan(ASpans, Count, 0, Len, clBrightBlack);
    SetLength(ASpans, Count);
    Exit;
  end;

  { HTML comment }
  if (Len >= 4) and (ALine[1] = '<') and (ALine[2] = '!') and
     (ALine[3] = '-') and (ALine[4] = '-') then
  begin
    AppendSpan(ASpans, Count, 0, Len, clBrightBlack);
    SetLength(ASpans, Count);
    Exit;
  end;

  { ATX heading: # H1 ## H2 … ###### H6 }
  if ALine[1] = '#' then
  begin
    Level := 0;
    while (Level < Len) and (ALine[Level + 1] = '#') do Inc(Level);
    { must be followed by space or end of line }
    if (Level = Len) or (ALine[Level + 1] = ' ') then
    begin
      case Level of
        1:    AppendSpan(ASpans, Count, 0, Len, clBrightCyan);
        2:    AppendSpan(ASpans, Count, 0, Len, clBrightYellow);
        else  AppendSpan(ASpans, Count, 0, Len, clBrightGreen);
      end;
      SetLength(ASpans, Count);
      Exit;
    end;
  end;

  { Setext headings: === (H1) or --- (H2) — all same char, length >= 2 }
  if Len >= 2 then
  begin
    Ch := ALine[1];
    if Ch in ['=', '-'] then
    begin
      I := 1;
      while (I <= Len) and (ALine[I] = Ch) do Inc(I);
      if I > Len then
      begin
        if Ch = '=' then
          AppendSpan(ASpans, Count, 0, Len, clBrightCyan)
        else
          AppendSpan(ASpans, Count, 0, Len, clBrightYellow);
        SetLength(ASpans, Count);
        Exit;
      end;
    end;
  end;

  { Horizontal rule: ***, ---, ___ (3+ of same char, optionally spaced) }
  if Len >= 3 then
  begin
    Ch := ALine[1];
    if Ch in ['*', '-', '_'] then
    begin
      I := 1;
      while (I <= Len) and ((ALine[I] = Ch) or (ALine[I] = ' ')) do Inc(I);
      if I > Len then
      begin
        AppendSpan(ASpans, Count, 0, Len, clBrightBlack);
        SetLength(ASpans, Count);
        Exit;
      end;
    end;
  end;

  { Block quote: > … }
  if ALine[1] = '>' then
  begin
    AppendSpan(ASpans, Count, 0, 1, clYellow);
    AddInlineSpans(ALine, 1, ASpans, Count);
    SetLength(ASpans, Count);
    Exit;
  end;

  { Unordered list: - item, * item, + item }
  if (Len >= 2) and (ALine[1] in ['-', '*', '+']) and (ALine[2] = ' ') then
  begin
    AppendSpan(ASpans, Count, 0, 1, clBrightYellow);
    AddInlineSpans(ALine, 2, ASpans, Count);
    SetLength(ASpans, Count);
    Exit;
  end;

  { Ordered list: 1. item }
  if (Len >= 3) and (ALine[1] in ['0'..'9']) then
  begin
    I := 1;
    while (I <= Len) and (ALine[I] in ['0'..'9']) do Inc(I);
    if (I <= Len) and (ALine[I] = '.') and (I + 1 <= Len) and (ALine[I + 1] = ' ') then
    begin
      AppendSpan(ASpans, Count, 0, I, clBrightYellow);
      AddInlineSpans(ALine, I, ASpans, Count);
      SetLength(ASpans, Count);
      Exit;
    end;
  end;

  { Plain paragraph — just inline markup }
  AddInlineSpans(ALine, 0, ASpans, Count);
  SetLength(ASpans, Count);
end;

initialization
  RegisterHighlighter(TMarkdownHighlighter, '.md;.markdown;.mkd;.mkdn;.mdwn');

end.
