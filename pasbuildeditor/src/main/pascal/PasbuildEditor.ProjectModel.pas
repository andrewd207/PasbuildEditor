unit PasbuildEditor.ProjectModel;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DOM, XMLRead, XMLWrite, fgl;

type
  TProjectType = (ptApplication, ptLibrary, ptPOM);

  { Forward declarations }
  TProjectBase    = class;
  TProjectPOM     = class;
  TProjectCommon  = class;

  { A path with an optional platform condition }
  TConditionalPath = class
  public
    Path: string;
    Condition: string;
    Node: TDOMNode;
    constructor Create(const APath, ACondition: string; ANode: TDOMNode = nil);
  end;
  TConditionalPathList = specialize TFPGObjectList<TConditionalPath>;

  { A build profile with defines and compiler options }
  TProfile = class
  public
    ID: string;
    Defines: TStringList;
    CompilerOptions: TStringList;
    Node: TDOMNode;
    constructor Create;
    destructor Destroy; override;
  end;
  TProfileList = specialize TFPGObjectList<TProfile>;

  { A POM child module path (not a dependency — a sub-project reference) }
  TModule = class
  public
    Path: string;
    ActiveByDefault: Boolean;
    Node: TDOMNode;
    constructor Create(const APath: string; AActiveByDefault: Boolean = True;
      ANode: TDOMNode = nil);
  end;
  TModuleList = specialize TFPGObjectList<TModule>;

  { An external repository dependency }
  TDependency = class
  public
    Name: string;
    Version: string;
    Node: TDOMNode;
    constructor Create(const AName, AVersion: string; ANode: TDOMNode = nil);
  end;
  TDependencyList = specialize TFPGObjectList<TDependency>;

  { Resources configuration (appears inside <build> and <test>) }
  TResourcesConfig = class
  public
    Directory: string;
    Filtering: Boolean;
    Node: TDOMNode;
    constructor Create;
  end;

  { Base class — fields present on all project types }
  TProjectBase = class
  private
    FDocument: TXMLDocument;  // non-nil only for the root (file-owning) project
    FNode: TDOMNode;
    FFileName: string;
    FName: string;
    FVersion: string;
    FAuthor: string;
    FLicense: string;
    FDescription: string;
    FProjectUrl: string;
    FRepoUrl: string;
    FProfiles: TProfileList;
  protected
    procedure LoadBaseFields;
    procedure LoadProfiles;
    procedure SaveBaseFields;
    procedure SaveProfiles;
  public
    constructor Create(ANode: TDOMNode; ADocument: TXMLDocument = nil);
    destructor Destroy; override;

    { Load from file — detects project type and returns appropriate subclass }
    class function LoadFromFile(const AFileName: string): TProjectBase;

    { Save — writes all in-memory changes back into the DOM, then flushes to disk.
      Only valid on the root project (the one that owns FDocument). }
    procedure SaveToFile(const AFileName: string = '');

    procedure LoadFromNode; virtual;
    procedure SaveToNode; virtual;

    function ProjectType: TProjectType; virtual; abstract;
    function ProjectTypeLabel: string;

    { Profile management }
    function AddProfile: TProfile;
    procedure RemoveProfile(AProfile: TProfile);

    property Document: TXMLDocument read FDocument;
    property Node: TDOMNode read FNode;
    property FileName: string read FFileName;
    property Name: string read FName write FName;
    property Version: string read FVersion write FVersion;
    property Author: string read FAuthor write FAuthor;
    property License: string read FLicense write FLicense;
    property Description: string read FDescription write FDescription;
    property ProjectUrl: string read FProjectUrl write FProjectUrl;
    property RepoUrl: string read FRepoUrl write FRepoUrl;
    property Profiles: TProfileList read FProfiles;
  end;

  TProjectBaseList = specialize TFPGObjectList<TProjectBase>;

  { POM aggregator — contains child module references and nested child projects }
  TProjectPOM = class(TProjectBase)
  private
    FModules: TModuleList;
    FChildProjects: TProjectBaseList;
  public
    constructor Create(ANode: TDOMNode; ADocument: TXMLDocument = nil);
    destructor Destroy; override;

    procedure LoadFromNode; override;
    procedure SaveToNode; override;
    function ProjectType: TProjectType; override;

    function AddModule(const APath: string;
      AActiveByDefault: Boolean = True): TModule;
    procedure RemoveModule(AModule: TModule);

    { Child project management — AddChildProject takes ownership }
    procedure AddChildProject(AProject: TProjectBase);
    procedure RemoveChildProject(AProject: TProjectBase);

    property Modules: TModuleList read FModules;
    property ChildProjects: TProjectBaseList read FChildProjects;
  end;

  { Common base for application and library — holds build + test + dependencies }
  TProjectCommon = class(TProjectBase)
  private
    FBuildNode: TDOMNode;
    FTestNode: TDOMNode;
    { Build fields }
    FMainSource: string;
    FExecutableName: string;
    FOutputDirectory: string;
    FSourceDirectory: string;
    FManualUnitPaths: Boolean;
    FDefines: TStringList;
    FCompilerOptions: TStringList;
    FUnitPaths: TConditionalPathList;
    FIncludePaths: TConditionalPathList;
    FBuildResources: TResourcesConfig;
    FBootstrapExclude: TStringList;
    FSourcePackageIncludes: TStringList;
    { Test fields }
    FTestSource: string;
    FTestSourceDirectory: string;
    FTestFramework: string;
    FFrameworkOptions: TStringList;
    FTestResources: TResourcesConfig;
    { Dependency fields }
    FModuleDependencies: TStringList;
    FDependencies: TDependencyList;
  protected
    procedure LoadBuildFields;
    procedure LoadTestFields;
    procedure LoadDependencyFields;
    procedure SaveBuildFields;
    procedure SaveTestFields;
    procedure SaveDependencyFields;
  public
    constructor Create(ANode: TDOMNode; ADocument: TXMLDocument = nil);
    destructor Destroy; override;

    procedure LoadFromNode; override;
    procedure SaveToNode; override;

    function AddUnitPath(const APath, ACondition: string): TConditionalPath;
    procedure RemoveUnitPath(APath: TConditionalPath);
    function AddIncludePath(const APath, ACondition: string): TConditionalPath;
    procedure RemoveIncludePath(APath: TConditionalPath);
    function AddDependency(const AName, AVersion: string): TDependency;
    procedure RemoveDependency(ADep: TDependency);

    { Build }
    property MainSource: string read FMainSource write FMainSource;
    property ExecutableName: string read FExecutableName write FExecutableName;
    property OutputDirectory: string read FOutputDirectory write FOutputDirectory;
    property SourceDirectory: string read FSourceDirectory write FSourceDirectory;
    property ManualUnitPaths: Boolean read FManualUnitPaths write FManualUnitPaths;
    property Defines: TStringList read FDefines;
    property CompilerOptions: TStringList read FCompilerOptions;
    property UnitPaths: TConditionalPathList read FUnitPaths;
    property IncludePaths: TConditionalPathList read FIncludePaths;
    property BuildResources: TResourcesConfig read FBuildResources;
    property BootstrapExclude: TStringList read FBootstrapExclude;
    property SourcePackageIncludes: TStringList read FSourcePackageIncludes;
    { Test }
    property TestSource: string read FTestSource write FTestSource;
    property TestSourceDirectory: string
      read FTestSourceDirectory write FTestSourceDirectory;
    property TestFramework: string read FTestFramework write FTestFramework;
    property FrameworkOptions: TStringList read FFrameworkOptions;
    property TestResources: TResourcesConfig read FTestResources;
    { Dependencies }
    property ModuleDependencies: TStringList read FModuleDependencies;
    property Dependencies: TDependencyList read FDependencies;
  end;

  TProjectApplication = class(TProjectCommon)
  public
    function ProjectType: TProjectType; override;
  end;

  TProjectLibrary = class(TProjectCommon)
  public
    function ProjectType: TProjectType; override;
  end;

