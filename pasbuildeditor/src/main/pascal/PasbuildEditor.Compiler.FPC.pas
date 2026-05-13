{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Compiler.FPC;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  PasbuildEditor.Compiler;

type
  TCompilerFPC = class(TCompiler)
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
  Process;

const
  CFPCExecutable = 'fpc';
  CFPCHelpFlag   = '-h';

{ Run the fpc binary with AArgs, return combined stdout+stderr, or '' on failure. }
class function TCompilerFPC.RunCompiler(const AArgs: array of string): string;
var
  Proc: TProcess;
  Buf:  array[0..4095] of Byte;
  N:    Integer;
  I:    Integer;
  Chunk: string;
begin
  Result := '';
  Proc := TProcess.Create(nil);
  try
    Proc.Executable := CFPCExecutable;
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

class function TCompilerFPC.MakeOption(const AFlag, ADesc: string): TCompilerOptionItem;
var
  LtPos: Integer;
  GtPos: Integer;
begin
  Result := TCompilerOptionItem.Create;
  Result.Flag        := AFlag;
  Result.Description := ADesc;
  LtPos := Pos('<', AFlag);
  GtPos := Pos('>', AFlag);
  if (LtPos > 0) and (GtPos > LtPos) then
  begin
    Result.HasArgument  := True;
    Result.ArgumentHint := Copy(AFlag, LtPos, GtPos - LtPos + 1);
  end
  else
    Result.HasArgument := False;
end;

{ Parse the text from 'fpc -h'.
  Lines that start with optional spaces then a '-' or '@' are option lines.
  Indented sub-options (more leading spaces + '-') are also captured.
  We skip pure-text header/footer lines and continuation descriptions. }
class procedure TCompilerFPC.ParseHelpOutput(const AText: string; AList: TCompilerOptionsList);
var
  Lines:    TStringList;
  Line:     string;
  Trimmed:  string;
  I, J:     Integer;
  Flag:     string;
  Desc:     string;
  SpacePos: Integer;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := AText;
    for I := 0 to Lines.Count - 1 do
    begin
      Line    := Lines[I];
      Trimmed := TrimLeft(Line);

      { must start with '-' or '@' to be an option line }
      if (Trimmed = '') or not (Trimmed[1] in ['-', '@']) then
        Continue;

      { split flag from description: flag ends at first run of 2+ spaces }
      J := 1;
      while J <= Length(Trimmed) do
      begin
        if (Trimmed[J] = ' ') and (J < Length(Trimmed)) and (Trimmed[J+1] = ' ') then
          Break;
        Inc(J);
      end;
      Flag := TrimRight(Copy(Trimmed, 1, J - 1));

      { skip degenerate lines }
      if (Flag = '') or (Flag = '-') then
        Continue;

      SpacePos := J;
      while (SpacePos <= Length(Trimmed)) and (Trimmed[SpacePos] = ' ') do
        Inc(SpacePos);
      Desc := Trim(Copy(Trimmed, SpacePos, MaxInt));

      AList.Add(MakeOption(Flag, Desc));
    end;
  finally
    Lines.Free;
  end;
end;

class function TCompilerFPC.Name: string;
begin
  Result := 'Free Pascal Compiler';
end;

class function TCompilerFPC.Version: string;
var
  Raw: string;
  I:   Integer;
begin
  { fpc -iV prints just the version number, e.g. '3.2.2' }
  Raw := Trim(RunCompiler(['-iV']));
  { strip anything after the first newline }
  I := Pos(#10, Raw);
  if I > 0 then Raw := Trim(Copy(Raw, 1, I - 1));
  I := Pos(#13, Raw);
  if I > 0 then Raw := Trim(Copy(Raw, 1, I - 1));
  Result := Raw;
end;

class procedure TCompilerFPC.GetOptions(AList: TCompilerOptionsList);
var
  HelpText: string;
begin
  AList.Clear;
  HelpText := RunCompiler([CFPCHelpFlag]);
  if HelpText <> '' then
    ParseHelpOutput(HelpText, AList)
  else
    BasicOptions(AList);
end;

class function TCompilerFPC.HelpPageName: string;
begin
  Result := 'fpc';
end;

class procedure TCompilerFPC.BasicOptions(AList: TCompilerOptionsList);

  procedure Add(const AFlag, ADesc: string);
  begin
    AList.Add(MakeOption(AFlag, ADesc));
  end;

begin
  Add('-O<n>',    'Optimization level (1=basic, 2=more, 3=aggressive)');
  Add('-O-',      'Disable all optimizations');
  Add('-g',       'Generate debug information');
  Add('-gw',      'Generate DWARF debug information');
  Add('-gl',      'Include line numbers in debug info');
  Add('-gh',      'Use heaptrc unit (memory leak detection)');
  Add('-B',       'Rebuild all units');
  Add('-Cn',      'Omit linking stage');
  Add('-CX',      'Create smartlinked library');
  Add('-Xs',      'Strip symbols from executable');
  Add('-XX',      'Try to smartlink units');
  Add('-dDEBUG',  'Define symbol DEBUG');
  Add('-dRELEASE','Define symbol RELEASE');
  Add('-pg',      'Generate profiling code (gprof)');
  Add('-vewhn',   'Verbose: errors, warnings, hints, notes');
end;

initialization
  TCompiler.RegisterCompiler('fpc', TCompilerFPC);

end.
