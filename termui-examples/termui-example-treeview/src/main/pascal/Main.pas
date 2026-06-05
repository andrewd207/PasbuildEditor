{ termui-example-treeview — demonstrates TTreeView.

  Layout:
    Top half     TTreeView showing a simulated file-system tree
    Bottom 3 rows status bar (selection info + key hints)

  Features shown:
    - Concrete nodes added via AddRoot / AddChild
    - Lazy loading via OnExpanding (simulated sub-directories)
    - Disabled node (the "Locked" entry)
    - Checkboxes with tri-state propagation
    - ShowLines guide-lines
    - IndentWidth = 3

  Keys:
    Up/Down/Left/Right/Enter/Space as per TTreeView
    Q or Escape   quit
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
  TermUI.TreeView;

const
  STATUS_ROWS = 3;

type
  TTreeForm = class(TForm)
  private
    FTree:    TTreeView;
    FStatus:  string;

    procedure OnExpanding(Sender: TObject; Node: TTreeNode; var DoExpand: Boolean);
    procedure OnActivate(Sender: TObject; Node: TTreeNode);
    procedure OnSelChanged(Sender: TObject; Node: TTreeNode);
    procedure PaintStatus;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
    procedure ArrangeChildren; override;
  public
    constructor Create(const ATitle: string = ''); override;
    destructor  Destroy; override;
  end;

constructor TTreeForm.Create(const ATitle: string);
var
  Src, Bin, Doc, Locked: TTreeNode;
  Child: TTreeNode;
begin
  inherited Create(ATitle);

  FTree := TTreeView.Create;
  FTree.ShowLines   := True;
  FTree.IndentWidth := 3;
  FTree.OnExpanding    := @OnExpanding;
  FTree.OnActivate     := @OnActivate;
  FTree.OnSelectionChanged := @OnSelChanged;
  AddChild(FTree);

  { Concrete tree — src/ }
  Src := FTree.AddRoot('src/');
  Src.Glyph    := 'D';
  Src.HasGlyph := True;

  Child := Src.AddChild('main.pas');
  Child.Glyph    := 'F';
  Child.HasGlyph := True;

  Child := Src.AddChild('utils.pas');
  Child.Glyph    := 'F';
  Child.HasGlyph := True;

  Child := Src.AddChild('config.pas');
  Child.Glyph    := 'F';
  Child.HasGlyph := True;

  { bin/ — lazy: children added in OnExpanding }
  Bin := FTree.AddRoot('bin/');
  Bin.Glyph    := 'D';
  Bin.HasGlyph := True;
  Bin.Loaded   := False;   { mark as not yet loaded so OnExpanding fires }

  { docs/ }
  Doc := FTree.AddRoot('docs/');
  Doc.Glyph    := 'D';
  Doc.HasGlyph := True;
  Doc.AddChild('README.md').HasGlyph := False;
  Doc.AddChild('API.md').HasGlyph    := False;

  { Locked — disabled }
  Locked := FTree.AddRoot('locked/');
  Locked.Glyph    := 'L';
  Locked.HasGlyph := True;
  Locked.Enabled  := False;

  FStatus := 'Select a node with arrow keys.';
  ArrangeChildren;
end;

destructor TTreeForm.Destroy;
begin
  inherited;
end;

procedure TTreeForm.OnExpanding(Sender: TObject; Node: TTreeNode; var DoExpand: Boolean);
begin
  { Only lazy-load nodes that haven't been loaded yet (e.g. bin/).
    Leaves like file nodes are already Loaded := True and must not gain children. }
  if Node.Loaded then Exit;
  Node.AddChild('myapp');
  Node.AddChild('myapp.dbg');
  Node.Loaded := True;
end;

procedure TTreeForm.OnActivate(Sender: TObject; Node: TTreeNode);
begin
  FStatus := 'Activated: ' + Node.Text;
  Invalidate;
end;

procedure TTreeForm.OnSelChanged(Sender: TObject; Node: TTreeNode);
begin
  if Node <> nil then
    FStatus := 'Selected: ' + Node.Text
  else
    FStatus := '';
  Invalidate;
end;

procedure TTreeForm.PaintStatus;
var
  Y:    Integer;
  Hint: string;
  Line: string;
begin
  Y    := Top + Height - STATUS_ROWS;
  Hint := ' Arrows=navigate  Enter=expand/collapse  Space=check  Q=quit';

  Term.GotoXY(Left, Y);
  Term.SetFG(clBlack);
  Term.SetBG(clWhite);
  Line := ' ' + FStatus;
  while Length(Line) < Width do Line := Line + ' ';
  if Length(Line) > Width then Line := Copy(Line, 1, Width);
  Term.WriteStr(Line);

  Inc(Y);
  Term.GotoXY(Left, Y);
  Term.SetFG(clBlack);
  Term.SetBG(clCyan);
  Line := Hint;
  while Length(Line) < Width do Line := Line + ' ';
  if Length(Line) > Width then Line := Copy(Line, 1, Width);
  Term.WriteStr(Line);

  Inc(Y);
  Term.GotoXY(Left, Y);
  Term.ResetColors;
  Term.WriteStr(StringOfChar(' ', Width));

  Term.ResetColors;
end;

procedure TTreeForm.DoPaint;
begin
  inherited DoPaint;
  PaintStatus;
end;

function TTreeForm.DoKeyDown(var Key: TKeyEvent): Boolean;
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

procedure TTreeForm.ArrangeChildren;
begin
  if Assigned(FTree) then
    FTree.SetBounds(Left, Top, Width, Height - STATUS_ROWS);
end;

{ ── Main ── }

var
  Form: TTreeForm;
begin
  Term.EnableRawMode;
  Term.HideCursor;
  Term.EnterAltScreen;
  try
    Form := TTreeForm.Create('TTreeView Example');
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
