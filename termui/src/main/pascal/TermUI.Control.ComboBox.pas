{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Control.ComboBox;

{$mode objfpc}{$H+}

{ Single-line combo-box with a scrollable, optionally filtered drop-down.

  Style:
    csFixed    — read-only selector.  Down / Enter / Space opens the drop-down.
    csDropDown — the collapsed control is an edit field; typing filters the
                 items in the drop-down, which opens automatically.

  Drop-down behaviour:
    • Anchored immediately below the control; falls back above when there is
      not enough space below.
    • Height is capped to available screen rows; the list scrolls.
    • Right border doubles as a scrollbar track: ^ at the top when scrolled
      down, v at the bottom when more items exist below, # at the proportional
      thumb, | otherwise.
    • Home / End / PgUp / PgDn / Up / Down navigate the list.
    • Enter confirms.  Esc / Tab cancel.
    • In csDropDown mode the top row of the drop-down is a live filter field;
      typing in the collapsed control also pre-fills it and opens the drop-down.

  RequireValidSelection:
    When True, Esc/Tab restore the selection that was active when the
    drop-down opened instead of leaving SelectedIndex = -1. }

interface

uses
  Classes, TermUI.Terminal, TermUI.Control;

type
  TComboBoxStyle = (
    csFixed,     { read-only; Down/Enter/Space opens drop-down }
    csDropDown   { edit field; typing filters items             }
  );

  TComboBox = class(TControl)
  private
    FItems:                 TStringList;
    FSelectedIndex:         Integer;
    FStyle:                 TComboBoxStyle;
    FRequireValidSelection: Boolean;
    FOpenOnFocus:           Boolean;
    FTextAlign:             TTextAlign;
    FEditText:              string;
    FEditCursor:            Integer;   { 0-based cursor position in FEditText }
    FOnChange:              TNotifyEvent;

    function  GetSelectedText: string;
    procedure SetSelectedIndex(AValue: Integer);
    procedure SetEditText(const AValue: string);
    procedure OpenDropdown;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
    procedure DoGainFocus; override;
  public
    constructor Create;
    destructor  Destroy; override;

    { Items displayed in the drop-down. }
    property Items: TStringList read FItems;

    { Currently selected item index.  -1 = nothing selected. }
    property SelectedIndex: Integer read FSelectedIndex write SetSelectedIndex;

    { Text of the selected item, or the typed edit text in csDropDown mode. }
    property SelectedText: string read GetSelectedText;

    { csFixed = read-only selector. csDropDown = typing filters the list. }
    property Style: TComboBoxStyle read FStyle write FStyle;

    { Text alignment within the collapsed control (csFixed mode). }
    property TextAlign: TTextAlign read FTextAlign write FTextAlign;

    { When True, the drop-down opens automatically when GainFocus is called. }
    property OpenOnFocus: Boolean read FOpenOnFocus write FOpenOnFocus;

    { When True, Esc/Tab restore the previous selection rather than -1. }
    property RequireValidSelection: Boolean
      read FRequireValidSelection write FRequireValidSelection;

    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

implementation

uses
  SysUtils, Math, TermUI.StringUtils, TermUI.Application, TermUI.Forms;

{ Shorthand so DoPaint/DrawScrollbar read cleanly }
function DC(ABc: TDrawingChar): string; inline;
begin
  Result := Application.DrawingChar[ABc];
end;

{ ── TComboDropDown — internal modal drop-down overlay ────────────────────── }

type
  TComboDropDown = class(TForm)
  private
    FAllItems:   TStringList;  { reference — NOT owned }
    FStyle:      TComboBoxStyle;
    FFiltered:   TStringList;  { owned; Objects[i] = PtrInt(original index) }
    FEditText:   string;
    FEditCursor: Integer;      { 0-based }
    FSel:        Integer;      { index in FFiltered }
    FTopIdx:     Integer;      { first visible item in FFiltered }
    FListRows:   Integer;      { number of visible item rows }
    FResultIdx:  Integer;      { -1 = cancelled; else original-items index }
    FFixed:      record L, T, W, H: Integer; end;
    FBoundsSet:  Boolean;

    function  FilterRowOffset: Integer;  { 1 in csDropDown, 0 in csFixed }
    procedure RebuildFilter;
    function  FilteredCount: Integer;
    function  FilteredText(AIdx: Integer): string;
    function  OriginalIndex(AFilteredIdx: Integer): Integer;
    procedure EnsureSelVisible;
    procedure DrawScrollbar(AListRow: Integer);
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
  public
    constructor Create(AItems: TStringList; AStyle: TComboBoxStyle;
      const AEditText: string; AInitialOrigIdx: Integer;
      ACtrlLeft, ACtrlTop, ACtrlWidth: Integer);
    destructor  Destroy; override;
    procedure SetBounds(ALeft, ATop, AWidth, AHeight: Integer); override;
    property ResultIndex: Integer read FResultIdx;
  end;

constructor TComboDropDown.Create(AItems: TStringList; AStyle: TComboBoxStyle;
  const AEditText: string; AInitialOrigIdx: Integer;
  ACtrlLeft, ACtrlTop, ACtrlWidth: Integer);
var
  I, MaxItemW, PopW, Chrome, RowsBelow, RowsAbove, PopH, PopT: Integer;
begin
  inherited Create;
  Overlay     := True;
  FAllItems   := AItems;
  FStyle      := AStyle;
  FEditText   := AEditText;
  FEditCursor := Length(AEditText);  { 0-based: cursor after last char }
  FFiltered   := TStringList.Create;
  FResultIdx  := -1;
  FSel        := 0;
  FTopIdx     := 0;

  RebuildFilter;

  { Restore selection to the item matching AInitialOrigIdx }
  for I := 0 to FFiltered.Count - 1 do
    if OriginalIndex(I) = AInitialOrigIdx then begin FSel := I; Break; end;

  { Popup width: at least the control width, wide enough for every item }
  MaxItemW := 0;
  for I := 0 to FAllItems.Count - 1 do
    if Length(FAllItems[I]) + 5 > MaxItemW then
      MaxItemW := Length(FAllItems[I]) + 5;  { "| text  |" + scrollbar }
  PopW := Max(ACtrlWidth, MaxItemW);
  if PopW > Term.Width then PopW := Term.Width;

  { chrome = top border + bottom border + optional filter row }
  Chrome := 2 + FilterRowOffset;

  { Space available below / above }
  RowsBelow := Term.Height - ACtrlTop;
  RowsAbove := ACtrlTop - 1;

  if RowsBelow >= Chrome + 1 then
  begin
    FListRows := Min(Max(1, FFiltered.Count), RowsBelow - Chrome);
    PopH      := FListRows + Chrome;
    PopT      := ACtrlTop + 1;
  end
  else
  begin
    FListRows := Max(1, Min(Max(1, FFiltered.Count), RowsAbove - Chrome));
    PopH      := FListRows + Chrome;
    PopT      := ACtrlTop - PopH;
    if PopT < 1 then PopT := 1;
  end;

  FFixed.L   := ACtrlLeft;
  FFixed.T   := PopT;
  FFixed.W   := PopW;
  FFixed.H   := PopH;
  FBoundsSet := True;
  inherited SetBounds(FFixed.L, FFixed.T, FFixed.W, FFixed.H);

  EnsureSelVisible;
end;

destructor TComboDropDown.Destroy;
begin
  FFiltered.Free;
  inherited;
end;

procedure TComboDropDown.SetBounds(ALeft, ATop, AWidth, AHeight: Integer);
begin
  { Ignore TApplication resize calls — the drop-down is short-lived }
  if FBoundsSet then
    inherited SetBounds(FFixed.L, FFixed.T, FFixed.W, FFixed.H)
  else
    inherited SetBounds(ALeft, ATop, AWidth, AHeight);
end;

function TComboDropDown.FilterRowOffset: Integer;
begin
  if FStyle = csDropDown then Result := 1 else Result := 0;
end;

procedure TComboDropDown.RebuildFilter;
var
  I: Integer;
  LFilter: string;
begin
  LFilter := LowerCase(FEditText);
  FFiltered.Clear;
  for I := 0 to FAllItems.Count - 1 do
    if (LFilter = '') or PosNeutral(LFilter, LowerCase(FAllItems[I])) then
      FFiltered.AddObject(FAllItems[I], TObject(PtrInt(I)));
  if FSel >= FFiltered.Count then
    FSel := Max(0, FFiltered.Count - 1);
  EnsureSelVisible;
end;

function TComboDropDown.FilteredCount: Integer;
begin
  Result := FFiltered.Count;
end;

function TComboDropDown.FilteredText(AIdx: Integer): string;
begin
  if (AIdx >= 0) and (AIdx < FFiltered.Count) then
    Result := FFiltered[AIdx]
  else
    Result := '';
end;

function TComboDropDown.OriginalIndex(AFilteredIdx: Integer): Integer;
begin
  if (AFilteredIdx >= 0) and (AFilteredIdx < FFiltered.Count) then
    Result := PtrInt(FFiltered.Objects[AFilteredIdx])
  else
    Result := -1;
end;

procedure TComboDropDown.EnsureSelVisible;
begin
  if FSel < FTopIdx then
    FTopIdx := FSel
  else if (FListRows > 0) and (FSel >= FTopIdx + FListRows) then
    FTopIdx := FSel - FListRows + 1;
  if FTopIdx < 0 then FTopIdx := 0;
end;

procedure TComboDropDown.DrawScrollbar(AListRow: Integer);
var
  Total, ThumbPos: Integer;
begin
  Total := FilteredCount;
  if Total <= FListRows then begin Term.WriteStr(' '); Exit; end;

  if (AListRow = 1) and (FTopIdx > 0) then
    begin Term.WriteStr(DC(dcScrollUp)); Exit; end;

  if (AListRow = FListRows) and (FTopIdx + FListRows < Total) then
    begin Term.WriteStr(DC(dcScrollDown)); Exit; end;

  ThumbPos := 1;
  if FListRows > 2 then
    ThumbPos := 1 + Round((FListRows - 2) * FSel / Max(1, Total - 1));

  if AListRow = ThumbPos then Term.WriteStr(DC(dcScrollThumb))
  else                        Term.WriteStr(DC(dcScrollTrack));
end;

procedure TComboDropDown.DoPaint;
var
  I, Row, InnerW, ListRow: Integer;
  Lbl, EditField, HintLine: string;
  IsSelected: Boolean;
begin
  InnerW := Width - 2;

  Term.SetBG(clBlue);
  Term.SetFG(clBrightWhite);

  { Top border }
  GotoLocal(1, 1);
  Term.WriteStr(DC(dcTopLeft));
  Term.WriteStr(Application.RepeatChar(dcHoriz, InnerW));
  Term.WriteStr(DC(dcTopRight));

  { Filter row (csDropDown only) }
  if FStyle = csDropDown then
  begin
    GotoLocal(1, 2);
    Term.SetFG(clBrightWhite); Term.SetBG(clBlue);
    Term.WriteStr(DC(dcVert));
    Term.SetFG(clBlack); Term.SetBG(clCyan);
    EditField := FEditText;
    { Insert cursor marker }
    if FEditCursor < Length(EditField) then
      EditField[FEditCursor + 1] := '_'
    else
      EditField := EditField + '_';
    EditField := ' ' + EditField;
    if Length(EditField) > InnerW then
      EditField := Copy(EditField, 1, InnerW)
    else
      EditField := EditField + StringOfChar(' ', InnerW - Length(EditField));
    Term.WriteStr(EditField);
    Term.SetFG(clBrightWhite); Term.SetBG(clBlue);
    Term.WriteStr(DC(dcVert));
  end;

  { Item rows }
  for ListRow := 1 to FListRows do
  begin
    I   := FTopIdx + ListRow - 1;
    Row := 1 + FilterRowOffset + ListRow;
    GotoLocal(1, Row);

    Term.SetFG(clBrightWhite); Term.SetBG(clBlue);
    Term.WriteStr(DC(dcVert));

    IsSelected := (I = FSel);
    if IsSelected then begin Term.SetFG(clBlack); Term.SetBG(clCyan); end
    else               begin Term.SetFG(clBrightWhite); Term.SetBG(clBlue); end;

    if I < FilteredCount then
    begin
      Lbl := ' ' + FilteredText(I);
      { InnerW-1 cols for text: leave 1 for scrollbar; right border is separate }
      if Length(Lbl) > InnerW - 1 then
        Lbl := Copy(Lbl, 1, InnerW - 2) + '~';
      Term.WriteStr(Lbl);
      Term.WriteStr(StringOfChar(' ', InnerW - 1 - Length(Lbl)));
    end
    else
      Term.WriteStr(StringOfChar(' ', InnerW - 1));

    Term.SetFG(clBrightWhite); Term.SetBG(clBlue);
    DrawScrollbar(ListRow);
    Term.WriteStr(DC(dcVert));
  end;

  { Bottom border with key hints }
  GotoLocal(1, Height);
  Term.SetFG(clBrightWhite); Term.SetBG(clBlue);
  Term.WriteStr(DC(dcBottomLeft));
  HintLine := DC(dcHoriz) + ' Enter:select  Esc/Tab:cancel ';
  while UTF8VisualLen(HintLine) < InnerW do
    HintLine := HintLine + DC(dcHoriz);
  { Trim to exactly InnerW visual columns }
  while UTF8VisualLen(HintLine) > InnerW do
    Delete(HintLine, Length(HintLine), 1);
  Term.WriteStr(HintLine);
  Term.WriteStr(DC(dcBottomRight));

  Term.ResetColors;
  Term.HideCursor;
  inherited DoPaint;
end;

function TComboDropDown.DoKeyDown(var Key: TKeyEvent): Boolean;
var
  PageSize: Integer;
begin
  Result   := True;
  PageSize := Max(1, FListRows - 1);

  case Key.Code of
    kcUp:
      begin
        if FSel > 0 then Dec(FSel);
        EnsureSelVisible; Invalidate;
      end;
    kcDown:
      begin
        if FSel < FilteredCount - 1 then Inc(FSel);
        EnsureSelVisible; Invalidate;
      end;
    kcPageUp:
      begin
        Dec(FSel, PageSize);
        if FSel < 0 then FSel := 0;
        EnsureSelVisible; Invalidate;
      end;
    kcPageDown:
      begin
        Inc(FSel, PageSize);
        if FSel >= FilteredCount then FSel := Max(0, FilteredCount - 1);
        EnsureSelVisible; Invalidate;
      end;
    kcHome: begin FSel := 0;                             EnsureSelVisible; Invalidate; end;
    kcEnd:  begin FSel := Max(0, FilteredCount - 1);     EnsureSelVisible; Invalidate; end;

    kcEnter:
      begin
        if FilteredCount > 0 then FResultIdx := OriginalIndex(FSel);
        Close(1);
      end;
    kcEscape, kcTab:
      begin FResultIdx := -1; Close(1); end;

    kcBackspace:
      if FStyle = csDropDown then
      begin
        if FEditCursor > 0 then
        begin
          DeleteNeutral(FEditText, FEditCursor - 1, 1);
          Dec(FEditCursor);
          RebuildFilter; Invalidate;
        end;
      end
      else Result := False;

    kcChar:
      if (FStyle = csDropDown) and (Key.Ch >= ' ') then
      begin
        InsertNeutral(FEditText, Key.Ch, FEditCursor);
        Inc(FEditCursor, System.Length(string(Key.Ch)));
        RebuildFilter; Invalidate;
      end
      else Result := False;

  else
    Result := False;
  end;
end;

{ ── TComboBox ────────────────────────────────────────────────────────────── }

constructor TComboBox.Create;
begin
  inherited Create;
  FItems         := TStringList.Create;
  FSelectedIndex := -1;
  FStyle         := csFixed;
  FTextAlign     := taLeft;
  FEditCursor    := 0;
end;

destructor TComboBox.Destroy;
begin
  FItems.Free;
  inherited;
end;

function TComboBox.GetSelectedText: string;
begin
  if FStyle = csDropDown then
    Result := FEditText
  else if (FSelectedIndex >= 0) and (FSelectedIndex < FItems.Count) then
    Result := FItems[FSelectedIndex]
  else
    Result := '';
end;

procedure TComboBox.SetSelectedIndex(AValue: Integer);
begin
  if FSelectedIndex = AValue then Exit;
  FSelectedIndex := AValue;
  if (FStyle = csDropDown) then
  begin
    if (AValue >= 0) and (AValue < FItems.Count) then
      SetEditText(FItems[AValue])
    else
      SetEditText('');
  end;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TComboBox.SetEditText(const AValue: string);
begin
  FEditText   := AValue;
  FEditCursor := Length(AValue);  { 0-based: cursor after last char }
end;

procedure TComboBox.OpenDropdown;
var
  Drop:    TComboDropDown;
  PrevSel: Integer;
begin
  PrevSel := FSelectedIndex;
  Drop := TComboDropDown.Create(
    FItems, FStyle, FEditText, FSelectedIndex,
    Left, Top, Width);
  try
    Application.ShowModal(Drop);
    if Drop.ResultIndex >= 0 then
    begin
      FSelectedIndex := Drop.ResultIndex;
      if FStyle = csDropDown then
        SetEditText(FItems[FSelectedIndex]);
      Invalidate;
      if Assigned(FOnChange) then FOnChange(Self);
    end
    else if FRequireValidSelection then
    begin
      FSelectedIndex := PrevSel;
      if FStyle = csDropDown then
      begin
        if (PrevSel >= 0) and (PrevSel < FItems.Count) then
          SetEditText(FItems[PrevSel])
        else
          SetEditText('');
      end;
      Invalidate;
    end
    else
      Invalidate;
  finally
    Drop.Free;
  end;
  { Restore cursor state: csFixed never shows it; csDropDown shows it for editing }
  if FStyle = csFixed then Term.HideCursor
  else                     Term.ShowCursor;
end;

procedure TComboBox.DoGainFocus;
begin
  if FOpenOnFocus then OpenDropdown;
end;

procedure TComboBox.DoPaint;
var
  InnerW, Scroll, Pad, PadL, PadR, CursorCol: Integer;
  Display:                                     string;
  CFG, CBG, InvFG, InvBG:                      TColor;
begin
  if Width < 5 then Exit;
  InnerW := Width - 4;  { '[' + content(InnerW) + ' v]' = Width }
  Scroll := 0;

  { Resolve effective colors }
  if Enabled then
  begin
    CFG := ForeColor;
    CBG := BackColor;
  end
  else
  begin
    CFG := clBrightBlack;
    CBG := clDefault;
  end;

  { Inverted colors for the 'v' drop indicator.
    Substitute clBackground for clDefault so the swap is always visible:
    clDefault <-> clDefault is a no-op, but clBackground <-> clDefault is not. }
  if CBG = clDefault then InvFG := clBackground else InvFG := CBG;
  if CFG = clDefault then InvBG := clBackground else InvBG := CFG;

  Term.SetFG(CFG);
  Term.SetBG(CBG);
  GotoLocal(1, 1);
  Term.WriteStr(DC(dcComboLeft));

  if FStyle = csDropDown then
  begin
    { Edit text with _ cursor marker — always left-aligned }
    if FEditCursor >= InnerW then
      Scroll := FEditCursor - InnerW + 1;
    Display := CopyNeutral(FEditText, Scroll, InnerW);
    if FEditCursor - Scroll < Length(Display) then
      Display[FEditCursor - Scroll + 1] := '_'
    else
      Display := Display + '_';
    if Length(Display) < InnerW then
      Display := Display + StringOfChar(' ', InnerW - Length(Display));
  end
  else
  begin
    if (FSelectedIndex >= 0) and (FSelectedIndex < FItems.Count) then
      Display := FItems[FSelectedIndex]
    else
      Display := '';
    if Length(Display) > InnerW then
      Display := Copy(Display, 1, InnerW - 1) + '~';
    { Apply alignment padding }
    Pad := InnerW - Length(Display);
    case FTextAlign of
      taLeft:   begin PadL := 0;          PadR := Pad;               end;
      taRight:  begin PadL := Pad;        PadR := 0;                 end;
      taCenter: begin PadL := Pad div 2;  PadR := Pad - Pad div 2;   end;
    end;
    Display := StringOfChar(' ', PadL) + Display + StringOfChar(' ', PadR);
  end;

  Term.WriteStr(Display);
  Term.WriteStr(' ');

  { invert only for plain ASCII v/V — Unicode arrows are self-explanatory }
  if LowerCase(DC(dcComboArrow)) = 'v' then
  begin
    Term.SetFG(InvFG);
    Term.SetBG(InvBG);
  end;
  Term.WriteStr(DC(dcComboArrow));

  { closing bracket back to normal colors }
  Term.SetFG(CFG);
  Term.SetBG(CBG);
  Term.WriteStr(DC(dcComboRight));

  Term.ResetColors;

  { Cursor: hidden in csFixed (never editable); in csDropDown position at edit
    cursor so the OS cursor blinks in the right place for inline editing. }
  if FStyle = csDropDown then
  begin
    CursorCol := 2 + (FEditCursor - Scroll);
    GotoLocal(CursorCol, 1);
    Term.ShowCursor;
  end
  else
    Term.HideCursor;
end;

function TComboBox.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  Result := True;
  case Key.Code of
    kcEnter, kcDown:
      OpenDropdown;

    kcChar:
      if FStyle = csDropDown then
      begin
        if Key.Ch = ' ' then
          OpenDropdown
        else if Key.Ch >= ' ' then
        begin
          InsertNeutral(FEditText, Key.Ch, FEditCursor);
          Inc(FEditCursor, System.Length(string(Key.Ch)));
          Invalidate;
          OpenDropdown;
        end
        else Result := False;
      end
      else
      begin
        if Key.Ch = ' ' then OpenDropdown
        else Result := False;
      end;

    kcBackspace:
      if (FStyle = csDropDown) and (FEditCursor > 0) then
      begin
        DeleteNeutral(FEditText, FEditCursor - 1, 1);
        Dec(FEditCursor);
        Invalidate;
      end
      else Result := False;

    kcLeft:
      if (FStyle = csDropDown) and (FEditCursor > 0) then
        begin Dec(FEditCursor); Invalidate; end
      else Result := False;

    kcRight:
      if (FStyle = csDropDown) and (FEditCursor < Length(FEditText)) then
        begin Inc(FEditCursor); Invalidate; end
      else Result := False;

    kcHome:
      if FStyle = csDropDown then
        begin FEditCursor := 0; Invalidate; end
      else Result := False;

    kcEnd:
      if FStyle = csDropDown then
        begin FEditCursor := Length(FEditText); Invalidate; end
      else Result := False;

  else
    Result := False;
  end;
end;

end.
