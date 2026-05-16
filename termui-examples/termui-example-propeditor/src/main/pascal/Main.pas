{ termui-example-propeditor — demonstrates TPropertyEditor.

  Layout:
    Left half    TPropertyEditor (RTTI data source on TServerConfig)
    Right half   TPropertyEditor (TStrings data source with mixed editors)
    Bottom 2 rows  status bar and key hints

  Keys:
    Up/Down/Tab/Shift+Tab   navigate rows
    Enter                   open editor for row
    Escape                  cancel open editor
    Q or Escape (when not editing)  quit
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
  TermUI.PropertyEditor;

{ ── Sample object for RTTI datasource ── }

type
  TLogLevel    = (llDebug, llInfo, llWarning, llError);
  THttpMethod  = (hmGet, hmPost, hmPut, hmDelete, hmPatch, hmOptions);
  THttpMethods = set of THttpMethod;

  TServerConfig = class(TPersistent)
  private
    FHost:           string;
    FPort:           Integer;
    FMaxConns:       Integer;
    FTimeout:        Double;
    FEnableSSL:      Boolean;
    FLogLevel:       TLogLevel;
    FDescription:    string;
    FAllowedMethods: THttpMethods;
  published
    property Host:           string       read FHost           write FHost;
    property Port:           Integer      read FPort           write FPort;
    property MaxConns:       Integer      read FMaxConns       write FMaxConns;
    property Timeout:        Double       read FTimeout        write FTimeout;
    property EnableSSL:      Boolean      read FEnableSSL      write FEnableSSL;
    property LogLevel:       TLogLevel    read FLogLevel       write FLogLevel;
    property Description:    string       read FDescription    write FDescription;
    property AllowedMethods: THttpMethods read FAllowedMethods write FAllowedMethods;
  end;

{ ── Form ── }

type
  TPropForm = class(TForm)
  private
    FLeft:   TPropertyEditor;
    FRight:  TPropertyEditor;
    FConfig: TServerConfig;
    FRTTISrc:    TRTTIDataSource;
    FStringsSrc: TStringsDataSource;
    FStrings:    TStringList;
    FStatus: string;

    procedure PaintStatus;
    procedure OnLeftSel(Sender: TObject);
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
    procedure ArrangeChildren; override;
  public
    constructor Create(const ATitle: string = ''); override;
    destructor  Destroy; override;
  end;

constructor TPropForm.Create(const ATitle: string);
begin
  inherited Create(ATitle);

  { ── RTTI data source on TServerConfig ── }
  FConfig          := TServerConfig.Create;
  FConfig.Host     := 'localhost';
  FConfig.Port     := 8080;
  FConfig.MaxConns := 100;
  FConfig.Timeout  := 30.0;
  FConfig.EnableSSL := False;
  FConfig.LogLevel        := llInfo;
  FConfig.Description     := 'Development server';
  FConfig.AllowedMethods  := [hmGet, hmPost];

  FRTTISrc := TRTTIDataSource.Create(FConfig);

  FLeft := TPropertyEditor.Create;
  FLeft.NameWidth  := 14;
  FLeft.DataSource := FRTTISrc;
  AddChild(FLeft);

  { ── TStrings data source with mixed editor types ── }
  FStrings := TStringList.Create;
  FStrings.Add('Theme=Dark');
  FStrings.Add('Language=Pascal');
  FStrings.Add('TabSize=4');
  FStrings.Add('Encoding=UTF-8');
  FStrings.Add('LineEnding=LF');
  FStrings.Add('AutoSave=True');

  FStringsSrc := TStringsDataSource.Create(FStrings);

  { Theme: fixed combo }
  FStringsSrc.SetEditorType(0, petFixedCombo);
  FStringsSrc.AddChoice(0, 'Dark');
  FStringsSrc.AddChoice(0, 'Light');
  FStringsSrc.AddChoice(0, 'Solarized');
  FStringsSrc.AddChoice(0, 'Monokai');

  { Language: fixed combo }
  FStringsSrc.SetEditorType(1, petFixedCombo);
  FStringsSrc.AddChoice(1, 'Pascal');
  FStringsSrc.AddChoice(1, 'Python');
  FStringsSrc.AddChoice(1, 'Go');
  FStringsSrc.AddChoice(1, 'Rust');
  FStringsSrc.AddChoice(1, 'C');

  { Encoding: fixed combo }
  FStringsSrc.SetEditorType(3, petFixedCombo);
  FStringsSrc.AddChoice(3, 'UTF-8');
  FStringsSrc.AddChoice(3, 'UTF-16');
  FStringsSrc.AddChoice(3, 'Latin-1');

  { LineEnding: fixed combo }
  FStringsSrc.SetEditorType(4, petFixedCombo);
  FStringsSrc.AddChoice(4, 'LF');
  FStringsSrc.AddChoice(4, 'CRLF');
  FStringsSrc.AddChoice(4, 'CR');

  { AutoSave: fixed combo }
  FStringsSrc.SetEditorType(5, petFixedCombo);
  FStringsSrc.AddChoice(5, 'True');
  FStringsSrc.AddChoice(5, 'False');

  FRight := TPropertyEditor.Create;
  FRight.NameWidth  := 12;
  FRight.DataSource := FStringsSrc;
  AddChild(FRight);

  FStatus := 'Enter=edit  Tab=next  Esc=cancel/quit';
  ArrangeChildren;
end;

destructor TPropForm.Destroy;
begin
  FRTTISrc.Free;
  FStringsSrc.Free;
  FStrings.Free;
  FConfig.Free;
  inherited;
end;

procedure TPropForm.OnLeftSel(Sender: TObject);
begin
  Invalidate;
end;

procedure TPropForm.PaintStatus;
var
  Y: Integer;
  L: string;
begin
  Y := Top + Height - 2;

  { Row 1: active property value hint }
  Term.GotoXY(Left, Y);
  Term.SetFG(clBlack);
  Term.SetBG(clWhite);
  L := ' Left: RTTI (TServerConfig)   Right: TStrings (editor settings)';
  while Length(L) < Width do L := L + ' ';
  if Length(L) > Width then L := Copy(L, 1, Width);
  Term.WriteStr(L);

  Inc(Y);
  Term.GotoXY(Left, Y);
  Term.SetFG(clBlack);
  Term.SetBG(clCyan);
  L := ' ' + FStatus;
  while Length(L) < Width do L := L + ' ';
  if Length(L) > Width then L := Copy(L, 1, Width);
  Term.WriteStr(L);

  Term.ResetColors;
end;

procedure TPropForm.DoPaint;
begin
  inherited DoPaint;
  PaintStatus;
end;

function TPropForm.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  Result := True;
  case Key.Code of
    kcEscape:
      begin
        { If neither editor is open, quit }
        if (not FLeft.Editing) and (not FRight.Editing) then
          Application.Terminate
        else
          Result := inherited DoKeyDown(Key);
      end;
    kcChar:
      if (Key.Ch = 'q') or (Key.Ch = 'Q') then
      begin
        if (not FLeft.Editing) and (not FRight.Editing) then
          Application.Terminate
        else
          Result := inherited DoKeyDown(Key);
      end
      else
        Result := inherited DoKeyDown(Key);
  else
    Result := inherited DoKeyDown(Key);
  end;
end;

procedure TPropForm.ArrangeChildren;
var
  Half:       Integer;
  BodyHeight: Integer;
begin
  if not (Assigned(FLeft) and Assigned(FRight)) then Exit;
  BodyHeight := Height - 2;  { reserve 2 rows for status }
  if BodyHeight < 1 then BodyHeight := 1;
  Half := Width div 2;
  FLeft.SetBounds(Left,        Top, Half,         BodyHeight);
  FRight.SetBounds(Left + Half, Top, Width - Half, BodyHeight);
end;

{ ── Main ── }

var
  Form: TPropForm;
begin
  Term.EnableRawMode;
  Term.HideCursor;
  Term.EnterAltScreen;
  try
    Form := TPropForm.Create('TPropertyEditor Example');
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
