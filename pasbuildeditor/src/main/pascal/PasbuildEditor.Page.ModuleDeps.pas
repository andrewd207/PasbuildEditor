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
  TermUI.StringUtils,
  TermUI.Menu,
  PasbuildEditor.ProjectModel,
  PasbuildEditor.UIContext;

procedure RunModuleDepsPage(Ctx: TUIContext; P: TProjectCommon);

implementation

uses
  Process,
  TermUI.Terminal,
  TermUI.Application,
  TermUI.Debug.Overlay,
  PasbuildEditor.GlobalKeys,
  PasbuildEditor.UI.Utils;

{ Walk up the Ctx.Parent chain and return the root context. }
function FindRootCtx(Ctx: TUIContext): TUIContext;
begin
  Result := Ctx;
  while Assigned(Result.Parent) do
    Result := Result.Parent;
end;

{ Return the directory of the root context's parent POM (or project). }
function FindRootPOMDir(Ctx: TUIContext): string;
var
  C: TUIContext;
begin
  C := FindRootCtx(Ctx);
  if Assigned(C.ParentPOM) then
    Result := ExcludeTrailingPathDelimiter(
                ExtractFilePath(ExpandFileName(C.ParentPOM.FileName)))
  else
    Result := ExcludeTrailingPathDelimiter(
                ExtractFilePath(ExpandFileName(C.Project.FileName)));
end;

{ Recursively search ADir for project.xml files; build a name→dir map in AMap
  (AMap[name] = absolute directory containing project.xml). }
procedure BuildProjectNameMap(const ADir: string; AMap: TStringList);
var
  SR:      TSearchRec;
  XmlPath: string;
  Sub:     TProjectBase;
  ProjName: string;
begin
  { Check for a project.xml in this directory }
  XmlPath := IncludeTrailingPathDelimiter(ADir) + 'project.xml';
  if FileExists(XmlPath) then
  begin
    try
      Sub := TProjectBase.LoadFromFile(XmlPath);
      try
        ProjName := Sub.Name;
      finally
        Sub.Free;
      end;
    except
      ProjName := '';
    end;
    if ProjName <> '' then
      AMap.Values[ProjName] := ExcludeTrailingPathDelimiter(ADir);
  end;

  { Recurse into subdirectories }
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faDirectory, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then Continue;
      if (SR.Attr and faDirectory) = 0 then Continue;
      BuildProjectNameMap(IncludeTrailingPathDelimiter(ADir) + SR.Name, AMap);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

{ Run "pasbuild dependency-tree" from ARootDir.
  Parse: after each blank [INFO] line the next line is a module header.
  Split it by spaces; val[0] is the module name.  Only keep entries whose
  line contains [library] or [application].
  Returns a TStringList of module names (caller frees). }
function RunDepTree(const ARootDir: string): TStringList;
var
  Proc:        TProcess;
  Buf:         array[0..4095] of Byte;
  RawOutput:   string;
  N:           Integer;
  Lines:       TStringList;
  Line, Rest:  string;
  SpacePos:    Integer;
  I:           Integer;
  NextIsModule: Boolean;
begin
  Result := TStringList.Create;
  RawOutput := '';
  Proc := TProcess.Create(nil);
  try
    Proc.Executable       := 'pasbuild';
    Proc.Parameters.Add('dependency-tree');
    Proc.CurrentDirectory := ARootDir;
    Proc.Options          := [poUsePipes, poStderrToOutput];
    Proc.Execute;
    while Proc.Running or (Proc.Output.NumBytesAvailable > 0) do
    begin
      N := Proc.Output.Read(Buf, SizeOf(Buf));
      if N > 0 then
        RawOutput := RawOutput + Copy(string(PChar(@Buf[0])), 1, N);
    end;
  finally
    Proc.Free;
  end;

  Lines := TStringList.Create;
  try
    Lines.Text   := RawOutput;
    NextIsModule := False;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Lines[I];
      { Strip [INFO] prefix }
      if Copy(Line, 1, 7) = '[INFO] ' then
        Rest := Trim(Copy(Line, 8, MaxInt))
      else if Trim(Line) = '[INFO]' then
        Rest := ''
      else
        Continue;

      if Rest = '' then
      begin
        NextIsModule := True;
        Continue;
      end;

      if NextIsModule then
      begin
        NextIsModule := False;
        if (Pos('[library]', Rest) > 0) or (Pos('[application]', Rest) > 0) then
        begin
          SpacePos := Pos(' ', Rest);
          if SpacePos > 1 then
            Result.Add(Copy(Rest, 1, SpacePos - 1))
          else if Rest <> '' then
            Result.Add(Rest);
        end;
      end;
    end;
  finally
    Lines.Free;
  end;
end;

procedure RunModuleDepsPage(Ctx: TUIContext; P: TProjectCommon);
var
  Menu:       TMenu;
  Sel:        TMenuItem;
  I:          Integer;
  ModPath:    string;
  ModName:    string;
  Already:    Boolean;
  AddMenu:    TMenu;
  AddSel:     TMenuItem;
  ProjectDir: string;
  AbsModDir:  string;
  StorePath:  string;
  SortedMods: TStringList;
  LastLabel:  string;
  ModNames:   TStringList;
  NameMap:    TStringList;
  RootPomDir: string;
begin
  ProjectDir := ExcludeTrailingPathDelimiter(
                  ExtractFilePath(ExpandFileName(Ctx.Project.FileName)));
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
      case CheckGlobalKeys(Ctx) of
        gkContinue: Continue;
        gkBreak:    Break;
      end;
      if (Sel = nil) and (Menu.UnhandledChar = #0) then Break;

      if Sel.Label_ = 'Add module dependency' then
      begin
        DebugLog('add-mod: selected');
        AddMenu := TMenu.Create(Ctx.Breadcrumb + ' > Add Module Dependency');
        try
          AddMenu.AddHeader('Available modules');
          AddMenu.AddSeparator;
          try
            RootPomDir := FindRootPOMDir(Ctx);
            DebugLogFmt('add-mod: root=%s', [RootPomDir]);
            ModNames := RunDepTree(RootPomDir);
            DebugLogFmt('add-mod: dep-tree found %d names', [ModNames.Count]);
          except
            on E: Exception do
            begin
              DebugLogFmt('add-mod: dep-tree exception: %s', [E.Message]);
              Application.ShowExceptionMessage(E);
              if Application.Terminated then Break;
              Continue;
            end;
          end;
          try
            NameMap := TStringList.Create;
            try
              BuildProjectNameMap(RootPomDir, NameMap);
              DebugLogFmt('add-mod: name map has %d entries', [NameMap.Count]);
              SortedMods := TStringList.Create;
              try
                SortedMods.Duplicates := dupAccept;
                for I := 0 to ModNames.Count - 1 do
                begin
                  ModName   := ModNames[I];
                  AbsModDir := NameMap.Values[ModName];
                  if AbsModDir = '' then
                  begin
                    DebugLogFmt('add-mod: no dir for "%s"', [ModName]);
                    Continue;
                  end;
                  StorePath := ComputeRelativePath(ProjectDir,
                                 ExcludeTrailingPathDelimiter(AbsModDir));
                  if StorePath = '.' then Continue;
                  Already := P.ModuleDependencies.IndexOf(StorePath) >= 0;
                  if not Already then
                    SortedMods.Add(ModName + '=' + StorePath);
                end;
                DebugLogFmt('add-mod: %d items in picker', [SortedMods.Count]);
                SortedMods.Sort;
                for I := 0 to SortedMods.Count - 1 do
                begin
                  ModName   := SortedMods.Names[I];
                  StorePath := SortedMods.ValueFromIndex[I];
                  AddMenu.Add(TMenuItem.Create(ModName, nil, StorePath, #0, StorePath));
                end;
              finally
                SortedMods.Free;
              end;
            finally
              NameMap.Free;
            end;
          finally
            ModNames.Free;
          end;
          DebugLog('add-mod: discarding pending input');
          Term.DiscardPendingInput;
          DebugLogFmt('add-mod: pre-run terminated=%s',
            [BoolToStr(Application.Terminated, 'y', 'n')]);
          DebugLog('add-mod: showing picker');
          try
            AddSel := AddMenu.Run;
          except
            on E: Exception do
            begin
              DebugLogFmt('add-mod: EXCEPTION in Run: %s: %s',
                [E.ClassName, E.Message]);
              Application.ShowExceptionMessage(E);
              if Application.Terminated then Break;
              Continue;
            end;
          end;
          DebugLogFmt('add-mod: picker returned sel=%s terminated=%s unhandled="%s"',
            [BoolToStr(Assigned(AddSel), 'y', 'n'),
             BoolToStr(Application.Terminated, 'y', 'n'),
             AddMenu.UnhandledChar]);
          case CheckGlobalKeys(Ctx) of
            gkContinue: begin DebugLog('add-mod: gkContinue'); Continue; end;
            gkBreak:    begin DebugLog('add-mod: gkBreak');    Break;    end;
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
