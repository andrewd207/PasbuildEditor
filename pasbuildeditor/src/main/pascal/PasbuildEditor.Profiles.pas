{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Profiles;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, PasbuildEditor.ProjectModel;

type
  TProfileTemplate = record
    Name: string;
    Description: string;
    Defines: array of string;
    CompilerOptions: array of string;
  end;

  TProfileTemplateArray = array of TProfileTemplate;

  TBuiltinProfiles = class
  public
    class function Templates: TProfileTemplateArray;
    class function FindTemplate(const AName: string): TProfileTemplate;
    class function TemplateNames: TStringList;
    class procedure ApplyTemplate(AProfile: TProfile; const ATemplate: TProfileTemplate);
  end;

implementation

class function TBuiltinProfiles.Templates: TProfileTemplateArray;
begin
  SetLength(Result, 7);

  Result[0].Name := 'debug';
  Result[0].Description := 'Debug build with symbols and no optimization';
  SetLength(Result[0].Defines, 1);
  Result[0].Defines[0] := 'DEBUG';
  SetLength(Result[0].CompilerOptions, 3);
  Result[0].CompilerOptions[0] := '-gw';
  Result[0].CompilerOptions[1] := '-gl';
  Result[0].CompilerOptions[2] := '-O-';

  Result[1].Name := 'release';
  Result[1].Description := 'Optimized release build';
  SetLength(Result[1].Defines, 1);
  Result[1].Defines[0] := 'RELEASE';
  SetLength(Result[1].CompilerOptions, 2);
  Result[1].CompilerOptions[0] := '-O3';
  Result[1].CompilerOptions[1] := '-CX';

  Result[2].Name := 'memleak';
  Result[2].Description := 'Memory leak detection (heaptrc)';
  SetLength(Result[2].Defines, 0);
  SetLength(Result[2].CompilerOptions, 1);
  Result[2].CompilerOptions[0] := '-gh';

  Result[3].Name := 'profiler';
  Result[3].Description := 'Profiling build with gprof support';
  SetLength(Result[3].Defines, 0);
  SetLength(Result[3].CompilerOptions, 2);
  Result[3].CompilerOptions[0] := '-pg';
  Result[3].CompilerOptions[1] := '-O-';

  Result[4].Name := 'unix';
  Result[4].Description := 'Unix/X11 platform defines';
  SetLength(Result[4].Defines, 2);
  Result[4].Defines[0] := 'X11';
  Result[4].Defines[1] := 'UseCThreads';
  SetLength(Result[4].CompilerOptions, 0);

  Result[5].Name := 'windows';
  Result[5].Description := 'Windows/GDI platform defines';
  SetLength(Result[5].Defines, 1);
  Result[5].Defines[0] := 'GDI';
  SetLength(Result[5].CompilerOptions, 0);

  Result[6].Name := 'macos';
  Result[6].Description := 'macOS/Cocoa platform defines';
  SetLength(Result[6].Defines, 1);
  Result[6].Defines[0] := 'cocoa';
  SetLength(Result[6].CompilerOptions, 0);
end;

class function TBuiltinProfiles.FindTemplate(const AName: string): TProfileTemplate;
var
  T: array of TProfileTemplate;
  I: Integer;
begin
  T := Templates;
  for I := 0 to High(T) do
    if SameText(T[I].Name, AName) then
    begin
      Result := T[I];
      Exit;
    end;
  Result.Name := '';
  Result.Description := '';
  SetLength(Result.Defines, 0);
  SetLength(Result.CompilerOptions, 0);
end;

class function TBuiltinProfiles.TemplateNames: TStringList;
var
  T: array of TProfileTemplate;
  I: Integer;
begin
  Result := TStringList.Create;
  T := Templates;
  for I := 0 to High(T) do
    Result.Add(T[I].Name);
end;

class procedure TBuiltinProfiles.ApplyTemplate(AProfile: TProfile; const ATemplate: TProfileTemplate);
var
  I: Integer;
begin
  AProfile.ID := ATemplate.Name;
  AProfile.Defines.Clear;
  for I := 0 to High(ATemplate.Defines) do
    AProfile.Defines.Add(ATemplate.Defines[I]);
  AProfile.CompilerOptions.Clear;
  for I := 0 to High(ATemplate.CompilerOptions) do
    AProfile.CompilerOptions.Add(ATemplate.CompilerOptions[I]);
end;

end.
