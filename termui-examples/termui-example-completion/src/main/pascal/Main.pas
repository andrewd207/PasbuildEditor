{ termui-example-completion — demonstrates TCompletionPopup.

  Layout:
    Top area    A simple multi-line "document" (read-only, scrollable with PgUp/Dn).
                Starts pre-filled with Pascal keywords and identifiers.
    Middle row  Horizontal rule with item-count hint.
    Input row   A TTextEdit.  Completion fires as you type.
    Status row  Key hints.

  The TWordListDataSource scans the document lines and the input field itself,
  so every word you have typed becomes a suggestion for future typing.

  Two extra fixed data sources are layered on top via TChainedDataSource:
    • Pascal keywords (ckKeyword)
    • A small fake symbol table: functions, variables, types (ckFunction etc.)

  Key bindings:
    Down / Up       navigate completion list (Down from input opens it if visible)
    Enter           commit selected item — replaces the whole word
    Tab             commit selected item — replaces only the prefix (leaves suffix)
    Space           commit selected item then insert a space
    Escape          dismiss completion (suppressed until cursor moves)
    Ctrl+K          kill to end of input line
    Ctrl+U          kill to start of input line
    F5              clear input line
    PgUp / PgDn     scroll the document pane
    Q (no input)    quit
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
  TermUI.Control.LineEditor;

{ ── Chained data source ─────────────────────────────────────────────────── }
{ Queries multiple data sources and merges results, deduplicating by
  DisplayText. Sources listed first take priority (their items appear first). }

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
  Result := '';
end;

function TChainedDataSource.WordChars: string;
begin
  Result := '';
end;

{ ── Fixed keyword data source ───────────────────────────────────────────── }

type
  TKeywordDataSource = class(TCompletionDataSource)
  private
    FKeywords: TStringList;  { owned }
  public
    constructor Create;
    destructor  Destroy; override;
    procedure GetCompletions(const ACtx: TCompletionContext;
                             AList: TCompletionList); override;
    function  ShouldTrigger(const ACtx: TCompletionContext): Boolean; override;
  end;

const
  PascalKeywords: array[0..39] of string = (
    'and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const',
    'constructor', 'destructor', 'div', 'do', 'downto', 'else', 'end',
    'except', 'exports', 'file', 'finalization', 'finally', 'for',
    'function', 'goto', 'if', 'implementation', 'inherited', 'initialization',
    'inline', 'interface', 'is', 'label', 'mod', 'nil', 'not', 'object',
    'of', 'operator', 'or', 'override', 'packed'
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
    if (KwLo <> ACtx.Prefix) and (KwLo.Pos(PfxLo) = 0) then
      AList.Add(FKeywords[I], ckKeyword);
  end;
end;

function TKeywordDataSource.ShouldTrigger(const ACtx: TCompletionContext): Boolean;
begin
  Result := ACtx.Prefix.Length >= 2;
end;

{ ── Fixed symbol-table data source ─────────────────────────────────────── }

type
  TSymbolEntry = record
    Name:   string;
    Kind:   TCompletionKind;
    Detail: string;
  end;

  TSymbolDataSource = class(TCompletionDataSource)
  private
    FSymbols: array of TSymbolEntry;
    procedure Add(const AName: string; AKind: TCompletionKind;
                  const ADetail: string = '');
  public
    constructor Create;
    procedure GetCompletions(const ACtx: TCompletionContext;
                             AList: TCompletionList); override;
    function  ShouldTrigger(const ACtx: TCompletionContext): Boolean; override;
  end;

procedure TSymbolDataSource.Add(const AName: string; AKind: TCompletionKind;
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
  { Functions }
  Add('WriteLn',        ckFunction, 'procedure');
  Add('Write',          ckFunction, 'procedure');
  Add('ReadLn',         ckFunction, 'procedure');
  Add('IntToStr',       ckFunction, 'function: string');
  Add('StrToInt',       ckFunction, 'function: Integer');
  Add('StrToIntDef',    ckFunction, 'function: Integer');
  Add('LowerCase',      ckFunction, 'function: string');
  Add('UpperCase',      ckFunction, 'function: string');
  Add('Trim',           ckFunction, 'function: string');
  Add('Length',         ckFunction, 'function: Integer');
  Add('Copy',           ckFunction, 'function: string');
  Add('Pos',            ckFunction, 'function: Integer');
  Add('Concat',         ckFunction, 'function: string');
  Add('SetLength',      ckFunction, 'procedure');
  Add('Assigned',       ckFunction, 'function: Boolean');
  Add('FreeAndNil',     ckFunction, 'procedure');
  Add('SizeOf',         ckFunction, 'function: Integer');
  Add('Ord',            ckFunction, 'function: Integer');
  Add('Chr',            ckFunction, 'function: Char');
  Add('Inc',            ckFunction, 'procedure');
  Add('Dec',            ckFunction, 'procedure');
  Add('High',           ckFunction, 'function: Integer');
  Add('Low',            ckFunction, 'function: Integer');
  { Variables / fields }
  Add('Result',         ckVariable, 'return value');
  Add('Self',           ckVariable, 'current instance');
  Add('True',           ckVariable, 'Boolean');
  Add('False',          ckVariable, 'Boolean');
  Add('MaxInt',         ckVariable, 'Integer');
  Add('nil',            ckVariable, 'pointer');
  { Types }
  Add('Integer',        ckType);
  Add('Cardinal',       ckType);
  Add('Int64',          ckType);
  Add('Boolean',        ckType);
  Add('Char',           ckType);
  Add('string',         ckType);
  Add('Single',         ckType);
  Add('Double',         ckType);
  Add('Extended',       ckType);
  Add('Pointer',        ckType);
  Add('TObject',        ckType);
  Add('TClass',         ckType);
  Add('TStringList',    ckType);
  Add('TList',          ckType);
  Add('TComponent',     ckType);
  Add('TPersistent',    ckType);
  Add('Exception',      ckType);
  { Units / modules }
  Add('Classes',        ckModule);
  Add('SysUtils',       ckModule);
  Add('Math',           ckModule);
  Add('StrUtils',       ckModule);
  Add('Contnrs',        ckModule);
  Add('TypInfo',        ckModule);
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
    if (FSymbols[I].Name <> ACtx.Prefix) and (NamLo.Pos(PfxLo) = 0) then
      AList.Add(FSymbols[I].Name, FSymbols[I].Kind, '', FSymbols[I].Detail);
  end;
end;

function TSymbolDataSource.ShouldTrigger(const ACtx: TCompletionContext): Boolean;
begin
  Result := ACtx.Prefix.Length >= 1;
end;

{ ── Form ───────────────────────────────────────────────────────────────── }

const
  DocLines: array[0..19] of string = (
    'program MyProgram;',
    '',
    'uses Classes, SysUtils;',
    '',
    'type',
    '  TMyObject = class(TObject)',
    '  private',
    '    FValue:   Integer;',
    '    FName:    string;',
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
    '  MyObj: TMyObject;'
  );

type
  TCompletionForm = class(TForm)
  private
    FEdit:       TTextEdit;
    FDocLines:   TStringList;    { backing text for the word-list source }
    FDocTop:     Integer;        { first visible doc line }
    FDocHeight:  Integer;        { rows reserved for document pane }

    FWordSrc:    TWordListDataSource;
    FKwSrc:      TKeywordDataSource;
    FSymSrc:     TSymbolDataSource;
    FChain:      TChainedDataSource;

    FPopup:      TCompletionPopup;

    procedure OnEditChange(Sender: TObject);
    procedure OnEditAccept(Sender: TObject);

    procedure PaintDoc;
    procedure PaintDivider;
    procedure PaintStatus;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
    procedure ArrangeChildren; override;
  public
    constructor Create(const ATitle: string = ''); override;
    destructor  Destroy; override;
  end;

constructor TCompletionForm.Create(const ATitle: string);
var I: Integer;
begin
  inherited Create(ATitle);

  { Pre-fill document }
  FDocLines := TStringList.Create;
  for I := 0 to High(DocLines) do
    FDocLines.Add(DocLines[I]);
  FDocTop    := 0;
  FDocHeight := 0;   { set in ArrangeChildren }

  { Data sources }
  FWordSrc := TWordListDataSource.Create(FDocLines, 2);
  FKwSrc   := TKeywordDataSource.Create;
  FSymSrc  := TSymbolDataSource.Create;

  FChain := TChainedDataSource.Create;
  FChain.AddSource(FSymSrc);   { symbols first — richer detail }
  FChain.AddSource(FKwSrc);
  FChain.AddSource(FWordSrc);

  { Editor }
  FEdit := TTextEdit.Create;
  FEdit.Placeholder := 'Type here — completion appears automatically…';
  FEdit.OnChange    := @OnEditChange;
  FEdit.OnAccept    := @OnEditAccept;
  AddChild(FEdit);

  { Completion popup }
  FPopup := TCompletionPopup.Create;
  FPopup.DataSource := FChain;
  FPopup.MaxVisible := 10;

  ArrangeChildren;
end;

destructor TCompletionForm.Destroy;
begin
  FPopup.Free;
  FChain.Free;
  FSymSrc.Free;
  FKwSrc.Free;
  FWordSrc.Free;
  FDocLines.Free;
  inherited;
end;

procedure TCompletionForm.ArrangeChildren;
begin
  { Reserve bottom 2 rows: input + status. Doc fills the rest. }
  FDocHeight := Height - 3;   { 1 divider + 1 input + 1 status }
  if FDocHeight < 1 then FDocHeight := 1;
  if Assigned(FEdit) then
    FEdit.SetBounds(Left, Top + Height - 2, Width, 1);
end;

{ ── Event handlers ── }

procedure TCompletionForm.OnEditChange(Sender: TObject);
begin
  FPopup.TriggerFromEditor(FEdit);
  Invalidate;
end;

procedure TCompletionForm.OnEditAccept(Sender: TObject);
begin
  { Add the typed line to the document so it becomes available for completion }
  if FEdit.Text <> '' then
    FDocLines.Add(FEdit.Text);
  FEdit.Clear;
  FPopup.Hide;
  Invalidate;
end;

{ ── Painting ── }

procedure TCompletionForm.PaintDoc;
var
  I, Row:   Integer;
  Y:        Integer;
  Line:     string;
  LineNo:   string;
  NumW:     Integer;
  TextW:    Integer;
begin
  NumW  := 4;   { "NNN " gutter }
  TextW := Width - NumW;
  if TextW < 1 then TextW := 1;

  for Row := 0 to FDocHeight - 1 do
  begin
    I := FDocTop + Row;
    Y := Top + Row;

    Term.GotoXY(Left, Y);

    if I < FDocLines.Count then
    begin
      { Gutter }
      Term.SetFG(clBrightBlack);
      Term.ResetColors;
      LineNo := Format('%3d ', [I + 1]);
      Term.WriteStr(LineNo);

      { Content }
      Term.ResetColors;
      Line := FDocLines[I];
      if Line.Length > TextW then Line := Line.Copy(0, TextW)
      else while Line.Length < TextW do Line := Line + ' ';
      Term.WriteStr(Line);
    end
    else
    begin
      Term.SetFG(clBrightBlack);
      Term.ResetColors;
      Term.WriteStr('    ');
      Term.ResetColors;
      Term.WriteStr(StringOfChar(' ', TextW));
    end;
  end;
end;

procedure TCompletionForm.PaintDivider;
var
  Y:    Integer;
  Hint: string;
  Line: string;
begin
  Y    := Top + FDocHeight;
  Hint := Format(' %d words in scope  ·  Enter=accept line  Tab=complete prefix  '
               + 'Esc=dismiss  Q=quit', [FDocLines.Count]);
  Term.GotoXY(Left, Y);
  Term.SetFG(clBlack);
  Term.SetBG(clWhite);
  Line := Hint;
  while System.Length(Line) < Width do Line := Line + ' ';
  if System.Length(Line) > Width then Line := System.Copy(Line, 1, Width);
  Term.WriteStr(Line);
  Term.ResetColors;
end;

procedure TCompletionForm.PaintStatus;
var
  Y:    Integer;
  Hint: string;
  Line: string;
begin
  Y    := Top + Height - 1;
  Hint := Format(' cursor:%d  word:[%d..%d)  prefix:"%s"',
    [FPopup.SelIndex, 0, 0, '']);
  { Show context from popup if it's visible }
  Term.GotoXY(Left, Y);
  Term.SetFG(clBlack);
  Term.SetBG(clCyan);
  if FPopup.Visible and Assigned(FPopup.Selected) then
    Hint := Format(' ↑↓=navigate  Enter=whole word  Tab=prefix only  '
                 + 'selected: "%s"', [FPopup.Selected.DisplayText])
  else
    Hint := ' Type to complete  ·  Down=open list  ·  PgUp/Dn=scroll doc';
  Line := Hint;
  while System.Length(Line) < Width do Line := Line + ' ';
  if System.Length(Line) > Width then Line := System.Copy(Line, 1, Width);
  Term.WriteStr(Line);
  Term.ResetColors;
end;

procedure TCompletionForm.DoPaint;
begin
  PaintDoc;
  PaintDivider;
  inherited DoPaint;   { paints FEdit }
  PaintStatus;
  { Popup always painted last so it overlays everything }
  if FPopup.Visible then FPopup.Paint;
end;

{ ── Key routing ── }

function TCompletionForm.DoKeyDown(var Key: TKeyEvent): Boolean;
var
  ScrollMax: Integer;
begin
  Result := True;

  { Let popup consume navigation keys first }
  if FPopup.Visible then
  begin
    case Key.Code of
      kcDown, kcUp, kcPageUp, kcPageDown, kcEscape:
        if FPopup.HandleNavKey(Key) then
        begin
          Invalidate;
          Exit;
        end;
      kcEnter:
        if FPopup.CommitInto(FEdit, cmReplaceWord) then
        begin
          Invalidate;
          Exit;
        end;
      kcTab:
        if FPopup.CommitInto(FEdit, cmReplacePrefix) then
        begin
          Invalidate;
          Exit;
        end;
    end;
  end;

  { Down key when popup is hidden: try to open it }
  if (Key.Code = kcDown) and not FPopup.Visible then
  begin
    FPopup.TriggerFromEditor(FEdit);
    Invalidate;
    Exit;
  end;

  { Ctrl+Space: force-open popup regardless of prefix length }
  if Key.Code = kcCtrlSpace then
  begin
    FPopup.TriggerFromEditor(FEdit, True);
    Invalidate;
    Exit;
  end;

  { Space when popup is visible: commit then insert space }
  if (Key.Code = kcChar) and (Key.Ch = ' ') and FPopup.Visible then
  begin
    FPopup.CommitInto(FEdit, cmReplaceWord);
    { Let the space fall through to the editor }
  end;

  { Commit characters (.  ( etc.) }
  if (Key.Code = kcChar) and FPopup.CommitOnChar(FEdit, Key.Ch) then
  begin
    Invalidate;
    Exit;
  end;

  { Q with empty field → quit }
  if (Key.Code = kcChar) and ((Key.Ch = 'q') or (Key.Ch = 'Q'))
     and (FEdit.Text = '') then
  begin
    Application.Terminate;
    Exit;
  end;

  { F5: clear input }
  if Key.Code = kcF5 then
  begin
    FEdit.Clear;
    FPopup.Hide;
    Invalidate;
    Exit;
  end;

  { Document scrolling }
  ScrollMax := FDocLines.Count - FDocHeight;
  if ScrollMax < 0 then ScrollMax := 0;
  if Key.Code = kcPageUp then
  begin
    Dec(FDocTop, FDocHeight);
    if FDocTop < 0 then FDocTop := 0;
    Invalidate;
    Exit;
  end;
  if Key.Code = kcPageDown then
  begin
    Inc(FDocTop, FDocHeight);
    if FDocTop > ScrollMax then FDocTop := ScrollMax;
    Invalidate;
    Exit;
  end;

  Result := inherited DoKeyDown(Key);
end;

{ ── Main ── }

var
  Form: TCompletionForm;
begin
  Term.EnableRawMode;
  Term.HideCursor;
  Term.EnterAltScreen;
  try
    Form := TCompletionForm.Create('TCompletionPopup Example');
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