implementation

{ ---- DOM helpers ---- }

function GetDoc(ANode: TDOMNode): TXMLDocument;
begin
  Result := TXMLDocument(ANode.OwnerDocument);
end;

function GetChildText(AParent: TDOMNode; const ATagName: string;
  const ADefault: string = ''): string;
var
  Child: TDOMNode;
begin
  Result := ADefault;
  if not Assigned(AParent) then Exit;
  Child := AParent.FindNode(ATagName);
  if Assigned(Child) and Assigned(Child.FirstChild) then
    Result := Trim(Child.FirstChild.NodeValue);
end;

function GetOrCreateElement(AParent: TDOMNode;
  const ATagName: string): TDOMElement;
var
  Child: TDOMNode;
begin
  Child := AParent.FindNode(ATagName);
  if Assigned(Child) then
    Result := TDOMElement(Child)
  else
  begin
    Result := GetDoc(AParent).CreateElement(ATagName);
    AParent.AppendChild(Result);
  end;
end;

{ Set child text. Empty AValue removes the child node. }
procedure SetChildText(AParent: TDOMNode; const ATagName, AValue: string);
var
  Doc: TXMLDocument;
  Child: TDOMNode;
begin
  Child := AParent.FindNode(ATagName);
  if AValue = '' then
  begin
    if Assigned(Child) then
      AParent.RemoveChild(Child);
    Exit;
  end;
  Doc := GetDoc(AParent);
  if not Assigned(Child) then
  begin
    Child := Doc.CreateElement(ATagName);
    AParent.AppendChild(Child);
  end;
  while Assigned(Child.FirstChild) do
    Child.RemoveChild(Child.FirstChild);
  Child.AppendChild(Doc.CreateTextNode(AValue));
end;

{ Omit the node when AValue equals ADefault (avoids writing clutter defaults). }
procedure SetChildTextDefault(AParent: TDOMNode;
  const ATagName, AValue, ADefault: string);
begin
  if AValue = ADefault then
    SetChildText(AParent, ATagName, '')
  else
    SetChildText(AParent, ATagName, AValue);
end;

{ Set text content of a node that is known to exist. }
procedure SetNodeText(ANode: TDOMNode; const AValue: string);
var
  Doc: TXMLDocument;
begin
  Doc := GetDoc(ANode);
  while Assigned(ANode.FirstChild) do
    ANode.RemoveChild(ANode.FirstChild);
  ANode.AppendChild(Doc.CreateTextNode(AValue));
end;

{ Rebuild wrapper/item pairs (defines/define, compilerOptions/option, etc.)
  Only removes element nodes with the matching item tag; other node types
  (e.g. comments) inside the wrapper are preserved. }
procedure SyncStringWrapper(AParent: TDOMNode;
  const AWrapperTag, AItemTag: string; AItems: TStringList);
