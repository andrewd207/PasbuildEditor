{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Dialog.UnitPathEditor;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  TermUI.Terminal, TermUI.Menu,
  PasbuildEditor.ProjectModel;

{ Single-path editor dialog (path + optional condition).
  ADeleted may be nil; if supplied it is set True when the user chooses Delete.
  ASrcPrefix is stripped from/prepended to APath when opening the path picker
  so the picker shows full project-relative paths.
  Returns True when the user presses OK with a non-empty path. }
function RunUnitPathEditor(AProject: TProjectBase; AParentPOM: TProjectPOM;
  const ABreadcrumb, ABaseDir: string;
  var APath, ACondition: string;
  const ATitle: string = 'Unit Path';
  ADeleted: PBoolean = nil;
  const ASrcPrefix: string = ''): Boolean;

implementation

uses
  StrUtils,
  TermUI.PathPicker,
  PasbuildEditor.Dialog.ConditionPicker,
  PasbuildEditor.UIContext,
  TermUI.Application;

function RunUnitPathEditor(AProject: TProjectBase; AParentPOM: TProjectPOM;
  const ABreadcrumb, ABaseDir: string;
  var APath, ACondition: string;
  const ATitle: string;
  ADeleted: PBoolean;
  const ASrcPrefix: string): Boolean;
var
  Menu:      TMenu;
  Sel, It:   TMenuItem;
  NewVal:    string;
  LastLabel: string;
  Prefix:    string;
begin
  Result    := False;
  if Assigned(ADeleted) then ADeleted^ := False;
  LastLabel := '';
  repeat
    Menu := TMenu.Create(ABreadcrumb);
    try
      Menu.AddHeader(ATitle);
      Menu.AddSeparator;
      Menu.Add(TMenuItem.Create('Path',      nil, APath,      'P'));
      It := TMenuItem.Create('Condition', nil,
        IfThen(ACondition = '', '(none)', ACondition), 'C');
      It.DimValue := (ACondition = ''); Menu.Add(It);
      Menu.AddSeparator;
      Menu.Add(TMenuItem.Create('OK',     nil, '', 'O'));
      if Assigned(ADeleted) then
        Menu.Add(TMenuItem.Create('Delete', nil, '', 'D'));
      Menu.Add(TMenuItem.Create('Cancel', nil, '', 'X'));

      if LastLabel <> '' then Menu.SelectByLabel(LastLabel);
      Sel := Menu.Run;
      if Application.Terminated or GSaveRequested then Break;
      if Sel = nil then Break;
      LastLabel := Sel.Label_;

      if Sel.Label_ = 'Path' then
      begin
        if (ASrcPrefix <> '') and (APath <> '') then
          NewVal := IncludeTrailingPathDelimiter(ASrcPrefix) + APath
        else
          NewVal := APath;
        if RunPathPicker(ABaseDir, ABreadcrumb + ' > Path', True, NewVal) then
        begin
          Prefix := IncludeTrailingPathDelimiter(ASrcPrefix);
          if (ASrcPrefix <> '') and
             (Copy(NewVal, 1, Length(Prefix)) = Prefix) then
            NewVal := Copy(NewVal, Length(Prefix) + 1, MaxInt);
          if (NewVal <> '') and ((Copy(NewVal, 1, 3) = '../') or (NewVal = '..')) then
          begin
            if Confirm('Path is outside the source directory. Are you sure?') then
              APath := NewVal;
          end
          else
            APath := NewVal;
        end;
      end
      else if Sel.Label_ = 'Condition' then
      begin
        NewVal := ACondition;
        if RunConditionPicker(AProject, AParentPOM, NewVal) then ACondition := NewVal;
      end
      else if Sel.Label_ = 'OK' then
      begin
        if APath <> '' then
        begin
          if SameFileName(
               ExcludeTrailingPathDelimiter(ExpandFileName(
                 IncludeTrailingPathDelimiter(ABaseDir) + APath)),
               ExcludeTrailingPathDelimiter(ExpandFileName(ABaseDir))) then
            ShowStatusMsg('Path cannot be the same as the source directory.', clRed)
          else
            Result := True;
        end;
        if Result then Break;
      end
      else if Sel.Label_ = 'Delete' then
      begin
        if Confirm('Delete path ' + APath + '?') then
        begin
          ADeleted^ := True;
          Break;
        end;
      end
      else if Sel.Label_ = 'Cancel' then
        Break;
    finally
      Menu.Free;
    end;
  until Application.Terminated;
end;

end.
