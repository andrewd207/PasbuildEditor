{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.

  JSON serialization helpers for project.xml data model.
  All public functions return a TJSONObject that the caller owns.
  Use PrintJSON to write to stdout and free in one step.
}
unit PBLib.JSON;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson,
  PBLib.ProjectModel;

{ Serialize a full project to JSON.
  AModuleName and AProjectFile are optional context fields added to the root object. }
function ProjectToJSON(AProject: TProjectBase;
  const AModuleName: string = ''; const AProjectFile: string = ''): TJSONObject;

{ Build an error response.  AModules (optional) lists available module names. }
function ErrorJSON(const AMsg: string; AModules: TStringList = nil): TJSONObject;

{ Build a success response with an optional message. }
function OkJSON(const AMsg: string = ''): TJSONObject;

{ Write formatted JSON to stdout and free AObj. }
procedure PrintJSON(AObj: TJSONObject);

{ Write formatted JSON to stderr and free AObj (for status during interactive ops). }
procedure PrintJSONErr(AObj: TJSONObject);

implementation

function StringListToArray(AList: TStringList): TJSONArray;
var
  I: Integer;
begin
  Result := TJSONArray.Create;
  for I := 0 to AList.Count - 1 do
    Result.Add(AList[I]);
end;

function ConditionalPathsToArray(APaths: TConditionalPathList): TJSONArray;
var
  I: Integer;
  Item: TJSONObject;
  CP: TConditionalPath;
begin
  Result := TJSONArray.Create;
  for I := 0 to APaths.Count - 1 do
  begin
    CP := APaths[I];
    if CP.Condition = '' then
      Result.Add(CP.Path)
    else
    begin
      Item := TJSONObject.Create;
      Item.Add('path', CP.Path);
      Item.Add('condition', CP.Condition);
      Result.Add(Item);
    end;
  end;
end;

function DependenciesToArray(ADeps: TDependencyList): TJSONArray;
var
  I: Integer;
  Item: TJSONObject;
  D: TDependency;
begin
  Result := TJSONArray.Create;
  for I := 0 to ADeps.Count - 1 do
  begin
    D    := ADeps[I];
    Item := TJSONObject.Create;
    Item.Add('name', D.Name);
    Item.Add('version', D.Version);
    Result.Add(Item);
  end;
end;

function ProfilesToArray(AProfiles: TProfileList): TJSONArray;
var
  I: Integer;
  Item: TJSONObject;
  P: TProfile;
begin
  Result := TJSONArray.Create;
  for I := 0 to AProfiles.Count - 1 do
  begin
    P    := AProfiles[I];
    Item := TJSONObject.Create;
    Item.Add('id', P.ID);
    Item.Add('defines', StringListToArray(P.Defines));
    Item.Add('compilerOptions', StringListToArray(P.CompilerOptions));
    Result.Add(Item);
  end;
end;

function ResourcesConfigToJSON(ARes: TResourcesConfig): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('directory', ARes.Directory);
  Result.Add('filtering', ARes.Filtering);
end;

function ModulesToArray(APOM: TProjectPOM): TJSONArray;
var
  I: Integer;
  Item: TJSONObject;
begin
  Result := TJSONArray.Create;
  for I := 0 to APOM.Modules.Count - 1 do
  begin
    Item := TJSONObject.Create;
    Item.Add('path', APOM.Modules[I].Path);
    Item.Add('activeByDefault', APOM.Modules[I].ActiveByDefault);
    Result.Add(Item);
  end;
end;

function ProjectToJSON(AProject: TProjectBase;
  const AModuleName: string; const AProjectFile: string): TJSONObject;
var
  ProjectObj, BuildObj, TestObj: TJSONObject;
  Common: TProjectCommon;
begin
  Result := TJSONObject.Create;
  if AModuleName <> '' then
    Result.Add('module', AModuleName);
  if AProjectFile <> '' then
    Result.Add('projectFile', AProjectFile);

  ProjectObj := TJSONObject.Create;
  ProjectObj.Add('name',        AProject.Name);
  ProjectObj.Add('version',     AProject.Version);
  ProjectObj.Add('author',      AProject.Author);
  ProjectObj.Add('license',     AProject.License);
  ProjectObj.Add('description', AProject.Description);
  ProjectObj.Add('projectUrl',  AProject.ProjectUrl);
  ProjectObj.Add('repoUrl',     AProject.RepoUrl);
  ProjectObj.Add('packaging',   AProject.ProjectTypeLabel);
  ProjectObj.Add('profiles',    ProfilesToArray(AProject.Profiles));

  if AProject is TProjectPOM then
    ProjectObj.Add('modules', ModulesToArray(TProjectPOM(AProject)))
  else if AProject is TProjectCommon then
  begin
    Common := TProjectCommon(AProject);

    BuildObj := TJSONObject.Create;
    BuildObj.Add('mainSource',           Common.MainSource);
    BuildObj.Add('executableName',       Common.ExecutableName);
    BuildObj.Add('outputDirectory',      Common.OutputDirectory);
    BuildObj.Add('sourceDirectory',      Common.SourceDirectory);
    BuildObj.Add('manualUnitPaths',      Common.ManualUnitPaths);
    BuildObj.Add('defines',              StringListToArray(Common.Defines));
    BuildObj.Add('compilerOptions',      StringListToArray(Common.CompilerOptions));
    BuildObj.Add('unitPaths',            ConditionalPathsToArray(Common.UnitPaths));
    BuildObj.Add('includePaths',         ConditionalPathsToArray(Common.IncludePaths));
    BuildObj.Add('bootstrapExclude',     StringListToArray(Common.BootstrapExclude));
    BuildObj.Add('sourcePackageIncludes',StringListToArray(Common.SourcePackageIncludes));
    BuildObj.Add('resources',            ResourcesConfigToJSON(Common.BuildResources));
    ProjectObj.Add('build', BuildObj);

    TestObj := TJSONObject.Create;
    TestObj.Add('testSource',          Common.TestSource);
    TestObj.Add('testSourceDirectory', Common.TestSourceDirectory);
    TestObj.Add('framework',           Common.TestFramework);
    TestObj.Add('frameworkOptions',    StringListToArray(Common.FrameworkOptions));
    TestObj.Add('resources',           ResourcesConfigToJSON(Common.TestResources));
    ProjectObj.Add('test', TestObj);

    ProjectObj.Add('moduleDependencies', StringListToArray(Common.ModuleDependencies));
    ProjectObj.Add('dependencies',       DependenciesToArray(Common.Dependencies));
  end;

  Result.Add('project', ProjectObj);
end;

function ErrorJSON(const AMsg: string; AModules: TStringList): TJSONObject;
var
  Arr: TJSONArray;
  I: Integer;
begin
  Result := TJSONObject.Create;
  Result.Add('error', AMsg);
  if Assigned(AModules) and (AModules.Count > 0) then
  begin
    Arr := TJSONArray.Create;
    for I := 0 to AModules.Count - 1 do
      Arr.Add(AModules[I]);
    Result.Add('availableModules', Arr);
  end;
end;

function OkJSON(const AMsg: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('ok', True);
  if AMsg <> '' then
    Result.Add('message', AMsg);
end;

procedure PrintJSON(AObj: TJSONObject);
begin
  WriteLn(AObj.FormatJSON);
  AObj.Free;
end;

procedure PrintJSONErr(AObj: TJSONObject);
begin
  WriteLn(ErrOutput, AObj.FormatJSON);
  AObj.Free;
end;

end.
