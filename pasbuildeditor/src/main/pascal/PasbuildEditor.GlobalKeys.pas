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
  TermUI.Terminal, TermUI.Control, TermUI.Menu,
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

{ Install the application key handler into GOnUnhandledKey.
  Call once during startup (before entering the UI loop).
  Maps Ctrl+C → quit, Ctrl+S → save, Ctrl+X → save+quit. }
procedure InstallGlobalKeyHandler;

implementation

uses
  SysUtils,
  PasbuildEditor.Page.ShowHelp,
  PasbuildEditor.Dialog.About;

{ ── Application key router ── }

type
  TGlobalKeyRouter = class
    function HandleKey(Sender: TObject; var Key: TKeyEvent): Boolean;
  end;

function TGlobalKeyRouter.HandleKey(Sender: TObject; var Key: TKeyEvent): Boolean;
begin
  Result := False;
  case Key.Code of
    kcCtrlC: begin GCtrlCRequested := True; GQuitRequested := True; Result := True; end;
    kcCtrlS: begin GSaveRequested  := True;                         Result := True; end;
    kcCtrlX: begin GCtrlXRequested := True; GQuitRequested := True; Result := True; end;
  end;
end;

var
  GKeyRouter: TGlobalKeyRouter;

procedure InstallGlobalKeyHandler;
begin
  if GKeyRouter = nil then
    GKeyRouter := TGlobalKeyRouter.Create;
  GOnUnhandledKey := @GKeyRouter.HandleKey;
end;

{ ── CheckGlobalKeys ── }

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

finalization
  FreeAndNil(GKeyRouter);

end.
