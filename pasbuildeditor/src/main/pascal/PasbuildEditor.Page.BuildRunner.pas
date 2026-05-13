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
  Process,
  TermUI.Terminal, TermUI.Menu,
  PasbuildEditor.UI.Colors,
  TermUI.Application;

procedure RunBuildRunnerPage(Ctx: TUIContext);
const
  HEADER_ROWS = 3;
  FOOTER_ROWS = 2;
var
  GoalMenu:    TMenu;
  GoalSel:     TMenuItem;
  It:          TMenuItem;
  GoalSelRow:  Integer;
  Goal:        string;
  Proc:        TProcess;
  Lines:       TStringList;
  Partial:     string;
  Buf:         array[0..511] of Byte;
  N, I:        Integer;
  ScrollOff:   Integer;
  AutoScroll:  Boolean;
  VisibleRows: Integer;
  Dirty:       Boolean;
  Running:     Boolean;
  ExitCode:    Integer;
  StartTime:   TDateTime;
  K:           TKeyEvent;
  S:           string;
  IsJsonMode:  Boolean;
  ModuleSuffix: string;

  function ElapsedSec: Integer;
  begin
    Result := Trunc((Now - StartTime) * 86400);
  end;

  function DisplayLineCount: Integer;
  begin
    Result := Lines.Count;
    if Partial <> '' then Inc(Result);
  end;

  function GetDisplayLine(AIdx: Integer): string;
  begin
    if AIdx < Lines.Count then Result := Lines[AIdx]
    else Result := Partial;
  end;

  procedure ComputeVisible;
  begin
    VisibleRows := Term.Height - HEADER_ROWS - FOOTER_ROWS;
    if VisibleRows < 1 then VisibleRows := 1;
  end;

  procedure PinToBottom;
  begin
    ComputeVisible;
    ScrollOff := DisplayLineCount - VisibleRows;
    if ScrollOff < 0 then ScrollOff := 0;
  end;

  procedure WriteJsonLine(const ALine: string);
  var
    P, Len, Q: Integer;
    C:         Char;
    InStr:     Boolean;
    IsKey:     Boolean;
    Escaped:   Boolean;
    Chunk:     string;
    KW:        string;

    procedure FlushChunk;
    begin
      if Chunk = '' then Exit;
      Term.ResetColors;
      Term.WriteStr(Chunk);
      Chunk := '';
    end;

  begin
    P      := 1;
    Len    := Length(ALine);
    InStr  := False;
    IsKey  := False;
    Chunk  := '';

    while P <= Len do
    begin
      C := ALine[P];

      if InStr then
      begin
        Chunk := Chunk + C;
        if C = '\' then
        begin
          if P < Len then
          begin
            Inc(P);
            Chunk := Chunk + ALine[P];
          end;
        end
        else if C = '"' then
        begin
          InStr := False;
          if IsKey then
            Term.SetFG(clBrightCyan)
          else
            Term.SetFG(clBrightGreen);
          Term.WriteStr(Chunk);
          Term.ResetColors;
          Chunk := '';
          IsKey := False;
        end;
        Inc(P);
        Continue;
      end;

      case C of
        '"':
        begin
          Q       := P + 1;
          Escaped := False;
          IsKey   := False;
          while Q <= Len do
          begin
            if Escaped then
              Escaped := False
            else if ALine[Q] = '\' then
              Escaped := True
            else if ALine[Q] = '"' then
            begin
              Inc(Q);
              while (Q <= Len) and (ALine[Q] = ' ') do Inc(Q);
              IsKey := (Q <= Len) and (ALine[Q] = ':');
              Break;
            end;
            Inc(Q);
          end;
          FlushChunk;
          InStr := True;
          Chunk := '"';
        end;
        '0'..'9', '-':
        begin
          FlushChunk;
          KW := '';
          while (P <= Len) and (ALine[P] in ['0'..'9', '-', '.', 'e', 'E', '+']) do
          begin
            KW := KW + ALine[P];
            Inc(P);
          end;
          Term.SetFG(clBrightYellow);
          Term.WriteStr(KW);
          Term.ResetColors;
          Continue;
        end;
        't', 'f', 'n':
        begin
          KW := '';
          Q  := P;
          while (Q <= Len) and (ALine[Q] in ['a'..'z']) do
          begin
            KW := KW + ALine[Q];
            Inc(Q);
          end;
          if (KW = 'true') or (KW = 'false') or (KW = 'null') then
          begin
            FlushChunk;
            if KW = 'null' then Term.SetFG(clBrightBlack)
            else                 Term.SetFG(clBrightMagenta);
            Term.WriteStr(KW);
            Term.ResetColors;
            P := Q;
            Continue;
          end
          else
            Chunk := Chunk + C;
        end;
        '{', '}', '[', ']', ':', ',':
        begin
          FlushChunk;
          Term.SetFG(clWhite);
          Term.WriteStr(C);
          Term.ResetColors;
        end;
      else
        Chunk := Chunk + C;
      end;
      Inc(P);
    end;
    FlushChunk;
  end;

  procedure Draw;
  var
    Row, LineIdx, J, TagEnd: Integer;
    StatusStr:               string;
  begin
    ComputeVisible;
    Term.ClearScreen;

    ColorHeader;
    Term.GotoXY(1, 1);
    Term.WriteStr(' ' + Ctx.Breadcrumb + ' > Run build > Run output');
    Term.ClearToEOL;
    Term.ResetColors;

    Term.GotoXY(1, 2);
    if Running then
    begin
      Term.SetFG(clBrightYellow);
      StatusStr := ' Running: pasbuild ' + Goal + ModuleSuffix +
                   '  (' + IntToStr(ElapsedSec) + 's)';
    end
    else if ExitCode = 0 then
    begin
      Term.SetFG(clBrightGreen);
      StatusStr := ' Done — pasbuild ' + Goal + ModuleSuffix +
                   '  exit 0  (' + IntToStr(ElapsedSec) + 's)';
    end
    else
    begin
      Term.SetFG(clBrightRed);
      StatusStr := ' Done — pasbuild ' + Goal + ModuleSuffix +
                   '  exit ' + IntToStr(ExitCode) +
                   '  (' + IntToStr(ElapsedSec) + 's)';
    end;
    Term.WriteStr(StatusStr);
    Term.ClearToEOL;
    Term.ResetColors;

    Term.GotoXY(1, 3);
    ColorRule;
    Term.WriteStr(StringOfChar('-', Term.Width));
    Term.ResetColors;

    for J := 0 to VisibleRows - 1 do
    begin
      LineIdx := ScrollOff + J;
      Row     := HEADER_ROWS + 1 + J;
      Term.GotoXY(1, Row);
      Term.ResetColors;
      if LineIdx < DisplayLineCount then
      begin
        S := GetDisplayLine(LineIdx);
        if Length(S) > Term.Width then S := Copy(S, 1, Term.Width);
        if IsJsonMode then
          WriteJsonLine(S)
        else if Copy(S, 1, 7) = '[INFO] ' then
        begin
          Term.SetFG(clBlue);   Term.WriteStr('[INFO]');
          Term.ResetColors;     Term.WriteStr(Copy(S, 7, MaxInt));
        end
        else if Copy(S, 1, 10) = '[WARNING] ' then
        begin
          Term.SetFG(clYellow); Term.WriteStr('[WARNING]');
          Term.ResetColors;     Term.WriteStr(Copy(S, 10, MaxInt));
        end
        else if Copy(S, 1, 8) = '[ERROR] ' then
        begin
          Term.SetFG(clRed);    Term.WriteStr('[ERROR]');
          Term.ResetColors;     Term.WriteStr(Copy(S, 8, MaxInt));
        end
        else if (Length(S) > 1) and (S[1] = '[') then
        begin
          TagEnd := Pos('] ', S);
          if TagEnd > 1 then
          begin
            Term.SetFG(clBrightCyan); Term.WriteStr(Copy(S, 1, TagEnd));
            Term.ResetColors;         Term.WriteStr(Copy(S, TagEnd + 1, MaxInt));
          end
          else
            Term.WriteStr(S);
        end
        else
          Term.WriteStr(S);
      end;
      Term.ClearToEOL;
    end;

    Term.GotoXY(1, Term.Height - 1);
    ColorHelp;
    if Running then
      Term.WriteStr(' [Up/Down/PgUp/PgDn] scroll   [Ctrl+C] cancel')
    else
      Term.WriteStr(' [Up/Down/PgUp/PgDn] scroll   [Enter/Esc] back');
    Term.ClearToEOL;
    Term.ResetColors;

    Term.FlushOutput;
    Dirty := False;
  end;

  procedure AppendOutput(const AData: string);
  var
    C:  Char;
    J:  Integer;
  begin
    for J := 1 to Length(AData) do
    begin
      C := AData[J];
      if C = #13 then Continue;
      if C = #10 then
      begin
        Lines.Add(Partial);
        Partial := '';
      end
      else
        Partial += C;
    end;
  end;

  procedure HandleScroll(ADelta: Integer);
  var
    MaxOff: Integer;
  begin
    AutoScroll := False;
    ComputeVisible;
    MaxOff := DisplayLineCount - VisibleRows;
    if MaxOff < 0 then MaxOff := 0;
    Inc(ScrollOff, ADelta);
    if ScrollOff > MaxOff then ScrollOff := MaxOff;
    if ScrollOff < 0 then ScrollOff := 0;
    Dirty := True;
  end;

  procedure DrainOutput;
  var J: Integer;
  begin
    N := Proc.Output.NumBytesAvailable;
    while N > 0 do
    begin
      if N > SizeOf(Buf) then N := SizeOf(Buf);
      N := Proc.Output.Read(Buf[0], N);
      S := '';
      for J := 0 to N - 1 do S += Chr(Buf[J]);
      AppendOutput(S);
      Dirty := True;
      N := Proc.Output.NumBytesAvailable;
    end;
  end;

  procedure AddPluginsFromDir(const ADir: string; ASeen: TStringList);
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
        PlugGoal := Copy(PlugName, Length('pasbuild-') + 1, MaxInt);
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
        GoalMenu.Add(TMenuItem.Create(ItemLabel, nil, PlugGoal, D));
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;

