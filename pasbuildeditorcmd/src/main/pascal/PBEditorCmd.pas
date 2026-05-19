{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.

  pb-editor-cmd — non-interactive CLI for reading and mutating pasbuild
  project.xml files.  All output is JSON (stdout).  Status messages during
  interactive sub-processes (e.g. pasbuild init) go to stderr so tooling
  can separate them.

  Exit codes:
    0  success
    1  error (bad args, module not found, write failure, …)
    2  validation error (known field, invalid value)
    <pasbuild exit code>  forwarded when --execute-goals is used with --no-json

  Missing features / future work:
    --validate          Check project integrity (paths exist, semver valid, etc.)
    --dry-run           Show what would change without writing project.xml
    --root <dir>        Override automatic POM detection
    --format text       Human-readable output alternative
    Stdin JSON mode     Read a mutation batch from stdin (piping support)
    project.profiles.* in --set  (e.g. project.profiles.debug.defines)
    project.build.resources.* in --set
    project.test.resources.* in --set
}
program PBEditorCmd;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads, BaseUnix,{$ENDIF}
  SysUtils, Classes, StrUtils, Process, Math, fpjson,
  PBLib.ProjectModel, PBLib.ProjectTree, PBLib.JSON,
  PBUtil.Setup;

const
  VERSION = '0.1.0';

type
  TMutationKind = (
    mkSet,
    mkAddDependency,        mkRemoveDependency,
    mkAddModuleDep,         mkRemoveModuleDep,
    mkAddUnitPath,          mkRemoveUnitPath,
    mkAddIncludePath,       mkRemoveIncludePath,
    mkAddDefine,            mkRemoveDefine,
    mkAddCompilerOption,    mkRemoveCompilerOption,
    mkAddBootstrapExclude,  mkRemoveBootstrapExclude,
    mkAddProfile,           mkRemoveProfile,
    mkAddProfileDefine,     mkRemoveProfileDefine,
    mkAddProfileOption,     mkRemoveProfileOption,
    mkAddPOMModule,         mkRemovePOMModule,
    mkSetModuleActive,
    mkInitNewModule
  );

  TMutation = record
    Kind: TMutationKind;
    A, B, C: string;   // generic arg slots; meaning depends on Kind
  end;

{ ---- Known compilers (for --list-compilers) ---- }

const
  KnownCompilers: array[0..1] of string = ('fpc', 'blaise');
  KnownCompilerDescs: array[0..1] of string = (
    'Free Pascal Compiler — production compiler for all pasbuild projects',
    'Blaise — experimental Pascal compiler');

{ ---- Known pasbuild goals (for --list-goals) ---- }

const
  KnownGoals: array[0..11] of string = (
    'clean', 'process-resources', 'compile', 'process-test-resources',
    'test-compile', 'test', 'package', 'source-package', 'install',
    'dependency-tree', 'resolve', 'init');

  KnownGoalDescs: array[0..11] of string = (
    'Delete all build artifacts',
    'Copy resources to target directory',
    'Build the executable (implies: process-resources)',
    'Copy test resources to target directory',
    'Compile tests (implies: compile, process-test-resources)',
    'Run tests (implies: compile, process-test-resources, test-compile)',
    'Create release archive (implies: clean, compile)',
    'Create source archive with src/, docs, and configured includes',
    'Install compiled units to ~/.pasbuild/repository/',
    'Show project dependency tree (no compilation)',
    'Output resolved build configuration as JSON (no compilation)',
    'Create new project structure interactively');

var
  GModuleName:    string;
  GListModules:    Boolean;
  GListGoals:      Boolean;
  GListCompilers:  Boolean;
  GShowHelp:      Boolean;
  GShowExamples:  Boolean;
  GShowFields:    Boolean;
  GMutations:     array of TMutation;
  GMutCount:      Integer;
  { --execute-goals }
  GExecuteGoals:  TStringList;
  GProfile:       string;       // -p / --profile
  GNoJson:        Boolean;      // stream pasbuild output raw
  GFilterTags:    TStringList;  // only emit lines with these [TAG] prefixes
  GShowSummary:   Boolean;      // only emit the final reactor summary block
  GErrorContext:  Integer;      // lines of context around each [ERROR] line
  GVerbose:       Boolean;      // pass -v to pasbuild
  GBuildAll:      Boolean;      // pass --all to pasbuild
  GAllModules:    Boolean;      // run on whole reactor (no -m flag)
  GCompiler:      string;       // pass --compiler <path> to pasbuild
  GTimeout:       Integer;      // seconds; 0 = no timeout
  GInstall:       Boolean;      // run install wizard explicitly
  GBashCword:     Integer;      // --bash <cword> completion mode (-1 = off)
  GBashWords:     TStringList;  // words passed to --bash
  GRenameModuleDir: string;     // --rename-module-dir <new-name>
  GRun:           Boolean;      // --run: execute the built application
  GRunArgs:       TStringList;  // arguments forwarded after --
  GGetField:        string;     // --get <field>: read a single scalar field
  GGetModuleActive: string;     // --get-module-active <path>: read activeByDefault for a POM child

{ ---- Arg helpers ---- }

procedure AddMutation(AKind: TMutationKind; const AA, AB, AC: string);
begin
  if GMutCount >= Length(GMutations) then
    SetLength(GMutations, GMutCount + 16);
  GMutations[GMutCount].Kind := AKind;
  GMutations[GMutCount].A    := AA;
  GMutations[GMutCount].B    := AB;
  GMutations[GMutCount].C    := AC;
  Inc(GMutCount);
end;

{ ---- Error exit helpers ---- }

procedure Die(const AMsg: string; ACode: Integer = 1);
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  Obj.Add('error', AMsg);
  PrintJSON(Obj);
  Halt(ACode);
end;

procedure DieWithModules(const AMsg: string; ATree: TProjectTree);
var
  Names: TStringList;
  Obj: TJSONObject;
begin
  Names := TStringList.Create;
  try
    ATree.GetModuleNames(Names);
    Obj := ErrorJSON(AMsg, Names);
  finally
    Names.Free;
  end;
  PrintJSON(Obj);
  Halt(1);
end;

{ ---- Usage ---- }

procedure PrintUsage;
begin
  WriteLn('pb-editor-cmd v', VERSION);
  WriteLn('Non-interactive CLI for pasbuild project.xml files.  Output is always JSON.');
  WriteLn;
  WriteLn('Usage:');
  WriteLn('  pb-editor-cmd --module <name> [mutations...]');
  WriteLn('  pb-editor-cmd --list-modules');
  WriteLn('  pb-editor-cmd --help');
  WriteLn;
  WriteLn('Module selection:');
  WriteLn('  --module <name>      Select module by directory name or project <name>.');
  WriteLn('                       Required for all operations except --list-modules.');
  WriteLn('  --list-modules       List all modules found in the project tree.');
  WriteLn;
  WriteLn('Reading:');
  WriteLn('  (no mutations given) Dump all project fields as JSON.');
  WriteLn('  --get <field>        Read a single scalar field.  Same field names as --set.');
  WriteLn('                       Outputs {"field":...,"value":...}; with --no-json prints the value only.');
  WriteLn;
  WriteLn('Scalar fields  (--set <field> <value>):');
  WriteLn('  project.name                     project.version');
  WriteLn('  project.author                   project.license');
  WriteLn('  project.description              project.projectUrl');
  WriteLn('  project.repoUrl');
  WriteLn('  project.build.mainSource         project.build.executableName');
  WriteLn('  project.build.outputDirectory    project.build.sourceDirectory');
  WriteLn('  project.build.manualUnitPaths    (true / false)');
  WriteLn('  project.test.testSource          project.test.testSourceDirectory');
  WriteLn('  project.test.framework           (auto / fpcunit / fptest)');
  WriteLn;
  WriteLn('List mutations:');
  WriteLn('  --add-dependency <name> <version>');
  WriteLn('  --remove-dependency <name>');
  WriteLn('  --add-module-dependency <path> [condition]');
  WriteLn('  --remove-module-dependency <path>');
  WriteLn('  --add-unit-path <path> [condition]');
  WriteLn('  --remove-unit-path <path>');
  WriteLn('  --add-include-path <path> [condition]');
  WriteLn('  --remove-include-path <path>');
  WriteLn('  --add-define <define>');
  WriteLn('  --remove-define <define>');
  WriteLn('  --add-compiler-option <option>');
  WriteLn('  --remove-compiler-option <option>');
  WriteLn('  --add-bootstrap-exclude <unit>');
  WriteLn('  --remove-bootstrap-exclude <unit>');
  WriteLn;
  WriteLn('Profile mutations:');
  WriteLn('  --add-profile <id>');
  WriteLn('  --remove-profile <id>');
  WriteLn('  --add-profile-define <id> <define>');
  WriteLn('  --remove-profile-define <id> <define>');
  WriteLn('  --add-profile-option <id> <option>');
  WriteLn('  --remove-profile-option <id> <option>');
  WriteLn;
  WriteLn('Run application:');
  WriteLn('  --run [-- <args...>]');
  WriteLn('    Execute the built application for the selected module.');
  WriteLn('    Only valid for application projects.  The process inherits the');
  WriteLn('    terminal; its exit code is forwarded.  Pass -- to separate app');
  WriteLn('    arguments from pb-editor-cmd flags.');
  WriteLn;
  WriteLn('Module directory rename:');
  WriteLn('  --rename-module-dir <new-name>');
  WriteLn('    Rename the module''s directory on disk and update all project.xml');
  WriteLn('    files in the reactor: the root POM''s <modules> list and every');
  WriteLn('    sibling module''s <moduleDependencies>.  Requires --module.');
  WriteLn('    Fails if the target directory already exists.');
  WriteLn;
  WriteLn('POM module management (--module must point to a POM):');
  WriteLn('  --get-module-active <path>');
  WriteLn('    Read the activeByDefault flag for a child module.');
  WriteLn('    Outputs {"module":...,"activeByDefault":...}; with --no-json prints true/false.');
  WriteLn('  --set-module-active <path> <true|false>');
  WriteLn('    Set the activeByDefault flag for a child module.');
  WriteLn('  --add-pom-module <path> [--inactive]');
  WriteLn('    Add an existing child module path to the POM.');
  WriteLn('  --remove-pom-module <path>');
  WriteLn('    Remove a child module path from the POM.');
  WriteLn('  --add-new-module <path>');
  WriteLn('    Create directory at <path>, run "pasbuild init" there interactively');
  WriteLn('    (init output goes to stderr/tty), then add the module to the POM.');
  WriteLn;
  WriteLn('Conditions for --add-unit-path / --add-include-path:');
  WriteLn('  Platform built-ins: UNIX, LINUX, FREEBSD, DARWIN, WINDOWS, WIN32, WIN64');
  WriteLn('  Or any define name (profile defines, global defines, etc.)');
  WriteLn;
  WriteLn('Build execution (--execute-goals):');
  WriteLn('  --execute-goals <goal> [goal...]');
  WriteLn('    Run one or more pasbuild goals for the selected module.');
  WriteLn('    Goals are consumed until the next -- flag.');
  WriteLn('  --profile <id>           Activate a build profile (-p)');
  WriteLn('  --verbose                Pass -v to pasbuild (full compiler output)');
  WriteLn('  --include-inactive       Include inactive modules in the reactor build');
  WriteLn('  --all-modules            Run on the whole reactor; --module not required');
  WriteLn('  --compiler <path>        Pass --compiler <path> to pasbuild');
  WriteLn('  --timeout <sec>          Kill pasbuild if it runs longer than <sec> seconds');
  WriteLn;
  WriteLn('Build output control (JSON mode, default):');
  WriteLn('  --filter-tags <tag> [tag...]');
  WriteLn('    Only emit output lines whose [TAG] matches. Consumed until next -- flag.');
  WriteLn('    Tags: INFO, WARNING, ERROR, RAW  (case-insensitive; RAW = untagged test/tool output)');
  WriteLn('  --show-summary           Only emit the final reactor summary block');
  WriteLn('  --error-context <n>      Include N lines of context around each [ERROR] line');
  WriteLn('  --no-json                Stream pasbuild output directly; no JSON wrapping');
  WriteLn;
  WriteLn('Discovery:');
  WriteLn('  --list-goals             List built-in goals and discovered plugins');
  WriteLn('  --list-compilers         List known compiler backends (fpc, blaise)');
  WriteLn;
  WriteLn('Tool setup:');
  WriteLn('  --install                Install pb-editor-cmd itself: register bash completion');
  WriteLn('                           and copy the binary to ~/bin. Does not affect your project.');
  WriteLn('  --bash <cword> <words...> Emit bash completion candidates (used by the shell hook)');
  WriteLn;
  WriteLn('Run --help-examples for usage examples.');
  WriteLn('Run --help-fields to list all readable/writable field names.');
