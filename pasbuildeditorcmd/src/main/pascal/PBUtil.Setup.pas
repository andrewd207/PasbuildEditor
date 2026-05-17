{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.

  Bash completion and first-run / install helpers for pb-editor-cmd.

  Bash completion protocol:
    pb-editor-cmd --bash <cword_index> <word0> <word1> ... <wordN>

  Completions are written one per line to stdout (plain text, not JSON).
  The registered bash completion function calls us this way so the shell
  populates COMPREPLY automatically.

  Install actions (--install or first-run prompt):
    1. Append completion hook to ~/.bashrc
    2. Copy the binary to the first user-writable dir found in $PATH

  First-run marker: ~/.pasbuild/.pb-editor-cmd-setup
  If absent AND stdout is a terminal, the user is prompted interactively.
  The marker is written once setup completes (or is declined).
}
unit PBUtil.Setup;

{$mode objfpc}{$H+}

interface

{ Bash completion: write one candidate per line to stdout based on the
  partial command line passed by the bash completion function.
  ACword is the index of the word currently being typed (0-based). }
procedure DoBashCompletion(ACword: Integer; const AWords: array of string);

{ Run the interactive install wizard.  Offers bash-completion registration
  and binary copy.  Always writes the first-run marker when done. }
procedure DoInstall;

{ If this is the first run and stdout is a terminal, run DoInstall. }
procedure CheckFirstRun;

implementation

uses
  SysUtils, Classes,
  {$IFDEF UNIX}termio, BaseUnix,{$ENDIF}
  PBLib.ProjectModel, PBLib.ProjectTree;

{ ---- Constants ---- }

const
  MarkerName = '.pb-editor-cmd-setup';

  AllFlags: array[0..48] of string = (
    '--module', '--list-modules', '--list-goals', '--list-compilers',
    '--execute-goals', '--all-modules',
    '--get', '--set',
    '--run',
    '--rename-module-dir',
    '--add-dependency',        '--remove-dependency',
    '--add-module-dependency', '--remove-module-dependency',
    '--add-unit-path',         '--remove-unit-path',
    '--add-include-path',      '--remove-include-path',
    '--add-define',            '--remove-define',
    '--add-compiler-option',   '--remove-compiler-option',
    '--add-bootstrap-exclude', '--remove-bootstrap-exclude',
    '--add-profile',           '--remove-profile',
    '--add-profile-define',    '--remove-profile-define',
    '--add-profile-option',    '--remove-profile-option',
    '--add-pom-module',        '--remove-pom-module',
    '--add-new-module',
    '--inactive',
    '--profile',
    '--verbose', '--include-inactive', '--all-modules',
    '--compiler',
    '--timeout',
    '--filter-tags', '--show-summary', '--error-context', '--no-json',
    '--help', '--help-examples', '--help-fields', '--install', '--bash'
  );

  SetFields: array[0..14] of string = (
    'project.name',
    'project.version',
    'project.author',
    'project.license',
    'project.description',
    'project.projectUrl',
    'project.repoUrl',
    'project.build.mainSource',
    'project.build.executableName',
    'project.build.outputDirectory',
    'project.build.sourceDirectory',
    'project.build.manualUnitPaths',
    'project.test.testSource',
    'project.test.testSourceDirectory',
    'project.test.framework'
  );

  KnownGoals: array[0..10] of string = (
    'clean', 'process-resources', 'compile', 'process-test-resources',
    'test-compile', 'test', 'package', 'source-package', 'install',
    'dependency-tree', 'resolve'
  );

  { Flags valid alongside --execute-goals, offered once at least one goal
    has been typed.  Each may only be used once, so we suppress duplicates. }
  ExecuteFlags: array[0..8] of string = (
    '--profile', '--verbose', '--include-inactive',
    '--compiler', '--timeout',
    '--filter-tags', '--show-summary', '--error-context', '--no-json'
  );

  KnownCompilers: array[0..1] of string = ('fpc', 'blaise');

  KnownTags: array[0..3] of string = ('INFO', 'WARNING', 'ERROR', 'RAW');

  BashSnippet =
    '# pb-editor-cmd bash completion'                                           + LineEnding +
    '_pb_editor_cmd() {'                                                         + LineEnding +
    '    COMPREPLY=($(pb-editor-cmd --bash "$COMP_CWORD" "${COMP_WORDS[@]}" 2>/dev/null))' + LineEnding +
    '}'                                                                          + LineEnding +
    'complete -F _pb_editor_cmd pb-editor-cmd';

