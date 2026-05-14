{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.SPDX;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  TermUI.FilteredPicker;

{ Populate AList with common SPDX identifiers and their descriptions. }
procedure PopulateSPDXList(AList: TFilteredPickerItemList);

{ Returns the name of the first license file found in ADir that does NOT
  appear to match ASpdx, or '' if everything looks consistent (or there is
  no license file at all).  Only the file name (not full path) is returned. }
function LicenseMismatchFile(const ADir, ASpdx: string): string;

implementation

procedure PopulateSPDXList(AList: TFilteredPickerItemList);
begin
  AList.Add(TFilteredPickerItem.Create('MIT',                           'MIT License'));
  AList.Add(TFilteredPickerItem.Create('Apache-2.0',                    'Apache License 2.0'));
  AList.Add(TFilteredPickerItem.Create('Apache-2.0 WITH Swift-exception', 'Apache License 2.0 with Swift Runtime Library Exception'));
  AList.Add(TFilteredPickerItem.Create('GPL-2.0-only',                  'GNU General Public License v2.0 only'));
  AList.Add(TFilteredPickerItem.Create('GPL-2.0-or-later',              'GNU General Public License v2.0 or later'));
  AList.Add(TFilteredPickerItem.Create('GPL-3.0-only',                  'GNU General Public License v3.0 only'));
  AList.Add(TFilteredPickerItem.Create('GPL-3.0-or-later',              'GNU General Public License v3.0 or later'));
  AList.Add(TFilteredPickerItem.Create('LGPL-2.0-only',                 'GNU Library General Public License v2 only'));
  AList.Add(TFilteredPickerItem.Create('LGPL-2.0-or-later',             'GNU Library General Public License v2 or later'));
  AList.Add(TFilteredPickerItem.Create('LGPL-2.0-or-later WITH FLTK-exception', 'Modified LGPL with linking exception (Lazarus/FPC style)'));
  AList.Add(TFilteredPickerItem.Create('LGPL-2.1-only',                 'GNU Lesser General Public License v2.1 only'));
  AList.Add(TFilteredPickerItem.Create('LGPL-2.1-or-later',             'GNU Lesser General Public License v2.1 or later'));
  AList.Add(TFilteredPickerItem.Create('LGPL-3.0-only',                 'GNU Lesser General Public License v3.0 only'));
  AList.Add(TFilteredPickerItem.Create('LGPL-3.0-or-later',             'GNU Lesser General Public License v3.0 or later'));
  AList.Add(TFilteredPickerItem.Create('MPL-2.0',                       'Mozilla Public License 2.0'));
  AList.Add(TFilteredPickerItem.Create('BSD-2-Clause',                  'BSD 2-Clause "Simplified" License'));
  AList.Add(TFilteredPickerItem.Create('BSD-3-Clause',                  'BSD 3-Clause "New" or "Revised" License'));
  AList.Add(TFilteredPickerItem.Create('ISC',                           'ISC License'));
  AList.Add(TFilteredPickerItem.Create('Artistic-2.0',                  'Artistic License 2.0'));
  AList.Add(TFilteredPickerItem.Create('EUPL-1.2',                      'European Union Public License 1.2'));
  AList.Add(TFilteredPickerItem.Create('AGPL-3.0-only',                 'GNU Affero General Public License v3.0 only'));
  AList.Add(TFilteredPickerItem.Create('AGPL-3.0-or-later',             'GNU Affero General Public License v3.0 or later'));
  AList.Add(TFilteredPickerItem.Create('Unlicense',                     'The Unlicense (public domain)'));
  AList.Add(TFilteredPickerItem.Create('CC0-1.0',                       'Creative Commons Zero v1.0 Universal'));
  AList.Add(TFilteredPickerItem.Create('WTFPL',                         'Do What The F*ck You Want To Public License'));
end;

{ ── Mismatch detection ──────────────────────────────────────────────── }

function LicenseMismatchFile(const ADir, ASpdx: string): string;
const
  CANDIDATES: array[0..7] of string = (
    'LICENSE', 'LICENSE.txt', 'LICENSE.md',
    'LICENCE', 'LICENCE.txt', 'LICENCE.md',
    'COPYING', 'COPYING.txt'
  );
type
  TKeywords = array of string;

  { All of Must must appear in S; none of MustNot may appear. }
  function Matches(const S: string; const Must, MustNot: TKeywords): Boolean;
  var K: string;
  begin
    for K in Must do
      if Pos(LowerCase(K), S) = 0 then Exit(False);
    for K in MustNot do
      if Pos(LowerCase(K), S) > 0 then Exit(False);
    Result := True;
  end;

  procedure KeywordsFor(const Spdx: string; out Must, MustNot: TKeywords);
  var S: string;
  begin
    S := LowerCase(Spdx);
    SetLength(Must, 0);
    SetLength(MustNot, 0);

    if (Pos('agpl', S) > 0) and (Pos('3', S) > 0) then
    begin
      Must    := ['gnu affero general public license', 'version 3'];
    end
    else if (Pos('gpl', S) > 0) and (Pos('3', S) > 0) then
    begin
      Must    := ['gnu general public license', 'version 3'];
      MustNot := ['affero'];
    end
    else if (Pos('gpl', S) > 0) and (Pos('2', S) > 0) then
    begin
      Must    := ['gnu general public license', 'version 2'];
      MustNot := ['version 3', 'affero'];
    end
    else if (Pos('lgpl', S) > 0) and (Pos('3', S) > 0) then
    begin
      Must    := ['gnu lesser general public license', 'version 3'];
    end
    else if (Pos('lgpl', S) > 0) and (Pos('2.1', S) > 0) then
    begin
      Must    := ['gnu lesser general public license', '2.1'];
      MustNot := ['version 3'];
    end
    else if (Pos('lgpl', S) > 0) and (Pos('2', S) > 0) then
    begin
      Must    := ['gnu library general public license', 'version 2'];
      MustNot := ['version 3', '2.1'];
    end
    else if Pos('mpl', S) > 0 then
    begin
      Must := ['mozilla public license'];
    end
    else if (Pos('apache', S) > 0) and (Pos('swift', S) > 0) then
    begin
      Must := ['apache license', 'swift'];
    end
    else if Pos('apache', S) > 0 then
    begin
      Must    := ['apache license'];
      MustNot := ['swift'];
    end
    else if Pos('mit', S) > 0 then
    begin
      Must    := ['permission is hereby granted', 'without restriction'];
      MustNot := ['redistribution'];
    end
    else if (Pos('bsd-3', S) > 0) or (Pos('bsd 3', S) > 0) then
    begin
      Must := ['redistribution', 'neither the name'];
    end
    else if (Pos('bsd-2', S) > 0) or (Pos('bsd 2', S) > 0) then
    begin
      Must    := ['redistribution'];
      MustNot := ['neither the name'];
    end
    else if Pos('isc', S) > 0 then
    begin
      Must    := ['permission to use, copy, modify'];
      MustNot := ['redistribution'];
    end
    else if Pos('artistic', S) > 0 then
    begin
      Must := ['artistic license'];
    end
    else if Pos('eupl', S) > 0 then
    begin
      Must := ['european union public licence'];
    end
    else if Pos('unlicense', S) > 0 then
    begin
      Must := ['this is free and unencumbered software'];
    end
    else if Pos('cc0', S) > 0 then
    begin
      Must := ['creative commons'];
    end
    else if Pos('wtfpl', S) > 0 then
    begin
      Must := ['do what the f'];
    end;
  end;

var
  Candidate: string;
  FullPath:  string;
  Content:   string;
  F:         TextFile;
  Line:      string;
  Must:      TKeywords;
  MustNot:   TKeywords;
begin
  Result := '';
  if ASpdx = '' then Exit;
  KeywordsFor(ASpdx, Must, MustNot);
  if Length(Must) = 0 then Exit;

  for Candidate in CANDIDATES do
  begin
    FullPath := IncludeTrailingPathDelimiter(ADir) + Candidate;
    if not FileExists(FullPath) then Continue;
    Content := '';
    AssignFile(F, FullPath);
    try
      Reset(F);
      while not EOF(F) and (Length(Content) < 4096) do
      begin
        ReadLn(F, Line);
        Content := Content + LowerCase(Line) + ' ';
      end;
    finally
      CloseFile(F);
    end;
    if not Matches(Content, Must, MustNot) then
      Result := Candidate;
    Exit;
  end;
end;

end.
