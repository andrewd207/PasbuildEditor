{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Compiler.Blaise;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  PasbuildEditor.Compiler;

const
  CBlaiseCompiler: String = '/home/andrew/Programming/GroupProjects/blaise/compiler/target/blaise';
  CBlaiseHelpFlag: String = '--help';

type
  TCompilerBlaise = class(TCompiler)
  public
    class function Name: string; override;
    class function Version: string; override;
    class procedure GetOptions(AList: TCompilerOptionsList); override;
    class function HelpPageName: string; override;
    class procedure BasicOptions(AList: TCompilerOptionsList); override;
  private
    class function RunCompiler(const AArgs: array of string): string;
    class procedure ParseHelpOutput(const AText: string; AList: TCompilerOptionsList);
    class function MakeOption(const AFlag, ADesc: string): TCompilerOptionItem;
  end;

implementation

uses
  Process,
  TermUI.StringUtils;

class function TCompilerBlaise.RunCompiler(const AArgs: array of string): string;
var
  Proc:  TProcess;
  Buf:   array[0..4095] of Byte;
  N, I:  Integer;
  Chunk: string;
begin
  Result := '';
  Proc := TProcess.Create(nil);
  try
    Proc.Executable := CBlaiseCompiler;
    for I := 0 to High(AArgs) do
      Proc.Parameters.Add(AArgs[I]);
    Proc.Options := [poUsePipes, poStderrToOutput, poNoConsole];
    try
      Proc.Execute;
    except
      Exit;
    end;
    repeat
      N := Proc.Output.NumBytesAvailable;
      if N = 0 then
      begin
        if not Proc.Running then Break;
        Sleep(10);
        Continue;
      end;
      if N > SizeOf(Buf) then N := SizeOf(Buf);
      N := Proc.Output.Read(Buf[0], N);
      if N > 0 then
      begin
        SetString(Chunk, PAnsiChar(@Buf[0]), N);
        Result += Chunk;
      end;
    until False;
    { drain any tail after exit }
    repeat
      N := Proc.Output.NumBytesAvailable;
      if N = 0 then Break;
      if N > SizeOf(Buf) then N := SizeOf(Buf);
      N := Proc.Output.Read(Buf[0], N);
      if N > 0 then
      begin
        SetString(Chunk, PAnsiChar(@Buf[0]), N);
        Result += Chunk;
      end;
    until False;
  finally
    if Proc.Running then Proc.Terminate(0);
    Proc.Free;
  end;
end;

class function TCompilerBlaise.MakeOption(const AFlag, ADesc: string): TCompilerOptionItem;
var
  LtPos, GtPos: Integer;
begin
  Result := TCompilerOptionItem.Create;
  Result.Flag        := AFlag;
  Result.Description := ADesc;
  if PosNeutral('<', AFlag, LtPos) and PosNeutral('>', AFlag, GtPos) and (GtPos > LtPos) then
  begin
    Result.HasArgument  := True;
    Result.ArgumentHint := CopyNeutral(AFlag, LtPos, GtPos - LtPos + 1);
  end
  else
    Result.HasArgument := False;
end;

{ Parse 'blaise --help' output.
  Flag lines begin with '--'; the flag and description are separated by 2+ spaces. }
class procedure TCompilerBlaise.ParseHelpOutput(const AText: string; AList: TCompilerOptionsList);
var
  Lines:   TStringList;
  Line:    string;
  Trimmed: string;
  I, J:    Integer;
  Flag:    string;
  Desc:    string;
  SpacePos: Integer;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := AText;
    for I := 0 to Lines.Count - 1 do
    begin
      Line    := Lines[I];
      Trimmed := TrimLeft(Line);

      if (Length(Trimmed) < 2) or (Trimmed.Index[0] <> '-') or (Trimmed.Index[1] <> '-') then
        Continue;

      { split flag from description at first run of 2+ spaces }
      J := 1;
      while J <= Length(Trimmed) do
      begin
        if (Trimmed[J] = ' ') and (J < Length(Trimmed)) and (Trimmed[J+1] = ' ') then
          Break;
        Inc(J);
      end;
      Flag := TrimRight(CopyNeutral(Trimmed, 0, J - 1));

      if (Flag = '') or (Flag = '--') then
        Continue;

      SpacePos := J;
      while (SpacePos <= Length(Trimmed)) and (Trimmed[SpacePos] = ' ') do
        Inc(SpacePos);
      Desc := Trim(CopyNeutral(Trimmed, SpacePos - 1, MaxInt));

      AList.Add(MakeOption(Flag, Desc));
    end;
  finally
    Lines.Free;
  end;
end;

class function TCompilerBlaise.Name: string;
begin
  Result := 'Blaise Compiler';
end;

{ Extract version from the first line of --help output, e.g. "Blaise Compiler v0.8.0-dev" }
class function TCompilerBlaise.Version: string;
var
  Raw:   string;
  EOL:   Integer;
  VPos:  Integer;
begin
  Raw  := RunCompiler([CBlaiseHelpFlag]);
  if PosNeutral(#10, Raw, EOL) then Raw := Trim(CopyNeutral(Raw, 0, EOL));
  if PosNeutral(#13, Raw, EOL) then Raw := Trim(CopyNeutral(Raw, 0, EOL));
  { first line is "Blaise Compiler v<ver>" }
  if PosNeutral(' v', Raw, VPos) then
    Result := CopyNeutral(Raw, VPos + 2, MaxInt)
  else
    Result := '';
end;

class procedure TCompilerBlaise.GetOptions(AList: TCompilerOptionsList);
var
  HelpText: string;
begin
  AList.Clear;
  HelpText := RunCompiler([CBlaiseHelpFlag]);
  if HelpText <> '' then
    ParseHelpOutput(HelpText, AList)
  else
    BasicOptions(AList);
end;

class function TCompilerBlaise.HelpPageName: string;
begin
  Result := 'blaise';
end;

class procedure TCompilerBlaise.BasicOptions(AList: TCompilerOptionsList);

  procedure Add(const AFlag, ADesc: string);
  begin
    AList.Add(MakeOption(AFlag, ADesc));
  end;

begin
  Add('--source <path>',   'Pascal source file');
  Add('--output <path>',   'Output binary path');
  Add('--unit-path <dir>', 'Add directory to unit search path (repeatable)');
  Add('--target <id>',     'linux-x86_64 (default), macos-arm64');
  Add('--emit-ir',         'Print QBE IR to stdout and exit');
  Add('--debug-opdf',      'Emit OPDF debug info (.opdf.s companion file)');
  Add('--cache-dir <dir>', 'Directory for per-unit IR cache (speeds up incremental builds)');
end;

end.

initialization
  TCompiler.RegisterCompiler('blaise', TCompilerBlaise);