var
  Doc: TXMLDocument;
  Wrapper, Child, Next: TDOMNode;
  I: Integer;
begin
  Wrapper := AParent.FindNode(AWrapperTag);
  if AItems.Count = 0 then
  begin
    if Assigned(Wrapper) then
      AParent.RemoveChild(Wrapper);
    Exit;
  end;
  Doc := GetDoc(AParent);
  if not Assigned(Wrapper) then
  begin
    Wrapper := Doc.CreateElement(AWrapperTag);
    AParent.AppendChild(Wrapper);
  end;
  Child := Wrapper.FirstChild;
  while Assigned(Child) do
  begin
    Next := Child.NextSibling;
    if (Child.NodeType = ELEMENT_NODE) and (Child.NodeName = AItemTag) then
      Wrapper.RemoveChild(Child);
    Child := Next;
  end;
  for I := 0 to AItems.Count - 1 do
  begin
    Child := Doc.CreateElement(AItemTag);
    Child.AppendChild(Doc.CreateTextNode(AItems[I]));
    Wrapper.AppendChild(Child);
  end;
end;

{ Rebuild a flat list of same-named children (moduleDependencies/module). }
procedure SyncFlatList(AParent: TDOMNode;
  const AWrapperTag, AItemTag: string; AItems: TStringList);
begin
  SyncStringWrapper(AParent, AWrapperTag, AItemTag, AItems);
end;

{ Sync conditional path lists (unitPaths, includePaths).
  Comments inside the wrapper are preserved; path elements are rebuilt. }
procedure SyncConditionalPaths(AParent: TDOMNode; const AWrapperTag: string;
  APaths: TConditionalPathList);
var
  Doc: TXMLDocument;
  Wrapper, Child, Next: TDOMNode;
  PathElem: TDOMElement;
  I: Integer;
begin
  Wrapper := AParent.FindNode(AWrapperTag);
  if APaths.Count = 0 then
  begin
    if Assigned(Wrapper) then
      AParent.RemoveChild(Wrapper);
    Exit;
  end;
  Doc := GetDoc(AParent);
  if not Assigned(Wrapper) then
  begin
    Wrapper := Doc.CreateElement(AWrapperTag);
    AParent.AppendChild(Wrapper);
  end;
  Child := Wrapper.FirstChild;
  while Assigned(Child) do
  begin
    Next := Child.NextSibling;
    if (Child.NodeType = ELEMENT_NODE) and (Child.NodeName = 'path') then
      Wrapper.RemoveChild(Child);
    Child := Next;
  end;
  for I := 0 to APaths.Count - 1 do
  begin
    PathElem := Doc.CreateElement('path');
    if APaths[I].Condition <> '' then
      PathElem.SetAttribute('condition', APaths[I].Condition);
    PathElem.AppendChild(Doc.CreateTextNode(APaths[I].Path));
    Wrapper.AppendChild(PathElem);
    APaths[I].Node := PathElem;
  end;
end;

{ Update <resources> in place; create if needed; remove if no content. }
procedure SyncResources(AParent: TDOMNode; ARes: TResourcesConfig);
var
  Doc: TXMLDocument;
  ResNode: TDOMNode;
begin
  if (not ARes.Filtering) and (ARes.Directory = '') then
  begin
    ResNode := AParent.FindNode('resources');
    if Assigned(ResNode) then
      AParent.RemoveChild(ResNode);
    ARes.Node := nil;
    Exit;
  end;
  Doc := GetDoc(AParent);
  ResNode := AParent.FindNode('resources');
  if not Assigned(ResNode) then
  begin
    ResNode := Doc.CreateElement('resources');
    AParent.AppendChild(ResNode);
  end;
  ARes.Node := ResNode;
  SetChildText(ResNode, 'directory', ARes.Directory);
  if ARes.Filtering then
    SetChildText(ResNode, 'filtering', 'true')
  else
    SetChildText(ResNode, 'filtering', '');
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

function DetectProjectType(ANode: TDOMNode): TProjectType;
var
  BuildNode: TDOMNode;
  S: string;
begin
  Result := ptApplication;
  BuildNode := ANode.FindNode('build');
  if not Assigned(BuildNode) then Exit;
  S := GetChildText(BuildNode, 'packaging');
  if S <> '' then
    Result := StringToProjectType(S)
  else
    Result := StringToProjectType(
      GetChildText(BuildNode, 'projectType', 'application'));
end;

function CreateProjectForNode(ANode: TDOMNode;
  ADocument: TXMLDocument): TProjectBase;
begin
  case DetectProjectType(ANode) of
    ptPOM:     Result := TProjectPOM.Create(ANode, ADocument);
    ptLibrary: Result := TProjectLibrary.Create(ANode, ADocument);
  else
    Result := TProjectApplication.Create(ANode, ADocument);
  end;
end;

{ ---- TConditionalPath ---- }

constructor TConditionalPath.Create(const APath, ACondition: string;
  ANode: TDOMNode);
begin
  inherited Create;
  Path      := APath;
  Condition := ACondition;
  Node      := ANode;
end;

{ ---- TProfile ---- }

constructor TProfile.Create;
begin
  inherited Create;
  Defines        := TStringList.Create;
  CompilerOptions := TStringList.Create;
  Node           := nil;
end;

destructor TProfile.Destroy;
begin
  Defines.Free;
  CompilerOptions.Free;
  inherited Destroy;
end;

{ ---- TModule ---- }