end;

procedure PrintFields;
begin
  WriteLn('Fields supported by --get and --set:');
  WriteLn;
  WriteLn('  Common (all packaging types):');
  WriteLn('    project.name');
  WriteLn('    project.version');
  WriteLn('    project.author');
  WriteLn('    project.license');
  WriteLn('    project.description');
  WriteLn('    project.projectUrl');
  WriteLn('    project.repoUrl');
  WriteLn;
  WriteLn('  Build (application / library):');
  WriteLn('    project.build.mainSource');
  WriteLn('    project.build.executableName');
  WriteLn('    project.build.outputDirectory');
  WriteLn('    project.build.sourceDirectory');
  WriteLn('    project.build.manualUnitPaths    (true / false)');
  WriteLn;
  WriteLn('  Test (application / library):');
  WriteLn('    project.test.testSource');
  WriteLn('    project.test.testSourceDirectory');
  WriteLn('    project.test.framework           (auto / fpcunit / fptest)');
end;

procedure PrintExamples;
begin
  WriteLn('pb-editor-cmd examples:');
  WriteLn;
  WriteLn('  Read project state:');
  WriteLn('    pb-editor-cmd --list-modules');
  WriteLn('    pb-editor-cmd --list-goals');
  WriteLn('    pb-editor-cmd --module pasbuildeditor');
  WriteLn;
  WriteLn('  Read a single field:');
  WriteLn('    pb-editor-cmd --module pasbuildeditor --get project.version');
  WriteLn('    pb-editor-cmd --module pasbuildeditor --get project.version --no-json');
  WriteLn('    VERSION=$(pb-editor-cmd --module myapp --get project.version --no-json)');
  WriteLn;
  WriteLn('  Set project properties:');
  WriteLn('    pb-editor-cmd --module pasbuildeditor --set project.version 1.2.0');
  WriteLn('    pb-editor-cmd --module pasbuildeditor --set project.author "Jane Smith"');
  WriteLn('    pb-editor-cmd --module pasbuildeditor --set project.license MIT');
  WriteLn('    pb-editor-cmd --module pasbuildeditor --set project.build.executableName my-tool');
  WriteLn('    pb-editor-cmd --module pasbuildeditor --set project.build.outputDirectory out');
  WriteLn('    pb-editor-cmd --module pasbuildeditor --set project.test.framework fpcunit');
  WriteLn('    pb-editor-cmd --module pasbuildeditor --set project.build.manualUnitPaths true');
  WriteLn;
  WriteLn('  Multiple mutations in one call:');
  WriteLn('    pb-editor-cmd --module pasbuildeditor --set project.version 2.0.0 --set project.author "Jane Smith"');
  WriteLn;
  WriteLn('  Dependencies and paths:');
  WriteLn('    pb-editor-cmd --module pasbuildeditor --add-dependency fpc-fcl-base 3.2.2');
  WriteLn('    pb-editor-cmd --module pasbuildeditor --add-unit-path helpers UNIX');
  WriteLn('    pb-editor-cmd --module pasbuildeditor --add-compiler-option -O2');
  WriteLn('    pb-editor-cmd --module pasbuildeditor --add-define RELEASE_BUILD');
  WriteLn;
  WriteLn('  Run the built application:');
  WriteLn('    pb-editor-cmd --module myapp --run');
  WriteLn('    pb-editor-cmd --module myapp --run -- --verbose input.txt');
  WriteLn;
  WriteLn('  Rename module directory (updates all project.xml files):');
  WriteLn('    pb-editor-cmd --module oldname --rename-module-dir newname');
  WriteLn;
  WriteLn('  POM management:');
  WriteLn('    pb-editor-cmd --module . --add-new-module newlib');
  WriteLn('    pb-editor-cmd --module . --get-module-active termui');
  WriteLn('    pb-editor-cmd --module . --get-module-active termui --no-json');
  WriteLn('    pb-editor-cmd --module . --set-module-active termui false');
  WriteLn;
  WriteLn('  Run goals:');
  WriteLn('    pb-editor-cmd --module pasbuildeditor --execute-goals compile');
  WriteLn('    pb-editor-cmd --module pasbuildeditor --execute-goals compile --profile debug');
  WriteLn('    pb-editor-cmd --module pasbuildeditor --execute-goals compile --filter-tags ERROR WARNING');
  WriteLn('    pb-editor-cmd --module pasbuildeditor --execute-goals test --show-summary');
  WriteLn('    pb-editor-cmd --module pasbuildeditor --execute-goals compile --no-json');
  WriteLn('    pb-editor-cmd --module pasbuildeditor --execute-goals compile --timeout 120');
  WriteLn('    pb-editor-cmd --all-modules --execute-goals compile --show-summary');
  WriteLn('    pb-editor-cmd --all-modules --execute-goals clean compile --show-summary');
end;

{ ---- Argument parsing ---- }

{ Return next arg and advance I, or die if not available. }
function NextArg(var I: Integer; const AFlag: string): string;
begin
  Inc(I);
  if I > ParamCount then
    Die('Flag ' + AFlag + ' requires an argument');
  Result := ParamStr(I);
end;

{ Peek at next arg; return '' if end-of-args or starts with '--'. }
function PeekArg(I: Integer): string;
begin
  if (I + 1 <= ParamCount) and (ParamStr(I + 1)[1] <> '-') then
    Result := ParamStr(I + 1)
  else
    Result := '';
end;

procedure ParseArgs;
var
  I: Integer;
  S, A, B, C: string;
  InactiveNext: Boolean;