{ ---- Helpers ---- }

function MarkerPath: string;
begin
  Result := IncludeTrailingPathDelimiter(GetUserDir) +
            '.pasbuild' + PathDelim + MarkerName;
end;

function IsFirstRun: Boolean;
begin
  Result := not FileExists(MarkerPath);
end;

procedure MarkInstalled;
var
  Dir: string;
  F: TextFile;
begin
  Dir := IncludeTrailingPathDelimiter(GetUserDir) + '.pasbuild';
  if not DirectoryExists(Dir) then
    ForceDirectories(Dir);
  AssignFile(F, MarkerPath);
  Rewrite(F);
  CloseFile(F);
end;

function StdoutIsTerminal: Boolean;
begin
  {$IFDEF UNIX}
  Result := IsATTY(1) = 1;
  {$ELSE}
  Result := IsConsole;
  {$ENDIF}
end;

function ReadYN(const APrompt: string): Boolean;
var
  S: string;
begin
  Write(APrompt + ' [y/N] ');
  ReadLn(S);
  Result := (Length(S) > 0) and (UpCase(S[1]) = 'Y');
end;

{ Return the first directory in $PATH that lives under the user's home dir
  and already exists.  Prefers ~/bin; falls back to ~/.local/bin; then any
  matching dir found in PATH order. }
function FindUserBinDir: string;
var
  PathVar, Home, Dir: string;
  Parts: TStringList;
  I: Integer;
  Preferred: array[0..1] of string;
begin
  Result := '';
  Home := ExcludeTrailingPathDelimiter(GetUserDir);

  Preferred[0] := Home + PathDelim + 'bin';
  Preferred[1] := Home + PathDelim + '.local' + PathDelim + 'bin';
  for I := 0 to High(Preferred) do
    if DirectoryExists(Preferred[I]) then
    begin
      Result := Preferred[I];
      Exit;
    end;

  PathVar := GetEnvironmentVariable('PATH');
  Parts := TStringList.Create;
  try
    Parts.Delimiter := PathSeparator;
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := PathVar;
    for I := 0 to Parts.Count - 1 do
    begin
      Dir := Parts[I];
      if (Length(Dir) > Length(Home)) and
         (Copy(Dir, 1, Length(Home)) = Home) and
         DirectoryExists(Dir) then
      begin
        Result := Dir;
        Exit;
      end;
    end;
  finally
    Parts.Free;
  end;
end;

procedure CopyBinary(const ASrc, ADest: string);
var
  Src, Dst: TFileStream;
begin
  Src := TFileStream.Create(ASrc, fmOpenRead or fmShareDenyNone);
  try
    Dst := TFileStream.Create(ADest, fmCreate);
    try
      Dst.CopyFrom(Src, 0);
    finally
      Dst.Free;
    end;
  finally
    Src.Free;
  end;
  {$IFDEF UNIX}
  fpChmod(ADest, &755);
  {$ENDIF}
end;

{ ---- Install wizard ---- }

procedure DoInstall;
var
  RcFile, BinDir, Dest, BinName, Backup: string;
  SrcAge, DestAge: LongInt;
  F: TextFile;
  AlreadyInRc: Boolean;
  Content: TStringList;
