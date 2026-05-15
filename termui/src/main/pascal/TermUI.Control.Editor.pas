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
  Classes, SysUtils, TermUI.Terminal, TermUI.Control, TermUI.StringUtils;

type
  { A single styled region within one line.
    Col is 0-based; Len is in bytes.  FG/BG = clDefault means inherit. }
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
    { Called once before painting begins, with all lines. }
    procedure Prepare(ALines: TStrings); virtual;
    { Return color spans for line ARow (0-based). ALine is the plain text. }
    procedure GetSpans(ARow: Integer; const ALine: string;
      out ASpans: TTextSpanArray); virtual;
  end;

  TTextEditor = class(TControl)
  private
    FLines:       TStringList;
    FReadOnly:    Boolean;
    FWordWrap:    Boolean;
    FCurRow:      Integer;   { 1-based line number }
    FCurCol:      Integer;   { 1-based column in current line }
    FTopRow:      Integer;   { 0-based: lines scrolled off the top }
    FLeftCol:     Integer;   { 0-based: columns scrolled off the left }
    FHighlighter: TTextHighlighter;
    FOnChange:    TNotifyEvent;

    procedure LinesChanged(Sender: TObject);
    procedure ClampCursor;
    procedure EnsureVisible;
    function  CurrentLine: string;
    function  LineCount: Integer;
    procedure SetReadOnly(AValue: Boolean);
    procedure SetWordWrap(AValue: Boolean);
    procedure SetHighlighter(AValue: TTextHighlighter);

    { Editing primitives }
    procedure InsertChar(ACh: Char);
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

    procedure Clear;

    { Lines is owned by the editor.  Assign content via Lines.Text,
      Lines.Add, Lines.LoadFromFile, etc. }
    property Lines:       TStrings          read FLines;
    property ReadOnly:    Boolean           read FReadOnly    write SetReadOnly;
    property WordWrap:    Boolean           read FWordWrap    write SetWordWrap;
    { Not owned.  Set to nil to revert to plain rendering. }
    property Highlighter: TTextHighlighter  read FHighlighter write SetHighlighter;
    property CursorRow:   Integer           read FCurRow;
    property CursorCol:   Integer           read FCurCol;
    property OnChange:    TNotifyEvent      read FOnChange    write FOnChange;
  end;

implementation

{ ── TTextHighlighter ── }

procedure TTextHighlighter.Prepare(ALines: TStrings);
begin
end;

procedure TTextHighlighter.GetSpans(ARow: Integer; const ALine: string;
  out ASpans: TTextSpanArray);
begin
  ASpans := nil;
end;

{ ── TTextEditor ── }

constructor TTextEditor.Create;
begin
  inherited Create;
  FLines  := TStringList.Create;
  FLines.OnChange := @LinesChanged;
  FCurRow := 1;
  FCurCol := 1;
end;

destructor TTextEditor.Destroy;
begin
  FLines.Free;
  inherited;
end;

procedure TTextEditor.LinesChanged(Sender: TObject);
begin
  ClampCursor;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTextEditor.Clear;
begin
  FLines.Clear;  { triggers LinesChanged }
  FCurRow  := 1;
  FCurCol  := 1;
  FTopRow  := 0;
  FLeftCol := 0;
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
    Len := Length(FLines[FCurRow - 1])
  else
    Len := 0;
  if FCurCol < 1 then FCurCol := 1;
  if FCurCol > Len + 1 then FCurCol := Len + 1;
end;

procedure TTextEditor.EnsureVisible;
begin
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
end;

{ ── Editing primitives ── }

procedure TTextEditor.InsertChar(ACh: Char);
var S: string;
begin
  if FReadOnly then Exit;
  while FLines.Count < FCurRow do FLines.Add('');
  S := FLines[FCurRow - 1];
  Insert(ACh, S, FCurCol);
  FLines[FCurRow - 1] := S;
  Inc(FCurCol);
  EnsureVisible;
  { LinesChanged fires via OnChange }
end;

procedure TTextEditor.DeleteBack;
var S: string;
begin
  if FReadOnly then Exit;
  if (FCurCol > 1) then
  begin
    S := FLines[FCurRow - 1];
    DeleteNeutral(S, FCurCol - 2, 1);
    FLines[FCurRow - 1] := S;
    Dec(FCurCol);
    EnsureVisible;
  end
  else if FCurRow > 1 then
  begin
    { Merge with previous line }
    FCurCol := Length(FLines[FCurRow - 2]) + 1;
    FLines[FCurRow - 2] := FLines[FCurRow - 2] + FLines[FCurRow - 1];
    FLines.Delete(FCurRow - 1);
    Dec(FCurRow);
    EnsureVisible;
  end;
end;

procedure TTextEditor.DeleteForward;
var S: string;
begin
  if FReadOnly then Exit;
  if FLines.Count = 0 then Exit;
  S := FLines[FCurRow - 1];
  if FCurCol <= Length(S) then
  begin
    DeleteNeutral(S, FCurCol - 1, 1);
    FLines[FCurRow - 1] := S;
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
  Rest := Copy(S, FCurCol, MaxInt);
  FLines[FCurRow - 1] := Copy(S, 1, FCurCol - 1);
  FLines.Insert(FCurRow, Rest);
  Inc(FCurRow);
  FCurCol := 1;
  EnsureVisible;
