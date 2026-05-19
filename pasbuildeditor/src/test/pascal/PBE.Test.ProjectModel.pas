unit PBE.Test.ProjectModel;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  PBLib.ProjectModel;

type
  TProjectModelTests = class(TTestCase)
  private
    FFixtureDir: string;
    function Fixture(const AName: string): string;
    function SaveAndReload(AProject: TProjectBase): TProjectBase;
  protected
    procedure SetUp; override;
  published
    { POM }
    procedure TestPOM_Type;
    procedure TestPOM_BaseFields;
    procedure TestPOM_Modules;
    procedure TestPOM_ModuleActiveByDefault;
    procedure TestPOM_Profiles;
    procedure TestPOM_ProfileDefines;
    procedure TestPOM_ProfileOptions;

    { Application }
    procedure TestApp_Type;
    procedure TestApp_BaseFields;
    procedure TestApp_BuildFields;
    procedure TestApp_UnitPaths;
    procedure TestApp_UnitPathCondition;
    procedure TestApp_Defines;
    procedure TestApp_CompilerOptions;
    procedure TestApp_TestSection;
    procedure TestApp_TestFrameworkOptions;
    procedure TestApp_ModuleDependencies;
    procedure TestApp_Dependencies;

    { Library }
    procedure TestLib_Type;
    procedure TestLib_Name;

    { Round-trip: modify → save → reload }
    procedure TestRoundTrip_BaseName;
    procedure TestRoundTrip_AddModule;
    procedure TestRoundTrip_AddProfile;
    procedure TestRoundTrip_RemoveProfile;
    procedure TestRoundTrip_TestSectionRemovedWhenEmpty;
  end;

implementation

