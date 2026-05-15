{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Control;

{$mode objfpc}{$H+}
{$interfaces corba}

interface

uses
  Classes, TermUI.Terminal;

type
  TTextAlign = (taLeft, taCenter, taRight);

  TControl = class;

  { Fired when a key is pressed. Return True to mark the key as handled. }
  TKeyDownEvent = function(Sender: TObject; var Key: TKeyEvent): Boolean of object;

  { Fired when help is requested for this control. Return True to mark as handled
    and stop propagation toward the parent. }
  THelpEvent = function(Sender: TObject): Boolean of object;

  { Implemented by any class that owns and arranges child controls.
    TForm implements this directly; container controls subclass TControl and
    also implement it.  CORBA — no reference counting. }
  IContainer = interface
    { Called when the container's bounds change.  Implementations compute and
      push new bounds to each child via SetBounds. }
    procedure ArrangeChildren;
    function  ChildCount: Integer;
    function  GetChild(AIndex: Integer): TControl;
    procedure AddChild(AControl: TControl);
  end;

  { Base class for all visible, interactive terminal UI elements.
    Left/Top are 1-based terminal coordinates of the control's top-left corner.
    GotoLocal(X, Y) translates control-local coords into terminal coords automatically. }
  TControl = class
  private
    FLeft:             Integer;
    FTop:              Integer;
    FWidth:            Integer;
    FHeight:           Integer;
    FVisible:          Boolean;
    FEnabled:          Boolean;
    FInvalidated:      Boolean;
    FForeColor:        TColor;
    FBackColor:        TColor;
    FOnKeyDown:        TKeyDownEvent;
    FOnPaint:          TNotifyEvent;
    FOnBoundsChanged:  TNotifyEvent;
    FOnHelp:           THelpEvent;
  protected
    { Override to draw the control. GotoLocal(1,1) positions at the top-left corner. }
    procedure DoPaint; virtual;
    { Override to handle keys before OnKeyDown fires. Return True to consume the key. }
    function  DoKeyDown(var Key: TKeyEvent): Boolean; virtual;
    { Called when the control receives input focus. }
    procedure DoGainFocus; virtual;
    { Called when the control loses input focus. }
    procedure DoLoseFocus; virtual;
    { Called from SetBounds after new bounds are stored. Override in containers to
      rearrange children, or in leaf controls to recompute display state (e.g. truncate
      labels, recalculate scroll limits). Fires before OnBoundsChanged and Invalidate. }
    procedure DoBoundsChanged; virtual;
    { Override to handle a help request before OnHelp fires. Containers should try
      their focused child first. Return True to stop propagation. }
    function  DoHelp: Boolean; virtual;
    { Position the terminal cursor at control-local coordinates (1-based). }
    procedure GotoLocal(AX, AY: Integer); inline;
  public
    constructor Create; virtual;

    { Store new bounds, call DoBoundsChanged, fire OnBoundsChanged, then Invalidate.
      Skips the notifications and repaint when bounds are unchanged. }
    procedure SetBounds(ALeft, ATop, AWidth, AHeight: Integer); virtual;
    procedure Invalidate; virtual;

    { Paint the control if visible. Clears FInvalidated. }
    procedure Paint;
    { Dispatch a key to DoKeyDown then OnKeyDown. Returns True if consumed. }
    function  KeyDown(var Key: TKeyEvent): Boolean;
    { Request help for this control. Calls DoHelp then OnHelp. Returns True if handled. }
    function  Help: Boolean;
    { Notify the control that it has gained or lost input focus. }
    procedure GainFocus;
    procedure LoseFocus;

    property Left:        Integer       read FLeft        write FLeft;
    property Top:         Integer       read FTop         write FTop;
    property Width:       Integer       read FWidth       write FWidth;
    property Height:      Integer       read FHeight      write FHeight;
    property Visible:     Boolean       read FVisible     write FVisible;
    property Enabled:     Boolean       read FEnabled     write FEnabled;
    property Invalidated: Boolean       read FInvalidated;
    property ForeColor: TColor read FForeColor write FForeColor;
    property BackColor: TColor read FBackColor write FBackColor;
    property OnKeyDown:       TKeyDownEvent read FOnKeyDown        write FOnKeyDown;
    property OnPaint:         TNotifyEvent  read FOnPaint           write FOnPaint;
    property OnBoundsChanged: TNotifyEvent  read FOnBoundsChanged   write FOnBoundsChanged;
    property OnHelp:          THelpEvent    read FOnHelp            write FOnHelp;
  end;

implementation

constructor TControl.Create;
begin
  inherited Create;
  FVisible    := True;
  FEnabled    := True;
  FInvalidated := True;
  FForeColor  := clDefault;
  FBackColor  := clDefault;
end;

procedure TControl.SetBounds(ALeft, ATop, AWidth, AHeight: Integer);
begin
  if (FLeft = ALeft) and (FTop = ATop) and
     (FWidth = AWidth) and (FHeight = AHeight) then Exit;
  FLeft   := ALeft;
  FTop    := ATop;
  FWidth  := AWidth;
  FHeight := AHeight;
  DoBoundsChanged;
  if Assigned(FOnBoundsChanged) then FOnBoundsChanged(Self);
  Invalidate;
end;

procedure TControl.DoBoundsChanged;
begin
end;

procedure TControl.Invalidate;
begin
  FInvalidated := True;
end;

procedure TControl.GotoLocal(AX, AY: Integer);
begin
  Term.GotoXY(FLeft + AX - 1, FTop + AY - 1);
end;

procedure TControl.DoPaint;
begin
  if Assigned(FOnPaint) then
    FOnPaint(Self);
end;

function TControl.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  Result := False;
end;

function TControl.DoHelp: Boolean;
begin
  Result := False;
end;

procedure TControl.Paint;
begin
  if not FVisible then Exit;
  FInvalidated := False;
  DoPaint;
end;

function TControl.KeyDown(var Key: TKeyEvent): Boolean;
begin
  Result := False;
  if not FEnabled then Exit;
  Result := DoKeyDown(Key);
  if Result then Exit;
  if Assigned(FOnKeyDown) then
    Result := FOnKeyDown(Self, Key);
end;

function TControl.Help: Boolean;
begin
  Result := DoHelp;
  if Result then Exit;
  if Assigned(FOnHelp) then
    Result := FOnHelp(Self);
end;

procedure TControl.DoGainFocus;
begin
end;

procedure TControl.DoLoseFocus;
begin
end;

procedure TControl.GainFocus;
begin
  DoGainFocus;
end;

procedure TControl.LoseFocus;
begin
  DoLoseFocus;
end;

end.