constructor TModule.Create(const APath: string; AActiveByDefault: Boolean;
  ANode: TDOMNode);
begin
  inherited Create;
  Path            := APath;
  ActiveByDefault := AActiveByDefault;
  Node            := ANode;
end;

{ ---- TDependency ---- }

constructor TDependency.Create(const AName, AVersion: string; ANode: TDOMNode);
begin
  inherited Create;
  Name    := AName;
  Version := AVersion;
  Node    := ANode;
end;

{ ---- TResourcesConfig ---- }

constructor TResourcesConfig.Create;
begin
  inherited Create;
  Directory := '';
  Filtering := False;
  Node      := nil;
end;

{ ---- TProjectBase ---- }

constructor TProjectBase.Create(ANode: TDOMNode; ADocument: TXMLDocument);
begin
  inherited Create;
  FNode     := ANode;
  FDocument := ADocument;
  FProfiles := TProfileList.Create(True);
  FAuthor   := 'Unknown';
  FLicense  := 'Proprietary';
end;

destructor TProjectBase.Destroy;
begin
  FProfiles.Free;
  FDocument.Free;  // nil for child projects — Free(nil) is a no-op
  inherited Destroy;
end;

class function TProjectBase.LoadFromFile(const AFileName: string): TProjectBase;
var
  Doc: TXMLDocument;
  Root: TDOMNode;
begin
  ReadXMLFile(Doc, AFileName);
  Root := Doc.DocumentElement;
  if not Assigned(Root) or (Root.NodeName <> 'project') then
  begin
    Doc.Free;
    raise Exception.CreateFmt(
      'Invalid project.xml: missing <project> root in %s', [AFileName]);
  end;
  Result := CreateProjectForNode(Root, Doc);
  Result.FFileName := AFileName;
  Result.LoadFromNode;
end;

procedure TProjectBase.SaveToFile(const AFileName: string);
var
  Target: string;
begin
  if not Assigned(FDocument) then
    raise Exception.Create(
      'SaveToFile must be called on the root project, not a child project');
  SaveToNode;
  if AFileName <> '' then
    Target := AFileName
  else
    Target := FFileName;
  WriteXMLFile(FDocument, Target);
end;

procedure TProjectBase.LoadFromNode;
begin
  LoadBaseFields;
end;

procedure TProjectBase.SaveToNode;
begin
  SaveBaseFields;
end;

function TProjectBase.ProjectTypeLabel: string;
begin
  Result := ProjectTypeToString(ProjectType);
end;

procedure TProjectBase.LoadBaseFields;
begin
  FName        := GetChildText(FNode, 'name');
  FVersion     := GetChildText(FNode, 'version');
  FAuthor      := GetChildText(FNode, 'author', 'Unknown');
  FLicense     := GetChildText(FNode, 'license', 'Proprietary');
  FDescription := GetChildText(FNode, 'description');
  FProjectUrl  := GetChildText(FNode, 'projectUrl');
  FRepoUrl     := GetChildText(FNode, 'repoUrl');
  LoadProfiles;
end;

procedure TProjectBase.LoadProfiles;
var
  ProfilesNode, ProfileNode, SubNode: TDOMNode;
  Profile: TProfile;
  I, J: Integer;
begin
  FProfiles.Clear;
  ProfilesNode := FNode.FindNode('profiles');
  if not Assigned(ProfilesNode) then Exit;
  for I := 0 to Integer(ProfilesNode.ChildNodes.Count) - 1 do
  begin
    ProfileNode := ProfilesNode.ChildNodes.Item[I];
    if ProfileNode.NodeName <> 'profile' then Continue;
    Profile      := TProfile.Create;
    Profile.Node := ProfileNode;
    Profile.ID   := GetChildText(ProfileNode, 'id');
    SubNode := ProfileNode.FindNode('defines');
    if Assigned(SubNode) then
      for J := 0 to Integer(SubNode.ChildNodes.Count) - 1 do
        if SubNode.ChildNodes.Item[J].NodeName = 'define' then
          if Assigned(SubNode.ChildNodes.Item[J].FirstChild) then
            Profile.Defines.Add(
              Trim(SubNode.ChildNodes.Item[J].FirstChild.NodeValue));
    SubNode := ProfileNode.FindNode('compilerOptions');
    if Assigned(SubNode) then
      for J := 0 to Integer(SubNode.ChildNodes.Count) - 1 do
        if SubNode.ChildNodes.Item[J].NodeName = 'option' then
          if Assigned(SubNode.ChildNodes.Item[J].FirstChild) then
            Profile.CompilerOptions.Add(
              Trim(SubNode.ChildNodes.Item[J].FirstChild.NodeValue));
    FProfiles.Add(Profile);
  end;
end;

procedure TProjectBase.SaveBaseFields;
begin
  SetChildText(FNode, 'name',    FName);
  SetChildText(FNode, 'version', FVersion);
  SetChildText(FNode, 'author',  FAuthor);
  SetChildText(FNode, 'license', FLicense);
  SetChildText(FNode, 'description', FDescription);
  SetChildText(FNode, 'projectUrl',  FProjectUrl);
  SetChildText(FNode, 'repoUrl',     FRepoUrl);
  SaveProfiles;
end;

procedure TProjectBase.SaveProfiles;
var
  Doc: TXMLDocument;
  ProfilesNode, Child, Next: TDOMNode;
  Profile: TProfile;
  ClaimedNodes: TList;
  I: Integer;
