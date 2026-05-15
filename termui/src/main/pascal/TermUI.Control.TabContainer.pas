{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Control.TabContainer;

{$mode objfpc}{$H+}
{$interfaces corba}

{ Tab container — one child visible at a time, with a tab bar on the top row.

  Tab bar rendering:
    [Active Tab]  Inactive  Another
  Active tab is bracketed and highlighted; inactive tabs are dimmed.
  Labels are truncated with '~' if the bar runs out of width.

  Key bindings (handled before passing to the active child):
    Shift+Left  — previous tab
    Shift+Right — next tab

  Programmatic switching: set ActiveTab directly.
  AddChild via IContainer adds with an empty label; use AddTab for a named tab. }

interface

uses
  Classes, TermUI.Terminal, TermUI.Control, TermUI.Control.Container;

type
  TTabContainer = class(TMultiContainerControl)
  private
    FTabLabels:     array of string;
    FOnTabChanged:  TNotifyEvent;
    procedure SetActiveTab(AIndex: Integer);
    function  GetActiveTab: Integer;
    procedure DrawTabBar;
    procedure ApplyVisibility;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
    procedure ArrangeChildren; override;
  public
    { Add a named tab. Takes ownership of AControl. }
    procedure AddTab(const ALabel: string; AControl: TControl);
    { IContainer.AddChild — adds with an empty label. }
    procedure AddChild(AControl: TControl);

    property ActiveTab:     Integer      read GetActiveTab   write SetActiveTab;
    property OnTabChanged:  TNotifyEvent read FOnTabChanged  write FOnTabChanged;
  end;

implementation

uses SysUtils, Math;

const
  TAB_BAR_HEIGHT = 1;

function TTabContainer.GetActiveTab: Integer;
begin
  Result := FFocusIndex;
end;

procedure TTabContainer.SetActiveTab(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= FChildCount) then Exit;
  if AIndex = FFocusIndex then Exit;
  FFocusIndex := AIndex;
  ApplyVisibility;
  ArrangeChildren;
  Invalidate;
  if Assigned(FOnTabChanged) then FOnTabChanged(Self);
end;

procedure TTabContainer.ApplyVisibility;
var I: Integer;
begin
  for I := 0 to FChildCount - 1 do
    FChildren[I].Control.Visible := (I = FFocusIndex);
end;

procedure TTabContainer.AddTab(const ALabel: string; AControl: TControl);
begin
  SetLength(FTabLabels, FChildCount + 1);
  FTabLabels[FChildCount] := ALabel;
  inherited AddChild(AControl);        { updates FChildCount, calls ArrangeChildren }
  ApplyVisibility;
end;

procedure TTabContainer.AddChild(AControl: TControl);
begin
  AddTab('', AControl);
end;

procedure TTabContainer.ArrangeChildren;
var
  I, ContentTop, ContentH: Integer;
begin
  ContentTop := Top + TAB_BAR_HEIGHT;
  ContentH   := Height - TAB_BAR_HEIGHT;
  if ContentH < 1 then ContentH := 1;
  for I := 0 to FChildCount - 1 do
    FChildren[I].Control.SetBounds(Left, ContentTop, Width, ContentH);
end;

procedure TTabContainer.DrawTabBar;
var
  I, X, LabelW, AvailW: Integer;
  S: string;
begin
  GotoLocal(1, 1);
  Term.ResetColors;

  X      := 1;
  AvailW := Width;

  for I := 0 to FChildCount - 1 do
  begin
    if AvailW <= 0 then Break;

    S := FTabLabels[I];

    if I = FFocusIndex then
    begin
      { Active: [ Label ] — 4 chars of chrome around the label }
      LabelW := Length(S) + 4;
      if LabelW > AvailW then
      begin
        S := Copy(S, 1, Max(0, AvailW - 4));
        if Length(S) > 0 then S[Length(S)] := '~';
        LabelW := AvailW;
      end;
      Term.SetFG(clBrightWhite);
      Term.SetBG(clBlue);
      Term.WriteStr('[ ');
      Term.WriteStr(S);
      Term.WriteStr(' ]');
    end
    else
    begin
      { Inactive: space + Label + space }
      LabelW := Length(S) + 2;
      if LabelW > AvailW then
      begin
        S := Copy(S, 1, Max(0, AvailW - 2));
        if Length(S) > 0 then S[Length(S)] := '~';
        LabelW := AvailW;
      end;
      Term.ResetColors;
      Term.SetFG(clBrightBlack);
      Term.WriteStr(' ');
      Term.WriteStr(S);
      Term.WriteStr(' ');
    end;

    Inc(X, LabelW);
    Dec(AvailW, LabelW);
  end;

  { Fill the rest of the tab bar row }
  Term.ResetColors;
  Term.SetFG(clBrightBlack);
  while AvailW > 0 do
  begin
    Term.WriteStr(' ');
    Dec(AvailW);
  end;
  Term.ResetColors;
end;

procedure TTabContainer.DoPaint;
begin
  DrawTabBar;
  inherited DoPaint;  { paints visible+invalidated children }
end;

function TTabContainer.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  case Key.Code of
    kcShiftLeft:
      begin
        if FFocusIndex > 0 then
          SetActiveTab(FFocusIndex - 1);
        Result := True;
      end;
    kcShiftRight:
      begin
        if FFocusIndex < FChildCount - 1 then
          SetActiveTab(FFocusIndex + 1);
        Result := True;
      end;
  else
    Result := inherited DoKeyDown(Key);
  end;
end;

end.