begin
  WriteLn('pb-editor-cmd self-install');
  WriteLn('(This installs the pb-editor-cmd tool itself, not your pasbuild project)');
  WriteLn('--------------------------');

  { Bash completion }
  RcFile := IncludeTrailingPathDelimiter(GetUserDir) + '.bashrc';
  AlreadyInRc := False;
  if FileExists(RcFile) then
  begin
    Content := TStringList.Create;
    try
      Content.LoadFromFile(RcFile);
      AlreadyInRc := Content.IndexOf('_pb_editor_cmd()') >= 0;
    finally
      Content.Free;
    end;
  end;

  if AlreadyInRc then
    WriteLn('Bash completion already registered in ' + RcFile + '.')
  else if ReadYN('Register bash completion in ' + RcFile + '?') then
  begin
    if FileExists(RcFile) then
    begin
      Backup := RcFile + '.' + FormatDateTime('yyyymmdd_hhnnss', Now) + '.bak';
      CopyBinary(RcFile, Backup);
      WriteLn('Backed up ' + RcFile + ' → ' + ExtractFileName(Backup));
    end;
    AssignFile(F, RcFile);
    if FileExists(RcFile) then Append(F) else Rewrite(F);
    try
      WriteLn(F, '');
      WriteLn(F, BashSnippet);
    finally
      CloseFile(F);
    end;
    WriteLn('Done.  Run: source ' + RcFile);
  end;

  WriteLn;

  { Binary copy }
  BinDir := FindUserBinDir;
  {$IFDEF WINDOWS}
  BinName := 'pb-editor-cmd.exe';
  {$ELSE}
  BinName := 'pb-editor-cmd';
  {$ENDIF}
  if BinDir = '' then
    WriteLn('No user bin directory found in $PATH — skipping binary copy.')
  else
  begin
    Dest := IncludeTrailingPathDelimiter(BinDir) + BinName;

    { Running from the destination path — nothing to do }
    if SameText(ExpandFileName(ParamStr(0)), ExpandFileName(Dest)) then
      WriteLn('Binary already installed at ' + Dest + '.')

    else if FileExists(Dest) then
    begin
      { Compare modification times: if the installed copy is older than the
        binary we are running now, replace it silently.  If it is the same age
        or newer, ask the user — they may have a custom build there. }
      SrcAge  := FileAge(ParamStr(0));
      DestAge := FileAge(Dest);
      if SrcAge > DestAge then
      begin
        WriteLn('Installed binary at ' + Dest + ' is older — updating.');
        try
          CopyBinary(ParamStr(0), Dest);
          WriteLn('Updated ' + Dest + '.');
        except
          on E: Exception do
            WriteLn('Update failed: ' + E.Message);
        end;
      end
      else if ReadYN('Installed binary at ' + Dest + ' is up-to-date. Overwrite anyway?') then
      begin
        try
          CopyBinary(ParamStr(0), Dest);
          WriteLn('Overwritten ' + Dest + '.');
        except
          on E: Exception do
            WriteLn('Copy failed: ' + E.Message);
        end;
      end;
    end

    else if ReadYN('Copy ' + BinName + ' to ' + BinDir + '?') then
    begin
      try
        CopyBinary(ParamStr(0), Dest);
        WriteLn('Copied to ' + Dest + '.');
      except
        on E: Exception do
          WriteLn('Copy failed: ' + E.Message);
      end;
    end;
  end;

  WriteLn;
  MarkInstalled;
end;

procedure CheckFirstRun;
begin
  if IsFirstRun and StdoutIsTerminal then
  begin
    WriteLn('');
    WriteLn('pb-editor-cmd: first run detected.');
    DoInstall;
  end;
end;

{ ---- Bash completion ---- }

{ Emit one candidate per line if it starts with the current partial word.
  Bash reads these lines and builds COMPREPLY from them. }
procedure Emit(const ACandidate, APrefix: string);
begin
  if (APrefix = '') or (Copy(ACandidate, 1, Length(APrefix)) = APrefix) then
    WriteLn(ACandidate);
end;

procedure EmitArray(const AArr: array of string; const APrefix: string);
var
  I: Integer;
begin
  for I := Low(AArr) to High(AArr) do
    Emit(AArr[I], APrefix);
end;

{ Scan ADir for executables named pasbuild-<goal>[.exe] and add the goal
  names to AList.  Mirrors the logic in PBEditorCmd.ScanPluginDir so that
  completion sees the same plugins the tool itself does. }
procedure ScanPluginGoals(const ADir: string; AList: TStringList);
const
  Prefix = 'pasbuild-';
  {$IFDEF WINDOWS}
  Suffix = '.exe';
  {$ELSE}
  Suffix = '';
  {$ENDIF}
var
  SR: TSearchRec;
  Name: string;