begin
  I := 1;
  InactiveNext := False;
  while I <= ParamCount do
  begin
    S := ParamStr(I);

    if (S = '-h') or (S = '--help') then
      GShowHelp := True

    else if S = '--help-examples' then
      GShowExamples := True

    else if S = '--help-fields' then
      GShowFields := True

    else if S = '--list-modules' then
      GListModules := True

    else if S = '--module' then
      GModuleName := NextArg(I, '--module')

    else if S = '--get' then
      GGetField := NextArg(I, '--get')

    else if S = '--set' then
    begin
      A := NextArg(I, '--set');
      B := NextArg(I, '--set <field>');
      AddMutation(mkSet, A, B, '');
    end

    else if S = '--add-dependency' then
    begin
      A := NextArg(I, '--add-dependency');
      B := NextArg(I, '--add-dependency <name>');
      AddMutation(mkAddDependency, A, B, '');
    end

    else if S = '--remove-dependency' then
      AddMutation(mkRemoveDependency, NextArg(I, '--remove-dependency'), '', '')

    else if S = '--add-module-dependency' then
    begin
      A := NextArg(I, '--add-module-dependency');
      C := PeekArg(I);
      if C <> '' then Inc(I);
      AddMutation(mkAddModuleDep, A, C, '');
    end

    else if S = '--remove-module-dependency' then
      AddMutation(mkRemoveModuleDep, NextArg(I, '--remove-module-dependency'), '', '')

    else if S = '--add-unit-path' then
    begin
      A := NextArg(I, '--add-unit-path');
      C := PeekArg(I);
      if C <> '' then Inc(I);
      AddMutation(mkAddUnitPath, A, C, '');
    end

    else if S = '--remove-unit-path' then
      AddMutation(mkRemoveUnitPath, NextArg(I, '--remove-unit-path'), '', '')

    else if S = '--add-include-path' then
    begin
      A := NextArg(I, '--add-include-path');
      C := PeekArg(I);
      if C <> '' then Inc(I);
      AddMutation(mkAddIncludePath, A, C, '');
    end

    else if S = '--remove-include-path' then
      AddMutation(mkRemoveIncludePath, NextArg(I, '--remove-include-path'), '', '')

    else if S = '--add-define' then
      AddMutation(mkAddDefine, NextArg(I, '--add-define'), '', '')

    else if S = '--remove-define' then
      AddMutation(mkRemoveDefine, NextArg(I, '--remove-define'), '', '')

    else if S = '--add-compiler-option' then
      AddMutation(mkAddCompilerOption, NextArg(I, '--add-compiler-option'), '', '')

    else if S = '--remove-compiler-option' then
      AddMutation(mkRemoveCompilerOption, NextArg(I, '--remove-compiler-option'), '', '')

    else if S = '--add-bootstrap-exclude' then
      AddMutation(mkAddBootstrapExclude, NextArg(I, '--add-bootstrap-exclude'), '', '')

    else if S = '--remove-bootstrap-exclude' then
      AddMutation(mkRemoveBootstrapExclude, NextArg(I, '--remove-bootstrap-exclude'), '', '')

    else if S = '--add-profile' then
      AddMutation(mkAddProfile, NextArg(I, '--add-profile'), '', '')

    else if S = '--remove-profile' then
      AddMutation(mkRemoveProfile, NextArg(I, '--remove-profile'), '', '')

    else if S = '--add-profile-define' then
    begin
      A := NextArg(I, '--add-profile-define');
      B := NextArg(I, '--add-profile-define <id>');
      AddMutation(mkAddProfileDefine, A, B, '');
    end

    else if S = '--remove-profile-define' then
    begin
      A := NextArg(I, '--remove-profile-define');
      B := NextArg(I, '--remove-profile-define <id>');
      AddMutation(mkRemoveProfileDefine, A, B, '');
    end

    else if S = '--add-profile-option' then
    begin
      A := NextArg(I, '--add-profile-option');
      B := NextArg(I, '--add-profile-option <id>');
      AddMutation(mkAddProfileOption, A, B, '');
    end

    else if S = '--remove-profile-option' then
    begin
      A := NextArg(I, '--remove-profile-option');
      B := NextArg(I, '--remove-profile-option <id>');
      AddMutation(mkRemoveProfileOption, A, B, '');
    end

    else if S = '--add-pom-module' then
    begin
      A := NextArg(I, '--add-pom-module');
      { Check for optional --inactive flag immediately following }
      if (I + 1 <= ParamCount) and (ParamStr(I + 1) = '--inactive') then
      begin
        Inc(I);
        B := 'false';
      end
      else
        B := 'true';
      AddMutation(mkAddPOMModule, A, B, '');
    end

    else if S = '--remove-pom-module' then
      AddMutation(mkRemovePOMModule, NextArg(I, '--remove-pom-module'), '', '')

    else if S = '--set-module-active' then
    begin
      A := NextArg(I, '--set-module-active');
      B := NextArg(I, '--set-module-active <path>');
      if (LowerCase(B) <> 'true') and (LowerCase(B) <> 'false') then
        Die('--set-module-active requires "true" or "false" as the second argument');
      AddMutation(mkSetModuleActive, A, LowerCase(B), '');
    end

    else if S = '--get-module-active' then
      GGetModuleActive := NextArg(I, '--get-module-active')

    else if S = '--add-new-module' then
      AddMutation(mkInitNewModule, NextArg(I, '--add-new-module'), '', '')

    { ---- Build execution flags ---- }

    else if S = '--list-goals' then
      GListGoals := True

    else if S = '--list-compilers' then
      GListCompilers := True

    else if S = '--execute-goals' then
    begin
      { Consume all non-flag args that follow as goal names }
      while (I + 1 <= ParamCount) and (ParamStr(I + 1)[1] <> '-') do
      begin
        Inc(I);
        GExecuteGoals.Add(ParamStr(I));
      end;
      if GExecuteGoals.Count = 0 then
        Die('--execute-goals requires at least one goal name');
    end

    else if (S = '--profile') or (S = '-p') then
      GProfile := NextArg(I, S)

    else if (S = '--verbose') or (S = '-v') then
      GVerbose := True

    else if S = '--include-inactive' then
      GBuildAll := True

    else if S = '--all-modules' then
      GAllModules := True

    else if S = '--compiler' then
      GCompiler := NextArg(I, '--compiler')

    else if S = '--timeout' then
    begin
      A := NextArg(I, '--timeout');
      GTimeout := StrToIntDef(A, 0);
      if GTimeout <= 0 then
        Die('--timeout requires a positive integer number of seconds');
    end

    else if S = '--no-json' then
      GNoJson := True

    else if S = '--show-summary' then
      GShowSummary := True

    else if S = '--error-context' then
    begin
      A := NextArg(I, '--error-context');
      GErrorContext := StrToIntDef(A, -1);
      if GErrorContext < 0 then
        Die('--error-context requires a non-negative integer');
    end

    else if S = '--filter-tags' then
    begin
      { Consume all non-flag args as tag names }
      while (I + 1 <= ParamCount) and (ParamStr(I + 1)[1] <> '-') do
      begin
        Inc(I);
        GFilterTags.Add(UpperCase(ParamStr(I)));
      end;
      if GFilterTags.Count = 0 then
        Die('--filter-tags requires at least one tag name (e.g. ERROR, WARNING, INFO)');
    end

    else if S = '--rename-module-dir' then
      GRenameModuleDir := NextArg(I, '--rename-module-dir')

    else if S = '--run' then
    begin
      GRun := True;
      { Consume optional -- then collect remaining words as app arguments }
      if (I + 1 <= ParamCount) and (ParamStr(I + 1) = '--') then
        Inc(I);
      while I + 1 <= ParamCount do
      begin
        Inc(I);
        GRunArgs.Add(ParamStr(I));
      end;
    end

    else if S = '--install' then
      GInstall := True

    else if S = '--bash' then
    begin
      A := NextArg(I, '--bash');
      GBashCword := StrToIntDef(A, 1);
      while I + 1 <= ParamCount do
      begin
        Inc(I);
        GBashWords.Add(ParamStr(I));
      end;
    end

    else
      Die('Unknown argument: ' + S);

    Inc(I);
  end;
end;

{ ---- Field validation ---- }

function ValidateSetField(const AField, AValue: string;
  AProject: TProjectBase; out AMsg: string): Boolean;
begin
  Result := True;
  AMsg   := '';

  if AField = 'project.build.manualUnitPaths' then
  begin
    if (LowerCase(AValue) <> 'true') and (LowerCase(AValue) <> 'false') then
    begin
      AMsg   := 'project.build.manualUnitPaths must be "true" or "false"';
      Result := False;
    end;
    Exit;
  end;

  if AField = 'project.test.framework' then
  begin
    if not ((AValue = 'auto') or (AValue = 'fpcunit') or (AValue = 'fptest') or
            (AValue = '')) then
    begin
      AMsg   := 'project.test.framework must be one of: auto, fpcunit, fptest';
      Result := False;
    end;
    Exit;
  end;

  if AField = 'project.build.packaging' then
  begin
    AMsg   := 'Use pasbuild to change packaging type; direct edits may break the build';
    Result := False;
    Exit;
  end;

  if not (AProject is TProjectPOM) and
     (AField = 'project.name') and (AValue = '') then
  begin
    AMsg   := 'project.name cannot be empty';
    Result := False;
    Exit;
  end;
end;

function IsKnownSetField(const AField: string;
  AProject: TProjectBase): Boolean;
const
  BaseFields: array[0..6] of string = (
    'project.name', 'project.version', 'project.author', 'project.license',
    'project.description', 'project.projectUrl', 'project.repoUrl');
  CommonFields: array[0..8] of string = (
    'project.build.mainSource', 'project.build.executableName',
    'project.build.outputDirectory', 'project.build.sourceDirectory',
    'project.build.manualUnitPaths',
    'project.test.testSource', 'project.test.testSourceDirectory',
    'project.test.framework', 'project.build.packaging');
var
  I: Integer;
  F: string;
begin
  for F in BaseFields do
    if F = AField then Exit(True);
  if AProject is TProjectCommon then
    for F in CommonFields do
      if F = AField then Exit(True);
  Result := False;
end;

{ ---- Mutation application ---- }

function FindProfile(AProject: TProjectBase; const AID: string): TProfile;
var
  I: Integer;
begin
  for I := 0 to AProject.Profiles.Count - 1 do
    if AProject.Profiles[I].ID = AID then
      Exit(AProject.Profiles[I]);
  Result := nil;
end;

function GetFieldValue(AProject: TProjectBase; const AField: string;
  out AValue: string): Boolean;
var
  Common: TProjectCommon;
begin
  Result := True;
  AValue := '';
  if      AField = 'project.name'        then AValue := AProject.Name
  else if AField = 'project.version'     then AValue := AProject.Version
  else if AField = 'project.author'      then AValue := AProject.Author
  else if AField = 'project.license'     then AValue := AProject.License
  else if AField = 'project.description' then AValue := AProject.Description
  else if AField = 'project.projectUrl'  then AValue := AProject.ProjectUrl
  else if AField = 'project.repoUrl'     then AValue := AProject.RepoUrl
  else if AProject is TProjectCommon then
  begin
    Common := TProjectCommon(AProject);
    if      AField = 'project.build.mainSource'         then AValue := Common.MainSource
    else if AField = 'project.build.executableName'     then AValue := Common.ExecutableName
    else if AField = 'project.build.outputDirectory'    then AValue := Common.OutputDirectory
    else if AField = 'project.build.sourceDirectory'    then AValue := Common.SourceDirectory
    else if AField = 'project.build.manualUnitPaths'    then AValue := BoolToStr(Common.ManualUnitPaths, 'true', 'false')
    else if AField = 'project.test.testSource'          then AValue := Common.TestSource
    else if AField = 'project.test.testSourceDirectory' then AValue := Common.TestSourceDirectory
    else if AField = 'project.test.framework'           then AValue := Common.TestFramework
    else Result := False;
  end
  else
    Result := False;
end;

procedure DoGetField(AProject: TProjectBase; const AField: string);
var
  Value: string;
  Obj:   TJSONObject;
