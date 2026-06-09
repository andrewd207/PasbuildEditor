{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.UI;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  PBLib.ProjectModel,
  PasbuildEditor.DependencyResolver,
  PasbuildEditor.Dialog.PackageSearch;

{ Semver-aware comparison: returns >0 if A is newer than B. }
function CompareSemver(const A, B: string): Integer;

{ Sort a version list newest-first in place. }
procedure SortVersionsNewest(Versions: TPackageVersionList);

{ Full-screen package search + version picker.
  Returns True and sets AOutName / AOutVersion on success. }
function RunPackageSearch(AResolver: TDependencyResolver;
  out AOutName, AOutVersion: string;
  AExcludeNames: TStrings = nil;
  const ABreadcrumb: string = ''): Boolean;

{ Top-level entry point: build menus from AProject and run the UI loop. }
procedure RunUI(AProject: TProjectBase; AParentPOM: TProjectPOM = nil);

implementation

uses
  TermUI.Terminal,
  TermUI.Menu,
  TermUI.Application,
  PasbuildEditor.Consts,
  PasbuildEditor.GlobalKeys,
  PasbuildEditor.UIContext,
  PasbuildEditor.Page.Project;

type
  { One-shot idle driver: fires RunProjectUI on the first Application idle tick,
    then terminates the application loop. Owned and freed by RunUI. }
  TAppDriver = class
  private
    FCtx: TUIContext;
    FInside: Boolean;
  public
    constructor Create(ACtx: TUIContext);
    procedure OnIdle(Sender: TObject);
  end;

constructor TAppDriver.Create(ACtx: TUIContext);
begin
  inherited Create;
  FCtx := ACtx;
end;

procedure TAppDriver.OnIdle(Sender: TObject);
begin
  { Guard against re-entry: ProcessMessages keeps firing OnIdle inside any
    nested ShowModal loop, which would otherwise rebuild the UI from scratch
    on every idle tick. After a crash, Application.Run re-enters this handler
    naturally — the guard unwinds via the finally so recovery still works. }
  if FInside then Exit;
  FInside := True;
  try
    RunProjectUI(FCtx);
    Application.Terminate;
  finally
    FInside := False;
  end;
end;

{ Delegate semver helpers to Dialog.PackageSearch }

function CompareSemver(const A, B: string): Integer;
begin
  Result := PasbuildEditor.Dialog.PackageSearch.CompareSemver(A, B);
end;

procedure SortVersionsNewest(Versions: TPackageVersionList);
begin
  PasbuildEditor.Dialog.PackageSearch.SortVersionsNewest(Versions);
end;

function RunPackageSearch(AResolver: TDependencyResolver;
  out AOutName, AOutVersion: string;
  AExcludeNames: TStrings = nil;
  const ABreadcrumb: string = ''): Boolean;
begin
  Result := PasbuildEditor.Dialog.PackageSearch.RunPackageSearch(
    AResolver, AOutName, AOutVersion, AExcludeNames, ABreadcrumb);
end;

procedure RunUI(AProject: TProjectBase; AParentPOM: TProjectPOM = nil);
var
  Ctx:    TUIContext;
  Driver: TAppDriver;
begin
  AppTitle   := APP_TITLE;
  AppVersion := APP_VERSION;
  InstallGlobalKeyHandler;
  Term.EnableRawMode;
  Term.HideCursor;
  Term.EnterAltScreen;
  try
    Ctx := TUIContext.Create(AProject, AProject.Name, DefaultResolver,
                             True, nil, AParentPOM);
    try
      Driver := TAppDriver.Create(Ctx);
      try
        Application.OnIdle := @Driver.OnIdle;
        Application.Run;
      finally
        Driver.Free;
      end;
    finally
      Ctx.Free;
    end;
  finally
    Term.ExitAltScreen;
    Term.ShowCursor;
    Term.DisableRawMode;
  end;
end;

end.
