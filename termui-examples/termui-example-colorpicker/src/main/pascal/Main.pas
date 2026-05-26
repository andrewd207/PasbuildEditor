{ termui-example-colorpicker — demonstrates TColorPicker.

  The picker fills the entire screen.  The two bottom rows (status line +
  editable hex field + wide sample swatch) are part of the picker itself;
  see TermUI.ColorPicker for the layout.

  Keys:
    Arrow keys                navigate the grid (when grid is focused)
    Enter (in grid)           copy current hex into the field, focus field
    Enter (in hex field)      "accept" — flashes the chosen color above
    Tab                       toggle focus between grid and hex field
    M                         re-open the same picker as a modal dialog
    Q / Escape                quit
}

program Main;

{$mode objfpc}{$H+}

{$IFDEF UNIX}
uses cthreads,
{$ELSE}
uses
{$ENDIF}
  Classes, SysUtils,
  TermUI.Terminal,
  TermUI.Application,
  TermUI.Forms,
  TermUI.Control,
  TermUI.ColorPicker;

type
  TPickerExampleForm = class(TForm)
  private
    FPicker:      TColorPicker;
    FAccepted:    TColor;
    FHasAccepted: Boolean;
    FBanner:      string;

    procedure OnAccepted(Sender: TObject; AColor: TColor);
    procedure DrawBanner;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
    procedure ArrangeChildren; override;
  public
    constructor Create(const ATitle: string = ''); override;
  end;

constructor TPickerExampleForm.Create(const ATitle: string);
begin
  inherited Create(ATitle);
  FPicker := TColorPicker.Create;
  FPicker.OnActivate := @OnAccepted;
  AddChild(FPicker);
  FHasAccepted := False;
  FAccepted    := clDefault;
  FBanner      := '';
  ArrangeChildren;
end;

procedure TPickerExampleForm.ArrangeChildren;
begin
  if Assigned(FPicker) then
    { Reserve the top row for the title bar and a banner line. }
    FPicker.SetBounds(Left, Top + 1, Width, Height - 1);
end;

procedure TPickerExampleForm.OnAccepted(Sender: TObject; AColor: TColor);
begin
  FAccepted    := AColor;
  FHasAccepted := True;
  FBanner      := 'Accepted: ' + Format('#%.2x%.2x%.2x  rgb(%d,%d,%d)',
    [RedOf(AColor), GreenOf(AColor), BlueOf(AColor),
     RedOf(AColor), GreenOf(AColor), BlueOf(AColor)]);
  Invalidate;
end;

procedure TPickerExampleForm.DrawBanner;
var
  Line: string;
  I:    Integer;
begin
  Term.GotoXY(Left, Top);
  if FHasAccepted then
  begin
    Term.SetFG(clBlack);
    Term.SetBG(FAccepted);
    Line := ' ' + FBanner;
    if Length(Line) > Width then Line := Copy(Line, 1, Width);
    Term.WriteStr(Line);
    Term.ResetColors;
    for I := Length(Line) + 1 to Width do Term.WriteStr(' ');
  end
  else
  begin
    Term.SetFG(clBlack);
    Term.SetBG(clWhite);
    Line := ' TColorPicker example  —  Tab to toggle focus, Enter to accept,'
          + ' M for modal, Q to quit';
    if Length(Line) > Width then Line := Copy(Line, 1, Width);
    Term.WriteStr(Line);
    for I := Length(Line) + 1 to Width do Term.WriteStr(' ');
    Term.ResetColors;
  end;
end;

procedure TPickerExampleForm.DoPaint;
begin
  inherited DoPaint;
  DrawBanner;
end;

function TPickerExampleForm.DoKeyDown(var Key: TKeyEvent): Boolean;
var Picked: TColor;
begin
  Result := True;
  case Key.Code of
    kcEscape: Application.Terminate;
    kcChar:
      begin
        if (Key.Ch = 'q') or (Key.Ch = 'Q') then
          Application.Terminate
        else if (Key.Ch = 'm') or (Key.Ch = 'M') then
        begin
          if TColorPicker.PickColor(Picked, FPicker.SelectedColor,
                                    'Modal Color Picker') then
            OnAccepted(Self, Picked);
          Invalidate;
        end
        else
          Result := inherited DoKeyDown(Key);
      end;
  else
    Result := inherited DoKeyDown(Key);
  end;
end;

var
  Form: TPickerExampleForm;
begin
  Term.EnableRawMode;
  Term.HideCursor;
  Term.EnterAltScreen;
  try
    Form := TPickerExampleForm.Create('TColorPicker Example');
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
