{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.DependencyResolver;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fgl;

type
  { A single available version of a package }
  TPackageVersion = class
  public
    Version: string;
    { Platform variant, e.g. "x86_64-linux-3.2.2" — empty if not applicable }
    Platform: string;
    constructor Create(const AVersion, APlatform: string);
  end;
  TPackageVersionList = specialize TFPGObjectList<TPackageVersion>;

  { A package available from a source }
  TPackageInfo = class
  public
    Name: string;
    Versions: TPackageVersionList;
    constructor Create(const AName: string);
    destructor Destroy; override;
  end;
  TPackageInfoList = specialize TFPGObjectList<TPackageInfo>;

  { Abstract base — swap in a web source later without touching the UI }
  TDependencySource = class
  public
    { Returns all available packages. Caller does not own the list. }
    function ListPackages: TPackageInfoList; virtual; abstract;
    { Returns versions available for a specific package name. }
    function ListVersions(const APackageName: string): TPackageVersionList; virtual; abstract;
    { Human-readable label shown in the UI, e.g. "Local repository" or "pasbuild store" }
    function SourceLabel: string; virtual; abstract;
    { True if this source is reachable right now (local: dir exists; remote: ping) }
    function IsAvailable: Boolean; virtual; abstract;
  end;

  { Reads from ~/.pasbuild/repository/<name>/<version>/<platform>/metadata.xml }
  TLocalRepositorySource = class(TDependencySource)
  private
    FRootPath: string;
    FPackages: TPackageInfoList;
    procedure Scan;
  public
    constructor Create(const ARootPath: string = '');
    destructor Destroy; override;
    function ListPackages: TPackageInfoList; override;
    function ListVersions(const APackageName: string): TPackageVersionList; override;
    function SourceLabel: string; override;
    function IsAvailable: Boolean; override;
    property RootPath: string read FRootPath;
  end;

  { Aggregates one or more sources; first source that has a package wins }
  TDependencyResolver = class
  private
    FSources: specialize TFPGObjectList<TDependencySource>;
  public
    constructor Create;
    destructor Destroy; override;
    { Resolver takes ownership of ASource }
    procedure AddSource(ASource: TDependencySource);
    { Returns packages from all sources, merged by name }
    function ListAllPackages: TPackageInfoList;
    { Returns available sources (for UI to display / let user choose) }
    function Sources: specialize TFPGObjectList<TDependencySource>;
  end;

function DefaultResolver: TDependencyResolver;

implementation

uses
  DOM, XMLRead;

{ TPackageVersion }

constructor TPackageVersion.Create(const AVersion, APlatform: string);
begin
  inherited Create;
  Version  := AVersion;
  Platform := APlatform;
end;

{ TPackageInfo }

constructor TPackageInfo.Create(const AName: string);
begin
  inherited Create;
  Name     := AName;
  Versions := TPackageVersionList.Create(True);
end;

destructor TPackageInfo.Destroy;
begin
  Versions.Free;
  inherited;
end;

{ TLocalRepositorySource }

constructor TLocalRepositorySource.Create(const ARootPath: string = '');
begin
  inherited Create;
  if ARootPath = '' then
    FRootPath := IncludeTrailingPathDelimiter(GetUserDir) + '.pasbuild' +
                 PathDelim + 'repository'
  else
    FRootPath := ARootPath;
  FPackages := nil;
end;

destructor TLocalRepositorySource.Destroy;
begin
  FPackages.Free;
  inherited;
end;

procedure TLocalRepositorySource.Scan;
var
  PackageSR, VersionSR, PlatformSR: TSearchRec;
  PkgInfo: TPackageInfo;
  PkgVer: TPackageVersion;
  PkgPath, VerPath: string;
begin
  FreeAndNil(FPackages);
  FPackages := TPackageInfoList.Create(True);

  if not DirectoryExists(FRootPath) then
    Exit;

  if FindFirst(FRootPath + PathDelim + '*', faDirectory, PackageSR) = 0 then
  try
    repeat
      if (PackageSR.Name = '.') or (PackageSR.Name = '..') then
        Continue;
      if (PackageSR.Attr and faDirectory) = 0 then
        Continue;

      PkgPath := FRootPath + PathDelim + PackageSR.Name;
      PkgInfo := TPackageInfo.Create(PackageSR.Name);
      FPackages.Add(PkgInfo);

      if FindFirst(PkgPath + PathDelim + '*', faDirectory, VersionSR) = 0 then
      try
        repeat
          if (VersionSR.Name = '.') or (VersionSR.Name = '..') then
            Continue;
          if (VersionSR.Attr and faDirectory) = 0 then
            Continue;

          VerPath := PkgPath + PathDelim + VersionSR.Name;

          { Each version dir may contain one or more platform subdirs }
          if FindFirst(VerPath + PathDelim + '*', faDirectory, PlatformSR) = 0 then
          try
            repeat
              if (PlatformSR.Name = '.') or (PlatformSR.Name = '..') then
                Continue;
              if (PlatformSR.Attr and faDirectory) = 0 then
                Continue;
              if FileExists(VerPath + PathDelim + PlatformSR.Name + PathDelim + 'metadata.xml') then
              begin
                PkgVer := TPackageVersion.Create(VersionSR.Name, PlatformSR.Name);
                PkgInfo.Versions.Add(PkgVer);
              end;
            until FindNext(PlatformSR) <> 0;
          finally
            FindClose(PlatformSR);
          end;
        until FindNext(VersionSR) <> 0;
      finally
        FindClose(VersionSR);
      end;
    until FindNext(PackageSR) <> 0;
  finally
    FindClose(PackageSR);
  end;
end;

function TLocalRepositorySource.ListPackages: TPackageInfoList;
begin
  if not Assigned(FPackages) then
    Scan;
  Result := FPackages;
end;

function TLocalRepositorySource.ListVersions(const APackageName: string): TPackageVersionList;
var
  Pkgs: TPackageInfoList;
  I: Integer;
begin
  Pkgs := ListPackages;
  for I := 0 to Pkgs.Count - 1 do
    if SameText(Pkgs[I].Name, APackageName) then
    begin
      Result := Pkgs[I].Versions;
      Exit;
    end;
  Result := nil;
end;

function TLocalRepositorySource.SourceLabel: string;
begin
  Result := 'Local repository (' + FRootPath + ')';
end;

function TLocalRepositorySource.IsAvailable: Boolean;
begin
  Result := DirectoryExists(FRootPath);
end;

{ TDependencyResolver }

constructor TDependencyResolver.Create;
begin
  inherited Create;
  FSources := specialize TFPGObjectList<TDependencySource>.Create(True);
end;

destructor TDependencyResolver.Destroy;
begin
  FSources.Free;
  inherited;
end;

procedure TDependencyResolver.AddSource(ASource: TDependencySource);
begin
  FSources.Add(ASource);
end;

function TDependencyResolver.ListAllPackages: TPackageInfoList;
var
  I, J, K: Integer;
  SrcPkgs: TPackageInfoList;
  SrcPkg: TPackageInfo;
  Merged: TPackageInfo;
  Found: Boolean;
begin
  Result := TPackageInfoList.Create(True);
  for I := 0 to FSources.Count - 1 do
  begin
    if not FSources[I].IsAvailable then
      Continue;
    SrcPkgs := FSources[I].ListPackages;
    for J := 0 to SrcPkgs.Count - 1 do
    begin
      SrcPkg := SrcPkgs[J];
      Found := False;
      for K := 0 to Result.Count - 1 do
        if SameText(Result[K].Name, SrcPkg.Name) then
        begin
          Found := True;
          Break;
        end;
      if not Found then
      begin
        { Shallow copy — versions list points into source's memory; caller must
          not free source while using this list }
        Merged := TPackageInfo.Create(SrcPkg.Name);
        for K := 0 to SrcPkg.Versions.Count - 1 do
          Merged.Versions.Add(TPackageVersion.Create(
            SrcPkg.Versions[K].Version, SrcPkg.Versions[K].Platform));
        Result.Add(Merged);
      end;
    end;
  end;
end;

function TDependencyResolver.Sources: specialize TFPGObjectList<TDependencySource>;
begin
  Result := FSources;
end;

{ Module-level convenience }

var
  GDefaultResolver: TDependencyResolver = nil;

function DefaultResolver: TDependencyResolver;
begin
  if not Assigned(GDefaultResolver) then
  begin
    GDefaultResolver := TDependencyResolver.Create;
    GDefaultResolver.AddSource(TLocalRepositorySource.Create);
  end;
  Result := GDefaultResolver;
end;

finalization
  GDefaultResolver.Free;

end.
