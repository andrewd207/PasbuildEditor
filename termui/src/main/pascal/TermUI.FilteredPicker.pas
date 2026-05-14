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
  Classes, SysUtils, fgl,
  TermUI.StringUtils,
  TermUI.Terminal, TermUI.Control, TermUI.Forms, TermUI.Application, TermUI.Menu;

type
  TFilteredPickerItem = class
    Label_: string;  { primary value — returned on confirm, searched }
    Desc:   string;  { description shown alongside, searched but not returned }
    constructor Create(const ALabel, ADesc: string);
  end;

  TFilteredPickerItemList = specialize TFPGObjectList<TFilteredPickerItem>;

  { Full-screen filtered picker form.
    Use RunFilteredPicker for a one-shot call, or RunModal for explicit control. }
  TFilteredPicker = class(TForm)
  private
    FPickerItems:  TFilteredPickerItemList;   // not owned
    FBuf:          string;
    FCur:          Integer;
    FSel:          Integer;
    FTopRow:       Integer;
    FStaged:       Boolean;
    FFiltered:     array of Integer;
    FFilterCount:  Integer;
    FResult:       string;
    FAccepted:     Boolean;

    procedure RebuildFilter;
    function  VisibleRows: Integer;
    procedure EnsureVisible;
    procedure DrawFilterBar;
    procedure DrawList;
    procedure DrawFooter;
    procedure PlaceCursor;
    procedure RefreshAll;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
  public
    constructor Create(const ATitle: string = ''); override;

    { Populate items (not owned by the picker). }
    procedure SetItems(AItems: TFilteredPickerItemList;
      const AInitialValue: string = '');

    { Run as modal; returns True and sets Result on confirm. }
    function RunModal: Boolean;

    property Accepted: Boolean read FAccepted;
    property Result_:  string  read FResult;
  end;

{ Full-screen filtered picker — one-shot helper.
  Returns True on confirm with AResult set to the label value. }
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

{ ══════════════════════════════════════════════════════════════════════
  TFilteredPicker
  ══════════════════════════════════════════════════════════════════════ }

constructor TFilteredPicker.Create(const ATitle: string);
begin
  inherited Create(ATitle);
  FCur          := 1;
  FSel          := 0;
  FTopRow       := 0;
  FStaged       := False;
  FFilterCount  := 0;
  FAccepted     := False;
end;

procedure TFilteredPicker.SetItems(AItems: TFilteredPickerItemList;
  const AInitialValue: string);
begin
  FPickerItems := AItems;
  FBuf         := AInitialValue;
  FCur         := Length(AInitialValue) + 1;
  FSel         := 0;
  FTopRow      := 0;
  FStaged      := False;
  FAccepted    := False;
  FResult      := '';
  RebuildFilter;
  Invalidate;
end;

procedure TFilteredPicker.RebuildFilter;
var
  Lo: string;
  It: TFilteredPickerItem;
  J:  Integer;
begin
  if FPickerItems = nil then
  begin
    FFilterCount := 0;
    SetLength(FFiltered, 0);
    Exit;
  end;
  Lo           := LowerCase(FBuf);
  FFilterCount := 0;
  SetLength(FFiltered, FPickerItems.Count);
  for J := 0 to FPickerItems.Count - 1 do
  begin
    It := FPickerItems[J];
    if (Lo = '') or
       PosNeutral(Lo, LowerCase(It.Label_)) or
       PosNeutral(Lo, LowerCase(It.Desc)) then
    begin
      FFiltered[FFilterCount] := J;
      Inc(FFilterCount);
    end;
  end;
  SetLength(FFiltered, FFilterCount);
  if FSel >= FFilterCount then FSel := FFilterCount - 1;
  if FSel < 0 then FSel := 0;
  if FTopRow > FSel then FTopRow := FSel;
end;

function TFilteredPicker.VisibleRows: Integer;
begin
  Result := Term.Height - HEADER_ROWS - FOOTER_ROWS;
  if Result < 1 then Result := 1;
end;

procedure TFilteredPicker.EnsureVisible;
var VR: Integer;
begin
  VR := VisibleRows;
  if FSel < FTopRow then FTopRow := FSel
  else if FSel >= FTopRow + VR then FTopRow := FSel - VR + 1;
end;

procedure TFilteredPicker.DrawFilterBar;
var
  PromptStr: string;
  FieldW, Scroll: Integer;
  Visible_: string;
begin
  PromptStr := ' Search: ';
  FieldW    := Term.Width - Length(PromptStr) - 1;
  if FieldW < 4 then FieldW := 4;
  Scroll := 0;
  if FCur > FieldW then
    Scroll := FCur - FieldW;
  Term.GotoXY(1, 3);
  Term.ClearToEOL;
  Term.SetFG(clBrightYellow);
  Term.WriteStr(PromptStr);
  if FStaged then Term.SetFG(clBrightGreen) else Term.SetFG(clWhite);
  Visible_ := CopyNeutral(FBuf, Scroll, FieldW);
  Term.WriteStr(Visible_);
  Term.ClearToEOL;
  DrawRule(4, 1, Term.Width);
  Term.ResetColors;
end;

procedure TFilteredPicker.DrawList;
var
  J, Row, Idx, LabelW, DescW: Integer;
  It: TFilteredPickerItem;
  IsSel: Boolean;
  LabelStr, DescStr: string;
  VR: Integer;
