{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Page.Profiles;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  TermUI.Menu,
  PasbuildEditor.ProjectModel,
  PasbuildEditor.Profiles,
  PasbuildEditor.UIContext;

procedure RunProfileEditPage(Ctx: TUIContext; P: TProjectBase; AProfile: TProfile);
procedure RunProfilesPage(Ctx: TUIContext; P: TProjectBase);

implementation

uses
  StrUtils,
  TermUI.Terminal,
  PasbuildEditor.GlobalKeys,
  PasbuildEditor.Dialog.CompilerOptions,
  PasbuildEditor.Page.StringList,
  TermUI.Application;

procedure RunProfileEditPage(Ctx: TUIContext; P: TProjectBase; AProfile: TProfile);
var
  Menu:      TMenu;
  Sel, It:   TMenuItem;
  NewVal:    string;
  LastLabel: string;
  I:         Integer;
  NewProf:   TProfile;
begin
  LastLabel := '';
  repeat
    Menu := TMenu.Create(Ctx.Breadcrumb + ' > Profile: ' + AProfile.ID);
    try
      Menu.AddHeader('Profile: ' + AProfile.ID);
      Menu.AddSeparator;
      Menu.Add(TMenuItem.Create('ID', nil, AProfile.ID, 'I'));
      It := TMenuItem.Create('Defines', nil,
        IfThen(AProfile.Defines.Count = 0, '(none)',
               JoinTruncated(AProfile.Defines, ' ', Term.Width - 26)), 'D');
      It.DimValue := (AProfile.Defines.Count = 0); Menu.Add(It);
      It := TMenuItem.Create('Compiler options', nil,
        IfThen(AProfile.CompilerOptions.Count = 0, '(none)',
               JoinTruncated(AProfile.CompilerOptions, ' ', Term.Width - 26)), 'C');
      It.DimValue := (AProfile.CompilerOptions.Count = 0); Menu.Add(It);
      Menu.AddSeparator;
      Menu.Add(TMenuItem.Create('Delete profile', nil, '', 'X'));
      Menu.Add(TMenuItem.Create('Duplicate profile', nil, '', 'U'));

      if LastLabel <> '' then Menu.SelectByLabel(LastLabel);
      Sel := Menu.Run;
      case CheckGlobalKeys(Menu, Ctx, Sel) of
        gkContinue: Continue;
        gkBreak:    Break;
      end;
      if (Sel = nil) and (Menu.UnhandledChar = #0) then Break;

      LastLabel := Sel.Label_;
      case Sel.Label_ of
        'ID':
          begin
            NewVal := AProfile.ID;
            if EditLine('Profile ID', NewVal, NewVal, Menu.SelectedRow) and (NewVal <> '') and
               not SameText(NewVal, AProfile.ID) then
            begin
              if not IsValidIdentifier(NewVal) then
                ShowStatusMsg('Invalid identifier "' + NewVal +
                  '". Use A-Z, a-z, _ and digits (not first char).', clRed)
              else
              begin
                for I := 0 to P.Profiles.Count - 1 do
                  if (P.Profiles[I] <> AProfile) and SameText(P.Profiles[I].ID, NewVal) then
                  begin
                    ShowStatusMsg('Profile "' + NewVal + '" already exists.', clRed);
                    NewVal := '';
                    Break;
                  end;
                if NewVal <> '' then
                begin
                  AProfile.ID := NewVal;
                  Ctx.SetModified;
                end;
              end;
            end;
          end;
        'Defines':
          RunStringListPage(Ctx,
            Ctx.Breadcrumb + ' > Profile: ' + AProfile.ID + ' > Defines',
            AProfile.Defines);
        'Compiler options':
          RunCompilerOptionsDialog(Ctx,
            Ctx.Breadcrumb + ' > Profile: ' + AProfile.ID + ' > Compiler options',
            AProfile.CompilerOptions);
        'Delete profile':
          if Confirm('Delete profile "' + AProfile.ID + '"?') then
          begin
            P.RemoveProfile(AProfile);
            Ctx.SetModified;
            Break;
          end;
        'Duplicate profile':
          begin
            NewVal := AProfile.ID + '_copy';
            if EditLine('New profile ID', NewVal, NewVal, Menu.SelectedRow) and (NewVal <> '') then
            begin
              if not IsValidIdentifier(NewVal) then
              begin
                ShowStatusMsg('Invalid identifier "' + NewVal +
                  '". Use A-Z, a-z, _ and digits (not first char).', clRed);
                NewVal := '';
              end;
              if NewVal <> '' then
              begin
                NewVal := Trim(NewVal);
                I := -1;
                if NewVal <> '' then
                  for I := 0 to P.Profiles.Count - 1 do
                    if SameText(P.Profiles[I].ID, NewVal) then
                    begin
                      ShowStatusMsg('Profile "' + NewVal + '" already exists.', clRed);
                      NewVal := '';
                      Break;
                    end;
                if NewVal <> '' then
                begin
                  NewProf    := P.AddProfile;
                  NewProf.ID := NewVal;
                  for I := 0 to AProfile.Defines.Count - 1 do
                    NewProf.Defines.Add(AProfile.Defines[I]);
                  for I := 0 to AProfile.CompilerOptions.Count - 1 do
                    NewProf.CompilerOptions.Add(AProfile.CompilerOptions[I]);
                  Ctx.SetModified;
                  RunProfileEditPage(Ctx, P, NewProf);
                end;
              end;
            end;
          end;
      end;
    finally
      Menu.Free;
    end;
  until Application.Terminated;
end;

procedure RunProfilesPage(Ctx: TUIContext; P: TProjectBase);
var
  Menu:        TMenu;
  Prof:        TProfile;
  I:           Integer;
  Templates:   TProfileTemplateArray;
  Sel:         TMenuItem;
  TplMenu:     TMenu;
  Tpl:         TProfileTemplate;
  NewProf:     TProfile;
  NewName:     string;
  ProfSummary: string;
begin
  repeat
    Menu := TMenu.Create(Ctx.Breadcrumb + ' > Profiles');
    try
      Menu.AddHeader('Profiles (' + IntToStr(P.Profiles.Count) + ')');
      Menu.AddSeparator;
      for I := 0 to P.Profiles.Count - 1 do
      begin
        Prof := P.Profiles[I];
        ProfSummary := '';
        if Prof.Defines.Count > 0 then
          ProfSummary := 'defines: ' + JoinTruncated(Prof.Defines, ' ', Term.Width - 26);
        if Prof.CompilerOptions.Count > 0 then
        begin
          if ProfSummary <> '' then ProfSummary := ProfSummary + '  ';
          ProfSummary := ProfSummary + 'options: ' + JoinTruncated(Prof.CompilerOptions, ' ', Term.Width - 26);
        end;
        if ProfSummary = '' then ProfSummary := '(empty)';
        Menu.Add(TMenuItem.Create(Prof.ID, nil, ProfSummary));
      end;
      Menu.AddSeparator;
      Menu.Add(TMenuItem.Create('Add profile from template', nil));
      Menu.Add(TMenuItem.Create('Add blank profile', nil));

      Sel := Menu.Run;
      case CheckGlobalKeys(Menu, Ctx, Sel) of
        gkContinue: Continue;
        gkBreak:    Break;
      end;
      if (Sel = nil) and (Menu.UnhandledChar = #0) then Break;

      if Sel.Label_ = 'Add profile from template' then
      begin
        TplMenu := TMenu.Create('Choose template');
        try
          Templates := TBuiltinProfiles.Templates;
          for I := 0 to High(Templates) do
            TplMenu.Add(TMenuItem.Create(Templates[I].Name, nil,
              Templates[I].Description));
          Sel := TplMenu.Run;
          if (not Application.Terminated) and Assigned(Sel) then
          begin
            NewProf := nil;
            for I := 0 to P.Profiles.Count - 1 do
              if SameText(P.Profiles[I].ID, Sel.Label_) then
              begin
                NewProf := P.Profiles[I];
                Break;
              end;
            if Assigned(NewProf) then
              ShowStatusMsg('Profile "' + Sel.Label_ + '" already exists.', clRed)
            else
            begin
              Tpl     := TBuiltinProfiles.FindTemplate(Sel.Label_);
              NewProf := P.AddProfile;
              TBuiltinProfiles.ApplyTemplate(NewProf, Tpl);
              Ctx.SetModified;
            end;
          end;
        finally
          TplMenu.Free;
        end;
      end
      else if Sel.Label_ = 'Add blank profile' then
      begin
        if EditLine('Profile ID', '', NewName, Menu.SelectedRow) and (NewName <> '') then
        begin
          if not IsValidIdentifier(NewName) then
            ShowStatusMsg('Invalid identifier "' + NewName +
              '". Use A-Z, a-z, _ and digits (not first char).', clRed)
          else
          begin
            NewProf := nil;
            for I := 0 to P.Profiles.Count - 1 do
              if SameText(P.Profiles[I].ID, NewName) then
              begin
                NewProf := P.Profiles[I];
                Break;
              end;
            if Assigned(NewProf) then
              ShowStatusMsg('Profile "' + NewName + '" already exists.', clRed)
            else
            begin
              NewProf    := P.AddProfile;
              NewProf.ID := NewName;
              Ctx.SetModified;
            end;
          end;
        end;
      end
      else if Menu.DeletePressed then
      begin
        for I := 0 to P.Profiles.Count - 1 do
          if P.Profiles[I].ID = Sel.Label_ then
          begin
            if Confirm('Delete profile "' + Sel.Label_ + '"?') then
            begin
              P.RemoveProfile(P.Profiles[I]);
              Ctx.SetModified;
            end;
            Break;
          end;
      end
      else
      begin
        for I := 0 to P.Profiles.Count - 1 do
          if P.Profiles[I].ID = Sel.Label_ then
          begin
            RunProfileEditPage(Ctx, P, P.Profiles[I]);
            Break;
          end;
      end;
    finally
      Menu.Free;
    end;
  until Application.Terminated;
end;

end.
