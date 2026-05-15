{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Menu;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, fgl,
  TermUI.StringUtils,
  TermUI.Terminal, TermUI.Control, TermUI.Forms, TermUI.Application;

type
  TMenuItemKind = (mikNormal, mikHeader, mikSeparator, mikRadio, mikCheck, mikSubmenu);

  TMenuItem = class;
  TMenuItemList = specialize TFPGObjectList<TMenuItem>;

  TMenuItem = class
  public
    Kind:    TMenuItemKind;
    Label_:  string;
    Value:   string;
    Hint:    string;   // gray suffix shown after the label (headers only)
    Desc:    string;   // one-line description shown in the status bar when selected
    Hotkey:  Char;     // #0 = none
    Enabled: Boolean;
    DimItem:  Boolean;  // render label+value in dim/gray (e.g. inactive modules)
    DimValue: Boolean;  // render value only in dim/gray (e.g. "(none)")
    MarkOld:  Boolean;  // render value in yellow (e.g. older available versions)
    Checked:  Boolean;  // checked state for mikCheck and mikRadio items
    GroupTag: Integer;  // radio group ID; items with the same GroupTag in the same
                        // list are mutually exclusive (0 = ungrouped)
    SubItems: TMenuItemList;  // owned; non-nil only for mikSubmenu items
    Action:  TNotifyEvent;
    constructor Create(const ALabel: string; AAction: TNotifyEvent = nil;
      const AValue: string = ''; AHotkey: Char = #0; AHint: String = '');
    constructor CreateEmbeddedHotkey(const ALabel: string; AAction: TNotifyEvent = nil;
      const AValue: string = ''; AHint: String = '');
    constructor CreateHeader(const ALabel: string);
    constructor CreateSeparator;
    { Creates a radio button item.  AGroupTag groups mutually exclusive items. }
    constructor CreateRadio(const ALabel: string; AGroupTag: Integer;
      AAction: TNotifyEvent = nil; AChecked: Boolean = False);
    { Creates a checkbox item. }
    constructor CreateCheck(const ALabel: string; AAction: TNotifyEvent = nil;
      AChecked: Boolean = False);
    { Creates a submenu item.  Populate SubItems after construction. }
    constructor CreateSubmenu(const ALabel: string; AHotkey: Char = #0);
    destructor Destroy; override;
  end;

  { A single page of menu items with keyboard navigation.
    Extends TForm so it integrates with TApplication.ShowModal. }
  TMenu = class(TForm)
  private
    FItems:          TMenuItemList;
    FSel:            Integer;
    FScrollOff:      Integer;
    FHeaderRows:     Integer;
    FFooterRows:     Integer;
    FSelectedItem:   TMenuItem;  // set by DoKeyDown before calling Close
    FExitedLeft:     Boolean;  // True when Run returned nil via Left arrow (not Esc/Q)
    FUnhandledChar:  Char;     // Set when a char key wasn't consumed; #0 otherwise
    FDeletePressed:  Boolean;  // True when Del was pressed on the current selection
    FHelpDoc:        string;

    function Selectable(I: Integer): Boolean;
    function NextSel(From, Dir: Integer): Integer;
    function VisibleRows: Integer;
    procedure DrawItem(I: Integer; Full: Boolean);
    procedure DrawHelp;
    procedure EnsureVisible;
    procedure Draw;
    procedure HandleKey(const K: TKeyEvent);
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
  public
    constructor Create(const ATitle: string = ''); override;
    destructor Destroy; override;

    procedure Add(AItem: TMenuItem);
    procedure AddSeparator;
    procedure AddHeader(const ALabel: string);
    procedure SelectByLabel(const ALabel: string);

    { Returns selected item, or nil on back/quit.
      Check ExitedLeft to distinguish Left-arrow back from Esc.
      Internally calls Application.ShowModal(Self). }
    function Run: TMenuItem;

    property Items:         TMenuItemList read FItems;
    property Selected:      Integer       read FSel;
    property SelectedItem:  TMenuItem     read FSelectedItem;
    property ExitedLeft:    Boolean       read FExitedLeft;
    property UnhandledChar: Char          read FUnhandledChar;
    property DeletePressed: Boolean       read FDeletePressed;
    { Help document name for F1 (e.g. 'build', 'project'). Empty = no help. }
    property HelpDoc:       string        read FHelpDoc        write FHelpDoc;
    { Label of the currently highlighted item; empty when nothing is selected. }
    function SelectedLabel: string;
    { Screen row (1-based) of the currently selected item, for in-place editing. }
    function SelectedRow: Integer;
  end;

  { Inline single-line text editor.  ARow=0 uses the vertical centre of the screen. }
  function EditLine(const APrompt, ACurrent: string; var AResult: string;
    ARow: Integer = 0): Boolean;

  { Confirmation prompt at the bottom of the screen. Default is No unless ADefault=True. }
  function Confirm(const AMsg: string; ADefault: Boolean = False): Boolean;

  { Write an ephemeral error/info line at Term.Height-1, wait for a key. }
  procedure ShowStatusMsg(const S: string; AColor: TColor);

  { Drawing helpers used by PathPicker and app-side code. }
  procedure DrawHeader(const Breadcrumb: string; Row: Integer);
  procedure DrawRule(Row, Col, Width: Integer);
  function  PadRight(const S: string; Width: Integer): string;
  function  JoinTruncated(AList: TStrings; const Sep: string; MaxLen: Integer): string;
  function  IsValidIdentifier(const S: string): Boolean;

var
  AppTitle:   string = 'TermUI';
  AppVersion: string = '';

implementation

{ ══════════════════════════════════════════════════════════════════════
  Layout constants
  ══════════════════════════════════════════════════════════════════════ }

const
  COL_LABEL_W = 20;
  HELP_TEXT   = ' ↑↓ Navigate   Enter Select   Esc Back   ^S Save   ^X Save+Exit   ^C Quit   F1 Help   F2 About ';

{ ══════════════════════════════════════════════════════════════════════
  Colour helpers
  ══════════════════════════════════════════════════════════════════════ }

procedure ColorTitle;   begin Term.SetFG(clBrightCyan);    Term.SetBG(clDefault); end;
procedure ColorNormal;  begin Term.ResetColors; end;
procedure ColorHeader;  begin Term.SetFG(clBrightYellow); end;
procedure ColorSelFG;   begin Term.SetFG(clBlack); Term.SetBG(clCyan); end;
procedure ColorRule;    begin Term.SetFG(clBrightBlack); end;
procedure ColorValue;   begin Term.SetFG(clGreen); end;
procedure ColorDim;     begin Term.SetFG(clBrightBlack); end;
procedure ColorHelp;    begin Term.SetFG(clBrightBlack); end;
procedure ColorHotkey;  begin Term.SetFG(clBrightCyan); end;
procedure ColorSearch;  begin Term.SetFG(clWhite); Term.SetBG(clBlue); end;

{ ══════════════════════════════════════════════════════════════════════
  Low-level drawing helpers
  ══════════════════════════════════════════════════════════════════════ }

procedure DrawRule(Row, Col, Width: Integer);
var
  I: Integer;
begin
  Term.GotoXY(Col, Row);
  ColorRule;
  for I := 1 to Width do
    Term.WriteStr('-');
  Term.ResetColors;
end;

{ Build a compact summary: items joined by Sep, truncated with '…' to MaxLen chars. }
function JoinTruncated(AList: TStrings; const Sep: string; MaxLen: Integer): string;
var
  I: Integer;
  S: string;
begin
  Result := '';
  for I := 0 to AList.Count - 1 do
  begin
    if Result = '' then
      S := AList[I]
    else
      S := Result + Sep + AList[I];
    if Length(S) > MaxLen then
    begin
      Result := CopyNeutral(Result, 0, MaxLen - 1) + '…';
      Exit;
    end;
    Result := S;
  end;
end;

{ Write an ephemeral error/info line at Term.Height-1, wait for a key.
  Invalidates the front buffer first so the overlay is guaranteed to appear
  even when an inline editor has left the buffer in a partially-flushed state. }
procedure ShowStatusMsg(const S: string; AColor: TColor);
begin
  Term.InvalidateFront;
  Term.GotoXY(1, Term.Height - 1);
  Term.ClearToEOL;
  Term.SetFG(AColor);
  Term.WriteStr(' ' + S);
  Term.ResetColors;
  Term.FlushOutput;
  Term.ReadKey;
end;

{ Returns True if S is a valid compiler define/profile identifier:
  A-Z, a-z, _ plus digits (not as first character). No spaces. }
function IsValidIdentifier(const S: string): Boolean;
var I: Integer;
begin
  Result := False;
  if S = '' then Exit;
  if not (S.Index[0] in ['A'..'Z', 'a'..'z', '_']) then Exit;
  for I := 2 to Length(S) do
    if not (S[I] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) then Exit;
  Result := True;
end;

procedure DrawHeader(const Breadcrumb: string; Row: Integer);
var
  W, TitleLen, MaxBC, BCLen: Integer;
  BC: string;
begin
  W := Term.Width;
  Term.GotoXY(1, Row);
  Term.ClearToEOL;
  ColorTitle;
  Term.WriteStr(' ' + AppTitle + ' ');
  ColorNormal;
  if Breadcrumb <> '' then
  begin
    TitleLen := Length(AppTitle) + 2;  // leading space + trailing space
    MaxBC    := W - TitleLen - 2;       // 2 for '[' and ']'
    BC       := Breadcrumb;
    BCLen    := Length(BC);
    if BCLen > MaxBC then
    begin
      BC    := '…' + CopyNeutral(BC, BCLen - MaxBC + 1, MaxBC - 1);
    end;
    Term.SetFG(clBrightBlack);
    Term.WriteStr('[');
    Term.SetFG(clCyan);
    Term.WriteStr(BC);
    Term.SetFG(clBrightBlack);
    Term.WriteStr(']');
  end;
  Term.ResetColors;
  DrawRule(Row + 1, 1, W);
end;

{ Write ALabel into a field of AWidth columns, highlighting the hotkey letter. }
procedure WriteLabelWithHotkey(const ALabel: string; AHotkey: Char;
  IsSel: Boolean; AWidth: Integer);
var
  HKPos, Written, I: Integer;
begin
  HKPos := -1;
  if AHotkey <> #0 then
    PosNeutral(UpCase(AHotkey), UpperCase(ALabel), HKPos);

  Written := 0;
  if HKPos >= 0 then
  begin
    for I := 0 to Length(ALabel) - 1 do
    begin
      if I = HKPos then
      begin
        { Hotkey letter: underline + colour; colour alone on platforms without underline }
        ColorHotkey;
        Term.SetUnderline(True);
        Term.WriteStr(ALabel.Index[I]);
        Term.SetUnderline(False);
        if IsSel then ColorSelFG else ColorNormal;
      end
      else
        Term.WriteStr(ALabel.Index[I]);
      Inc(Written);
    end;
  end
  else
  begin
    Term.WriteStr(ALabel);
    Written := Length(ALabel);
  end;
  { Pad to field width }
  while Written < AWidth do
  begin
    Term.WriteStr(' ');
    Inc(Written);
  end;
end;

function PadRight(const S: string; Width: Integer): string;
begin
  Result := S;
  while Length(Result) < Width do
    Result := Result + ' ';
  if Length(Result) > Width then
    Result := CopyNeutral(Result, 0, Width);
end;

{ ══════════════════════════════════════════════════════════════════════
  TMenuItem
  ══════════════════════════════════════════════════════════════════════ }

constructor TMenuItem.Create(const ALabel: string; AAction: TNotifyEvent = nil;
  const AValue: string = ''; AHotkey: Char = #0; AHint: String = '');
begin
  inherited Create;
  Kind    := mikNormal;
  Label_  := ALabel;
  Value   := AValue;
  Hint    := AHint;
  Hotkey  := AHotkey;
  Enabled := True;
  DimItem := False;
  MarkOld := False;
  Action  := AAction;
end;

constructor TMenuItem.CreateEmbeddedHotkey(
  const ALabel: string;
  AAction: TNotifyEvent;
  const AValue: string;
  AHint: string
);
var
  HotkeyPos: Integer;
  CleanLabel: string;
  HotkeyChar: Char;
begin
  if not PosNeutral('&', ALabel, HotkeyPos) then
    HotkeyPos := -1;

  if (HotkeyPos >= 0) and (HotkeyPos < Length(ALabel) - 1) then
  begin
    CleanLabel := ALabel;
    DeleteNeutral(CleanLabel, HotkeyPos, 1);
    HotkeyChar := UpCase(CleanLabel.Index[HotkeyPos]);
  end
  else
  begin
    CleanLabel := ALabel;
    HotkeyChar := #0;
  end;

  Create(CleanLabel, AAction, AValue, HotkeyChar, AHint);
end;

constructor TMenuItem.CreateHeader(const ALabel: string);
begin
  inherited Create;
  Kind    := mikHeader;
  Label_  := ALabel;
  Hint    := '';
  Enabled := False;
end;

constructor TMenuItem.CreateSeparator;
begin
  inherited Create;
  Kind    := mikSeparator;
  Enabled := False;
end;

constructor TMenuItem.CreateRadio(const ALabel: string; AGroupTag: Integer;
  AAction: TNotifyEvent; AChecked: Boolean);
begin
  inherited Create;
  Kind     := mikRadio;
  Label_   := ALabel;
  Hotkey   := #0;
  Enabled  := True;
  Checked  := AChecked;
  GroupTag := AGroupTag;
  Action   := AAction;
end;

constructor TMenuItem.CreateCheck(const ALabel: string; AAction: TNotifyEvent;
  AChecked: Boolean);
begin
  inherited Create;
  Kind     := mikCheck;
  Label_   := ALabel;
  Hotkey   := #0;
  Enabled  := True;
  Checked  := AChecked;
  GroupTag := 0;
  Action   := AAction;
end;

constructor TMenuItem.CreateSubmenu(const ALabel: string; AHotkey: Char);
begin
  inherited Create;
  Kind     := mikSubmenu;
  Label_   := ALabel;
  Hotkey   := AHotkey;
  Enabled  := True;
  SubItems := TMenuItemList.Create(True);
end;

destructor TMenuItem.Destroy;
begin
  SubItems.Free;
  inherited;
end;

{ ══════════════════════════════════════════════════════════════════════
  TMenu
  ══════════════════════════════════════════════════════════════════════ }

constructor TMenu.Create(const ATitle: string);
begin
  inherited Create(ATitle);
  FItems      := TMenuItemList.Create(True);
  FSel        := -1;
  FScrollOff  := 0;
  FHeaderRows := 3;  // title row + rule + blank
  FFooterRows := 3;  // desc + rule + help
end;

destructor TMenu.Destroy;
begin
  FItems.Free;
  inherited;
end;

procedure TMenu.Add(AItem: TMenuItem);
begin
  FItems.Add(AItem);
  if (FSel < 0) and Selectable(FItems.Count - 1) then
    FSel := FItems.Count - 1;
end;

procedure TMenu.AddSeparator;
begin
  FItems.Add(TMenuItem.CreateSeparator);
end;

procedure TMenu.AddHeader(const ALabel: string);
begin
  FItems.Add(TMenuItem.CreateHeader(ALabel));
end;

procedure TMenu.SelectByLabel(const ALabel: string);
var
  I: Integer;
begin
  for I := 0 to FItems.Count - 1 do
    if Selectable(I) and (FItems[I].Label_ = ALabel) then
    begin
      FSel := I;
      EnsureVisible;
      Exit;
    end;
end;

function TMenu.Selectable(I: Integer): Boolean;
begin
  Result := (I >= 0) and (I < FItems.Count) and
            (FItems[I].Kind in [mikNormal, mikRadio, mikCheck, mikSubmenu]) and FItems[I].Enabled;
end;

function TMenu.NextSel(From, Dir: Integer): Integer;
var
  I, Tries: Integer;
begin
  Result := From;
  I := From + Dir;
  Tries := 0;
  while Tries < FItems.Count do
  begin
    if I < 0 then I := FItems.Count - 1;
    if I >= FItems.Count then I := 0;
    if Selectable(I) then
    begin
      Result := I;
      Exit;
    end;
    Inc(I, Dir);
    Inc(Tries);
  end;
end;

function TMenu.VisibleRows: Integer;
begin
  Result := Term.Height - FHeaderRows - FFooterRows - 1;
  if Result < 1 then Result := 1;
end;

procedure TMenu.EnsureVisible;
var
  VR: Integer;
begin
  VR := VisibleRows;
  if FSel < FScrollOff then
    FScrollOff := FSel
  else if FSel >= FScrollOff + VR then
    FScrollOff := FSel - VR + 1;
end;

function TMenu.SelectedLabel: string;
begin
  if (FSel >= 0) and (FSel < FItems.Count) then
    Result := FItems[FSel].Label_
  else
    Result := '';
end;

function TMenu.SelectedRow: Integer;
begin
  Result := FHeaderRows + 1 + (FSel - FScrollOff);
  if Result < 1 then Result := 1;
  if Result > Term.Height then Result := Term.Height;
end;

procedure TMenu.DrawItem(I: Integer; Full: Boolean);
var
  Row:    Integer;
  Item:   TMenuItem;
  IsSel:  Boolean;
  LabelW: Integer;
begin
  if (I < FScrollOff) or (I >= FScrollOff + VisibleRows) then Exit;
  Row  := FHeaderRows + 1 + (I - FScrollOff);
  Item := FItems[I];
  IsSel := (I = FSel);

  Term.GotoXY(1, Row);
  Term.ClearToEOL;

  case Item.Kind of
    mikSeparator: begin
      ColorRule;
      Term.WriteStr('  ' + StringOfChar('-', Term.Width - 4));
      Term.ResetColors;
    end;
    mikHeader: begin
      ColorHeader;
      Term.WriteStr('  ' + Item.Label_);
      if Item.Hint <> '' then
      begin
        ColorDim;
        Term.WriteStr('  ' + Item.Hint);
      end;
      Term.ResetColors;
    end;
    mikNormal, mikRadio, mikCheck: begin
      if IsSel then
      begin
        ColorSelFG;
        Term.WriteStr(' > ');
      end
      else
      begin
        if Item.DimItem then ColorDim else ColorNormal;
        Term.WriteStr('   ');
      end;
      { Radio / check glyph }
      if Item.Kind = mikRadio then
      begin
        if IsSel then Term.SetFG(clBlack) else Term.SetFG(clBrightCyan);
        if Item.Checked then Application.DrawChar(dcRadioOn)
        else                 Application.DrawChar(dcRadioOff);
        Term.WriteStr(' ');
        if IsSel then ColorSelFG else ColorNormal;
      end
      else if Item.Kind = mikCheck then
      begin
        if IsSel then Term.SetFG(clBlack) else Term.SetFG(clBrightCyan);
        if Item.Checked then Application.DrawChar(dcCheckOn)
        else                 Application.DrawChar(dcCheckOff);
        Term.WriteStr(' ');
        if IsSel then ColorSelFG else ColorNormal;
      end;
      { Write label, highlighting the hotkey letter in place }
      if (not IsSel) and Item.DimItem then
      begin
        ColorDim;
        Term.WriteStr(Item.Label_);
        Term.ResetColors;
      end
      else
        WriteLabelWithHotkey(Item.Label_, Item.Hotkey, IsSel, COL_LABEL_W);
      if Item.Value <> '' then
      begin
        if IsSel then
          Term.SetFG(clBlack)
        else if Item.DimItem or Item.DimValue then
          ColorDim
        else if Item.MarkOld then
          Term.SetFG(clYellow)
        else
          ColorValue;
        Term.WriteStr(' : ' + Item.Value);
      end;
      Term.ResetColors;
    end;
    mikSubmenu: begin
      if IsSel then begin ColorSelFG; Term.WriteStr(' > '); end
      else          begin ColorNormal; Term.WriteStr('   '); end;
      WriteLabelWithHotkey(Item.Label_, Item.Hotkey, IsSel, COL_LABEL_W);
      { Arrow indicator on the right }
      if IsSel then Term.SetFG(clBlack) else Term.SetFG(clBrightCyan);
      Application.DrawChar(dcArrowRight);
      Term.ResetColors;
    end;
  end;
end;

procedure TMenu.DrawHelp;
var
  Row:     Integer;
  VerStr:  string;
  Avail:   Integer;
  Desc:    string;
  DescMax: Integer;
begin
  Row := Term.Height;

  { Description row — one line above the rule }
  Term.GotoXY(1, Row - 2);
  Term.ClearToEOL;
  Desc := '';
  if (FSel >= 0) and (FSel < FItems.Count) then
    Desc := FItems[FSel].Desc;
  if Desc <> '' then
  begin
    Term.SetFG(clBrightBlack);
    DescMax := Term.Width - 2;
    if Length(Desc) > DescMax then
      Desc := CopyNeutral(Desc, 0, DescMax - 1) + '…';
    Term.WriteStr(' ' + Desc);
    Term.ResetColors;
  end;

  DrawRule(Row - 1, 1, Term.Width);
  Term.GotoXY(1, Row);
  Term.ClearToEOL;
  ColorHelp;
  Term.WriteStr(HELP_TEXT);
  VerStr := AppVersion + ' ';
  Avail  := Term.Width - Length(HELP_TEXT) - Length(VerStr);
  if Avail >= 0 then
  begin
    Term.GotoXY(Term.Width - Length(VerStr) + 1, Row);
    Term.WriteStr(VerStr);
  end;
  Term.ResetColors;
end;

procedure TMenu.DoPaint;
var
  I: Integer;
begin
  Term.HideCursor;
  Term.ClearScreen;
  DrawHeader(Title, 1);
  for I := FScrollOff to FScrollOff + VisibleRows - 1 do
    if I < FItems.Count then
      DrawItem(I, True);
  DrawHelp;
  inherited DoPaint;
end;

procedure TMenu.Draw;
begin
  Paint;
  Term.FlushOutput;
end;

{ Move the selection, repaint only the changed lines (or full redraw on scroll). }
procedure TMenu.HandleKey(const K: TKeyEvent);
var
  OldSel, OldScroll: Integer;
begin
  OldSel    := FSel;
  OldScroll := FScrollOff;

  case K.Code of
    kcUp:     FSel := NextSel(FSel, -1);
    kcDown:   FSel := NextSel(FSel, +1);
    kcPageUp: begin
      FSel := FSel - VisibleRows;
      if FSel < 0 then FSel := 0;
      FSel := NextSel(FSel - 1, +1);
    end;
    kcPageDown: begin
      FSel := FSel + VisibleRows;
      if FSel >= FItems.Count then FSel := FItems.Count - 1;
      FSel := NextSel(FSel + 1, -1);
    end;
    kcHome: FSel := NextSel(-1, +1);
    kcEnd:  FSel := NextSel(FItems.Count, -1);
  end;

  EnsureVisible;

  if FScrollOff <> OldScroll then
    Draw
  else if FSel <> OldSel then
  begin
    DrawItem(OldSel, False);
    DrawItem(FSel, False);
    DrawHelp;
    Term.FlushOutput;
  end;
end;

function TMenu.DoKeyDown(var Key: TKeyEvent): Boolean;
var
  Item: TMenuItem;
begin
  Result := True;
  case Key.Code of
    kcEnter, kcRight: begin
      if Selectable(FSel) then
        FSelectedItem := FItems[FSel];
      Close(1);
    end;

    kcEscape: begin
      FExitedLeft := False;
      Close(1);
    end;

    kcLeft: begin
      FExitedLeft := True;
      Close(1);
    end;

    kcDelete: begin
      if Selectable(FSel) then
      begin
        FDeletePressed := True;
        FSelectedItem  := FItems[FSel];
      end;
      Close(1);
    end;

    kcChar: begin
      for Item in FItems do
        if Selectable(FItems.IndexOf(Item)) and
           (Item.Hotkey <> #0) and (UpCase(Item.Hotkey) = UpCase(Key.Ch)) then
        begin
          FSel          := FItems.IndexOf(Item);
          FSelectedItem := Item;
          EnsureVisible;
          Close(1);
          Exit;
        end;
      FUnhandledChar := Key.Ch;
      Close(1);
    end;

    kcUp, kcDown, kcPageUp, kcPageDown, kcHome, kcEnd:
      HandleKey(Key);

    else
      Result := False;  // unhandled — bubbles to Application.OnKeyDown
  end;
end;

{ Calls Application.ShowModal so the TApplication event loop drives input.
  Returns selected item, or nil on back/quit.
  Check ExitedLeft to distinguish Left-arrow back from Esc. }
function TMenu.Run: TMenuItem;
begin
  FSelectedItem  := nil;
  FExitedLeft    := False;
  FUnhandledChar := #0;
  FDeletePressed := False;
  ModalResult    := 0;
  Invalidate;
  Application.ShowModal(Self);
  Result := FSelectedItem;
end;

{ ══════════════════════════════════════════════════════════════════════
  TEditLineForm — inline single-line editor as a TForm
  ══════════════════════════════════════════════════════════════════════ }

type
  TEditLineForm = class(TForm)
  private
    FPrompt:    string;
    FBuf:       string;
    FCur:       Integer;
    FScroll:    Integer;
    FRow:       Integer;
    FResult:    string;
    FAccepted:  Boolean;
    FPromptLen: Integer;
    FFieldW:    Integer;

    procedure CalcScroll;
    function  WordLeft: Integer;
    function  WordRight: Integer;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
  public
    procedure SetParams(const APrompt, ACurrent: string; ARow: Integer);
    function  RunModal: Boolean;
    property  Accepted: Boolean read FAccepted;
    property  Result_:  string  read FResult;
  end;

procedure TEditLineForm.SetParams(const APrompt, ACurrent: string; ARow: Integer);
begin
  FPrompt    := APrompt;
  FBuf       := ACurrent;
  FCur       := Length(ACurrent) + 1;
  FScroll    := 0;
  FAccepted  := False;
  FResult    := '';
  if ARow <= 0 then FRow := Term.Height div 2 else FRow := ARow;
  FPromptLen := 1 + Length(APrompt) + 2;
  FFieldW    := Term.Width - FPromptLen;
  if FFieldW < 4 then FFieldW := 4;
  Invalidate;
end;

procedure TEditLineForm.CalcScroll;
var ViewCur: Integer;
begin
  ViewCur := FCur - FScroll;
  if ViewCur < 1 then FScroll := FCur - 1;
  if FCur - FScroll > FFieldW then FScroll := FCur - FFieldW;
end;

function TEditLineForm.WordLeft: Integer;
var I: Integer;
begin
  I := FCur - 1;
  while (I > 1) and (FBuf[I - 1] = ' ') do Dec(I);
  while (I > 1) and (FBuf[I - 1] <> ' ') do Dec(I);
  Result := I;
end;

function TEditLineForm.WordRight: Integer;
var I, Len: Integer;
begin
  Len := Length(FBuf);
  I   := FCur;
  while (I <= Len) and (FBuf[I] <> ' ') do Inc(I);
  while (I <= Len) and (FBuf[I] = ' ') do Inc(I);
  Result := I;
end;

procedure TEditLineForm.DoPaint;
begin
  CalcScroll;
  Term.GotoXY(1, FRow);
  Term.ClearToEOL;
  Term.SetFG(clBrightYellow);
  Term.WriteStr(' ' + FPrompt + ': ');
  Term.SetFG(clWhite);
  Term.WriteStr(CopyNeutral(FBuf, FScroll, FFieldW));
  Term.ClearToEOL;
  Term.ResetColors;
  Term.ShowCursor;
  Term.GotoXY(FPromptLen + (FCur - FScroll), FRow);
  inherited DoPaint;
end;

function TEditLineForm.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  Result := True;
  case Key.Code of
    kcEnter: begin FResult := FBuf; FAccepted := True; Close(1); end;
    kcEscape: Close(1);
    kcLeft:      begin if FCur > 1 then Dec(FCur); Invalidate; end;
    kcRight:     begin if FCur <= Length(FBuf) then Inc(FCur); Invalidate; end;
    kcHome:      begin FCur := 1;                    Invalidate; end;
    kcEnd:       begin FCur := Length(FBuf) + 1;     Invalidate; end;
    kcCtrlLeft:  begin FCur := WordLeft;              Invalidate; end;
    kcCtrlRight: begin FCur := WordRight;             Invalidate; end;
    kcBackspace:
      if FCur > 1 then begin DeleteNeutral(FBuf, FCur - 2, 1); Dec(FCur); Invalidate; end;
    kcDelete:
      if FCur <= Length(FBuf) then begin DeleteNeutral(FBuf, FCur - 1, 1); Invalidate; end;
    kcChar:
      if Key.Ch >= ' ' then begin Insert(Key.Ch, FBuf, FCur); Inc(FCur); Invalidate; end;
    else
      Result := False;
  end;
end;

function TEditLineForm.RunModal: Boolean;
begin
  FAccepted := False;
  ModalResult := 0;
  Application.ShowModal(Self);
  Term.HideCursor;
  Term.ResetColors;
  Result := FAccepted;
end;

{ ══════════════════════════════════════════════════════════════════════
  EditLine — wrapper around TEditLineForm
  ══════════════════════════════════════════════════════════════════════ }

function EditLine(const APrompt, ACurrent: string; var AResult: string;
  ARow: Integer = 0): Boolean;
var
  Form: TEditLineForm;
begin
  Form := TEditLineForm.Create;
  try
    Form.SetParams(APrompt, ACurrent, ARow);
    Result := Form.RunModal;
    if Result then AResult := Form.Result_;
  finally
    Form.Free;
  end;
end;

{ ══════════════════════════════════════════════════════════════════════
  TConfirmForm — yes/no prompt as a TForm
  ══════════════════════════════════════════════════════════════════════ }

type
  TConfirmForm = class(TForm)
  private
    FMsg:     string;
    FDefault: Boolean;
    FResult:  Boolean;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
  public
    procedure SetParams(const AMsg: string; ADefault: Boolean);
    function  RunModal: Boolean;
    property  Result_: Boolean read FResult;
  end;

procedure TConfirmForm.SetParams(const AMsg: string; ADefault: Boolean);
begin
  FMsg     := AMsg;
  FDefault := ADefault;
  FResult  := ADefault;
  Invalidate;
end;

procedure TConfirmForm.DoPaint;
var Options: string;
begin
  if FDefault then Options := '(yes/no) [Y]' else Options := '(yes/no) [N]';
  Term.InvalidateFront;
  Term.GotoXY(1, Term.Height - 1);
  Term.ClearToEOL;
  ColorHelp;
  Term.WriteStr(' ' + FMsg + ' ' + Options + ': ');
  Term.ResetColors;
  Term.ShowCursor;
  Term.GotoXY(2 + Length(FMsg) + 1 + Length(Options) + 2, Term.Height - 1);
  inherited DoPaint;
end;

function TConfirmForm.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  Result := True;
  case Key.Code of
    kcEnter:  begin FResult := FDefault; Close(1); end;
    kcEscape: begin FResult := False;    Close(1); end;
    kcChar:
      case UpCase(Key.Ch) of
        'Y': begin FResult := True;  Close(1); end;
        'N': begin FResult := False; Close(1); end;
        else Result := False;
      end;
    else
      Result := False;
  end;
end;

function TConfirmForm.RunModal: Boolean;
begin
  FResult := FDefault;
  ModalResult := 0;
  Application.ShowModal(Self);
  Term.HideCursor;
  Result := FResult;
end;

{ ══════════════════════════════════════════════════════════════════════
  Confirm — wrapper around TConfirmForm
  ══════════════════════════════════════════════════════════════════════ }

function Confirm(const AMsg: string; ADefault: Boolean = False): Boolean;
var
  Form: TConfirmForm;
begin
  Form := TConfirmForm.Create;
  try
    Form.SetParams(AMsg, ADefault);
    Result := Form.RunModal;
  finally
    Form.Free;
  end;
end;

end.
