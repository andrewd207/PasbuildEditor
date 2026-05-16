{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Control.Editor;

{$mode objfpc}{$H+}
{$modeswitch typehelpers}

{ Multi-line text editor control.

  Plain text lives in Lines (TStrings).  Visual presentation is handled
  separately by a pluggable TTextHighlighter that maps each line to a list
  of TTextSpan color/style regions — the editor never parses markup itself.

  Subclass TTextHighlighter to add syntax highlighting, AsciiDoc coloring,
  XML highlighting, etc.  The highlighter is called during paint only and
  has no influence on the stored text.

  ReadOnly = True:  cursor is hidden; Up/Down/PgUp/PgDn scroll the view.
  ReadOnly = False: full editing with cursor.

  WordWrap = True:  long lines are split into visual rows at the control
                    width boundary.  No hard newlines are inserted.
                    FTopRow, scroll, and cursor movement all operate in
                    visual-row space.  FCurRow/FCurCol always track the
                    logical (stored) position. }

interface

uses
  Classes, SysUtils, Math, TermUI.Terminal, TermUI.Control, TermUI.StringUtils,
  TermUI.Clipboard, TermUI.Observer, TermUI.ObservedStringList;

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

  { Selection anchor.  The selection spans from (AnchorRow, AnchorCol) to
    the current cursor (FCurRow, FCurCol).  Active=False means no selection. }
  TSelection = record
    Active:    Boolean;
    AnchorRow: Integer;   { 1-based }
    AnchorCol: Integer;   { 1-based }
  end;

  { Maps one visual (screen) row to a position in FLines when WordWrap=True.
    LineIdx is 0-based; StartChar is the 0-based char offset within that line
    where this visual row begins. }
  TWrapEntry = record
    LineIdx:   Integer;
    StartChar: Integer;
  end;

  TTextEditor = class(TControl, ITermUIObserver)
  private
    FLines:                  TObservedStringList;
    FReadOnly:               Boolean;
    FWordWrap:               Boolean;
    FCaptureTabs:            Boolean;
    FTabMode:                TTabMode;
    FTabWidth:               Integer;
    FHighlightTrailingSpaces: Boolean;
    FUpdating:               Integer;   { >0 suppresses OnChange and Invalidate from LinesChanged }
    FCurRow:       Integer;   { 1-based logical line number }
    FCurCol:       Integer;   { 1-based column in current logical line }
    FTopRow:       Integer;   { 0-based visual rows scrolled off the top }
    FLeftCol:      Integer;   { 0-based columns scrolled off the left (unused when WordWrap) }
    FHighlighter:  TTextHighlighter;
    FOnChange:     TNotifyEvent;
    FSelection:    TSelection;
    FWrapTable:    array of TWrapEntry;  { rebuilt when WordWrap=True and content/width changes }

    procedure LinesChanged(Sender: TObject);
    procedure ObservedChanged(ASender: TObject; ANotify: TObserverNotification);
    procedure ClampCursor;
    function  EnsureVisStr: Boolean;  { returns True if no scroll occurred }
    function  CurrentLine: string;
    function  LineCount: Integer;     { logical line count (always >= 1) }
    function  VisualLineCount: Integer; { visual row count (== LineCount when not WordWrap) }
    procedure BuildWrapTable;         { rebuild FWrapTable from FLines and Width }
    function  CursorVisualRow: Integer; { 0-based visual row of the current cursor }
    procedure SetReadOnly(AValue: Boolean);
    procedure SetWordWrap(AValue: Boolean);
    procedure SetHighlighter(AValue: TTextHighlighter);
    function  GetLines: TStrings;

    { Selection helpers }
    procedure SetAnchor;      { activate selection anchored at current cursor }
    procedure ClearSelection; { deactivate; cursor stays }
    function  HasSelection: Boolean;
    procedure GetSelRange(out SR, SC, ER, EC: Integer); { normalised start/end }
    function  GetSelectedText: string;
    procedure DeleteSelectionImpl; { delete selected text; moves cursor to start; caller must ClearSelection after }

    { Editing primitives }
    procedure InsertChar(ACh: TUTF8Char);
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

    { AOffset: 0-based char position within ALine where the visible region starts.
      In no-wrap mode this is FLeftCol; in wrap mode it is the segment's StartChar. }
    procedure PaintLine(ADisplayRow: Integer; const ALine: string;
      ALineIdx: Integer; const ASpans: TTextSpanArray; AOffset: Integer);
  protected
    procedure DoPaint; override;
    procedure DoBoundsChanged; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
    { Stores ARow→FCurRow, ACol→FCurCol then calls inherited. }
    procedure SetCursorPos(ARow, ACol: Integer); override;
    { Translates (FCurRow, FCurCol) + scroll offsets to 1-based terminal coords. }
    function  CursorToScreen(out AScreenCol, AScreenRow: Integer): Boolean; override;
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
    property OnChange:     TNotifyEvent      read FOnChange     write FOnChange;

    { 0-based terminal row/column of the text cursor, for popup anchoring. }
    function CursorScreenRow: Integer;
    function CursorScreenCol: Integer;

    { Replace chars [AFrom..ATo) (0-based codepoint positions within the current
      line) with AText. Cursor is placed immediately after the inserted text.
      Fires OnChange. }
    procedure ReplaceCurrentLineRange(AFrom, ATo: Integer; const AText: string);

    { Current selection state.  AnchorRow/Col mark the fixed end; the cursor
      is the moving end.  Active=False means no selection. }
    property Selection:   TSelection        read FSelection;

    { Insert AText at the current cursor position (replaces selection if active).
      Newlines in AText split the line as pressing Enter would. }
    procedure InsertText(const AText: string);

    { Copy the current selection to the system clipboard.
      Falls back to the current line when nothing is selected. }
    procedure CopyCurrentLine;
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
  FLines       := TObservedStringList.Create;
  FLines.AttachObserver(Self);
  FCurRow      := 1;
  FCurCol      := 1;
  FCaptureTabs             := True;
  FTabMode                 := tmSpaces;
  FTabWidth                := 4;
  FHighlightTrailingSpaces := True;
  ShowCursor := True;
end;

destructor TTextEditor.Destroy;
begin
  if Assigned(FLines) then
  begin
    FLines.DetachObserver(Self);
    FLines.Free;
  end;
  inherited;
end;

{ ── Wrap table ── }

procedure TTextEditor.BuildWrapTable;
var
  I, Pos, Len, N, W: Integer;
begin
  SetLength(FWrapTable, 0);
  N := 0;
  W := Width;
  if W <= 0 then W := 1;
  for I := 0 to FLines.Count - 1 do
  begin
    Len := FLines[I].Length;
    if Len = 0 then
    begin
      SetLength(FWrapTable, N + 1);
      FWrapTable[N].LineIdx   := I;
      FWrapTable[N].StartChar := 0;
      Inc(N);
    end
    else
    begin
      Pos := 0;
      while Pos < Len do
      begin
        SetLength(FWrapTable, N + 1);
        FWrapTable[N].LineIdx   := I;
        FWrapTable[N].StartChar := Pos;
        Inc(N);
        Inc(Pos, W);
      end;
    end;
  end;
  if N = 0 then
  begin
    SetLength(FWrapTable, 1);
    FWrapTable[0].LineIdx   := 0;
    FWrapTable[0].StartChar := 0;
  end;
end;

function TTextEditor.CursorVisualRow: Integer;
var I: Integer;
begin
  { Default fallback (also covers not-WordWrap) }
  Result := FCurRow - 1;
  if not FWordWrap then Exit;
  { Last wrap entry for this logical line where StartChar <= FCurCol-1 }
  for I := 0 to High(FWrapTable) do
    if (FWrapTable[I].LineIdx = FCurRow - 1) and
       (FWrapTable[I].StartChar <= FCurCol - 1) then
      Result := I;
end;

function TTextEditor.VisualLineCount: Integer;
begin
  if FWordWrap then
    Result := Length(FWrapTable)
  else
    Result := LineCount;
end;

{ ── Selection helpers ── }

procedure TTextEditor.SetAnchor;
begin
  FSelection.Active    := True;
  FSelection.AnchorRow := FCurRow;
  FSelection.AnchorCol := FCurCol;
end;

procedure TTextEditor.ClearSelection;
begin
  FSelection.Active := False;
end;

function TTextEditor.HasSelection: Boolean;
begin
  Result := FSelection.Active and
            ((FSelection.AnchorRow <> FCurRow) or (FSelection.AnchorCol <> FCurCol));
end;

procedure TTextEditor.GetSelRange(out SR, SC, ER, EC: Integer);
begin
  if (FSelection.AnchorRow < FCurRow) or
     ((FSelection.AnchorRow = FCurRow) and (FSelection.AnchorCol <= FCurCol)) then
  begin
    SR := FSelection.AnchorRow;  SC := FSelection.AnchorCol;
    ER := FCurRow;               EC := FCurCol;
  end
  else
  begin
    SR := FCurRow;               SC := FCurCol;
    ER := FSelection.AnchorRow;  EC := FSelection.AnchorCol;
  end;
end;

function TTextEditor.GetSelectedText: string;
var
  SR, SC, ER, EC, I: Integer;
begin
  Result := '';
  if not HasSelection then Exit;
  GetSelRange(SR, SC, ER, EC);
  if SR = ER then
  begin
    Result := FLines[SR - 1].Copy(SC - 1, EC - SC);
  end
  else
  begin
    Result := FLines[SR - 1].Copy(SC - 1, MaxInt);
    for I := SR + 1 to ER - 1 do
      Result := Result + LineEnding + FLines[I - 1];
    Result := Result + LineEnding + FLines[ER - 1].Copy(0, EC - 1);
  end;
end;

procedure TTextEditor.DeleteSelectionImpl;
var
  SR, SC, ER, EC, I: Integer;
begin
  if not HasSelection then Exit;
  GetSelRange(SR, SC, ER, EC);
  BeginUpdate;
  try
    if SR = ER then
    begin
      FLines[SR - 1] := FLines[SR - 1].Copy(0, SC - 1) +
                        FLines[SR - 1].Copy(EC - 1, MaxInt);
    end
    else
    begin
      FLines[SR - 1] := FLines[SR - 1].Copy(0, SC - 1) +
                        FLines[ER - 1].Copy(EC - 1, MaxInt);
      for I := 1 to ER - SR do
        FLines.Delete(SR);   { deletes 0-based index SR = row SR+1, repeated ER-SR times }
    end;
  finally
    EndUpdate;
  end;
  FCurRow := SR;
  FCurCol := SC;
  EnsureVisStr;
end;

procedure TTextEditor.LinesChanged(Sender: TObject);
begin
  if FWordWrap then BuildWrapTable;
  ClampCursor;
  if FUpdating > 0 then Exit;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
  SetCursorPos(FCurRow, FCurCol);
end;

procedure TTextEditor.ObservedChanged(ASender: TObject;
  ANotify: TObserverNotification);
begin
  case ANotify.Operation of
    ooFreeing:
      FLines := nil;
    ooBeginUpdate:
      { TStrings.BeginUpdate already raises FUpdating via the editor's own
        BeginUpdate wrapper — nothing extra needed here. } ;
    ooEndUpdate:
      { Mirror of the above: EndUpdate handles Invalidate/OnChange. } ;
  else
    { ooAdd, ooInsert, ooDelete, ooChange, ooClear — treat like OnChange }
    LinesChanged(ASender);
  end;
end;

procedure TTextEditor.ScrollToBottom;
var MaxTop: Integer;
begin
  if Height <= 0 then Exit;
  MaxTop := VisualLineCount - Height;
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
  if FWordWrap then BuildWrapTable;
  Invalidate;
end;

procedure TTextEditor.SetReadOnly(AValue: Boolean);
begin
  if FReadOnly = AValue then Exit;
  FReadOnly := AValue;
  ShowCursor := not FReadOnly;
  Invalidate;
end;

procedure TTextEditor.SetWordWrap(AValue: Boolean);
begin
  if FWordWrap = AValue then Exit;
  FWordWrap := AValue;
  if FWordWrap then
  begin
    FLeftCol := 0;
    BuildWrapTable;
  end;
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

procedure TTextEditor.SetCursorPos(ARow, ACol: Integer);
begin
  FCurRow := ARow;
  FCurCol := ACol;
  inherited SetCursorPos(ARow, ACol);
end;

function TTextEditor.CursorToScreen(out AScreenCol, AScreenRow: Integer): Boolean;
var VRow, VCol: Integer;
begin
  Result := False;
  if FWordWrap then
  begin
    VRow := CursorVisualRow;
    VCol := FCurCol - 1 - FWrapTable[VRow].StartChar;   { 0-based within visual row }
    AScreenCol := Left + VCol;                           { Left is 1-based; VCol=0 → col Left }
    AScreenRow := Top  + (VRow - FTopRow);
    Result := (VRow >= FTopRow) and (VRow < FTopRow + Height);
  end
  else
  begin
    AScreenCol := Left + (FCurCol - FLeftCol) - 1;      { FCurCol 1-based, FLeftCol 0-based }
    AScreenRow := Top  + (FCurRow - FTopRow)  - 1;
    Result := (FCurRow > FTopRow) and (FCurRow <= FTopRow + Height)
          and (FCurCol >= FLeftCol + 1) and (FCurCol <= FLeftCol + Width);
  end;
end;

procedure TTextEditor.ClampCursor;
var
  Len: Integer;
  Line: String;
begin
  if FCurRow < 1 then FCurRow := 1;
  if FCurRow > LineCount then FCurRow := LineCount;
  if FLines.Count > 0 then
  begin
    Line := FLines[FCurRow - 1];
    Len := Line.Length;
  end
  else
    Len := 0;
  if FCurCol < 1 then FCurCol := 1;
  if FCurCol > Len + 1 then FCurCol := Len + 1;
end;

function TTextEditor.EnsureVisStr: Boolean;
var OldTop, OldLeft, VRow: Integer;
begin
  OldTop  := FTopRow;
  OldLeft := FLeftCol;

  if FWordWrap then
  begin
    VRow := CursorVisualRow;
    if VRow < FTopRow then
      FTopRow := VRow;
    if VRow >= FTopRow + Height then
      FTopRow := VRow - Height + 1;
    FLeftCol := 0;
  end
  else
  begin
    { Vertical }
    if FCurRow - 1 < FTopRow then
      FTopRow := FCurRow - 1;
    if FCurRow - 1 >= FTopRow + Height then
      FTopRow := FCurRow - Height;
    { Horizontal }
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
  if FWordWrap then
    Result := Top + (CursorVisualRow - FTopRow)
  else
    Result := Top + (FCurRow - FTopRow) - 1;
end;

function TTextEditor.CursorScreenCol: Integer;
var VRow: Integer;
begin
  if FWordWrap then
  begin
    VRow   := CursorVisualRow;
    Result := Left + (FCurCol - 1 - FWrapTable[VRow].StartChar);
  end
  else
    Result := Left + (FCurCol - FLeftCol) - 1;
end;

procedure TTextEditor.ReplaceCurrentLineRange(AFrom, ATo: Integer; const AText: string);
var
  S: string;
begin
  if FReadOnly then Exit;
  while FLines.Count < FCurRow do FLines.Add('');
  S := FLines[FCurRow - 1];
  if AFrom < 0 then AFrom := 0;
  if ATo > S.Length then ATo := S.Length;
  FLines[FCurRow - 1] := S.Copy(0, AFrom) + AText + S.Copy(ATo, S.Length - ATo);
  FCurCol := AFrom + AText.Length + 1;  { 1-based }
  ClampCursor;
  EnsureVisStr;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
  SetCursorPos(FCurRow, FCurCol);
end;

procedure TTextEditor.InsertChar(ACh: TUTF8Char);
var S: rawbytestring;
begin
  if FReadOnly then Exit;
  if HasSelection then begin DeleteSelectionImpl; ClearSelection; end;
  while FLines.Count < FCurRow do FLines.Add('');
  S := FLines[FCurRow - 1];
  S.Chars[FCurCol - 1] := ACh;          { 0-based: insert before cursor position }
  Inc(FCurCol);                          { advance cursor BEFORE FLines write }
  FLines[FCurRow - 1] := S;             { LinesChanged/ClampCursor sees correct FCurCol }
  if EnsureVisStr and not FWordWrap then
    Term.HintDirtyRow(CursorScreenRow)
  else
    Invalidate;
end;

procedure TTextEditor.InsertTab;
var I: Integer;
begin
  if FReadOnly then Exit;
  if HasSelection then begin DeleteSelectionImpl; ClearSelection; end;
  if FTabMode = tmChar then
    InsertChar(#9)
  else
    for I := 1 to FTabWidth do InsertChar(' ');
end;

procedure TTextEditor.DeleteBack;
var S: string;
begin
  if FReadOnly then Exit;
  if HasSelection then begin DeleteSelectionImpl; ClearSelection; Invalidate; Exit; end;
  if (FCurCol > 1) then
  begin
    S := FLines[FCurRow - 1];
    S.Delete(FCurCol - 2, 1);
    Dec(FCurCol);              { BEFORE FLines write so ClampCursor sees correct col }
    FLines[FCurRow - 1] := S;
    if EnsureVisStr and not FWordWrap then
      Term.HintDirtyRow(CursorScreenRow)
    else
      Invalidate;
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
  if HasSelection then begin DeleteSelectionImpl; ClearSelection; Invalidate; Exit; end;
  if FLines.Count = 0 then Exit;
  S := FLines[FCurRow - 1];
  if FCurCol <= S.Length then
  begin
    S.Delete(FCurCol - 1, 1);
    FLines[FCurRow - 1] := S;
    if EnsureVisStr and not FWordWrap then
      Term.HintDirtyRow(CursorScreenRow)
    else
      Invalidate;
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
  if HasSelection then begin DeleteSelectionImpl; ClearSelection; end;
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
  if HasSelection then begin DeleteSelectionImpl; ClearSelection; Invalidate; Exit; end;
  if FLines.Count = 0 then Exit;
  S := FLines[FCurRow - 1];
  FLines[FCurRow - 1] := S.Copy(0, FCurCol - 1);
  if FWordWrap then Invalidate
  else Term.HintDirtyRow(CursorScreenRow);
end;

procedure TTextEditor.CopyCurrentLine;
begin
  if HasSelection then
    Clipboard.SetText(GetSelectedText)
  else if FLines.Count = 0 then
    Clipboard.SetText('')
  else
    Clipboard.SetText(FLines[FCurRow - 1]);
end;

procedure TTextEditor.InsertText(const AText: string);
var
  SL:     TStringList;
  Norm:   string;
  Prefix, Suffix: RawByteString;
  S:      RawByteString;
  I, N:   Integer;
begin
  if FReadOnly then Exit;
  if HasSelection then
  begin
    DeleteSelectionImpl;
    ClearSelection;
  end;
  if AText = '' then Exit;

  Norm := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
  Norm := StringReplace(Norm,  #13,    #10, [rfReplaceAll]);

  SL := TStringList.Create;
  try
    SL.Delimiter       := #10;
    SL.StrictDelimiter := True;
    SL.DelimitedText   := Norm;
    N := SL.Count;
    if N = 0 then Exit;

    BeginUpdate;
    try
      while FLines.Count < FCurRow do FLines.Add('');
      S      := RawByteString(FLines[FCurRow - 1]);
      Prefix := S.Copy(0, FCurCol - 1);
      Suffix := S.Copy(FCurCol - 1, MaxInt);

      if N = 1 then
      begin
        FLines[FCurRow - 1] := Prefix + RawByteString(SL[0]) + Suffix;
        Inc(FCurCol, RawByteString(SL[0]).Length);
      end
      else
      begin
        FLines[FCurRow - 1] := Prefix + RawByteString(SL[0]);
        for I := 1 to N - 2 do
          FLines.Insert(FCurRow - 1 + I, RawByteString(SL[I]));
        FLines.Insert(FCurRow - 1 + N - 1, RawByteString(SL[N - 1]) + Suffix);
        Inc(FCurRow, N - 1);
        FCurCol := RawByteString(SL[N - 1]).Length + 1;
      end;
    finally
      EndUpdate;
    end;
  finally
    SL.Free;
  end;

  EnsureVisStr;
  Invalidate;
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
  SetCursorPos(FCurRow, FCurCol);
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
  SetCursorPos(FCurRow, FCurCol);
end;

procedure TTextEditor.MoveCursorUp;
var
  V, VisCol, NewCol, Len: Integer;
begin
  if FWordWrap then
  begin
    V := CursorVisualRow;
    if V > 0 then
    begin
      VisCol := FCurCol - 1 - FWrapTable[V].StartChar;   { 0-based col within visual row }
      FCurRow := FWrapTable[V - 1].LineIdx + 1;
      NewCol  := FWrapTable[V - 1].StartChar + VisCol;
      Len     := FLines[FCurRow - 1].Length;
      if NewCol > Len then NewCol := Len;
      FCurCol := NewCol + 1;
      EnsureVisStr;
      Invalidate;
      SetCursorPos(FCurRow, FCurCol);
    end;
  end
  else
  begin
    if FCurRow > 1 then
    begin
      Dec(FCurRow);
      Len := FLines[FCurRow - 1].Length;
      if FCurCol > Len + 1 then FCurCol := Len + 1;
    end;
    EnsureVisStr;
    Invalidate;
    SetCursorPos(FCurRow, FCurCol);
  end;
end;

procedure TTextEditor.MoveCursorDown;
var
  V, VisCol, NewCol, Len: Integer;
begin
  if FWordWrap then
  begin
    V := CursorVisualRow;
    if V < Length(FWrapTable) - 1 then
    begin
      VisCol := FCurCol - 1 - FWrapTable[V].StartChar;
      FCurRow := FWrapTable[V + 1].LineIdx + 1;
      NewCol  := FWrapTable[V + 1].StartChar + VisCol;
      Len     := FLines[FCurRow - 1].Length;
      if NewCol > Len then NewCol := Len;
      FCurCol := NewCol + 1;
      EnsureVisStr;
      Invalidate;
      SetCursorPos(FCurRow, FCurCol);
    end;
  end
  else
  begin
    if FCurRow < LineCount then
    begin
      Inc(FCurRow);
      Len := FLines[FCurRow - 1].Length;
      if FCurCol > Len + 1 then FCurCol := Len + 1;
    end;
    EnsureVisStr;
    Invalidate;
    SetCursorPos(FCurRow, FCurCol);
  end;
end;

procedure TTextEditor.MoveHome;
begin
  FCurCol := 1;
  EnsureVisStr;
  Invalidate;
  SetCursorPos(FCurRow, FCurCol);
end;

procedure TTextEditor.MoveEnd;
begin
  FCurCol := CurrentLine.Length + 1;
  EnsureVisStr;
  Invalidate;
  SetCursorPos(FCurRow, FCurCol);
end;

procedure TTextEditor.MoveDocStart;
begin
  FCurRow := 1; FCurCol := 1;
  FTopRow := 0; FLeftCol := 0;
  Invalidate;
  SetCursorPos(FCurRow, FCurCol);
end;

procedure TTextEditor.MoveDocEnd;
begin
  FCurRow := LineCount;
  FCurCol := CurrentLine.Length + 1;
  EnsureVisStr;
  Invalidate;
  SetCursorPos(FCurRow, FCurCol);
end;

procedure TTextEditor.ScrollUp;
begin
  if FTopRow > 0 then begin Dec(FTopRow); Invalidate; end;
end;

procedure TTextEditor.ScrollDown;
begin
  if FTopRow < VisualLineCount - 1 then begin Inc(FTopRow); Invalidate; end;
end;

procedure TTextEditor.PageUp;
var Delta, V, NewV, VisCol, NewCol, Len: Integer;
begin
  Delta := Height - 1;
  if FReadOnly then
  begin
    FTopRow := Max(0, FTopRow - Delta);
  end
  else if FWordWrap then
  begin
    V    := CursorVisualRow;
    NewV := Max(0, V - Delta);
    VisCol  := FCurCol - 1 - FWrapTable[V].StartChar;
    FCurRow := FWrapTable[NewV].LineIdx + 1;
    NewCol  := FWrapTable[NewV].StartChar + VisCol;
    Len     := FLines[FCurRow - 1].Length;
    if NewCol > Len then NewCol := Len;
    FCurCol := NewCol + 1;
    EnsureVisStr;
  end
  else
  begin
    FCurRow := Max(1, FCurRow - Delta);
    EnsureVisStr;
  end;
  Invalidate;
end;

procedure TTextEditor.PageDown;
var Delta, V, NewV, VisCol, NewCol, Len: Integer;
begin
  Delta := Height - 1;
  if FReadOnly then
  begin
    FTopRow := Min(VisualLineCount - 1, FTopRow + Delta);
  end
  else if FWordWrap then
  begin
    V    := CursorVisualRow;
    NewV := Min(VisualLineCount - 1, V + Delta);
    VisCol  := FCurCol - 1 - FWrapTable[V].StartChar;
    FCurRow := FWrapTable[NewV].LineIdx + 1;
    NewCol  := FWrapTable[NewV].StartChar + VisCol;
    Len     := FLines[FCurRow - 1].Length;
    if NewCol > Len then NewCol := Len;
    FCurCol := NewCol + 1;
    EnsureVisStr;
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
  ALineIdx: Integer; const ASpans: TTextSpanArray; AOffset: Integer);
var
  VisStr:       string;
  Col, SpanIdx, SpanEnd, PadCount, I: Integer;
  CurrentFG:    TColor;
  CurrentBG:    TColor;
  CurrentUL:    Boolean;
  SR, SC, ER, EC: Integer;
  LineRow:      Integer;   { 1-based row of this line }
  SelActive:    Boolean;
  SelColStart:  Integer;   { 0-based, inclusive; -1 = no sel on this line }
  SelColEnd:    Integer;   { 0-based, exclusive }
  PadSelected:  Boolean;
begin
  VisStr := ALine.Copy(AOffset, Width);

  { Compute selection span for this line (0-based column range, exclusive end) }
  SelColStart := -1;
  SelColEnd   := -1;
  PadSelected := False;
  SelActive   := HasSelection;
  if SelActive then
  begin
    GetSelRange(SR, SC, ER, EC);
    LineRow := ALineIdx + 1;  { ALineIdx is 0-based }
    if (LineRow >= SR) and (LineRow <= ER) then
    begin
      if SR = ER then
      begin
        SelColStart := SC - 1;
        SelColEnd   := EC - 1;
      end
      else if LineRow = SR then
      begin
        SelColStart := SC - 1;
        SelColEnd   := ALine.Length;
        PadSelected := True;
      end
      else if LineRow = ER then
      begin
        SelColStart := 0;
        SelColEnd   := EC - 1;
      end
      else
      begin
        SelColStart := 0;
        SelColEnd   := ALine.Length;
        PadSelected := True;
      end;
    end;
  end;

  GotoLocal(1, ADisplayRow);
  CurrentFG := clDefault;
  CurrentBG := clDefault;
  CurrentUL := False;
  Term.ResetColors;

  for Col := 0 to VisStr.Length - 1 do
  begin
    CurrentFG := clDefault;
    CurrentBG := clDefault;
    CurrentUL := False;
    { Spans: last matching wins — selection spans appended after highlighter spans }
    for SpanIdx := 0 to High(ASpans) do
    begin
      SpanEnd := ASpans[SpanIdx].Col + ASpans[SpanIdx].Len;
      if (AOffset + Col >= ASpans[SpanIdx].Col) and
         (AOffset + Col < SpanEnd) then
      begin
        CurrentFG := ASpans[SpanIdx].FG;
        CurrentBG := ASpans[SpanIdx].BG;
        CurrentUL := ASpans[SpanIdx].Underline;
        { no Break — last matching span wins }
      end;
    end;
    { Selection overrides everything }
    if (SelColStart >= 0) and
       (AOffset + Col >= SelColStart) and
       (AOffset + Col < SelColEnd) then
    begin
      CurrentFG := clBlack;
      CurrentBG := clCyan;
      CurrentUL := False;
    end;
    Term.SetFG(CurrentFG);
    Term.SetBG(CurrentBG);
    Term.SetUnderline(CurrentUL);
    Term.WriteStr(VisStr.Chars[Col]);
  end;

  { Pad to end of line to clear stale content; highlight if selection covers EOL }
  PadCount := Width - VisStr.Length;
  if PadSelected and (PadCount > 0) then
  begin
    Term.SetFG(clBlack);
    Term.SetBG(clCyan);
    Term.WriteStr(' ');  { one highlighted space at EOL to show the newline is selected }
    Term.ResetColors;
    for I := 2 to PadCount do Term.WriteStr(' ');
  end
  else
  begin
    Term.ResetColors;
    for I := 1 to PadCount do Term.WriteStr(' ');
  end;
end;

procedure TTextEditor.DoPaint;
var
  Row, LineIdx, VIdx, StartChar: Integer;
  S:                             string;
  Spans:                         TTextSpanArray;
  TrailStart, SLen, N, SpanIdx:  Integer;
begin
  BeginCursorUpdate;
  try
  if Assigned(FHighlighter) then
    FHighlighter.Prepare(FLines);

  if FWordWrap then
  begin
    for Row := 1 to Height do
    begin
      VIdx := FTopRow + Row - 1;
      if VIdx < Length(FWrapTable) then
      begin
        LineIdx   := FWrapTable[VIdx].LineIdx;
        StartChar := FWrapTable[VIdx].StartChar;
        if LineIdx < FLines.Count then
          S := FLines[LineIdx]
        else
          S := '';

        Spans := nil;
        if Assigned(FHighlighter) then
          FHighlighter.GetSpans(LineIdx, S, Spans);

        if FHighlightTrailingSpaces and (S <> '') then
        begin
          SLen       := S.Length;
          TrailStart := SLen;
          while (TrailStart > 0) and (S.Chars[TrailStart - 1] = ' ') do Dec(TrailStart);
          N := SLen - TrailStart;
          if (N > 0) and ((LineIdx <> FCurRow - 1) or (FCurCol <= TrailStart)) then
          begin
            SpanIdx := System.Length(Spans);
            SetLength(Spans, SpanIdx + 1);
            Spans[SpanIdx].Col       := TrailStart;
            Spans[SpanIdx].Len       := N;
            Spans[SpanIdx].FG        := clDefault;
            Spans[SpanIdx].BG        := clRed;
            Spans[SpanIdx].Underline := False;
          end;
        end;

        PaintLine(Row, S, LineIdx, Spans, StartChar);
      end
      else
        PaintLine(Row, '', -1, nil, 0);
    end;

  end
  else
  begin
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
        SLen       := S.Length;
        TrailStart := SLen;
        while (TrailStart > 0) and (S.Chars[TrailStart - 1] = ' ') do Dec(TrailStart);
        N := SLen - TrailStart;
        if (N > 0) and ((LineIdx <> FCurRow - 1) or (FCurCol <= TrailStart)) then
        begin
          SpanIdx := System.Length(Spans);
          SetLength(Spans, SpanIdx + 1);
          Spans[SpanIdx].Col       := TrailStart;
          Spans[SpanIdx].Len       := N;
          Spans[SpanIdx].FG        := clDefault;
          Spans[SpanIdx].BG        := clRed;
          Spans[SpanIdx].Underline := False;
        end;
      end;

      PaintLine(Row, S, LineIdx, Spans, FLeftCol);
    end;

  end;

  inherited DoPaint;
  finally
    EndCursorUpdate;
  end;
end;

procedure TTextEditor.DoBoundsChanged;
begin
  if FWordWrap then BuildWrapTable;
  EnsureVisStr;
end;

function TTextEditor.DoKeyDown(var Key: TKeyEvent): Boolean;
var
  SR, SC, ER, EC: Integer;
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
    Exit;
  end;

  { Edit mode — handle selection-aware keys }
  case Key.Code of

    { ── Plain movement: collapse selection to start or end ── }
    kcLeft:
      if HasSelection then
      begin
        GetSelRange(SR, SC, ER, EC);
        FCurRow := SR; FCurCol := SC;
        ClearSelection; EnsureVisStr; Invalidate;
      end
      else
        MoveCursorLeft;
    kcRight:
      if HasSelection then
      begin
        GetSelRange(SR, SC, ER, EC);
        FCurRow := ER; FCurCol := EC;
        ClearSelection; EnsureVisStr; Invalidate;
      end
      else
        MoveCursorRight;
    kcUp:     begin ClearSelection; MoveCursorUp;   end;
    kcDown:   begin ClearSelection; MoveCursorDown; end;
    kcHome:   begin ClearSelection; MoveHome;       end;
    kcEnd:    begin ClearSelection; MoveEnd;        end;
    kcPageUp:   begin ClearSelection; PageUp;       end;
    kcPageDown: begin ClearSelection; PageDown;     end;
    kcCtrlLeft:  begin ClearSelection; MoveCursorLeft(True);  end;
    kcCtrlRight: begin ClearSelection; MoveCursorRight(True); end;
    kcCtrlHome:  begin ClearSelection; MoveDocStart;          end;
    kcCtrlEnd:   begin ClearSelection; MoveDocEnd;            end;

    { ── Shift+movement: extend selection ── }
    kcShiftLeft:
      begin
        if not FSelection.Active then SetAnchor;
        MoveCursorLeft; Invalidate;
      end;
    kcShiftRight:
      begin
        if not FSelection.Active then SetAnchor;
        MoveCursorRight; Invalidate;
      end;
    kcShiftUp:
      begin
        if not FSelection.Active then SetAnchor;
        MoveCursorUp; Invalidate;
      end;
    kcShiftDown:
      begin
        if not FSelection.Active then SetAnchor;
        MoveCursorDown; Invalidate;
      end;
    kcShiftHome:
      begin
        if not FSelection.Active then SetAnchor;
        MoveHome; Invalidate;
      end;
    kcShiftEnd:
      begin
        if not FSelection.Active then SetAnchor;
        MoveEnd; Invalidate;
      end;
    kcShiftPageUp:
      begin
        if not FSelection.Active then SetAnchor;
        PageUp; Invalidate;
      end;
    kcShiftPageDown:
      begin
        if not FSelection.Active then SetAnchor;
        PageDown; Invalidate;
      end;
    kcShiftCtrlLeft:
      begin
        if not FSelection.Active then SetAnchor;
        MoveCursorLeft(True); Invalidate;
      end;
    kcShiftCtrlRight:
      begin
        if not FSelection.Active then SetAnchor;
        MoveCursorRight(True); Invalidate;
      end;
    kcShiftCtrlHome:
      begin
        if not FSelection.Active then SetAnchor;
        MoveDocStart; Invalidate;
      end;
    kcShiftCtrlEnd:
      begin
        if not FSelection.Active then SetAnchor;
        MoveDocEnd; Invalidate;
      end;

    { ── Escape: clear selection ── }
    kcEscape:
      if HasSelection then
      begin
        ClearSelection; Invalidate;
      end
      else
        Result := False;

    { ── Editing ── }
    kcBackspace:        DeleteBack;
    kcDelete:           DeleteForward;
    kcEnter:            InsertNewLine;
    kcCtrlK:            DeleteToEOL;

    kcCtrlA:
      begin
        { Select all }
        FSelection.Active    := True;
        FSelection.AnchorRow := 1;
        FSelection.AnchorCol := 1;
        FCurRow := LineCount;
        FCurCol := FLines[FCurRow - 1].Length + 1;
        EnsureVisStr; Invalidate;
      end;

    kcCtrlC: CopyCurrentLine;

    kcCtrlX:
      if HasSelection then
      begin
        Clipboard.SetText(GetSelectedText);
        DeleteSelectionImpl;
        ClearSelection;
        Invalidate;
      end;

    kcCtrlV:
      begin
        { InsertText already handles selection replacement }
        InsertText(Clipboard.GetText);
      end;

    kcBracketedPaste: InsertText(Key.PasteText);

    kcTab:
      if FCaptureTabs then InsertTab
      else Result := False;

    kcChar:
      if Key.Ch >= ' ' then InsertChar(Key.Ch)
      else Result := False;

  else
    Result := False;
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
