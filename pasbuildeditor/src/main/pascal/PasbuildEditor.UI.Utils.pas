{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.UI.Utils;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  PBLib.ProjectModel;

{ Return the <name> from a module's project.xml given its absolute directory,
  falling back to the directory's base name if the file cannot be read. }
function ModuleNameFromAbsDir(const AAbsModDir: string): string;

{ Compute a relative path from AFromDir to AToDir (both absolute, no trailing sep). }
function ComputeRelativePath(const AFromDir, AToDir: string): string;

implementation

function ModuleNameFromAbsDir(const AAbsModDir: string): string;
var
  XmlPath: string;
  Sub:     TProjectBase;
begin
  Result  := ExtractFileName(ExcludeTrailingPathDelimiter(AAbsModDir));
  XmlPath := IncludeTrailingPathDelimiter(AAbsModDir) + 'project.xml';
  if not FileExists(XmlPath) then Exit;
  try
    Sub := TProjectBase.LoadFromFile(XmlPath);
    try
      if Sub.Name <> '' then Result := Sub.Name;
    finally
      Sub.Free;
    end;
  except
  end;
end;

function ComputeRelativePath(const AFromDir, AToDir: string): string;
var
  From, To_: string;
  FromParts, ToParts: TStringList;
  Common, I: Integer;
  Rel: string;
begin
  From := ExcludeTrailingPathDelimiter(AFromDir);
  To_  := ExcludeTrailingPathDelimiter(AToDir);
  if SameFileName(From, To_) then begin Result := '.'; Exit; end;
  FromParts := TStringList.Create;
  ToParts   := TStringList.Create;
  try
    FromParts.Delimiter := PathDelim;
    ToParts.Delimiter   := PathDelim;
    FromParts.StrictDelimiter := True;
    ToParts.StrictDelimiter   := True;
    FromParts.DelimitedText := From;
    ToParts.DelimitedText   := To_;
    Common := 0;
    while (Common < FromParts.Count) and (Common < ToParts.Count) and
          SameFileName(FromParts[Common], ToParts[Common]) do
      Inc(Common);
    Rel := '';
    for I := Common to FromParts.Count - 1 do
      Rel := Rel + '..' + PathDelim;
    for I := Common to ToParts.Count - 1 do
    begin
      if I > Common then Rel := Rel + PathDelim;
      Rel := Rel + ToParts[I];
    end;
    if (Rel <> '') and (Rel[Length(Rel)] = PathDelim) then
      SetLength(Rel, Length(Rel) - 1);
    Result := Rel;
  finally
    FromParts.Free;
    ToParts.Free;
  end;
end;

end.
