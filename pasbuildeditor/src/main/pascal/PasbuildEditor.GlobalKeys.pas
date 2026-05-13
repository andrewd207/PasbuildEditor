{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.GlobalKeys;

{$mode objfpc}{$H+}

interface

uses
  TermUI.Menu,
  PasbuildEditor.UIContext;

type
  { Return value from CheckGlobalKeys.
    gkUnhandled — not a global key; Sel is valid and ready to dispatch.
    gkContinue  — global key consumed; caller should Continue the loop.
    gkBreak     — terminal signal received; caller should Break the loop. }
  TGlobalKeyResult = (gkUnhandled, gkContinue, gkBreak);

{ Handle the standard post-Menu.Run checks shared by every page loop:
  F1 help, F2 about, Ctrl-S save, and quit signals.
  Does NOT handle the (Sel = nil) → break case; each caller manages nil
  because the exact break/exit/continue behaviour differs per page.
  AHelpDoc is the adoc document name passed to ShowHelpPage (e.g. 'build').
  Pass '' if the page has no dedicated help document. }
function CheckGlobalKeys(Menu: TMenu; Ctx: TUIContext; Sel: TMenuItem;
  const AHelpDoc: string = ''): TGlobalKeyResult;

implementation

uses
  PasbuildEditor.Page.ShowHelp,
  PasbuildEditor.Dialog.About;

function CheckGlobalKeys(Menu: TMenu; Ctx: TUIContext; Sel: TMenuItem;
  const AHelpDoc: string): TGlobalKeyResult;
begin
  if Menu.F1Pressed then
  begin
    if Sel <> nil then
      ShowHelpPage(AHelpDoc, Sel.Label_)
    else
      ShowHelpPage(AHelpDoc, '');
    Exit(gkContinue);
  end;
  if Menu.F2Pressed then
  begin
    ShowAboutPage;
    Exit(gkContinue);
  end;
  if GSaveRequested then
  begin
    Ctx.SaveProject;
    GSaveRequested := False;
    Exit(gkContinue);
  end;
  if GQuitRequested or GCtrlCRequested or GCtrlXRequested then
    Exit(gkBreak);
  Result := gkUnhandled;
end;

end.
