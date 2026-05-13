{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Page.Dependencies;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  TermUI.Menu,
  PasbuildEditor.ProjectModel,
  PasbuildEditor.UIContext;

{ Detail view for a single dependency: version picker + remove.
  Returns True if the dependency was removed. }
function RunDepDetailPage(Ctx: TUIContext; P: TProjectCommon;
  Dep: TDependency): Boolean;

{ List of external dependencies with add/remove. }
procedure RunDepsPage(Ctx: TUIContext; P: TProjectCommon);

implementation

uses
  TermUI.Terminal,
  PasbuildEditor.GlobalKeys,
  PasbuildEditor.DependencyResolver,
  PasbuildEditor.Strings,
  PasbuildEditor.UI.Utils,
  PasbuildEditor.Dialog.PackageSearch,
  TermUI.Application;

function RunDepDetailPage(Ctx: TUIContext; P: TProjectCommon;
  Dep: TDependency): Boolean;
var
  SubMenu:  TMenu;
  SubSel:   TMenuItem;
  Versions: TPackageVersionList;
  AllPkgs:  TPackageInfoList;
  I, Shown: Integer;
  Ver:      TPackageVersion;
  Item:     TMenuItem;
  UniqVers: TStringList;
  VerStr:   string;
begin
  Result := False;
  AllPkgs := nil;
  UniqVers := TStringList.Create;
  try
    if Assigned(Ctx.Resolver) then
    begin
      AllPkgs := Ctx.Resolver.ListAllPackages;
      try
        for I := 0 to AllPkgs.Count - 1 do
          if SameText(AllPkgs[I].Name, Dep.Name) then
          begin
            Versions := AllPkgs[I].Versions;
            SortVersionsNewest(Versions);
            for Ver in Versions do
              if UniqVers.IndexOf(Ver.Version) < 0 then
                UniqVers.Add(Ver.Version);
            Break;
          end;
      finally
        AllPkgs.Free;
      end;
    end;

    SubMenu := TMenu.Create(Ctx.Breadcrumb + ' > ' + Dep.Name);
    try
      SubMenu.AddHeader(Dep.Name + ' ' + Dep.Version);
      SubMenu.AddSeparator;

      Shown := 0;
      for I := 0 to UniqVers.Count - 1 do
      begin
        if Shown >= 5 then Break;
        VerStr := UniqVers[I];
        if SameText(VerStr, Dep.Version) then
          Item := TMenuItem.Create(VerStr, nil, '(current)')
        else
        begin
          Item := TMenuItem.Create(VerStr, nil);
          if CompareSemver(VerStr, Dep.Version) < 0 then
            Item.MarkOld := True;
        end;
        SubMenu.Add(Item);
        Inc(Shown);
      end;

      SubMenu.AddSeparator;
      SubMenu.Add(TMenuItem.Create('Remove dependency', nil, '', 'R'));

      SubSel := SubMenu.Run;
      if GSaveRequested then begin Ctx.SaveProject; GSaveRequested := False; end;
      if Application.Terminated or (SubSel = nil) then Exit;

      if SubSel.Label_ = 'Remove dependency' then
      begin
        if Confirm('Remove dependency "' + Dep.Name + '"?') then
        begin
          P.RemoveDependency(Dep);
          Ctx.SetModified;
          Result := True;
        end;
      end
      else
      begin
        if not SameText(SubSel.Label_, Dep.Version) then
        begin
          Dep.Version := SubSel.Label_;
          Ctx.SetModified;
        end;
      end;
    finally
      SubMenu.Free;
    end;
  finally
    UniqVers.Free;
  end;
end;

procedure RunDepsPage(Ctx: TUIContext; P: TProjectCommon);
var
  Menu:            TMenu;
  Sel, It:         TMenuItem;
  I:               Integer;
  Dep:             TDependency;
  PkgName, PkgVer: string;
  ModuleNames:     TStringList;
  PomDir, AbsModDir, ModName: string;
begin
  repeat
    Menu := TMenu.Create(Ctx.Breadcrumb + ' > Dependencies');
    try
      Menu.AddHeader('External dependencies (' + IntToStr(P.Dependencies.Count) + ')');
      Menu.AddSeparator;
      for I := 0 to P.Dependencies.Count - 1 do
      begin
        Dep := P.Dependencies[I];
        It := TMenuItem.Create(Dep.Name, nil, Dep.Version);
        It.Desc := SDescDepVersion;
        Menu.Add(It);
      end;
      Menu.AddSeparator;
      It := TMenuItem.Create('Add dependency', nil);
      It.Desc := SDescDependencies;
      Menu.Add(It);

      Sel := Menu.Run;
      case CheckGlobalKeys(Menu, Ctx, Sel) of
        gkContinue: Continue;
        gkBreak:    Break;
      end;
      if (Sel = nil) and (Menu.UnhandledChar = #0) then Break;

      if Sel.Label_ = 'Add dependency' then
      begin
        ModuleNames := TStringList.Create;
        try
          if Assigned(Ctx.ParentPOM) then
          begin
            PomDir := ExcludeTrailingPathDelimiter(
                        ExtractFilePath(ExpandFileName(Ctx.ParentPOM.FileName)));
            for I := 0 to Ctx.ParentPOM.Modules.Count - 1 do
            begin
              AbsModDir := ExpandFileName(
                IncludeTrailingPathDelimiter(PomDir) + Ctx.ParentPOM.Modules[I].Path);
              ModName := ModuleNameFromAbsDir(AbsModDir);
              if ModName <> '' then
                ModuleNames.Add(ModName);
            end;
          end;
          if RunPackageSearch(Ctx.Resolver, PkgName, PkgVer, ModuleNames,
               Ctx.Breadcrumb + ' > Add Dependency') then
          begin
            if PkgVer = '' then
              EditLine('Version for ' + PkgName, '', PkgVer);
            if (PkgName <> '') and (PkgVer <> '') then
            begin
              Dep := nil;
              for I := 0 to P.Dependencies.Count - 1 do
                if SameText(P.Dependencies[I].Name, PkgName) then
                begin
                  Dep := P.Dependencies[I];
                  Break;
                end;
              if Assigned(Dep) then
              begin
                if Dep.Version <> PkgVer then
                begin
                  Dep.Version := PkgVer;
                  Ctx.SetModified;
                end;
              end
              else
              begin
                P.AddDependency(PkgName, PkgVer);
                Ctx.SetModified;
              end;
            end;
          end;
        finally
          ModuleNames.Free;
        end;
      end
      else
      begin
        Dep := nil;
        for I := 0 to P.Dependencies.Count - 1 do
          if P.Dependencies[I].Name = Sel.Label_ then
          begin
            Dep := P.Dependencies[I];
            Break;
          end;
        if Assigned(Dep) then
          RunDepDetailPage(Ctx, P, Dep);
      end;
    finally
      Menu.Free;
    end;
  until Application.Terminated;
end;

end.
