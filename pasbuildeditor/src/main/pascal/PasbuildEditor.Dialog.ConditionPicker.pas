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
  TermUI.Terminal, TermUI.Menu,
  PasbuildEditor.ProjectModel;

{ Full-screen condition picker with live filter.
  Returns True and updates ACondition on accept. }
function RunConditionPicker(AProject: TProjectBase; AParentPOM: TProjectPOM;
  var ACondition: string): Boolean;

implementation

uses
  PasbuildEditor.UI.Colors,
  PasbuildEditor.UIContext,
  TermUI.Application;

function RunConditionPicker(AProject: TProjectBase; AParentPOM: TProjectPOM;
  var ACondition: string): Boolean;
const
  KNOWN: array[0..5] of string = (
    'LINUX', 'DARWIN', 'WINDOWS', 'FREEBSD', 'NETBSD', 'OPENBSD');
var
  All:           TStringList;
  Shown:         TStringList;
  Filter:        string;
  Sel:           Integer;
  FilterFocused: Boolean;
  NeedRefresh:   Boolean;
  K:             TKeyEvent;
  I:             Integer;
  TopRow, VR:    Integer;

  procedure BuildAll;
  var PI, DI: Integer; Prof: TProfile; Def: string;

    procedure CollectFromProject(APrj: TProjectBase);
    var CPI, CDI: Integer; CProf: TProfile; CDef: string;
    begin
      if not Assigned(APrj) then Exit;
      for CPI := 0 to APrj.Profiles.Count - 1 do
      begin
        CProf := APrj.Profiles[CPI];
        for CDI := 0 to CProf.Defines.Count - 1 do
        begin
          CDef := CProf.Defines[CDI];
          if All.IndexOf(CDef) < 0 then All.Add(CDef);
        end;
      end;
    end;

  begin
    All.Clear;
    for PI := Low(KNOWN) to High(KNOWN) do All.Add(KNOWN[PI]);
    CollectFromProject(AProject);
    CollectFromProject(AParentPOM);
    All.Sort;
  end;

  procedure BuildShown;
  var SI: Integer; S: string;
  begin
    Shown.Clear;
    for SI := 0 to All.Count - 1 do
    begin
      S := All[SI];
      if (Filter = '') or
         (Pos(LowerCase(Filter), LowerCase(S)) > 0) then
        Shown.Add(S);
    end;
  end;

  procedure DrawScreen;
  var R, RI: Integer;
  begin
    Term.ClearScreen;
    DrawHeader('Select Condition', 1);

    Term.GotoXY(1, 3);
    Term.ClearToEOL;
    if FilterFocused then
      ColorSearch
    else
    begin
      Term.SetFG(clBrightBlack);
      Term.SetBG(clDefault);
    end;
    Term.WriteStr(' Condition: ' + PadRight(Filter, Term.Width - 14));
    Term.ResetColors;

    TopRow := 4;
    VR := Term.Height - TopRow - 2;

    for RI := 0 to VR - 1 do
    begin
      R := TopRow + RI;
      Term.GotoXY(1, R);
      Term.ClearToEOL;
      if RI < Shown.Count then
      begin
        if (not FilterFocused) and (RI = Sel) then
        begin
          ColorSelFG;
          Term.WriteStr(' > ' + Shown[RI]);
        end
        else
        begin
          ColorNormal;
          Term.WriteStr('   ' + Shown[RI]);
        end;
        Term.ResetColors;
      end;
    end;

    if Shown.Count = 0 then
    begin
      Term.GotoXY(3, TopRow);
      Term.SetFG(clBrightBlack);
      if Filter <> '' then
        Term.WriteStr('(no match — Enter accepts "' + Filter + '" as custom value)')
      else
        Term.WriteStr('(no conditions defined)');
      Term.ResetColors;
    end;

    DrawRule(Term.Height - 1, 1, Term.Width);
    Term.GotoXY(1, Term.Height);
    ColorHelp;
    Term.WriteStr(' Type to filter   ↑↓ Move   Enter Select/Accept   Esc Cancel ');
    Term.ResetColors;
    if FilterFocused then
      Term.GotoXY(13 + Length(Filter), 3)
    else
      Term.GotoXY(1, TopRow + Sel);
    Term.FlushOutput;
  end;

