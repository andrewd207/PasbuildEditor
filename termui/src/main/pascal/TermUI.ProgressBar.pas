{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.ProgressBar;

{$mode objfpc}{$H+}

{ TProgressBar  — deterministic progress bar (0.0 .. 1.0).
  TBusyIndicator — animated spinner using rotating triangle glyphs and cycling
                   colors; call Step to advance one frame. }

interface

uses
  Classes, SysUtils, TermUI.Terminal, TermUI.Control, TermUI.Application,
  SyncObjs;

type
  { A horizontal progress bar that fills from left to right.

    Set Value (0.0 .. 1.0) to update.  Optionally show a centred percentage
    label by setting ShowPercent := True or provide a custom Label_ string. }
  TProgressBar = class(TControl)
  private
    FValue:       Double;    { 0.0 .. 1.0 }
    FShowPercent: Boolean;
    FLabel:       string;    { overrides percentage when non-empty }
    FFillColor:   TColor;
    FTrackColor:  TColor;
    procedure SetValue(AValue: Double);
  protected
    procedure DoPaint; override;
  public
    constructor Create; override;

    property Value:       Double  read FValue       write SetValue;
    property ShowPercent: Boolean read FShowPercent write FShowPercent;
    { Custom text centred over the bar.  When empty and ShowPercent=True,
      the percentage is shown instead. }
    property Label_:      string  read FLabel       write FLabel;
    property FillColor:   TColor  read FFillColor   write FFillColor;
    property TrackColor:  TColor  read FTrackColor  write FTrackColor;
  end;

  TBusyIndicator = class;

  { Background thread that calls TBusyIndicator.DoStep via Synchronize
    at the configured interval. }
  TBusyThread = class(TThread)
  private
    FOwner:    TBusyIndicator;
    FInterval: Integer;      { ms between frames }
    FStop:     TEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TBusyIndicator; AIntervalMs: Integer);
    destructor  Destroy; override;
    procedure RequestStop;
  end;

  { An animated busy indicator that cycles through four triangle glyphs
    (▶ ▼ ◀ ▲) with cycling foreground colors.  The indicator occupies a
    single cell at the control's top-left corner.

    Set Active := True to start the background animation thread; the thread
    calls DoStep via TThread.Synchronize so it runs on the main thread and is
    safe to touch the terminal back-buffer.  DoStep writes only the single
    cell and calls Term.FlushRow — no full-screen redraw occurs.

    Set Active := False (or free the control) to stop the thread.

    Manual control is still available: call Step at any time from the main
    thread (e.g. inside a processing loop) regardless of Active state. }
  TBusyIndicator = class(TControl)
  private
    const
      GlyphCount = 4;
    var
      FFrame:    Integer;
      FThread:   TBusyThread;
      FInterval: Integer;
      FActive:   Boolean;
      FGlyphs:   array[0..GlyphCount - 1] of TDrawingChar;
      FColors:   array[0..GlyphCount - 1] of TColor;

    procedure SetActive(AValue: Boolean);
    procedure SetInterval(AValue: Integer);
    { Called on the main thread (via Synchronize) by the background thread. }
    procedure DoStep;
  protected
    procedure DoPaint; override;
  public
    constructor Create; override;
    destructor  Destroy; override;

    { Advance one animation frame immediately on the calling thread.
      Writes only the indicator cell and flushes just that row. }
    procedure Step;

    property Frame:    Integer read FFrame;
    { Start (True) or stop (False) the automatic animation thread. }
    property Active:   Boolean read FActive   write SetActive;
    { Milliseconds between frames.  Default: 150.
      Changing while Active has no effect until the next SetActive(True). }
    property Interval: Integer read FInterval write SetInterval;
  end;

implementation

{ ── TProgressBar ── }

constructor TProgressBar.Create;
begin
  inherited Create;
  FFillColor  := clCyan;
  FTrackColor := clDefault;
  FValue      := 0.0;
end;

procedure TProgressBar.SetValue(AValue: Double);
begin
  if AValue < 0.0 then AValue := 0.0;
  if AValue > 1.0 then AValue := 1.0;
  if FValue = AValue then Exit;
  FValue := AValue;
  Invalidate;
