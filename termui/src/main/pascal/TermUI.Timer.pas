{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Timer;

{$mode objfpc}{$H+}

{ Periodic timer.  A background thread sleeps for Interval milliseconds then
  fires OnTimer on the main thread via Synchronize.

  Disabling the timer or destroying it signals the thread immediately via an
  RTLEvent so there is no wait for the current interval to expire.

  TApplication.ProcessMessages calls CheckSynchronize every cycle so OnTimer
  is delivered promptly regardless of whether the main thread is idle. }

interface

uses
  Classes, SysUtils;

type
  TTimer = class
  private
    FInterval: Cardinal;
    FEnabled:  Boolean;
    FOnTimer:  TNotifyEvent;
    FThread:   TThread;
    FEvent:    PRTLEvent;
    procedure SetEnabled(AValue: Boolean);
    procedure SetInterval(AValue: Cardinal);
  public
    constructor Create;
    destructor  Destroy; override;

    property Interval: Cardinal      read FInterval write SetInterval;
    property Enabled:  Boolean       read FEnabled  write SetEnabled;
    property OnTimer:  TNotifyEvent  read FOnTimer  write FOnTimer;
  end;

implementation

{ ── Internal thread ── }

type
  TTimerThread = class(TThread)
  private
    FOwner: TTimer;
    procedure FireTimer;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TTimer);
  end;

constructor TTimerThread.Create(AOwner: TTimer);
begin
  FOwner      := AOwner;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TTimerThread.FireTimer;
begin
  if Assigned(FOwner.FOnTimer) then
    FOwner.FOnTimer(FOwner);
end;

procedure TTimerThread.Execute;
begin
  while not Terminated do
  begin
    RTLEventWaitFor(FOwner.FEvent, FOwner.FInterval);
    RTLEventResetEvent(FOwner.FEvent);
    if Terminated then Break;
    if FOwner.FEnabled then
      Synchronize(@FireTimer);
  end;
end;

{ ── TTimer ── }

constructor TTimer.Create;
begin
  inherited Create;
  FInterval := 1000;
  FEnabled  := False;
  FEvent    := RTLEventCreate;
end;

destructor TTimer.Destroy;
begin
  { Wake and stop the thread before freeing the event it references. }
  if Assigned(FThread) then
  begin
    FThread.Terminate;
    RTLEventSetEvent(FEvent);
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  RTLEventDestroy(FEvent);
  inherited;
end;

procedure TTimer.SetEnabled(AValue: Boolean);
begin
  if FEnabled = AValue then Exit;
  FEnabled := AValue;
  if FEnabled then
  begin
    if not Assigned(FThread) then
      FThread := TTimerThread.Create(Self);
  end
  else
  begin
    { Wake the thread so it doesn't wait out the current interval. }
    RTLEventSetEvent(FEvent);
  end;
end;

procedure TTimer.SetInterval(AValue: Cardinal);
begin
  if FInterval = AValue then Exit;
  FInterval := AValue;
  { If running, interrupt the current wait — next sleep uses the new interval. }
  if FEnabled then
    RTLEventSetEvent(FEvent);
end;

end.