begin
  if FProfiles.Count = 0 then
  begin
    ProfilesNode := FNode.FindNode('profiles');
    if Assigned(ProfilesNode) then
      FNode.RemoveChild(ProfilesNode);
    Exit;
  end;
  Doc          := GetDoc(FNode);
  ProfilesNode := GetOrCreateElement(FNode, 'profiles');
  ClaimedNodes := TList.Create;
  try
    for I := 0 to FProfiles.Count - 1 do
    begin
      Profile := FProfiles[I];
      if not Assigned(Profile.Node) then
      begin
        Profile.Node := Doc.CreateElement('profile');
        ProfilesNode.AppendChild(Profile.Node);
      end;
      ClaimedNodes.Add(Profile.Node);
      SetChildText(Profile.Node, 'id', Profile.ID);
      SyncStringWrapper(Profile.Node, 'defines', 'define', Profile.Defines);
      SyncStringWrapper(Profile.Node, 'compilerOptions', 'option',
        Profile.CompilerOptions);
    end;
    { Remove DOM nodes for profiles that were deleted from the list }
    Child := ProfilesNode.FirstChild;
    while Assigned(Child) do
    begin
      Next := Child.NextSibling;
      if (Child.NodeType = ELEMENT_NODE) and (Child.NodeName = 'profile') and
         (ClaimedNodes.IndexOf(Child) < 0) then
        ProfilesNode.RemoveChild(Child);
      Child := Next;
    end;
  finally
    ClaimedNodes.Free;
  end;
end;

function TProjectBase.AddProfile: TProfile;
begin
  Result := TProfile.Create;
  FProfiles.Add(Result);
end;

procedure TProjectBase.RemoveProfile(AProfile: TProfile);
begin
  if Assigned(AProfile.Node) and Assigned(AProfile.Node.ParentNode) then
    AProfile.Node.ParentNode.RemoveChild(AProfile.Node);
  FProfiles.Remove(AProfile);
end;

{ ---- TProjectPOM ---- }

constructor TProjectPOM.Create(ANode: TDOMNode; ADocument: TXMLDocument);
begin
  inherited Create(ANode, ADocument);
  FModules       := TModuleList.Create(True);
  FChildProjects := TProjectBaseList.Create(True);
end;

destructor TProjectPOM.Destroy;
begin
  FChildProjects.Free;
  FModules.Free;
  inherited Destroy;
end;

function TProjectPOM.ProjectType: TProjectType;
begin
  Result := ptPOM;
end;

procedure TProjectPOM.LoadFromNode;
var
  ModulesNode, ModNode, ChildNode: TDOMNode;
  Modl: TModule;
  Child: TProjectBase;
  ActiveStr: string;
  I: Integer;
begin
  inherited LoadFromNode;
  FModules.Clear;
  ModulesNode := FNode.FindNode('modules');
  if Assigned(ModulesNode) then
    for I := 0 to Integer(ModulesNode.ChildNodes.Count) - 1 do
    begin
      ModNode := ModulesNode.ChildNodes.Item[I];
      if ModNode.NodeName <> 'module' then Continue;
      Modl := TModule.Create('', True, ModNode);
      if Assigned(ModNode.FirstChild) then
        Modl.Path := Trim(ModNode.FirstChild.NodeValue);
      if ModNode is TDOMElement then
      begin
        ActiveStr := LowerCase(
          Trim(TDOMElement(ModNode).GetAttribute('activeByDefault')));
        if ActiveStr = 'false' then
          Modl.ActiveByDefault := False;
      end;
      FModules.Add(Modl);
    end;
  FChildProjects.Clear;
  for I := 0 to Integer(FNode.ChildNodes.Count) - 1 do
  begin
    ChildNode := FNode.ChildNodes.Item[I];
    if ChildNode.NodeName <> 'project' then Continue;
    Child := CreateProjectForNode(ChildNode, nil);
    Child.LoadFromNode;
    FChildProjects.Add(Child);
  end;
end;

procedure TProjectPOM.SaveToNode;
var
  Doc: TXMLDocument;
  ModulesNode, Child, Next: TDOMNode;
  Modl: TModule;
  ClaimedNodes: TList;
  I: Integer;
begin
  inherited SaveToNode;
  Doc := GetDoc(FNode);

  { Modules }
  if FModules.Count = 0 then
  begin
    ModulesNode := FNode.FindNode('modules');
    if Assigned(ModulesNode) then
      FNode.RemoveChild(ModulesNode);
  end
  else
  begin
    ModulesNode  := GetOrCreateElement(FNode, 'modules');
    ClaimedNodes := TList.Create;
    try
      for I := 0 to FModules.Count - 1 do
      begin
        Modl := FModules[I];
        if not Assigned(Modl.Node) then
        begin
          Modl.Node := Doc.CreateElement('module');
          ModulesNode.AppendChild(Modl.Node);
        end;
        ClaimedNodes.Add(Modl.Node);
        if not Modl.ActiveByDefault then
          TDOMElement(Modl.Node).SetAttribute('activeByDefault', 'false')
        else
          TDOMElement(Modl.Node).RemoveAttribute('activeByDefault');
        SetNodeText(Modl.Node, Modl.Path);
      end;
      Child := ModulesNode.FirstChild;
      while Assigned(Child) do
      begin
        Next := Child.NextSibling;
        if (Child.NodeType = ELEMENT_NODE) and (Child.NodeName = 'module') and
           (ClaimedNodes.IndexOf(Child) < 0) then
          ModulesNode.RemoveChild(Child);
        Child := Next;
      end;
    finally
      ClaimedNodes.Free;
    end;
  end;

  { Child projects recurse }
  for I := 0 to FChildProjects.Count - 1 do
    FChildProjects[I].SaveToNode;
