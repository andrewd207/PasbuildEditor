{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Page.Project;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  PasbuildEditor.ProjectModel,
  PasbuildEditor.UIContext;

{ Run the modules/children page for a POM project. }
procedure RunPOMPage(Ctx: TUIContext; P: TProjectPOM);

{ Run the top-level project page (identity, profiles, build, modules). }
procedure RunProjectPage(Ctx: TUIContext);

{ Run the full project UI loop (handles save-on-quit, Ctrl-X). }
procedure RunProjectUI(Ctx: TUIContext);

implementation

uses
  TermUI.Terminal, TermUI.Menu, TermUI.PathPicker,
  PasbuildEditor.Strings,
  PasbuildEditor.UI.Utils,
  PasbuildEditor.Page.Common,
  PasbuildEditor.Page.Profiles,
  PasbuildEditor.Page.BuildRunner,
  PasbuildEditor.GlobalKeys,
  PasbuildEditor.Dialog.About,
  PasbuildEditor.Dialog.PasbuildInit,
  PasbuildEditor.Page.ShowHelp,
  TermUI.Application;

{ ── POM page helpers ─────────────────────────────────────────────── }

procedure RunCreateModuleWizard(Ctx: TUIContext; P: TProjectPOM);
var
  FolderName: string;
  FullDir:    string;
  ModPath:    string;
  ProjectDir: string;
  I:          Integer;

  procedure ShowMsg(const S: string; AColor: TColor);
  begin
    Term.GotoXY(1, Term.Height - 1);
    Term.ClearToEOL;
    Term.SetFG(AColor);
    Term.WriteStr(' ' + S);
    Term.ResetColors;
    Term.FlushOutput;
    Term.ReadKey;
  end;

begin
  if not EditLine('New module folder name', '', FolderName) or (FolderName = '') then Exit;

  FolderName := ExcludeLeadingPathDelimiter(FolderName);
  if (FolderName = '') or (Pos('..', FolderName) > 0) then
  begin
    ShowMsg('Folder name must not be empty or contain "..".', clRed);
    Exit;
  end;

  ProjectDir := IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(Ctx.Project.FileName)));
  FullDir    := ProjectDir + FolderName;

  if Pos(ProjectDir, IncludeTrailingPathDelimiter(FullDir)) <> 1 then
  begin
    ShowMsg('Folder must be inside the project directory.', clRed);
    Exit;
  end;

  if DirectoryExists(FullDir) then
  begin
    ShowMsg('Folder already exists: ' + FullDir, clRed);
    Exit;
  end;

  ModPath := FolderName;
  for I := 0 to P.Modules.Count - 1 do
    if SameText(P.Modules[I].Path, ModPath) then
    begin
      ShowMsg('Module already listed: ' + FolderName, clRed);
      Exit;
    end;

  if not ForceDirectories(FullDir) then
  begin
    ShowMsg('Could not create directory: ' + FullDir, clRed);
    Exit;
  end;

  if RunPasbuildInitInteractive(FullDir, P.License, P.Author) then
  begin
    P.AddModule(ModPath, True);
    Ctx.SetModified;
    ShowMsg('Created ' + FolderName + ' and added to modules.', clBrightCyan);
  end
  else
  begin
    if not FileExists(FullDir + '/project.xml') then
      RemoveDir(FullDir);
  end;
end;

{ ── POM page ─────────────────────────────────────────────────────── }

procedure RunPOMPage(Ctx: TUIContext; P: TProjectPOM);
var
  Menu:        TMenu;
  Sel:         TMenuItem;
  Item:        TMenuItem;
  I:           Integer;
  LastLabel:   string;
  NewPath:     string;
  SR:          TSearchRec;
  BaseDir:     string;
  CandPath:    string;
  AlreadyIn:   Boolean;
  Added:       Integer;
  Modl:        TModule;
  SelIdx:      Integer;
  SubProject:  TProjectBase;
  SubCtx:      TUIContext;
  ModFilePath: string;
  UChar:       Char;
  ScanMenu:    TMenu;
  ScanSel:     TMenuItem;
  CandName:    string;

  function ModuleAtMenuIdx(Idx: Integer): TModule;
  var J: Integer;
  begin
    Result := nil;
    J := Idx - 2;  // 2 = header + separator
    if (J >= 0) and (J < P.Modules.Count) then
      Result := P.Modules[J];
  end;

