{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Completion;

{$mode objfpc}{$H+}
{$modeswitch typehelpers}

{ TCompletionPopup — non-stealing text-completion popup.

  The popup is a plain object (not TControl/TForm) that draws directly on the
  terminal back-buffer. It does not push a new form or steal key focus.

  Hosting (in the enclosing TForm):

    1. Create popup and data source once:
         FPopup := TCompletionPopup.Create;
         FPopup.DataSource := FMySource;

    2. Connect the editor's OnChange:
         FEdit.OnChange := @OnEditorChange;

         procedure TMyForm.OnEditorChange(Sender: TObject);
         begin
           FPopup.TriggerFromEditor(FEdit);
           Invalidate;
         end;

    3. In DoPaint — paint popup LAST so it overlays everything:
         inherited DoPaint;
         if FPopup.Visible then FPopup.Paint;

    4. In DoKeyDown — intercept popup navigation before the editor:
         if FPopup.Visible then
         begin
           case Key.Code of
             kcDown, kcUp, kcEscape: { let popup handle }
               if FPopup.HandleNavKey(Key) then Exit(True);
             kcEnter:
               if FPopup.CommitInto(FEdit, cmReplaceWord) then Exit(True);
             kcTab:
               if FPopup.CommitInto(FEdit, cmReplacePrefix) then Exit(True);
           end;
         end;
         Result := inherited DoKeyDown(Key);   { pass to focused editor }

  Commit modes (TCommitMode):
    cmReplaceWord    Replace [WordStart..WordEnd) — the whole word the cursor
                     is inside.  Used for Enter and Space.
    cmReplacePrefix  Replace [WordStart..CursorPos) only — leave text that
                     follows the cursor intact.  Used for Tab.

  Commit characters (DataSource.CommitChars):
    If the user types a character that is in CommitChars (e.g. '.' or '('),
    CommitOnChar is called.  It commits the selection and then lets the
    character pass through to the editor normally.

  Trigger suppression:
    After the user presses Escape the popup is suppressed until the cursor
    moves to a different position in the buffer.

  Item kinds and glyphs (drawn in dim cyan to the left of the item text):
    ckText     ·    plain word
    ckKeyword  kw   language keyword
    ckFunction fn   function / method
    ckVariable vr   variable / field
    ckType     tp   type / class
    ckModule   md   unit / module
    ckSnippet  sn   code snippet

  Detail annotation:
    Each item may carry a Detail string (type signature, return type, etc.)
    drawn right-aligned in dim colour to the right of the item text.

  Further ideas not yet implemented:
    • Documentation side-panel (secondary popup with full docstring)
    • Async data source interface (for LSP / slow providers)
    • Multiple chained data sources
    • Fuzzy scoring (currently prefix-only with an exact-match boost)
    • Snippet tab-stop support (${1:name} placeholders)
    • Context-aware suppression (inside strings / comments)
}

interface

uses
  Classes, SysUtils, Contnrs,
  TermUI.Terminal, TermUI.Application, TermUI.StringUtils,
  TermUI.Control.LineEditor;

type
  TCompletionKind = (
    ckText,      { plain word from document }
    ckKeyword,   { language keyword }
    ckFunction,  { function or method }
    ckVariable,  { variable or field }
    ckType,      { type, class, record }
    ckModule,    { unit or module }
    ckSnippet    { code template }
  );

  TCompletionItem = class
    DisplayText: string;   { text shown in the list }
    InsertText:  string;   { text inserted on commit; empty → use DisplayText }
    Kind:        TCompletionKind;
    Detail:      string;   { brief annotation shown right-aligned }

    constructor Create(const ADisplay: string;
                       AKind: TCompletionKind = ckText;
                       const AInsert: string = '';
                       const ADetail: string = '');
    function EffectiveInsert: string;
  end;

  TCompletionList = class
  private
    FItems: TObjectList;
    function  GetItem(I: Integer): TCompletionItem;
    function  GetCount: Integer;
  public
    constructor Create;
    destructor  Destroy; override;
    procedure Add(const ADisplay: string;
                  AKind: TCompletionKind = ckText;
                  const AInsert: string  = '';
                  const ADetail: string  = '');
    procedure Clear;
    property Items[I: Integer]: TCompletionItem read GetItem; default;
    property Count: Integer read GetCount;
  end;

  TCompletionContext = record
    LineText:  string;    { full text of the line/buffer being edited }
    CursorPos: Integer;   { 1-based byte position of the cursor }
    WordStart: Integer;   { 1-based start of the word being completed }
    WordEnd:   Integer;   { 1-based exclusive end of the word }
    Prefix:    string;    { LineText[WordStart..CursorPos-1] }
  end;

  { Abstract data source. }
  TCompletionDataSource = class
  public
    { Populate AList with completions for the current context. }
    procedure GetCompletions(const ACtx: TCompletionContext;
                             AList: TCompletionList); virtual; abstract;

    { Return False to suppress the popup (e.g. prefix too short). }
    function  ShouldTrigger(const ACtx: TCompletionContext): Boolean; virtual;

    { Characters that auto-commit the selected item when typed.
      The character is still passed through to the editor afterward. }
    function  CommitChars: string; virtual;

    { Characters considered part of a word for boundary detection.
      Override to include '.' for member-access completion. }
    function  WordChars: string; virtual;
  end;

  { Scans a TStrings for words and suggests matches for the current prefix.
    Suitable as the "every word in the document" basic example.

    Scoring:
      3  exact case match of full word (already typed perfectly — skip)
      2  exact case prefix match
      1  case-insensitive prefix match
      0  substring match
    Items with the same score are sorted alphabetically.
    The word that exactly equals the prefix is excluded (no point completing it). }
  TWordListDataSource = class(TCompletionDataSource)
  private
    FSource:      TStrings;   { not owned }
    FMinPrefix:   Integer;
    procedure Tokenize(ALines: TStrings; AWords: TStringList);
  public
    constructor Create(ASource: TStrings; AMinPrefix: Integer = 2);
    procedure GetCompletions(const ACtx: TCompletionContext;
                             AList: TCompletionList); override;
    function  ShouldTrigger(const ACtx: TCompletionContext): Boolean; override;
    property MinPrefix: Integer read FMinPrefix write FMinPrefix;
  end;

  TCommitMode = (
    cmReplaceWord,    { replace entire word [WordStart..WordEnd) — Enter / Space }
    cmReplacePrefix   { replace only prefix [WordStart..CursorPos) — Tab }
  );

  { The completion popup. }
  TCompletionPopup = class
  private
    FItems:       TCompletionList;   { current filtered & ranked items }
    FSel:         Integer;           { selected index; -1 = none }
    FTopItem:     Integer;           { first visible item }
    FMaxVisible:  Integer;
    FVisible:     Boolean;
    FDataSource:  TCompletionDataSource;
    FContext:     TCompletionContext; { context from last trigger }

    { Terminal position of the popup's top-left corner }
    FAnchorX:     Integer;
    FAnchorY:     Integer;
    FPopupWidth:  Integer;

    { Suppression: set when Escape pressed; cleared when cursor moves }
    FSuppressed:      Boolean;
    FSuppressedPos:   Integer;  { CursorPos when suppression started }

    function  VisibleCount: Integer;
    procedure Clamp;
    function  GetSelected: TCompletionItem;
    procedure DoCommit(AEditor: TTextEdit; AMode: TCommitMode;
                       const AExtraChar: TUTF8Char);
    procedure CalcLayout(AEditorLeft, AEditorTop: Integer);

    function  KindGlyph(AKind: TCompletionKind): string;
    function  KindColor(AKind: TCompletionKind): TColor;

  public
    constructor Create;
    destructor  Destroy; override;

    { Call from the editor's OnChange handler. Queries the data source and
      shows / hides / repositions the popup. AEditor is used to compute
      the context and the screen position of the cursor. }
    procedure TriggerFromEditor(AEditor: TTextEdit);

    { Call from the host form's DoKeyDown when the popup is visible.
      Navigation keys (Up/Down/PgUp/PgDn/Escape) are consumed by the popup.
      Returns True if the key was handled and should NOT be passed to the editor. }
    function  HandleNavKey(var Key: TKeyEvent): Boolean;

    { Commit the selected item into the editor.
      Returns True if there was a selection to commit. }
    function  CommitInto(AEditor: TTextEdit; AMode: TCommitMode): Boolean;

    { Call when the user types a char that may be a commit char.
      If the char is in DataSource.CommitChars AND an item is selected,
      commits the selection and returns True (the char still goes to the editor).
      Otherwise returns False and the caller should let the char through normally. }
    function  CommitOnChar(AEditor: TTextEdit; const Ch: TUTF8Char): Boolean;

    { Paint the popup. Call AFTER all other painting in the host's DoPaint. }
    procedure Paint;

    procedure Hide;

    property Visible:    Boolean             read FVisible;
    property DataSource: TCompletionDataSource read FDataSource write FDataSource;
    property MaxVisible: Integer             read FMaxVisible  write FMaxVisible;
    property Selected:   TCompletionItem     read GetSelected;
    property SelIndex:   Integer             read FSel;
  end;

{ Utility: build a TCompletionContext from a line string and cursor position.
  AWordChars defines which characters are treated as part of a word. }
function BuildContext(const ALine: string; ACursorPos: Integer;
                     const AWordChars: string = ''): TCompletionContext;

implementation


{ ── TCompletionItem ── }

constructor TCompletionItem.Create(const ADisplay: string;
  AKind: TCompletionKind; const AInsert: string; const ADetail: string);
begin
  inherited Create;
  DisplayText := ADisplay;
  Kind        := AKind;
  InsertText  := AInsert;
  Detail      := ADetail;
end;

function TCompletionItem.EffectiveInsert: string;
begin
  if InsertText <> '' then Result := InsertText
  else Result := DisplayText;
end;

{ ── TCompletionList ── }

constructor TCompletionList.Create;
begin
  inherited Create;
  FItems := TObjectList.Create(True);
end;

destructor TCompletionList.Destroy;
begin
  FItems.Free;
  inherited;
end;

function TCompletionList.GetItem(I: Integer): TCompletionItem;
begin
  Result := TCompletionItem(FItems[I]);
end;

function TCompletionList.GetCount: Integer;
begin
  Result := FItems.Count;
end;

procedure TCompletionList.Add(const ADisplay: string; AKind: TCompletionKind;
  const AInsert: string; const ADetail: string);
begin
  FItems.Add(TCompletionItem.Create(ADisplay, AKind, AInsert, ADetail));
end;

procedure TCompletionList.Clear;
begin
  FItems.Clear;
end;

{ ── TCompletionDataSource defaults ── }

function TCompletionDataSource.ShouldTrigger(const ACtx: TCompletionContext): Boolean;
begin
  Result := ACtx.Prefix.Length >= 1;
end;

function TCompletionDataSource.CommitChars: string;
begin
  Result := '';
end;

function TCompletionDataSource.WordChars: string;
begin
  Result := '';  { empty = use default: letters + digits + '_' }
end;

{ ── BuildContext ── }

{ All positions are 0-based codepoint indices matching TTextEdit.CursorPos. }

function IsWordChar(const Ch: TUTF8Char; const AExtra: string): Boolean;
begin
  Result := (Length(Ch) = 1) and
            ((Ch[1] in ['A'..'Z', 'a'..'z', '0'..'9', '_'])
             or (AExtra.Pos(Ch) >= 0));
end;

function BuildContext(const ALine: string; ACursorPos: Integer;
  const AWordChars: string): TCompletionContext;
var
  Len, WS, WE: Integer;
begin
  Len := ALine.Length;
  if ACursorPos < 0   then ACursorPos := 0;
  if ACursorPos > Len then ACursorPos := Len;

  { Scan left to find word start }
  WS := ACursorPos;
  while (WS > 0) and IsWordChar(ALine.Chars[WS - 1], AWordChars) do Dec(WS);

  { Scan right to find word end }
  WE := ACursorPos;
  while (WE < Len) and IsWordChar(ALine.Chars[WE], AWordChars) do Inc(WE);

  Result.LineText  := ALine;
  Result.CursorPos := ACursorPos;
  Result.WordStart := WS;
  Result.WordEnd   := WE;
  Result.Prefix    := ALine.Copy(WS, ACursorPos - WS);
end;

{ ── TWordListDataSource ── }

constructor TWordListDataSource.Create(ASource: TStrings; AMinPrefix: Integer);
begin
  inherited Create;
  FSource    := ASource;
  FMinPrefix := AMinPrefix;
end;

procedure TWordListDataSource.Tokenize(ALines: TStrings; AWords: TStringList);
var
  I, J:   Integer;
  Line:   string;
  Len:    Integer;
  Start:  Integer;   { 0-based start of current token, -1 = not in word }
  Word:   string;
begin
  for I := 0 to ALines.Count - 1 do
  begin
    Line  := ALines[I];
    Len   := Line.Length;
    Start := -1;
    for J := 0 to Len - 1 do
    begin
      if IsWordChar(Line.Chars[J], '') then
      begin
        if Start < 0 then Start := J;
      end
      else
      begin
        if Start >= 0 then
        begin
          Word := Line.Copy(Start, J - Start);
          if AWords.IndexOf(Word) < 0 then
            AWords.Add(Word);
          Start := -1;
        end;
      end;
    end;
    if Start >= 0 then
    begin
      Word := Line.Copy(Start, Len - Start);
      if AWords.IndexOf(Word) < 0 then
        AWords.Add(Word);
    end;
  end;
end;

procedure TWordListDataSource.GetCompletions(const ACtx: TCompletionContext;
  AList: TCompletionList);
var
  AllWords:  TStringList;
  Scored:    TStringList;  { 'score:word' for sorting }
  I:         Integer;
  Word:      string;
  Prefix:    string;
  PrefixLo:  string;
  WordLo:    string;
  Score:     Integer;
  Entry:     string;
  ColonPos:  Integer;
begin
  if not Assigned(FSource) then Exit;
  Prefix   := ACtx.Prefix;
  PrefixLo := LowerCase(Prefix);

  AllWords := TStringList.Create;
  Scored   := TStringList.Create;
  try
    Tokenize(FSource, AllWords);
    for I := 0 to AllWords.Count - 1 do
    begin
      Word   := AllWords[I];
      WordLo := LowerCase(Word);

      if Word = Prefix then Continue;   { exact match — already typed it }

      Score := -1;
      if WordLo.Pos(PrefixLo) = 0 then
      begin
        { Prefix match }
        if Word.Copy(0, Prefix.Length) = Prefix then
          Score := 2   { exact case prefix }
        else
          Score := 1;  { case-insensitive prefix }
      end
      else if WordLo.Pos(PrefixLo) > 0 then
        Score := 0;    { substring match }

      if Score >= 0 then
        Scored.Add(Format('%d:%s', [9 - Score, Word]));  { invert so sort is ascending }
    end;

    Scored.Sort;

    for I := 0 to Scored.Count - 1 do
    begin
      Entry    := Scored[I];
      ColonPos := Entry.Pos(TUTF8Char(':'));   { 0-based char pos of ':' in score prefix }
      Word     := Entry.Copy(ColonPos + 1, Entry.Length - ColonPos - 1);
      AList.Add(Word, ckText);
    end;
  finally
    Scored.Free;
    AllWords.Free;
  end;
end;

function TWordListDataSource.ShouldTrigger(const ACtx: TCompletionContext): Boolean;
begin
  Result := ACtx.Prefix.Length >= FMinPrefix;
end;

{ ── TCompletionPopup ── }

constructor TCompletionPopup.Create;
begin
  inherited Create;
  FItems      := TCompletionList.Create;
  FSel        := -1;
  FTopItem    := 0;
  FMaxVisible := 8;
  FVisible    := False;
end;

destructor TCompletionPopup.Destroy;
begin
  FItems.Free;
  inherited;
end;

function TCompletionPopup.VisibleCount: Integer;
begin
  Result := FItems.Count;
  if Result > FMaxVisible then Result := FMaxVisible;
end;

procedure TCompletionPopup.Clamp;
var VC: Integer;
begin
  if FItems.Count = 0 then begin FSel := -1; FTopItem := 0; Exit; end;
  if FSel < 0 then FSel := 0;
  if FSel >= FItems.Count then FSel := FItems.Count - 1;
  VC := VisibleCount;
  if FSel < FTopItem then FTopItem := FSel
  else if FSel >= FTopItem + VC then FTopItem := FSel - VC + 1;
  if FTopItem < 0 then FTopItem := 0;
end;

function TCompletionPopup.GetSelected: TCompletionItem;
begin
  if (FSel >= 0) and (FSel < FItems.Count) then
    Result := FItems[FSel]
  else
    Result := nil;
end;

function TCompletionPopup.KindGlyph(AKind: TCompletionKind): string;
begin
  case AKind of
    ckKeyword:  Result := 'kw';
    ckFunction: Result := 'fn';
    ckVariable: Result := 'vr';
    ckType:     Result := 'tp';
    ckModule:   Result := 'md';
    ckSnippet:  Result := 'sn';
  else
    Result := ' ·';
  end;
end;

function TCompletionPopup.KindColor(AKind: TCompletionKind): TColor;
begin
  case AKind of
    ckKeyword:  Result := clYellow;
    ckFunction: Result := clGreen;
    ckVariable: Result := clCyan;
    ckType:     Result := clMagenta;
    ckModule:   Result := clBlue;
    ckSnippet:  Result := clBrightYellow;
  else
    Result := clBrightBlack;
  end;
end;

procedure TCompletionPopup.CalcLayout(AEditorLeft, AEditorTop: Integer);
var
  CursorScreenX: Integer;
  I:             Integer;
  MaxW:          Integer;
  ItemW:         Integer;
  TermW:         Integer;
  TermH:         Integer;
  PopupH:        Integer;
begin
  TermW := Term.Width;
  TermH := Term.Height;

  { Cursor screen column = editor left + (CursorPos - FScroll).
    CursorPos is 0-based; we approximate without the scroll offset — the
    anchor is clamped to the terminal width regardless. }
  CursorScreenX := AEditorLeft + FContext.CursorPos;
  if CursorScreenX < 1     then CursorScreenX := 1;
  if CursorScreenX > TermW then CursorScreenX := TermW;

  { Measure required width: glyph (2) + space + text + space + detail }
  MaxW := 20;
  for I := 0 to FItems.Count - 1 do
  begin
    ItemW := 4 + Length(FItems[I].DisplayText);
    if FItems[I].Detail <> '' then ItemW := ItemW + 2 + Length(FItems[I].Detail);
    if ItemW > MaxW then MaxW := ItemW;
  end;
  if MaxW > TermW then MaxW := TermW;
  FPopupWidth := MaxW;

  { Anchor X: try to start at cursor; clamp so popup fits }
  FAnchorX := CursorScreenX;
  if FAnchorX + FPopupWidth - 1 > TermW then
    FAnchorX := TermW - FPopupWidth + 1;
  if FAnchorX < 1 then FAnchorX := 1;

  { Anchor Y: prefer one row below the editor; flip above if needed }
  PopupH := VisibleCount;
  if AEditorTop + 1 + PopupH - 1 <= TermH then
    FAnchorY := AEditorTop + 1    { below }
  else
    FAnchorY := AEditorTop - PopupH;  { above }
  if FAnchorY < 1 then FAnchorY := 1;
end;

procedure TCompletionPopup.TriggerFromEditor(AEditor: TTextEdit);
var
  WordChars: string;
begin
  if not Assigned(FDataSource) then Exit;

  WordChars := FDataSource.WordChars;
  FContext  := BuildContext(AEditor.Text, AEditor.CursorPos, WordChars);

  { Lift suppression if cursor moved }
  if FSuppressed and (AEditor.CursorPos <> FSuppressedPos) then
    FSuppressed := False;

  if FSuppressed then Exit;

  if not FDataSource.ShouldTrigger(FContext) then
  begin
    Hide;
    Exit;
  end;

  FItems.Clear;
  FDataSource.GetCompletions(FContext, FItems);

  if FItems.Count = 0 then
  begin
    Hide;
    Exit;
  end;

  { Auto-select first item }
  FSel     := 0;
  FTopItem := 0;

  CalcLayout(AEditor.Left, AEditor.Top);
  FVisible := True;
end;

function TCompletionPopup.HandleNavKey(var Key: TKeyEvent): Boolean;
begin
  Result := False;
  if not FVisible then Exit;

  case Key.Code of
    kcDown:
    begin
      if FSel < FItems.Count - 1 then
      begin
        Inc(FSel);
        Clamp;
      end;
      Result := True;
    end;
    kcUp:
    begin
      if FSel > 0 then
      begin
        Dec(FSel);
        Clamp;
      end
      else
        { Up from first item hides the popup so the cursor can go up in the editor }
        Hide;
      Result := True;
    end;
    kcPageDown:
    begin
      Inc(FSel, FMaxVisible);
      Clamp;
      Result := True;
    end;
    kcPageUp:
    begin
      Dec(FSel, FMaxVisible);
      if FSel < 0 then FSel := 0;
      Clamp;
      Result := True;
    end;
    kcEscape:
    begin
      FSuppressed    := True;
      FSuppressedPos := FContext.CursorPos;
      Hide;
      Result := True;
    end;
  end;
end;

procedure TCompletionPopup.DoCommit(AEditor: TTextEdit; AMode: TCommitMode;
  const AExtraChar: TUTF8Char);
var
  Item:    TCompletionItem;
  Insert:  string;
  RepFrom: Integer;
  RepTo:   Integer;
begin
  Item := GetSelected;
  if not Assigned(Item) then Exit;

  Insert  := Item.EffectiveInsert;
  RepFrom := FContext.WordStart;

  case AMode of
    cmReplaceWord:   RepTo := FContext.WordEnd;
    cmReplacePrefix: RepTo := FContext.CursorPos;
  end;

  if AExtraChar <> '' then
    Insert := Insert + string(AExtraChar);

  AEditor.ReplaceRange(RepFrom, RepTo, Insert);
  Hide;
end;

function TCompletionPopup.CommitInto(AEditor: TTextEdit; AMode: TCommitMode): Boolean;
begin
  Result := FVisible and (FSel >= 0) and (FSel < FItems.Count);
  if Result then DoCommit(AEditor, AMode, '');
end;

function TCompletionPopup.CommitOnChar(AEditor: TTextEdit;
  const Ch: TUTF8Char): Boolean;
begin
  Result := FVisible and (FSel >= 0) and (FSel < FItems.Count)
            and (FDataSource.CommitChars.Pos(Ch) >= 0);
  if Result then DoCommit(AEditor, cmReplacePrefix, Ch);
end;

procedure TCompletionPopup.Hide;
begin
  FVisible := False;
  FItems.Clear;
  FSel     := -1;
  FTopItem := 0;
end;

procedure TCompletionPopup.Paint;
const
  GlyphW = 2;   { width of kind glyph column }
var
  VC, I, Idx:  Integer;
  Item:        TCompletionItem;
  IsSel:       Boolean;
  Glyph:       string;
  Display:     string;
  DetailStr:   string;
  AvailW:      Integer;
  TextW:       Integer;
  DetailW:     Integer;
  Line:        string;
  ScrollUp:    Boolean;
  ScrollDown:  Boolean;
begin
  if not FVisible or (FItems.Count = 0) then Exit;

  VC         := VisibleCount;
  ScrollUp   := FTopItem > 0;
  ScrollDown := FTopItem + VC < FItems.Count;

  for I := 0 to VC - 1 do
  begin
    Idx  := FTopItem + I;
    Item := FItems[Idx];
    IsSel := Idx = FSel;

    Term.GotoXY(FAnchorX, FAnchorY + I);

    if IsSel then
    begin
      Term.SetFG(clBlack);
      Term.SetBG(clCyan);
    end
    else
    begin
      Term.SetFG(clWhite);
      Term.SetBG(clBrightBlack);
    end;

    { Kind glyph }
    if not IsSel then
      Term.SetFG(KindColor(Item.Kind));
    Glyph := KindGlyph(Item.Kind);
    if Length(Glyph) < GlyphW then Glyph := StringOfChar(' ', GlyphW - Length(Glyph)) + Glyph;
    Term.WriteStr(Glyph);
    Term.WriteStr(' ');

    { Item text + detail }
    if IsSel then
    begin
      Term.SetFG(clBlack);
      Term.SetBG(clCyan);
    end
    else
    begin
      Term.SetFG(clWhite);
      Term.SetBG(clBrightBlack);
    end;

    AvailW    := FPopupWidth - GlyphW - 1;  { space after glyph }
    DetailStr := Item.Detail;
    Display   := Item.DisplayText;

    if DetailStr <> '' then
    begin
      DetailW := DetailStr.Length + 2;   { ' : detail' }
      TextW   := AvailW - DetailW;
      if TextW < 8 then begin TextW := AvailW; DetailStr := ''; end;
    end
    else
      TextW := AvailW;

    if Display.Length > TextW then Display := Display.Copy(0, TextW);

    Line := Display;
    if DetailStr <> '' then
    begin
      while Line.Length < TextW do Line := Line + ' ';
      if IsSel then
      begin
        Term.WriteStr(Line);
        Term.SetFG(clBrightBlack);
        Term.WriteStr(' : ' + DetailStr);
      end
      else
      begin
        Term.WriteStr(Line);
        Term.SetFG(clBrightBlack);
        Term.SetBG(clBrightBlack);
        Term.WriteStr(' : ' + DetailStr);
      end;
    end
    else
    begin
      while Line.Length < AvailW do Line := Line + ' ';
      Term.WriteStr(Line);
    end;

    { Scroll indicator on the rightmost char of first/last visible row }
    if (I = 0) and ScrollUp then
    begin
      Term.GotoXY(FAnchorX + FPopupWidth - 1, FAnchorY);
      Term.SetFG(clWhite);
      Term.SetBG(clBrightBlack);
      Application.DrawChar(dcArrowUp);
    end;
    if (I = VC - 1) and ScrollDown then
    begin
      Term.GotoXY(FAnchorX + FPopupWidth - 1, FAnchorY + I);
      Term.SetFG(clWhite);
      Term.SetBG(clBrightBlack);
      Application.DrawChar(dcArrowDown);
    end;
  end;

  Term.ResetColors;
end;

end.
