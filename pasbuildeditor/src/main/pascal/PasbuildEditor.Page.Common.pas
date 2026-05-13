{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Page.Common;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  TermUI.Menu,
  PasbuildEditor.ProjectModel,
  PasbuildEditor.UIContext;

{ Build / dependencies aggregate page for TProjectCommon projects. }
procedure RunCommonPage(Ctx: TUIContext; P: TProjectCommon);

implementation

uses
  StrUtils,
  TermUI.Terminal,
  TermUI.PathPicker,
  PasbuildEditor.Strings,
  PasbuildEditor.Page.StringList,
  PasbuildEditor.Page.Profiles,
  PasbuildEditor.Page.Dependencies,
  PasbuildEditor.Page.ModuleDeps,
  PasbuildEditor.GlobalKeys,
  PasbuildEditor.Dialog.CompilerOptions,
  PasbuildEditor.Page.BootstrapExclude,
  PasbuildEditor.Page.SourcePackage,
  PasbuildEditor.Page.UnitPaths,
  PasbuildEditor.Page.ShowHelp,
  TermUI.Application;

procedure RunCommonPage(Ctx: TUIContext; P: TProjectCommon);
var
  Menu:      TMenu;
  Sel:       TMenuItem;
  It:        TMenuItem;
  NewVal:    string;
  LastLabel: string;
  DepNames:  TStringList;
  DepVal:    string;
  DI:        Integer;
begin
  LastLabel := '';
  repeat
    Menu := TMenu.Create(Ctx.Breadcrumb);
    try
      Menu.AddHeader('Build');
      if P.ProjectType = ptApplication then
      begin
        It := TMenuItem.Create('Main source', nil, P.MainSource, 'S');
        It.Desc := SDescMainSource; Menu.Add(It);
      end;
      It := TMenuItem.Create('Output directory', nil, P.OutputDirectory, 'O');
      It.Desc := SDescOutputDir; Menu.Add(It);
      It := TMenuItem.Create('Source directory', nil, P.SourceDirectory, 'C');
      It.Desc := SDescSourceDir; Menu.Add(It);
      if P.ProjectType = ptApplication then
      begin
        It := TMenuItem.Create('Executable name', nil, P.ExecutableName, 'X');
        It.Desc := SDescExeName; Menu.Add(It);
      end;
      Menu.AddSeparator;
      It := TMenuItem.Create('Unit paths', nil,
        IntToStr(P.UnitPaths.Count) + ' entries', 'U');
      It.Desc := SDescUnitPaths; Menu.Add(It);
      It := TMenuItem.Create('Defines', nil,
        IfThen(P.Defines.Count = 0, '(none)',
               JoinTruncated(P.Defines, ' ', Term.Width - 26)), 'F');
      It.DimValue := (P.Defines.Count = 0);
      It.Desc := SDescDefines; Menu.Add(It);
      It := TMenuItem.Create('Include paths', nil,
        IntToStr(P.IncludePaths.Count) + ' entries', 'I');
      It.Desc := SDescIncludePaths; Menu.Add(It);
      It := TMenuItem.Create('Compiler options', nil,
        IfThen(P.CompilerOptions.Count = 0, '(none)',
               JoinTruncated(P.CompilerOptions, ' ', Term.Width - 26)), 'P');
      It.DimValue := (P.CompilerOptions.Count = 0);
      It.Desc := SDescCompilerOptions; Menu.Add(It);
      It := TMenuItem.Create('Bootstrap exclude', nil,
        IfThen(P.BootstrapExclude.Count = 0, '(none)',
               JoinTruncated(P.BootstrapExclude, ' ', Term.Width - 26)), 'B');
      It.DimValue := (P.BootstrapExclude.Count = 0);
      It.Desc := SDescBootstrapExclude; Menu.Add(It);
      It := TMenuItem.Create('Source package', nil,
        IfThen(P.SourcePackageIncludes.Count = 0,
               'src/  (default)',
               JoinTruncated(P.SourcePackageIncludes, ' ', Term.Width - 26)), 'K');
      It.DimValue := (P.SourcePackageIncludes.Count = 0);
      It.Desc := SDescSourcePkgIncludes; Menu.Add(It);
      Menu.AddSeparator;
      DepNames := TStringList.Create;
      try
        for DI := 0 to P.Dependencies.Count - 1 do
          DepNames.Add(P.Dependencies[DI].Name);
        if DepNames.Count = 0 then DepVal := '(none)'
        else DepVal := JoinTruncated(DepNames, ', ', Term.Width - 26);
      finally
        DepNames.Free;
      end;
      It := TMenuItem.Create('Dependencies', nil, DepVal, 'D');
      It.DimValue := (P.Dependencies.Count = 0);
      It.Desc := SDescDependencies; Menu.Add(It);
      if Assigned(Ctx.ParentPOM) then
      begin
        DepNames := TStringList.Create;
        try
          for DI := 0 to P.ModuleDependencies.Count - 1 do
            DepNames.Add(P.ModuleDependencies[DI]);
          if DepNames.Count = 0 then DepVal := '(none)'
          else DepVal := JoinTruncated(DepNames, ', ', Term.Width - 26);
        finally
          DepNames.Free;
        end;
        It := TMenuItem.Create('Module dependencies', nil, DepVal, 'M');
        It.DimValue := (P.ModuleDependencies.Count = 0);
        It.Desc := SDescModuleDeps; Menu.Add(It);
      end;

      if LastLabel <> '' then Menu.SelectByLabel(LastLabel);
      Sel := Menu.Run;

      case CheckGlobalKeys(Menu, Ctx, Sel, 'build') of
        gkContinue: Continue;
        gkBreak:    Break;
      end;
      if (Sel = nil) and (Menu.UnhandledChar = #0) then Break;
      LastLabel := Sel.Label_;

      case Sel.Label_ of
        'Main source': begin
          NewVal := P.MainSource;
          if RunPathPicker(ExtractFilePath(ExpandFileName(Ctx.Project.FileName)),
               Ctx.Breadcrumb + ' > Main Source', False, NewVal) then
            begin P.MainSource := NewVal; Ctx.SetModified; end;
        end;
        'Output directory': begin
          NewVal := P.OutputDirectory;
          if RunPathPicker(ExtractFilePath(ExpandFileName(Ctx.Project.FileName)),
               Ctx.Breadcrumb + ' > Output Directory', True, NewVal) then
            begin P.OutputDirectory := NewVal; Ctx.SetModified; end;
        end;
        'Source directory': begin
          NewVal := P.SourceDirectory;
          if RunPathPicker(ExtractFilePath(ExpandFileName(Ctx.Project.FileName)),
               Ctx.Breadcrumb + ' > Source Directory', True, NewVal) then
            begin P.SourceDirectory := NewVal; Ctx.SetModified; end;
        end;
        'Executable name':
          if EditLine('Executable name', P.ExecutableName, NewVal, Menu.SelectedRow) then
            begin P.ExecutableName := NewVal; Ctx.SetModified; end;
        'Unit paths':
          RunUnitPathsPage(Ctx, P, 'Unit Paths', P.UnitPaths, 'unit');
        'Defines':
          RunStringListPage(Ctx, Ctx.Breadcrumb + ' > Defines', P.Defines);
        'Include paths':
          RunUnitPathsPage(Ctx, P, 'Include Paths', P.IncludePaths, 'include');
        'Compiler options':
          RunCompilerOptionsDialog(Ctx,
            Ctx.Breadcrumb + ' > Compiler options', P.CompilerOptions);
        'Bootstrap exclude':
          RunBootstrapExcludePage(Ctx, P);
        'Source package':
          RunSourcePackagePage(Ctx, P);
        'Dependencies':
          RunDepsPage(Ctx, P);
        'Module dependencies':
          RunModuleDepsPage(Ctx, P);
      end;
    finally
      Menu.Free;
    end;
  until Application.Terminated;
end;

end.
