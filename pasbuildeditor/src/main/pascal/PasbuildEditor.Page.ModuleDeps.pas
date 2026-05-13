{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Page.ModuleDeps;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  TermUI.Menu,
  PasbuildEditor.ProjectModel,
  PasbuildEditor.UIContext;

procedure RunModuleDepsPage(Ctx: TUIContext; P: TProjectCommon);

implementation

uses
  TermUI.Terminal,
  PasbuildEditor.GlobalKeys,
  PasbuildEditor.UI.Utils,
  TermUI.Application;

procedure RunModuleDepsPage(Ctx: TUIContext; P: TProjectCommon);
var
  Menu:       TMenu;
  Sel:        TMenuItem;
  I:          Integer;
  Modl:       TModule;
  ModPath:    string;
  ModName:    string;
  Already:    Boolean;
  AddMenu:    TMenu;
  AddSel:     TMenuItem;
  PomDir:     string;
  ProjectDir: string;
  AbsModDir:  string;
  StorePath:  string;
  SelfItem:   TMenuItem;
  SortedMods: TStringList;
  LastLabel:  string;
begin
  ProjectDir := ExcludeTrailingPathDelimiter(
                  ExtractFilePath(ExpandFileName(Ctx.Project.FileName)));
  PomDir     := ExcludeTrailingPathDelimiter(
                  ExtractFilePath(ExpandFileName(Ctx.ParentPOM.FileName)));
  LastLabel  := '';
  repeat
    Menu := TMenu.Create(Ctx.Breadcrumb + ' > Module Dependencies');
    try
      Menu.AddHeader('Module dependencies (' + IntToStr(P.ModuleDependencies.Count) + ')');
      Menu.AddSeparator;
      for I := 0 to P.ModuleDependencies.Count - 1 do
      begin
        ModPath   := P.ModuleDependencies[I];
        AbsModDir := ExpandFileName(IncludeTrailingPathDelimiter(ProjectDir) + ModPath);
        ModName   := ModuleNameFromAbsDir(AbsModDir);
        Menu.Add(TMenuItem.Create(ModName, nil, ModPath));
      end;
      Menu.AddSeparator;
      Menu.Add(TMenuItem.Create('Add module dependency', nil, '', 'A'));
      if LastLabel <> '' then Menu.SelectByLabel(LastLabel);

      Sel := Menu.Run;
      if Sel <> nil then LastLabel := Sel.Label_;
      case CheckGlobalKeys(Menu, Ctx, Sel) of
        gkContinue: Continue;
        gkBreak:    Break;
      end;
      if (Sel = nil) and (Menu.UnhandledChar = #0) then Break;

      if Sel.Label_ = 'Add module dependency' then
      begin
        AddMenu := TMenu.Create(Ctx.Breadcrumb + ' > Add Module Dependency');
        try
          AddMenu.AddHeader('Sibling modules');
          AddMenu.AddSeparator;
          SortedMods := TStringList.Create;
          try
            SortedMods.Duplicates := dupAccept;
            for I := 0 to Ctx.ParentPOM.Modules.Count - 1 do
            begin
              Modl      := Ctx.ParentPOM.Modules[I];
              AbsModDir := ExpandFileName(IncludeTrailingPathDelimiter(PomDir) + Modl.Path);
              StorePath := ComputeRelativePath(ProjectDir,
                             ExcludeTrailingPathDelimiter(AbsModDir));
              Already   := P.ModuleDependencies.IndexOf(StorePath) >= 0;
              ModName   := ModuleNameFromAbsDir(AbsModDir);
              if StorePath = '.' then
                SortedMods.Add(#0 + ModName + '=' + StorePath)
              else if not Already then
                SortedMods.Add(ModName + '=' + StorePath);
            end;
            SortedMods.Sort;
            for I := 0 to SortedMods.Count - 1 do
            begin
              ModName   := SortedMods.Names[I];
              StorePath := SortedMods.ValueFromIndex[I];
              if (Length(ModName) > 0) and (ModName[1] = #0) then
              begin
                ModName := Copy(ModName, 2, MaxInt) + ' (current)';
                SelfItem         := TMenuItem.Create(ModName, nil, StorePath);
                SelfItem.DimItem := True;
                SelfItem.Enabled := False;
                AddMenu.Add(SelfItem);
              end
              else
                AddMenu.Add(TMenuItem.Create(ModName, nil, StorePath));
            end;
          finally
            SortedMods.Free;
          end;
          AddSel := AddMenu.Run;
          case CheckGlobalKeys(AddMenu, Ctx, AddSel) of
            gkContinue: Continue;
            gkBreak:    Break;
          end;
          if Assigned(AddSel) then
          begin
            P.ModuleDependencies.Add(AddSel.Value);
            Ctx.SetModified;
          end;
        finally
          AddMenu.Free;
        end;
      end
      else
      begin
        ModPath := Sel.Value;
        if Confirm('Remove module dependency "' + Sel.Label_ + '"?') then
        begin
          I := P.ModuleDependencies.IndexOf(ModPath);
          if I >= 0 then
          begin
            P.ModuleDependencies.Delete(I);
            Ctx.SetModified;
          end;
        end;
      end;
    finally
      Menu.Free;
    end;
  until Application.Terminated;
end;

end.
