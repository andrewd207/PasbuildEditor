{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Page.SourcePackage;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  TermUI.Menu,
  PasbuildEditor.ProjectModel,
  PasbuildEditor.UIContext;

procedure RunSourcePackagePage(Ctx: TUIContext; P: TProjectCommon);

implementation

uses
  TermUI.Terminal,
  TermUI.PathPicker;

procedure RunSourcePackagePage(Ctx: TUIContext; P: TProjectCommon);
var
  Menu:       TMenu;
  Sel:        TMenuItem;
  It:         TMenuItem;
  ProjectDir: string;
  PickedPath: string;
  RelPath:    string;
  LastLabel:  string;
  I:          Integer;
begin
  ProjectDir := ExtractFilePath(ExpandFileName(Ctx.Project.FileName));
  LastLabel  := '';
  repeat
    Menu := TMenu.Create(Ctx.Breadcrumb + ' > Source package');
    try
      Menu.AddHeader('Source package extra includes');
      Menu.AddSeparator;

      if P.SourcePackageIncludes.Count = 0 then
      begin
        It := TMenuItem.Create('src/', nil, '(default)');
        It.DimItem := True;
        Menu.Add(It);
      end
      else
      begin
        for I := 0 to P.SourcePackageIncludes.Count - 1 do
          Menu.Add(TMenuItem.Create(P.SourcePackageIncludes[I], nil));
      end;

      Menu.AddSeparator;
      Menu.Add(TMenuItem.Create('Add folder', nil, '', 'A'));

      if LastLabel <> '' then Menu.SelectByLabel(LastLabel);
      Sel := Menu.Run;
      if GSaveRequested then begin Ctx.SaveProject; GSaveRequested := False; Continue; end;
      if GQuitRequested or GCtrlCRequested or GCtrlXRequested or
         ((Sel = nil) and (Menu.UnhandledChar = #0)) then Break;
      if Sel = nil then Continue;
      LastLabel := Sel.Label_;

      if Sel.Label_ = 'Add folder' then
      begin
        PickedPath := '';
        if RunPathPicker(ProjectDir, Ctx.Breadcrumb + ' > Source package > Add',
             True, PickedPath) then
        begin
          RelPath := ExtractRelativepath(ProjectDir, PickedPath);
          if (RelPath <> '') and (P.SourcePackageIncludes.IndexOf(RelPath) < 0) then
          begin
            P.SourcePackageIncludes.Add(RelPath);
            Ctx.SetModified;
            LastLabel := RelPath;
          end;
        end;
      end
      else if not Sel.DimItem then
      begin
        if Menu.DeletePressed then
        begin
          if Confirm('Remove "' + Sel.Label_ + '"?') then
          begin
            I := P.SourcePackageIncludes.IndexOf(Sel.Label_);
            if I >= 0 then begin P.SourcePackageIncludes.Delete(I); Ctx.SetModified; end;
            LastLabel := '';
          end;
        end;
      end;
    finally
      Menu.Free;
    end;
  until GQuitRequested or GCtrlCRequested or GCtrlXRequested;
end;

end.
