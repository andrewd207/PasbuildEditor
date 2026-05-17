{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.

  TProjectTree walks a pasbuild multi-module project to build a map of
  module name -> project.xml path.  Modules are discoverable by:
    - Their directory name as listed in the root POM's <modules> list
    - Their <name> value from project.xml (if different from directory name)

  Detection strategy (LoadFromDir):
    1. Run git rev-parse --show-toplevel; if found and that directory has a
       POM project.xml, use it.
    2. Walk up from the given directory looking for the first POM project.xml.

  Sub-POMs are recursed so nested aggregators are fully scanned.
}
unit PBLib.ProjectTree;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fgl, Process,
  PBLib.ProjectModel;

type
  TModuleEntry = class
  public
    PathComponent: string;  // directory name as listed in parent POM <modules>
    ProjectName: string;    // <name> from project.xml (may equal PathComponent)
    ProjectFile: string;    // absolute path to project.xml
    ModuleDir: string;      // absolute path to module directory
  end;

  TModuleEntryList = specialize TFPGObjectList<TModuleEntry>;

  TProjectTree = class
  private
    FRootPOMFile: string;
    FModules: TModuleEntryList;
    procedure ScanModules(APOM: TProjectPOM; const APOMDir: string);
  public
    constructor Create;
    destructor Destroy; override;

    { Walk up from ADir (or use git toplevel) to find the root POM, then scan
      all modules recursively.  Returns True if a root POM was found. }
    function LoadFromDir(const ADir: string): Boolean;

    { Find a module by directory name or project name.
      Returns True and sets AProjectFile on success. }
    function FindModule(const AName: string; out AProjectFile: string): Boolean;

    { Populate AList with all known module names.
      Each entry is the PathComponent; if ProjectName differs it is appended
      in parentheses as an alias hint. }
    procedure GetModuleNames(AList: TStringList);

    property RootPOMFile: string read FRootPOMFile;
    property Modules: TModuleEntryList read FModules;
  end;

{ Run git rev-parse --show-toplevel from ADir; returns '' on failure. }
function GitToplevel(const ADir: string): string;

implementation

function GitToplevel(const ADir: string): string;
var
  P: TProcess;
  Buf: array[0..4095] of Char;
  N: Integer;
begin
  Result := '';
  P := TProcess.Create(nil);
  try
    P.Executable        := 'git';
    P.Parameters.Add('rev-parse');
    P.Parameters.Add('--show-toplevel');
    P.CurrentDirectory  := ADir;
    P.Options           := [poUsePipes, poStderrToOutPut, poNoConsole];
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

{ Return path to project.xml if ADir contains a POM project, else ''. }
function FindPOMInDir(const ADir: string): string;
var
  F: string;
  P: TProjectBase;
begin
  Result := '';
  F := IncludeTrailingPathDelimiter(ADir) + 'project.xml';
  if not FileExists(F) then Exit;
  try
    P := TProjectBase.LoadFromFile(F);
    try
      if P is TProjectPOM then
        Result := F;
    finally
      P.Free;
    end;
  except
  end;
end;

{ Return path to project.xml if ADir contains any pasbuild project, else ''. }
function FindAnyProjectInDir(const ADir: string): string;
var
  F: string;
begin
  Result := '';
  F := IncludeTrailingPathDelimiter(ADir) + 'project.xml';
  if FileExists(F) then
    Result := F;
end;

{ ---- TProjectTree ---- }

constructor TProjectTree.Create;
begin
  inherited Create;
  FModules := TModuleEntryList.Create(True);
end;

destructor TProjectTree.Destroy;
begin
  FModules.Free;
  inherited Destroy;
end;

function TProjectTree.LoadFromDir(const ADir: string): Boolean;
var
  Dir, POMFile, TopLevel, AnyFile: string;
  P: TProjectBase;
  Entry: TModuleEntry;
