{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Dialog.PackageSearch;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fgl,
  TermUI.Terminal, TermUI.Menu,
  PasbuildEditor.DependencyResolver;

{ Semver-aware comparison: returns >0 if A is newer than B. }
function CompareSemver(const A, B: string): Integer;

{ Sort a version list newest-first in place. }
procedure SortVersionsNewest(Versions: TPackageVersionList);

{ Full-screen package search + version picker.
  Returns True and fills AOutName / AOutVersion on success. }
function RunPackageSearch(AResolver: TDependencyResolver;
  out AOutName, AOutVersion: string;
  AExcludeNames: TStrings = nil;
  const ABreadcrumb: string = ''): Boolean;

implementation

uses
  PasbuildEditor.UI.Colors;

{ ══════════════════════════════════════════════════════════════════════
  Semver helpers
  ══════════════════════════════════════════════════════════════════════ }

type
  TSemver = record
    Major, Minor, Patch: Integer;
    PreRelease: string;
    IsValid: Boolean;
  end;

function ParseSemver(const S: string): TSemver;
var
  Main, Pre, Part: string;
  Dash, Dot1, Dot2: Integer;
begin
  Result.IsValid    := False;
  Result.PreRelease := '';
  Result.Major      := 0;
  Result.Minor      := 0;
  Result.Patch      := 0;

  Main := S;
  Dash := Pos('-', Main);
  if Dash > 0 then
  begin
    Pre  := Copy(Main, Dash + 1, MaxInt);
    Main := Copy(Main, 1, Dash - 1);
  end;
  { Strip build metadata }
  Dot1 := Pos('+', Main);
  if Dot1 > 0 then
    Main := Copy(Main, 1, Dot1 - 1);

  Dot1 := Pos('.', Main);
  if Dot1 = 0 then Exit;
  Dot2 := Pos('.', Main, Dot1 + 1);

  if Dot2 = 0 then
  begin
    Part := Copy(Main, 1, Dot1 - 1);
    if not TryStrToInt(Part, Result.Major) then Exit;
    Part := Copy(Main, Dot1 + 1, MaxInt);
    if not TryStrToInt(Part, Result.Minor) then Exit;
    Result.Patch := 0;
  end
  else
  begin
    Part := Copy(Main, 1, Dot1 - 1);
    if not TryStrToInt(Part, Result.Major) then Exit;
    Part := Copy(Main, Dot1 + 1, Dot2 - Dot1 - 1);
    if not TryStrToInt(Part, Result.Minor) then Exit;
    Part := Copy(Main, Dot2 + 1, MaxInt);
    if not TryStrToInt(Part, Result.Patch) then Exit;
  end;
  Result.PreRelease := Pre;
  Result.IsValid    := True;
end;

function CompareSemver(const A, B: string): Integer;
var
  SA, SB: TSemver;
begin
  SA := ParseSemver(A);
  SB := ParseSemver(B);

  if (not SA.IsValid) or (not SB.IsValid) then
  begin
    Result := CompareStr(A, B);
    Exit;
  end;

  Result := SA.Major - SB.Major;
  if Result <> 0 then Exit;
  Result := SA.Minor - SB.Minor;
  if Result <> 0 then Exit;
  Result := SA.Patch - SB.Patch;
  if Result <> 0 then Exit;

  if (SA.PreRelease = '') and (SB.PreRelease <> '') then
    Result := 1
  else if (SA.PreRelease <> '') and (SB.PreRelease = '') then
    Result := -1
  else
    Result := CompareStr(SA.PreRelease, SB.PreRelease);
end;

procedure SortVersionsNewest(Versions: TPackageVersionList);
var
  I, J:    Integer;
  Swapped: Boolean;
begin
  for I := 0 to Versions.Count - 2 do
  begin
    Swapped := False;
    for J := 0 to Versions.Count - 2 - I do
    begin
      if CompareSemver(Versions[J].Version, Versions[J + 1].Version) < 0 then
      begin
        Versions.Exchange(J, J + 1);
        Swapped := True;
      end;
    end;
    if not Swapped then Break;
  end;
end;

{ ══════════════════════════════════════════════════════════════════════
  Package search dialog
  ══════════════════════════════════════════════════════════════════════ }

type
  TSearchResult = class
  public
    Name:        string;
    SourceLabel: string;
    Versions:    TPackageVersionList;  // sorted newest-first; borrowed ref
    constructor Create(const AName, ASourceLabel: string;
      AVersions: TPackageVersionList);
  end;
  TSearchResultList = specialize TFPGObjectList<TSearchResult>;

constructor TSearchResult.Create(const AName, ASourceLabel: string;
  AVersions: TPackageVersionList);
begin
  inherited Create;
  Name        := AName;
  SourceLabel := ASourceLabel;
  Versions    := AVersions;
end;

procedure DrawSearchRow(Row: Integer; const SR: TSearchResult; Selected: Boolean;
  W: Integer);
var
  NewestVer: string;
  IsNew:     Boolean;
begin
  Term.GotoXY(1, Row);
  Term.ClearToEOL;

  if Selected then
    ColorSelFG
  else
    ColorNormal;

  if Selected then
    Term.WriteStr(' > ')
  else
    Term.WriteStr('   ');

  Term.WriteStr(PadRight(SR.Name, 30));

  if SR.Versions.Count > 0 then
  begin
    NewestVer := SR.Versions[0].Version;
    IsNew := (Pos('-', NewestVer) = 0);
    if Selected then
      Term.SetFG(clBlack)
    else if IsNew then
      ColorNew
    else
      ColorOld;
    Term.WriteStr(' ' + NewestVer);
  end;

  if not Selected then
  begin
    ColorSource;
    Term.WriteStr('  (' + SR.SourceLabel + ')');
  end;

  Term.ResetColors;
end;

function PickVersion(const APkgName: string; Versions: TPackageVersionList;
  out AVersion: string): Boolean;
var
  Sel, I, TopRow, VR, Row: Integer;
  K:   TKeyEvent;
  Ver: TPackageVersion;
begin
  Result   := False;
  AVersion := '';
  Sel      := 0;

  TopRow := 5;
  VR     := Term.Height - TopRow - 3;

  repeat
    Term.ClearScreen;
    DrawHeader('Select version: ' + APkgName, 1);

    for I := 0 to Versions.Count - 1 do
    begin
      Row := TopRow + I;
      if Row > Term.Height - 3 then Break;
      Ver := Versions[I];
      Term.GotoXY(1, Row);
      Term.ClearToEOL;
      if I = Sel then
        ColorSelFG
      else
        ColorNormal;
      if I = Sel then
        Term.WriteStr(' > ')
      else
        Term.WriteStr('   ');
      Term.WriteStr(PadRight(Ver.Version, 20));
      if Pos('-', Ver.Version) > 0 then
      begin
        if I = Sel then Term.SetFG(clBlack) else ColorOld;
        Term.WriteStr(' pre-release');
      end;
      if I = 0 then
      begin
        if I = Sel then Term.SetFG(clBlack) else ColorNew;
        Term.WriteStr(' [newest]');
      end;
      if Ver.Platform <> '' then
      begin
        if I = Sel then Term.SetFG(clBlack) else ColorSource;
        Term.WriteStr('  ' + Ver.Platform);
      end;
      Term.ResetColors;
    end;

    DrawRule(Term.Height - 1, 1, Term.Width);
    Term.GotoXY(1, Term.Height);
    ColorHelp;
    Term.WriteStr(' ↑↓ Move   Enter Select   Esc Cancel ');
    Term.ResetColors;
    Term.FlushOutput;

    K := Term.ReadKey;
    case K.Code of
      kcUp:     if Sel > 0 then Dec(Sel);
      kcDown:   if Sel < Versions.Count - 1 then Inc(Sel);
      kcEnter:  begin
        AVersion := Versions[Sel].Version;
        Result := True;
        Break;
      end;
      kcEscape: Break;
    end;
  until False;
end;

function CompareSearchResultsByName(const A, B: TSearchResult): Integer;
begin
  Result := CompareText(A.Name, B.Name);
end;

function RunPackageSearch(AResolver: TDependencyResolver;
  out AOutName, AOutVersion: string;
  AExcludeNames: TStrings;
  const ABreadcrumb: string): Boolean;
var
  Filter:      string;
  AllResults:  TSearchResultList;
  Shown:       TSearchResultList;
  AllPackages: TPackageInfoList;
  Pkg:         TPackageInfo;
  SrcIdx, I:   Integer;
  Src:         TDependencySource;
  SR:          TSearchResult;
  Sel:           Integer;
  TopRow, VR:    Integer;
  K:             TKeyEvent;
  Row:           Integer;
  NeedRefresh:   Boolean;
  FilterFocused: Boolean;

  procedure BuildShown;
  var J: Integer;
  begin
    Shown.Clear;
    for J := 0 to AllResults.Count - 1 do
      if (Filter = '') or
         (Pos(LowerCase(Filter), LowerCase(AllResults[J].Name)) > 0) then
        Shown.Add(AllResults[J]);
  end;

  procedure DrawSearchScreen;
  var J, R: Integer;
  begin
    Term.ClearScreen;
    DrawHeader(ABreadcrumb, 1);

    Term.GotoXY(1, 3);
    for J := 0 to AResolver.Sources.Count - 1 do
    begin
      Src := AResolver.Sources[J];
      if Src.IsAvailable then
        Term.SetFG(clGreen)
      else
        Term.SetFG(clRed);
      Term.WriteStr(' [' + Src.SourceLabel + ']  ');
    end;
    Term.ResetColors;

    Term.GotoXY(1, 4);
    Term.ClearToEOL;
    if FilterFocused then
      ColorSearch
    else
    begin
      Term.SetFG(clBrightBlack);
      Term.SetBG(clDefault);
    end;
    Term.WriteStr(' Filter: ' + PadRight(Filter, Term.Width - 11));
    Term.ResetColors;

    TopRow := 5;
    VR := Term.Height - TopRow - 2;

    for J := 0 to VR - 1 do
    begin
      R := TopRow + J;
      if J < Shown.Count then
        DrawSearchRow(R, Shown[J], J = Sel, Term.Width)
      else
      begin
        Term.GotoXY(1, R);
        Term.ClearToEOL;
      end;
    end;

    if Shown.Count = 0 then
    begin
      Term.GotoXY(3, TopRow);
      Term.SetFG(clBrightBlack);
      Term.WriteStr('(no packages match)');
      Term.ResetColors;
    end;

    DrawRule(Term.Height - 1, 1, Term.Width);
    Term.GotoXY(1, Term.Height);
    ColorHelp;
    Term.WriteStr(' Type to filter   ↑↓/Home/End Move   Enter Select   Esc Cancel ');
    Term.ResetColors;
    if FilterFocused then
      Term.GotoXY(10 + Length(Filter), 4)
    else
      Term.GotoXY(1, TopRow + Sel);
    Term.FlushOutput;
  end;

begin
  Result        := False;
  AOutName      := '';
  AOutVersion   := '';
  Filter        := '';
  Sel           := 0;
  TopRow        := 5;
  FilterFocused := True;

  AllResults := TSearchResultList.Create(True);
  Shown      := TSearchResultList.Create(False);
  try
    for SrcIdx := 0 to AResolver.Sources.Count - 1 do
    begin
      Src := AResolver.Sources[SrcIdx];
      if not Src.IsAvailable then Continue;
      AllPackages := Src.ListPackages;
      for I := 0 to AllPackages.Count - 1 do
      begin
        Pkg := AllPackages[I];
        if Assigned(AExcludeNames) and
           (AExcludeNames.IndexOf(Pkg.Name) >= 0) then
          Continue;
        SortVersionsNewest(Pkg.Versions);
        SR := TSearchResult.Create(Pkg.Name, Src.SourceLabel, Pkg.Versions);
        AllResults.Add(SR);
      end;
    end;
    AllResults.Sort(@CompareSearchResultsByName);

    BuildShown;
    DrawSearchScreen;
    Term.ShowCursor;

    repeat
      K := Term.ReadKey;
      NeedRefresh := False;

      if Term.HasResized then
      begin
        DrawSearchScreen;
        Continue;
      end;

      case K.Code of
        kcEscape: Break;

        kcCtrlC: begin GCtrlCRequested := True; Break; end;
        kcCtrlS: begin GSaveRequested  := True; Break; end;
        kcCtrlX: begin GCtrlXRequested := True; Break; end;

        kcUp: begin
          if Sel > 0 then Dec(Sel);
          FilterFocused := False;
          NeedRefresh := True;
        end;
        kcDown: begin
          if Sel < Shown.Count - 1 then Inc(Sel);
          FilterFocused := False;
          NeedRefresh := True;
        end;
        kcPageUp: begin
          VR := Term.Height - TopRow - 2;
          Dec(Sel, VR);
          if Sel < 0 then Sel := 0;
          FilterFocused := False;
          NeedRefresh := True;
        end;
        kcPageDown: begin
          VR := Term.Height - TopRow - 2;
          Inc(Sel, VR);
          if Sel >= Shown.Count then Sel := Shown.Count - 1;
          FilterFocused := False;
          NeedRefresh := True;
        end;
        kcHome: begin
          Sel := 0;
          FilterFocused := False;
          NeedRefresh := True;
        end;
        kcEnd: begin
          if Shown.Count > 0 then Sel := Shown.Count - 1;
          FilterFocused := False;
          NeedRefresh := True;
        end;

        kcEnter: begin
          if (Sel >= 0) and (Sel < Shown.Count) then
          begin
            SR := Shown[Sel];
            if SR.Versions.Count = 0 then
            begin
              AOutName    := SR.Name;
              AOutVersion := '';
              Result := True;
            end
            else
            begin
              Term.HideCursor;
              if PickVersion(SR.Name, SR.Versions, AOutVersion) then
              begin
                AOutName := SR.Name;
                Result   := True;
              end;
            end;
            Break;
          end;
        end;

        kcBackspace: begin
          if Length(Filter) > 0 then
          begin
            Delete(Filter, Length(Filter), 1);
            if Sel >= Shown.Count then Sel := 0;
            BuildShown;
            FilterFocused := True;
            NeedRefresh := True;
          end;
        end;

        kcChar: begin
          Filter := Filter + K.Ch;
          Sel    := 0;
          BuildShown;
          FilterFocused := True;
          NeedRefresh := True;
        end;
      end;

      if NeedRefresh then
        DrawSearchScreen;
    until False;
  finally
    Term.HideCursor;
    Shown.Free;
    AllResults.Free;
  end;
end;

end.
