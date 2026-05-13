{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Forms;

{$mode objfpc}{$H+}

interface

uses
  Classes, fgl, TermUI.Terminal, TermUI.Control;

type
  TControlList = specialize TFPGObjectList<TControl>;

  { A full-screen (or bounded) container of TControl children.
    Owns its children. Focused child gets first crack at key events,
    then the form's own OnKeyDown fires if nothing consumed the key.
    ModalResult <> 0 signals that ShowModal should return. }
  TForm = class(TControl)
  private
    FTitle:        string;
    FControls:     TControlList;
    FFocusIndex:   Integer;
    FModalResult:  Integer;
    FOnActivate:   TNotifyEvent;
    FOnDeactivate: TNotifyEvent;
    function  NextFocusable(AFrom, ADir: Integer): Integer;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
  public
    constructor Create(const ATitle: string = ''); reintroduce; virtual;
    destructor Destroy; override;

    { Add a child control. The form takes ownership. }
    procedure AddControl(AControl: TControl);
    function  ControlCount: Integer;
    function  GetControl(AIndex: Integer): TControl;

    procedure FocusNext;
    procedure FocusPrev;
    function  FocusedControl: TControl;

    { Invalidate the form and all its children. }
    procedure Invalidate; override;

    { Set ModalResult to signal ShowModal to return. }
    procedure Close(AModalResult: Integer = 1);
    procedure CloseCancel;

    property Title:        string       read FTitle        write FTitle;
    property ModalResult:  Integer      read FModalResult  write FModalResult;
    property OnActivate:   TNotifyEvent read FOnActivate   write FOnActivate;
    property OnDeactivate: TNotifyEvent read FOnDeactivate write FOnDeactivate;
  end;

implementation

constructor TForm.Create(const ATitle: string);
begin
  inherited Create;
  FTitle       := ATitle;
  FControls    := TControlList.Create(True);
  FFocusIndex  := -1;
  FModalResult := 0;
  SetBounds(1, 1, Term.Width, Term.Height);
end;

destructor TForm.Destroy;
begin
  FControls.Free;
  inherited;
end;

procedure TForm.AddControl(AControl: TControl);
begin
  FControls.Add(AControl);
  if FFocusIndex < 0 then
    FFocusIndex := 0;
end;

function TForm.ControlCount: Integer;
begin
  Result := FControls.Count;
end;

function TForm.GetControl(AIndex: Integer): TControl;
begin
  Result := FControls[AIndex];
end;

function TForm.NextFocusable(AFrom, ADir: Integer): Integer;
var
  I, N: Integer;
begin
  N := FControls.Count;
  Result := AFrom;
  for I := 1 to N do
  begin
    Result := (Result + ADir + N) mod N;
    if FControls[Result].Enabled and FControls[Result].Visible then
      Exit;
  end;
end;

function TForm.FocusedControl: TControl;
begin
  if (FFocusIndex >= 0) and (FFocusIndex < FControls.Count) then
    Result := FControls[FFocusIndex]
  else
    Result := nil;
end;

procedure TForm.FocusNext;
begin
  if FControls.Count > 0 then
    FFocusIndex := NextFocusable(FFocusIndex, +1);
end;

procedure TForm.FocusPrev;
begin
  if FControls.Count > 0 then
    FFocusIndex := NextFocusable(FFocusIndex, -1);
end;

procedure TForm.Invalidate;
var
  I: Integer;
begin
  inherited Invalidate;
  for I := 0 to FControls.Count - 1 do
    FControls[I].Invalidate;
end;

procedure TForm.Close(AModalResult: Integer);
begin
  FModalResult := AModalResult;
  if Assigned(FOnDeactivate) then
    FOnDeactivate(Self);
end;

procedure TForm.CloseCancel;
begin
  Close(-1);
end;

procedure TForm.DoPaint;
var
  I: Integer;
begin
  for I := 0 to FControls.Count - 1 do
    if FControls[I].Invalidated then
      FControls[I].Paint;
  inherited DoPaint;
end;

function TForm.DoKeyDown(var Key: TKeyEvent): Boolean;
var
  FC: TControl;
begin
  FC := FocusedControl;
  if Assigned(FC) then
  begin
    Result := FC.KeyDown(Key);
    if Result then Exit;
  end;
  if Key.Code = kcTab then
  begin
    FocusNext;
    Result := True;
    Exit;
  end;
  Result := inherited DoKeyDown(Key);
end;

end.
