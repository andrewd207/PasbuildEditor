{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Control.Container;

{$mode objfpc}{$H+}
{$interfaces corba}

interface

uses
  Classes, TermUI.Terminal, TermUI.Control;

type
  { How a child participates in layout.
    lhFixed   — occupies exactly FixedSize columns/rows.
    lhStretch — shares whatever space remains after fixed children are placed.
                Multiple stretch children divide the remainder equally. }
  TLayoutHint = (lhFixed, lhStretch);

  TChildEntry = record
    Control:   TControl;
    Hint:      TLayoutHint;
    FixedSize: Integer;
  end;

  { Single-child container control.  The child may itself be a TContainerControl
    or any other TControl.  ArrangeChildren gives the child the full bounds by
    default; override it to reserve space for a border, header row, etc.
    Multi-child layouts (VBox, HBox, TabContainer) subclass this and expand the
    child model. }
  TContainerControl = class(TControl, IContainer)
  private
    FChild: TControl;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
    function  DoHelp: Boolean; override;
    { Calls ArrangeChildren so subclasses only need to override that. }
    procedure DoBoundsChanged; override;
    { Override to compute and push bounds to children.
      Base gives FChild the full container bounds. }
    procedure ArrangeChildren; virtual;
  public
    destructor Destroy; override;

    { IContainer — AddChild takes ownership of AControl. }
    procedure AddChild(AControl: TControl);
    function  ChildCount: Integer;
    function  GetChild(AIndex: Integer): TControl;

    procedure Invalidate; override;

    property Child: TControl read FChild;
  end;

  { Abstract base for containers with two or more children.
    Subclasses override ArrangeChildren to implement their layout strategy.
    AddChild adds a stretch child; AddFixedChild adds a fixed-size child. }
  TMultiContainerControl = class(TControl, IContainer)
  private
    function  NextFocusable(AFrom, ADir: Integer): Integer;
  protected
    FChildren:    array of TChildEntry;
    FChildCount:  Integer;
    FFocusIndex:  Integer;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
    function  DoHelp: Boolean; override;
    procedure DoBoundsChanged; override;
    procedure ArrangeChildren; virtual; abstract;
  public
    destructor Destroy; override;

    { IContainer — AddChild adds as lhStretch. }
    procedure AddChild(AControl: TControl);
    function  ChildCount: Integer;
    function  GetChild(AIndex: Integer): TControl;

    { Add a child that occupies exactly AFixedSize columns (HBox) or rows (VBox). }
    procedure AddFixedChild(AControl: TControl; AFixedSize: Integer);

    procedure FocusNext;
    procedure FocusPrev;
    function  FocusedChild: TControl;

    procedure Invalidate; override;
  end;

implementation

destructor TContainerControl.Destroy;
begin
  FChild.Free;
  inherited;
end;

procedure TContainerControl.AddChild(AControl: TControl);
begin
  if FChild <> AControl then
    FChild.Free;
  FChild := AControl;
  ArrangeChildren;
  Invalidate;
end;

function TContainerControl.ChildCount: Integer;
begin
  if Assigned(FChild) then Result := 1 else Result := 0;
end;

function TContainerControl.GetChild(AIndex: Integer): TControl;
begin
  if AIndex = 0 then Result := FChild else Result := nil;
end;

procedure TContainerControl.DoBoundsChanged;
begin
  ArrangeChildren;
end;

procedure TContainerControl.ArrangeChildren;
begin
  if Assigned(FChild) then
    FChild.SetBounds(Left, Top, Width, Height);
end;

procedure TContainerControl.DoPaint;
begin
  if Assigned(FChild) and FChild.Invalidated then
    FChild.Paint;
  inherited DoPaint;
end;

function TContainerControl.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  if Assigned(FChild) and FChild.Enabled then
    Result := FChild.KeyDown(Key)
  else
    Result := False;
  if not Result then
    Result := inherited DoKeyDown(Key);
end;

function TContainerControl.DoHelp: Boolean;
begin
  if Assigned(FChild) then
    Result := FChild.Help
  else
    Result := False;
  if not Result then
    Result := inherited DoHelp;
end;

procedure TContainerControl.Invalidate;
begin
  inherited Invalidate;
  if Assigned(FChild) then
    FChild.Invalidate;
end;

{ ── TMultiContainerControl ── }

procedure TMultiContainerControl.AddChild(AControl: TControl);
var E: TChildEntry;
begin
  E.Control   := AControl;
  E.Hint      := lhStretch;
  E.FixedSize := 0;
  SetLength(FChildren, FChildCount + 1);
  FChildren[FChildCount] := E;
  Inc(FChildCount);
  if FFocusIndex < 0 then FFocusIndex := 0;
  ArrangeChildren;
  Invalidate;
end;

procedure TMultiContainerControl.AddFixedChild(AControl: TControl; AFixedSize: Integer);
var E: TChildEntry;
begin
  E.Control   := AControl;
  E.Hint      := lhFixed;
  E.FixedSize := AFixedSize;
  SetLength(FChildren, FChildCount + 1);
  FChildren[FChildCount] := E;
  Inc(FChildCount);
  if FFocusIndex < 0 then FFocusIndex := 0;
  ArrangeChildren;
  Invalidate;
end;

function TMultiContainerControl.ChildCount: Integer;
begin
  Result := FChildCount;
end;

function TMultiContainerControl.GetChild(AIndex: Integer): TControl;
begin
  if (AIndex >= 0) and (AIndex < FChildCount) then
    Result := FChildren[AIndex].Control
  else
    Result := nil;
end;

function TMultiContainerControl.NextFocusable(AFrom, ADir: Integer): Integer;
var I: Integer;
begin
  Result := AFrom;
  for I := 1 to FChildCount do
  begin
    Result := (Result + ADir + FChildCount) mod FChildCount;
    if FChildren[Result].Control.Enabled and
       FChildren[Result].Control.Visible then Exit;
  end;
end;

function TMultiContainerControl.FocusedChild: TControl;
begin
  if (FFocusIndex >= 0) and (FFocusIndex < FChildCount) then
    Result := FChildren[FFocusIndex].Control
  else
    Result := nil;
end;

procedure TMultiContainerControl.FocusNext;
begin
  if FChildCount > 0 then
    FFocusIndex := NextFocusable(FFocusIndex, +1);
end;

procedure TMultiContainerControl.FocusPrev;
begin
  if FChildCount > 0 then
    FFocusIndex := NextFocusable(FFocusIndex, -1);
end;

procedure TMultiContainerControl.DoBoundsChanged;
begin
  ArrangeChildren;
end;

procedure TMultiContainerControl.DoPaint;
var I: Integer;
begin
  for I := 0 to FChildCount - 1 do
    if FChildren[I].Control.Visible and FChildren[I].Control.Invalidated then
      FChildren[I].Control.Paint;
  inherited DoPaint;
end;

function TMultiContainerControl.DoKeyDown(var Key: TKeyEvent): Boolean;
var FC: TControl;
begin
  FC := FocusedChild;
  if Assigned(FC) and FC.Enabled then
    Result := FC.KeyDown(Key)
  else
    Result := False;
  if not Result then
    Result := inherited DoKeyDown(Key);
end;

function TMultiContainerControl.DoHelp: Boolean;
var FC: TControl;
begin
  FC := FocusedChild;
  if Assigned(FC) then
    Result := FC.Help
  else
    Result := False;
  if not Result then
    Result := inherited DoHelp;
end;

procedure TMultiContainerControl.Invalidate;
var I: Integer;
begin
  inherited Invalidate;
  for I := 0 to FChildCount - 1 do
    FChildren[I].Control.Invalidate;
end;

destructor TMultiContainerControl.Destroy;
var I: Integer;
begin
  for I := 0 to FChildCount - 1 do
    FChildren[I].Control.Free;
  inherited;
end;

end.