end;

procedure TTextEditor.DeleteToEOL;
var S: string;
begin
  if FReadOnly then Exit;
  if FLines.Count = 0 then Exit;
  S := FLines[FCurRow - 1];
  FLines[FCurRow - 1] := Copy(S, 1, FCurCol - 1);
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
      I := FCurCol - 1;
      while (I > 1) and (S[I - 1] = ' ') do Dec(I);
      while (I > 1) and (S[I - 1] <> ' ') do Dec(I);
      FCurCol := I;
    end
    else
      Dec(FCurCol);
  end
  else if FCurRow > 1 then
  begin
    Dec(FCurRow);
    FCurCol := Length(FLines[FCurRow - 1]) + 1;
  end;
  EnsureVisible;
  Invalidate;
end;

procedure TTextEditor.MoveCursorRight(AWord: Boolean);
var S: string; I, Len: Integer;
begin
  S   := CurrentLine;
  Len := Length(S);
  if FCurCol <= Len then
  begin
    if AWord then
    begin
      I := FCurCol;
      while (I <= Len) and (S[I] <> ' ') do Inc(I);
      while (I <= Len) and (S[I] = ' ')  do Inc(I);
      FCurCol := I;
    end
    else
      Inc(FCurCol);
  end
  else if FCurRow < LineCount then
  begin
    Inc(FCurRow);
    FCurCol := 1;
  end;
  EnsureVisible;
  Invalidate;
end;

procedure TTextEditor.MoveCursorUp;
var Len: Integer;
begin
  if FCurRow > 1 then
  begin
    Dec(FCurRow);
    Len := Length(FLines[FCurRow - 1]);
    if FCurCol > Len + 1 then FCurCol := Len + 1;
  end;
  EnsureVisible;
  Invalidate;
end;

procedure TTextEditor.MoveCursorDown;
var Len: Integer;
begin
  if FCurRow < LineCount then
  begin
    Inc(FCurRow);
    Len := Length(FLines[FCurRow - 1]);
    if FCurCol > Len + 1 then FCurCol := Len + 1;
  end;
  EnsureVisible;
  Invalidate;
end;

procedure TTextEditor.MoveHome;
begin
  FCurCol := 1;
  EnsureVisible;
  Invalidate;
end;

procedure TTextEditor.MoveEnd;
begin
  FCurCol := Length(CurrentLine) + 1;
  EnsureVisible;
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
  FCurCol := Length(CurrentLine) + 1;
  EnsureVisible;
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
    EnsureVisible;
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
    EnsureVisible;
  end;
  Invalidate;
end;

{ ── Paint ── }

procedure TTextEditor.PaintLine(ADisplayRow: Integer; const ALine: string;
  const ASpans: TTextSpanArray);
var
  Visible:   string;
  Col, SpanIdx, SpanEnd, PadCount, I: Integer;
  CurrentFG: TColor;
  CurrentBG: TColor;
  CurrentUL: Boolean;
  Ch:        Char;
begin
  Visible := CopyNeutral(ALine, FLeftCol, Width);

  GotoLocal(1, ADisplayRow);
  CurrentFG := clDefault;
  CurrentBG := clDefault;
  CurrentUL := False;
  Term.ResetColors;

  for Col := 0 to UTF8VisualLen(Visible) - 1 do
  begin
    { Find which span covers this column (absolute column = FLeftCol + Col) }
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
    Ch := Visible[Col + 1];
    Term.WriteStr(Ch);
  end;

  { Pad to end of line to clear stale content }
  Term.ResetColors;
  PadCount := Width - UTF8VisualLen(Visible);
  for I := 1 to PadCount do
    Term.WriteStr(' ');
end;

procedure TTextEditor.DoPaint;
var
  Row, LineIdx: Integer;
  S:            string;
  Spans:        TTextSpanArray;
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

    PaintLine(Row, S, Spans);
  end;

  { Position terminal cursor }
  if not FReadOnly then
  begin
    Term.ShowCursor;
    GotoLocal(FCurCol - FLeftCol, FCurRow - FTopRow);
  end
  else
    Term.HideCursor;

  inherited DoPaint;
end;

procedure TTextEditor.DoBoundsChanged;
begin
  EnsureVisible;
end;

function TTextEditor.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  Result := True;
  if FReadOnly then
  begin
    case Key.Code of
      kcUp:       ScrollUp;
      kcDown:     ScrollDown;
      kcPageUp:   PageUp;
      kcPageDown: PageDown;
      kcCtrlHome: MoveDocStart;
      kcCtrlEnd:  MoveDocEnd;
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
      kcChar:
        if Key.Ch >= ' ' then InsertChar(Key.Ch);
    else
      Result := False;
    end;
  end;
end;

end.
