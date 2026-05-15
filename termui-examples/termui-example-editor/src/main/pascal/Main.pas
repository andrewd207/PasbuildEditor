{
  termui-example-editor — a minimal text-file editor built on TermUI.

  Layout (top to bottom):
    Row 1            TTitleBar  — filename, line:col, modified flag
                     TMenuBar   — peek overlay; covers the title bar when open
    Rows 2..H-1      TTextEditor
    Row H            hint bar   — key bindings painted in DoPaint

  Opening the menu:
    Alt+F1           show menu bar and open first submenu
    Alt (any letter) show menu bar; if no matching submenu just shows the bar

  Keyboard shortcuts (also available via menu):
    Ctrl+N   new file
    Ctrl+O   open file
    Ctrl+S   save
    Ctrl+A   save as
    Ctrl+Q   quit
}

program Main;

{$mode objfpc}{$H+}

{$IFDEF UNIX}
uses
  cthreads,
{$ELSE}
uses
{$ENDIF}
  Classes, SysUtils, StrUtils, TermUI.StringUtils,
  TermUI.Terminal,
  TermUI.Application,
  TermUI.Forms,
  TermUI.Control,
  TermUI.Control.TitleBar,
  TermUI.Control.Editor,
  TermUI.Menu,
  TermUI.MenuBar,
  TermUI.Form.FileDialog,
  TermUI.Highlighter.Pascal,
  TermUI.Highlighter.AsciiDoc,
  TermUI.Highlighter.XML,
  TermUI.Highlighter.Markdown;

const
  HINT_ROWS = 1;

type
  TEditorForm = class(TForm)
  private
    FTitleBar:   TTitleBar;
    FEditor:     TTextEditor;
    FMenuBar:    TMenuBar;
    FEditMenu:   TMenuBarItem;    { Edit top-level item; used to rebuild submenu }
    FFilePath:   string;
    FModified:   Boolean;

    procedure EditorChanged(Sender: TObject);
    procedure UpdateTitleBar;
    procedure BuildHighlighterSubmenu;

    function  CheckSave: Boolean;
    procedure DoNew(Sender: TObject = nil);
    procedure DoOpen(Sender: TObject = nil);
    procedure DoSave(Sender: TObject = nil);
    procedure DoSaveAs(Sender: TObject = nil);
    procedure DoQuit(Sender: TObject = nil);
    procedure DoSelectHighlighterItem(Sender: TObject);

    procedure OpenFile(const APath: string);
    procedure ApplyHighlighterForPath(const APath: string);

    procedure PaintHintBar;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
    procedure ArrangeChildren; override;
  public
    constructor Create(const ATitle: string = ''); override;
    destructor  Destroy; override;
  end;

{ ── helpers ── }

function AskYesNo(const APrompt: string): Boolean;
var
  Key: TKeyEvent;
begin
  Term.GotoXY(1, Term.Height - 2);
  Term.ResetColors;
  Term.SetFG(clYellow);
  Term.WriteStr(APrompt + ' [Y/N] ');
  Term.ResetColors;
  Term.ShowCursor;
  repeat
    Term.ReadKeyTimeout(Key, -1);
  until Key.Code in [kcChar, kcEscape, kcEnter];
  Term.HideCursor;
  Result := (Key.Code = kcChar) and (UpCase(Key.Ch) = 'Y');
end;

{ ── TEditorForm ── }

constructor TEditorForm.Create(const ATitle: string);
var
  FileMenu, HelpMenu: TMenuBarItem;
begin
  inherited Create(ATitle);

  { Title bar }
  FTitleBar := TTitleBar.Create;
  FTitleBar.BackColor := clCyan;
  FTitleBar.ForeColor := clBlack;
  AddChild(FTitleBar);

  { Editor }
  FEditor := TTextEditor.Create;
  FEditor.OnChange := @EditorChanged;
  AddChild(FEditor);

  FFilePath := '';
  FModified := False;
  UpdateTitleBar;

  { Menu bar — peek overlay, not a child control }
  FMenuBar := TMenuBar.Create;

  FileMenu := FMenuBar.AddItem('&File');
  FileMenu.Items.Add(TMenuItem.CreateEmbeddedHotkey('&New',     @DoNew));
  FileMenu.Items.Add(TMenuItem.CreateEmbeddedHotkey('&Open',    @DoOpen));
  FileMenu.Items.Add(TMenuItem.CreateEmbeddedHotkey('&Save',    @DoSave));
  FileMenu.Items.Add(TMenuItem.CreateEmbeddedHotkey('Save &As', @DoSaveAs));
  FileMenu.Items.Add(TMenuItem.CreateSeparator);
  FileMenu.Items.Add(TMenuItem.CreateEmbeddedHotkey('&Quit',    @DoQuit));

  FEditMenu := FMenuBar.AddItem('&Edit');
  BuildHighlighterSubmenu;

  HelpMenu := FMenuBar.AddItem('&Help');
  HelpMenu.Items.Add(TMenuItem.CreateEmbeddedHotkey('&About', nil));

  { TForm.Create called ArrangeChildren before children existed.
    Call it now that all children are in place. }
  ArrangeChildren;
