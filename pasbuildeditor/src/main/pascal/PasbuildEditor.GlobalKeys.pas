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
  TermUI.Terminal, TermUI.Control, TermUI.Menu, TermUI.Application,
  PasbuildEditor.UIContext;

type
  { Return value from CheckGlobalKeys.
    gkUnhandled — not a global key; Sel is valid and ready to dispatch.
    gkContinue  — global key consumed; caller should Continue the loop.
    gkBreak     — terminal signal received; caller should Break the loop. }
  TGlobalKeyResult = (gkUnhandled, gkContinue, gkBreak);

{ Handle the standard post-Menu.Run checks shared by every page loop:
  Ctrl-S save and quit signals. F1/F2 are now handled by the global key router
  and do not reach individual page loops. }
function CheckGlobalKeys(Ctx: TUIContext): TGlobalKeyResult;

{ Install the application key handler into Application.OnKeyDown.
  Call once during startup (before entering the UI loop).
  Maps Ctrl+C → quit, Ctrl+S → save, Ctrl+X → save+quit. }
procedure InstallGlobalKeyHandler;

implementation

uses
  SysUtils,
  TermUI.Forms,
  TermUI.Debug.Overlay,
  PasbuildEditor.Page.ShowHelp,
  PasbuildEditor.Dialog.About;

{ ── Application key router ── }

type
  TGlobalKeyRouter = class
    function HandleKey(Sender: TObject; var Key: TKeyEvent): Boolean;
  end;

function TGlobalKeyRouter.HandleKey(Sender: TObject; var Key: TKeyEvent): Boolean;
var
  AF: TForm;
begin
  Result := False;
  case Key.Code of
    kcF1: begin
      AF := Application.ActiveForm;
      if AF is TMenu then
        ShowHelpPage(TMenu(AF).HelpDoc, TMenu(AF).SelectedLabel);
      Result := True;
    end;
    kcF2: begin
      ShowAboutPage;
      Result := True;
    end;
    kcF12: begin
      DebugOverlay.Toggle;
      Result := True;
    end;
    kcCtrlC: begin
      GCtrlCRequested := True;
      GQuitRequested  := True;
      Application.Terminate;
      Result := True;
    end;
    kcCtrlS: begin
      GSaveRequested := True;
      Result := True;
    end;
    kcCtrlX: begin
      GCtrlXRequested := True;
      GQuitRequested  := True;
      Application.Terminate;
      Result := True;
    end;
  end;
end;

var
  GKeyRouter: TGlobalKeyRouter;

procedure InstallGlobalKeyHandler;
begin
  if GKeyRouter = nil then
    GKeyRouter := TGlobalKeyRouter.Create;
  Application.OnKeyDown := @GKeyRouter.HandleKey;
end;

{ ── CheckGlobalKeys ── }

function CheckGlobalKeys(Ctx: TUIContext): TGlobalKeyResult;
begin
  if GSaveRequested then
  begin
    Ctx.SaveProject;
    GSaveRequested := False;
    Exit(gkContinue);
  end;
  if Application.Terminated then
    Exit(gkBreak);
  Result := gkUnhandled;
end;

finalization
  FreeAndNil(GKeyRouter);

end.
