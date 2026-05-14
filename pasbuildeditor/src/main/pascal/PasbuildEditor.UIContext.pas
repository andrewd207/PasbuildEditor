{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.UIContext;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  TermUI.Terminal, TermUI.Menu, TermUI.Application,
  PasbuildEditor.ProjectModel,
  PasbuildEditor.DependencyResolver;

type
  TUIContext = class
  public
    Project:       TProjectBase;
    Breadcrumb:    string;
    Resolver:      TDependencyResolver;
    Modified:      Boolean;
    IsRoot:        Boolean;
    Parent:        TUIContext;
    ParentPOM:     TProjectPOM;
    LastMenuLabel: string;

    constructor Create(AProject: TProjectBase; const ABreadcrumb: string;
      AResolver: TDependencyResolver; AIsRoot: Boolean = False;
      AParent: TUIContext = nil; AParentPOM: TProjectPOM = nil);

    procedure SetModified;
    procedure SaveProject(ASilentSelf: Boolean = False; ASilentParent: Boolean = False);
    function  PromptSaveOnQuit: Boolean;
  end;

{ Application-level signal flags.
  Declared here (rather than GlobalKeys) to avoid a circular dependency:
  GlobalKeys already imports UIContext for TUIContext/CheckGlobalKeys. }
var
  GQuitRequested:  Boolean;
  GSaveRequested:  Boolean;
  GCtrlCRequested: Boolean;
  GCtrlXRequested: Boolean;

implementation

constructor TUIContext.Create(AProject: TProjectBase; const ABreadcrumb: string;
  AResolver: TDependencyResolver; AIsRoot: Boolean; AParent: TUIContext;
  AParentPOM: TProjectPOM);
begin
  inherited Create;
  Project    := AProject;
  Breadcrumb := ABreadcrumb;
  Resolver   := AResolver;
  Modified   := False;
  IsRoot     := AIsRoot;
  Parent     := AParent;
  ParentPOM  := AParentPOM;
end;

procedure TUIContext.SetModified;
begin
  Modified := True;
end;

procedure TUIContext.SaveProject(ASilentSelf: Boolean; ASilentParent: Boolean);
begin
  if Project.FileName = '' then Exit;
  try
    Project.SaveToFile;
    Modified := False;
    if not ASilentSelf then
    begin
      Term.InvalidateFront;
      Term.GotoXY(1, Term.Height - 1);
      Term.ClearToEOL;
      Term.SetFG(clGreen);
      Term.WriteStr(' Saved: ' + Project.FileName);
      Term.ResetColors;
      Term.FlushOutput;
      if Application.Terminated then
        Sleep(500)
      else
        Term.ReadKey;
    end;
  except
    on E: Exception do
    begin
      ShowStatusMsg('Error saving: ' + E.Message, clRed);
      Exit;
    end;
  end;
  if not ASilentSelf then
    if (Project.Version = '') and not Assigned(ParentPOM) then
      ShowStatusMsg('Warning: version is empty — consider setting a version for this standalone project.', clYellow);
  if Assigned(Parent) and Parent.Modified then
  begin
    if ASilentParent then
      Parent.SaveProject(True, True)
    else if Confirm('Parent project also has unsaved changes. Save parent now?', True) then
      Parent.SaveProject;
  end;
end;

function TUIContext.PromptSaveOnQuit: Boolean;
var
  K: TKeyEvent;
begin
  Result := True;
  if not Modified then Exit;

  Term.InvalidateFront;
  Term.GotoXY(1, Term.Height - 1);
  Term.ClearToEOL;
  Term.SetFG(clBrightYellow);
  Term.WriteStr(' Unsaved changes — [Enter/Y] Save & quit   [N] Discard   [Esc] Cancel ');
  Term.ResetColors;
  Term.ShowCursor;
  Term.FlushOutput;

  repeat
    K := Term.ReadKey;
    if K.Code = kcEnter then
    begin
      Term.HideCursor;
      SaveProject;
      Exit;
    end;
    if K.Code = kcChar then
      case UpCase(K.Ch) of
        'Y': begin Term.HideCursor; SaveProject; Exit; end;
        'N': begin Term.HideCursor; Exit; end;
      end;
    if K.Code = kcEscape then
    begin
      Term.HideCursor;
      GQuitRequested  := False;
      GCtrlCRequested := False;
      GCtrlXRequested := False;
      Application.Resume;
      Result := False;
      Exit;
    end;
    if K.Code = kcCtrlC then
    begin
      Term.HideCursor;
      GQuitRequested := True;
      Application.Terminate;
      Exit;
    end;
  until False;
end;

end.
