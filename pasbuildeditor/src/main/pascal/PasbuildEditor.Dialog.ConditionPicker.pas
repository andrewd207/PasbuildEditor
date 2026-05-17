{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Dialog.ConditionPicker;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  TermUI.StringUtils,
  TermUI.Terminal, TermUI.Menu,
  PBLib.ProjectModel;

{ Full-screen condition picker with live filter.
  Returns True and updates ACondition on accept. }
function RunConditionPicker(AProject: TProjectBase; AParentPOM: TProjectPOM;
  var ACondition: string): Boolean;

implementation

uses
  PasbuildEditor.UI.Colors,
  PasbuildEditor.UIContext,
  TermUI.Application, TermUI.Forms;

type
  TConditionPickerForm = class(TForm)
  private
    FProject:      TProjectBase;
    FParentPOM:    TProjectPOM;
    FAll:          TStringList;
    FShown:        TStringList;
    FFilter:       string;
    FSel:          Integer;
    FFilterFocused: Boolean;
    FAccepted:     Boolean;
    FResult:       string;
    FTopRow:       Integer;

    procedure BuildAll;
    procedure BuildShown;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
  public
    constructor Create(const ATitle: string = ''); override;
    destructor  Destroy; override;

    procedure SetParams(AProject: TProjectBase; AParentPOM: TProjectPOM;
      const AInitial: string);
    function  RunModal: Boolean;
    property  Accepted: Boolean read FAccepted;
    property  Result_:  string  read FResult;
  end;

const
  KNOWN_CONDITIONS: array[0..13] of string = (
    'LINUX', 'DARWIN', 'WINDOWS', 'FREEBSD', 'NETBSD', 'OPENBSD', 'UNIX',
    'CPUI386', 'CPUX86_64', 'CPUARM', 'CPUAARCH64', 'CPUPOWERPC', 'CPUMIPS', 'CPURISCV64');

constructor TConditionPickerForm.Create(const ATitle: string);
begin
  inherited Create(ATitle);
  FAll      := TStringList.Create;
  FShown    := TStringList.Create;
  FTopRow   := 4;
  FAccepted := False;
end;

destructor TConditionPickerForm.Destroy;
begin
  FShown.Free;
  FAll.Free;
  inherited;
end;

procedure TConditionPickerForm.BuildAll;
  procedure CollectFromProject(APrj: TProjectBase);
  var I, J: Integer; Prof: TProfile; Def: string;
  begin
    if not Assigned(APrj) then Exit;
    for I := 0 to APrj.Profiles.Count - 1 do
    begin
      Prof := APrj.Profiles[I];
      for J := 0 to Prof.Defines.Count - 1 do
      begin
        Def := Prof.Defines[J];
        if FAll.IndexOf(Def) < 0 then FAll.Add(Def);
      end;
    end;
  end;
var I: Integer;
begin
  FAll.Clear;
  for I := Low(KNOWN_CONDITIONS) to High(KNOWN_CONDITIONS) do FAll.Add(KNOWN_CONDITIONS[I]);
  CollectFromProject(FProject);
  CollectFromProject(FParentPOM);
  FAll.Sort;
end;

procedure TConditionPickerForm.BuildShown;
var I: Integer; S: string;
begin
  FShown.Clear;
  for I := 0 to FAll.Count - 1 do
  begin
    S := FAll[I];
    if (FFilter = '') or (Pos(LowerCase(FFilter), LowerCase(S)) > 0) then
      FShown.Add(S);
  end;
end;

procedure TConditionPickerForm.SetParams(AProject: TProjectBase;
  AParentPOM: TProjectPOM; const AInitial: string);
var I: Integer;
begin
  FProject    := AProject;
  FParentPOM  := AParentPOM;
  FFilter     := AInitial;
  FSel        := 0;
  FFilterFocused := True;
  FAccepted   := False;
  FResult     := '';
  BuildAll;
  BuildShown;
  if FFilter <> '' then
    for I := 0 to FShown.Count - 1 do
      if SameText(FShown[I], FFilter) then begin FSel := I; FFilterFocused := False; Break; end;
  Invalidate;
end;

procedure TConditionPickerForm.DoPaint;
var VR, RI, R: Integer;
begin
  Term.ClearScreen;
  DrawHeader('Select Condition', 1);
  Term.GotoXY(1, 3); Term.ClearToEOL;
  if FFilterFocused then ColorSearch
  else begin Term.SetFG(clBrightBlack); Term.SetBG(clDefault); end;
  Term.WriteStr(' Condition: ' + PadRight(FFilter, Term.Width - 14));
  Term.ResetColors;

  FTopRow := 4;
  VR := Term.Height - FTopRow - 2;
  for RI := 0 to VR - 1 do
  begin
    R := FTopRow + RI;
    Term.GotoXY(1, R); Term.ClearToEOL;
    if RI < FShown.Count then
    begin
      if (not FFilterFocused) and (RI = FSel) then
        begin ColorSelFG; Term.WriteStr(' > ' + FShown[RI]); end
      else
        begin ColorNormal; Term.WriteStr('   ' + FShown[RI]); end;
      Term.ResetColors;
    end;
  end;

  if FShown.Count = 0 then
  begin
    Term.GotoXY(3, FTopRow);
    Term.SetFG(clBrightBlack);
    if FFilter <> '' then
      Term.WriteStr('(no match — Enter accepts "' + FFilter + '" as custom value)')
    else
      Term.WriteStr('(no conditions defined)');
    Term.ResetColors;
  end;

  DrawRule(Term.Height - 1, 1, Term.Width);
  Term.GotoXY(1, Term.Height); ColorHelp;
  Term.WriteStr(' Type to filter   ↑↓ Move   Enter Select/Accept   Esc Cancel ');
  Term.ResetColors;
  Term.ShowCursor;
  if FFilterFocused then
    Term.GotoXY(13 + Length(FFilter), 3)
  else
    Term.GotoXY(1, FTopRow + FSel);
  inherited DoPaint;
end;

function TConditionPickerForm.DoKeyDown(var Key: TKeyEvent): Boolean;
var VR: Integer;
begin
  Result := True;
  case Key.Code of
    kcEscape: Close(1);

    kcUp: begin
      if FFilterFocused then begin FFilterFocused := False; if FSel >= FShown.Count then FSel := 0; end
      else if FSel > 0 then Dec(FSel);
      Invalidate;
    end;
    kcDown: begin
      if FFilterFocused then begin FFilterFocused := False; if FSel >= FShown.Count then FSel := 0; end
      else if FSel < FShown.Count - 1 then Inc(FSel);
      Invalidate;
    end;
    kcPageUp: begin
      VR := Term.Height - FTopRow - 2; FFilterFocused := False;
      Dec(FSel, VR); if FSel < 0 then FSel := 0; Invalidate;
    end;
    kcPageDown: begin
      VR := Term.Height - FTopRow - 2; FFilterFocused := False;
      Inc(FSel, VR);
      if FSel >= FShown.Count then FSel := FShown.Count - 1;
      if FSel < 0 then FSel := 0;
      Invalidate;
    end;
    kcHome: begin FFilterFocused := False; FSel := 0; Invalidate; end;
    kcEnd:  begin
      FFilterFocused := False;
      if FShown.Count > 0 then FSel := FShown.Count - 1;
      Invalidate;
    end;

    kcEnter: begin
      if (not FFilterFocused) and (FSel >= 0) and (FSel < FShown.Count) then
      begin
        FResult := FShown[FSel]; FAccepted := True; Close(1);
      end
      else if FFilter = '' then
      begin
        FResult := ''; FAccepted := True; Close(1);
      end
      else if IsValidIdentifier(FFilter) then
      begin
        FResult := FFilter; FAccepted := True; Close(1);
      end
      else
        Confirm('Invalid identifier. Use A-Z, a-z, _ and digits (not first char).', False);
    end;

    kcBackspace: begin
      if Length(FFilter) > 0 then
      begin
        DeleteNeutral(FFilter, Length(FFilter) - 1, 1);
        BuildShown;
        if FSel >= FShown.Count then FSel := 0;
        FFilterFocused := True;
        Invalidate;
      end;
    end;

    kcChar:
      if Key.Ch >= ' ' then
      begin
        FFilter := FFilter + Key.Ch;
        BuildShown; FSel := 0; FFilterFocused := True; Invalidate;
      end
      else
        Result := False;

    else
      Result := False;
  end;
end;

function TConditionPickerForm.RunModal: Boolean;
begin
  FAccepted := False;
  ModalResult := 0;
  Application.ShowModal(Self);
  Term.HideCursor;
  Result := FAccepted;
end;

function RunConditionPicker(AProject: TProjectBase; AParentPOM: TProjectPOM;
  var ACondition: string): Boolean;
var
  Form: TConditionPickerForm;
begin
  Form := TConditionPickerForm.Create;
  try
    Form.SetParams(AProject, AParentPOM, ACondition);
    Result := Form.RunModal;
    if Result then ACondition := Form.Result_;
  finally
    Form.Free;
  end;
end;

end.