begin
  if not GetFieldValue(AProject, AField, Value) then
    Die('Unknown --get field: ' + AField + '. Run --help-fields to see valid fields.', 2);
  if GNoJson then
    WriteLn(Value)
  else
  begin
    Obj := TJSONObject.Create;
    Obj.Add('field', AField);
    Obj.Add('value', Value);
    PrintJSON(Obj);
  end;
end;

procedure DoGetModuleActive(AProject: TProjectBase; const AModulePath: string);
var
  POM: TProjectPOM;
  I:   Integer;
  Obj: TJSONObject;
  Active: Boolean;
begin
  if not (AProject is TProjectPOM) then
    Die('--get-module-active requires a POM project (use --module to select the POM)');
  POM := TProjectPOM(AProject);
  for I := 0 to POM.Modules.Count - 1 do
    if POM.Modules[I].Path = AModulePath then
    begin
      Active := POM.Modules[I].ActiveByDefault;
      if GNoJson then
        WriteLn(BoolToStr(Active, 'true', 'false'))
      else
      begin
        Obj := TJSONObject.Create;
        Obj.Add('module', AModulePath);
        Obj.Add('activeByDefault', Active);
        PrintJSON(Obj);
      end;
      Exit;
    end;
  Die('POM module not found: ' + AModulePath);
end;

procedure ApplySet(AProject: TProjectBase; const AField, AValue: string);
var
  Common: TProjectCommon;
begin
  if AField = 'project.name'        then AProject.Name        := AValue
  else if AField = 'project.version'     then AProject.Version     := AValue
  else if AField = 'project.author'      then AProject.Author      := AValue
  else if AField = 'project.license'     then AProject.License     := AValue
  else if AField = 'project.description' then AProject.Description := AValue
  else if AField = 'project.projectUrl'  then AProject.ProjectUrl  := AValue
  else if AField = 'project.repoUrl'     then AProject.RepoUrl     := AValue
  else if AProject is TProjectCommon then
  begin
    Common := TProjectCommon(AProject);
    if      AField = 'project.build.mainSource'        then Common.MainSource        := AValue
    else if AField = 'project.build.executableName'    then Common.ExecutableName    := AValue
    else if AField = 'project.build.outputDirectory'   then Common.OutputDirectory   := AValue
    else if AField = 'project.build.sourceDirectory'   then Common.SourceDirectory   := AValue
    else if AField = 'project.build.manualUnitPaths'   then Common.ManualUnitPaths   := LowerCase(Trim(AValue)) = 'true'
    else if AField = 'project.test.testSource'         then Common.TestSource        := AValue
    else if AField = 'project.test.testSourceDirectory'then Common.TestSourceDirectory := AValue
    else if AField = 'project.test.framework'          then Common.TestFramework      := AValue
    else
      Die('Unknown --set field: ' + AField + '. Run --help-fields to see valid fields.', 2);
  end
  else
    Die('Unknown --set field: ' + AField + '. Run --help-fields to see valid fields.', 2);
end;

procedure ApplyMutation(AProject: TProjectBase;
  const AM: TMutation; const AProjectFile: string);
var
  Common: TProjectCommon;
  POM: TProjectPOM;
  Profile: TProfile;
  I: Integer;
  Dep: TDependency;
  CP: TConditionalPath;
  ErrMsg: string;
  ModDir: string;
  InitProc: TProcess;
  StatusObj: TJSONObject;
begin
  case AM.Kind of

    mkSet:
    begin
      if not IsKnownSetField(AM.A, AProject) then
        Die('Unknown --set field: ' + AM.A + '. Run --help-fields to see valid fields.', 2);
      if not ValidateSetField(AM.A, AM.B, AProject, ErrMsg) then
        Die(ErrMsg, 2);
      ApplySet(AProject, AM.A, AM.B);
    end;

    mkAddDependency:
    begin
      if not (AProject is TProjectCommon) then
        Die('--add-dependency requires an application or library project');
      Common := TProjectCommon(AProject);
      Common.AddDependency(AM.A, AM.B);
    end;

    mkRemoveDependency:
    begin
      if not (AProject is TProjectCommon) then
        Die('--remove-dependency requires an application or library project');
      Common := TProjectCommon(AProject);
      Dep := nil;
      for I := 0 to Common.Dependencies.Count - 1 do
        if Common.Dependencies[I].Name = AM.A then
        begin
          Dep := Common.Dependencies[I];
          Break;
        end;
      if not Assigned(Dep) then
        Die('Dependency not found: ' + AM.A);
      Common.RemoveDependency(Dep);
    end;

    mkAddModuleDep:
    begin
      if not (AProject is TProjectCommon) then
        Die('--add-module-dependency requires an application or library project');
      TProjectCommon(AProject).AddModuleDependency(AM.A, AM.B);
    end;

    mkRemoveModuleDep:
    begin
      if not (AProject is TProjectCommon) then
        Die('--remove-module-dependency requires an application or library project');
      Common := TProjectCommon(AProject);
      if not Assigned(Common.FindModuleDependency(AM.A)) then
        Die('Module dependency not found: ' + AM.A);
      Common.RemoveModuleDependencyByPath(AM.A);
    end;

    mkAddUnitPath:
    begin
      if not (AProject is TProjectCommon) then
        Die('--add-unit-path requires an application or library project');
      TProjectCommon(AProject).AddUnitPath(AM.A, AM.B);
    end;

    mkRemoveUnitPath:
    begin
      if not (AProject is TProjectCommon) then
        Die('--remove-unit-path requires an application or library project');
      Common := TProjectCommon(AProject);
      CP := nil;
      for I := 0 to Common.UnitPaths.Count - 1 do
        if Common.UnitPaths[I].Path = AM.A then
        begin
          CP := Common.UnitPaths[I];
          Break;
        end;
      if not Assigned(CP) then
        Die('Unit path not found: ' + AM.A);
      Common.RemoveUnitPath(CP);
    end;

    mkAddIncludePath:
    begin
      if not (AProject is TProjectCommon) then
        Die('--add-include-path requires an application or library project');
      TProjectCommon(AProject).AddIncludePath(AM.A, AM.B);
    end;

    mkRemoveIncludePath:
    begin
      if not (AProject is TProjectCommon) then
        Die('--remove-include-path requires an application or library project');
      Common := TProjectCommon(AProject);
      CP := nil;
      for I := 0 to Common.IncludePaths.Count - 1 do
        if Common.IncludePaths[I].Path = AM.A then
        begin
          CP := Common.IncludePaths[I];
          Break;
        end;
      if not Assigned(CP) then
        Die('Include path not found: ' + AM.A);
      Common.RemoveIncludePath(CP);
    end;

    mkAddDefine:
    begin
      if not (AProject is TProjectCommon) then
        Die('--add-define requires an application or library project');
      TProjectCommon(AProject).Defines.Add(AM.A);
    end;

    mkRemoveDefine:
    begin
      if not (AProject is TProjectCommon) then
        Die('--remove-define requires an application or library project');
      Common := TProjectCommon(AProject);
      I := Common.Defines.IndexOf(AM.A);
      if I < 0 then
        Die('Define not found: ' + AM.A);
      Common.Defines.Delete(I);
    end;

    mkAddCompilerOption:
    begin
      if not (AProject is TProjectCommon) then
        Die('--add-compiler-option requires an application or library project');
      TProjectCommon(AProject).CompilerOptions.Add(AM.A);
    end;

    mkRemoveCompilerOption:
    begin
      if not (AProject is TProjectCommon) then
        Die('--remove-compiler-option requires an application or library project');
      Common := TProjectCommon(AProject);
      I := Common.CompilerOptions.IndexOf(AM.A);
      if I < 0 then
        Die('Compiler option not found: ' + AM.A);
      Common.CompilerOptions.Delete(I);
    end;

    mkAddBootstrapExclude:
    begin
      if not (AProject is TProjectCommon) then
        Die('--add-bootstrap-exclude requires an application or library project');
      TProjectCommon(AProject).BootstrapExclude.Add(AM.A);
    end;

    mkRemoveBootstrapExclude:
    begin
      if not (AProject is TProjectCommon) then
        Die('--remove-bootstrap-exclude requires an application or library project');
      Common := TProjectCommon(AProject);
      I := Common.BootstrapExclude.IndexOf(AM.A);
      if I < 0 then
        Die('Bootstrap exclude not found: ' + AM.A);
      Common.BootstrapExclude.Delete(I);
    end;

    mkAddProfile:
    begin
      if Assigned(FindProfile(AProject, AM.A)) then
        Die('Profile already exists: ' + AM.A);
      Profile    := AProject.AddProfile;
      Profile.ID := AM.A;
    end;

    mkRemoveProfile:
    begin
      Profile := FindProfile(AProject, AM.A);
      if not Assigned(Profile) then
        Die('Profile not found: ' + AM.A);
      AProject.RemoveProfile(Profile);
    end;

    mkAddProfileDefine:
    begin
      Profile := FindProfile(AProject, AM.A);
      if not Assigned(Profile) then
        Die('Profile not found: ' + AM.A);
      Profile.Defines.Add(AM.B);
    end;

    mkRemoveProfileDefine:
    begin
      Profile := FindProfile(AProject, AM.A);
      if not Assigned(Profile) then
        Die('Profile not found: ' + AM.A);
      I := Profile.Defines.IndexOf(AM.B);
      if I < 0 then
        Die('Define "' + AM.B + '" not found in profile "' + AM.A + '"');
      Profile.Defines.Delete(I);
    end;

    mkAddProfileOption:
    begin
      Profile := FindProfile(AProject, AM.A);
      if not Assigned(Profile) then
        Die('Profile not found: ' + AM.A);
      Profile.CompilerOptions.Add(AM.B);
    end;

    mkRemoveProfileOption:
    begin
      Profile := FindProfile(AProject, AM.A);
      if not Assigned(Profile) then
        Die('Profile not found: ' + AM.A);
      I := Profile.CompilerOptions.IndexOf(AM.B);
      if I < 0 then
        Die('Compiler option "' + AM.B + '" not found in profile "' + AM.A + '"');
      Profile.CompilerOptions.Delete(I);
    end;

    mkAddPOMModule:
    begin
      if not (AProject is TProjectPOM) then
        Die('--add-pom-module requires a POM project');
      POM := TProjectPOM(AProject);
      POM.AddModule(AM.A, AM.B = 'true');
    end;

    mkRemovePOMModule:
    begin
      if not (AProject is TProjectPOM) then
        Die('--remove-pom-module requires a POM project');
      POM := TProjectPOM(AProject);
      for I := 0 to POM.Modules.Count - 1 do
        if POM.Modules[I].Path = AM.A then
        begin
          POM.RemoveModule(POM.Modules[I]);
          Exit;
        end;
      Die('POM module not found: ' + AM.A);
    end;

    mkSetModuleActive:
    begin
      if not (AProject is TProjectPOM) then
        Die('--set-module-active requires a POM project (use --module to select the POM)');
      POM := TProjectPOM(AProject);
      for I := 0 to POM.Modules.Count - 1 do
        if POM.Modules[I].Path = AM.A then
        begin
          POM.Modules[I].ActiveByDefault := LowerCase(AM.B) = 'true';
          Exit;
        end;
      Die('POM module not found: ' + AM.A);
    end;

    mkInitNewModule:
    begin
      if not (AProject is TProjectPOM) then
        Die('--add-new-module requires a POM project (use --module to select the POM)');
      POM    := TProjectPOM(AProject);
      ModDir := ExpandFileName(
        IncludeTrailingPathDelimiter(ExtractFilePath(AProjectFile)) + AM.A);

      if not DirectoryExists(ModDir) then
        if not ForceDirectories(ModDir) then
          Die('Could not create directory: ' + ModDir);

      { Status to stderr so JSON stdout is clean }
      StatusObj := TJSONObject.Create;
      StatusObj.Add('status', 'running pasbuild init');
      StatusObj.Add('path', ModDir);
      PrintJSONErr(StatusObj);

      InitProc := TProcess.Create(nil);
      try
        InitProc.Executable      := 'pasbuild';
        InitProc.Parameters.Add('init');
        InitProc.CurrentDirectory := ModDir;
        { No pipes — user interacts with pasbuild init via the terminal }
        InitProc.Options := [poWaitOnExit];
        try
          InitProc.Execute;
          if InitProc.ExitCode <> 0 then
            Die('pasbuild init failed with exit code ' +
              IntToStr(InitProc.ExitCode));
        except
          on E: Exception do
            Die('Failed to run pasbuild init: ' + E.Message);
        end;
      finally
        InitProc.Free;
      end;

      if not FileExists(IncludeTrailingPathDelimiter(ModDir) + 'project.xml') then
        Die('pasbuild init did not create project.xml in ' + ModDir);

      POM.AddModule(AM.A, True);

      StatusObj := TJSONObject.Create;
      StatusObj.Add('status', 'module created');
      StatusObj.Add('path', AM.A);
      PrintJSONErr(StatusObj);
    end;

  end;
