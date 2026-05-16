{ termui-example-editor-completion — TCompletionPopup with the multi-line TTextEditor.

  Layout:
    Most of the screen is a TTextEditor pre-loaded with a short Pascal program.
    A status bar at the bottom shows the cursor position and completion hint.

  Completion fires on every change (OnChange).  The word-list source scans the
  editor's own Lines so every identifier you type becomes a future suggestion.
  A Pascal keyword source and a small built-in symbol table are chained on top.

  Key bindings (while completion popup is visible):
    Down / Up        navigate the completion list
    Enter            commit selected item — replaces the whole word under cursor
    Tab              commit selected item — replaces only the prefix before cursor
    Space            commit selected item then insert a space
    Escape           dismiss popup (suppressed until cursor moves)

  Key bindings (always):
    Ctrl+Q           quit
    All normal TTextEditor bindings work (arrows, Home/End, Shift+arrows, etc.)
}

program Main;

{$mode objfpc}{$H+}
{$modeswitch typehelpers}

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
  TermUI.StringUtils,
  TermUI.Completion,
  TermUI.Control.Editor,
  TermUI.Highlighter.Pascal;

{ ── Chained data source ─────────────────────────────────────────────────── }

type
  TChainedDataSource = class(TCompletionDataSource)
  private
    FSources: array of TCompletionDataSource;  { not owned }
  public
    procedure AddSource(ASource: TCompletionDataSource);
    procedure GetCompletions(const ACtx: TCompletionContext;
                             AList: TCompletionList); override;
    function  ShouldTrigger(const ACtx: TCompletionContext): Boolean; override;
    function  CommitChars: string; override;
    function  WordChars: string; override;
  end;

procedure TChainedDataSource.AddSource(ASource: TCompletionDataSource);
begin
  SetLength(FSources, Length(FSources) + 1);
  FSources[High(FSources)] := ASource;
end;

procedure TChainedDataSource.GetCompletions(const ACtx: TCompletionContext;
  AList: TCompletionList);
var
  Scratch: TCompletionList;
  Seen:    TStringList;
  S, I:    Integer;
  Item:    TCompletionItem;
begin
  Seen    := TStringList.Create;
  Scratch := TCompletionList.Create;
  try
    for S := 0 to High(FSources) do
    begin
      Scratch.Clear;
      FSources[S].GetCompletions(ACtx, Scratch);
      for I := 0 to Scratch.Count - 1 do
      begin
        Item := Scratch[I];
        if Seen.IndexOf(Item.DisplayText) < 0 then
        begin
          Seen.Add(Item.DisplayText);
          AList.Add(Item.DisplayText, Item.Kind, Item.InsertText, Item.Detail);
        end;
      end;
    end;
  finally
    Scratch.Free;
    Seen.Free;
  end;
end;

function TChainedDataSource.ShouldTrigger(const ACtx: TCompletionContext): Boolean;
var S: Integer;
begin
  for S := 0 to High(FSources) do
    if FSources[S].ShouldTrigger(ACtx) then Exit(True);
  Result := False;
end;

function TChainedDataSource.CommitChars: string;
begin
  Result := '.';
end;

function TChainedDataSource.WordChars: string;
begin
  Result := '';
end;

{ ── Keyword data source ─────────────────────────────────────────────────── }

type
  TKeywordDataSource = class(TCompletionDataSource)
  private
    FKeywords: TStringList;
  public
    constructor Create;
    destructor  Destroy; override;
    procedure GetCompletions(const ACtx: TCompletionContext;
                             AList: TCompletionList); override;
    function  ShouldTrigger(const ACtx: TCompletionContext): Boolean; override;
  end;

const
  PascalKeywords: array[0..47] of string = (
    'and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const',
    'constructor', 'destructor', 'div', 'do', 'downto', 'else', 'end',
    'except', 'exports', 'file', 'finalization', 'finally', 'for',
    'function', 'goto', 'if', 'implementation', 'inherited', 'initialization',
    'inline', 'interface', 'is', 'label', 'mod', 'nil', 'not', 'object',
    'of', 'operator', 'or', 'override', 'packed', 'procedure', 'program',
    'property', 'published', 'raise', 'record', 'repeat', 'result'
  );