end;

function TProjectPOM.AddModule(const APath: string;
  AActiveByDefault: Boolean): TModule;
begin
  Result := TModule.Create(APath, AActiveByDefault, nil);
  FModules.Add(Result);
end;

procedure TProjectPOM.RemoveModule(AModule: TModule);
begin
  if Assigned(AModule.Node) and Assigned(AModule.Node.ParentNode) then
    AModule.Node.ParentNode.RemoveChild(AModule.Node);
  FModules.Remove(AModule);
end;

procedure TProjectPOM.AddChildProject(AProject: TProjectBase);
var
  NewNode: TDOMElement;
begin
  NewNode          := GetDoc(FNode).CreateElement('project');
  FNode.AppendChild(NewNode);
  AProject.FNode   := NewNode;
  FChildProjects.Add(AProject);
end;

procedure TProjectPOM.RemoveChildProject(AProject: TProjectBase);
begin
  if Assigned(AProject.FNode) and Assigned(AProject.FNode.ParentNode) then
    AProject.FNode.ParentNode.RemoveChild(AProject.FNode);
  FChildProjects.Remove(AProject);
end;

{ ---- TProjectCommon ---- }

constructor TProjectCommon.Create(ANode: TDOMNode; ADocument: TXMLDocument);
begin
  inherited Create(ANode, ADocument);
  FDefines              := TStringList.Create;
  FCompilerOptions      := TStringList.Create;
  FUnitPaths            := TConditionalPathList.Create(True);
  FIncludePaths         := TConditionalPathList.Create(True);
  FBuildResources       := TResourcesConfig.Create;
  FBootstrapExclude     := TStringList.Create;
  FSourcePackageIncludes := TStringList.Create;
  FFrameworkOptions     := TStringList.Create;
  FTestResources        := TResourcesConfig.Create;
  FModuleDependencies   := TStringList.Create;
  FDependencies         := TDependencyList.Create(True);
  FOutputDirectory      := 'target';
  FSourceDirectory      := 'src/main/pascal';
  FTestSource           := '';
  FTestSourceDirectory  := 'src/test/pascal';
end;

destructor TProjectCommon.Destroy;
begin
  FDefines.Free;
  FCompilerOptions.Free;
  FUnitPaths.Free;
  FIncludePaths.Free;
  FBuildResources.Free;
  FBootstrapExclude.Free;
  FSourcePackageIncludes.Free;
  FFrameworkOptions.Free;
  FTestResources.Free;
  FModuleDependencies.Free;
  FDependencies.Free;
  inherited Destroy;
end;

procedure TProjectCommon.LoadBuildFields;
var
  WrapNode, ItemNode: TDOMNode;
  Path: TConditionalPath;
  Condition: string;
  I: Integer;
begin
  FBuildNode := FNode.FindNode('build');
  if not Assigned(FBuildNode) then Exit;

  FMainSource      := GetChildText(FBuildNode, 'mainSource');
  FExecutableName  := GetChildText(FBuildNode, 'executableName');
  FOutputDirectory := GetChildText(FBuildNode, 'outputDirectory', 'target');
  FSourceDirectory := GetChildText(FBuildNode, 'sourceDirectory', 'src/main/pascal');
  FManualUnitPaths :=
    LowerCase(GetChildText(FBuildNode, 'manualUnitPaths')) = 'true';

  FDefines.Clear;
  WrapNode := FBuildNode.FindNode('defines');
  if Assigned(WrapNode) then
    for I := 0 to Integer(WrapNode.ChildNodes.Count) - 1 do
    begin
      ItemNode := WrapNode.ChildNodes.Item[I];
      if (ItemNode.NodeName = 'define') and Assigned(ItemNode.FirstChild) then
        FDefines.Add(Trim(ItemNode.FirstChild.NodeValue));
    end;

  FCompilerOptions.Clear;
  WrapNode := FBuildNode.FindNode('compilerOptions');
  if Assigned(WrapNode) then
    for I := 0 to Integer(WrapNode.ChildNodes.Count) - 1 do
    begin
      ItemNode := WrapNode.ChildNodes.Item[I];
      if (ItemNode.NodeName = 'option') and Assigned(ItemNode.FirstChild) then
        FCompilerOptions.Add(Trim(ItemNode.FirstChild.NodeValue));
    end;

  FUnitPaths.Clear;
  WrapNode := FBuildNode.FindNode('unitPaths');
  if Assigned(WrapNode) then
    for I := 0 to Integer(WrapNode.ChildNodes.Count) - 1 do
    begin
      ItemNode := WrapNode.ChildNodes.Item[I];
      if ItemNode.NodeName <> 'path' then Continue;
      Condition := '';
      if ItemNode is TDOMElement then
        Condition := Trim(TDOMElement(ItemNode).GetAttribute('condition'));
      Path := TConditionalPath.Create(
        Trim(ItemNode.TextContent), Condition, ItemNode);
      FUnitPaths.Add(Path);
    end;

  FIncludePaths.Clear;
  WrapNode := FBuildNode.FindNode('includePaths');
  if Assigned(WrapNode) then
    for I := 0 to Integer(WrapNode.ChildNodes.Count) - 1 do
    begin
      ItemNode := WrapNode.ChildNodes.Item[I];
      if ItemNode.NodeName <> 'path' then Continue;
      Condition := '';
      if ItemNode is TDOMElement then
        Condition := Trim(TDOMElement(ItemNode).GetAttribute('condition'));
      Path := TConditionalPath.Create(
        Trim(ItemNode.TextContent), Condition, ItemNode);
      FIncludePaths.Add(Path);
    end;

  FBuildResources.Node := FBuildNode.FindNode('resources');
  if Assigned(FBuildResources.Node) then
  begin
    FBuildResources.Directory :=
      GetChildText(FBuildResources.Node, 'directory');
    FBuildResources.Filtering :=
      LowerCase(GetChildText(FBuildResources.Node, 'filtering')) = 'true';
  end;

  FBootstrapExclude.Clear;
  WrapNode := FBuildNode.FindNode('bootstrapExclude');
  if Assigned(WrapNode) then
    for I := 0 to Integer(WrapNode.ChildNodes.Count) - 1 do
    begin
      ItemNode := WrapNode.ChildNodes.Item[I];
      if (ItemNode.NodeName = 'unit') and Assigned(ItemNode.FirstChild) then
        FBootstrapExclude.Add(Trim(ItemNode.FirstChild.NodeValue));
    end;

  FSourcePackageIncludes.Clear;
  WrapNode := FBuildNode.FindNode('sourcePackage');
  if Assigned(WrapNode) then
    for I := 0 to Integer(WrapNode.ChildNodes.Count) - 1 do
    begin
      ItemNode := WrapNode.ChildNodes.Item[I];
      if (ItemNode.NodeName = 'include') and Assigned(ItemNode.FirstChild) then
        FSourcePackageIncludes.Add(Trim(ItemNode.FirstChild.NodeValue));
    end;