begin
  if FPickerItems = nil then Exit;
  VR := VisibleRows;
  for J := 0 to VR - 1 do
  begin
    Row := HEADER_ROWS + 1 + J;
    Term.GotoXY(1, Row);
    Term.ClearToEOL;
    Idx := FTopRow + J;
    if Idx >= FFilterCount then Continue;
    It    := FPickerItems[FFiltered[Idx]];
    IsSel := (Idx = FSel);
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
    LabelStr := It.Label_;
    LabelW   := COL_FLAG_W;
    if Length(LabelStr) > LabelW then
      LabelStr := CopyNeutral(LabelStr, 0, LabelW);
    while Length(LabelStr) < LabelW do LabelStr := LabelStr + ' ';
    Term.WriteStr(LabelStr);
    DescW   := Term.Width - 3 - LabelW - 2;
    DescStr := It.Desc;
    if DescW > 0 then
    begin
      if not IsSel then Term.SetFG(clBrightBlack);
      Term.WriteStr('  ');
      if Length(DescStr) > DescW then
        DescStr := CopyNeutral(DescStr, 0, DescW - 1) + '…';
      Term.WriteStr(DescStr);
    end;
    Term.ResetColors;
  end;
end;

procedure TFilteredPicker.DrawFooter;
var
  HintStr: string;
begin
  Term.GotoXY(1, Term.Height - 2);
  Term.ClearToEOL;
  if FStaged and (FFilterCount > 0) then
  begin
    Term.SetFG(clBrightBlack);
    HintStr := ' Enter again to confirm: ' + FPickerItems[FFiltered[0]].Label_;
    if Length(HintStr) > Term.Width - 1 then
      HintStr := CopyNeutral(HintStr, 0, Term.Width - 2) + '…';
    Term.WriteStr(HintStr);
  end;
  DrawRule(Term.Height - 1, 1, Term.Width);
  Term.GotoXY(1, Term.Height);
  Term.ClearToEOL;
  Term.SetFG(clBrightBlack);
  Term.WriteStr(HELP_FP);
  Term.ResetColors;
end;

procedure TFilteredPicker.PlaceCursor;
var
  PromptStr: string;
  FieldW, ViewCur: Integer;
begin
  PromptStr := ' Search: ';
  FieldW    := Term.Width - Length(PromptStr) - 1;
  if FieldW < 4 then FieldW := 4;
  ViewCur := FCur;
  if ViewCur > FieldW then ViewCur := FieldW;
  Term.GotoXY(Length(PromptStr) + ViewCur, 3);
end;

procedure TFilteredPicker.RefreshAll;
begin
  DrawFilterBar;
  DrawList;
  DrawFooter;
  PlaceCursor;
  Term.FlushOutput;
end;

procedure TFilteredPicker.DoPaint;
begin
  Term.ClearScreen;
  DrawHeader(Title, 1);
  DrawFilterBar;
  DrawList;
  DrawFooter;
  PlaceCursor;
  inherited DoPaint;
end;

function TFilteredPicker.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  Result := True;
  case Key.Code of
    kcEscape:
      Close(1);  // FAccepted stays False

    kcUp:
      if FSel > 0 then
      begin
        Dec(FSel);
        EnsureVisible;
        RefreshAll;
      end;

    kcDown:
      if FSel < FFilterCount - 1 then
      begin
        Inc(FSel);
        EnsureVisible;
        RefreshAll;
      end;

    kcEnter:
      begin
        if FStaged or (FFilterCount = 0) then
        begin
          FResult   := FBuf;
          FAccepted := True;
          Term.HideCursor;
          Close(1);
        end
        else
        begin
          FBuf    := FPickerItems[FFiltered[FSel]].Label_;
          FCur    := Length(FBuf) + 1;
          FStaged := True;
          FSel    := 0;
          FTopRow := 0;
          RebuildFilter;
          RefreshAll;
        end;
      end;

    kcBackspace:
      if FCur > 1 then
      begin
        DeleteNeutral(FBuf, FCur - 2, 1);
        Dec(FCur);
        FStaged := False;
        FSel    := 0;
        FTopRow := 0;
        RebuildFilter;
        RefreshAll;
      end;

    kcDelete:
      if FCur <= Length(FBuf) then
      begin
        DeleteNeutral(FBuf, FCur - 1, 1);
        FStaged := False;
        FSel    := 0;
        FTopRow := 0;
        RebuildFilter;
        RefreshAll;
      end;

    kcHome:  begin FCur := 1;                  RefreshAll; end;
    kcEnd:   begin FCur := Length(FBuf) + 1;   RefreshAll; end;
    kcLeft:  begin if FCur > 1 then Dec(FCur); RefreshAll; end;
    kcRight: begin if FCur <= Length(FBuf) then Inc(FCur); RefreshAll; end;

    kcChar:
      if Key.Ch >= ' ' then
      begin
        Insert(Key.Ch, FBuf, FCur);
        Inc(FCur);
        FStaged := False;
        FSel    := 0;
        FTopRow := 0;
        RebuildFilter;
        RefreshAll;
      end;

    else
      Result := False;  // unhandled — bubbles to Application.OnKeyDown
  end;
end;

function TFilteredPicker.RunModal: Boolean;
begin
  FAccepted := False;
  ModalResult := 0;
  Term.ShowCursor;
  Application.ShowModal(Self);
  Term.HideCursor;
  Result := FAccepted;
end;

{ ══════════════════════════════════════════════════════════════════════
  Standalone helper
  ══════════════════════════════════════════════════════════════════════ }

function RunFilteredPicker(const ATitle: string;
  AItems: TFilteredPickerItemList; out AResult: string;
  const AInitialValue: string = ''): Boolean;
var
  Picker: TFilteredPicker;
begin
  Picker := TFilteredPicker.Create(ATitle);
  try
    Picker.SetItems(AItems, AInitialValue);
    Result  := Picker.RunModal;
    AResult := Picker.Result_;
  finally
    Picker.Free;
  end;
end;

end.
