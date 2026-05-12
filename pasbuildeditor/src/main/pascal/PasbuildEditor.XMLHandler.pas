{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.XMLHandler;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, XMLRead, XMLWrite, DOM;

type
  TProjectType = (ptPOM, ptApplication, ptLibrary);

  TStringArray = array of string;

  TDependency = record
    Name: string;
    Version: string;
  end;

  TDependencyArray = array of TDependency;

  { A path with an optional platform condition, used for unitPaths and includePaths }
  TConditionalPath = record
    Path: string;
    Condition: string;
  end;

  TConditionalPathArray = array of TConditionalPath;

  { A POM child module path with optional activeByDefault flag }
  TModule = record
    Path: string;
    ActiveByDefault: Boolean;
  end;

  TModuleArray = array of TModule;

  TResources = record
    Directory: string;
    Filtering: Boolean;
  end;

  TBuildInfo = record
    ProjectType: TProjectType;
    MainSource: string;
    ExecutableName: string;         // application only
    OutputDirectory: string;        // default: target
    SourceDirectory: string;        // default: src/main/pascal
    ManualUnitPaths: Boolean;
    Defines: TStringArray;
    CompilerOptions: TStringArray;
    UnitPaths: TConditionalPathArray;
    IncludePaths: TConditionalPathArray;
    Resources: TResources;
    BootstrapExclude: TStringArray;
    SourcePackageIncludes: TStringArray;
  end;

  TTestInfo = record
    TestSource: string;             // default: TestRunner.pas
    SourceDirectory: string;        // default: src/test/pascal
    Framework: string;              // auto | fpcunit | fptest
    FrameworkOptions: TStringArray;
    Resources: TResources;
  end;

  TProfile = record
    ID: string;
    Defines: TStringArray;
    CompilerOptions: TStringArray;
  end;

  TProfileArray = array of TProfile;

  TChildProject = record
    Name: string;
    Version: string;
    Author: string;
    License: string;
    Description: string;
    ProjectUrl: string;
    RepoUrl: string;
    Profiles: TProfileArray;
    Build: TBuildInfo;
    Test: TTestInfo;
    Modules: TModuleArray;
    ModuleDependencies: TStringArray;
    Dependencies: TDependencyArray;
  end;

  TChildProjectArray = array of TChildProject;

  TProject = record
    Name: string;
    Version: string;
    Author: string;
    License: string;
    Description: string;
    ProjectUrl: string;
    RepoUrl: string;
    Profiles: TProfileArray;
    Build: TBuildInfo;
    Test: TTestInfo;
    Modules: TModuleArray;
    ModuleDependencies: TStringArray;
    Dependencies: TDependencyArray;
    ChildProjects: TChildProjectArray;
  end;

  TXMLHandler = class
  public
    function LoadProject(const FileName: string): TProject;
    procedure SaveProject(const Project: TProject; const FileName: string);
  end;

implementation

{ ---- Utility ---- }

function GetNodeText(Node: TDOMNode): string;
begin
  Result := '';
  if Assigned(Node) and Assigned(Node.FirstChild) then
    Result := Trim(Node.FirstChild.NodeValue);
end;

function GetChildText(Parent: TDOMNode; const ChildName: string;
  const Default: string = ''): string;
var
  Child: TDOMNode;
begin
  Result := Default;
  if not Assigned(Parent) then Exit;
  Child := Parent.FindNode(ChildName);
  if Assigned(Child) then
    Result := GetNodeText(Child);
end;

function StringToBool(const S: string): Boolean;
begin
  Result := (S = 'true') or (S = '1') or (S = 'yes');
end;

function StringToProjectType(const S: string): TProjectType;
begin
  case LowerCase(Trim(S)) of
    'pom':     Result := ptPOM;
    'library': Result := ptLibrary;
  else
    Result := ptApplication;
  end;
end;

function ProjectTypeToString(PT: TProjectType): string;
begin
  case PT of
    ptPOM:     Result := 'pom';
    ptLibrary: Result := 'library';
  else
    Result := 'application';
  end;
end;

function ParseStringArray(Parent: TDOMNode; const WrapperName, ItemName: string): TStringArray;
var
  Wrapper, Node: TDOMNode;
  List: TDOMNodeList;
  I: Integer;
begin
  Result := nil;
  if not Assigned(Parent) then Exit;
  Wrapper := Parent.FindNode(WrapperName);
  if not Assigned(Wrapper) then Exit;
  List := Wrapper.ChildNodes;
  for I := 0 to Integer(List.Count) - 1 do
  begin
    Node := List.Item[I];
    if Node.NodeName = ItemName then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := GetNodeText(Node);
    end;
  end;
end;

function ParseFlatStringArray(Parent: TDOMNode; const ItemName: string): TStringArray;
var
  List: TDOMNodeList;
  Node: TDOMNode;
  I: Integer;
begin
  Result := nil;
  if not Assigned(Parent) then Exit;
  List := Parent.ChildNodes;
  for I := 0 to Integer(List.Count) - 1 do
  begin
    Node := List.Item[I];
    if Node.NodeName = ItemName then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := GetNodeText(Node);
    end;
  end;
end;

function ParseConditionalPaths(Parent: TDOMNode; const WrapperName: string): TConditionalPathArray;
var
  Wrapper, Node: TDOMNode;
  List: TDOMNodeList;
  PathValue, Condition: string;
  I: Integer;
begin
  Result := nil;
  if not Assigned(Parent) then Exit;
  Wrapper := Parent.FindNode(WrapperName);
  if not Assigned(Wrapper) then Exit;
  List := Wrapper.ChildNodes;
  for I := 0 to Integer(List.Count) - 1 do
  begin
    Node := List.Item[I];
    if Node.NodeName <> 'path' then Continue;
    PathValue := GetNodeText(Node);
    if PathValue = '' then Continue;
    Condition := '';
    if Node is TDOMElement then
      Condition := Trim(TDOMElement(Node).GetAttribute('condition'));
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Path      := PathValue;
    Result[High(Result)].Condition := Condition;
  end;
end;

function ParseDependencyArray(Parent: TDOMNode): TDependencyArray;
var
  DepsNode, Node: TDOMNode;
  List: TDOMNodeList;
  I: Integer;
begin
  Result := nil;
  if not Assigned(Parent) then Exit;
  DepsNode := Parent.FindNode('dependencies');
  if not Assigned(DepsNode) then Exit;
  List := DepsNode.ChildNodes;
  for I := 0 to Integer(List.Count) - 1 do
  begin
    Node := List.Item[I];
    if Node.NodeName <> 'dependency' then Continue;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Name    := GetChildText(Node, 'name');
    Result[High(Result)].Version := GetChildText(Node, 'version');
  end;
end;

function ParseModuleArray(Parent: TDOMNode; const WrapperName: string): TModuleArray;
var
  Wrapper, Node: TDOMNode;
  List: TDOMNodeList;
  ActiveStr: string;
  I: Integer;
begin
  Result := nil;
  if not Assigned(Parent) then Exit;
  Wrapper := Parent.FindNode(WrapperName);
  if not Assigned(Wrapper) then Exit;
  List := Wrapper.ChildNodes;
  for I := 0 to Integer(List.Count) - 1 do
  begin
    Node := List.Item[I];
    if Node.NodeName <> 'module' then Continue;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Path := GetNodeText(Node);
    Result[High(Result)].ActiveByDefault := True;
    if Node is TDOMElement then
    begin
      ActiveStr := LowerCase(Trim(TDOMElement(Node).GetAttribute('activeByDefault')));
      if ActiveStr = 'false' then
        Result[High(Result)].ActiveByDefault := False;
    end;
  end;
end;

function ParseModuleDependencies(Parent: TDOMNode): TStringArray;
var
  Wrapper, Node: TDOMNode;
  List: TDOMNodeList;
  I: Integer;
begin
  Result := nil;
  if not Assigned(Parent) then Exit;
  Wrapper := Parent.FindNode('moduleDependencies');
  if not Assigned(Wrapper) then Exit;
  List := Wrapper.ChildNodes;
  for I := 0 to Integer(List.Count) - 1 do
  begin
    Node := List.Item[I];
    if Node.NodeName = 'module' then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := GetNodeText(Node);
    end;
  end;
end;

function ParseResources(Parent: TDOMNode): TResources;
var
  ResNode: TDOMNode;
begin
  Result.Directory := '';
  Result.Filtering := False;
  if not Assigned(Parent) then Exit;
  ResNode := Parent.FindNode('resources');
  if not Assigned(ResNode) then Exit;
  Result.Directory := GetChildText(ResNode, 'directory');
  Result.Filtering := StringToBool(GetChildText(ResNode, 'filtering'));
end;

{ ---- Read helpers ---- }

function ReadBuildInfo(BuildNode: TDOMNode): TBuildInfo;
var
  PackagingStr: string;
begin
  // <packaging> preferred; <projectType> accepted for backward compatibility
  PackagingStr := GetChildText(BuildNode, 'packaging');
  if PackagingStr <> '' then
    Result.ProjectType := StringToProjectType(PackagingStr)
  else
    Result.ProjectType := StringToProjectType(GetChildText(BuildNode, 'projectType', 'application'));

  Result.MainSource      := GetChildText(BuildNode, 'mainSource');
  Result.ExecutableName  := GetChildText(BuildNode, 'executableName');
  Result.OutputDirectory := GetChildText(BuildNode, 'outputDirectory', 'target');
  Result.SourceDirectory := GetChildText(BuildNode, 'sourceDirectory', 'src/main/pascal');
  Result.ManualUnitPaths := StringToBool(GetChildText(BuildNode, 'manualUnitPaths'));

  Result.Defines             := ParseStringArray(BuildNode, 'defines', 'define');
  Result.CompilerOptions     := ParseStringArray(BuildNode, 'compilerOptions', 'option');
  Result.UnitPaths           := ParseConditionalPaths(BuildNode, 'unitPaths');
  Result.IncludePaths        := ParseConditionalPaths(BuildNode, 'includePaths');
  Result.Resources           := ParseResources(BuildNode);
  Result.BootstrapExclude    := ParseStringArray(BuildNode, 'bootstrapExclude', 'unit');
  Result.SourcePackageIncludes := ParseStringArray(BuildNode, 'sourcePackage', 'include');
end;

function ReadTestInfo(TestNode: TDOMNode): TTestInfo;
begin
  Result.TestSource      := GetChildText(TestNode, 'testSource', 'TestRunner.pas');
  Result.SourceDirectory := GetChildText(TestNode, 'testSourceDirectory', 'src/test/pascal');
  Result.Framework       := GetChildText(TestNode, 'framework');
  Result.FrameworkOptions := ParseStringArray(TestNode, 'frameworkOptions', 'option');
  Result.Resources       := ParseResources(TestNode);
end;

function ReadProfiles(ProfilesNode: TDOMNode): TProfileArray;
var
  List: TDOMNodeList;
  Node: TDOMNode;
  I: Integer;
begin
  Result := nil;
  if not Assigned(ProfilesNode) then Exit;
  List := ProfilesNode.ChildNodes;
  for I := 0 to Integer(List.Count) - 1 do
  begin
    Node := List.Item[I];
    if Node.NodeName <> 'profile' then Continue;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].ID             := GetChildText(Node, 'id');
    Result[High(Result)].Defines        := ParseStringArray(Node, 'defines', 'define');
    Result[High(Result)].CompilerOptions := ParseStringArray(Node, 'compilerOptions', 'option');
  end;
