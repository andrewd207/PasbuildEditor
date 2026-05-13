{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Dialog.PasbuildInit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

{ Run `pasbuild init` interactively in AWorkDir, driving its prompts via TProcess
  stdout polling. AParentLicense and AParentAuthor pre-fill relevant questions.
  Returns True on success (exit 0 and project.xml written). }
function RunPasbuildInitInteractive(const AWorkDir: string;
  const AParentLicense: string = '';
  const AParentAuthor:  string = ''): Boolean;

implementation

uses
  Process,
  TermUI.Terminal, TermUI.Menu,
  PasbuildEditor.ProjectModel,
  TermUI.Application;

{ Parse a line from pasbuild init stdout into a prompt structure.
  Returns True if the line looks like a question prompt.
  AQuestion receives the question text; ADefault the default answer;
  AOptions the list of choices (empty for free-text questions). }
function ParseInitPrompt(const Line: string;
  out AQuestion, ADefault: string; AOptions: TStringList): Boolean;
var
  S:              string;
  L, I:           Integer;
  P1, P2:         Integer;
  D1, D2:         Integer;
  OptStr:         string;
  Start:          Integer;
begin
  Result    := False;
  AQuestion := '';
  ADefault  := '';
  AOptions.Clear;

  S := Line;
  while (S <> '') and (S[Length(S)] in [#13, #10]) do
    Delete(S, Length(S), 1);

  L := Length(S);
  if (L < 2) or (S[L] <> ' ') or (S[L-1] <> ':') then Exit;
  if Copy(S, 1, 6) = '[INFO]' then Exit;

  Result := True;
  S := Copy(S, 1, L - 2);

  D2 := 0;
  for I := Length(S) downto 1 do
    if S[I] = ']' then begin D2 := I; Break; end;
  if D2 > 0 then
  begin
    D1 := 0;
    for I := D2 - 1 downto 1 do
      if S[I] = '[' then begin D1 := I; Break; end;
    if D1 > 0 then
    begin
      ADefault := Copy(S, D1 + 1, D2 - D1 - 1);
      S := TrimRight(Copy(S, 1, D1 - 1));
    end;
  end;

  P1 := 0;
  for I := 1 to Length(S) do
    if S[I] = '(' then begin P1 := I; Break; end;
  if P1 > 0 then
  begin
    P2 := 0;
    for I := Length(S) downto P1 + 1 do
      if S[I] = ')' then begin P2 := I; Break; end;
    if P2 > P1 then
    begin
      OptStr    := Copy(S, P1 + 1, P2 - P1 - 1);
      AQuestion := TrimRight(Copy(S, 1, P1 - 1));
      Start := 1;
      for I := 1 to Length(OptStr) do
        if OptStr[I] = '/' then
        begin
          AOptions.Add(Trim(Copy(OptStr, Start, I - Start)));
          Start := I + 1;
        end;
      AOptions.Add(Trim(Copy(OptStr, Start, MaxInt)));
      Exit;
    end;
  end;
  AQuestion := S;
end;

function RunPasbuildInitInteractive(const AWorkDir: string;
  const AParentLicense: string; const AParentAuthor: string): Boolean;
const
  IDLE_POLL_MS = 5;
  PROMPT_IDLE  = 20;
var
  Proc:          TProcess;
  Accum:         string;
  Buf:           array[0..511] of Byte;
  N, Idle:       Integer;
  LastNL:        Integer;
  LastLine:      string;
  I:             Integer;
  Question, Default_: string;
  Options:       TStringList;
  PickMenu:      TMenu;
  PickSel:       TMenuItem;
  Answer:        string;
  IsVersionQ:    Boolean;
  IsLicenseQ:    Boolean;
  LicenseAnswer: string;
  ChildXML:      string;
  ChildProj:     TProjectBase;
begin
  Result        := False;
  LicenseAnswer := '';
  Options       := TStringList.Create;
  Proc          := TProcess.Create(nil);
  try
    Proc.Executable       := 'pasbuild';
    Proc.Parameters.Add('init');
    Proc.CurrentDirectory := AWorkDir;
    Proc.Options          := [poUsePipes, poStderrToOutput];
    Proc.Execute;

    Accum := '';
    Idle  := 0;

    repeat
      N := Proc.Output.NumBytesAvailable;

      if N > 0 then
      begin
        if N > SizeOf(Buf) then N := SizeOf(Buf);
        N := Proc.Output.Read(Buf[0], N);
        for I := 0 to N - 1 do Accum += Chr(Buf[I]);
        Idle := 0;
        Continue;
      end;

      if not Proc.Running then Break;

      Inc(Idle);
      if Idle < PROMPT_IDLE then
      begin
        Sleep(IDLE_POLL_MS);
        Continue;
      end;
      Idle := 0;

      LastNL := 0;
      for I := Length(Accum) downto 1 do
        if Accum[I] = #10 then begin LastNL := I; Break; end;
      LastLine := StringReplace(
        Copy(Accum, LastNL + 1, MaxInt), #13, '', [rfReplaceAll]);

      if not ParseInitPrompt(LastLine, Question, Default_, Options) then
        Continue;

      IsVersionQ := (AParentLicense <> '') and (Pos('version', LowerCase(Question)) > 0);
      IsLicenseQ := (AParentLicense <> '') and (Pos('license', LowerCase(Question)) > 0);

      if (AParentAuthor <> '') and (Pos('author', LowerCase(Question)) > 0) then
        Default_ := AParentAuthor;

      if IsVersionQ then
      begin
        Answer := LineEnding;
        Proc.Input.Write(Answer[1], Length(Answer));
        Accum := '';
        Continue;
      end;

      if Options.Count > 0 then
      begin
        PickMenu := TMenu.Create(Question);
        try
          if IsLicenseQ then
            PickMenu.Add(TMenuItem.Create(
              'Use inherited (' + AParentLicense + ')', nil, 'inherited'));
          for I := 0 to Options.Count - 1 do
            PickMenu.Add(TMenuItem.Create(Options[I], nil));
          if IsLicenseQ then
            PickMenu.SelectByLabel('Use inherited (' + AParentLicense + ')')
          else if Default_ <> '' then
            PickMenu.SelectByLabel(Default_);
          PickSel := PickMenu.Run;
          if Application.Terminated or (PickSel = nil) then
          begin
            Proc.Terminate(1);
            Exit;
          end;
          if IsLicenseQ and (PickSel.Value = 'inherited') then
          begin
            LicenseAnswer := AParentLicense;
            Answer := Default_ + LineEnding;
            Proc.Input.Write(Answer[1], Length(Answer));
            Accum := '';
            Continue;
          end;
          Answer := PickSel.Label_;
          if IsLicenseQ then LicenseAnswer := Answer;
        finally
          PickMenu.Free;
        end;
      end
      else
      begin
        if not EditLine(Question, Default_, Answer) then
        begin
          Proc.Terminate(1);
          Exit;
        end;
        if Answer = '' then Answer := Default_;
      end;

      Answer += LineEnding;
      Proc.Input.Write(Answer[1], Length(Answer));
      Accum := '';
    until False;

    Proc.WaitOnExit;

    ChildXML := IncludeTrailingPathDelimiter(AWorkDir) + 'project.xml';
    if (AParentLicense <> '') and FileExists(ChildXML) then
    begin
      ChildProj := TProjectBase.LoadFromFile(ChildXML);
      if ChildProj <> nil then
      try
        ChildProj.Version := '';
        if SameText(LicenseAnswer, AParentLicense) then
          DeleteFile(IncludeTrailingPathDelimiter(AWorkDir) + 'LICENSE');
        ChildProj.SaveToFile;
      finally
        ChildProj.Free;
      end;
    end;

    Result := True;
  finally
    Options.Free;
    Proc.Free;
  end;
end;

end.