end;

destructor TEditorForm.Destroy;
begin
  FMenuBar.Free;
  inherited;
end;

procedure TEditorForm.UpdateTitleBar;
var
  Name, Info: string;
begin
  if not Assigned(FTitleBar) then Exit;
  if FFilePath <> '' then
    Name := ExtractFileName(FFilePath)
  else
    Name := '[new file]';
  if FModified then Name := Name + ' *';
  Info := 'Alt+F1=Menu';
  FTitleBar.Title     := Name;
  FTitleBar.RightText := Info;
end;

procedure TEditorForm.EditorChanged(Sender: TObject);
begin
  FModified := True;
  UpdateTitleBar;
end;

procedure TEditorForm.ArrangeChildren;
begin
  if Assigned(FTitleBar) then
    FTitleBar.SetBounds(Left, Top, Width, 1);
  if Assigned(FEditor) then
    FEditor.SetBounds(Left, Top + 1, Width, Height - 1 - HINT_ROWS);
end;

procedure TEditorForm.PaintHintBar;
var
  Hints: string;
begin
  Term.GotoXY(Left, Top + Height - 1);
  Term.SetFG(clBlack);
  Term.SetBG(clWhite);
  Hints := ' ^N New  ^O Open  ^S Save  ^A Save As  ^Q Quit  Alt+F1 Menu ';
  while Length(Hints) < Width do Hints := Hints + ' ';
  if Length(Hints) > Width then Hints := CopyNeutral(Hints, 0, Width);
  Term.WriteStr(Hints);
  Term.ResetColors;
end;

procedure TEditorForm.DoPaint;
begin
  inherited DoPaint;   { paints title bar + editor }
  PaintHintBar;
end;

function TEditorForm.CheckSave: Boolean;
begin
  if not FModified then begin Result := True; Exit; end;
  Invalidate; Paint;
  Result := not AskYesNo('Unsaved changes — save first?');
  if not Result then
  begin
    DoSave;
    Result := not FModified;
  end;
  Invalidate;
end;

procedure TEditorForm.ApplyHighlighterForPath(const APath: string);
var
  Ext: string;
  HL:  TTextHighlighter;
begin
  Ext := LowerCase(ExtractFileExt(APath));
  HL  := FindHighlighterForExt(Ext);
  if Assigned(FEditor.Highlighter) then
    FEditor.Highlighter.Free;
  FEditor.Highlighter := HL;
  BuildHighlighterSubmenu;
end;

procedure TEditorForm.OpenFile(const APath: string);
begin
  FEditor.Lines.LoadFromFile(APath);
  FFilePath := APath;
  FModified := False;
  ApplyHighlighterForPath(APath);
  UpdateTitleBar;
  Invalidate;
end;

procedure TEditorForm.DoNew(Sender: TObject);
begin
  if not CheckSave then Exit;
  FEditor.Clear;
  if Assigned(FEditor.Highlighter) then
    FEditor.Highlighter.Free;
  FEditor.Highlighter := nil;
  FFilePath := '';
  FModified := False;
  UpdateTitleBar;
  BuildHighlighterSubmenu;
  Invalidate;
end;

procedure TEditorForm.DoOpen(Sender: TObject);
var
  Path: string;
begin
  if not CheckSave then Exit;
  Path := '';
  if not RunOpenDialog(GetCurrentDir, Path, 'Open File') then Exit;
  try
    OpenFile(Path);
  except
    on E: Exception do
    begin
      Invalidate; Paint;
      AskYesNo('Error opening file: ' + E.Message + '  (press N)');
      Invalidate;
    end;
  end;