begin
  LastLabel := '';
  repeat
    Menu := TMenu.Create(Ctx.Breadcrumb + ' > Modules');
    try
      Item := TMenuItem.CreateHeader('Modules (' + IntToStr(P.Modules.Count) + ')');
      Item.Hint := '[E]nable  [D]isable';
      Menu.Add(Item);
      Menu.AddSeparator;
      for I := 0 to P.Modules.Count - 1 do
      begin
        Modl     := P.Modules[I];
        CandName := ModuleNameFromAbsDir(
          IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(Ctx.Project.FileName)))
          + Modl.Path);
        if Modl.ActiveByDefault then
          Item := TMenuItem.Create(CandName, nil, Modl.Path)
        else
        begin
          Item := TMenuItem.Create(CandName + ' (disabled)', nil, Modl.Path);
          Item.DimItem := True;
        end;
        Menu.Add(Item);
      end;
      Menu.AddSeparator;
      Menu.Add(TMenuItem.Create('Create new module',       nil, '', 'N'));
      Menu.Add(TMenuItem.Create('Scan folder for modules', nil, '', 'A'));
      Menu.Add(TMenuItem.Create('Add existing path',       nil, '', 'X'));

      if LastLabel <> '' then Menu.SelectByLabel(LastLabel);
      Sel    := Menu.Run;
      SelIdx := Menu.Selected;
      UChar  := Menu.UnhandledChar;

      case CheckGlobalKeys(Menu, Ctx, Sel, 'modules') of
        gkContinue: Continue;
        gkBreak:    Break;
      end;

      if (Sel = nil) and (UChar <> #0) then
      begin
        Modl := ModuleAtMenuIdx(SelIdx);
        if Assigned(Modl) then
        begin
          CandName := ModuleNameFromAbsDir(
            IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(Ctx.Project.FileName)))
            + Modl.Path);
          case UpCase(UChar) of
            'E': begin
              Modl.ActiveByDefault := True;
              Ctx.SetModified;
              LastLabel := CandName;
            end;
            'D': begin
              Modl.ActiveByDefault := False;
              Ctx.SetModified;
              LastLabel := CandName + ' (disabled)';
            end;
          end;
        end;
        Continue;
      end;

      if Sel = nil then Break;
      LastLabel := Sel.Label_;

      if Sel.Label_ = 'Create new module' then
      begin
        RunCreateModuleWizard(Ctx, P);
        LastLabel := '';
      end
      else if Sel.Label_ = 'Scan folder for modules' then
      begin
        BaseDir := ExtractFilePath(Ctx.Project.FileName);
        ScanMenu := TMenu.Create(Ctx.Breadcrumb + ' > Scan — Found Modules');
        try
          ScanMenu.AddHeader('Select a module to add');
          ScanMenu.AddSeparator;
          Added := 0;
          if FindFirst(BaseDir + '*', faDirectory, SR) = 0 then
          try
            repeat
              if (SR.Name = '.') or (SR.Name = '..') then Continue;
              if (SR.Attr and faDirectory) = 0 then Continue;
              if not FileExists(BaseDir + SR.Name + PathDelim + 'project.xml') then Continue;
              CandPath := SR.Name;
              AlreadyIn := False;
              for I := 0 to P.Modules.Count - 1 do
                if SameText(P.Modules[I].Path, CandPath) then
                begin
                  AlreadyIn := True;
                  Break;
                end;
              if not AlreadyIn then
              begin
                CandName := ModuleNameFromAbsDir(BaseDir + CandPath);
                ScanMenu.Add(TMenuItem.Create(CandName, nil, CandPath));
                Inc(Added);
              end;
            until FindNext(SR) <> 0;
          finally
            FindClose(SR);
          end;
          if Added = 0 then
          begin
            Term.GotoXY(1, Term.Height - 1);
            Term.ClearToEOL;
            Term.SetFG(clBrightBlack);
            Term.WriteStr(' No new modules found.  Press any key.');
            Term.ResetColors;
            Term.FlushOutput;
            Term.ReadKey;
          end
          else
          begin
            ScanSel := ScanMenu.Run;
            if Assigned(ScanSel) then
            begin
              P.AddModule(ScanSel.Value, True);
              Ctx.SetModified;
            end;
          end;
        finally
          ScanMenu.Free;
        end;
        LastLabel := '';
      end
      else if Sel.Label_ = 'Add existing path' then
      begin
        NewPath := '';
        if RunPathPicker(ExtractFilePath(ExpandFileName(Ctx.Project.FileName)),
             Ctx.Breadcrumb + ' > Add Module Path', True, NewPath) and (NewPath <> '') then
        begin
          AlreadyIn := False;
          for I := 0 to P.Modules.Count - 1 do
            if SameText(P.Modules[I].Path, NewPath) then
            begin
              AlreadyIn := True;
              Break;
            end;
          if AlreadyIn then
          begin
            Term.GotoXY(1, Term.Height - 1);
            Term.ClearToEOL;
            Term.SetFG(clRed);
            Term.WriteStr(' Module already in list: ' + NewPath + '  (press any key)');
            Term.ResetColors;
            Term.ReadKey;
          end
          else
          begin
            P.AddModule(NewPath, True);
            Ctx.SetModified;
          end;
        end;
      end
      else if Menu.DeletePressed then
      begin
        Modl := ModuleAtMenuIdx(SelIdx);
        if Assigned(Modl) and
           Confirm('Remove module "' + Modl.Path + '" from project? (no files deleted)') then
        begin
          P.RemoveModule(Modl);
          Ctx.SetModified;
          LastLabel := '';
        end;
      end
      else
      begin
        Modl := ModuleAtMenuIdx(SelIdx);
        if Assigned(Modl) then
        begin
          BaseDir     := ExtractFilePath(Ctx.Project.FileName);
          ModFilePath := BaseDir + Modl.Path;
          if not SameText(ExtractFileName(ModFilePath), 'project.xml') then
            ModFilePath := IncludeTrailingPathDelimiter(ModFilePath) + 'project.xml';
          if FileExists(ModFilePath) then
          begin
            try
              SubProject := TProjectBase.LoadFromFile(ModFilePath);
              try
                SubCtx := TUIContext.Create(SubProject,
                  Ctx.Breadcrumb + ' > ' + Modl.Path, Ctx.Resolver,
                  False, Ctx, TProjectPOM(Ctx.Project));
                try
                  RunProjectUI(SubCtx);
                  if SubCtx.Modified then Ctx.SetModified;
                finally
                  SubCtx.Free;
                end;
              finally
                SubProject.Free;
              end;
            except
              on E: Exception do
              begin
                Term.GotoXY(1, Term.Height - 1);
                Term.ClearToEOL;
                Term.SetFG(clRed);
                Term.WriteStr(' Cannot open ' + ModFilePath + ': ' + E.Message);
                Term.ResetColors;
                Term.ReadKey;
              end;
            end;
          end
          else
          begin
            Term.GotoXY(1, Term.Height - 1);
            Term.ClearToEOL;
            Term.SetFG(clRed);
            Term.WriteStr(' File not found: ' + ModFilePath + ' — press any key.');
            Term.ResetColors;
            Term.ReadKey;
          end;
          if not Application.Terminated then
            GCtrlCRequested := False;
        end;
      end;
    finally
      Menu.Free;
    end;
  until Application.Terminated;
