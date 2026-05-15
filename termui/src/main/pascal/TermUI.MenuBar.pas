{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.MenuBar;

{$mode objfpc}{$H+}

{ Horizontal menu bar overlay and pop-down submenu.

  TMenuBar is a one-row overlay form that lives at the top of the screen.
  It is intended to be used as a TApplication peek:

    FMenuBar := TMenuBar.Create;
    with FMenuBar.AddItem('&File') do
    begin
      Items.Add(TMenuItem.CreateEmbeddedHotkey('&New',   @OnNew));
      Items.Add(TMenuItem.CreateEmbeddedHotkey('&Open',  @OnOpen));
      Items.Add(TMenuItem.CreateSeparator);
      Items.Add(TMenuItem.CreateEmbeddedHotkey('&Quit',  @OnQuit));
    end;
    with FMenuBar.AddItem('&Help') do
      Items.Add(TMenuItem.CreateEmbeddedHotkey('&About', @OnAbout));

  Show the bar when the user presses Alt+letter:

    procedure TMyForm.HandleGlobalKey(Sender: TObject; var Key: TKeyEvent);
    begin
      if Key.Code = kcAltChar then
      begin
        Application.ShowPeek(FMenuBar);
        FMenuBar.ActivateAccel(Key.Ch);
      end;
    end;

    Application.OnKeyDown := @HandleGlobalKey;

  Navigation while the bar is visible:
    ←/→       move focus between top-level items (wraps)
    ↓/Enter   open the focused item's submenu
    A-Z       jump to item whose accelerator matches (opens submenu)
    Alt+A-Z   same as A-Z when the bar is focused
    Esc       close the menu bar

  Navigation inside an open submenu:
    ↑/↓       move selection
    Enter      execute selected item's Action; close bar
    A-Z       jump to item whose hotkey matches; execute and close bar
    ←/→       close this submenu and open the prev/next top-level one
    Esc        close submenu; return to bar }

interface

uses
  Classes, SysUtils, fgl,
  TermUI.StringUtils,
  TermUI.Terminal, TermUI.Control, TermUI.Forms, TermUI.Application,
  TermUI.Menu;

type
  { One top-level entry in the menu bar (e.g. "File", "Edit", "Help").
    Caption has '&' stripped out; Accel holds the accelerator char.
    Items is owned by this object; populate it with TMenuItem instances. }
  TMenuBarItem = class
  public
    Caption: string;
    Accel:   Char;     { #0 = no accelerator }
    AccelIdx: Integer; { 0-based position of the accel char in Caption; -1 = none }
    Items:   TMenuItemList;

    { Parse '&' prefix from ACaption to extract Caption and Accel.
      E.g. '&File' → Caption='File', Accel='F', AccelIdx=0. }
    constructor CreateAccel(const ACaption: string);
    destructor Destroy; override;
  end;
  TMenuBarItemList = specialize TFPGObjectList<TMenuBarItem>;

  { Drop-down popup for one top-level menu entry.
    Pushed onto the Application form stack via ShowModal while a submenu
    is open.  ExitDir communicates to TMenuBar how the user dismissed it:
       0  = Enter / item selected  (Selected holds the chosen TMenuItem)
      -1  = Left arrow  (caller should open the previous top-level item)
      +1  = Right arrow (caller should open the next top-level item)
       2  = Esc         (caller should close the popup but keep bar visible) }
  TMenuBarDropDown = class(TForm)
  private
    FItemList: TMenuItemList;  { NOT owned — points to TMenuBarItem.Items }
    FSel:      Integer;
    FExitDir:  Integer;
    FSelected: TMenuItem;
    FRunning:  Boolean;
    FOriginX:  Integer;
    function  Selectable(I: Integer): Boolean;
    function  NextSel(AFrom, ADir: Integer): Integer;
    function  CalcWidth: Integer;
    function  ContentRows: Integer;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
    { Intercepts TApplication resize notifications: close the popup so the
      menu bar can reposition itself cleanly on the new terminal size. }
    procedure SetBounds(ALeft, ATop, AWidth, AHeight: Integer); override;
  public
    constructor Create(const ATitle: string = ''); override;
    { Configure for AItems dropped from column AOriginX. }
    procedure Setup(AItems: TMenuItemList; AOriginX: Integer);
    { Run the popup modally. Returns the selected TMenuItem or nil. }
    function  RunPopup: TMenuItem;
    property  ExitDir:  Integer   read FExitDir;
    property  Selected: TMenuItem read FSelected;
  end;

  { One-row horizontal menu bar.  Always anchors to row 1, full terminal width.
    Overlay = True so the form beneath it remains visible. }
  TMenuBar = class(TForm)
  private
    FTopItems: TMenuBarItemList;
    FFocused:  Integer;
    FDropDown: TMenuBarDropDown;
    function  ItemLeft(I: Integer): Integer;
    function  ItemDisplayLen(I: Integer): Integer;
    function  FindAccel(ACh: Char): Integer;
    procedure OpenDropDown(AIdx: Integer);
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
    { Always recalculate to row 1, full width. }
    procedure SetBounds(ALeft, ATop, AWidth, AHeight: Integer); override;
  public
    constructor Create(const ATitle: string = ''); override;
    destructor Destroy; override;
    { Add a top-level menu item. Returns the new TMenuBarItem so sub-items
      can be added immediately:
        with MenuBar.AddItem('&File') do
          Items.Add(TMenuItem.CreateEmbeddedHotkey('&Open', @OnOpen)); }
    function  AddItem(const ACaption: string): TMenuBarItem;
    { Open the submenu whose accelerator matches ACh.  No-op if not found.
      Call from your Application.OnKeyDown when kcAltChar is received and
      the bar is already showing. }
    procedure ActivateAccel(ACh: Char);
  end;

implementation

{ ── TMenuBarItem ── }

constructor TMenuBarItem.CreateAccel(const ACaption: string);
var
  P:     Integer;
  Clean: string;
begin
  inherited Create;
  Items    := TMenuItemList.Create(True);
  AccelIdx := -1;
  if PosNeutral('&', ACaption, P) and (P < Length(ACaption) - 1) then
  begin
    Clean := ACaption;
    DeleteNeutral(Clean, P, 1);
    Caption  := Clean;
    Accel    := UpCase(Clean.Index[P]);
    AccelIdx := P;
  end
  else
  begin
    Caption := ACaption;
    Accel   := #0;
  end;
end;

destructor TMenuBarItem.Destroy;
begin
  Items.Free;
  inherited;
end;

{ ── TMenuBarDropDown ── }

constructor TMenuBarDropDown.Create(const ATitle: string);
begin
  inherited Create(ATitle);
  Overlay  := True;
  FRunning := False;
  FExitDir := 2;
end;

function TMenuBarDropDown.Selectable(I: Integer): Boolean;
begin
  Result := (I >= 0) and (I < FItemList.Count) and
            (FItemList[I].Kind = mikNormal) and FItemList[I].Enabled;
end;

function TMenuBarDropDown.NextSel(AFrom, ADir: Integer): Integer;
var
  I, Tries: Integer;
begin
  Result := AFrom;
  I      := AFrom + ADir;
  Tries  := 0;
  while Tries < FItemList.Count do
  begin
    if I < 0 then I := FItemList.Count - 1;
    if I >= FItemList.Count then I := 0;
    if Selectable(I) then begin Result := I; Exit; end;
    Inc(I, ADir);
    Inc(Tries);
  end;
end;

function TMenuBarDropDown.CalcWidth: Integer;
var
  I, L: Integer;
begin
  Result := 12;
  for I := 0 to FItemList.Count - 1 do
  begin
    case FItemList[I].Kind of
      mikNormal:
        begin
          { " > Label  Value " — 4 prefix + 2 suffix minimum }
          L := 4 + Length(FItemList[I].Label_) + 2;
          if FItemList[I].Value <> '' then
            Inc(L, 2 + Length(FItemList[I].Value));
          if L > Result then Result := L;
        end;
      mikHeader:
        begin
          L := 2 + Length(FItemList[I].Label_) + 2;
          if L > Result then Result := L;
        end;
    end;
  end;
end;

function TMenuBarDropDown.ContentRows: Integer;
begin
  Result := Height - 2;
  if Result < 0 then Result := 0;
end;

procedure TMenuBarDropDown.SetBounds(ALeft, ATop, AWidth, AHeight: Integer);
begin
  if FRunning then
  begin
    FExitDir := 2;
    Close(1);
  end
  else
    inherited SetBounds(ALeft, ATop, AWidth, AHeight);
end;

procedure TMenuBarDropDown.Setup(AItems: TMenuItemList; AOriginX: Integer);
var
  W, H, MaxLeft: Integer;
begin
  FItemList := AItems;
  FSel      := -1;
  FExitDir  := 2;
  FSelected := nil;
  if (FItemList <> nil) and (FItemList.Count > 0) then
    FSel := NextSel(-1, 1);
  W       := CalcWidth;
  H       := 2 + FItemList.Count;  { top border + items + bottom border }
  MaxLeft := Term.Width - W + 1;
  FOriginX := AOriginX;
  if FOriginX > MaxLeft then FOriginX := MaxLeft;
  if FOriginX < 1 then FOriginX := 1;
  if H > Term.Height - 2 then H := Term.Height - 2;
  if H < 2 then H := 2;
  inherited SetBounds(FOriginX, 2, W, H);
end;

procedure TMenuBarDropDown.DoPaint;
var
  I, Row, InnerW: Integer;
  Item:    TMenuItem;
  IsSel:   Boolean;
  LStr:    string;
  AccelPos: Integer;
  J:       Integer;
begin
  Term.HideCursor;
  InnerW := Width - 2;

  { ── Border ── }
  Term.SetFG(clWhite);
  Term.SetBG(clBlack);

  GotoLocal(1, 1);
  Application.DrawChar(dcTopLeft);
  Term.WriteStr(Application.RepeatChar(dcHoriz, InnerW));
  Application.DrawChar(dcTopRight);

  GotoLocal(1, Height);
  Application.DrawChar(dcBottomLeft);
  Term.WriteStr(Application.RepeatChar(dcHoriz, InnerW));
  Application.DrawChar(dcBottomRight);

  { ── Items ── }
  Row := 2;
  for I := 0 to FItemList.Count - 1 do
  begin
    if Row - 2 >= ContentRows then Break;
    Item  := FItemList[I];
    IsSel := (I = FSel);

    GotoLocal(1, Row);
    Term.SetFG(clWhite);
    Term.SetBG(clBlack);
    Application.DrawChar(dcVert);

    case Item.Kind of
      mikSeparator:
        begin
          Term.SetFG(clBrightBlack);
          Term.WriteStr(StringOfChar('-', InnerW));
        end;

      mikHeader:
        begin
          Term.SetFG(clBrightYellow);
          LStr := ' ' + Item.Label_;
          while Length(LStr) < InnerW do LStr := LStr + ' ';
          Term.WriteStr(CopyNeutral(LStr, 0, InnerW));
        end;

      mikNormal:
        begin
          if IsSel then begin Term.SetFG(clBlack); Term.SetBG(clCyan); end
          else          begin Term.SetFG(clWhite); Term.SetBG(clBlack); end;

          { Leading arrow }
          if IsSel then Term.WriteStr(' > ')
          else          Term.WriteStr('   ');

          { Label with hotkey highlighted }
          AccelPos := -1;
          if Item.Hotkey <> #0 then
            PosNeutral(UpCase(Item.Hotkey), UpperCase(Item.Label_), AccelPos);

          for J := 0 to Length(Item.Label_) - 1 do
          begin
            if J = AccelPos then
            begin
              if IsSel then Term.SetFG(clBrightYellow)
              else          Term.SetFG(clBrightCyan);
              Term.SetUnderline(True);
              Term.WriteStr(Item.Label_.Index[J]);
              Term.SetUnderline(False);
              if IsSel then Term.SetFG(clBlack)
              else          Term.SetFG(clWhite);
            end
            else
              Term.WriteStr(Item.Label_.Index[J]);
          end;

          { Optional value (shortcut display) }
          if Item.Value <> '' then
          begin
            if IsSel then Term.SetFG(clBlack)
            else          Term.SetFG(clBrightBlack);
            Term.WriteStr('  ' + Item.Value);
          end;

          { Pad to right border }
          J := 3 + Length(Item.Label_);
          if Item.Value <> '' then Inc(J, 2 + Length(Item.Value));
          while J < InnerW do begin Term.WriteStr(' '); Inc(J); end;

          if IsSel then begin Term.SetFG(clBlack); Term.SetBG(clCyan); end
          else          begin Term.SetFG(clWhite); Term.SetBG(clBlack); end;
        end;
    end;

    Term.SetFG(clWhite);
    Term.SetBG(clBlack);
    Application.DrawChar(dcVert);
    Inc(Row);
  end;

  Term.ResetColors;
  inherited DoPaint;
end;

function TMenuBarDropDown.DoKeyDown(var Key: TKeyEvent): Boolean;
var
  I: Integer;
begin
  Result := True;
  case Key.Code of
    kcUp:     begin FSel := NextSel(FSel, -1); Invalidate; end;
    kcDown:   begin FSel := NextSel(FSel, +1); Invalidate; end;
    kcLeft:   begin FExitDir := -1; Close(1); end;
    kcRight:  begin FExitDir := +1; Close(1); end;
    kcEscape: begin FExitDir :=  2; Close(1); end;
    kcEnter:
      begin
        if Selectable(FSel) then
          FSelected := FItemList[FSel];
        FExitDir := 0;
        Close(1);
      end;
    kcAltChar, kcChar:
      begin
        for I := 0 to FItemList.Count - 1 do
          if Selectable(I) and (FItemList[I].Hotkey <> #0) and
             (UpCase(FItemList[I].Hotkey) = UpCase(Key.Ch)) then
          begin
            FSel      := I;
            FSelected := FItemList[I];
            FExitDir  := 0;
            Close(1);
            Exit;
          end;
        Result := False;
      end;
  else
    Result := False;
  end;
end;

function TMenuBarDropDown.RunPopup: TMenuItem;
begin
  FSelected   := nil;
  FExitDir    := 2;
  ModalResult := 0;
  Invalidate;
  FRunning := True;
  Application.ShowModal(Self);
  FRunning := False;
  Result := FSelected;
end;

{ ── TMenuBar ── }

constructor TMenuBar.Create(const ATitle: string);
begin
  inherited Create(ATitle);
  Overlay   := True;
  FTopItems := TMenuBarItemList.Create(True);
  FFocused  := 0;
  FDropDown := TMenuBarDropDown.Create;
  { Anchor to row 1 }
  inherited SetBounds(1, 1, Term.Width, 1);
end;

destructor TMenuBar.Destroy;
begin
  FDropDown.Free;
  FTopItems.Free;
  inherited;
end;

function TMenuBar.AddItem(const ACaption: string): TMenuBarItem;
begin
  Result := TMenuBarItem.CreateAccel(ACaption);
  FTopItems.Add(Result);
end;

function TMenuBar.ItemDisplayLen(I: Integer): Integer;
begin
  Result := Length(FTopItems[I].Caption) + 2;
end;

function TMenuBar.ItemLeft(I: Integer): Integer;
var J: Integer;
begin
  Result := 1;
  for J := 0 to I - 1 do
    Inc(Result, ItemDisplayLen(J));
end;

function TMenuBar.FindAccel(ACh: Char): Integer;
var I: Integer;
begin
  for I := 0 to FTopItems.Count - 1 do
    if (FTopItems[I].Accel <> #0) and
       (UpCase(FTopItems[I].Accel) = UpCase(ACh)) then
      Exit(I);
  Result := -1;
end;

procedure TMenuBar.SetBounds(ALeft, ATop, AWidth, AHeight: Integer);
begin
  inherited SetBounds(1, 1, Term.Width, 1);
end;

procedure TMenuBar.DoPaint;
var
  I, J, Col: Integer;
  Item: TMenuBarItem;
begin
  Term.HideCursor;

  { Fill entire row with background }
  GotoLocal(1, 1);
  Term.SetBG(clBlack);
  Term.SetFG(clWhite);
  for I := 1 to Width do
    Term.WriteStr(' ');

  { Draw each top-level item }
  Col := 1;
  for I := 0 to FTopItems.Count - 1 do
  begin
    Item := FTopItems[I];
    GotoLocal(Col, 1);

    if I = FFocused then begin Term.SetBG(clCyan); Term.SetFG(clBlack); end
    else                 begin Term.SetBG(clBlack); Term.SetFG(clWhite); end;

    Term.WriteStr(' ');

    { Caption with accelerator highlighted }
    for J := 0 to Length(Item.Caption) - 1 do
    begin
      if J = Item.AccelIdx then
      begin
        if I = FFocused then Term.SetFG(clBrightYellow)
        else                 Term.SetFG(clBrightCyan);
        Term.SetUnderline(True);
        Term.WriteStr(Item.Caption.Index[J]);
        Term.SetUnderline(False);
        if I = FFocused then Term.SetFG(clBlack)
        else                 Term.SetFG(clWhite);
      end
      else
        Term.WriteStr(Item.Caption.Index[J]);
    end;

    Term.WriteStr(' ');
    Inc(Col, ItemDisplayLen(I));
  end;

  Term.ResetColors;
  inherited DoPaint;
end;

procedure TMenuBar.OpenDropDown(AIdx: Integer);
var
  Sel: TMenuItem;
  Dir: Integer;
begin
  if FTopItems.Count = 0 then Exit;
  repeat
    FDropDown.Setup(FTopItems[AIdx].Items, ItemLeft(AIdx));
    Invalidate;
    Sel := FDropDown.RunPopup;
    Dir := FDropDown.ExitDir;

    if Dir = 0 then
    begin
      { Item selected — execute action and close bar }
      if Assigned(Sel) and Assigned(Sel.Action) then
        Sel.Action(Sel);
      Close(1);
      Exit;
    end;

    if Dir = -1 then
    begin
      AIdx     := (AIdx - 1 + FTopItems.Count) mod FTopItems.Count;
      FFocused := AIdx;
      Invalidate;
    end
    else if Dir = 1 then
    begin
      AIdx     := (AIdx + 1) mod FTopItems.Count;
      FFocused := AIdx;
      Invalidate;
    end
    else
    begin
      { Esc — close popup, keep bar visible }
      Invalidate;
      Exit;
    end;
  until False;
end;

procedure TMenuBar.ActivateAccel(ACh: Char);
var
  Idx: Integer;
begin
  if ACh = #0 then
  begin
    { No specific accel — just open the currently-focused top item. }
    if FTopItems.Count > 0 then
      OpenDropDown(FFocused);
    Exit;
  end;
  Idx := FindAccel(ACh);
  if Idx >= 0 then
  begin
    FFocused := Idx;
    OpenDropDown(Idx);
  end;
end;

function TMenuBar.DoKeyDown(var Key: TKeyEvent): Boolean;
var
  Idx: Integer;
begin
  Result := True;
  if FTopItems.Count = 0 then begin Result := False; Exit; end;
  case Key.Code of
    kcLeft:
      begin
        FFocused := (FFocused - 1 + FTopItems.Count) mod FTopItems.Count;
        Invalidate;
      end;
    kcRight:
      begin
        FFocused := (FFocused + 1) mod FTopItems.Count;
        Invalidate;
      end;
    kcDown, kcEnter:
      OpenDropDown(FFocused);
    kcEscape:
      Close(1);
    kcAltChar, kcChar:
      begin
        Idx := FindAccel(Key.Ch);
        if Idx >= 0 then
        begin
          FFocused := Idx;
          OpenDropDown(Idx);
        end
        else
          Result := False;
      end;
  else
    Result := False;
  end;
end;

end.