begin
  Result        := False;
  Filter        := ACondition;
  Sel           := 0;
  FilterFocused := True;
  TopRow        := 4;

  All   := TStringList.Create;
  Shown := TStringList.Create;
  try
    BuildAll;
    BuildShown;
    if Filter <> '' then
    begin
      for I := 0 to Shown.Count - 1 do
        if SameText(Shown[I], Filter) then begin Sel := I; FilterFocused := False; Break; end;
    end;

    Term.ShowCursor;
    DrawScreen;

    repeat
      K := Term.ReadKey;
      NeedRefresh := False;

      if Term.HasResized then begin DrawScreen; Continue; end;

      case K.Code of
        kcEscape: Break;

        kcCtrlC: begin GCtrlCRequested := True; GQuitRequested := True; Application.Terminate; Break; end;
        kcCtrlS: begin GSaveRequested  := True; Break; end;
        kcCtrlX: begin GCtrlXRequested := True; GQuitRequested := True; Application.Terminate; Break; end;

        kcUp: begin
          if FilterFocused then
          begin
            FilterFocused := False;
            if Sel >= Shown.Count then Sel := 0;
          end
          else if Sel > 0 then Dec(Sel);
          NeedRefresh := True;
        end;
        kcDown: begin
          if FilterFocused then
          begin
            FilterFocused := False;
            if Sel >= Shown.Count then Sel := 0;
          end
          else if Sel < Shown.Count - 1 then Inc(Sel);
          NeedRefresh := True;
        end;
        kcPageUp: begin
          VR := Term.Height - TopRow - 2;
          FilterFocused := False;
          Dec(Sel, VR); if Sel < 0 then Sel := 0;
          NeedRefresh := True;
        end;
        kcPageDown: begin
          VR := Term.Height - TopRow - 2;
          FilterFocused := False;
          Inc(Sel, VR);
          if Sel >= Shown.Count then Sel := Shown.Count - 1;
          if Sel < 0 then Sel := 0;
          NeedRefresh := True;
        end;
        kcHome: begin FilterFocused := False; Sel := 0; NeedRefresh := True; end;
        kcEnd:  begin
          FilterFocused := False;
          if Shown.Count > 0 then Sel := Shown.Count - 1;
          NeedRefresh := True;
        end;

        kcEnter: begin
          if (not FilterFocused) and (Sel >= 0) and (Sel < Shown.Count) then
          begin
            ACondition := Shown[Sel];
            Result := True;
            Break;
          end
          else if Filter = '' then
          begin
            ACondition := '';
            Result := True;
            Break;
          end
          else if IsValidIdentifier(Filter) then
          begin
            ACondition := Filter;
            Result := True;
            Break;
          end
          else
          begin
            Term.HideCursor;
            Confirm('Invalid identifier. Use A-Z, a-z, _ and digits (not first char).', False);
            Term.ShowCursor;
            DrawScreen;
          end;
        end;

        kcBackspace: begin
          if Length(Filter) > 0 then
          begin
            Delete(Filter, Length(Filter), 1);
            BuildShown;
            if Sel >= Shown.Count then Sel := 0;
            FilterFocused := True;
            NeedRefresh := True;
          end;
        end;

        kcChar: begin
          Filter := Filter + K.Ch;
          BuildShown;
          Sel := 0;
          FilterFocused := True;
          NeedRefresh := True;
        end;
      end;

      if NeedRefresh then DrawScreen;
    until False;
  finally
    Term.HideCursor;
    Shown.Free;
    All.Free;
  end;
end;

end.