begin
  Result := False;
  FModules.Clear;
  FRootPOMFile := '';

  TopLevel := GitToplevel(ADir);
  if TopLevel <> '' then
  begin
    POMFile := FindPOMInDir(TopLevel);
    if POMFile <> '' then
    begin
      FRootPOMFile := POMFile;
      P := TProjectBase.LoadFromFile(POMFile);
      try
        ScanModules(TProjectPOM(P), ExtractFilePath(POMFile));
      finally
        P.Free;
      end;
      Exit(True);
    end;
  end;

  Dir := ExcludeTrailingPathDelimiter(ExpandFileName(ADir));
  repeat
    POMFile := FindPOMInDir(Dir);
    if POMFile <> '' then
    begin
      FRootPOMFile := POMFile;
      P := TProjectBase.LoadFromFile(POMFile);
      try
        ScanModules(TProjectPOM(P), ExtractFilePath(POMFile));
      finally
        P.Free;
      end;
      Exit(True);
    end;
    Dir := ExcludeTrailingPathDelimiter(ExtractFilePath(Dir));
  until Dir = '';

  { Fallback: standalone project with no POM parent.
    Walk up from ADir looking for any project.xml; treat it as the sole module. }
  Dir := ExcludeTrailingPathDelimiter(ExpandFileName(ADir));
  repeat
    AnyFile := FindAnyProjectInDir(Dir);
    if AnyFile <> '' then
    begin
      FRootPOMFile := AnyFile;
      Entry := TModuleEntry.Create;
      Entry.PathComponent := '.';
      Entry.ModuleDir     := Dir;
      Entry.ProjectFile   := AnyFile;
      try
        P := TProjectBase.LoadFromFile(AnyFile);
        try
          Entry.ProjectName := P.Name;
        finally
          P.Free;
        end;
      except
      end;
      FModules.Add(Entry);
      Exit(True);
    end;
    Dir := ExcludeTrailingPathDelimiter(ExtractFilePath(Dir));
  until Dir = '';
end;

procedure TProjectTree.ScanModules(APOM: TProjectPOM; const APOMDir: string);
var
  I: Integer;
  M: TModule;
  Entry: TModuleEntry;
  ModDir, ProjFile: string;
  Sub: TProjectBase;
begin
  for I := 0 to APOM.Modules.Count - 1 do
  begin
    M := APOM.Modules[I];
    ModDir   := ExpandFileName(IncludeTrailingPathDelimiter(APOMDir) + M.Path);
    ProjFile := IncludeTrailingPathDelimiter(ModDir) + 'project.xml';

    Entry := TModuleEntry.Create;
    Entry.PathComponent := M.Path;
    Entry.ModuleDir     := ModDir;
    Entry.ProjectFile   := ProjFile;

    if FileExists(ProjFile) then
    begin
      try
        Sub := TProjectBase.LoadFromFile(ProjFile);
        try
          Entry.ProjectName := Sub.Name;
          if Sub is TProjectPOM then
            ScanModules(TProjectPOM(Sub), ModDir);
        finally
          Sub.Free;
        end;
      except
      end;
    end;

    FModules.Add(Entry);
  end;
end;

function TProjectTree.FindModule(const AName: string;
  out AProjectFile: string): Boolean;
var
  I: Integer;
  E: TModuleEntry;
begin
  for I := 0 to FModules.Count - 1 do
  begin
    E := FModules[I];
    if SameText(E.PathComponent, AName) or SameText(E.ProjectName, AName) then
    begin
      AProjectFile := E.ProjectFile;
      Exit(True);
    end;
  end;
  Result       := False;
  AProjectFile := '';
end;

procedure TProjectTree.GetModuleNames(AList: TStringList);
var
  I: Integer;
  E: TModuleEntry;
begin
  for I := 0 to FModules.Count - 1 do
  begin
    E := FModules[I];
    AList.Add(E.PathComponent);
    { Also add the project <name> as an alias if it differs from the dir name,
      so both can be used with --module and both appear in completion. }
    if (E.ProjectName <> '') and not SameText(E.ProjectName, E.PathComponent) then
      AList.Add(E.ProjectName);
  end;
end;

end.
