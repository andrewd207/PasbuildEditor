{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Control;

{$mode objfpc}{$H+}

interface

uses
  Classes, TermUI.Terminal;

type
  { Fired when a key is pressed. Return True to mark the key as handled. }
  TKeyDownEvent = function(Sender: TObject; var Key: TKeyEvent): Boolean of object;

  { Base class for all visible, interactive terminal UI elements.
    Left/Top are 1-based terminal coordinates of the control's top-left corner.
    GotoLocal(X, Y) translates control-local coords into terminal coords automatically. }
  TControl = class
  private
    FLeft:        Integer;
    FTop:         Integer;
    FWidth:       Integer;
    FHeight:      Integer;
    FVisible:     Boolean;
    FEnabled:     Boolean;
    FInvalidated: Boolean;
    FOnKeyDown:   TKeyDownEvent;
    FOnPaint:     TNotifyEvent;
  protected
    { Override to draw the control. GotoLocal(1,1) positions at the top-left corner. }
    procedure DoPaint; virtual;
    { Override to handle keys before OnKeyDown fires. Return True to consume the key. }
    function  DoKeyDown(var Key: TKeyEvent): Boolean; virtual;
    { Position the terminal cursor at control-local coordinates (1-based). }
    procedure GotoLocal(AX, AY: Integer); inline;
  public
    constructor Create; virtual;

    procedure SetBounds(ALeft, ATop, AWidth, AHeight: Integer);
    procedure Invalidate; virtual;

    { Paint the control if visible. Clears FInvalidated. }
    procedure Paint;
    { Dispatch a key to DoKeyDown then OnKeyDown. Returns True if consumed. }
    function  KeyDown(var Key: TKeyEvent): Boolean;

    property Left:        Integer       read FLeft        write FLeft;
    property Top:         Integer       read FTop         write FTop;
    property Width:       Integer       read FWidth       write FWidth;
    property Height:      Integer       read FHeight      write FHeight;
    property Visible:     Boolean       read FVisible     write FVisible;
    property Enabled:     Boolean       read FEnabled     write FEnabled;
    property Invalidated: Boolean       read FInvalidated;
    property OnKeyDown:   TKeyDownEvent read FOnKeyDown   write FOnKeyDown;
    property OnPaint:     TNotifyEvent  read FOnPaint     write FOnPaint;
  end;

implementation

constructor TControl.Create;
begin
  inherited Create;
  FVisible     := True;
  FEnabled     := True;
  FInvalidated := True;
end;

procedure TControl.SetBounds(ALeft, ATop, AWidth, AHeight: Integer);
begin
  FLeft   := ALeft;
  FTop    := ATop;
  FWidth  := AWidth;
  FHeight := AHeight;
  Invalidate;
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

end.
