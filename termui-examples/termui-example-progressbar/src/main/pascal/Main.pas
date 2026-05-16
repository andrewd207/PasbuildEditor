{ termui-example-progressbar

  Press Enter to start a 5-second simulation.
  The busy indicator spins automatically via its background thread.
  The progress bar advances in 20 steps of 250 ms each.
  Press Q or Escape to quit at any time.
}

program Main;

{$mode objfpc}{$H+}

{$IFDEF UNIX}
uses cthreads,
{$ELSE}
uses
{$ENDIF}
  Classes, SysUtils, SyncObjs,
  TermUI.Terminal,
  TermUI.Application,
  TermUI.Forms,
  TermUI.Control,
  TermUI.ProgressBar;

const
  SIM_STEPS    = 20;
  STEP_MS      = 250;
  HINT_ROW_OFS = 8;   { rows below Top }

type
  TDemoForm = class(TForm)
  private
    FBar:     TProgressBar;
    FBusy:    TBusyIndicator;
    FRunning: Boolean;

    procedure RunSimulation;
    procedure PaintUI;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
    procedure ArrangeChildren; override;
  public
    constructor Create(const ATitle: string = ''); override;
    destructor  Destroy; override;
  end;

constructor TDemoForm.Create(const ATitle: string);
begin
  inherited Create(ATitle);

  FBar := TProgressBar.Create;
  FBar.ShowPercent := True;
  FBar.FillColor   := clGreen;
  AddChild(FBar);

  FBusy          := TBusyIndicator.Create;
  FBusy.Interval := 120;
  AddChild(FBusy);

  ArrangeChildren;
end;

destructor TDemoForm.Destroy;
begin
  FBusy.Active := False;
  inherited;
end;

procedure TDemoForm.ArrangeChildren;
begin
  if Assigned(FBar) then
    FBar.SetBounds(Left + 2, Top + 3, Width - 4, 1);
  if Assigned(FBusy) then
    FBusy.SetBounds(Left + 2, Top + 6, 1, 1);
end;

procedure TDemoForm.PaintUI;
var
  Lbl, Hint: string;
begin
  { Title }
  Term.GotoXY(Left + 2, Top + 1);
  Term.SetFG(clBrightCyan);
  Term.WriteStr('Progress bar + busy indicator demo');
  Term.ResetColors;

  { Progress label }
  Term.GotoXY(Left + 2, Top + 2);
  Term.SetFG(clCyan);
  Term.WriteStr('Progress:');
  Term.ResetColors;

  { Busy label }
  Term.GotoXY(Left + 2, Top + 5);
  Term.SetFG(clCyan);
  Term.WriteStr('Busy indicator:');
  Term.ResetColors;

  { Status beside spinner }
  Term.GotoXY(Left + 4, Top + 6);
  if FRunning then
    Lbl := 'Working… (5 seconds)'
  else if FBar.Value >= 1.0 then
    Lbl := 'Done!              '
  else
    Lbl := 'Idle               ';
  Term.WriteStr(Lbl);

  { Hint bar }
  Hint := ' Enter=start  Q=quit';
  Term.GotoXY(Left, Top + HINT_ROW_OFS);
  Term.SetFG(clBlack);
  Term.SetBG(clWhite);
  while Length(Hint) < Width do Hint := Hint + ' ';
  Term.WriteStr(Copy(Hint, 1, Width));
  Term.ResetColors;
end;

procedure TDemoForm.DoPaint;
begin
  inherited DoPaint;
  PaintUI;
end;

procedure TDemoForm.RunSimulation;
const
  POLL_MS = 20;   { how often to check keys and service Synchronize }
var
  I, J:    Integer;
  Key:     TKeyEvent;
  Aborted: Boolean;
begin
  FRunning     := True;
  FBar.Value   := 0.0;
  FBusy.Active := True;
  Invalidate;
  Paint;
  Term.FlushOutput;

  Aborted := False;
  for I := 1 to SIM_STEPS do
  begin
    { Wait STEP_MS in small slices so CheckSynchronize can process the
      spinner thread's Synchronize calls between each slice. }
    for J := 0 to (STEP_MS div POLL_MS) - 1 do
    begin
      if Term.ReadKeyTimeout(Key, POLL_MS) then
        if (Key.Code = kcEscape) or
           ((Key.Code = kcChar) and ((Key.Ch = 'q') or (Key.Ch = 'Q'))) then
        begin
          Aborted := True;
          Break;
        end;
      CheckSynchronize(0);
    end;
    if Aborted then Break;

    FBar.Value := I / SIM_STEPS;
    FBar.Paint;
    PaintUI;
    Term.FlushOutput;
  end;

  FBusy.Active := False;
  FRunning     := False;
  if Aborted then
    Application.Terminate
  else
    Invalidate;
end;

function TDemoForm.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  Result := True;
  case Key.Code of
    kcEscape: Application.Terminate;
    kcEnter:
      if not FRunning then RunSimulation;
    kcChar:
      if (Key.Ch = 'q') or (Key.Ch = 'Q') then
        Application.Terminate
      else
        Result := False;
  else
    Result := False;
  end;
end;

var
  Form: TDemoForm;
begin
  Term.EnableRawMode;
  Term.HideCursor;
  Term.EnterAltScreen;
  try
    Form := TDemoForm.Create;
    try
      Form.SetBounds(1, 1, Term.Width, Term.Height);
      Application.PushForm(Form);
      Application.Run;
    finally
      Form.Free;
    end;
  finally
    Term.ExitAltScreen;
    Term.ShowCursor;
    Term.DisableRawMode;
  end;
end.