constructor TKeywordDataSource.Create;
var I: Integer;
begin
  inherited Create;
  FKeywords := TStringList.Create;
  for I := 0 to High(PascalKeywords) do
    FKeywords.Add(PascalKeywords[I]);
end;

destructor TKeywordDataSource.Destroy;
begin
  FKeywords.Free;
  inherited;
end;

procedure TKeywordDataSource.GetCompletions(const ACtx: TCompletionContext;
  AList: TCompletionList);
var
  PfxLo, KwLo: string;
  I:            Integer;
begin
  PfxLo := LowerCase(ACtx.Prefix);
  for I := 0 to FKeywords.Count - 1 do
  begin
    KwLo := FKeywords[I];
    if (KwLo <> PfxLo) and (KwLo.Pos(PfxLo) = 0) then
      AList.Add(FKeywords[I], ckKeyword);
  end;
end;

function TKeywordDataSource.ShouldTrigger(const ACtx: TCompletionContext): Boolean;
begin
  Result := ACtx.Prefix.Length >= 2;
end;

{ ── Symbol data source ──────────────────────────────────────────────────── }

type
  TSymbolEntry = record
    Name:   string;
    Kind:   TCompletionKind;
    Detail: string;
  end;

  TSymbolDataSource = class(TCompletionDataSource)
  private
    FSymbols: array of TSymbolEntry;
    procedure AddSym(const AName: string; AKind: TCompletionKind;
                     const ADetail: string = '');
  public
    constructor Create;
    procedure GetCompletions(const ACtx: TCompletionContext;
                             AList: TCompletionList); override;
    function  ShouldTrigger(const ACtx: TCompletionContext): Boolean; override;
  end;

procedure TSymbolDataSource.AddSym(const AName: string; AKind: TCompletionKind;
  const ADetail: string);
var N: Integer;
begin
  N := Length(FSymbols);
  SetLength(FSymbols, N + 1);
  FSymbols[N].Name   := AName;
  FSymbols[N].Kind   := AKind;
  FSymbols[N].Detail := ADetail;
end;

constructor TSymbolDataSource.Create;
begin
  inherited Create;
  AddSym('WriteLn',        ckFunction, 'procedure');
  AddSym('Write',          ckFunction, 'procedure');
  AddSym('ReadLn',         ckFunction, 'procedure');
  AddSym('IntToStr',       ckFunction, 'function: string');
  AddSym('StrToInt',       ckFunction, 'function: Integer');
  AddSym('StrToIntDef',    ckFunction, 'function: Integer');
  AddSym('LowerCase',      ckFunction, 'function: string');
  AddSym('UpperCase',      ckFunction, 'function: string');
  AddSym('Trim',           ckFunction, 'function: string');
  AddSym('Length',         ckFunction, 'function: Integer');
  AddSym('Copy',           ckFunction, 'function: string');
  AddSym('Pos',            ckFunction, 'function: Integer');
  AddSym('SetLength',      ckFunction, 'procedure');
  AddSym('Assigned',       ckFunction, 'function: Boolean');
  AddSym('FreeAndNil',     ckFunction, 'procedure');
  AddSym('SizeOf',         ckFunction, 'function: Integer');
  AddSym('Ord',            ckFunction, 'function: Integer');
  AddSym('Chr',            ckFunction, 'function: Char');
  AddSym('Inc',            ckFunction, 'procedure');
  AddSym('Dec',            ckFunction, 'procedure');
  AddSym('High',           ckFunction, 'function: Integer');
  AddSym('Low',            ckFunction, 'function: Integer');
  AddSym('Result',         ckVariable, 'return value');
  AddSym('Self',           ckVariable, 'current instance');
  AddSym('True',           ckVariable, 'Boolean');
  AddSym('False',          ckVariable, 'Boolean');
  AddSym('MaxInt',         ckVariable, 'Integer');
  AddSym('Integer',        ckType);
  AddSym('Cardinal',       ckType);
  AddSym('Int64',          ckType);
  AddSym('Boolean',        ckType);
  AddSym('Char',           ckType);
  AddSym('string',         ckType);
  AddSym('Single',         ckType);
  AddSym('Double',         ckType);
  AddSym('Pointer',        ckType);
  AddSym('TObject',        ckType);
  AddSym('TClass',         ckType);
  AddSym('TStringList',    ckType);
  AddSym('TList',          ckType);
  AddSym('TComponent',     ckType);
  AddSym('Exception',      ckType);
  AddSym('Classes',        ckModule);
  AddSym('SysUtils',       ckModule);
  AddSym('Math',           ckModule);
  AddSym('StrUtils',       ckModule);
  AddSym('Contnrs',        ckModule);
  AddSym('TypInfo',        ckModule);