end;

procedure ReadProjectFields(Node: TDOMNode;
  out Name, Version, Author, License, Description, ProjectUrl, RepoUrl: string;
  out Profiles: TProfileArray;
  out Build: TBuildInfo;
  out Test: TTestInfo;
  out Modules: TModuleArray;
  out ModuleDependencies: TStringArray;
  out Dependencies: TDependencyArray);
var
  BuildNode, TestNode, ProfilesNode: TDOMNode;
begin
  Name        := GetChildText(Node, 'name');
  Version     := GetChildText(Node, 'version');
  Author      := GetChildText(Node, 'author', 'Unknown');
  License     := GetChildText(Node, 'license', 'Proprietary');
  Description := GetChildText(Node, 'description');
  ProjectUrl  := GetChildText(Node, 'projectUrl');
  RepoUrl     := GetChildText(Node, 'repoUrl');

  ProfilesNode := Node.FindNode('profiles');
  Profiles := ReadProfiles(ProfilesNode);

  BuildNode := Node.FindNode('build');
  if Assigned(BuildNode) then
    Build := ReadBuildInfo(BuildNode);

  TestNode := Node.FindNode('test');
  if Assigned(TestNode) then
    Test := ReadTestInfo(TestNode);

  Modules            := ParseModuleArray(Node, 'modules');
  ModuleDependencies := ParseModuleDependencies(Node);
  Dependencies       := ParseDependencyArray(Node);