function TProjectModelTests.Fixture(const AName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(FFixtureDir) + AName;
end;

{ Load AProject, save to a unique temp file, free AProject, reload from temp. }
function TProjectModelTests.SaveAndReload(AProject: TProjectBase): TProjectBase;
var
  TmpFile: string;
begin
  TmpFile := GetTempFileName('', 'pbe') + '.xml';
  try
    AProject.SaveToFile(TmpFile);
  finally
    AProject.Free;
  end;
  Result := TProjectBase.LoadFromFile(TmpFile);
  DeleteFile(TmpFile);
end;

procedure TProjectModelTests.SetUp;
begin
  { pasbuild copies src/test/resources → target/test-resources before running }
  FFixtureDir := ExtractFilePath(ParamStr(0)) + 'fixtures';
end;

{ ---- POM tests ---- }

procedure TProjectModelTests.TestPOM_Type;
var P: TProjectBase;
begin
  P := TProjectBase.LoadFromFile(Fixture('pom.xml'));
  try
    AssertEquals('project type', Integer(ptPOM), Integer(P.ProjectType));
  finally P.Free; end;
end;

procedure TProjectModelTests.TestPOM_BaseFields;
var P: TProjectBase;
begin
  P := TProjectBase.LoadFromFile(Fixture('pom.xml'));
  try
    AssertEquals('name',    'test-pom', P.Name);
    AssertEquals('version', '2.3.4',    P.Version);
    AssertEquals('author',  'Test Author', P.Author);
    AssertEquals('license', 'MIT',      P.License);
  finally P.Free; end;
end;

procedure TProjectModelTests.TestPOM_Modules;
var P: TProjectPOM;
begin
  P := TProjectPOM(TProjectBase.LoadFromFile(Fixture('pom.xml')));
  try
    AssertEquals('module count', 2, P.Modules.Count);
    AssertEquals('module[0]', 'child-a', P.Modules[0].Path);
    AssertEquals('module[1]', 'child-b', P.Modules[1].Path);
  finally P.Free; end;
end;

procedure TProjectModelTests.TestPOM_ModuleActiveByDefault;
var P: TProjectPOM;
begin
  P := TProjectPOM(TProjectBase.LoadFromFile(Fixture('pom.xml')));
  try
    AssertTrue('module[0] active',     P.Modules[0].ActiveByDefault);
    AssertFalse('module[1] not active', P.Modules[1].ActiveByDefault);
  finally P.Free; end;
end;

procedure TProjectModelTests.TestPOM_Profiles;
var P: TProjectBase;
begin
  P := TProjectBase.LoadFromFile(Fixture('pom.xml'));
  try
    AssertEquals('profile count', 1, P.Profiles.Count);
    AssertEquals('profile id', 'debug', P.Profiles[0].ID);
  finally P.Free; end;
end;

procedure TProjectModelTests.TestPOM_ProfileDefines;
var P: TProjectBase;
begin
  P := TProjectBase.LoadFromFile(Fixture('pom.xml'));
  try
    AssertEquals('define count', 1, P.Profiles[0].Defines.Count);
    AssertEquals('define[0]', 'DEBUG', P.Profiles[0].Defines[0]);
  finally P.Free; end;
end;

procedure TProjectModelTests.TestPOM_ProfileOptions;
var P: TProjectBase;
begin
  P := TProjectBase.LoadFromFile(Fixture('pom.xml'));
  try
    AssertEquals('option count', 2, P.Profiles[0].CompilerOptions.Count);
    AssertEquals('option[0]', '-gw', P.Profiles[0].CompilerOptions[0]);
    AssertEquals('option[1]', '-O-', P.Profiles[0].CompilerOptions[1]);
  finally P.Free; end;
end;

{ ---- Application tests ---- }

procedure TProjectModelTests.TestApp_Type;
var P: TProjectBase;
begin
  P := TProjectBase.LoadFromFile(Fixture('application.xml'));
  try
    AssertEquals('project type', Integer(ptApplication), Integer(P.ProjectType));
  finally P.Free; end;
end;

procedure TProjectModelTests.TestApp_BaseFields;
var P: TProjectBase;
begin
  P := TProjectBase.LoadFromFile(Fixture('application.xml'));
  try
    AssertEquals('name',    'test-app',     P.Name);
    AssertEquals('version', '1.2.3',        P.Version);
    AssertEquals('license', 'BSD-3-Clause', P.License);
  finally P.Free; end;
end;

procedure TProjectModelTests.TestApp_BuildFields;
var P: TProjectCommon;
begin
  P := TProjectCommon(TProjectBase.LoadFromFile(Fixture('application.xml')));
  try
    AssertEquals('mainSource',      'Main.pas', P.MainSource);
    AssertEquals('executableName',  'my-app',   P.ExecutableName);
    AssertTrue('manualUnitPaths', P.ManualUnitPaths);
  finally P.Free; end;
end;

procedure TProjectModelTests.TestApp_UnitPaths;
var P: TProjectCommon;
begin
  P := TProjectCommon(TProjectBase.LoadFromFile(Fixture('application.xml')));
  try
    AssertEquals('unitPath count', 2, P.UnitPaths.Count);
    AssertEquals('unitPath[0]', 'src/main/pascal', P.UnitPaths[0].Path);
    AssertEquals('unitPath[1]', 'src/platform/unix', P.UnitPaths[1].Path);
  finally P.Free; end;
end;

procedure TProjectModelTests.TestApp_UnitPathCondition;
var P: TProjectCommon;
begin
  P := TProjectCommon(TProjectBase.LoadFromFile(Fixture('application.xml')));
  try
    AssertEquals('condition[0]', '',      P.UnitPaths[0].Condition);
    AssertEquals('condition[1]', 'LINUX', P.UnitPaths[1].Condition);
  finally P.Free; end;
end;

procedure TProjectModelTests.TestApp_Defines;
var P: TProjectCommon;
begin
  P := TProjectCommon(TProjectBase.LoadFromFile(Fixture('application.xml')));
  try
    AssertEquals('define count', 1, P.Defines.Count);
    AssertEquals('define[0]', 'MY_DEFINE', P.Defines[0]);
  finally P.Free; end;
end;

procedure TProjectModelTests.TestApp_CompilerOptions;
var P: TProjectCommon;
begin
  P := TProjectCommon(TProjectBase.LoadFromFile(Fixture('application.xml')));
  try
    AssertEquals('option count', 1, P.CompilerOptions.Count);
    AssertEquals('option[0]', '-O2', P.CompilerOptions[0]);
  finally P.Free; end;
end;

procedure TProjectModelTests.TestApp_TestSection;
var P: TProjectCommon;
begin
  P := TProjectCommon(TProjectBase.LoadFromFile(Fixture('application.xml')));
  try
    AssertEquals('testSource',   'TestRunner.pas', P.TestSource);
    AssertEquals('testFramework', 'auto',           P.TestFramework);
  finally P.Free; end;
end;

procedure TProjectModelTests.TestApp_TestFrameworkOptions;
var P: TProjectCommon;
begin
  P := TProjectCommon(TProjectBase.LoadFromFile(Fixture('application.xml')));
  try
    AssertEquals('frameworkOption count', 1, P.FrameworkOptions.Count);
    AssertEquals('frameworkOption[0]', '--all', P.FrameworkOptions[0]);
  finally P.Free; end;
end;

procedure TProjectModelTests.TestApp_ModuleDependencies;
var P: TProjectCommon;
begin
  P := TProjectCommon(TProjectBase.LoadFromFile(Fixture('application.xml')));
  try
    AssertEquals('moduleDep count', 1, P.ModuleDependencies.Count);
    AssertEquals('moduleDep[0]', '../somelib', P.ModuleDependencies[0].Path);
  finally P.Free; end;
end;

procedure TProjectModelTests.TestApp_Dependencies;
var P: TProjectCommon;
begin
  P := TProjectCommon(TProjectBase.LoadFromFile(Fixture('application.xml')));
  try
    AssertEquals('dep count', 1, P.Dependencies.Count);
    AssertEquals('dep name',    'mylib', P.Dependencies[0].Name);
    AssertEquals('dep version', '1.0.0', P.Dependencies[0].Version);
  finally P.Free; end;
end;

{ ---- Library tests ---- }

procedure TProjectModelTests.TestLib_Type;
var P: TProjectBase;
begin
  P := TProjectBase.LoadFromFile(Fixture('library.xml'));
  try
    AssertEquals('project type', Integer(ptLibrary), Integer(P.ProjectType));
  finally P.Free; end;
end;

procedure TProjectModelTests.TestLib_Name;
var P: TProjectBase;
begin
  P := TProjectBase.LoadFromFile(Fixture('library.xml'));
  try
    AssertEquals('name', 'test-lib', P.Name);
  finally P.Free; end;
end;

{ ---- Round-trip tests ---- }

procedure TProjectModelTests.TestRoundTrip_BaseName;
var P, P2: TProjectBase;
begin
  P := TProjectBase.LoadFromFile(Fixture('pom.xml'));
  P.Name := 'renamed-pom';
  P2 := SaveAndReload(P);
  try
    AssertEquals('name after reload', 'renamed-pom', P2.Name);
  finally P2.Free; end;
end;

procedure TProjectModelTests.TestRoundTrip_AddModule;
var P: TProjectBase; P2: TProjectPOM;
begin
  P := TProjectBase.LoadFromFile(Fixture('pom.xml'));
  TProjectPOM(P).AddModule('child-c');
  P2 := TProjectPOM(SaveAndReload(P));
  try
    AssertEquals('module count after reload', 3, P2.Modules.Count);
    AssertEquals('new module path', 'child-c', P2.Modules[2].Path);
  finally P2.Free; end;
end;

procedure TProjectModelTests.TestRoundTrip_AddProfile;
var P, P2: TProjectBase; Prof: TProfile;
begin
  P := TProjectBase.LoadFromFile(Fixture('pom.xml'));
  Prof := P.AddProfile;
  Prof.ID := 'release';
  Prof.Defines.Add('RELEASE');
  P2 := SaveAndReload(P);
  try
    AssertEquals('profile count', 2, P2.Profiles.Count);
    AssertEquals('new profile id', 'release', P2.Profiles[1].ID);
    AssertEquals('new profile define', 'RELEASE', P2.Profiles[1].Defines[0]);
  finally P2.Free; end;
end;

procedure TProjectModelTests.TestRoundTrip_RemoveProfile;
var P, P2: TProjectBase;
begin
  P := TProjectBase.LoadFromFile(Fixture('pom.xml'));
  P.RemoveProfile(P.Profiles[0]);
  P2 := SaveAndReload(P);
  try
    AssertEquals('profile count after remove', 0, P2.Profiles.Count);
  finally P2.Free; end;
end;

procedure TProjectModelTests.TestRoundTrip_TestSectionRemovedWhenEmpty;
var P, P2: TProjectBase; C: TProjectCommon;
begin
  { Load application which has a <test> section, clear it, verify it disappears }
  P := TProjectBase.LoadFromFile(Fixture('application.xml'));
  C := TProjectCommon(P);
  C.TestSource  := '';
  C.TestFramework := '';
  C.FrameworkOptions.Clear;
  P2 := SaveAndReload(P);
  try
    AssertEquals('testSource empty after reload', '',
      TProjectCommon(P2).TestSource);
    AssertEquals('testFramework empty after reload', '',
      TProjectCommon(P2).TestFramework);
  finally P2.Free; end;
end;

initialization
  RegisterTest(TProjectModelTests);
end.
