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
  TermUI.StringUtils,
  PBLib.ProjectModel,
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
  while (S <> '') and (S.Index[Length(S) - 1] in [#13, #10]) do
    DeleteNeutral(S, Length(S) - 1, 1);

  L := Length(S);
  if (L < 2) or (S.Index[L - 1] <> ' ') or (S.Index[L - 2] <> ':') then Exit;
  if CopyNeutral(S, 0, 6) = '[INFO]' then Exit;

  Result := True;
  S := CopyNeutral(S, 0, L - 2);

  D2 := -1;
  for I := Length(S) - 1 downto 0 do
    if S.Index[I] = ']' then begin D2 := I; Break; end;
  if D2 >= 0 then
  begin
    D1 := -1;
    for I := D2 - 1 downto 0 do
      if S.Index[I] = '[' then begin D1 := I; Break; end;
    if D1 >= 0 then
    begin
      ADefault := CopyNeutral(S, D1 + 1, D2 - D1 - 1);
      S := TrimRight(CopyNeutral(S, 0, D1));
    end;
  end;

  P1 := -1;
  for I := 0 to Length(S) - 1 do
    if S.Index[I] = '(' then begin P1 := I; Break; end;
  if P1 >= 0 then
  begin
    P2 := -1;
    for I := Length(S) - 1 downto P1 + 1 do
      if S.Index[I] = ')' then begin P2 := I; Break; end;
    if P2 > P1 then
    begin
      OptStr    := CopyNeutral(S, P1 + 1, P2 - P1 - 1);
      AQuestion := TrimRight(CopyNeutral(S, 0, P1));
      Start := 0;
      for I := 0 to Length(OptStr) - 1 do
        if OptStr.Index[I] = '/' then
        begin
          AOptions.Add(Trim(CopyNeutral(OptStr, Start, I - Start)));
          Start := I + 1;
        end;
      AOptions.Add(Trim(CopyNeutral(OptStr, Start, MaxInt)));
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

      LastNL := -1;
      for I := Length(Accum) - 1 downto 0 do
        if Accum.Index[I] = #10 then begin LastNL := I; Break; end;
      LastLine := StringReplace(
        CopyNeutral(Accum, LastNL + 1, MaxInt), #13, '', [rfReplaceAll]);

      if not ParseInitPrompt(LastLine, Question, Default_, Options) then
        Continue;

      IsVersionQ := (AParentLicense <> '') and PosNeutral('version', LowerCase(Question));
      IsLicenseQ := (AParentLicense <> '') and PosNeutral('license', LowerCase(Question));

      if (AParentAuthor <> '') and PosNeutral('author', LowerCase(Question)) then
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