end;

function ReadChildProjects(Root: TDOMNode): TChildProjectArray;
var
  List: TDOMNodeList;
  Node: TDOMNode;
  I: Integer;
begin
  Result := nil;
  if not Assigned(Root) then Exit;
  List := Root.ChildNodes;
  for I := 0 to Integer(List.Count) - 1 do
  begin
    Node := List.Item[I];
    if Node.NodeName <> 'project' then Continue;
    SetLength(Result, Length(Result) + 1);
    with Result[High(Result)] do
      ReadProjectFields(Node, Name, Version, Author, License, Description,
        ProjectUrl, RepoUrl, Profiles, Build, Test,
        Modules, ModuleDependencies, Dependencies);
  end;
end;

{ ---- Write helpers ---- }

procedure AddTextElement(Doc: TXMLDocument; Parent: TDOMNode;
  const ElemName, Value: string);
var
  Elem: TDOMElement;
begin
  Elem := Doc.CreateElement(ElemName);
  Elem.AppendChild(Doc.CreateTextNode(Value));
  Parent.AppendChild(Elem);
end;

procedure WriteStringArray(Doc: TXMLDocument; Parent: TDOMNode;
  const WrapperName, ItemName: string; const Items: TStringArray);
var
  Wrapper: TDOMElement;
  I: Integer;