begin
  if not DirectoryExists(ADir) then Exit;
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + Prefix + '*',
               faAnyFile and not faDirectory, SR) = 0 then
  try
    repeat
      Name := SR.Name;
      Delete(Name, 1, Length(Prefix));
      { Strip .exe on Windows }
      if (Suffix <> '') and (Length(Name) > Length(Suffix)) and
         (CompareText(Copy(Name, Length(Name) - Length(Suffix) + 1, Length(Suffix)), Suffix) = 0) then
        Delete(Name, Length(Name) - Length(Suffix) + 1, Length(Suffix));
      if (Name <> '') and (AList.IndexOf(Name) < 0) then
        AList.Add(Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

{ Emit all known goal names: built-ins first, then any discovered plugins.
  Scans the project plugins/ dir (found via the tree) and ~/.pasbuild/plugins/
  so completion reflects the same plugin set the tool itself uses.
  ASuppressGoal is skipped — it is the goal immediately before the cursor,
  and repeating the same goal twice in a row never makes sense. }
procedure EmitGoalNames(const APrefix, AProjectRootDir, ASuppressGoal: string);
var
  Goals: TStringList;
  I: Integer;
  UserPluginsDir, ProjectPluginsDir: string;
begin
  Goals := TStringList.Create;
  try
    { Start with the hardcoded built-in goals }
    for I := Low(KnownGoals) to High(KnownGoals) do
      Goals.Add(KnownGoals[I]);

    { Scan user-level plugins: ~/.pasbuild/plugins/ }
    UserPluginsDir := IncludeTrailingPathDelimiter(GetUserDir) +
                      '.pasbuild' + PathDelim + 'plugins';
    ScanPluginGoals(UserPluginsDir, Goals);

    { Scan project-level plugins: <root>/plugins/ }
    if AProjectRootDir <> '' then
    begin
      ProjectPluginsDir := IncludeTrailingPathDelimiter(AProjectRootDir) + 'plugins';
      ScanPluginGoals(ProjectPluginsDir, Goals);
    end;

    for I := 0 to Goals.Count - 1 do
    begin
      { Skip the goal immediately before the cursor — "clean clean" is never
        useful, but "clean test clean" is fine because LastGoal resets to
        "test" by the time we complete the second "clean". }
      if SameText(Goals[I], ASuppressGoal) then Continue;
      Emit(Goals[I], APrefix);
    end;
  finally
    Goals.Free;
  end;
end;

{ Return the root POM directory by walking up from cwd, or '' if not found. }
function GetProjectRootDir: string;
var
  Tree: TProjectTree;
begin
  Result := '';
  Tree := TProjectTree.Create;
  try
    if Tree.LoadFromDir(GetCurrentDir) then
      Result := ExtractFilePath(Tree.RootPOMFile);
  finally
    Tree.Free;
  end;
end;

{ Walk the project tree to get real module names.
  Used for --module value completion so the user sees live module names. }
procedure EmitModuleNames(const APrefix: string);
var
  Tree: TProjectTree;
  I: Integer;
  E: TModuleEntry;
  Name: string;
begin
  Tree := TProjectTree.Create;
  try
    if Tree.LoadFromDir(GetCurrentDir) then
      for I := 0 to Tree.Modules.Count - 1 do
      begin
        E := Tree.Modules[I];
        { Prefer the project <name> field; fall back to directory component }
        if E.ProjectName <> '' then
          Name := E.ProjectName
        else
          Name := E.PathComponent;
        Emit(Name, APrefix);
      end;
  finally
    Tree.Free;
  end;
end;

{ Emit package names from the local pasbuild repository (~/.pasbuild/repository/).
  Each subdirectory is a package name. }
procedure EmitRepoPackages(const APrefix: string);
var
  RepoDir: string;
  SR: TSearchRec;
begin
  RepoDir := IncludeTrailingPathDelimiter(GetUserDir) +
             '.pasbuild' + PathDelim + 'repository';
  if not DirectoryExists(RepoDir) then Exit;
  if FindFirst(RepoDir + PathDelim + '*', faDirectory, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then Continue;
      if (SR.Attr and faDirectory) <> 0 then
        Emit(SR.Name, APrefix);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

{ Emit version strings available for APackage in the local repository. }
procedure EmitRepoVersions(const APackage, APrefix: string);
var
  PkgDir: string;
  SR: TSearchRec;
begin
  PkgDir := IncludeTrailingPathDelimiter(GetUserDir) +
            '.pasbuild' + PathDelim + 'repository' + PathDelim + APackage;
  if not DirectoryExists(PkgDir) then Exit;
  if FindFirst(PkgDir + PathDelim + '*', faDirectory, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then Continue;
      if (SR.Attr and faDirectory) <> 0 then
        Emit(SR.Name, APrefix);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

{ Return true if the named module is a POM project, by loading its project.xml.
  Returns false on any error (not found, not a POM, load failure). }
function ModuleIsPOM(const AModuleName: string): Boolean;
var
  Tree: TProjectTree;
  ProjFile: string;
  Proj: TProjectBase;
begin
  Result := False;
  Tree := TProjectTree.Create;
  try
    if not Tree.LoadFromDir(GetCurrentDir) then Exit;
    { '.' and 'root' are shorthands for the root POM, which is always a POM }
    if (AModuleName = '.') or (AModuleName = 'root') then
    begin
      Result := FileExists(Tree.RootPOMFile);
      Exit;
    end;
    if not Tree.FindModule(AModuleName, ProjFile) then Exit;
    try
      Proj := TProjectBase.LoadFromFile(ProjFile);
      try
        Result := Proj is TProjectPOM;
      finally
        Proj.Free;
      end;
    except
    end;
  finally
    Tree.Free;
  end;
end;

{ Parsed state of everything typed on the command line so far.
  We scan left-to-right through the already-typed words to figure out
  which "stage" the user is in, so we only offer flags that are actually
  valid next. }
type
  TCompletionState = record
    HasModule:      Boolean;   // --module <name> fully consumed
    ModuleName:     string;    // the name passed to --module
    HasAllModules:  Boolean;   // --all-modules present
    HasExecute:     Boolean;   // --execute-goals present
    HasGet:         Boolean;   // --get <field> fully consumed
    IsDone:         Boolean;   // command is complete — no further flags make sense
                               // (--list-*, or --rename-module-dir <value> consumed)
    InExecuteList:  Boolean;   // cursor is still inside the goals word-list
    InFilterList:   Boolean;   // cursor is still inside the --filter-tags list
    ValueFlag:      string;    // we are completing the first value for this flag
    ValueFlag2:     string;    // we are completing the second value (e.g. version after package name)
    DepName:        string;    // the package name already typed for --add-dependency
    LastGoal:       string;    // the goal immediately before the cursor (suppress repeat)
  end;

{ Scan all words before ACword to build the completion state.
  Each flag that takes a value consumes the next word; list-flags (--execute-goals,
  --filter-tags) consume words until the next -- flag. }
function BuildState(ACword: Integer;
                    const AWords: array of string): TCompletionState;
var
  I: Integer;
  W: string;
  SkipNext: Boolean;
begin
  FillChar(Result, SizeOf(Result), 0);
  SkipNext := False;
  I := 1;  { skip word[0] which is the program name }
  while I < ACword do
  begin
    W := AWords[I];

    { If the previous iteration flagged this word as a consumed value, skip it }
    if SkipNext then
    begin
      SkipNext := False;
      Inc(I);
      Continue;
    end;

    { Any flag that starts with '--' resets list-collecting modes }
    if (Length(W) > 0) and (W[1] = '-') then
    begin
      Result.InExecuteList := False;
      Result.InFilterList  := False;
      Result.ValueFlag     := '';
    end;

    { Track which primary mode the user has entered }
    if W = '--module' then
    begin
      { The name that follows is the value; skip it next iteration.
        We consider the module "set" only after its value has been consumed. }
      if I + 1 < ACword then
      begin
        Result.HasModule  := True;
        Result.ModuleName := AWords[I + 1];
        SkipNext := True;
      end
      else
        Result.ValueFlag := '--module';
    end
    else if W = '--all-modules' then
      Result.HasAllModules := True

    { Listing flags are complete commands — nothing meaningful follows them }
    else if (W = '--list-modules') or (W = '--list-goals') or
            (W = '--list-compilers') then
      Result.IsDone := True

    { --rename-module-dir is a standalone operation; once its value is consumed
      the command is complete }
    else if W = '--rename-module-dir' then
    begin
      if I + 1 < ACword then
      begin
        SkipNext := True;
        Result.IsDone := True;
      end
      else
        Result.ValueFlag := W;
    end

    else if W = '--execute-goals' then
    begin
      Result.HasExecute     := True;
      Result.InExecuteList  := True;  { words that follow are goals, not flags }
    end

    else if W = '--filter-tags' then
      Result.InFilterList := True

    { A non-flag word while collecting goals: record it as the last goal so
      we can suppress it from suggestions.  "clean test clean" is fine — only
      repeating the immediately preceding goal ("clean clean") is suppressed. }
    else if Result.InExecuteList then
      Result.LastGoal := W
    { Single-value flags: the word that follows is a value, not a flag }
    { --add-dependency takes two words: package name then version.
      Track both so we can offer repo names for the first and repo versions
      for the second. }
    else if W = '--add-dependency' then
    begin
      if I + 2 < ACword then
      begin
        { Both values already consumed — skip both }
        SkipNext := True;  { skips name }
        Inc(I);            { pre-advance so SkipNext skips version }
      end
      else if I + 1 < ACword then
      begin
        { Name consumed, version is the cursor word }
        Result.DepName   := AWords[I + 1];
        Result.ValueFlag2 := W;
        SkipNext := True;
      end
      else
        { Neither consumed yet — cursor word is the name }
        Result.ValueFlag := W;
    end

    else if W = '--get' then
    begin
      if I + 1 < ACword then
      begin
        SkipNext := True;
        Result.HasGet := True;  { field value consumed — --no-json now valid }
      end
      else
        Result.ValueFlag := W;
    end

    else if (W = '--set') or (W = '--compiler') or (W = '--profile') or
            (W = '--timeout') or (W = '--error-context') or
            (W = '--add-module-dependency') or
            (W = '--add-unit-path') or (W = '--add-include-path') or
            (W = '--add-define') or (W = '--add-compiler-option') or
            (W = '--add-bootstrap-exclude') or
            (W = '--add-profile') or (W = '--remove-profile') or
            (W = '--add-pom-module') or (W = '--remove-pom-module') or
            (W = '--add-new-module') or
            (W = '--remove-dependency') or (W = '--remove-module-dependency') or
            (W = '--remove-unit-path') or (W = '--remove-include-path') or
            (W = '--remove-define') or (W = '--remove-compiler-option') or
            (W = '--remove-bootstrap-exclude') then
    begin
      if I + 1 < ACword then
        SkipNext := True
      else
        Result.ValueFlag := W;
    end;

    Inc(I);
  end;

  { If the cursor word itself is not a flag and we are in a list, stay there }
  if ACword < Length(AWords) then
  begin
    W := AWords[ACword];
    if (Length(W) = 0) or (W[1] <> '-') then
    begin
      { non-flag partial word: list modes remain active }
    end
    else
    begin
      { partial flag word: leave list modes so we offer flag completions }
      Result.InExecuteList := False;
      Result.InFilterList  := False;
    end;
  end;
end;

procedure DoBashCompletion(ACword: Integer; const AWords: array of string);
var
  Cur:         string;
  St:          TCompletionState;
  I, J:        Integer;
  AlreadyUsed: Boolean;
begin
  { The word currently being typed (may be empty if the user just hit Tab) }
  Cur := '';
  if ACword < Length(AWords) then
    Cur := AWords[ACword];

  { Understand what the user has already typed }
  St := BuildState(ACword, AWords);

  { Commands that take no further arguments once complete }
  if St.IsDone then Exit;

  { ── Value completions ──────────────────────────────────────────────────
    If we are filling in the argument to a specific flag, offer the right
    set of values for that flag rather than more flags. }

  if St.ValueFlag = '--module' then
  begin
    { Show live module names from the project tree }
    EmitModuleNames(Cur);
    Exit;
  end;

  if St.ValueFlag = '--compiler' then
  begin
    EmitArray(KnownCompilers, Cur);
    Exit;
  end;

  if (St.ValueFlag = '--get') or (St.ValueFlag = '--set') then
  begin
    { List every dotted field path that --get / --set accepts }
    EmitArray(SetFields, Cur);
    Exit;
  end;

  if St.HasGet then
  begin
    { --get <field> is fully typed; the only useful follow-on flag is --no-json,
      but only if it hasn't been typed already. }
    for I := 1 to ACword - 1 do
      if AWords[I] = '--no-json' then Exit;
    Emit('--no-json', Cur);
    Exit;
  end;

  if St.ValueFlag = '--timeout' then
  begin
    { Offer sane timeout values in seconds.  Nothing else is shown here —
      the user must supply a value before more flags become available. }
    EmitArray(['30', '60', '120', '300', '600'], Cur);
    Exit;
  end;

  if St.ValueFlag = '--error-context' then
  begin
    { Lines of context around each ERROR line — small numbers make sense }
    EmitArray(['1', '2', '3', '5', '10'], Cur);
    Exit;
  end;

  if St.ValueFlag = '--add-dependency' then
  begin
    { First word after --add-dependency: offer package names from the local repo }
    EmitRepoPackages(Cur);
    Exit;
  end;

  if St.ValueFlag2 = '--add-dependency' then
  begin
    { Second word: offer versions available for the already-typed package name }
    EmitRepoVersions(St.DepName, Cur);
    Exit;
  end;

  { ── List-argument completions ──────────────────────────────────────────
    --execute-goals and --filter-tags consume multiple words until the next
    -- flag.  While we are inside those lists keep offering their values. }

  if St.InExecuteList then
  begin
    { Always offer more goals (minus the one immediately before the cursor) }
    EmitGoalNames(Cur, GetProjectRootDir, St.LastGoal);

    { Once at least one goal has been typed we can also offer the execution-
      control flags — the user may want to pin a profile, set a timeout, etc.
      without having to finish the goals list first.  Only offer flags that
      have not already appeared on the command line. }
    if St.LastGoal <> '' then
      for I := 0 to High(ExecuteFlags) do
      begin
        AlreadyUsed := False;
        for J := 1 to ACword - 1 do
          if AWords[J] = ExecuteFlags[I] then
          begin
            AlreadyUsed := True;
            Break;
          end;
        if not AlreadyUsed then
          Emit(ExecuteFlags[I], Cur);
      end;
    Exit;
  end;

  if St.InFilterList then
  begin
    { Only the three standard tags are known ahead of time; plugins can add
      more but we can't discover those here without running the build }
    EmitArray(KnownTags, Cur);
    Exit;
  end;

  { ── Flag completions — progressive disclosure ──────────────────────────
    We show only the flags that are meaningful given what has already been
    typed.  The stages are:

      Stage 1 (nothing chosen yet):
        Entry-point flags only — --module, --all-modules, --list-*, --help,
        --install.  No mutation flags; they require a module context.

      Stage 2 (--module <name> consumed):
        Mutation flags (--set, --add-*, --remove-*) become available, plus
        --execute-goals to run goals against the selected module.

      Stage 3 (--all-modules chosen, no --execute-goals yet):
        Only --execute-goals makes sense; --all-modules does not accept
        mutations.

      Stage 4 (--execute-goals seen):
        Execution-control flags: --profile, --verbose, --include-inactive,
        --all-modules, --compiler, --timeout, --filter-tags, --show-summary,
        --error-context, --no-json. }

  if St.HasExecute then
  begin
    { Stage 4: user is past the goals list and configuring the run.
      Suppress any execution-control flag already present in the command. }
    for I := 0 to High(ExecuteFlags) do
    begin
      AlreadyUsed := False;
      for J := 1 to ACword - 1 do
        if AWords[J] = ExecuteFlags[I] then
        begin
          AlreadyUsed := True;
          Break;
        end;
      if not AlreadyUsed then
        Emit(ExecuteFlags[I], Cur);
    end;
    Exit;
  end;

  if St.HasAllModules then
  begin
    { Stage 3: --all-modules is set; the only next step is --execute-goals }
    Emit('--execute-goals', Cur);
    Exit;
  end;

  if St.HasModule then
  begin
    { Stage 2: a module is selected — offer mutations and goal execution.
      POM-only flags are only shown when the selected module is actually a POM. }
    EmitArray([
      '--get', '--set',
      '--add-dependency',        '--remove-dependency',
      '--add-module-dependency', '--remove-module-dependency',
      '--add-unit-path',         '--remove-unit-path',
      '--add-include-path',      '--remove-include-path',
      '--add-define',            '--remove-define',
      '--add-compiler-option',   '--remove-compiler-option',
      '--add-bootstrap-exclude', '--remove-bootstrap-exclude',
      '--add-profile',           '--remove-profile',
      '--add-profile-define',    '--remove-profile-define',
      '--add-profile-option',    '--remove-profile-option',
      '--run',
      '--rename-module-dir',
      '--execute-goals'
    ], Cur);
    { POM-only flags: only offer them when the module is actually a POM }
    if ModuleIsPOM(St.ModuleName) then
      EmitArray([
        '--add-pom-module', '--remove-pom-module',
        '--add-new-module',
        '--inactive'
      ], Cur);
    Exit;
  end;

  { Stage 1: nothing chosen yet — show only the entry-point flags.
    We deliberately hide mutation flags and execution-control flags here
    because they all require --module or --all-modules first. }
  EmitArray([
    '--module',
    '--all-modules',
    '--list-modules',
    '--list-goals',
    '--list-compilers',
    '--help',
    '--help-examples',
    '--help-fields',
    '--install'
  ], Cur);
end;

end.