end;

{ ---- Platform helpers ---- }

{ Return the pasbuild user data root directory.
  Mirrors PasBuild.Plugin / PasBuild.Repository — all platforms use
  GetUserDir + '.pasbuild', which resolves to:
    Linux   : /home/<user>/.pasbuild/
    macOS   : /Users/<user>/.pasbuild/
    Windows : C:\Users\<user>\.pasbuild\
              (pasbuild deliberately uses the home dir, not %APPDATA%, so that
               the same layout works across all three platforms)
  On Windows the leading dot makes no difference — the folder is not hidden. }
function GetPasbuildUserDir: string;
begin
  Result := IncludeTrailingPathDelimiter(GetUserDir) + '.pasbuild';
end;

function GetPasbuildUserPluginsDir: string;
begin
  Result := IncludeTrailingPathDelimiter(GetPasbuildUserDir) + 'plugins';
end;

{ Return the platform executable suffix ('exe' on Windows, '' elsewhere). }
function ExeSuffix: string;
begin
  {$IFDEF WINDOWS}
  Result := '.exe';
  {$ELSE}
  Result := '';
  {$ENDIF}
end;

{ ---- Plugin discovery (mirrors PasBuild.Plugin.TPluginDiscovery) ---- }

{ Scan ADir for executables named pasbuild-*.  Strips the prefix and appends
  goal names to AList.  Duplicates are silently ignored (AList must have
  Duplicates=dupIgnore and Sorted=True). }
procedure ScanPluginDir(const ADir: string; AList: TStringList);
const
  Prefix = 'pasbuild-';
var
  SR: TSearchRec;
  Name: string;
begin
  if not DirectoryExists(ADir) then Exit;
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + Prefix + '*',
               faAnyFile and not faDirectory, SR) = 0 then
  begin
    try
      repeat
        Name := SR.Name;
        Delete(Name, 1, Length(Prefix));
        if (ExeSuffix <> '') and
           (Length(Name) > Length(ExeSuffix)) and
           (CompareText(Copy(Name, Length(Name) - Length(ExeSuffix) + 1, Length(ExeSuffix)), ExeSuffix) = 0) then
          Delete(Name, Length(Name) - Length(ExeSuffix) + 1, Length(ExeSuffix));
        if Name <> '' then
          AList.Add(Name);
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;
end;

{ Run <exe> --pasbuild-phase and return the raw trimmed output, or '' on error. }
function QueryPluginPhase(const AExe: string): string;
var
  P: TProcess;
  Buf: array[0..4095] of Char;
  N: Integer;
  Out: string;
begin
  Result := '';
  P := TProcess.Create(nil);
  try
    P.Executable := AExe;
    P.Parameters.Add('--pasbuild-phase');
    P.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
    try
      P.Execute;
      Out := '';
      repeat
        N := P.Output.Read(Buf[0], SizeOf(Buf) - 1);
        if N > 0 then
        begin
          Buf[N] := #0;
          Out := Out + string(Buf);
        end;
      until N = 0;
      P.WaitOnExit;
      if P.ExitCode = 0 then
        Result := Trim(Out);
    except
    end;
  finally
    P.Free;
  end;
end;

{ Find the full path to a plugin executable by goal name, or '' if not found.
  Search order matches pasbuild: AProjectPluginsDir -> ~/.pasbuild/plugins/ }
function FindPluginExe(const AGoalName, AProjectPluginsDir: string): string;
const
  Prefix = 'pasbuild-';
var
  ExeName: string;
  Candidate: string;
begin
  Result  := '';
  ExeName := Prefix + AGoalName + ExeSuffix;

  Candidate := IncludeTrailingPathDelimiter(AProjectPluginsDir) + ExeName;
  if FileExists(Candidate) then Exit(Candidate);

  Candidate := IncludeTrailingPathDelimiter(GetPasbuildUserPluginsDir) + ExeName;
  if FileExists(Candidate) then Exit(Candidate);
end;

{ ---- List-goals ---- }

{ AProjectRootDir: root POM directory (project-wide plugins/).
  AModuleDir:      selected module directory, or '' if none selected.
  AModuleName:     name label for module-specific annotation. }
procedure DoListGoals(const AProjectRootDir, AModuleDir, AModuleName: string);
var
  Obj: TJSONObject;
  BuiltinArr, PluginArr: TJSONArray;
  Item: TJSONObject;
  I: Integer;
  UserPluginDir, RootPluginDir, ModulePluginDir: string;
  AllGoals: TStringList;         // deduplicated set of discovered goal names
  RootGoals, UserGoals, ModGoals: TStringList;
  Phase, ExePath: string;
  IsModuleOnly: Boolean;
begin
  Obj := TJSONObject.Create;

  { Built-in goals }
  BuiltinArr := TJSONArray.Create;
  for I := Low(KnownGoals) to High(KnownGoals) do
  begin
    Item := TJSONObject.Create;
    Item.Add('goal',        KnownGoals[I]);
    Item.Add('description', KnownGoalDescs[I]);
    BuiltinArr.Add(Item);
  end;
  Obj.Add('builtinGoals', BuiltinArr);

  { Scan the three plugin locations that pasbuild itself uses }
  RootPluginDir   := IncludeTrailingPathDelimiter(AProjectRootDir) + 'plugins';
  UserPluginDir   := IncludeTrailingPathDelimiter(GetUserDir) +
                     '.pasbuild' + PathDelim + 'plugins';
  ModulePluginDir := '';
  if AModuleDir <> '' then
    ModulePluginDir := IncludeTrailingPathDelimiter(AModuleDir) + 'plugins';

  RootGoals := TStringList.Create;
  RootGoals.Sorted := True;
  RootGoals.Duplicates := dupIgnore;

  UserGoals := TStringList.Create;
  UserGoals.Sorted := True;
  UserGoals.Duplicates := dupIgnore;

  ModGoals := TStringList.Create;
  ModGoals.Sorted := True;
  ModGoals.Duplicates := dupIgnore;

  AllGoals := TStringList.Create;
  AllGoals.Sorted := True;
  AllGoals.Duplicates := dupIgnore;

  try
    ScanPluginDir(RootPluginDir,   RootGoals);
    ScanPluginDir(UserPluginDir,   UserGoals);
    if ModulePluginDir <> '' then
      ScanPluginDir(ModulePluginDir, ModGoals);

    for I := 0 to RootGoals.Count - 1 do AllGoals.Add(RootGoals[I]);
    for I := 0 to UserGoals.Count - 1 do AllGoals.Add(UserGoals[I]);
    for I := 0 to ModGoals.Count - 1 do AllGoals.Add(ModGoals[I]);

    PluginArr := TJSONArray.Create;
    for I := 0 to AllGoals.Count - 1 do
    begin
      { Determine where this plugin lives (module > root > user priority) }
      IsModuleOnly := (ModGoals.IndexOf(AllGoals[I]) >= 0) and
                      (RootGoals.IndexOf(AllGoals[I]) < 0) and
                      (UserGoals.IndexOf(AllGoals[I]) < 0);

      { Resolve the exe so we can query --pasbuild-phase }
      ExePath := FindPluginExe(AllGoals[I],
        IfThen(IsModuleOnly, ModulePluginDir, RootPluginDir));
      if ExePath = '' then
        ExePath := FindPluginExe(AllGoals[I], UserPluginDir);

      Phase := '';
      if ExePath <> '' then
        Phase := QueryPluginPhase(ExePath);

      Item := TJSONObject.Create;
      Item.Add('goal', AllGoals[I]);

      { Annotate scope }
      if IsModuleOnly then
      begin
        Item.Add('scope', 'module');
        if AModuleName <> '' then
          Item.Add('module', AModuleName);
        Item.Add('description',
          'Module-specific plugin (only available for module "' +
          AModuleName + '")');
      end
      else if UserGoals.IndexOf(AllGoals[I]) >= 0 then
      begin
        Item.Add('scope', 'user');
        Item.Add('description', 'User-global plugin (~/.pasbuild/plugins/)');
      end
      else
      begin
        Item.Add('scope', 'project');
        Item.Add('description', 'Project-wide plugin (plugins/ in project root)');
      end;

      { Phase: when the plugin runs relative to other goals }
      if Phase = '' then
        Item.Add('phase', TJSONNull.Create)
      else if LowerCase(Phase) = 'none' then
        Item.Add('phase', 'standalone')
      else
      begin
        { Strip leading "after:" if present }
        if Pos('after:', LowerCase(Phase)) = 1 then
          Delete(Phase, 1, Length('after:'));
        Item.Add('phase', 'after:' + Phase);
      end;

      PluginArr.Add(Item);
    end;

    Obj.Add('plugins', PluginArr);
  finally
    AllGoals.Free;
    ModGoals.Free;
    UserGoals.Free;
    RootGoals.Free;
  end;

  PrintJSON(Obj);