end;

procedure TProjectCommon.LoadTestFields;
var
  WrapNode, ItemNode: TDOMNode;
  I: Integer;
begin
  FTestNode := FNode.FindNode('test');
  if not Assigned(FTestNode) then Exit;

  FTestSource :=
    GetChildText(FTestNode, 'testSource');
  FTestSourceDirectory :=
    GetChildText(FTestNode, 'testSourceDirectory', 'src/test/pascal');
  FTestFramework := GetChildText(FTestNode, 'framework');

  FFrameworkOptions.Clear;
  WrapNode := FTestNode.FindNode('frameworkOptions');
  if Assigned(WrapNode) then
    for I := 0 to Integer(WrapNode.ChildNodes.Count) - 1 do
    begin
      ItemNode := WrapNode.ChildNodes.Item[I];
      if (ItemNode.NodeName = 'option') and Assigned(ItemNode.FirstChild) then
        FFrameworkOptions.Add(Trim(ItemNode.FirstChild.NodeValue));
    end;

  FTestResources.Node := FTestNode.FindNode('resources');
  if Assigned(FTestResources.Node) then
  begin
    FTestResources.Directory :=
      GetChildText(FTestResources.Node, 'directory');
    FTestResources.Filtering :=
      LowerCase(GetChildText(FTestResources.Node, 'filtering')) = 'true';
  end;
end;

procedure TProjectCommon.LoadDependencyFields;
var
  WrapNode, ItemNode: TDOMNode;
  Dep: TDependency;
  I: Integer;
begin
  FModuleDependencies.Clear;
  WrapNode := FNode.FindNode('moduleDependencies');
  if Assigned(WrapNode) then
    for I := 0 to Integer(WrapNode.ChildNodes.Count) - 1 do
    begin
      ItemNode := WrapNode.ChildNodes.Item[I];
      if (ItemNode.NodeName = 'module') and Assigned(ItemNode.FirstChild) then
        FModuleDependencies.Add(Trim(ItemNode.FirstChild.NodeValue));
    end;

  FDependencies.Clear;
  WrapNode := FNode.FindNode('dependencies');
  if Assigned(WrapNode) then
    for I := 0 to Integer(WrapNode.ChildNodes.Count) - 1 do
    begin
      ItemNode := WrapNode.ChildNodes.Item[I];
      if ItemNode.NodeName <> 'dependency' then Continue;
      Dep := TDependency.Create(
        GetChildText(ItemNode, 'name'),
        GetChildText(ItemNode, 'version'),
        ItemNode);
      FDependencies.Add(Dep);
    end;
end;

procedure TProjectCommon.SaveBuildFields;
var
  Doc: TXMLDocument;
begin
  Doc := GetDoc(FNode);
  if not Assigned(FBuildNode) then
  begin
    FBuildNode := Doc.CreateElement('build');
    FNode.AppendChild(FBuildNode);
  end;

  SetChildText(FBuildNode, 'packaging', ProjectTypeToString(ProjectType));
  SetChildText(FBuildNode, 'mainSource', FMainSource);
  SetChildText(FBuildNode, 'executableName', FExecutableName);
  SetChildTextDefault(FBuildNode, 'outputDirectory', FOutputDirectory, 'target');
  SetChildTextDefault(FBuildNode, 'sourceDirectory', FSourceDirectory,
    'src/main/pascal');
  if FManualUnitPaths then
    SetChildText(FBuildNode, 'manualUnitPaths', 'true')
  else
    SetChildText(FBuildNode, 'manualUnitPaths', '');

  SyncStringWrapper(FBuildNode, 'defines', 'define', FDefines);
  SyncStringWrapper(FBuildNode, 'compilerOptions', 'option', FCompilerOptions);
  SyncConditionalPaths(FBuildNode, 'unitPaths', FUnitPaths);
  SyncConditionalPaths(FBuildNode, 'includePaths', FIncludePaths);
  SyncResources(FBuildNode, FBuildResources);
  SyncStringWrapper(FBuildNode, 'bootstrapExclude', 'unit', FBootstrapExclude);
  SyncStringWrapper(FBuildNode, 'sourcePackage', 'include',
    FSourcePackageIncludes);
