{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Page.UnitPaths;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  TermUI.Menu,
  PasbuildEditor.ProjectModel,
  PasbuildEditor.UIContext;

{ Editor for a conditional path list (unit paths or include paths).
  AKind must be 'unit' or 'include'. }
procedure RunUnitPathsPage(Ctx: TUIContext; P: TProjectCommon;
  const ATitle: string; AList: TConditionalPathList; AKind: string);

implementation

uses
  TermUI.Terminal,
  PasbuildEditor.GlobalKeys,
  PasbuildEditor.Strings,
  PasbuildEditor.Dialog.UnitPathEditor;

procedure RunUnitPathsPage(Ctx: TUIContext; P: TProjectCommon;
  const ATitle: string; AList: TConditionalPathList; AKind: string);
var
  Menu:      TMenu;
  Sel:       TMenuItem;
  It:        TMenuItem;
  I:         Integer;
  CP:        TConditionalPath;
  Path, Cond: string;
  LastLabel: string;
  Common, First, Other, OtherDir: string;
  ProjectDir, SrcBaseDir: string;
  Deleted:   Boolean;
begin
  LastLabel  := '';
  ProjectDir := ExtractFilePath(ExpandFileName(Ctx.Project.FileName));
  SrcBaseDir := ProjectDir;
  repeat
    Menu := TMenu.Create(Ctx.Breadcrumb + ' > ' + ATitle);
    try
      Menu.AddHeader(ATitle + ' (' + IntToStr(AList.Count) + ')');
      Menu.AddSeparator;
      if AKind = 'unit' then
      begin
        if P.ManualUnitPaths then
          It := TMenuItem.Create(SManualPathsOn, nil, '', 'M')
        else
          It := TMenuItem.Create(SManualPathsOff, nil, '', 'M');
        It.Desc := SDescManualPaths;
        Menu.Add(It);
        Menu.AddSeparator;
      end;
      for I := 0 to AList.Count - 1 do
      begin
        CP := AList[I];
        if CP.Condition <> '' then
          It := TMenuItem.Create(CP.Path, nil, '[' + CP.Condition + ']')
        else
          It := TMenuItem.Create(CP.Path, nil);
        Menu.Add(It);
      end;
      Menu.AddSeparator;
      It := TMenuItem.Create('Add path', nil, '', 'A');
      Menu.Add(It);

      if LastLabel <> '' then Menu.SelectByLabel(LastLabel);
      Sel := Menu.Run;
      case CheckGlobalKeys(Menu, Ctx, Sel) of
        gkContinue: Continue;
        gkBreak:
        begin
          if P.ManualUnitPaths and (AList.Count = 0) then
            ShowStatusMsg('Warning: manual paths enabled but no paths added — at least one path is recommended.', clYellow);
          Break;
        end;
      end;
      if (Sel = nil) and (Menu.UnhandledChar = #0) then
      begin
        if P.ManualUnitPaths and (AList.Count = 0) then
          ShowStatusMsg('Warning: manual paths enabled but no paths added — at least one path is recommended.', clYellow);
        Break;
      end;
      if Sel = nil then Continue;
      LastLabel := Sel.Label_;

      if (Sel.Label_ = SManualPathsOn) or (Sel.Label_ = SManualPathsOff) then
      begin
        P.ManualUnitPaths := not P.ManualUnitPaths;
        Ctx.SetModified;
        if P.ManualUnitPaths then LastLabel := SManualPathsOn
        else LastLabel := SManualPathsOff;
        Continue;
      end;

      if Sel.Label_ = 'Add path' then
      begin
        Path := '';
        if AList.Count > 0 then
        begin
          First  := ExcludeTrailingPathDelimiter(AList[0].Path);
          Common := ExtractFilePath(First);
          for I := 1 to AList.Count - 1 do
          begin
            Other    := ExcludeTrailingPathDelimiter(AList[I].Path);
            OtherDir := ExtractFilePath(Other);
            while (Common <> '') and
                  (Pos(LowerCase(ExcludeTrailingPathDelimiter(Common)),
                       LowerCase(OtherDir)) <> 1) do
              Common := ExtractFilePath(ExcludeTrailingPathDelimiter(Common));
          end;
          Path := Common;
        end;
        Cond := '';
        if RunUnitPathEditor(Ctx.Project, Ctx.ParentPOM,
             Ctx.Breadcrumb + ' > ' + ATitle + ' > Add',
             SrcBaseDir, Path, Cond,
             Copy(ATitle, 1, Length(ATitle) - 1), nil, P.SourceDirectory) and (Path <> '') then
        begin
          if AKind = 'include' then
            P.AddIncludePath(Path, Cond)
          else
            P.AddUnitPath(Path, Cond);
          Ctx.SetModified;
          LastLabel := Path;
        end;
      end
      else
      begin
        CP := nil;
        for I := 0 to AList.Count - 1 do
          if AList[I].Path = Sel.Label_ then begin CP := AList[I]; Break; end;
        if not Assigned(CP) then Continue;

        if Menu.DeletePressed then
        begin
          if Confirm('Remove path ' + CP.Path + '?') then
          begin
            if AKind = 'include' then
              P.RemoveIncludePath(CP)
            else
              P.RemoveUnitPath(CP);
            Ctx.SetModified;
            LastLabel := '';
          end;
          Continue;
        end;

        Path := CP.Path;
        Cond := CP.Condition;
        Deleted := False;
        if RunUnitPathEditor(Ctx.Project, Ctx.ParentPOM,
             Ctx.Breadcrumb + ' > ' + ATitle + ' > ' + Path,
             SrcBaseDir, Path, Cond,
             Copy(ATitle, 1, Length(ATitle) - 1), @Deleted, P.SourceDirectory) then
        begin
          if AKind = 'include' then
          begin
            P.RemoveIncludePath(CP);
            P.AddIncludePath(Path, Cond);
          end
          else
          begin
            P.RemoveUnitPath(CP);
            P.AddUnitPath(Path, Cond);
          end;
          Ctx.SetModified;
          LastLabel := Path;
        end
        else if Deleted then
        begin
          if AKind = 'include' then
            P.RemoveIncludePath(CP)
          else
            P.RemoveUnitPath(CP);
          Ctx.SetModified;
          LastLabel := '';
        end;
      end;
    finally
      Menu.Free;
    end;
  until GQuitRequested or GCtrlCRequested or GCtrlXRequested;
end;

end.