end;

{ ---- Execute goals ---- }

{ Parse a [TAG] prefix from a pasbuild output line.
  Returns the tag (uppercased, without brackets) or '' if none found. }
function ParseTag(const ALine: string): string;
var
  Close: Integer;
begin
  Result := '';
  if (Length(ALine) < 3) or (ALine[1] <> '[') then Exit;
  Close := Pos(']', ALine);
  if Close < 3 then Exit;
  Result := UpperCase(Copy(ALine, 2, Close - 2));
end;

{ True for [INFO] lines that are pure dash separators, e.g.
  "[INFO] ------------------------------------------------------------------------"
  These are visual noise in JSON output — the structure already groups things. }
function IsSeparatorLine(const ALine: string): Boolean;
var
  Close, K: Integer;
  Rest: string;
begin
  Result := False;
  if ParseTag(ALine) <> 'INFO' then Exit;
  Close := Pos(']', ALine);
  Rest  := TrimLeft(Copy(ALine, Close + 1, MaxInt));
  if Length(Rest) = 0 then Exit;
  for K := 1 to Length(Rest) do
    if Rest[K] <> '-' then Exit;
  Result := True;
end;

{ True if ATag is in the filter list (or no filter set = accept all). }
function TagAccepted(const ATag: string): Boolean;
begin
  if GFilterTags.Count = 0 then
    Result := True
  else
    Result := GFilterTags.IndexOf(ATag) >= 0;
end;

{ Return the name of the goal that produced line ALineIdx, given the start-
  index table built during the goal loop.  AGoalStartLine[I] is the first
  Lines index that belongs to goal AGoalNames[I]. }
function GoalForLine(ALineIdx: Integer;
                     const AGoalStartLine: array of Integer;
                     AGoalNames: TStringList): string;
var
  I: Integer;
begin
  Result := '';
  for I := High(AGoalStartLine) downto 0 do
    if ALineIdx >= AGoalStartLine[I] then
    begin
      Result := AGoalNames[I];
      Exit;
    end;
end;

{ Run pasbuild for a single goal, append its combined stdout+stderr output to
  ALines, and return the exit code.  If GTimeout is set and elapsed, sets
  ATimedOut to True, terminates the process, and returns 1.
  Stdin is forwarded from our own stdin so interactive goals can prompt the user. }
function RunGoalCaptured(const AGoal, ARootDir: string;
                         ALines: TStringList;
                         var ATimedOut: Boolean): Integer;
var
  Proc: TProcess;
  Buf: array[0..4095] of Char;
  N: Integer;
  Raw: string;
  StartTick, NowTick: QWord;
  {$IFDEF UNIX}
  FDS: TFDSet;
  TV:  TimeVal;
  {$ENDIF}
