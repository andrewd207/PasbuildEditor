{ termui-example-listbox — demonstrates TListBox.

  Layout:
    Left half    TListBox with a list of programming languages
    Right half   detail panel showing info about the selected language

  The "Legacy" items are disabled to show the dim rendering and key skip.

  Keys:
    Up / Down / Home / End / PgUp / PgDn   navigate the list
    Enter                                   "open" the selection (shows message)
    Q or Escape                             quit
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
  TermUI.ListBox;

type
  TListBoxForm = class(TForm)
  private
    FList:   TListBox;
    FLastActivated: string;

    procedure OnActivate(Sender: TObject; Index: Integer);
    procedure OnSelChanged(Sender: TObject; Index: Integer);
    procedure PaintDetail;
    procedure PaintHints;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
    procedure ArrangeChildren; override;
  public
    constructor Create(const ATitle: string = ''); override;
    destructor  Destroy; override;
  end;

const
  Languages: array[0..14] of string = (
    'Free Pascal', 'Delphi', 'C', 'C++', 'Rust', 'Go', 'Python',
    'Ruby', 'Java', 'Kotlin', 'Swift', 'TypeScript', 'Haskell',
    'Ada', 'COBOL'
  );

  Descriptions: array[0..14] of string = (
    'Compiled, object-oriented, cross-platform Pascal dialect.',
    'Commercial Object Pascal IDE and compiler by Embarcadero.',
    'Low-level systems programming language.',
    'C with classes — zero-cost abstractions, templates.',
    'Memory-safe systems language with ownership model.',
    'Statically typed, garbage-collected, fast compilation.',
    'Dynamic, interpreted, beloved for scripts and ML.',
    'Dynamic, expressive, great for web and scripting.',
    'Strongly typed, JVM-based, enterprise standard.',
    'Modern JVM language with null safety.',
    'Apple''s modern language for iOS/macOS development.',
    'Typed superset of JavaScript, compiles to JS.',
    'Purely functional, lazy evaluation, type inference.',
    'Designed for safety-critical real-time systems.',
    'Dinosaur — still running bank mainframes worldwide.'
  );

constructor TListBoxForm.Create(const ATitle: string);
var I: Integer;
begin
  inherited Create(ATitle);

  FList := TListBox.Create;
  FList.OnActivate         := @OnActivate;
  FList.OnSelectionChanged := @OnSelChanged;
  AddChild(FList);

  for I := 0 to High(Languages) do
  begin
    FList.AddItem(Languages[I]);
    { Disable "legacy" languages as a demonstration }
    if Languages[I] = 'COBOL' then
      FList.ItemEnabled[I] := False;
    if Languages[I] = 'Ada' then
      FList.ItemEnabled[I] := False;
  end;

  FLastActivated := '';
  ArrangeChildren;
end;

destructor TListBoxForm.Destroy;
begin
  inherited;
end;

procedure TListBoxForm.ArrangeChildren;
var ListW: Integer;
begin
  if Assigned(FList) then
  begin
    ListW := Width div 2;
    FList.SetBounds(Left, Top, ListW, Height - 1);
  end;
end;

procedure TListBoxForm.OnActivate(Sender: TObject; Index: Integer);
begin
  FLastActivated := FList.Items[Index];
  Invalidate;
end;

procedure TListBoxForm.OnSelChanged(Sender: TObject; Index: Integer);
begin
  Invalidate;
end;

procedure TListBoxForm.PaintDetail;
var
  X, Y, W:  Integer;
  Sel:      Integer;
  Desc:     string;
  Line:     string;
begin
  X   := Left + Width div 2 + 1;
  Y   := Top;
  W   := Width - (Width div 2) - 1;
  Sel := FList.SelectedIndex;

  Term.ResetColors;

  { Panel header }
  Term.GotoXY(X, Y);
  Term.SetFG(clBlack);
  Term.SetBG(clCyan);
  Line := ' Detail';
  while Length(Line) < W do Line := Line + ' ';
  Term.WriteStr(Copy(Line, 1, W));
  Term.ResetColors;
  Inc(Y);

  { Description }
  if (Sel >= 0) and (Sel <= High(Descriptions)) then
    Desc := Descriptions[Sel]
  else
    Desc := 'Select a language on the left.';

  { Word-wrap very simply: just truncate at W }
  Term.GotoXY(X, Y);
  Term.WriteStr(Copy(Desc, 1, W));
  Inc(Y);

  { Activated message }
  Term.GotoXY(X, Y);
  Term.WriteStr(StringOfChar(' ', W));
  if FLastActivated <> '' then
  begin
    Term.GotoXY(X, Y);
    Term.SetFG(clGreen);
    Term.WriteStr('Opened: ' + Copy(FLastActivated, 1, W - 8));
    Term.ResetColors;
  end;

  { Fill remaining detail rows }
  Inc(Y);
  while Y < Top + Height - 1 do
  begin
    Term.GotoXY(X, Y);
    Term.WriteStr(StringOfChar(' ', W));
    Inc(Y);
  end;
end;

procedure TListBoxForm.PaintHints;
var
  Hint: string;
begin
  Hint := ' Arrows=navigate  Enter=open  Q=quit';
  Term.GotoXY(Left, Top + Height - 1);
  Term.SetFG(clBlack);
  Term.SetBG(clWhite);
  while Length(Hint) < Width do Hint := Hint + ' ';
  if Length(Hint) > Width then Hint := Copy(Hint, 1, Width);
  Term.WriteStr(Hint);
  Term.ResetColors;
end;

procedure TListBoxForm.DoPaint;
begin
  inherited DoPaint;
  PaintDetail;
  PaintHints;
end;

function TListBoxForm.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  Result := True;
  case Key.Code of
    kcEscape: Application.Terminate;
    kcChar:
      if (Key.Ch = 'q') or (Key.Ch = 'Q') then
        Application.Terminate
      else
        Result := inherited DoKeyDown(Key);
  else
    Result := inherited DoKeyDown(Key);
  end;
end;

{ ── Main ── }

var
  Form: TListBoxForm;
begin
  Term.EnableRawMode;
  Term.HideCursor;
  Term.EnterAltScreen;
  try
    Form := TListBoxForm.Create('TListBox Example');
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