end;

procedure TSymbolDataSource.GetCompletions(const ACtx: TCompletionContext;
  AList: TCompletionList);
var
  PfxLo, NamLo: string;
  I:             Integer;
begin
  PfxLo := LowerCase(ACtx.Prefix);
  for I := 0 to High(FSymbols) do
  begin
    NamLo := LowerCase(FSymbols[I].Name);
    if (NamLo <> PfxLo) and (NamLo.Pos(PfxLo) = 0) then
      AList.Add(FSymbols[I].Name, FSymbols[I].Kind, '', FSymbols[I].Detail);
  end;
end;

function TSymbolDataSource.ShouldTrigger(const ACtx: TCompletionContext): Boolean;
begin
  Result := ACtx.Prefix.Length >= 1;
end;

{ ── Form ────────────────────────────────────────────────────────────────── }

const
  StartCode: array[0..22] of string = (
    'program MyProgram;',
    '',
    '{$mode objfpc}{$H+}',
    '',
    'uses Classes, SysUtils;',
    '',
    'type',
    '  TMyObject = class(TObject)',
    '  private',
    '    FValue: Integer;',
    '    FName:  string;',
    '  public',
    '    constructor Create(const AName: string);',
    '    destructor  Destroy; override;',
    '    function    GetValue: Integer;',
    '    procedure   SetValue(AVal: Integer);',
    '    property Name:  string  read FName  write FName;',
    '    property Value: Integer read FValue write SetValue;',
    '  end;',
    '',
    'var',
    '  MyObj: TMyObject;',
    ''
  );

type
  TEditorCompletionForm = class(TForm)
  private
    FEditor:     TTextEditor;
    FWordSrc:    TWordListDataSource;
    FKwSrc:      TKeywordDataSource;
    FSymSrc:     TSymbolDataSource;
    FChain:      TChainedDataSource;
    FPopup:      TCompletionPopup;
    FHighlighter: TTextHighlighter;

    procedure OnEditorChange(Sender: TObject);
    procedure OnEditorCursorMove(Sender: TObject);
    procedure PaintStatus;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
    procedure ArrangeChildren; override;
  public
    constructor Create(const ATitle: string = ''); override;
    destructor  Destroy; override;
  end;

constructor TEditorCompletionForm.Create(const ATitle: string);
var I: Integer;
begin
  inherited Create(ATitle);

  { Editor }
  FEditor := TTextEditor.Create;
  FEditor.CaptureTabs := True;
  FEditor.TabMode     := tmSpaces;
  FEditor.TabWidth    := 2;
  AddChild(FEditor);

  { Load initial content }
  FEditor.BeginUpdate;
  for I := 0 to High(StartCode) do
    FEditor.Lines.Add(StartCode[I]);
  FEditor.EndUpdate;
  FEditor.OnChange     := @OnEditorChange;
  FEditor.OnCursorMove := @OnEditorCursorMove;

  { Pascal highlighter }
  FHighlighter         := FindHighlighterForExt('.pas');
  FEditor.Highlighter  := FHighlighter;

  { Data sources }
  FWordSrc := TWordListDataSource.Create(FEditor.Lines, 2);
  FKwSrc   := TKeywordDataSource.Create;
  FSymSrc  := TSymbolDataSource.Create;

  FChain := TChainedDataSource.Create;
  FChain.AddSource(FSymSrc);
  FChain.AddSource(FKwSrc);
  FChain.AddSource(FWordSrc);

  { Completion popup }
  FPopup            := TCompletionPopup.Create;
  FPopup.DataSource := FChain;
  FPopup.MaxVisible := 10;

  ArrangeChildren;