var
  ProjectDir:    string;
  PluginsSeen:   TStringList;
  LastGoalLabel: string;
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
          AddPluginsFromDir(IncludeTrailingPathDelimiter(ProjectDir) + 'plugins', PluginsSeen);
          AddPluginsFromDir(IncludeTrailingPathDelimiter(GetUserDir) + '.pasbuild/plugins', PluginsSeen);
        finally
          PluginsSeen.Free;
        end;
        GoalMenu.AddHeader('Other');
        GoalMenu.Add(TMenuItem.Create('(custom)', nil, '', 'M'));
        if LastGoalLabel <> '' then GoalMenu.SelectByLabel(LastGoalLabel);
        GoalSel := GoalMenu.Run;
        GCtrlCRequested := False;
        GCtrlXRequested := False;
        if Application.Terminated or (GoalSel = nil) then Exit;
        LastGoalLabel := GoalSel.Label_;
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

    Lines := TStringList.Create;
    Proc  := TProcess.Create(nil);
    try
      Proc.Executable := 'pasbuild';
      Proc.Parameters.Add(Goal);
      if Assigned(Ctx.ParentPOM) then
      begin
        Proc.CurrentDirectory := ExtractFilePath(ExpandFileName(Ctx.ParentPOM.FileName));
        Proc.Parameters.Add('-m');
        Proc.Parameters.Add(Ctx.Project.Name);
      end
      else
        Proc.CurrentDirectory := ExtractFilePath(ExpandFileName(Ctx.Project.FileName));
      Proc.Options := [poUsePipes, poStderrToOutput];

      StartTime  := Now;
      ScrollOff  := 0;
      AutoScroll := True;
      Partial    := '';
      ExitCode   := 0;
      Running    := True;
      Dirty      := True;
      IsJsonMode := (Goal = 'resolve');
      if Assigned(Ctx.ParentPOM) then
        ModuleSuffix := ' -m ' + Ctx.Project.Name
      else
        ModuleSuffix := '';

      Proc.Execute;

      repeat
        DrainOutput;
        if AutoScroll and Dirty then PinToBottom;
        if not Proc.Running then
        begin
          DrainOutput;
          if Partial <> '' then begin Lines.Add(Partial); Partial := ''; end;
          ExitCode   := Proc.ExitCode;
          Running    := False;
          PinToBottom;
          Dirty := True;
          Draw;
          Break;
        end;
        if Term.ReadKeyTimeout(K, 50) then
          case K.Code of
            kcUp:       HandleScroll(-1);
            kcDown:     HandleScroll(1);
            kcPageUp:   HandleScroll(-VisibleRows);
            kcPageDown: HandleScroll(VisibleRows);
            kcCtrlC:
              if Running then
              begin
                Proc.Terminate(1);
                AutoScroll := False;
                Dirty := True;
              end;
          end;
        if Dirty then Draw;
      until False;

      repeat
        if Term.ReadKeyTimeout(K, 200) then
        begin
          case K.Code of
            kcUp:        HandleScroll(-1);
            kcDown:      HandleScroll(1);
            kcPageUp:    HandleScroll(-VisibleRows);
            kcPageDown:  HandleScroll(VisibleRows);
            kcEnter, kcEscape: Break;
          end;
          if Dirty then Draw;
        end;
      until False;

    finally
      if Proc.Running then Proc.Terminate(1);
      Proc.Free;
      Lines.Free;
    end;
  until False;
end;

end.