begin
  if Length(Items) = 0 then Exit;
  Wrapper := Doc.CreateElement(WrapperName);
  Parent.AppendChild(Wrapper);
  for I := 0 to High(Items) do
    AddTextElement(Doc, Wrapper, ItemName, Items[I]);
end;

procedure WriteConditionalPaths(Doc: TXMLDocument; Parent: TDOMNode;
  const WrapperName: string; const Paths: TConditionalPathArray);
var
  Wrapper, PathNode: TDOMElement;
  I: Integer;
begin
  if Length(Paths) = 0 then Exit;
  Wrapper := Doc.CreateElement(WrapperName);
  Parent.AppendChild(Wrapper);
  for I := 0 to High(Paths) do
  begin
    PathNode := Doc.CreateElement('path');
    Wrapper.AppendChild(PathNode);
    if Paths[I].Condition <> '' then
      PathNode.SetAttribute('condition', Paths[I].Condition);
    PathNode.AppendChild(Doc.CreateTextNode(Paths[I].Path));
  end;
end;

procedure WriteResources(Doc: TXMLDocument; Parent: TDOMNode;
  const Resources: TResources);
var
  ResNode: TDOMElement;
  HasContent: Boolean;
begin
  HasContent := Resources.Filtering or (Resources.Directory <> '');
  if not HasContent then Exit;
  ResNode := Doc.CreateElement('resources');
  Parent.AppendChild(ResNode);
  if Resources.Directory <> '' then
    AddTextElement(Doc, ResNode, 'directory', Resources.Directory);
  if Resources.Filtering then
    AddTextElement(Doc, ResNode, 'filtering', 'true');
end;

procedure WriteBuildInfo(Doc: TXMLDocument; Parent: TDOMNode;
  const Build: TBuildInfo);
var
  BuildNode: TDOMElement;