end;

{ ── Project page ─────────────────────────────────────────────────── }

procedure RunProjectPage(Ctx: TUIContext);
var
  Menu:      TMenu;
  Sel:       TMenuItem;
  It:        TMenuItem;
  NewVal:    string;
  ProfNames: TStringList;
  ProfVal:   string;
  ModNames:  TStringList;
  ModVal:    string;
  ModXML:    string;
  ModChild:  TProjectBase;
  I:         Integer;
begin
  repeat
    Menu := TMenu.Create(Ctx.Breadcrumb);
    try
      Menu.AddHeader('Identity  [' + Ctx.Project.ProjectTypeLabel + ']');
      It := TMenuItem.CreateEmbeddedHotkey(SLabelName, nil, Ctx.Project.Name);
      It.Desc := SDescName; Menu.Add(It);

      It := TMenuItem.CreateEmbeddedHotkey(SLabelVersion, nil);
      if Ctx.Project.Version <> '' then
        It.Value := Ctx.Project.Version
      else if Assigned(Ctx.ParentPOM) and (Ctx.ParentPOM.Version <> '') then
        begin It.Value := Ctx.ParentPOM.Version + ' (inherited)'; It.DimValue := True; end
      else
        begin It.Value := '(inherited)'; It.DimValue := True; end;
      It.Desc := SDescVersion; Menu.Add(It);

      It := TMenuItem.CreateEmbeddedHotkey(SLabelAuthor, nil);
      if Ctx.Project.Author <> '' then
        It.Value := Ctx.Project.Author
      else if Assigned(Ctx.ParentPOM) and (Ctx.ParentPOM.Author <> '') then
        begin It.Value := Ctx.ParentPOM.Author + ' (inherited)'; It.DimValue := True; end;
      It.Desc := SDescAuthor; Menu.Add(It);

      It := TMenuItem.CreateEmbeddedHotkey(SLabelLicense, nil);
      if Ctx.Project.License <> '' then
        It.Value := Ctx.Project.License
      else if Assigned(Ctx.ParentPOM) and (Ctx.ParentPOM.License <> '') then
        begin It.Value := Ctx.ParentPOM.License + ' (inherited)'; It.DimValue := True; end;
      It.Desc := SDescLicense; Menu.Add(It);

      It := TMenuItem.CreateEmbeddedHotkey(SLabelDescription, nil);
      if Ctx.Project.Description <> '' then
        It.Value := Ctx.Project.Description
      else if Assigned(Ctx.ParentPOM) and (Ctx.ParentPOM.Description <> '') then
        begin It.Value := Ctx.ParentPOM.Description + ' (inherited)'; It.DimValue := True; end;
      It.Desc := SDescDescription; Menu.Add(It);

      It := TMenuItem.CreateEmbeddedHotkey(SLabelProjectUrl, nil);
      if Ctx.Project.ProjectUrl <> '' then
        It.Value := Ctx.Project.ProjectUrl
      else if Assigned(Ctx.ParentPOM) and (Ctx.ParentPOM.ProjectUrl <> '') then
        begin It.Value := Ctx.ParentPOM.ProjectUrl + ' (inherited)'; It.DimValue := True; end;
      It.Desc := SDescProjectUrl; Menu.Add(It);

      It := TMenuItem.CreateEmbeddedHotkey(SLabelRepoUrl, nil);
      if Ctx.Project.RepoUrl <> '' then
        It.Value := Ctx.Project.RepoUrl
      else if Assigned(Ctx.ParentPOM) and (Ctx.ParentPOM.RepoUrl <> '') then
        begin It.Value := Ctx.ParentPOM.RepoUrl + ' (inherited)'; It.DimValue := True; end;
      It.Desc := SDescRepoUrl; Menu.Add(It);
      Menu.AddSeparator;

      ProfNames := TStringList.Create;
      try
        for I := 0 to Ctx.Project.Profiles.Count - 1 do
          ProfNames.Add(Ctx.Project.Profiles[I].ID);
        if ProfNames.Count = 0 then
          ProfVal := '(none)'
        else
          ProfVal := JoinTruncated(ProfNames, ', ', Term.Width - 26);
      finally
        ProfNames.Free;
      end;
      It := TMenuItem.CreateEmbeddedHotkey(SLabelProfiles, nil, ProfVal);
      It.DimValue := (Ctx.Project.Profiles.Count = 0);
      It.Desc := SDescProfiles; Menu.Add(It);

      It := TMenuItem.CreateEmbeddedHotkey(SLabelRunBuild, nil);
      It.Desc := 'Run a pasbuild goal and view output live';
      Menu.Add(It);

      if Ctx.Project is TProjectCommon then
      begin
        It := TMenuItem.CreateEmbeddedHotkey(SLabelBuildDeps, nil);
        It.Desc := SDescBuildDeps;
        Menu.Add(It);
      end;
      if Ctx.Project is TProjectPOM then
      begin
        ModNames := TStringList.Create;
        try
          for I := 0 to TProjectPOM(Ctx.Project).Modules.Count - 1 do
          begin
            ModXML := IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(Ctx.Project.FileName)))
              + IncludeTrailingPathDelimiter(TProjectPOM(Ctx.Project).Modules[I].Path)
              + 'project.xml';
            if FileExists(ModXML) then
            begin
              ModChild := TProjectBase.LoadFromFile(ModXML);
              try
                ModNames.Add(ModChild.Name);
              finally
                ModChild.Free;
              end;
            end
            else
              ModNames.Add(TProjectPOM(Ctx.Project).Modules[I].Path);
          end;
          if ModNames.Count = 0 then
            ModVal := '(none)'
          else
            ModVal := JoinTruncated(ModNames, ', ', Term.Width - 26);
        finally
          ModNames.Free;
        end;
        It := TMenuItem.CreateEmbeddedHotkey(SLabelModules, nil, ModVal);
        It.DimValue := (TProjectPOM(Ctx.Project).Modules.Count = 0);
        Menu.Add(It);
      end;

      if Ctx.LastMenuLabel <> '' then Menu.SelectByLabel(Ctx.LastMenuLabel);
      Sel := Menu.Run;

      if (Menu.Selected >= 0) and (Menu.Selected < Menu.Items.Count) then
        Ctx.LastMenuLabel := Menu.Items[Menu.Selected].Label_;

      case CheckGlobalKeys(Menu, Ctx, Sel, 'project') of
        gkContinue: Continue;
        gkBreak:    Break;
      end;

      if (Sel = nil) and (Menu.UnhandledChar <> #0) then Continue;
      if (Sel = nil) then
      begin
        if Menu.ExitedLeft and Ctx.IsRoot then Continue;
        if Ctx.IsRoot then GQuitRequested := True;
        Break;
      end;

      case Sel.Label_ of
        'Name':
          if EditLine('Name', Ctx.Project.Name, NewVal, Menu.SelectedRow) then
          begin
            if Trim(NewVal) = '' then
            begin
              ShowStatusMsg('Name cannot be blank!', clRed);
              Continue;
            end;
            Ctx.Project.Name := NewVal; Ctx.SetModified;
          end;
        'Version':
          if EditLine('Version', Ctx.Project.Version, NewVal, Menu.SelectedRow) then
            begin Ctx.Project.Version := NewVal; Ctx.SetModified; end;
        'Author':
          if EditLine('Author', Ctx.Project.Author, NewVal, Menu.SelectedRow) then
            begin Ctx.Project.Author := NewVal; Ctx.SetModified; end;
        'License':
          if EditLine('License', Ctx.Project.License, NewVal, Menu.SelectedRow) then
            begin Ctx.Project.License := NewVal; Ctx.SetModified; end;
        'Description':
          if EditLine('Description', Ctx.Project.Description, NewVal, Menu.SelectedRow) then
            begin Ctx.Project.Description := NewVal; Ctx.SetModified; end;
        'Project URL':
          if EditLine('Project URL', Ctx.Project.ProjectUrl, NewVal, Menu.SelectedRow) then
            begin Ctx.Project.ProjectUrl := NewVal; Ctx.SetModified; end;
        'Repo URL':
          if EditLine('Repo URL', Ctx.Project.RepoUrl, NewVal, Menu.SelectedRow) then
            begin Ctx.Project.RepoUrl := NewVal; Ctx.SetModified; end;
        'Profiles':
          RunProfilesPage(Ctx, Ctx.Project);
        'Run build':
          RunBuildRunnerPage(Ctx);
        'Build / Dependencies':
          RunCommonPage(Ctx, TProjectCommon(Ctx.Project));
        'Modules / Children':
          RunPOMPage(Ctx, TProjectPOM(Ctx.Project));
      end;
    finally
      Menu.Free;
    end;
  until Application.Terminated;
end;

{ ── UI entry loop ────────────────────────────────────────────────── }

procedure RunProjectUI(Ctx: TUIContext);
begin
  GQuitRequested  := False;
  GCtrlCRequested := False;
  GCtrlXRequested := False;
  Application.Resume;
  RunProjectPage(Ctx);
  if GCtrlXRequested then
  begin
    GCtrlXRequested := False;
    GQuitRequested  := True;
    if Ctx.Modified then Ctx.SaveProject;
  end
  else if GQuitRequested or GCtrlCRequested then
  begin
    GQuitRequested  := True;
    GCtrlCRequested := False;
    if not Ctx.PromptSaveOnQuit then
    begin
      GQuitRequested  := False;
      GCtrlCRequested := False;
      Application.Resume;
      RunProjectUI(Ctx);
    end;
  end
  else if Ctx.Modified and Assigned(Ctx.Parent) then
  begin
    if not Ctx.PromptSaveOnQuit then
    begin
      Application.Resume;
      RunProjectUI(Ctx);
    end;
  end;
end;

end.
