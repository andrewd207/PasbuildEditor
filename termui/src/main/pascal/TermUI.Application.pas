{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Application;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, TermUI.Terminal, TermUI.Control, TermUI.Forms;

type
  { The application event loop. There is one global instance: Application.

    Typical usage:
      Application.PushForm(MyMainForm);
      Application.Run;

    Modal sub-page:
      Result := Application.ShowModal(MyDialog);
      // ShowModal spins ProcessMessages until MyDialog.Close is called.

    App-level key handling:
      Application.OnKeyDown := @HandleGlobalKey;
      // HandleGlobalKey receives keys not consumed by the active form or its children. }
  TApplication = class
  private
    FTerminated:  Boolean;
    FFormStack:   array of TForm;
    FOnKeyDown:   TKeyDownEvent;
    FOnIdle:      TNotifyEvent;
    function  ActiveForm: TForm;
    procedure DispatchKey(var Key: TKeyEvent);
    procedure RepaintActive;
    procedure HandleResize;
  public
    destructor Destroy; override;

    { Main event loop — returns when Terminate is called. }
    procedure Run;

    { Process one cycle of input + repaint. Non-blocking if no key is waiting
      (16 ms timeout). Call this in a modal sub-loop:
        while AForm.ModalResult = 0 do Application.ProcessMessages; }
    procedure ProcessMessages;

    procedure Terminate;
    { Clear the terminated flag — call to resume after a cancelled quit. }
    procedure Resume;

    { Push/pop the active form. The top of the stack is the active form. }
    procedure PushForm(AForm: TForm);
    procedure PopForm;

    { Push AForm, spin ProcessMessages until AForm.ModalResult <> 0, pop and return
      the ModalResult. The caller owns AForm. }
    function  ShowModal(AForm: TForm): Integer;

    property Terminated: Boolean       read FTerminated;
    property OnKeyDown:  TKeyDownEvent read FOnKeyDown  write FOnKeyDown;
    { Fired each ProcessMessages cycle when there is no pending input. }
    property OnIdle:     TNotifyEvent  read FOnIdle     write FOnIdle;
  end;

var
  Application: TApplication;

implementation

function TApplication.ActiveForm: TForm;
var N: Integer;
begin
  N := Length(FFormStack);
  if N > 0 then
    Result := FFormStack[N - 1]
  else
    Result := nil;
end;

procedure TApplication.DispatchKey(var Key: TKeyEvent);
var
  AF: TForm;
begin
  AF := ActiveForm;
  if Assigned(AF) then
    if AF.KeyDown(Key) then Exit;
  if Assigned(FOnKeyDown) then
    FOnKeyDown(Self, Key);
end;

procedure TApplication.RepaintActive;
var
  AF: TForm;
begin
  AF := ActiveForm;
  if Assigned(AF) and AF.Invalidated then
  begin
    AF.Paint;
    Term.FlushOutput;
  end;
end;

procedure TApplication.HandleResize;
var
  AF: TForm;
begin
  AF := ActiveForm;
  if Assigned(AF) then
  begin
    AF.SetBounds(1, 1, Term.Width, Term.Height);
    AF.Invalidate;
  end;
end;

destructor TApplication.Destroy;
begin
  SetLength(FFormStack, 0);
  inherited;
end;

procedure TApplication.PushForm(AForm: TForm);
var N: Integer;
begin
  N := Length(FFormStack);
  SetLength(FFormStack, N + 1);
  FFormStack[N] := AForm;
  AForm.Invalidate;
  if Assigned(AForm.OnActivate) then
    AForm.OnActivate(AForm);
end;

procedure TApplication.PopForm;
var
  N:  Integer;
  AF: TForm;
begin
  N := Length(FFormStack);
  if N = 0 then Exit;
  AF := FFormStack[N - 1];
  if Assigned(AF.OnDeactivate) then
    AF.OnDeactivate(AF);
  SetLength(FFormStack, N - 1);
  if N - 1 > 0 then
    FFormStack[N - 2].Invalidate;
end;

procedure TApplication.ProcessMessages;
var
  Key:    TKeyEvent;
  HadKey: Boolean;
begin
  if Term.HasResized then
    HandleResize;
  RepaintActive;
  HadKey := Term.ReadKeyTimeout(Key, 16);
  if HadKey then
    DispatchKey(Key)
  else
  begin
    CheckSynchronize;
    if Assigned(FOnIdle) then
      FOnIdle(Self);
  end;
end;

procedure TApplication.Run;
begin
  FTerminated := False;
  while not FTerminated do
    ProcessMessages;
end;

function TApplication.ShowModal(AForm: TForm): Integer;
begin
  AForm.ModalResult := 0;
  PushForm(AForm);
  try
    while (AForm.ModalResult = 0) and not FTerminated do
      ProcessMessages;
  finally
    PopForm;
  end;
  Result := AForm.ModalResult;
end;

procedure TApplication.Terminate;
begin
  FTerminated := True;
end;

procedure TApplication.Resume;
begin
  FTerminated := False;
end;

initialization
  Application := TApplication.Create;

finalization
  FreeAndNil(Application);

end.
