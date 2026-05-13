{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.FilteredPicker;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fgl, TermUI.Terminal, TermUI.Menu;

type
  TFilteredPickerItem = class
    Label_: string;  { primary value — returned on confirm, searched }
    Desc:   string;  { description shown alongside, searched but not returned }
    constructor Create(const ALabel, ADesc: string);
  end;

  TFilteredPickerItemList = specialize TFPGObjectList<TFilteredPickerItem>;

{ Full-screen filtered picker.
  The filter bar at the top searches Label_ and Desc case-insensitively.
  First Enter on a list item copies its Label_ into the filter bar and stages it.
  Second Enter (or Enter when filter already exactly matches top result) confirms.
  If no items match, Enter confirms with whatever is in the filter bar (free-form).
  Esc/Left cancels. Returns True on confirm with AResult set to the label value.
  AInitialValue pre-fills the filter bar (useful for editing an existing value). }
function RunFilteredPicker(const ATitle: string;
  AItems: TFilteredPickerItemList; out AResult: string;
  const AInitialValue: string = ''): Boolean;

implementation

const
  HEADER_ROWS = 4;  { title+rule (DrawHeader=2), filter bar, separator rule }
  FOOTER_ROWS = 3;  { hint/desc, rule, help }
  COL_FLAG_W  = 18; { fixed width of the label column in the list }
  HELP_FP     = ' ↑↓ Navigate   Enter Select/Confirm   Esc Cancel   ^S Save   ^C Quit ';

constructor TFilteredPickerItem.Create(const ALabel, ADesc: string);
begin
  inherited Create;
  Label_ := ALabel;
  Desc   := ADesc;
end;

function RunFilteredPicker(const ATitle: string;
  AItems: TFilteredPickerItemList; out AResult: string;
  const AInitialValue: string = ''): Boolean;
var
  Buf:      string;     { current filter bar text }
  Cur:      Integer;    { cursor position in Buf (1-based) }
  Sel:      Integer;    { selected row in filtered list (0-based) }
  TopRow:   Integer;    { scroll offset into filtered list }
  Staged:   Boolean;    { true after first Enter copies a label into Buf }
  K:        TKeyEvent;

  { Indices of AItems that pass the current filter }
  Filtered: array of Integer;
  FCount:   Integer;

  procedure RebuildFilter;
  var
    Lo: string;
    It: TFilteredPickerItem;
    J:  Integer;
  begin
    Lo     := LowerCase(Buf);
    FCount := 0;
    SetLength(Filtered, AItems.Count);
    for J := 0 to AItems.Count - 1 do
    begin
      It := AItems[J];
      if (Lo = '') or
         (Pos(Lo, LowerCase(It.Label_)) > 0) or
         (Pos(Lo, LowerCase(It.Desc))   > 0) then
      begin
        Filtered[FCount] := J;
        Inc(FCount);
      end;
    end;
    SetLength(Filtered, FCount);
    if Sel >= FCount then Sel := FCount - 1;
    if Sel < 0 then Sel := 0;
    if TopRow > Sel then TopRow := Sel;
  end;

  function VisibleRows: Integer;
  begin
    Result := Term.Height - HEADER_ROWS - FOOTER_ROWS;
    if Result < 1 then Result := 1;
  end;

  procedure EnsureVisible;
  var VR: Integer;
  begin
    VR := VisibleRows;
    if Sel < TopRow then TopRow := Sel
    else if Sel >= TopRow + VR then TopRow := Sel - VR + 1;
  end;

  procedure DrawFilterBar;
  var
    PromptStr: string;
    FieldW, Scroll: Integer;
    Label_: string;
  begin
    PromptStr := ' Search: ';
    FieldW    := Term.Width - Length(PromptStr) - 1;
    if FieldW < 4 then FieldW := 4;

    Scroll := 0;
    if Cur > FieldW then
      Scroll := Cur - FieldW;

    Term.GotoXY(1, 3);
    Term.ClearToEOL;
    Term.SetFG(clBrightYellow);
    Term.WriteStr(PromptStr);
    if Staged then Term.SetFG(clBrightGreen) else Term.SetFG(clWhite);
    Label_ := Copy(Buf, Scroll + 1, FieldW);
    Term.WriteStr(Label_);
    Term.ClearToEOL;
    DrawRule(4, 1, Term.Width);
    Term.ResetColors;
  end;

  procedure DrawList;
  var
    J, Row, Idx, LabelW, DescW: Integer;
    It: TFilteredPickerItem;
    IsSel: Boolean;
    LabelStr, DescStr: string;
    VR: Integer;
  begin
    VR := VisibleRows;
    for J := 0 to VR - 1 do
    begin
      Row := HEADER_ROWS + 1 + J;
      Term.GotoXY(1, Row);
      Term.ClearToEOL;
      Idx := TopRow + J;
      if Idx >= FCount then Continue;
      It    := AItems[Filtered[Idx]];
      IsSel := (Idx = Sel);

      if IsSel then
      begin
        Term.SetFG(clBlack);
        Term.SetBG(clCyan);
        Term.WriteStr(' > ');
      end
      else
      begin
        Term.ResetColors;
        Term.WriteStr('   ');
      end;

      { Label column }
      LabelStr := It.Label_;
      LabelW   := COL_FLAG_W;
      if Length(LabelStr) > LabelW then
        LabelStr := Copy(LabelStr, 1, LabelW);
      while Length(LabelStr) < LabelW do LabelStr := LabelStr + ' ';
      Term.WriteStr(LabelStr);

      { Description column — fill remaining width }
      DescW   := Term.Width - 3 - LabelW - 2;
      DescStr := It.Desc;
      if DescW > 0 then
      begin
        if not IsSel then Term.SetFG(clBrightBlack);
        Term.WriteStr('  ');
        if Length(DescStr) > DescW then
          DescStr := Copy(DescStr, 1, DescW - 1) + '…';
        Term.WriteStr(DescStr);
      end;
      Term.ResetColors;
    end;
  end;

  procedure DrawFooter;
  var
    HintStr: string;
  begin
    Term.GotoXY(1, Term.Height - 2);
    Term.ClearToEOL;
    if Staged and (FCount > 0) then
    begin
      Term.SetFG(clBrightBlack);
      HintStr := ' Enter again to confirm: ' + AItems[Filtered[0]].Label_;
      if Length(HintStr) > Term.Width - 1 then
        HintStr := Copy(HintStr, 1, Term.Width - 2) + '…';
      Term.WriteStr(HintStr);
    end;
    DrawRule(Term.Height - 1, 1, Term.Width);
    Term.GotoXY(1, Term.Height);
    Term.ClearToEOL;
    Term.SetFG(clBrightBlack);
    Term.WriteStr(HELP_FP);
    Term.ResetColors;
  end;

  procedure PlaceCursor;
  var
    PromptStr: string;
    FieldW, Scroll, ViewCur: Integer;
  begin
    PromptStr := ' Search: ';
    FieldW    := Term.Width - Length(PromptStr) - 1;
    if FieldW < 4 then FieldW := 4;
    Scroll  := 0;
    ViewCur := Cur;
    if ViewCur > FieldW then
    begin
      Scroll  := Cur - FieldW;
      ViewCur := FieldW;
    end;
    Term.GotoXY(Length(PromptStr) + ViewCur, 3);
  end;

  procedure FullDraw;
  begin
    Term.ClearScreen;
    DrawHeader(ATitle, 1);
    DrawFilterBar;
    DrawList;
    DrawFooter;
    PlaceCursor;
    Term.FlushOutput;
  end;

  procedure RefreshAll;
  begin
    DrawFilterBar;
    DrawList;
    DrawFooter;
    PlaceCursor;
    Term.FlushOutput;
  end;

begin
  Result  := False;
  AResult := '';
  Buf     := AInitialValue;
  Cur     := Length(AInitialValue) + 1;
  Sel     := 0;
  TopRow  := 0;
  Staged  := False;
  FCount  := 0;

  RebuildFilter;
  Term.ShowCursor;
  FullDraw;

  repeat
    K := Term.ReadKey;

    if Term.HasResized then
    begin
      EnsureVisible;
      FullDraw;
      Continue;
    end;

    case K.Code of
      kcEscape:
        Exit;  { Result = False }

      kcCtrlC:
        begin
          GCtrlCRequested := True;
          Exit;
        end;

      kcCtrlS:
        begin
          GSaveRequested := True;
          Exit;
        end;

      kcCtrlX:
        begin
          GCtrlXRequested := True;
          Exit;
        end;

      kcUp:
        if Sel > 0 then
        begin
          Dec(Sel);
          EnsureVisible;
          RefreshAll;
        end;

      kcDown:
        if Sel < FCount - 1 then
        begin
          Inc(Sel);
          EnsureVisible;
          RefreshAll;
        end;

      kcEnter:
        begin
          if Staged or (FCount = 0) then
          begin
            { Second Enter or free-form: confirm }
            AResult := Buf;
            Result  := True;
            Term.HideCursor;
            Exit;
          end
          else
          begin
            { First Enter: copy selected label into filter bar, stage it }
            Buf    := AItems[Filtered[Sel]].Label_;
            Cur    := Length(Buf) + 1;
            Staged := True;
            Sel    := 0;
            TopRow := 0;
            RebuildFilter;
            RefreshAll;
          end;
        end;

      kcBackspace:
        if Cur > 1 then
        begin
          Delete(Buf, Cur - 1, 1);
          Dec(Cur);
          Staged := False;
          Sel    := 0;
          TopRow := 0;
          RebuildFilter;
          RefreshAll;
        end;

      kcDelete:
        if Cur <= Length(Buf) then
        begin
          Delete(Buf, Cur, 1);
          Staged := False;
          Sel    := 0;
          TopRow := 0;
          RebuildFilter;
          RefreshAll;
        end;

      kcHome: begin Cur := 1; RefreshAll; end;
      kcEnd:  begin Cur := Length(Buf) + 1; RefreshAll; end;

      kcLeft:  if Cur > 1 then begin Dec(Cur); RefreshAll; end;
      kcRight: if Cur <= Length(Buf) then begin Inc(Cur); RefreshAll; end;

      kcChar:
        if K.Ch >= ' ' then
        begin
          Insert(K.Ch, Buf, Cur);
          Inc(Cur);
          Staged := False;
          Sel    := 0;
          TopRow := 0;
          RebuildFilter;
          RefreshAll;
        end;
    end;
  until False;
end;

end.