end;

destructor TEditorCompletionForm.Destroy;
begin
  FPopup.Free;
  FChain.Free;
  FSymSrc.Free;
  FKwSrc.Free;
  FWordSrc.Free;
  FHighlighter.Free;
  inherited;
end;

procedure TEditorCompletionForm.ArrangeChildren;
begin
  if Assigned(FEditor) then
    FEditor.SetBounds(Left, Top, Width, Height - 1);  { leave 1 row for status }
end;

procedure TEditorCompletionForm.OnEditorChange(Sender: TObject);
begin
  FPopup.TriggerFromMultiEditor(FEditor);
  Invalidate;
end;

procedure TEditorCompletionForm.OnEditorCursorMove(Sender: TObject);
begin
  if FPopup.Visible then
  begin
    FPopup.TriggerFromMultiEditor(FEditor);
    Invalidate;
  end;
end;

procedure TEditorCompletionForm.PaintStatus;
var
  Y:    Integer;
  Hint: string;
  Line: string;
begin
  Y := Top + Height - 1;
  Term.GotoXY(Left, Y);
  Term.SetFG(clBlack);
  Term.SetBG(clCyan);

  if FPopup.Visible and Assigned(FPopup.Selected) then
    Hint := Format(' ↑↓=navigate  Enter=whole word  Tab=prefix  Esc=dismiss'
                 + '  selected: "%s"', [FPopup.Selected.DisplayText])
  else
    Hint := Format(' Ln %d, Col %d  ·  type to complete  ·  Ctrl+Q=quit',
                   [FEditor.CursorRow, FEditor.CursorCol]);

  Line := Hint;
  while System.Length(Line) < Width do Line := Line + ' ';
  if System.Length(Line) > Width then
    Line := System.Copy(Line, 1, Width);
  Term.WriteStr(Line);
  Term.ResetColors;
end;

procedure TEditorCompletionForm.DoPaint;
begin
  inherited DoPaint;   { paints FEditor }
  PaintStatus;
  if FPopup.Visible then FPopup.Paint;
end;

function TEditorCompletionForm.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  Result := True;

  if FPopup.Visible then
  begin
    case Key.Code of
      kcDown, kcUp, kcPageUp, kcPageDown, kcEscape:
        if FPopup.HandleNavKey(Key) then begin Invalidate; Exit; end;

      kcEnter:
        begin
          FPopup.CommitInto(FEditor, cmReplaceWord);
          Invalidate;
          Exit;
        end;

      kcTab:
        begin
          FPopup.CommitInto(FEditor, cmReplacePrefix);
          Invalidate;
          Exit;
        end;

      kcChar:
        begin
          if not FPopup.IsWordChar(Key.Ch) then
          begin
            if Assigned(FPopup.DataSource)
               and (FPopup.DataSource.CommitChars.Pos(Key.Ch) >= 0) then
            begin
              { Commit char: commit word, insert char, re-trigger }
              FPopup.CommitOnChar(FEditor, Key.Ch);
              FPopup.TriggerFromMultiEditor(FEditor, True);
              Invalidate;
              Exit;
            end
            else
            begin
              { Any other non-word char: commit, close, then insert the char }
              FPopup.CommitInto(FEditor, cmReplaceWord);
              FPopup.Hide;
              FEditor.KeyDown(Key);
              Invalidate;
              Exit;
            end;
          end;
        end;
    end;
  end;

  { Ctrl+Space: force-open popup }
  if Key.Code = kcCtrlSpace then
  begin
    FPopup.TriggerFromMultiEditor(FEditor, True);
    Invalidate;
    Exit;
  end;

  { Ctrl+Q: quit }
  if Key.Code = kcCtrlQ then
  begin
    Application.Terminate;
    Exit;
  end;

  Result := inherited DoKeyDown(Key);
end;

{ ── Main ── }

var
  Form: TEditorCompletionForm;
begin
  Term.EnableRawMode;
  Term.HideCursor;
  Term.EnterAltScreen;
  try
    Form := TEditorCompletionForm.Create(
      'TCompletionPopup + TTextEditor Example');
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
