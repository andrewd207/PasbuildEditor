{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Page.BuildRunner;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  PasbuildEditor.UIContext;

procedure RunBuildRunnerPage(Ctx: TUIContext);

implementation

uses
  Math, Process,
  TermUI.Terminal, TermUI.Menu, TermUI.Forms, TermUI.Application,
  TermUI.StringUtils,
  TermUI.Control.Editor,
  TermUI.Control.TextLabel,
  TermUI.Timer,
  PasbuildEditor.UI.Colors, PasbuildEditor.GlobalKeys;

{ ── Build output highlighter ──────────────────────────────────────── }

type
  TBuildHighlighter = class(TTextHighlighter)
  private
    FIsJson: Boolean;
    procedure EmitSpan(var ASpans: TTextSpanArray; var ACount: Integer;
      ACol, ALen: Integer; AFG: TColor);
    procedure EmitJsonSpans(const ALine: string; var ASpans: TTextSpanArray;
      var ACount: Integer);
  public
    constructor Create(AIsJson: Boolean);
    procedure GetSpans(ARow: Integer; const ALine: string;
      out ASpans: TTextSpanArray); override;
  end;

constructor TBuildHighlighter.Create(AIsJson: Boolean);
begin
  inherited Create;
  FIsJson := AIsJson;
end;

procedure TBuildHighlighter.EmitSpan(var ASpans: TTextSpanArray;
  var ACount: Integer; ACol, ALen: Integer; AFG: TColor);
begin
  if ALen <= 0 then Exit;
  if ACount >= Length(ASpans) then
    SetLength(ASpans, Max(8, Length(ASpans) * 2));
  ASpans[ACount].Col       := ACol;
  ASpans[ACount].Len       := ALen;
  ASpans[ACount].FG        := AFG;
  ASpans[ACount].BG        := clDefault;
  ASpans[ACount].Underline := False;
  Inc(ACount);
end;

procedure TBuildHighlighter.EmitJsonSpans(const ALine: string;
  var ASpans: TTextSpanArray; var ACount: Integer);
var
  P, Len, Q, SpanStart: Integer;
  C: Char;
  InStr, IsKey, Escaped: Boolean;
  KW: string;
begin
  P := 1; Len := Length(ALine);
  InStr := False; IsKey := False; Escaped := False;
  while P <= Len do
  begin
    C := ALine[P];

    if InStr then
    begin
      if Escaped then
        Escaped := False
      else if C = '\' then
        Escaped := True
      else if C = '"' then
      begin
        if IsKey then
          EmitSpan(ASpans, ACount, SpanStart - 1, P - SpanStart + 1, clBrightCyan)
        else
          EmitSpan(ASpans, ACount, SpanStart - 1, P - SpanStart + 1, clBrightGreen);
        InStr := False; IsKey := False;
      end;
      Inc(P); Continue;
    end;

    case C of
      '"':
      begin
        SpanStart := P;
        { Peek ahead to determine if this string is a key (followed by ':') }
        Q := P + 1; IsKey := False;
        while Q <= Len do
        begin
          if ALine[Q] = '\' then begin Inc(Q); Inc(Q); Continue; end;
          if ALine[Q] = '"' then
          begin
            Inc(Q);
            while (Q <= Len) and (ALine[Q] = ' ') do Inc(Q);
            IsKey := (Q <= Len) and (ALine[Q] = ':');
            Break;
          end;
          Inc(Q);
        end;
        Escaped := False; InStr := True;
        Inc(P); Continue;
      end;

      '0'..'9', '-':
      begin
        SpanStart := P;
        while (P <= Len) and (ALine[P] in ['0'..'9', '.', 'e', 'E', '+', '-']) do
          Inc(P);
        EmitSpan(ASpans, ACount, SpanStart - 1, P - SpanStart, clBrightYellow);
        Continue;
      end;

      't', 'f', 'n':
      begin
        Q := P; KW := '';
        while (Q <= Len) and (ALine[Q] in ['a'..'z']) do
        begin
          KW += ALine[Q]; Inc(Q);
        end;
        if (KW = 'true') or (KW = 'false') then
        begin
          EmitSpan(ASpans, ACount, P - 1, Length(KW), clBrightMagenta);
          P := Q; Continue;
        end
        else if KW = 'null' then
        begin
          EmitSpan(ASpans, ACount, P - 1, Length(KW), clBrightBlack);
          P := Q; Continue;
        end;
      end;

      '{', '}', '[', ']', ':', ',':
        EmitSpan(ASpans, ACount, P - 1, 1, clWhite);
    end;
    Inc(P);
  end;
end;

procedure TBuildHighlighter.GetSpans(ARow: Integer; const ALine: string;
  out ASpans: TTextSpanArray);
var
  Count, TagEnd: Integer;
begin
  ASpans := nil;
  Count  := 0;
  if Length(ALine) = 0 then Exit;

  SetLength(ASpans, 8);

  if FIsJson then
  begin
    EmitJsonSpans(ALine, ASpans, Count);
  end
  else if CopyNeutral(ALine, 0, 7) = '[INFO] ' then
  begin
    EmitSpan(ASpans, Count, 0, 6, clBlue);
  end
  else if CopyNeutral(ALine, 0, 10) = '[WARNING] ' then
  begin
    EmitSpan(ASpans, Count, 0, 9, clYellow);
  end
  else if CopyNeutral(ALine, 0, 8) = '[ERROR] ' then
  begin
    EmitSpan(ASpans, Count, 0, 7, clRed);
  end
  else if (Length(ALine) > 1) and (ALine[1] = '[') then
  begin
    if PosNeutral('] ', ALine, TagEnd) and (TagEnd > 0) then
      EmitSpan(ASpans, Count, 0, TagEnd + 1, clBrightCyan);
  end;

  SetLength(ASpans, Count);
end;

{ ── TBuildRunnerForm ───────────────────────────────────────────────── }

type
  TBuildRunnerForm = class(TForm)
  private
    FCtx:        TUIContext;
    FGoal:       string;
    FModSuffix:  string;
    FProc:       TProcess;
    FTimer:      TTimer;
    FHeaderLbl:  TLabel;
    FStatusLbl:  TLabel;
    FOutput:     TTextEditor;
    FFooterLbl:  TLabel;
    FHighlighter: TBuildHighlighter;
    FPartial:    string;
    FRunning:    Boolean;
    FExitCode:   Integer;
    FStartTime:  TDateTime;
    FAutoScroll: Boolean;

    function  ElapsedSec: Integer;
    procedure DrainOutput;
    procedure UpdateStatus;
    procedure OnPollTimer(Sender: TObject);
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
    procedure ArrangeChildren; override;
  public
    constructor Create(ACtx: TUIContext; const AGoal: string;
      AIsJson: Boolean; const AModSuffix: string);
    destructor Destroy; override;
  end;

constructor TBuildRunnerForm.Create(ACtx: TUIContext; const AGoal: string;
  AIsJson: Boolean; const AModSuffix: string);
begin
  inherited Create;
  FCtx       := ACtx;
  FGoal      := AGoal;
  FModSuffix := AModSuffix;
  FAutoScroll := True;

  FHighlighter := TBuildHighlighter.Create(AIsJson);

  FHeaderLbl := TLabel.Create;
  FHeaderLbl.ForeColor := clBrightYellow;
  FHeaderLbl.Text := ' ' + FCtx.Breadcrumb + ' > Run build > ' + FGoal;
  AddChild(FHeaderLbl);

  FStatusLbl := TLabel.Create;
  AddChild(FStatusLbl);

  FOutput := TTextEditor.Create;
  FOutput.ReadOnly    := True;
  FOutput.Highlighter := FHighlighter;
  AddChild(FOutput);

  FFooterLbl := TLabel.Create;
  FFooterLbl.ForeColor := clBrightBlack;
  AddChild(FFooterLbl);

  ArrangeChildren;

  { Start the process }
  FProc := TProcess.Create(nil);
  FProc.Executable := 'pasbuild';
  FProc.Parameters.Add(FGoal);
  if Assigned(FCtx.ParentPOM) then
  begin
    FProc.CurrentDirectory :=
      ExtractFilePath(ExpandFileName(FCtx.ParentPOM.FileName));
    FProc.Parameters.Add('-m');
    FProc.Parameters.Add(FCtx.Project.Name);
  end
  else
    FProc.CurrentDirectory :=
      ExtractFilePath(ExpandFileName(FCtx.Project.FileName));
  FProc.Options := [poUsePipes, poStderrToOutput];

  FRunning   := True;
  FStartTime := Now;
  FExitCode  := 0;
  UpdateStatus;
  FProc.Execute;

  FTimer          := TTimer.Create;
  FTimer.Interval := 50;
  FTimer.OnTimer  := @OnPollTimer;
  FTimer.Enabled  := True;
end;

destructor TBuildRunnerForm.Destroy;
begin
  FTimer.Free;
  if Assigned(FProc) and FProc.Running then
    FProc.Terminate(1);
  FProc.Free;
  FHighlighter.Free;
  inherited;
end;

procedure TBuildRunnerForm.ArrangeChildren;
begin
  if FOutput = nil then Exit;
  FHeaderLbl.SetBounds(1, 1, Width, 1);
  FStatusLbl.SetBounds(1, 2, Width, 1);
  { Row 3 = separator drawn in DoPaint }
  FOutput.SetBounds(1, 4, Width, Max(1, Height - 4));
  FFooterLbl.SetBounds(1, Height, Width, 1);
end;

function TBuildRunnerForm.ElapsedSec: Integer;
begin
  Result := Trunc((Now - FStartTime) * 86400);
end;

procedure TBuildRunnerForm.DrainOutput;
var
  Buf:  array[0..511] of Byte;
  N, J: Integer;
  S, C: string;
begin
  if not Assigned(FProc) then Exit;
  N := FProc.Output.NumBytesAvailable;
  while N > 0 do
  begin
    if N > SizeOf(Buf) then N := SizeOf(Buf);
    N := FProc.Output.Read(Buf[0], N);
    S := '';
    for J := 0 to N - 1 do S += Chr(Buf[J]);
    for J := 1 to Length(S) do
    begin
      C := S[J];
      if C = #13 then Continue;
      if C = #10 then
      begin
        FOutput.Lines.Add(FPartial);
        FPartial := '';
      end
      else
        FPartial += C;
    end;
    N := FProc.Output.NumBytesAvailable;
  end;
end;

procedure TBuildRunnerForm.UpdateStatus;
var S: string;
begin
  if FRunning then
  begin
    FStatusLbl.ForeColor := clBrightYellow;
    S := ' Running: pasbuild ' + FGoal + FModSuffix +
         '  (' + IntToStr(ElapsedSec) + 's)';
    FFooterLbl.Text := ' [↑↓/PgUp/PgDn] scroll   [Ctrl+C] cancel';
  end
  else if FExitCode = 0 then
  begin
    FStatusLbl.ForeColor := clBrightGreen;
    S := ' Done — pasbuild ' + FGoal + FModSuffix +
         '  exit 0  (' + IntToStr(ElapsedSec) + 's)';
    FFooterLbl.Text := ' [↑↓/PgUp/PgDn] scroll   [Enter/Esc] back';
  end
  else
  begin
    FStatusLbl.ForeColor := clBrightRed;
    S := ' Done — pasbuild ' + FGoal + FModSuffix +
         '  exit ' + IntToStr(FExitCode) +
         '  (' + IntToStr(ElapsedSec) + 's)';
    FFooterLbl.Text := ' [↑↓/PgUp/PgDn] scroll   [Enter/Esc] back';
  end;
  FStatusLbl.Text := S;
end;

procedure TBuildRunnerForm.OnPollTimer(Sender: TObject);
begin
  DrainOutput;
  if FRunning and not FProc.Running then
  begin
    { Process finished — drain any final output }
    DrainOutput;
    if FPartial <> '' then
    begin
      FOutput.Lines.Add(FPartial);
      FPartial := '';
    end;
    FExitCode  := FProc.ExitCode;
    FRunning   := False;
    FTimer.Enabled := False;
    FAutoScroll    := True;  { scroll to see the final output }
  end;
  if FAutoScroll then
    FOutput.ScrollToBottom;
  UpdateStatus;
  Invalidate;
end;

procedure TBuildRunnerForm.DoPaint;
begin
  { Draw the separator between status and output }
  GotoLocal(1, 3);
  Term.SetFG(clBrightBlack);
  Term.WriteStr(StringOfChar('-', Width));
  Term.ResetColors;
  inherited DoPaint;
end;

function TBuildRunnerForm.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  case Key.Code of
    kcUp, kcDown, kcPageUp, kcPageDown:
    begin
      FAutoScroll := False;
      Result := FOutput.KeyDown(Key);
    end;
    kcEnter, kcEscape:
      if not FRunning then
      begin
        Close(1);
        Exit(True);
      end
      else
        Result := inherited DoKeyDown(Key);
    kcCtrlC:
    begin
      if FRunning and Assigned(FProc) then
        FProc.Terminate(1);
      FAutoScroll := False;
      Result := True;
    end;
  else
    Result := inherited DoKeyDown(Key);
  end;
  if Result then Invalidate;
end;

{ ── Goal selection + page entry ───────────────────────────────────── }

procedure AddPluginsFromDir(AGoalMenu: TMenu; const ADir: string;
  ASeen: TStringList);
const
  Digits: array[0..9] of Char = ('1','2','3','4','5','6','7','8','9','0');
var
  SR:        TSearchRec;
  PlugName:  string;
  PlugGoal:  string;
  ItemLabel: string;
  D:         Char;
  Idx:       Integer;
begin
  if not DirectoryExists(ADir) then Exit;
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + 'pasbuild-*',
               faAnyFile and not faDirectory, SR) = 0 then
  try
    repeat
      if (SR.Attr and faDirectory) <> 0 then Continue;
      PlugName := SR.Name;
      PlugGoal := CopyNeutral(PlugName, Length('pasbuild-'), MaxInt);
      if (PlugGoal = '') or (ASeen.IndexOf(PlugGoal) >= 0) then Continue;
      Idx := ASeen.Count;
      ASeen.Add(PlugGoal);
      if Idx <= 9 then
      begin
        D         := Digits[Idx];
        ItemLabel := PadRight(PlugGoal, 18) + ' ' + D;
      end
      else
      begin
        D         := #0;
        ItemLabel := PlugGoal;
      end;
      AGoalMenu.Add(TMenuItem.Create(ItemLabel, nil, PlugGoal, D));
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