end;

procedure TEditorForm.DoSaveAs(Sender: TObject);
var
  Path: string;
begin
  Path := FFilePath;
  if not RunSaveDialog(
      IfThen(FFilePath <> '', ExtractFileDir(FFilePath), GetCurrentDir),
      Path, 'Save As') then Exit;
  try
    FEditor.Lines.SaveToFile(Path);
    FFilePath := Path;
    FModified := False;
    UpdateTitleBar;
    Invalidate;
  except
    on E: Exception do
    begin
      Invalidate; Paint;
      AskYesNo('Error saving file: ' + E.Message + '  (press N)');
      Invalidate;
    end;
  end;
end;

procedure TEditorForm.DoSave(Sender: TObject);
begin
  if FFilePath = '' then
    DoSaveAs
  else
  begin
    try
      FEditor.Lines.SaveToFile(FFilePath);
      FModified := False;
      UpdateTitleBar;
      Invalidate;
    except
      on E: Exception do
      begin
        Invalidate; Paint;
        AskYesNo('Error saving file: ' + E.Message + '  (press N)');
        Invalidate;
      end;
    end;
  end;
end;

procedure TEditorForm.DoQuit(Sender: TObject);
begin
  if CheckSave then Application.Terminate;
end;

procedure TEditorForm.BuildHighlighterSubmenu;
const
  HLGroup = 1;
var
  Names:   TStringList;
  I:       Integer;
  SubItem: TMenuItem;
  HLItem:  TMenuItem;
  Current: string;
begin
  FEditMenu.Items.Clear;
  if Assigned(FEditor.Highlighter) then
    Current := FEditor.Highlighter.Name
  else
    Current := 'None';

  HLItem := TMenuItem.CreateSubmenu('Highlighter');

  Names := TStringList.Create;
  try
    GetHighlighterNames(Names);

    SubItem := TMenuItem.CreateRadio('None', HLGroup, @DoSelectHighlighterItem,
                 Current = 'None');
    HLItem.SubItems.Add(SubItem);

    for I := 0 to Names.Count - 1 do
    begin
      SubItem := TMenuItem.CreateRadio(Names[I], HLGroup,
                   @DoSelectHighlighterItem, Names[I] = Current);
      HLItem.SubItems.Add(SubItem);
    end;
  finally
    Names.Free;
  end;

  FEditMenu.Items.Add(HLItem);
end;

procedure TEditorForm.DoSelectHighlighterItem(Sender: TObject);
var
  Item: TMenuItem;
  HL:   TTextHighlighter;
begin
  Item := TMenuItem(Sender);
  if Assigned(FEditor.Highlighter) then
    FEditor.Highlighter.Free;

  if Item.Label_ = 'None' then
    HL := nil
  else
    HL := FindHighlighterByName(Item.Label_);

  FEditor.Highlighter := HL;
  Invalidate;
end;

function TEditorForm.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  Result := True;
  case Key.Code of
    kcCtrlN: DoNew;
    kcCtrlO: DoOpen;
    kcCtrlS: DoSave;
    kcCtrlA: DoSaveAs;
    kcCtrlQ: DoQuit;
    kcAltF1:
      begin
        Application.ShowPeek(FMenuBar);
        FMenuBar.ActivateAccel(#0);   { show bar, no submenu pre-selected }
      end;
    kcAltChar:
      begin
        Application.ShowPeek(FMenuBar);
        FMenuBar.ActivateAccel(Key.Ch);
      end;
  else
    Result := inherited DoKeyDown(Key);
  end;
end;

{ ── Main ── }

var
  Form: TEditorForm;
  Arg:  string;
begin
  Term.EnableRawMode;
  Term.HideCursor;
  Term.EnterAltScreen;
  try
    Form := TEditorForm.Create('Editor');
    try
      Form.SetBounds(1, 1, Term.Width, Term.Height);
      Application.PushForm(Form);

      { Handle command-line filename argument. }
      if ParamCount >= 1 then
      begin
        Arg := ParamStr(1);
        if FileExists(Arg) then
        begin
          try
            Form.OpenFile(Arg);
          except
            { silently fall back to new document }
          end;
        end
        else
        begin
          { Non-existent file: use as target path, mark modified }
          Form.FFilePath := ExpandFileName(Arg);
          Form.FModified := True;
          Form.UpdateTitleBar;
        end;
      end;

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