end;

procedure TProgressBar.DoPaint;
var
  W, FillW, I: Integer;
  Lbl:         string;
  LblPos:      Integer;
  IsFill:      Boolean;
  Ch:          Char;
begin
  W     := Width;
  FillW := Round(FValue * W);

  { Build optional label }
  if FLabel <> '' then
    Lbl := FLabel
  else if FShowPercent then
    Lbl := Format('%3d%%', [Round(FValue * 100)])
  else
    Lbl := '';

  LblPos := (W - Length(Lbl)) div 2 + 1;  { 1-based start column }

  GotoLocal(1, 1);
  for I := 1 to W do
  begin
    IsFill := I <= FillW;

    { Determine the label character for this column (if any) }
    if (Lbl <> '') and (I >= LblPos) and (I < LblPos + Length(Lbl)) then
      Ch := Lbl[I - LblPos + 1]
    else
      Ch := ' ';

    if IsFill then
    begin
      Term.SetFG(clBlack);
      Term.SetBG(FFillColor);
    end
    else
    begin
      Term.SetFG(clDefault);
      Term.SetBG(FTrackColor);
    end;
    Term.WriteStr(Ch);
  end;

  Term.ResetColors;
end;

{ ── TBusyThread ── }

constructor TBusyThread.Create(AOwner: TBusyIndicator; AIntervalMs: Integer);
begin
  FOwner    := AOwner;
  FInterval := AIntervalMs;
  FStop     := TEvent.Create(nil, True, False, '');
  FreeOnTerminate := False;
  inherited Create(False);
end;

destructor TBusyThread.Destroy;
begin
  FStop.Free;
  inherited;
end;

procedure TBusyThread.Execute;
begin
  while not Terminated do
  begin
    { Wait for the interval or until stop is signalled }
    if FStop.WaitFor(FInterval) = wrSignaled then Break;
    if Terminated then Break;
    Synchronize(@FOwner.DoStep);
  end;
end;

procedure TBusyThread.RequestStop;
begin
  Terminate;
  FStop.SetEvent;
end;

{ ── TBusyIndicator ── }

constructor TBusyIndicator.Create;
begin
  inherited Create;
  FFrame     := 0;
  FInterval  := 150;
  FGlyphs[0] := dcTreeCollapsed;   { ▶ }
  FGlyphs[1] := dcArrowDown;       { ▼ }
  FGlyphs[2] := dcArrowLeft;       { ◀ }
  FGlyphs[3] := dcArrowUp;         { ▲ }
  FColors[0]  := clCyan;
  FColors[1]  := clGreen;
  FColors[2]  := clYellow;
  FColors[3]  := clMagenta;
end;

destructor TBusyIndicator.Destroy;
begin
  SetActive(False);
  inherited;
end;

procedure TBusyIndicator.SetActive(AValue: Boolean);
begin
  if AValue = FActive then Exit;
  FActive := AValue;
  if AValue then
  begin
    FThread := TBusyThread.Create(Self, FInterval);
  end
  else if Assigned(FThread) then
  begin
    FThread.RequestStop;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
end;

procedure TBusyIndicator.SetInterval(AValue: Integer);
begin
  if AValue < 50 then AValue := 50;
  FInterval := AValue;
end;

procedure TBusyIndicator.DoStep;
begin
  FFrame := (FFrame + 1) mod GlyphCount;
  { Write directly to the back buffer and flush only the indicator's row.
    This avoids triggering a full-screen repaint. }
  GotoLocal(1, 1);
  Term.SetFG(FColors[FFrame]);
  Application.DrawChar(FGlyphs[FFrame]);
  Term.ResetColors;
  Term.FlushRow(Top);
end;

procedure TBusyIndicator.DoPaint;
begin
  GotoLocal(1, 1);
  Term.SetFG(FColors[FFrame]);
  Application.DrawChar(FGlyphs[FFrame]);
  Term.ResetColors;
end;

procedure TBusyIndicator.Step;
begin
  DoStep;
end;

end.