procedure RunBuildRunnerPage(Ctx: TUIContext);
var
  GoalMenu:    TMenu;
  GoalSel:     TMenuItem;
  It:          TMenuItem;
  GoalSelRow:  Integer;
  Goal:        string;
  IsJsonMode:  Boolean;
  ModuleSuffix: string;
  ProjectDir:  string;
  PluginsSeen: TStringList;
  LastGoalLabel: string;
  RunForm:     TBuildRunnerForm;
begin
  LastGoalLabel := '';
  repeat
    Goal := '';
    repeat
      GoalMenu := TMenu.Create(Ctx.Breadcrumb + ' > Run build');
      try
        GoalMenu.AddHeader('Built-in');
        It := TMenuItem.CreateEmbeddedHotkey('clea&n',                  nil); It.Desc := 'Delete all build artifacts';                                             GoalMenu.Add(It);
        It := TMenuItem.CreateEmbeddedHotkey('p&rocess-resources',      nil); It.Desc := 'Copy resources to target directory';                                     GoalMenu.Add(It);
        It := TMenuItem.CreateEmbeddedHotkey('&compile',                nil); It.Desc := 'Build the executable (runs: process-resources -> compile)';              GoalMenu.Add(It);
        It := TMenuItem.CreateEmbeddedHotkey('pr&ocess-test-resources', nil); It.Desc := 'Copy test resources to target directory';                                GoalMenu.Add(It);
        It := TMenuItem.CreateEmbeddedHotkey('test-co&mpile',           nil); It.Desc := 'Compile tests (runs: compile -> process-test-resources -> test-compile)'; GoalMenu.Add(It);
        It := TMenuItem.CreateEmbeddedHotkey('&test',                   nil); It.Desc := 'Run tests (runs: compile -> process-test-resources -> test-compile -> test)'; GoalMenu.Add(It);
        It := TMenuItem.CreateEmbeddedHotkey('&package',                nil); It.Desc := 'Create release archive (runs: clean -> compile -> package)';             GoalMenu.Add(It);
        It := TMenuItem.CreateEmbeddedHotkey('&source-package',         nil); It.Desc := 'Create source archive with src/, docs, and configured files';            GoalMenu.Add(It);
        It := TMenuItem.CreateEmbeddedHotkey('&install',                nil); It.Desc := 'Install compiled units to local repository (~/.pasbuild/repository/)';   GoalMenu.Add(It);
        It := TMenuItem.CreateEmbeddedHotkey('&dependency-tree',        nil); It.Desc := 'Show project dependency tree (no compilation)';                          GoalMenu.Add(It);
        It := TMenuItem.CreateEmbeddedHotkey('resol&ve',                nil); It.Desc := 'Output resolved build configuration as JSON (no compilation)';           GoalMenu.Add(It);
        ProjectDir  := ExtractFilePath(ExpandFileName(Ctx.Project.FileName));
        PluginsSeen := TStringList.Create;
        try
          GoalMenu.AddHeader('Plugins');
          AddPluginsFromDir(GoalMenu,
            IncludeTrailingPathDelimiter(ProjectDir) + 'plugins', PluginsSeen);
          AddPluginsFromDir(GoalMenu,
            IncludeTrailingPathDelimiter(GetUserDir) + '.pasbuild/plugins',
            PluginsSeen);
        finally
          PluginsSeen.Free;
        end;
        GoalMenu.AddHeader('Other');
        GoalMenu.Add(TMenuItem.Create('(custom)', nil, '', 'M'));
        GoalMenu.HelpDoc := 'run_build';
        if LastGoalLabel <> '' then GoalMenu.SelectByLabel(LastGoalLabel);
        GoalSel := GoalMenu.Run;
        GCtrlCRequested := False;
        GCtrlXRequested := False;
        if Assigned(GoalSel) then LastGoalLabel := GoalSel.Label_;
        if CheckGlobalKeys(Ctx) = gkContinue then Continue;
        if Application.Terminated or (GoalSel = nil) then Exit;
        if GoalSel.Value <> '' then
          Goal := GoalSel.Value
        else
          Goal := Trim(GoalSel.Label_);
        GoalSelRow := GoalMenu.SelectedRow;
      finally
        GoalMenu.Free;
      end;

      if Goal = '(custom)' then
      begin
        Goal := '';
        if EditLine('Goal', '', Goal, GoalSelRow) and (Goal <> '') then
          Break;
      end
      else
        Break;
    until False;
    if Goal = '' then Exit;

    IsJsonMode   := (Goal = 'resolve');
    ModuleSuffix := '';
    if Assigned(Ctx.ParentPOM) then
      ModuleSuffix := ' -m ' + Ctx.Project.Name;

    RunForm := TBuildRunnerForm.Create(Ctx, Goal, IsJsonMode, ModuleSuffix);
    try
      Application.ShowModal(RunForm);
    finally
      RunForm.Free;
    end;
    GCtrlCRequested := False;
    GCtrlXRequested := False;
  until Application.Terminated;
end;

end.