begin
  BuildNode := Doc.CreateElement('build');
  Parent.AppendChild(BuildNode);

  AddTextElement(Doc, BuildNode, 'packaging', ProjectTypeToString(Build.ProjectType));

  if Build.MainSource <> '' then
    AddTextElement(Doc, BuildNode, 'mainSource', Build.MainSource);
  if Build.ExecutableName <> '' then
    AddTextElement(Doc, BuildNode, 'executableName', Build.ExecutableName);
  if (Build.OutputDirectory <> '') and (Build.OutputDirectory <> 'target') then
    AddTextElement(Doc, BuildNode, 'outputDirectory', Build.OutputDirectory);
  if (Build.SourceDirectory <> '') and (Build.SourceDirectory <> 'src/main/pascal') then
    AddTextElement(Doc, BuildNode, 'sourceDirectory', Build.SourceDirectory);
  if Build.ManualUnitPaths then
    AddTextElement(Doc, BuildNode, 'manualUnitPaths', 'true');

  WriteStringArray(Doc, BuildNode, 'defines', 'define', Build.Defines);
  WriteStringArray(Doc, BuildNode, 'compilerOptions', 'option', Build.CompilerOptions);
  WriteConditionalPaths(Doc, BuildNode, 'unitPaths', Build.UnitPaths);
  WriteConditionalPaths(Doc, BuildNode, 'includePaths', Build.IncludePaths);
  WriteResources(Doc, BuildNode, Build.Resources);
  WriteStringArray(Doc, BuildNode, 'bootstrapExclude', 'unit', Build.BootstrapExclude);
  WriteStringArray(Doc, BuildNode, 'sourcePackage', 'include', Build.SourcePackageIncludes);
end;

procedure WriteTestInfo(Doc: TXMLDocument; Parent: TDOMNode;
  const Test: TTestInfo);
var
  TestNode: TDOMElement;
  HasContent: Boolean;
begin
  HasContent := (Test.TestSource <> '') or (Test.Framework <> '') or
                (Length(Test.FrameworkOptions) > 0) or
                Test.Resources.Filtering or (Test.Resources.Directory <> '');
  if not HasContent then Exit;
  TestNode := Doc.CreateElement('test');
  Parent.AppendChild(TestNode);
  if Test.TestSource <> '' then
    AddTextElement(Doc, TestNode, 'testSource', Test.TestSource);
  if (Test.SourceDirectory <> '') and (Test.SourceDirectory <> 'src/test/pascal') then
    AddTextElement(Doc, TestNode, 'testSourceDirectory', Test.SourceDirectory);
  if Test.Framework <> '' then
    AddTextElement(Doc, TestNode, 'framework', Test.Framework);
  WriteStringArray(Doc, TestNode, 'frameworkOptions', 'option', Test.FrameworkOptions);
  WriteResources(Doc, TestNode, Test.Resources);
end;

procedure WriteProfiles(Doc: TXMLDocument; Parent: TDOMNode;
  const Profiles: TProfileArray);
var
  ProfilesNode, ProfileNode: TDOMElement;
  I: Integer;
begin
  if Length(Profiles) = 0 then Exit;
  ProfilesNode := Doc.CreateElement('profiles');
  Parent.AppendChild(ProfilesNode);
  for I := 0 to High(Profiles) do
  begin
    ProfileNode := Doc.CreateElement('profile');
    ProfilesNode.AppendChild(ProfileNode);
    AddTextElement(Doc, ProfileNode, 'id', Profiles[I].ID);
    WriteStringArray(Doc, ProfileNode, 'defines', 'define', Profiles[I].Defines);
    WriteStringArray(Doc, ProfileNode, 'compilerOptions', 'option', Profiles[I].CompilerOptions);
  end;
end;

procedure WriteModules(Doc: TXMLDocument; Parent: TDOMNode;
  const Modules: TModuleArray);
var
  ModulesNode, ModNode: TDOMElement;
  I: Integer;
begin
  if Length(Modules) = 0 then Exit;
  ModulesNode := Doc.CreateElement('modules');
  Parent.AppendChild(ModulesNode);
  for I := 0 to High(Modules) do
  begin
    ModNode := Doc.CreateElement('module');
    ModulesNode.AppendChild(ModNode);
    if not Modules[I].ActiveByDefault then
      ModNode.SetAttribute('activeByDefault', 'false');
    ModNode.AppendChild(Doc.CreateTextNode(Modules[I].Path));
  end;
end;

procedure WriteModuleDependencies(Doc: TXMLDocument; Parent: TDOMNode;
  const Paths: TStringArray);
var
  Wrapper: TDOMElement;
  I: Integer;
begin
  if Length(Paths) = 0 then Exit;
  Wrapper := Doc.CreateElement('moduleDependencies');
  Parent.AppendChild(Wrapper);
  for I := 0 to High(Paths) do
    AddTextElement(Doc, Wrapper, 'module', Paths[I]);
