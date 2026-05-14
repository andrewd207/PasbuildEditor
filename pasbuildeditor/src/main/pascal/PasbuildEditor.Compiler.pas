{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Compiler;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fgl, Process,
  TermUI.StringUtils;

type
  TCompilerOptionItem = class
    Flag:         string;  { literal flag, e.g. '-O2' or '-O<n>' }
    Description:  string;
    HasArgument:  Boolean; { true when flag contains a placeholder like <x> or <n> }
    ArgumentHint: string;  { e.g. '<x>', '<n>' }
  end;

  TCompilerOptionsList = specialize TFPGObjectList<TCompilerOptionItem>;

  TCompiler = class;
  TCompilerClass = class of TCompiler;

  TCompiler = class
  public
    { Human-readable compiler name, e.g. 'Free Pascal Compiler' }
    class function Name: string; virtual; abstract;

    { Compiler version string, or '' when the compiler is not found }
    class function Version: string; virtual; abstract;

    { Discover available options by interrogating the compiler binary.
      Clears AList then populates it. Falls back to BasicOptions when the
      compiler is not found. Caller owns the list and all items. }
    class procedure GetOptions(AList: TCompilerOptionsList); virtual; abstract;

    { Name used when looking up help page text for this compiler }
    class function HelpPageName: string; virtual; abstract;

    { A small static set of common options shown when the compiler is absent }
    class procedure BasicOptions(AList: TCompilerOptionsList); virtual; abstract;

    { Register a compiler class under a lookup key (case-insensitive).
      Called from each compiler unit's initialization section. }
    class procedure RegisterCompiler(const AKey: string; AClass: TCompilerClass);

    { Return the compiler class registered under AKey, or nil if not found. }
    class function FindCompiler(const AKey: string): TCompilerClass;
  end;

{ Run 'pasbuild resolve' for the given module and return the compilerName value.
  Pass APomFile + AModuleName for a module project, or leave both empty for a
  root project. Returns '' when pasbuild is unavailable or the field is absent. }
function DetectCompilerName(const AProjectDir, APomFile, AModuleName: string): string;

implementation

type
  TRegistryEntry = record
    Key:   string;
    Class_: TCompilerClass;
  end;

var
  GRegistry: array of TRegistryEntry;

class procedure TCompiler.RegisterCompiler(const AKey: string; AClass: TCompilerClass);
var
  I, N: Integer;
begin
  N := Length(GRegistry);
  for I := 0 to N - 1 do
    if UpperCase(GRegistry[I].Key) = UpperCase(AKey) then
    begin
      GRegistry[I].Class_ := AClass;
      Exit;
    end;
  SetLength(GRegistry, N + 1);
  GRegistry[N].Key    := AKey;
  GRegistry[N].Class_ := AClass;
end;

class function TCompiler.FindCompiler(const AKey: string): TCompilerClass;
var
  I: Integer;
begin
  for I := 0 to High(GRegistry) do
    if UpperCase(GRegistry[I].Key) = UpperCase(AKey) then
      Exit(GRegistry[I].Class_);
  Result := nil;
end;

function DetectCompilerName(const AProjectDir, APomFile, AModuleName: string): string;
var
  Proc:   TProcess;
  Buf:    array[0..65535] of Byte;
  N:      Integer;
  Output: string;
  Chunk:  string;
  P, Q:   Integer;
begin
  Result := '';
  Proc := TProcess.Create(nil);
  try
    Proc.Executable := 'pasbuild';
    Proc.Parameters.Add('resolve');
    if APomFile <> '' then
    begin
      Proc.Parameters.Add('-f');
      Proc.Parameters.Add(APomFile);
      Proc.Parameters.Add('-m');
      Proc.Parameters.Add(AModuleName);
    end;
    Proc.CurrentDirectory := AProjectDir;
    Proc.Options := [poUsePipes, poStderrToOutput, poNoConsole];
    try
      Proc.Execute;
    except
      Exit;
    end;
    Output := '';
    repeat
      N := Proc.Output.NumBytesAvailable;
      if N = 0 then begin if not Proc.Running then Break; Sleep(10); Continue; end;
      if N > SizeOf(Buf) then N := SizeOf(Buf);
      N := Proc.Output.Read(Buf[0], N);
      if N > 0 then begin SetString(Chunk, PAnsiChar(@Buf[0]), N); Output += Chunk; end;
    until False;
    repeat
      N := Proc.Output.NumBytesAvailable;
      if N = 0 then Break;
      if N > SizeOf(Buf) then N := SizeOf(Buf);
      N := Proc.Output.Read(Buf[0], N);
      if N > 0 then begin SetString(Chunk, PAnsiChar(@Buf[0]), N); Output += Chunk; end;
    until False;
  finally
    if Proc.Running then Proc.Terminate(0);
    Proc.Free;
  end;
  if not PosNeutral('"compilerName"', Output, P) then Exit;
  { Find ':' starting from P (0-based) }
  if not PosNeutral(':', CopyNeutral(Output, P, MaxInt), Q) then Exit;
  P := P + Q + 1;  { P is now 0-based index of char after ':' }
  while (P < Length(Output)) and (Output.Index[P] in [' ', #9, '"']) do Inc(P);
  Q := P;
  while (Q < Length(Output)) and (Output.Index[Q] <> '"') do Inc(Q);
  Result := CopyNeutral(Output, P, Q - P);
end;

end.
