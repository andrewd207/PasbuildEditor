{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Control.Editor;

{$mode objfpc}{$H+}

{ Multi-line text editor control.

  Plain text lives in Lines (TStrings).  Visual presentation is handled
  separately by a pluggable TTextHighlighter that maps each line to a list
  of TTextSpan color/style regions — the editor never parses markup itself.

  Subclass TTextHighlighter to add syntax highlighting, AsciiDoc coloring,
  XML highlighting, etc.  The highlighter is called during paint only and
  has no influence on the stored text.

  ReadOnly = True:  cursor is hidden; Up/Down/PgUp/PgDn scroll the view.
  ReadOnly = False: full editing with cursor.

  WordWrap:  property is stored and will influence layout in a future pass;
             horizontal scrolling is suppressed when True. }

interface

uses
  Classes, SysUtils, Math, TermUI.Terminal, TermUI.Control, TermUI.StringUtils;

type
  { A single styled region within one line.
    Col and Len are in UTF-8 codepoints (chars), 0-based.  FG/BG = clDefault means inherit. }
  TTextSpan = record
    Col:       Integer;
    Len:       Integer;
    FG:        TColor;
    BG:        TColor;
    Underline: Boolean;
  end;

  TTextSpanArray = array of TTextSpan;

  { Pluggable highlighter.  Override GetSpans to return styled regions for
    one line.  Override Prepare if you need a full-document pre-pass (e.g.
    to resolve multi-line constructs) before individual lines are painted. }
  TTextHighlighter = class
  public
    constructor Create; virtual;
    { Called once before painting begins, with all lines. }
    procedure Prepare(ALines: TStrings); virtual;
    { Return color spans for line ARow (0-based). ALine is the plain text. }
    procedure GetSpans(ARow: Integer; const ALine: string;
      out ASpans: TTextSpanArray); virtual;
    { Human-readable name shown in highlighter-selection UI. }
    function Name: string; virtual;
  end;

  TTextHighlighterClass = class of TTextHighlighter;

type
  TTabMode = (
    tmSpaces,   { insert TabWidth spaces }
    tmChar      { insert a literal #9 }
  );

  TTextEditor = class(TControl)
  private
    FLines:                  TStringList;
    FReadOnly:               Boolean;
    FWordWrap:               Boolean;
    FCaptureTabs:            Boolean;
    FTabMode:                TTabMode;
    FTabWidth:               Integer;
    FHighlightTrailingSpaces: Boolean;
    FUpdating:               Integer;   { >0 suppresses OnChange and Invalidate from LinesChanged }
    FCurRow:       Integer;   { 1-based line number }
    FCurCol:       Integer;   { 1-based column in current line }
    FTopRow:       Integer;   { 0-based: lines scrolled off the top }
    FLeftCol:      Integer;   { 0-based: columns scrolled off the left }
    FHighlighter:  TTextHighlighter;
    FOnChange:     TNotifyEvent;

    procedure LinesChanged(Sender: TObject);
    procedure ClampCursor;
    function  EnsureVisStr: Boolean;  { returns True if no scroll occurred }
    function  CurrentLine: string;
    function  LineCount: Integer;
    procedure SetReadOnly(AValue: Boolean);
    procedure SetWordWrap(AValue: Boolean);
    procedure SetHighlighter(AValue: TTextHighlighter);
    function  GetLines: TStrings;
    function  CursorScreenRow: Integer;

    { Editing primitives }
    procedure InsertChar(ACh: Char);
    procedure InsertTab;
    procedure DeleteBack;
    procedure DeleteForward;
    procedure InsertNewLine;
    procedure DeleteToEOL;

    { Cursor movement }
    procedure MoveCursorLeft(AWord: Boolean = False);
    procedure MoveCursorRight(AWord: Boolean = False);
    procedure MoveCursorUp;
    procedure MoveCursorDown;
    procedure MoveHome;
    procedure MoveEnd;
    procedure MoveDocStart;
    procedure MoveDocEnd;
    procedure ScrollUp;
    procedure ScrollDown;
    procedure PageUp;
    procedure PageDown;

    procedure PaintLine(ADisplayRow: Integer; const ALine: string;
      const ASpans: TTextSpanArray);
  protected
    procedure DoPaint; override;
    procedure DoBoundsChanged; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
  public
    constructor Create; override;
    destructor  Destroy; override;

    { Suppress OnChange and visual updates during bulk edits.
      Call BeginUpdate / EndUpdate in matched pairs. }
    procedure BeginUpdate;
    procedure EndUpdate;

    procedure Clear;

    { Lines is owned by the editor.  Assign content via Lines.Text,
      Lines.Add, Lines.LoadFromFile, etc. }
    property Lines:       TStrings          read GetLines;
    property ReadOnly:    Boolean           read FReadOnly    write SetReadOnly;
    property WordWrap:    Boolean           read FWordWrap    write SetWordWrap;
    { When True the Tab key is captured and handled by TabMode / TabWidth
      instead of being passed up to the parent form for focus cycling. }
    property CaptureTabs: Boolean           read FCaptureTabs write FCaptureTabs;
    { tmSpaces (default): Tab inserts TabWidth spaces.
      tmChar: Tab inserts a literal #9 character. }
    property TabMode:     TTabMode          read FTabMode     write FTabMode;
    { Number of spaces inserted when TabMode = tmSpaces.  Default 4. }
    property TabWidth:    Integer           read FTabWidth    write FTabWidth;
    { When True, trailing spaces on each line are shown with a red background. }
    property HighlightTrailingSpaces: Boolean read FHighlightTrailingSpaces
                                              write FHighlightTrailingSpaces;
    { Not owned.  Set to nil to revert to plain rendering. }
    property Highlighter: TTextHighlighter  read FHighlighter write SetHighlighter;
    { Scroll the view so the last line is visible. No-op in edit mode
      (use MoveDocEnd instead). }
    procedure ScrollToBottom;

    property CursorRow:   Integer           read FCurRow;
    property CursorCol:   Integer           read FCurCol;
    property OnChange:    TNotifyEvent      read FOnChange    write FOnChange;
  end;

{ Register a highlighter class for one or more file extensions.
  AExtensions: semicolon-separated list, e.g. '.adoc;.asciidoc'.
  Call this in the initialization section of the highlighter's unit. }
procedure RegisterHighlighter(AClass: TTextHighlighterClass; const AExtensions: string);

{ Return a new instance of the highlighter registered for AExt (e.g. '.adoc'),
  or nil if none is registered.  Caller owns the returned object. }
function FindHighlighterForExt(const AExt: string): TTextHighlighter;

{ Return a new instance of the highlighter whose Name matches AName (case-
  insensitive), or nil if none matches.  Caller owns the returned object. }
function FindHighlighterByName(const AName: string): TTextHighlighter;

{ Fill ANames with the Name of each unique registered highlighter class, in
  registration order.  Duplicate class entries (different extensions) are
  deduplicated.  Caller passes a TStringList to receive the results. }
procedure GetHighlighterNames(ANames: TStrings);

implementation

{ ── TTextHighlighter ── }

constructor TTextHighlighter.Create;
begin
  inherited Create;
end;

procedure TTextHighlighter.Prepare(ALines: TStrings);
begin
end;

procedure TTextHighlighter.GetSpans(ARow: Integer; const ALine: string;
  out ASpans: TTextSpanArray);
begin
  ASpans := nil;
end;

function TTextHighlighter.Name: string;
begin
  Result := 'Plain Text';
end;

{ ── TTextEditor ── }

constructor TTextEditor.Create;
begin
  inherited Create;
  FLines       := TStringList.Create;
  FLines.OnChange := @LinesChanged;
  FCurRow      := 1;
  FCurCol      := 1;
  FCaptureTabs             := True;
  FTabMode                 := tmSpaces;
  FTabWidth                := 4;
  FHighlightTrailingSpaces := True;
end;

destructor TTextEditor.Destroy;
begin
  FLines.Free;
  inherited;
end;

procedure TTextEditor.LinesChanged(Sender: TObject);
begin
  ClampCursor;
  if FUpdating > 0 then Exit;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTextEditor.ScrollToBottom;
var MaxTop: Integer;
begin
  if Height <= 0 then Exit;
  MaxTop := LineCount - Height;
  if MaxTop < 0 then MaxTop := 0;
  if FTopRow <> MaxTop then
  begin
    FTopRow := MaxTop;
    Invalidate;
  end;
end;

procedure TTextEditor.BeginUpdate;
begin
  Inc(FUpdating);
end;

procedure TTextEditor.EndUpdate;
begin
  if FUpdating > 0 then Dec(FUpdating);
  Invalidate;
end;

procedure TTextEditor.Clear;
begin
  Inc(FUpdating);
  try
    FLines.Clear;
  finally
    Dec(FUpdating);
  end;
  FCurRow  := 1;
  FCurCol  := 1;
  FTopRow  := 0;
  FLeftCol := 0;
  Invalidate;
end;

procedure TTextEditor.SetReadOnly(AValue: Boolean);
begin
  if FReadOnly = AValue then Exit;
  FReadOnly := AValue;
  Invalidate;
end;

procedure TTextEditor.SetWordWrap(AValue: Boolean);
begin
  if FWordWrap = AValue then Exit;
  FWordWrap := AValue;
  if FWordWrap then FLeftCol := 0;
  Invalidate;
end;

procedure TTextEditor.SetHighlighter(AValue: TTextHighlighter);
begin
  FHighlighter := AValue;
  Invalidate;
end;

function TTextEditor.GetLines: TStrings;
begin
  Result := FLines;
end;

function TTextEditor.LineCount: Integer;
begin
  Result := FLines.Count;
  if Result = 0 then Result := 1;
end;

function TTextEditor.CurrentLine: string;
begin
  if (FLines.Count = 0) or (FCurRow > FLines.Count) then
    Result := ''
  else
    Result := FLines[FCurRow - 1];
end;

procedure TTextEditor.ClampCursor;
var Len: Integer;
begin
  if FCurRow < 1 then FCurRow := 1;
  if FCurRow > LineCount then FCurRow := LineCount;
  if FLines.Count > 0 then
    Len := FLines[FCurRow - 1].Length
  else
    Len := 0;
  if FCurCol < 1 then FCurCol := 1;
  if FCurCol > Len + 1 then FCurCol := Len + 1;
end;

function TTextEditor.EnsureVisStr: Boolean;
var OldTop, OldLeft: Integer;
begin
  OldTop  := FTopRow;
  OldLeft := FLeftCol;
  { Vertical }
  if FCurRow - 1 < FTopRow then
    FTopRow := FCurRow - 1;
  if FCurRow - 1 >= FTopRow + Height then
    FTopRow := FCurRow - Height;
  { Horizontal (suppressed when wrapping) }
  if not FWordWrap then
  begin
    if FCurCol - 1 < FLeftCol then
      FLeftCol := FCurCol - 1;
    if FCurCol - 1 >= FLeftCol + Width then
      FLeftCol := FCurCol - Width;
  end;
  if FTopRow  < 0 then FTopRow  := 0;
  if FLeftCol < 0 then FLeftCol := 0;
  Result := (FTopRow = OldTop) and (FLeftCol = OldLeft);
end;

{ ── Editing primitives ── }

function TTextEditor.CursorScreenRow: Integer;
begin
  Result := Top + (FCurRow - FTopRow) - 1;
end;

procedure TTextEditor.InsertChar(ACh: Char);
var S: string;
begin
  if FReadOnly then Exit;
  while FLines.Count < FCurRow do FLines.Add('');
  S := FLines[FCurRow - 1];
  InsertNeutral(S, ACh, FCurCol - 1);   { 0-based: insert before cursor position }
  Inc(FCurCol);                          { advance cursor BEFORE FLines write }
  FLines[FCurRow - 1] := S;             { LinesChanged/ClampCursor sees correct FCurCol }
  if EnsureVisStr then
    Term.HintDirtyRow(CursorScreenRow);
end;

procedure TTextEditor.InsertTab;
var I: Integer;
begin
  if FReadOnly then Exit;
  if FTabMode = tmChar then
    InsertChar(#9)
  else
    for I := 1 to FTabWidth do InsertChar(' ');
end;

procedure TTextEditor.DeleteBack;
var S: string;
begin
  if FReadOnly then Exit;
  if (FCurCol > 1) then
  begin
    S := FLines[FCurRow - 1];
    S.Delete(FCurCol - 2, 1);
    Dec(FCurCol);              { BEFORE FLines write so ClampCursor sees correct col }
    FLines[FCurRow - 1] := S;
    if EnsureVisStr then
      Term.HintDirtyRow(CursorScreenRow);
  end
  else if FCurRow > 1 then
  begin
    { Merge with previous line }
    FCurCol := FLines[FCurRow - 2].Length + 1;
    Dec(FCurRow);              { BEFORE FLines changes so ClampCursor sees correct row }
    FLines[FCurRow - 1] := FLines[FCurRow - 1] + FLines[FCurRow];
    FLines.Delete(FCurRow);
    EnsureVisStr;
  end;
end;

procedure TTextEditor.DeleteForward;
var S: string;
begin
  if FReadOnly then Exit;
  if FLines.Count = 0 then Exit;
  S := FLines[FCurRow - 1];
  if FCurCol <= S.Length then
  begin
    S.Delete(FCurCol - 1, 1);
    FLines[FCurRow - 1] := S;
    if EnsureVisStr then
      Term.HintDirtyRow(CursorScreenRow);
  end
  else if FCurRow < FLines.Count then
  begin
    { Merge next line into current }
    FLines[FCurRow - 1] := FLines[FCurRow - 1] + FLines[FCurRow];
    FLines.Delete(FCurRow);
  end;
end;

procedure TTextEditor.InsertNewLine;
var S, Rest: string;
begin
  if FReadOnly then Exit;
  while FLines.Count < FCurRow do FLines.Add('');
  S    := FLines[FCurRow - 1];
  Rest := S.Copy(FCurCol - 1, MaxInt);
  FLines[FCurRow - 1] := S.Copy(0, FCurCol - 1);
  FLines.Insert(FCurRow, Rest);
  Inc(FCurRow);
  FCurCol := 1;
  EnsureVisStr;
end;

procedure TTextEditor.DeleteToEOL;
var S: string;
begin
  if FReadOnly then Exit;
  if FLines.Count = 0 then Exit;
  S := FLines[FCurRow - 1];
  FLines[FCurRow - 1] := S.Copy(0, FCurCol - 1);
  Term.HintDirtyRow(CursorScreenRow);  { no scroll possible on delete-to-EOL }
end;

{ ── Cursor movement ── }

procedure TTextEditor.MoveCursorLeft(AWord: Boolean);
var S: string; I: Integer;
begin
  if FCurCol > 1 then
  begin
    if AWord then
    begin
      S := CurrentLine;
      I := FCurCol - 1;  { 0-based char index }
      while (I > 0) and (S.Chars[I - 1] = ' ') do Dec(I);
      while (I > 0) and (S.Chars[I - 1] <> ' ') do Dec(I);
      FCurCol := I + 1;
    end
    else
      Dec(FCurCol);
  end
  else if FCurRow > 1 then
  begin
    Dec(FCurRow);
    FCurCol := FLines[FCurRow - 1].Length + 1;
  end;
  EnsureVisStr;
  Invalidate;
end;

procedure TTextEditor.MoveCursorRight(AWord: Boolean);
var S: string; I, Len: Integer;
begin
  S   := CurrentLine;
  Len := S.Length;
  if FCurCol <= Len then
  begin
    if AWord then
    begin
      I := FCurCol - 1;  { 0-based char index }
      while (I < Len) and (S.Chars[I] <> ' ') do Inc(I);
      while (I < Len) and (S.Chars[I] = ' ')  do Inc(I);
      FCurCol := I + 1;
    end
    else
      Inc(FCurCol);
  end
  else if FCurRow < LineCount then
  begin
    Inc(FCurRow);
    FCurCol := 1;
  end;
  EnsureVisStr;
  Invalidate;
end;

procedure TTextEditor.MoveCursorUp;
var Len: Integer;
begin
  if FCurRow > 1 then
  begin
    Dec(FCurRow);
    Len := FLines[FCurRow - 1].Length;
    if FCurCol > Len + 1 then FCurCol := Len + 1;
  end;
  EnsureVisStr;
  Invalidate;
end;

procedure TTextEditor.MoveCursorDown;
var Len: Integer;
begin
  if FCurRow < LineCount then
  begin
    Inc(FCurRow);
    Len := FLines[FCurRow - 1].Length;
    if FCurCol > Len + 1 then FCurCol := Len + 1;
  end;
  EnsureVisStr;
  Invalidate;
end;

procedure TTextEditor.MoveHome;
begin
  FCurCol := 1;
  EnsureVisStr;
  Invalidate;
end;

procedure TTextEditor.MoveEnd;
begin
  FCurCol := CurrentLine.Length + 1;
  EnsureVisStr;
  Invalidate;
end;

procedure TTextEditor.MoveDocStart;
begin
  FCurRow := 1; FCurCol := 1;
  FTopRow := 0; FLeftCol := 0;
  Invalidate;
end;

procedure TTextEditor.MoveDocEnd;
begin
  FCurRow := LineCount;
  FCurCol := CurrentLine.Length + 1;
  EnsureVisStr;
  Invalidate;
end;

procedure TTextEditor.ScrollUp;
begin
  if FTopRow > 0 then begin Dec(FTopRow); Invalidate; end;
end;

procedure TTextEditor.ScrollDown;
begin
  if FTopRow < LineCount - 1 then begin Inc(FTopRow); Invalidate; end;
end;

procedure TTextEditor.PageUp;
var Delta: Integer;
begin
  Delta := Height - 1;
  if FReadOnly then
  begin
    FTopRow := Max(0, FTopRow - Delta);
  end
  else
  begin
    FCurRow := Max(1, FCurRow - Delta);
    EnsureVisStr;
  end;
  Invalidate;
end;

procedure TTextEditor.PageDown;
var Delta: Integer;
begin
  Delta := Height - 1;
  if FReadOnly then
  begin
    FTopRow := Min(LineCount - 1, FTopRow + Delta);
  end
  else
  begin
    FCurRow := Min(LineCount, FCurRow + Delta);
    EnsureVisStr;
  end;
  Invalidate;
end;

{ ── Paint ── }

procedure TTextEditor.PaintLine(ADisplayRow: Integer; const ALine: string;
  const ASpans: TTextSpanArray);
var
  VisStr:    string;
  Col, SpanIdx, SpanEnd, PadCount, I: Integer;
  CurrentFG: TColor;
  CurrentBG: TColor;
  CurrentUL: Boolean;
begin
  VisStr := ALine.Copy(FLeftCol, Width);  { char-based slice of the visible window }

  GotoLocal(1, ADisplayRow);
  CurrentFG := clDefault;
  CurrentBG := clDefault;
  CurrentUL := False;
  Term.ResetColors;

  for Col := 0 to VisStr.Length - 1 do
  begin
    { Absolute char column in the full line = FLeftCol + Col }
    CurrentFG := clDefault;
    CurrentBG := clDefault;
    CurrentUL := False;
    for SpanIdx := 0 to High(ASpans) do
    begin
      SpanEnd := ASpans[SpanIdx].Col + ASpans[SpanIdx].Len;
      if (FLeftCol + Col >= ASpans[SpanIdx].Col) and
         (FLeftCol + Col < SpanEnd) then
      begin
        CurrentFG := ASpans[SpanIdx].FG;
        CurrentBG := ASpans[SpanIdx].BG;
        CurrentUL := ASpans[SpanIdx].Underline;
        Break;
      end;
    end;
    Term.SetFG(CurrentFG);
    Term.SetBG(CurrentBG);
    Term.SetUnderline(CurrentUL);
    Term.WriteStr(VisStr.Chars[Col]);  { full UTF-8 codepoint }
  end;

  { Pad to end of line to clear stale content }
  Term.ResetColors;
  PadCount := Width - VisStr.Length;
  for I := 1 to PadCount do
    Term.WriteStr(' ');
end;

procedure TTextEditor.DoPaint;
var
  Row, LineIdx:            Integer;
  S:                       string;
  Spans:                   TTextSpanArray;
  TrailStart, SLen, N, SpanIdx: Integer;
begin
  if Assigned(FHighlighter) then
    FHighlighter.Prepare(FLines);

  for Row := 1 to Height do
  begin
    LineIdx := FTopRow + Row - 1;
    if LineIdx < FLines.Count then
      S := FLines[LineIdx]
    else
      S := '';

    Spans := nil;
    if Assigned(FHighlighter) then
      FHighlighter.GetSpans(LineIdx, S, Spans);

    if FHighlightTrailingSpaces and (S <> '') then
    begin
      SLen       := S.Length;   { char count }
      TrailStart := SLen;
      while (TrailStart > 0) and (S.Chars[TrailStart - 1] = ' ') do Dec(TrailStart);
      { TrailStart is now the 0-based char index of the first trailing space
        (or SLen when there are no trailing spaces). }
      N := SLen - TrailStart;   { number of trailing space chars }
      { Show highlight only when cursor is on a different line, or cursor
        (1-based FCurCol) is before the trailing region (TrailStart is 0-based,
        so "cursor before" means FCurCol <= TrailStart). }
      if (N > 0) and ((LineIdx <> FCurRow - 1) or (FCurCol <= TrailStart)) then
      begin
        SpanIdx := System.Length(Spans);
        SetLength(Spans, SpanIdx + 1);
        Spans[SpanIdx].Col       := TrailStart;   { 0-based first trailing space char }
        Spans[SpanIdx].Len       := N;
        Spans[SpanIdx].FG        := clDefault;
        Spans[SpanIdx].BG        := clRed;
        Spans[SpanIdx].Underline := False;
      end;
    end;

    PaintLine(Row, S, Spans);
  end;

  { Position terminal cursor — use PlaceCursor so subsequent paint calls
    (hint bar, overlays) cannot silently move the cursor away. }
  if not FReadOnly then
  begin
    Term.ShowCursor;
    Term.PlaceCursor(Left + (FCurCol - FLeftCol) - 1,
                     Top  + (FCurRow - FTopRow)  - 1);
  end
  else
    Term.HideCursor;

  inherited DoPaint;
end;

procedure TTextEditor.DoBoundsChanged;
begin
  EnsureVisStr;
end;

function TTextEditor.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  Result := True;
  if FReadOnly then
  begin
    case Key.Code of
      kcUp:        ScrollUp;
      kcDown:      ScrollDown;
      kcLeft:      MoveCursorLeft;
      kcRight:     MoveCursorRight;
      kcHome:      MoveHome;
      kcEnd:       MoveEnd;
      kcCtrlLeft:  MoveCursorLeft(True);
      kcCtrlRight: MoveCursorRight(True);
      kcPageUp:    PageUp;
      kcPageDown:  PageDown;
      kcCtrlHome:  MoveDocStart;
      kcCtrlEnd:   MoveDocEnd;
    else
      Result := False;
    end;
  end
  else
  begin
    case Key.Code of
      kcLeft:      MoveCursorLeft;
      kcRight:     MoveCursorRight;
      kcUp:        MoveCursorUp;
      kcDown:      MoveCursorDown;
      kcHome:      MoveHome;
      kcEnd:       MoveEnd;
      kcCtrlLeft:  MoveCursorLeft(True);
      kcCtrlRight: MoveCursorRight(True);
      kcCtrlHome:  MoveDocStart;
      kcCtrlEnd:   MoveDocEnd;
      kcPageUp:    PageUp;
      kcPageDown:  PageDown;
      kcBackspace: DeleteBack;
      kcDelete:    DeleteForward;
      kcEnter:     InsertNewLine;
      kcCtrlK:     DeleteToEOL;
      kcTab:
        if FCaptureTabs then InsertTab
        else Result := False;
      kcChar:
        if Key.Ch >= ' ' then InsertChar(Key.Ch);
    else
      Result := False;
    end;
  end;
end;

{ ── Highlighter registry ── }

type
  THighlighterEntry = record
    Cls: TTextHighlighterClass;
    Ext: string;   { lower-case extension including dot, e.g. '.adoc' }
  end;

var
  GHighlighters: array of THighlighterEntry;

procedure RegisterHighlighter(AClass: TTextHighlighterClass; const AExtensions: string);
var
  Parts: TStringList;
  I, N:  Integer;
  E:     string;
begin
  Parts := TStringList.Create;
  try
    Parts.StrictDelimiter := True;
    Parts.Delimiter := ';';
    Parts.DelimitedText := AExtensions;
    for I := 0 to Parts.Count - 1 do
    begin
      E := LowerCase(Trim(Parts[I]));
      if E = '' then Continue;
      N := Length(GHighlighters);
      SetLength(GHighlighters, N + 1);
      GHighlighters[N].Cls := AClass;
      GHighlighters[N].Ext := E;
    end;
  finally
    Parts.Free;
  end;
end;

function FindHighlighterForExt(const AExt: string): TTextHighlighter;
var
  E: string;
  I: Integer;
begin
  Result := nil;
  E := LowerCase(Trim(AExt));
  for I := 0 to High(GHighlighters) do
    if GHighlighters[I].Ext = E then
    begin
      Result := GHighlighters[I].Cls.Create;
      Exit;
    end;
end;

function FindHighlighterByName(const AName: string): TTextHighlighter;
var
  I:    Integer;
  Inst: TTextHighlighter;
  N:    string;
begin
  Result := nil;
  N := LowerCase(Trim(AName));
  for I := 0 to High(GHighlighters) do
  begin
    Inst := GHighlighters[I].Cls.Create;
    if LowerCase(Inst.Name) = N then
    begin
      Result := Inst;
      Exit;
    end;
    Inst.Free;
  end;
end;

procedure GetHighlighterNames(ANames: TStrings);
var
  I, J:  Integer;
  Inst:  TTextHighlighter;
  N:     string;
  Found: Boolean;
begin
  ANames.Clear;
  for I := 0 to High(GHighlighters) do
  begin
    Inst := GHighlighters[I].Cls.Create;
    N    := Inst.Name;
    Inst.Free;
    Found := False;
    for J := 0 to ANames.Count - 1 do
      if ANames[J] = N then begin Found := True; Break; end;
    if not Found then
      ANames.Add(N);
  end;
end;

initialization
  SetLength(GHighlighters, 0);

end.
