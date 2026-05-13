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
  Classes, SysUtils, StrUtils, fgl, TermUI.Terminal, TermUI.Control;

type
  TMenuItemKind = (mikNormal, mikHeader, mikSeparator);

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
    Action:  TNotifyEvent;
    constructor Create(const ALabel: string; AAction: TNotifyEvent = nil;
      const AValue: string = ''; AHotkey: Char = #0; AHint: String = '');
    constructor CreateEmbeddedHotkey(const ALabel: string; AAction: TNotifyEvent = nil;
      const AValue: string = ''; AHint: String = '');
    constructor CreateHeader(const ALabel: string);
    constructor CreateSeparator;
  end;
  TMenuItemList = specialize TFPGObjectList<TMenuItem>;

  { A single page of menu items with keyboard navigation }
  TMenu = class
  private
    FTitle:          string;
    FItems:          TMenuItemList;
    FSel:            Integer;
    FScrollOff:      Integer;
    FHeaderRows:     Integer;
    FFooterRows:     Integer;
    FExitedLeft:     Boolean;  // True when Run returned nil via Left arrow (not Esc/Q)
    FUnhandledChar:  Char;     // Set when a char key wasn't consumed; #0 otherwise
    FDeletePressed:  Boolean;  // True when Del was pressed on the current selection
    FF1Pressed:      Boolean;  // True when F1 was pressed
    FF2Pressed:      Boolean;  // True when F2 was pressed

    function Selectable(I: Integer): Boolean;
    function NextSel(From, Dir: Integer): Integer;
    function VisibleRows: Integer;
    procedure DrawItem(I: Integer; Full: Boolean);
    procedure DrawHelp;
    procedure EnsureVisible;
  public
    constructor Create(const ATitle: string);
    destructor Destroy; override;

    procedure Add(AItem: TMenuItem);
    procedure AddSeparator;
    procedure AddHeader(const ALabel: string);
    procedure SelectByLabel(const ALabel: string);

    procedure Draw;
    procedure HandleKey(const K: TKeyEvent);
    { Returns selected item, or nil on back/quit.
      Check ExitedLeft to distinguish Left-arrow back from Esc. }
    function Run: TMenuItem;

    property Title:         string        read FTitle;
    property Items:         TMenuItemList read FItems;
    property Selected:      Integer       read FSel;
    property ExitedLeft:    Boolean       read FExitedLeft;
    property UnhandledChar: Char          read FUnhandledChar;
    property DeletePressed: Boolean       read FDeletePressed;
    property F1Pressed:     Boolean       read FF1Pressed;
    property F2Pressed:     Boolean       read FF2Pressed;
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

var
  GQuitRequested:  Boolean;
  GSaveRequested:  Boolean;
  GCtrlCRequested: Boolean;
  GCtrlXRequested: Boolean;

  { Install an application-level key handler here.
    The termui widgets call this for any key they do not consume themselves.
    Return True to mark the key handled.  The handler may set GQuitRequested
    (or any other flag) to signal loops to exit. }
  GOnUnhandledKey: TKeyDownEvent;

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
      Result := Copy(Result, 1, MaxLen - 1) + '…';
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
  if not (S[1] in ['A'..'Z', 'a'..'z', '_']) then Exit;
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
      BC    := '…' + Copy(BC, BCLen - MaxBC + 2, MaxBC - 1);
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
  HKPos := 0;
  if AHotkey <> #0 then
    HKPos := Pos(UpCase(AHotkey), UpperCase(ALabel));

  Written := 0;
  if HKPos > 0 then
  begin
    for I := 1 to Length(ALabel) do
    begin
      if I = HKPos then
      begin
        { Hotkey letter: underline + colour; colour alone on platforms without underline }
        ColorHotkey;
        Term.SetUnderline(True);
        Term.WriteStr(ALabel[I]);
        Term.SetUnderline(False);
        if IsSel then ColorSelFG else ColorNormal;
      end
      else
        Term.WriteStr(ALabel[I]);
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
    Result := Copy(Result, 1, Width);
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
  HotkeyPos: SizeInt;
  CleanLabel: string;
  HotkeyChar: Char;
begin
  HotkeyPos := Pos('&', ALabel);

  if (HotkeyPos > 0) and (HotkeyPos < Length(ALabel)) then
  begin
    CleanLabel := ALabel;
    Delete(CleanLabel, HotkeyPos, 1);
    HotkeyChar := UpCase(CleanLabel[HotkeyPos]);
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

{ ══════════════════════════════════════════════════════════════════════
  TMenu
  ══════════════════════════════════════════════════════════════════════ }

constructor TMenu.Create(const ATitle: string);
begin
  inherited Create;
  FTitle      := ATitle;
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
            (FItems[I].Kind = mikNormal) and FItems[I].Enabled;
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
    mikNormal: begin
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
      Desc := Copy(Desc, 1, DescMax - 1) + '…';
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

procedure TMenu.Draw;
var
  I: Integer;
begin
  Term.HideCursor;
  Term.ClearScreen;
  DrawHeader(FTitle, 1);
  for I := FScrollOff to FScrollOff + VisibleRows - 1 do
    if I < FItems.Count then
      DrawItem(I, True);
  DrawHelp;
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

{ Block until the user selects an item or goes back.
  Returns the selected TMenuItem, or nil on Esc / Left / Q (quit sets GQuitRequested). }
function TMenu.Run: TMenuItem;
var
  K:    TKeyEvent;
  Sel:  TMenuItem;
begin
  Result         := nil;
  FExitedLeft    := False;
  FUnhandledChar := #0;
  FDeletePressed := False;
  FF1Pressed     := False;
  FF2Pressed     := False;
  Draw;
  repeat
    K := Term.ReadKey;

    if Term.HasResized then
    begin
      Draw;
      Continue;
    end;

    case K.Code of
      kcEnter, kcRight: begin
        if Selectable(FSel) then
        begin
          Result := FItems[FSel];
          Exit;
        end;
      end;

      kcEscape: begin
        FExitedLeft := False;
        Exit;
      end;
      kcLeft: begin
        FExitedLeft := True;
        Exit;
      end;

      kcDelete: begin
        if Selectable(FSel) then
        begin
          FDeletePressed := True;
          Result := FItems[FSel];
          Exit;
        end;
      end;

      kcF1: begin
        FF1Pressed := True;
        if (FSel >= 0) and (FSel < FItems.Count) then
          Result := FItems[FSel];
        Exit;
      end;

      kcF2: begin
        FF2Pressed := True;
        if (FSel >= 0) and (FSel < FItems.Count) then
          Result := FItems[FSel];
        Exit;
      end;

      kcChar: begin
        { Check item hotkeys first }
        for Sel in FItems do
          if Selectable(FItems.IndexOf(Sel)) and
             (Sel.Hotkey <> #0) and (UpCase(Sel.Hotkey) = UpCase(K.Ch)) then
          begin
            FSel := FItems.IndexOf(Sel);
            EnsureVisible;
            Result := Sel;
            Exit;
          end;
        { Pass unrecognised char back to the caller }
        FUnhandledChar := K.Ch;
        Exit;
      end;

      else begin
        if K.Code in [kcUp, kcDown, kcPageUp, kcPageDown, kcHome, kcEnd] then
          HandleKey(K)
        else
        begin
          if Assigned(GOnUnhandledKey) then
            GOnUnhandledKey(Self, K);
          if GQuitRequested then Exit;
        end;
      end;
    end;
  until False;
end;

{ ══════════════════════════════════════════════════════════════════════
  EditLine — inline single-line editor
  ══════════════════════════════════════════════════════════════════════ }

function EditLine(const APrompt, ACurrent: string; var AResult: string;
  ARow: Integer = 0): Boolean;
var
  Row, PromptLen, FieldW: Integer;
  Buf:    string;
  Cur:    Integer;  { 1..Length(Buf)+1 }
  Scroll: Integer;  { index of leftmost visible char (0-based) }
  ViewCur: Integer;
  K:      TKeyEvent;

  procedure EnsureVisible;
  begin
    ViewCur := Cur - Scroll;
    if ViewCur < 1 then
    begin
      Scroll  := Cur - 1;
      ViewCur := 1;
    end;
    if ViewCur > FieldW then
    begin
      Scroll  := Cur - FieldW;
      ViewCur := FieldW;
    end;
  end;

  function WordLeft: Integer;
  var I: Integer;
  begin
    I := Cur - 1;
    while (I > 1) and (Buf[I - 1] = ' ') do Dec(I);
    while (I > 1) and (Buf[I - 1] <> ' ') do Dec(I);
    Result := I;
  end;

  function WordRight: Integer;
  var I, Len: Integer;
  begin
    Len := Length(Buf);
    I   := Cur;
    while (I <= Len) and (Buf[I] <> ' ') do Inc(I);
    while (I <= Len) and (Buf[I] = ' ') do Inc(I);
    Result := I;
  end;

begin
  Buf    := ACurrent;
  Cur    := Length(Buf) + 1;
  Scroll := 0;
  Result := False;

  if ARow <= 0 then
    Row := Term.Height div 2
  else
    Row := ARow;

  PromptLen := 1 + Length(APrompt) + 2;  { ' ' + prompt + ': ' }
  FieldW    := Term.Width - PromptLen;
  if FieldW < 4 then FieldW := 4;

  Term.ShowCursor;
  repeat
    EnsureVisible;
    Term.GotoXY(1, Row);
    Term.ClearToEOL;
    Term.SetFG(clBrightYellow);
    Term.WriteStr(' ' + APrompt + ': ');
    Term.SetFG(clWhite);
    Term.WriteStr(Copy(Buf, Scroll + 1, FieldW));
    Term.ClearToEOL;
    Term.GotoXY(PromptLen + ViewCur, Row);
    Term.FlushOutput;

    K := Term.ReadKey;
    case K.Code of
      kcEnter: begin
        AResult := Buf;
        Result  := True;
        Break;
      end;
      kcEscape: Break;
      kcLeft:      if Cur > 1 then Dec(Cur);
      kcRight:     if Cur <= Length(Buf) then Inc(Cur);
      kcHome:      Cur := 1;
      kcEnd:       Cur := Length(Buf) + 1;
      kcCtrlLeft:  Cur := WordLeft;
      kcCtrlRight: Cur := WordRight;
      kcBackspace:
        if Cur > 1 then
        begin
          Delete(Buf, Cur - 1, 1);
          Dec(Cur);
        end;
      kcDelete:
        if Cur <= Length(Buf) then
          Delete(Buf, Cur, 1);
      kcChar:
        if K.Ch >= ' ' then
        begin
          Insert(K.Ch, Buf, Cur);
          Inc(Cur);
        end;
    end;
  until False;

  Term.HideCursor;
  Term.ResetColors;
end;

{ ══════════════════════════════════════════════════════════════════════
  Confirm
  ══════════════════════════════════════════════════════════════════════ }

function Confirm(const AMsg: string; ADefault: Boolean = False): Boolean;
var
  K:       TKeyEvent;
  Options: string;
begin
  if ADefault then
    Options := '(yes/no) [Y]'
  else
    Options := '(yes/no) [N]';
  Term.InvalidateFront;
  Term.GotoXY(1, Term.Height - 1);
  Term.ClearToEOL;
  ColorHelp;
  Term.WriteStr(' ' + AMsg + ' ' + Options + ': ');
  Term.ResetColors;
  Term.ShowCursor;
  Term.FlushOutput;
  repeat
    K := Term.ReadKey;
    if K.Code = kcEnter then begin Result := ADefault; Break; end;
    if K.Code = kcChar then
      case UpCase(K.Ch) of
        'Y': begin Result := True;  Break; end;
        'N': begin Result := False; Break; end;
      end;
    if K.Code = kcEscape then begin Result := False; Break; end;
  until False;
  Term.HideCursor;
end;

initialization
  GQuitRequested  := False;
  GSaveRequested  := False;
  GCtrlCRequested := False;
  GCtrlXRequested := False;

end.
