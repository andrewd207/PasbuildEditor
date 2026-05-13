{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Page.BootstrapExclude;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  TermUI.Menu,
  PasbuildEditor.ProjectModel,
  PasbuildEditor.UIContext;

procedure RunBootstrapExcludePage(Ctx: TUIContext; P: TProjectCommon);

implementation

uses
  StrUtils,
  TermUI.Terminal;

procedure RunBootstrapExcludePage(Ctx: TUIContext; P: TProjectCommon);
var
  Menu:      TMenu;
  Sel:       TMenuItem;
  It:        TMenuItem;
  SR:        TSearchRec;
  SrcDir:    string;
  LastLabel: string;
  I:         Integer;
  Seen:      TStringList;

  procedure ScanDir(const ADir: string);
  var
    InnerSR:  TSearchRec;
    UnitName: string;
    Line:     string;
    F:        TextFile;
    Excluded: Boolean;
  begin
    if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*.pas', faAnyFile, InnerSR) = 0 then
    try
      repeat
        if (InnerSR.Attr and faDirectory) <> 0 then Continue;
        UnitName := '';
        AssignFile(F, IncludeTrailingPathDelimiter(ADir) + InnerSR.Name);
        try
          Reset(F);
          while not EOF(F) and (UnitName = '') do
          begin
            ReadLn(F, Line);
            Line := Trim(Line);
            if SameText(Copy(Line, 1, 5), 'unit ') then
            begin
              UnitName := Trim(Copy(Line, 6, MaxInt));
              if (UnitName <> '') and (UnitName[Length(UnitName)] = ';') then
                Delete(UnitName, Length(UnitName), 1);
              UnitName := Trim(UnitName);
            end;
          end;
        except
        end;
        CloseFile(F);
        if UnitName = '' then Continue;
        if Seen.IndexOf(UnitName) >= 0 then Continue;
        Seen.Add(UnitName);
        Excluded := P.BootstrapExclude.IndexOf(UnitName) >= 0;
        It := TMenuItem.Create(UnitName, nil,
          IfThen(Excluded, '[x] excluded', '[ ] included'));
        It.DimValue := Excluded;
        Menu.Add(It);
      until FindNext(InnerSR) <> 0;
    finally
      FindClose(InnerSR);
    end;
    if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faDirectory, InnerSR) = 0 then
    try
      repeat
        if (InnerSR.Attr and faDirectory) = 0 then Continue;
        if (InnerSR.Name = '.') or (InnerSR.Name = '..') then Continue;
        ScanDir(IncludeTrailingPathDelimiter(ADir) + InnerSR.Name);
      until FindNext(InnerSR) <> 0;
    finally
      FindClose(InnerSR);
    end;
  end;

begin
  SrcDir := ExtractFilePath(ExpandFileName(Ctx.Project.FileName));
  if P.SourceDirectory <> '' then
    SrcDir := IncludeTrailingPathDelimiter(SrcDir) + P.SourceDirectory
  else
    SrcDir := IncludeTrailingPathDelimiter(SrcDir) + 'src/main/pascal';

  LastLabel := '';
  repeat
    Menu := TMenu.Create(Ctx.Breadcrumb + ' > Bootstrap exclude');
    try
      Menu.AddHeader('Bootstrap exclude — Enter to toggle');
      Menu.AddSeparator;

      Seen := TStringList.Create;
      try
        Seen.CaseSensitive := False;
        if FindFirst(SrcDir, faDirectory, SR) = 0 then
        begin
          FindClose(SR);
          ScanDir(SrcDir);
        end
        else
          Menu.Add(TMenuItem.Create('(no source directory found)', nil));
      finally
        Seen.Free;
      end;

      if LastLabel <> '' then Menu.SelectByLabel(LastLabel);
      Sel := Menu.Run;
      if GSaveRequested then begin Ctx.SaveProject; GSaveRequested := False; Continue; end;
      if GQuitRequested or GCtrlCRequested or GCtrlXRequested or
         ((Sel = nil) and (Menu.UnhandledChar = #0)) then Break;
      if Sel = nil then Continue;
      LastLabel := Sel.Label_;

      I := P.BootstrapExclude.IndexOf(Sel.Label_);
      if I >= 0 then
        P.BootstrapExclude.Delete(I)
      else
        P.BootstrapExclude.Add(Sel.Label_);
      Ctx.SetModified;
    finally
      Menu.Free;
    end;
  until GQuitRequested or GCtrlCRequested or GCtrlXRequested;
end;

end.