end;

procedure TProjectCommon.SaveTestFields;
var
  Doc: TXMLDocument;
  HasContent: Boolean;
begin
  Doc        := GetDoc(FNode);
  HasContent := (FTestSource <> '') or (FTestFramework <> '') or
                (FFrameworkOptions.Count > 0) or FTestResources.Filtering or
                (FTestResources.Directory <> '');
  if not HasContent then
  begin
    if Assigned(FTestNode) then
    begin
      FNode.RemoveChild(FTestNode);
      FTestNode := nil;
    end;
    Exit;
  end;
  if not Assigned(FTestNode) then
  begin
    FTestNode := Doc.CreateElement('test');
    FNode.AppendChild(FTestNode);
  end;
  SetChildText(FTestNode, 'testSource', FTestSource);
  SetChildTextDefault(FTestNode, 'testSourceDirectory', FTestSourceDirectory,
    'src/test/pascal');
  SetChildText(FTestNode, 'framework', FTestFramework);
  SyncStringWrapper(FTestNode, 'frameworkOptions', 'option', FFrameworkOptions);
  SyncResources(FTestNode, FTestResources);
end;

procedure TProjectCommon.SaveDependencyFields;
var
  Doc: TXMLDocument;
  DepsNode, Child, Next: TDOMNode;
  ClaimedNodes: TList;
  Dep: TDependency;
  I: Integer;
begin
  Doc := GetDoc(FNode);

  SyncFlatList(FNode, 'moduleDependencies', 'module', FModuleDependencies);

  if FDependencies.Count = 0 then
  begin
    DepsNode := FNode.FindNode('dependencies');
    if Assigned(DepsNode) then
      FNode.RemoveChild(DepsNode);
    Exit;
  end;
  DepsNode     := GetOrCreateElement(FNode, 'dependencies');
  ClaimedNodes := TList.Create;
  try
    for I := 0 to FDependencies.Count - 1 do
    begin
      Dep := FDependencies[I];
      if not Assigned(Dep.Node) then
      begin
        Dep.Node := Doc.CreateElement('dependency');
        DepsNode.AppendChild(Dep.Node);
      end;
      ClaimedNodes.Add(Dep.Node);
      SetChildText(Dep.Node, 'name',    Dep.Name);
      SetChildText(Dep.Node, 'version', Dep.Version);
    end;
    Child := DepsNode.FirstChild;
    while Assigned(Child) do
    begin
      Next := Child.NextSibling;
      if (Child.NodeType = ELEMENT_NODE) and (Child.NodeName = 'dependency') and
         (ClaimedNodes.IndexOf(Child) < 0) then
        DepsNode.RemoveChild(Child);
      Child := Next;
    end;
  finally
    ClaimedNodes.Free;
  end;
end;

procedure TProjectCommon.LoadFromNode;
begin
  inherited LoadFromNode;
  LoadBuildFields;
  LoadTestFields;
  LoadDependencyFields;
end;

procedure TProjectCommon.SaveToNode;
begin
  inherited SaveToNode;
  SaveBuildFields;
  SaveTestFields;
  SaveDependencyFields;
end;

function TProjectCommon.AddUnitPath(const APath,
  ACondition: string): TConditionalPath;
begin
  Result := TConditionalPath.Create(APath, ACondition, nil);
  FUnitPaths.Add(Result);
end;

procedure TProjectCommon.RemoveUnitPath(APath: TConditionalPath);
begin
  if Assigned(APath.Node) and Assigned(APath.Node.ParentNode) then
    APath.Node.ParentNode.RemoveChild(APath.Node);
  FUnitPaths.Remove(APath);
end;

function TProjectCommon.AddIncludePath(const APath,
  ACondition: string): TConditionalPath;
begin
  Result := TConditionalPath.Create(APath, ACondition, nil);
  FIncludePaths.Add(Result);
end;

procedure TProjectCommon.RemoveIncludePath(APath: TConditionalPath);
begin
  if Assigned(APath.Node) and Assigned(APath.Node.ParentNode) then
    APath.Node.ParentNode.RemoveChild(APath.Node);
  FIncludePaths.Remove(APath);
end;

function TProjectCommon.AddDependency(const AName,
  AVersion: string): TDependency;
begin
  Result := TDependency.Create(AName, AVersion, nil);
  FDependencies.Add(Result);
end;

procedure TProjectCommon.RemoveDependency(ADep: TDependency);
begin
  if Assigned(ADep.Node) and Assigned(ADep.Node.ParentNode) then
    ADep.Node.ParentNode.RemoveChild(ADep.Node);
  FDependencies.Remove(ADep);
end;

{ ---- TProjectApplication ---- }

function TProjectApplication.ProjectType: TProjectType;
begin
  Result := ptApplication;
end;

{ ---- TProjectLibrary ---- }

function TProjectLibrary.ProjectType: TProjectType;
begin
  Result := ptLibrary;
end;

end.
