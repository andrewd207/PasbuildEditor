{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

program pbeditor;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Process, PasbuildEditor.ProjectModel, TermUI.Terminal, TermUI.Menu,
  TermUI.PathPicker, TermUI.Terminal.Platform, PasbuildEditor.Consts,
  PasbuildEditor.UI, PasbuildEditor.Strings, PasbuildEditor.Profiles,
  PasbuildEditor.DependencyResolver;

procedure PrintUsage;
begin
  WriteLn(APP_TITLE + ' v' + APP_VERSION + ' — a terminal UI editor for pasbuild project.xml files.');
  WriteLn('  Editor:   ' + APP_URL);
  WriteLn('  Pasbuild: ' + PASBUILD_URL);
  WriteLn;
  WriteLn('Usage: pasbuildeditor [file]');
  WriteLn;
  WriteLn('  With no arguments, opens project.xml in the current working directory.');
  WriteLn('  If no project.xml is found, you will be prompted to create one.');
  WriteLn;
  WriteLn('  [file]  Open a specific project.xml file.');
  WriteLn;
  WriteLn('Options:');
  WriteLn('  -h, --help  Show this help message.');
end;

{ Run git rev-parse --show-toplevel; returns '' on failure. }
function GitToplevel: string;
var
  P:   TProcess;
  Buf: array[0..4095] of Char;
  N:   Integer;
begin
  Result := '';
  P := TProcess.Create(nil);
  try
    P.Executable := 'git';
    P.Parameters.Add('rev-parse');
    P.Parameters.Add('--show-toplevel');
    P.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
    try
      P.Execute;
      N := P.Output.Read(Buf[0], SizeOf(Buf) - 1);
      P.WaitOnExit;
      if (P.ExitCode = 0) and (N > 0) then
      begin
        Buf[N] := #0;
        Result := Trim(string(Buf));
      end;
    except
    end;
  finally
    P.Free;
  end;
end;

function FindParentPOMByWalk(const ADir, AProjectDir: string): string;
var
  Dir:      string;
  PomFile:  string;
  Pom:      TProjectBase;
  PomDir:   string;
  ModPath:  string;
  I:        Integer;
begin
  Result := '';
  Dir := ExcludeTrailingPathDelimiter(ADir);
  repeat
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    Dir := ExcludeTrailingPathDelimiter(Dir);
    if Dir = '' then Break;
    PomFile := Dir + PathDelim + 'project.xml';
    if FileExists(PomFile) then
    begin
      try
        Pom := TProjectBase.LoadFromFile(PomFile);
        try
          if Pom is TProjectPOM then
          begin
            PomDir := ExtractFilePath(PomFile);
            for I := 0 to TProjectPOM(Pom).Modules.Count - 1 do
            begin
              ModPath := IncludeTrailingPathDelimiter(PomDir) +
                TProjectPOM(Pom).Modules[I].Path;
              if SameFileName(
                   ExcludeTrailingPathDelimiter(ExpandFileName(ModPath)),
                   ExcludeTrailingPathDelimiter(AProjectDir)) then
              begin
                Result := PomFile;
                Exit;
              end;
            end;
          end;
        finally
          Pom.Free;
        end;
      except
      end;
    end;
  until False;
end;

function FindParentPOM(const AProjectFile: string): string;
var
  ProjectDir: string;
  TopLevel:   string;
  PomFile:    string;
  Pom:        TProjectBase;
begin
  Result := '';
  ProjectDir := ExtractFilePath(ExpandFileName(AProjectFile));

  TopLevel := GitToplevel;
  if TopLevel <> '' then
  begin
    PomFile := IncludeTrailingPathDelimiter(TopLevel) + 'project.xml';
    if FileExists(PomFile) and
       not SameFileName(ExpandFileName(PomFile), ExpandFileName(AProjectFile)) then
    begin
      Result := FindParentPOMByWalk(ProjectDir,
        ExcludeTrailingPathDelimiter(ProjectDir));
      if Result = '' then
      begin
        try
          Pom := TProjectBase.LoadFromFile(PomFile);
          try
            if Pom is TProjectPOM then
              Result := PomFile;
          finally
            Pom.Free;
          end;
        except end;
      end;
      Exit;
    end;
  end;

  Result := FindParentPOMByWalk(ProjectDir,
    ExcludeTrailingPathDelimiter(ProjectDir));
end;

var
  FileName:  string;
  Project:   TProjectBase;
  ParentPOM: TProjectPOM;
  PomFile:   string;
  PomBase:   TProjectBase;
  InitLine:  string;
  InitProc:  TProcess;

begin
  if (ParamCount = 1) and
     ((ParamStr(1) = '-h') or (ParamStr(1) = '--help')) then
  begin
    PrintUsage;
    Halt(0);
  end;

  if (ParamCount >= 1) and (ParamStr(1)[1] <> '-') then
    FileName := ParamStr(1)
  else
    FileName := 'project.xml';

  if not FileExists(FileName) then
  begin
    if ParamCount >= 1 then
    begin
      WriteLn('Error: file not found: ', FileName);
      Halt(1);
    end;
    Write('No project.xml found. Create a new project here? (yes,no) [no]: ');
    ReadLn(InitLine);
    InitLine := LowerCase(Trim(InitLine));
    if (InitLine <> 'y') and (InitLine <> 'yes') then
      Halt(0);
    InitProc := TProcess.Create(nil);
    try
      InitProc.Executable := 'pasbuild';
      InitProc.Parameters.Add('init');
      InitProc.Options := [poWaitOnExit];
      try
        InitProc.Execute;
        if InitProc.ExitCode <> 0 then
        begin
          WriteLn('pasbuild init failed.');
          Halt(1);
        end;
      except
        on E: Exception do
        begin
          WriteLn('Failed to run pasbuild init: ', E.Message);
          Halt(1);
        end;
      end;
    finally
      InitProc.Free;
    end;
    if not FileExists(FileName) then
    begin
      WriteLn('Error: project.xml was not created.');
      Halt(1);
    end;
  end;

  try
    Project := TProjectBase.LoadFromFile(FileName);
  except
    on E: Exception do
    begin
      WriteLn('Error loading ', FileName, ': ', E.Message);
      Halt(1);
    end;
  end;

  ParentPOM := nil;
  PomFile   := FindParentPOM(FileName);
  if PomFile <> '' then
  begin
    try
      PomBase := TProjectBase.LoadFromFile(PomFile);
      if PomBase is TProjectPOM then
        ParentPOM := TProjectPOM(PomBase)
      else
        PomBase.Free;
    except
    end;
  end;

  try
    RunUI(Project, ParentPOM);
  finally
    Project.Free;
    ParentPOM.Free;
  end;
end.
