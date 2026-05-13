{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Dialog.CompilerOptions;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  TermUI.Menu,
  PasbuildEditor.UIContext;

{ String-list editor for FPC compiler flag lists.
  Entries are free-form (e.g. -O2, -gw); no identifier validation is applied. }
procedure RunCompilerOptionsDialog(Ctx: TUIContext; const ATitle: string;
  AList: TStringList);

implementation

uses
  PasbuildEditor.GlobalKeys,
  PasbuildEditor.Compiler,
  PasbuildEditor.Compiler.FPC,
  PasbuildEditor.ProjectModel,
  TermUI.FilteredPicker;

function ResolveCompilerClass(Ctx: TUIContext): TCompilerClass;
var
  PomFile:    string;
  ModuleName: string;
  Key:        string;
begin
  if Assigned(Ctx.ParentPOM) then
  begin
    PomFile    := Ctx.ParentPOM.FileName;
    ModuleName := Ctx.Project.Name;
  end
  else
  begin
    PomFile    := '';
    ModuleName := '';
  end;
  Key    := DetectCompilerName(ExtractFilePath(ExpandFileName(Ctx.Project.FileName)), PomFile, ModuleName);
  Result := TCompiler.FindCompiler(Key);
  if Result = nil then
    Result := TCompilerFPC;
end;

procedure RunCompilerOptionsDialog(Ctx: TUIContext; const ATitle: string;
  AList: TStringList);
var
  SMenu:     TMenu;
  SSel:      TMenuItem;
  SVal:      string;
  J:         Integer;
  AllOpts:   TCompilerOptionsList;
  PickItems: TFilteredPickerItemList;
  Opt:       TCompilerOptionItem;
begin
  repeat
    SMenu := TMenu.Create(ATitle);
    try
      SMenu.AddHeader(ExtractFileName(ATitle) + ' (' + IntToStr(AList.Count) + ')');
      SMenu.AddSeparator;
      for J := 0 to AList.Count - 1 do
        SMenu.Add(TMenuItem.Create(AList[J], nil));
      SMenu.AddSeparator;
      SMenu.Add(TMenuItem.Create('Add option', nil, '', 'A'));

      SSel := SMenu.Run;
      case CheckGlobalKeys(SMenu, Ctx, SSel) of
        gkContinue: Continue;
        gkBreak:    Break;
      end;
      if (SSel = nil) and (SMenu.UnhandledChar = #0) then Break;

      if SSel.Label_ = 'Add option' then
      begin
        AllOpts   := TCompilerOptionsList.Create(True);
        PickItems := TFilteredPickerItemList.Create(True);
        try
          ResolveCompilerClass(Ctx).GetOptions(AllOpts);
          for Opt in AllOpts do
            PickItems.Add(TFilteredPickerItem.Create(Opt.Flag, Opt.Description));
          if RunFilteredPicker(ATitle + ' › Add option', PickItems, SVal) and
             (SVal <> '') then
          begin
            AList.Add(SVal);
            Ctx.SetModified;
          end;
        finally
          PickItems.Free;
          AllOpts.Free;
        end;
      end
      else if SMenu.DeletePressed then
      begin
        if Confirm('Remove "' + SSel.Label_ + '"?') then
        begin
          J := AList.IndexOf(SSel.Label_);
          if J >= 0 then begin AList.Delete(J); Ctx.SetModified; end;
        end;
      end
      else
      begin
        SVal := SSel.Label_;
        if EditLine('Edit option', SVal, SVal, SMenu.SelectedRow) and
           (SVal <> '') and (SVal <> SSel.Label_) then
        begin
          J := AList.IndexOf(SSel.Label_);
          if J >= 0 then begin AList[J] := SVal; Ctx.SetModified; end;
        end;
      end;
    finally
      SMenu.Free;
    end;
  until GQuitRequested or GCtrlCRequested or GCtrlXRequested;
end;

end.