begin
  Result := 0;
  Proc   := TProcess.Create(nil);
  Raw    := '';
  try
    Proc.Executable := 'pasbuild';
    Proc.Parameters.Add(AGoal);
    if GModuleName <> '' then
    begin
      Proc.Parameters.Add('-m');
      Proc.Parameters.Add(GModuleName);
    end;
    if GProfile <> '' then
    begin
      Proc.Parameters.Add('-p');
      Proc.Parameters.Add(GProfile);
    end;
    if GVerbose  then Proc.Parameters.Add('-v');
    if GBuildAll then Proc.Parameters.Add('--all');
    if GCompiler <> '' then
    begin
      Proc.Parameters.Add('--compiler');
      Proc.Parameters.Add(GCompiler);
    end;
    Proc.CurrentDirectory := ARootDir;
    { Keep poUsePipes so we can capture stdout/stderr, but do NOT set
      poNoConsole — that would cut off stdin, breaking interactive goals.
      We forward our own stdin to the process manually in the poll loop. }
    Proc.Options := [poUsePipes, poStderrToOutPut];
    try
      Proc.Execute;
    except
      on E: Exception do
        Die('Failed to run pasbuild: ' + E.Message);
    end;

    StartTick := GetTickCount64;
    repeat
      { Forward stdin so interactive goals can prompt the user.
        select() with zero timeout means we never block here. }
      {$IFDEF UNIX}
      fpFD_ZERO(FDS);
      fpFD_SET(0, FDS);
      TV.tv_sec  := 0;
      TV.tv_usec := 0;
      if fpSelect(1, @FDS, nil, nil, @TV) > 0 then
      begin
        N := FileRead(0, Buf[0], SizeOf(Buf));
        if N > 0 then
          Proc.Input.Write(Buf[0], N)
        else if N = 0 then
          Proc.CloseInput;
      end;
      {$ENDIF}

      while Proc.Output.NumBytesAvailable > 0 do
      begin
        N := Proc.Output.Read(Buf[0], Min(SizeOf(Buf) - 1, Proc.Output.NumBytesAvailable));
        if N > 0 then
        begin
          Buf[N] := #0;
          Raw := Raw + string(Buf);
        end;
      end;
      if GTimeout > 0 then
      begin
        NowTick := GetTickCount64;
        if NowTick - StartTick > QWord(GTimeout) * 1000 then
        begin
          ATimedOut := True;
          Proc.Terminate(1);
          Break;
        end;
      end;
      if Proc.Running then Sleep(20);
    until not Proc.Running and (Proc.Output.NumBytesAvailable = 0);

    { Drain any final bytes }
    while Proc.Output.NumBytesAvailable > 0 do
    begin
      N := Proc.Output.Read(Buf[0], Min(SizeOf(Buf) - 1, Proc.Output.NumBytesAvailable));
      if N > 0 then
      begin
        Buf[N] := #0;
        Raw := Raw + string(Buf);
      end;
    end;
    Proc.WaitOnExit;
    Result := Proc.ExitCode;
  finally
    Proc.Free;
  end;
  { Append this goal's output to the shared accumulator }
  ALines.Text := ALines.Text + Raw;
end;

procedure DoExecuteGoals(const ARootDir: string);
var
  Proc: TProcess;          // used only in raw (--no-json) mode
  N, I: Integer;
  Lines: TStringList;      // all output lines accumulated across goal runs
  SummaryStart: Integer;   // index of first line in reactor summary block
  TimedOut: Boolean;
  Tag, LineText: string;
  { JSON mode accumulators }
  OutObj, LineObj: TJSONObject;
  LinesArr, ErrorsArr, WarningsArr: TJSONArray;
  TagCounts: TStringList;   // tag name -> count (as string)
  SuppressedTagsArr: TJSONArray;
  SuppressedObj: TJSONObject;
  TagIdx, TagCount: Integer;
  ContextStart, ContextEnd, J: Integer;
  EmittedLines: array of Boolean;
  GoalExitCode: Integer;   // exit code of the most recently run goal
  FailedGoalIdx: Integer;  // index into GExecuteGoals of the failed goal, or -1
  SkippedArr: TJSONArray;
  GoalStartLine: array of Integer; // Lines index where each goal's output begins
begin
  if GNoJson then
  begin
    { Raw mode: just exec pasbuild and let it write to stdout/stderr directly.
      We can't do timeout in this mode without a background thread, so we warn. }
    Proc := TProcess.Create(nil);
    try
      Proc.Executable := 'pasbuild';
      for I := 0 to GExecuteGoals.Count - 1 do
        Proc.Parameters.Add(GExecuteGoals[I]);
      if GModuleName <> '' then
      begin
        Proc.Parameters.Add('-m');
        Proc.Parameters.Add(GModuleName);
      end;
      if GProfile <> '' then
      begin
        Proc.Parameters.Add('-p');
        Proc.Parameters.Add(GProfile);
      end;
      if GVerbose then
        Proc.Parameters.Add('-v');
      if GBuildAll then
        Proc.Parameters.Add('--all');
      if GCompiler <> '' then
      begin
        Proc.Parameters.Add('--compiler');
        Proc.Parameters.Add(GCompiler);
      end;
      Proc.CurrentDirectory := ARootDir;
      Proc.Options := [poWaitOnExit];
      try
        Proc.Execute;
        Halt(Proc.ExitCode);
      except
        on E: Exception do
          Die('Failed to run pasbuild: ' + E.Message);
      end;
    finally
      Proc.Free;
    end;
  end;

  { JSON mode: run goals one at a time (via RunGoalCaptured above) so we can
    stop on the first failure rather than letting pasbuild decide.
    Output from all runs is merged into Lines for filtering/structuring. }
  Proc  := nil;
  Lines := TStringList.Create;

  TimedOut  := False;

  { Run goals one by one; stop as soon as one fails so later goals
    in the queue are not executed unnecessarily. }
  GoalExitCode := 0;
  FailedGoalIdx := -1;
  SetLength(GoalStartLine, GExecuteGoals.Count);
  for I := 0 to GExecuteGoals.Count - 1 do
  begin
    GoalStartLine[I] := Lines.Count;   { record where this goal's output starts }
    GoalExitCode := RunGoalCaptured(GExecuteGoals[I], ARootDir, Lines, TimedOut);
    if (GoalExitCode <> 0) or TimedOut then
    begin
      FailedGoalIdx := I;
      Break;
    end;
  end;

  try
    { Find reactor summary block: locate "Reactor Summary:" line and include
      the separator before it.  Falls back to the last separator if not found. }
    SummaryStart := -1;
    for I := 0 to Lines.Count - 1 do
      if Pos('Reactor Summary:', Lines[I]) > 0 then
      begin
        { Include the separator line that precedes Reactor Summary: }
        SummaryStart := Max(0, I - 1);
        Break;
      end;
    if SummaryStart < 0 then
      { Fallback: last separator line }
      for I := Lines.Count - 1 downto 0 do
        if Pos('---', Lines[I]) > 0 then
        begin
          SummaryStart := I;
          Break;
        end;

    { Build the output JSON }
    OutObj := TJSONObject.Create;
    if GAllModules then
      OutObj.Add('module', '*')
    else
      OutObj.Add('module', GModuleName);
    OutObj.Add('goals',    TJSONArray.Create);
    for I := 0 to GExecuteGoals.Count - 1 do
      (OutObj.Arrays['goals'] as TJSONArray).Add(GExecuteGoals[I]);
    if GProfile <> '' then
      OutObj.Add('profile', GProfile);
    OutObj.Add('exitCode', GoalExitCode);
    OutObj.Add('success',  (GoalExitCode = 0) and not TimedOut);
    if TimedOut then
      OutObj.Add('timedOut', True);
    { If a goal failed, report which one and list the goals that were skipped
      as a result — they never ran so their output is absent from the results. }
    if FailedGoalIdx >= 0 then
    begin
      OutObj.Add('failedGoal', GExecuteGoals[FailedGoalIdx]);
      if FailedGoalIdx < GExecuteGoals.Count - 1 then
      begin
        SkippedArr := TJSONArray.Create;
        for J := FailedGoalIdx + 1 to GExecuteGoals.Count - 1 do
          SkippedArr.Add(GExecuteGoals[J]);
        OutObj.Add('skippedGoals', SkippedArr);
      end;
    end;

    ErrorsArr   := TJSONArray.Create;
    WarningsArr := TJSONArray.Create;
    LinesArr    := TJSONArray.Create;
    TagCounts   := TStringList.Create;
    TagCounts.Sorted    := True;
    TagCounts.Duplicates := dupIgnore;

    { Mark which lines are emitted (for error-context expansion) }
    SetLength(EmittedLines, Lines.Count);
    for I := 0 to Lines.Count - 1 do
      EmittedLines[I] := False;

    { First pass: count all tags seen and decide which lines to include }
    for I := 0 to Lines.Count - 1 do
    begin
      LineText := Lines[I];
      Tag := ParseTag(LineText);
      if Tag = '' then Tag := 'RAW';

      { Drop [INFO] lines that are pure visual formatting: separator rows of
        dashes and blank [INFO] lines (e.g. "[INFO] " with nothing after). }
      if IsSeparatorLine(LineText) then Continue;
      if (Tag = 'INFO') and (Trim(Copy(LineText, Pos(']', LineText) + 1, MaxInt)) = '') then Continue;

      { Count every tag seen }
      if Tag <> '' then
      begin
        TagIdx := TagCounts.IndexOf(Tag);
        if TagIdx < 0 then
          TagCounts.AddObject(Tag, TObject(PtrInt(1)))
        else
          TagCounts.Objects[TagIdx] := TObject(PtrInt(TagCounts.Objects[TagIdx]) + 1);
      end;

      if GShowSummary then
      begin
        if (SummaryStart >= 0) and (I >= SummaryStart) then
          EmittedLines[I] := TagAccepted(Tag);
      end
      else
        EmittedLines[I] := TagAccepted(Tag);

      { Collect errors and warnings as objects so we can record which goal
        produced them — useful when multiple goals ran before the failure. }
      if (Tag = 'ERROR') or (Tag = 'WARNING') then
      begin
        LineObj := TJSONObject.Create;
        LineObj.Add('goal', GoalForLine(I, GoalStartLine, GExecuteGoals));
        LineObj.Add('text', Trim(LineText));
        if Tag = 'ERROR' then
          ErrorsArr.Add(LineObj)
        else
          WarningsArr.Add(LineObj);
        LineObj := nil;  { ownership transferred to array }
      end;
    end;

    { Expand error-context: mark N lines around each ERROR line }
    if GErrorContext > 0 then
      for I := 0 to Lines.Count - 1 do
        if ParseTag(Lines[I]) = 'ERROR' then
        begin
          ContextStart := Max(0, I - GErrorContext);
          ContextEnd   := Min(Lines.Count - 1, I + GErrorContext);
          for J := ContextStart to ContextEnd do
            EmittedLines[J] := True;
        end;

    { Build lines array from marked lines }
    for I := 0 to Lines.Count - 1 do
      if EmittedLines[I] then
      begin
        LineText := Lines[I];
        Tag      := ParseTag(LineText);
        if Tag = '' then Tag := 'RAW';
        LineObj  := TJSONObject.Create;
        LineObj.Add('goal', GoalForLine(I, GoalStartLine, GExecuteGoals));
        LineObj.Add('tag',  Tag);
        LineObj.Add('text', Trim(LineText));
        LinesArr.Add(LineObj);
      end;

    OutObj.Add('lines',    LinesArr);
    OutObj.Add('errors',   ErrorsArr);
    OutObj.Add('warnings', WarningsArr);

    { Report any tags that appeared in the output but were suppressed by the
      current filter (or by --show-summary).  Lets callers know what extra
      information is available without re-running with a wider filter. }
    SuppressedTagsArr := TJSONArray.Create;
    for I := 0 to TagCounts.Count - 1 do
    begin
      Tag      := TagCounts[I];
      TagCount := PtrInt(TagCounts.Objects[I]);

      { ERROR and WARNING lines are always surfaced in the dedicated
        "errors" and "warnings" arrays, so they are never truly suppressed
        from the consumer — don't report them here regardless of filter mode. }
      if (Tag = 'ERROR') or (Tag = 'WARNING') then Continue;

      if GFilterTags.Count > 0 then
      begin
        { Only report tags that were filtered out of the lines array }
        if GFilterTags.IndexOf(Tag) < 0 then
        begin
          SuppressedObj := TJSONObject.Create;
          SuppressedObj.Add('tag',   Tag);
          SuppressedObj.Add('count', TagCount);
          SuppressedTagsArr.Add(SuppressedObj);
        end;
      end
      else if GShowSummary then
      begin
        { In summary-only mode, report tags whose lines didn't make the cut }
        SuppressedObj := TJSONObject.Create;
        SuppressedObj.Add('tag',   Tag);
        SuppressedObj.Add('count', TagCount);
        SuppressedTagsArr.Add(SuppressedObj);
      end;
    end;
    TagCounts.Free;
    if SuppressedTagsArr.Count > 0 then
      OutObj.Add('suppressedTags', SuppressedTagsArr)
    else
      SuppressedTagsArr.Free;

    PrintJSON(OutObj);

    Halt(GoalExitCode);
  finally
    Lines.Free;
  end;
end;

{ ---- Run application ---- }

procedure DoRunApp(AProject: TProjectBase; const AProjectFile: string);
var
  App: TProjectApplication;
  ModuleDir, ExePath: string;
{$IFDEF UNIX}
  Argv: array of PAnsiChar;
  I: Integer;
{$ELSE}
  Proc: TProcess;
  ExitCode: Integer;
  I: Integer;
{$ENDIF}
begin
  if not (AProject is TProjectApplication) then
    Die('--run requires an application project (this module is a ' +
        AProject.ProjectTypeLabel + ')');

  App       := TProjectApplication(AProject);
  ModuleDir := ExcludeTrailingPathDelimiter(ExtractFilePath(AProjectFile));
  ExePath   := IncludeTrailingPathDelimiter(ModuleDir) +
               IncludeTrailingPathDelimiter(App.OutputDirectory) +
               App.ExecutableName + ExeSuffix;

  if not FileExists(ExePath) then
    Die('Executable not found: ' + ExePath +
        '  (run --execute-goals compile first)');

  { Change to the module directory so the app sees it as its working directory }
  if not SetCurrentDir(ModuleDir) then
    Die('Failed to change directory to: ' + ModuleDir);

{$IFDEF UNIX}
  { On Unix, replace this process with the app via execv — no polling,
    true terminal inheritance, exit code forwarded by the shell naturally. }
  SetLength(Argv, GRunArgs.Count + 2);
  Argv[0] := PAnsiChar(AnsiString(ExePath));
  for I := 0 to GRunArgs.Count - 1 do
    Argv[I + 1] := PAnsiChar(AnsiString(GRunArgs[I]));
  Argv[High(Argv)] := nil;
  FpExecv(ExePath, @Argv[0]);
  { If we get here execv failed }
  Die('Failed to execute: ' + ExePath);
{$ELSE}
  Proc := TProcess.Create(nil);
  try
    Proc.Executable := ExePath;
    Proc.Options    := [];
    for I := 0 to GRunArgs.Count - 1 do
      Proc.Parameters.Add(GRunArgs[I]);
    Proc.Execute;
    while Proc.Running do
      Sleep(50);
    ExitCode := Proc.ExitCode;
  finally
    Proc.Free;
  end;
  Halt(ExitCode);
{$ENDIF}
end;

{ ---- Rename module directory ---- }

{ Rename the module's directory on disk and update all project.xml files that
  reference it — the root POM's <modules> list and every sibling module's
  <moduleDependencies> list. }
procedure DoRenameModuleDir(ATree: TProjectTree;
  const AOldName, ANewName, AProjectFile: string);
var
  OldDir, NewDir, ParentDir: string;
  Entry: TModuleEntry;
  FoundEntry: TModuleEntry;
  POM: TProjectPOM;
  Proj: TProjectBase;
  Common: TProjectCommon;
  CP: TConditionalPath;
  I: Integer;
  OldRef, NewRef: string;
  ChangedFiles: TStringList;
  OutObj: TJSONObject;
  Arr: TJSONArray;
begin
  { Locate the module entry so we know its absolute directory }
  FoundEntry := nil;
  for I := 0 to ATree.Modules.Count - 1 do
  begin
    Entry := ATree.Modules[I];
    if SameText(Entry.PathComponent, AOldName) or
       SameText(Entry.ProjectName,   AOldName) then
    begin
      FoundEntry := Entry;
      Break;
    end;
  end;
  if FoundEntry = nil then
    Die('--rename-module-dir: module not found in reactor: ' + AOldName);

  OldDir    := ExcludeTrailingPathDelimiter(FoundEntry.ModuleDir);
  ParentDir := ExtractFilePath(OldDir);
  NewDir    := ParentDir + ANewName;

  if DirectoryExists(NewDir) then
    Die('--rename-module-dir: target directory already exists: ' + NewDir);

  ChangedFiles := TStringList.Create;
  try
    { 1. Rename the directory on disk }
    if not RenameFile(OldDir, NewDir) then
      Die('--rename-module-dir: failed to rename ' + OldDir + ' to ' + NewDir);
    ChangedFiles.Add(NewDir);

    { 2. Update the root POM's <modules> list }
    POM := TProjectBase.LoadFromFile(ATree.RootPOMFile) as TProjectPOM;
    try
      for I := 0 to POM.Modules.Count - 1 do
        if SameText(POM.Modules[I].Path, AOldName) then
        begin
          POM.Modules[I].Path := ANewName;
          Break;
        end;
      POM.SaveToFile;
      ChangedFiles.Add(ATree.RootPOMFile);
    finally
      POM.Free;
    end;

    { 3. Update moduleDependencies in every sibling module's project.xml.
         References use the form "../old-name" — relative from a sibling dir. }
    OldRef := '../' + AOldName;
    NewRef := '../' + ANewName;
    for I := 0 to ATree.Modules.Count - 1 do
    begin
      Entry := ATree.Modules[I];
      if SameText(Entry.PathComponent, AOldName) then
        Continue;  // skip the renamed module itself
      if not FileExists(Entry.ProjectFile) then
        Continue;
      Proj := TProjectBase.LoadFromFile(Entry.ProjectFile);
      try
        if Proj is TProjectCommon then
        begin
          Common := TProjectCommon(Proj);
          CP := Common.FindModuleDependency(OldRef);
          if Assigned(CP) then
          begin
            CP.Path := NewRef;
            Proj.SaveToFile;
            ChangedFiles.Add(Entry.ProjectFile);
          end;
        end;
      finally
        Proj.Free;
      end;
    end;

    OutObj := TJSONObject.Create;
    OutObj.Add('renamed', True);
    OutObj.Add('oldName', AOldName);
    OutObj.Add('newName', ANewName);
    OutObj.Add('oldDir',  OldDir);
    OutObj.Add('newDir',  NewDir);
    Arr := TJSONArray.Create;
    for I := 0 to ChangedFiles.Count - 1 do
      Arr.Add(ChangedFiles[I]);
    OutObj.Add('updatedFiles', Arr);
    PrintJSON(OutObj);

  finally
    ChangedFiles.Free;
  end;
end;

{ ---- List-modules output ---- }

procedure DoListModules(ATree: TProjectTree);
var
  Obj: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  E: TModuleEntry;
  Item: TJSONObject;
begin
  Obj := TJSONObject.Create;
  Obj.Add('rootPOM', ATree.RootPOMFile);
  Arr := TJSONArray.Create;
  for I := 0 to ATree.Modules.Count - 1 do
  begin
    E    := ATree.Modules[I];
    Item := TJSONObject.Create;
    Item.Add('path', E.PathComponent);
    Item.Add('projectName', E.ProjectName);
    Item.Add('projectFile', E.ProjectFile);
    Arr.Add(Item);
  end;
  Obj.Add('modules', Arr);
  PrintJSON(Obj);
end;

procedure DoListCompilers;
var
  Obj: TJSONObject;
  Arr: TJSONArray;
  Item: TJSONObject;
  I: Integer;
begin
  Obj := TJSONObject.Create;
  Arr := TJSONArray.Create;
  for I := Low(KnownCompilers) to High(KnownCompilers) do
  begin
    Item := TJSONObject.Create;
    Item.Add('name', KnownCompilers[I]);
    Item.Add('description', KnownCompilerDescs[I]);
    Arr.Add(Item);
  end;
  Obj.Add('compilers', Arr);
  PrintJSON(Obj);
end;

{ ---- Main ---- }

var
  Tree:        TProjectTree;
  Project:     TProjectBase;
  ProjectFile: string;
  I:           Integer;
  Changed:     Boolean;
  OutObj:      TJSONObject;

begin
  Project       := nil;
  GExecuteGoals := TStringList.Create;
  GFilterTags   := TStringList.Create;
  GBashWords    := TStringList.Create;
  GRunArgs      := TStringList.Create;
  GBashCword    := -1;
  GErrorContext := 0;
  GTimeout      := 0;
  ParseArgs;

  { --bash must be handled before anything else — outputs plain text, not JSON }
  if GBashCword >= 0 then
  begin
    DoBashCompletion(GBashCword, GBashWords.ToStringArray);
    Halt(0);
  end;

  if ParamCount = 0 then
  begin
    PrintJSON(ErrorJSON('No options given. Run with --help to see usage.'));
    Halt(1);
  end;

  if GShowHelp then
  begin
    PrintUsage;
    Halt(0);
  end;

  if GShowExamples then
  begin
    PrintExamples;
    Halt(0);
  end;

  if GShowFields then
  begin
    PrintFields;
    Halt(0);
  end;

  if GInstall then
  begin
    DoInstall;
    Halt(0);
  end;

  if GListCompilers then
  begin
    DoListCompilers;
    Halt(0);
  end;

  CheckFirstRun;

  Tree := TProjectTree.Create;
  try
    if not Tree.LoadFromDir(GetCurrentDir) then
      Die('No pasbuild root POM found.  Run from inside a pasbuild project tree.');

    if GListModules then
    begin
      DoListModules(Tree);
      Halt(0);
    end;

    if GListGoals then
    begin
      { Resolve module dir if --module was also given }
      ProjectFile := '';
      if GModuleName <> '' then
      begin
        if not Tree.FindModule(GModuleName, ProjectFile) then
        begin
          if (GModuleName = '.') or (GModuleName = 'root') then
            ProjectFile := Tree.RootPOMFile;
        end;
      end;
      DoListGoals(
        ExtractFilePath(Tree.RootPOMFile),
        IfThen(ProjectFile <> '', ExtractFilePath(ProjectFile), ''),
        GModuleName);
      Halt(0);
    end;

    { Auto-select when there is exactly one module (standalone project, no POM). }
    if (GModuleName = '') and (Tree.Modules.Count = 1) and not GAllModules then
      GModuleName := Tree.Modules[0].PathComponent;

    if GModuleName = '' then
    begin
      if GAllModules and (GExecuteGoals.Count > 0) then
      begin
        DoExecuteGoals(ExtractFilePath(Tree.RootPOMFile));
        Halt(0);
      end;
      if GAllModules then
        Die('--all-modules requires --execute-goals');
      Die('--module <name> is required.  Use --list-modules to see available modules.');
    end;

    if not Tree.FindModule(GModuleName, ProjectFile) then
    begin
      { '.' and 'root' are shorthands for the root POM itself, which is not
        listed as a child of itself.  Also accept the root POM's own <name>. }
      if (GModuleName = '.') or (GModuleName = 'root') then
        ProjectFile := Tree.RootPOMFile
      else
      begin
        { Last-chance: load root POM and check its <name> field }
        ProjectFile := '';
        if FileExists(Tree.RootPOMFile) then
        begin
          try
            Project := TProjectBase.LoadFromFile(Tree.RootPOMFile);
            try
              if SameText(Project.Name, GModuleName) then
                ProjectFile := Tree.RootPOMFile;
            finally
              Project.Free;
              Project := nil;
            end;
          except
          end;
        end;
        if ProjectFile = '' then
          DieWithModules('Module not found: ' + GModuleName, Tree);
      end;
    end;

    if not FileExists(ProjectFile) then
      Die('project.xml not found at: ' + ProjectFile);

    { --rename-module-dir: rename the directory and patch all project.xml files }
    if GRenameModuleDir <> '' then
    begin
      if GMutCount > 0 then
        Die('--rename-module-dir cannot be combined with other mutation flags');
      if SameText(ProjectFile, Tree.RootPOMFile) then
        Die('--rename-module-dir cannot be used on the root POM module');
      DoRenameModuleDir(Tree, GModuleName, GRenameModuleDir, ProjectFile);
      Halt(0);
    end;

    { --execute-goals does not load the model — it just needs the project dir }
    if GExecuteGoals.Count > 0 then
    begin
      if GMutCount > 0 then
        Die('--execute-goals cannot be combined with mutation flags');
      DoExecuteGoals(ExtractFilePath(Tree.RootPOMFile));
      { DoExecuteGoals calls Halt internally }
    end;

    try
      Project := TProjectBase.LoadFromFile(ProjectFile);
    except
      on E: Exception do
        Die('Failed to load ' + ProjectFile + ': ' + E.Message);
    end;

    try
      if GGetField <> '' then
      begin
        if GMutCount > 0 then
          Die('--get cannot be combined with mutation flags');
        DoGetField(Project, GGetField);
        Halt(0);
      end;

      if GGetModuleActive <> '' then
      begin
        if GMutCount > 0 then
          Die('--get-module-active cannot be combined with mutation flags');
        DoGetModuleActive(Project, GGetModuleActive);
        Halt(0);
      end;

      if GRun then
      begin
        if GMutCount > 0 then
          Die('--run cannot be combined with mutation flags');
        DoRunApp(Project, ProjectFile);
        { DoRunApp calls Halt internally }
      end;

      Changed := GMutCount > 0;

      for I := 0 to GMutCount - 1 do
        ApplyMutation(Project, GMutations[I], ProjectFile);

      if Changed then
      begin
        try
          Project.SaveToFile;
        except
          on E: Exception do
            Die('Failed to save ' + ProjectFile + ': ' + E.Message);
        end;
      end;

      OutObj := ProjectToJSON(Project, GModuleName, ProjectFile);
      if Changed then
        OutObj.Add('changed', True);
      PrintJSON(OutObj);

    finally
      Project.Free;
    end;

  finally
    Tree.Free;
  end;
end.