end;

procedure WriteDependencies(Doc: TXMLDocument; Parent: TDOMNode;
  const Dependencies: TDependencyArray);
var
  DepsNode, DepNode: TDOMElement;
  I: Integer;
begin
  if Length(Dependencies) = 0 then Exit;
  DepsNode := Doc.CreateElement('dependencies');
  Parent.AppendChild(DepsNode);
  for I := 0 to High(Dependencies) do
  begin
    DepNode := Doc.CreateElement('dependency');
    DepsNode.AppendChild(DepNode);
    AddTextElement(Doc, DepNode, 'name',    Dependencies[I].Name);
    AddTextElement(Doc, DepNode, 'version', Dependencies[I].Version);
  end;
end;

procedure WriteProjectFields(Doc: TXMLDocument; ProjectNode: TDOMNode;
  const Name, Version, Author, License, Description, ProjectUrl, RepoUrl: string;
  const Profiles: TProfileArray;
  const Build: TBuildInfo;
  const Test: TTestInfo;
  const Modules: TModuleArray;
  const ModuleDependencies: TStringArray;
  const Dependencies: TDependencyArray);
begin
  AddTextElement(Doc, ProjectNode, 'name', Name);
  if Version <> '' then
    AddTextElement(Doc, ProjectNode, 'version', Version);
  AddTextElement(Doc, ProjectNode, 'author',  Author);
  AddTextElement(Doc, ProjectNode, 'license', License);
  if Description <> '' then
    AddTextElement(Doc, ProjectNode, 'description', Description);
  if ProjectUrl <> '' then
    AddTextElement(Doc, ProjectNode, 'projectUrl', ProjectUrl);
  if RepoUrl <> '' then
    AddTextElement(Doc, ProjectNode, 'repoUrl', RepoUrl);
  WriteProfiles(Doc, ProjectNode, Profiles);
  WriteBuildInfo(Doc, ProjectNode, Build);
  WriteTestInfo(Doc, ProjectNode, Test);
  WriteModules(Doc, ProjectNode, Modules);
  WriteModuleDependencies(Doc, ProjectNode, ModuleDependencies);
  WriteDependencies(Doc, ProjectNode, Dependencies);
end;

{ ---- TXMLHandler ---- }

function TXMLHandler.LoadProject(const FileName: string): TProject;
var
  Doc: TXMLDocument;
  Root: TDOMNode;
begin
  ReadXMLFile(Doc, FileName);
  try
    Root := Doc.DocumentElement;
    if not Assigned(Root) or (Root.NodeName <> 'project') then
      raise Exception.Create('Invalid project.xml: missing <project> root element');

    ReadProjectFields(Root,
      Result.Name, Result.Version, Result.Author, Result.License,
      Result.Description, Result.ProjectUrl, Result.RepoUrl,
      Result.Profiles, Result.Build, Result.Test,
      Result.Modules, Result.ModuleDependencies, Result.Dependencies);

    Result.ChildProjects := ReadChildProjects(Root);
  finally
    Doc.Free;
  end;
end;

procedure TXMLHandler.SaveProject(const Project: TProject; const FileName: string);
var
  Doc: TXMLDocument;
  Root, ChildNode: TDOMElement;
  I: Integer;
begin
  Doc := TXMLDocument.Create;
  try
    Root := Doc.CreateElement('project');
    Doc.AppendChild(Root);

    WriteProjectFields(Doc, Root,
      Project.Name, Project.Version, Project.Author, Project.License,
      Project.Description, Project.ProjectUrl, Project.RepoUrl,
      Project.Profiles, Project.Build, Project.Test,
      Project.Modules, Project.ModuleDependencies, Project.Dependencies);

    for I := 0 to High(Project.ChildProjects) do
    begin
      ChildNode := Doc.CreateElement('project');
      Root.AppendChild(ChildNode);
      with Project.ChildProjects[I] do
        WriteProjectFields(Doc, ChildNode,
          Name, Version, Author, License,
          Description, ProjectUrl, RepoUrl,
          Profiles, Build, Test,
          Modules, ModuleDependencies, Dependencies);
    end;

    WriteXMLFile(Doc, FileName);
  finally
    Doc.Free;
  end;
end;

end.
