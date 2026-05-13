{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Page.StringList;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  TermUI.Menu,
  PasbuildEditor.UIContext;

{ Generic string-list editor page: add, edit, delete string entries.
  ATitle is used as both the menu title and the header label. }
procedure RunStringListPage(Ctx: TUIContext; const ATitle: string;
  AList: TStringList);

implementation

uses
  PasbuildEditor.GlobalKeys;

procedure RunStringListPage(Ctx: TUIContext; const ATitle: string;
  AList: TStringList);
var
  SMenu: TMenu;
  SSel:  TMenuItem;
  SVal:  string;
  J:     Integer;
begin
  repeat
    SMenu := TMenu.Create(ATitle);
    try
      SMenu.AddHeader(ExtractFileName(ATitle) + ' (' + IntToStr(AList.Count) + ')');
      SMenu.AddSeparator;
      for J := 0 to AList.Count - 1 do
        SMenu.Add(TMenuItem.Create(AList[J], nil));
      SMenu.AddSeparator;
      SMenu.Add(TMenuItem.Create('Add entry', nil, '', 'A'));

      SSel := SMenu.Run;
      case CheckGlobalKeys(SMenu, Ctx, SSel) of
        gkContinue: Continue;
        gkBreak:    Break;
      end;
      if (SSel = nil) and (SMenu.UnhandledChar = #0) then Break;

      if SSel.Label_ = 'Add entry' then
      begin
        if EditLine('Value', '', SVal, SMenu.SelectedRow) and (SVal <> '') then
        begin
          if not IsValidIdentifier(SVal) then
            Confirm('Invalid identifier "' + SVal +
              '". Use A-Z, a-z, _ and digits (not first char).', False)
          else
          begin
            AList.Add(SVal);
            Ctx.SetModified;
          end;
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
        if EditLine('Edit', SVal, SVal, SMenu.SelectedRow) and (SVal <> '') and (SVal <> SSel.Label_) then
        begin
          if not IsValidIdentifier(SVal) then
            Confirm('Invalid identifier "' + SVal +
              '". Use A-Z, a-z, _ and digits (not first char).', False)
          else
          begin
            J := AList.IndexOf(SSel.Label_);
            if J >= 0 then begin AList[J] := SVal; Ctx.SetModified; end;
          end;
        end;
      end;
    finally
      SMenu.Free;
    end;
  until GQuitRequested or GCtrlCRequested or GCtrlXRequested;
end;

end.
