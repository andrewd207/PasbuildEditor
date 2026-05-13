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
  PasbuildEditor.UI.Colors,
  PasbuildEditor.UIContext,
  TermUI.Application, TermUI.Forms;

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

type
  TVersionPickerForm = class(TForm)
  private
    FPkgName:  string;
    FVersions: TPackageVersionList;
    FSel:      Integer;
    FAccepted: Boolean;
    FResult:   string;
    FTopRow:   Integer;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
  public
    procedure SetParams(const APkgName: string; AVersions: TPackageVersionList);
    function  RunModal: Boolean;
    property  Accepted: Boolean read FAccepted;
    property  Result_:  string  read FResult;
  end;

procedure TVersionPickerForm.SetParams(const APkgName: string;
  AVersions: TPackageVersionList);
begin
  FPkgName  := APkgName;
  FVersions := AVersions;
  FSel      := 0;
  FAccepted := False;
  FResult   := '';
  FTopRow   := 5;
  Invalidate;
end;

procedure TVersionPickerForm.DoPaint;
var I, Row: Integer; Ver: TPackageVersion;
begin
  Term.ClearScreen;
  DrawHeader('Select version: ' + FPkgName, 1);
  FTopRow := 5;
  for I := 0 to FVersions.Count - 1 do
  begin
    Row := FTopRow + I;
    if Row > Term.Height - 3 then Break;
    Ver := FVersions[I];
    Term.GotoXY(1, Row); Term.ClearToEOL;
    if I = FSel then ColorSelFG else ColorNormal;
    if I = FSel then Term.WriteStr(' > ') else Term.WriteStr('   ');
    Term.WriteStr(PadRight(Ver.Version, 20));
    if Pos('-', Ver.Version) > 0 then
    begin
      if I = FSel then Term.SetFG(clBlack) else ColorOld;
      Term.WriteStr(' pre-release');
    end;
    if I = 0 then
    begin
      if I = FSel then Term.SetFG(clBlack) else ColorNew;
      Term.WriteStr(' [newest]');
    end;
    if Ver.Platform <> '' then
    begin
      if I = FSel then Term.SetFG(clBlack) else ColorSource;
      Term.WriteStr('  ' + Ver.Platform);
    end;
    Term.ResetColors;
  end;
  DrawRule(Term.Height - 1, 1, Term.Width);
  Term.GotoXY(1, Term.Height); ColorHelp;
  Term.WriteStr(' ↑↓ Move   Enter Select   Esc Cancel ');
  Term.ResetColors;
  inherited DoPaint;
end;

function TVersionPickerForm.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  Result := True;
  case Key.Code of
    kcUp:     begin if FSel > 0 then Dec(FSel); Invalidate; end;
    kcDown:   begin if FSel < FVersions.Count - 1 then Inc(FSel); Invalidate; end;
    kcEnter:  begin FResult := FVersions[FSel].Version; FAccepted := True; Close(1); end;
    kcEscape: Close(1);
    else Result := False;
  end;
end;

function TVersionPickerForm.RunModal: Boolean;
begin
  FAccepted := False;
  ModalResult := 0;
  Application.ShowModal(Self);
  Result := FAccepted;
end;

function PickVersion(const APkgName: string; Versions: TPackageVersionList;
  out AVersion: string): Boolean;
var
  Form: TVersionPickerForm;
begin
  Form := TVersionPickerForm.Create;
  try
    Form.SetParams(APkgName, Versions);
    Result := Form.RunModal;
    if Result then AVersion := Form.Result_;
  finally
    Form.Free;
  end;
end;

function CompareSearchResultsByName(const A, B: TSearchResult): Integer;
begin
  Result := CompareText(A.Name, B.Name);
end;

type
  TPackageSearchForm = class(TForm)
  private
    FResolver:     TDependencyResolver;
    FExcludeNames: TStrings;
    FBreadcrumb:   string;
    FAllResults:   TSearchResultList;
    FShown:        TSearchResultList;
    FFilter:       string;
    FSel:          Integer;
    FTopRow:       Integer;
    FFilterFocused: Boolean;
    FAccepted:     Boolean;
    FOutName:      string;
    FOutVersion:   string;

    procedure BuildShown;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
  public
    constructor Create(const ATitle: string = ''); override;
    destructor  Destroy; override;

    procedure SetParams(AResolver: TDependencyResolver;
      AExcludeNames: TStrings; const ABreadcrumb: string);
    function  RunModal: Boolean;
    property  Accepted:    Boolean read FAccepted;
    property  OutName:     string  read FOutName;
    property  OutVersion:  string  read FOutVersion;
  end;

constructor TPackageSearchForm.Create(const ATitle: string);
begin
  inherited Create(ATitle);
  FAllResults := TSearchResultList.Create(True);
  FShown      := TSearchResultList.Create(False);
  FTopRow     := 5;
  FFilterFocused := True;
  FAccepted   := False;
end;

destructor TPackageSearchForm.Destroy;
begin
  FShown.Free;
  FAllResults.Free;
  inherited;
end;

procedure TPackageSearchForm.SetParams(AResolver: TDependencyResolver;
  AExcludeNames: TStrings; const ABreadcrumb: string);
var
  SrcIdx, I: Integer;
  Src: TDependencySource;
  AllPackages: TPackageInfoList;
  Pkg: TPackageInfo;
  SR: TSearchResult;
begin
  FResolver     := AResolver;
  FExcludeNames := AExcludeNames;
  FBreadcrumb   := ABreadcrumb;
  FAllResults.Clear;
  for SrcIdx := 0 to AResolver.Sources.Count - 1 do
  begin
    Src := AResolver.Sources[SrcIdx];
    if not Src.IsAvailable then Continue;
    AllPackages := Src.ListPackages;
    for I := 0 to AllPackages.Count - 1 do
    begin
      Pkg := AllPackages[I];
      if Assigned(AExcludeNames) and (AExcludeNames.IndexOf(Pkg.Name) >= 0) then Continue;
      SortVersionsNewest(Pkg.Versions);
      SR := TSearchResult.Create(Pkg.Name, Src.SourceLabel, Pkg.Versions);
      FAllResults.Add(SR);
    end;
  end;
  FAllResults.Sort(@CompareSearchResultsByName);
  FSel := 0;
  FFilter := '';
  FFilterFocused := True;
  BuildShown;
  Invalidate;
end;

procedure TPackageSearchForm.BuildShown;
var J: Integer;
begin
  FShown.Clear;
  for J := 0 to FAllResults.Count - 1 do
    if (FFilter = '') or (Pos(LowerCase(FFilter), LowerCase(FAllResults[J].Name)) > 0) then
      FShown.Add(FAllResults[J]);
end;

procedure TPackageSearchForm.DoPaint;
var J, R, VR: Integer; Src: TDependencySource;
begin
  Term.ClearScreen;
  DrawHeader(FBreadcrumb, 1);
  Term.GotoXY(1, 3);
  for J := 0 to FResolver.Sources.Count - 1 do
  begin
    Src := FResolver.Sources[J];
    if Src.IsAvailable then Term.SetFG(clGreen) else Term.SetFG(clRed);
    Term.WriteStr(' [' + Src.SourceLabel + ']  ');
  end;
  Term.ResetColors;
  Term.GotoXY(1, 4); Term.ClearToEOL;
  if FFilterFocused then ColorSearch
  else begin Term.SetFG(clBrightBlack); Term.SetBG(clDefault); end;
  Term.WriteStr(' Filter: ' + PadRight(FFilter, Term.Width - 11));
  Term.ResetColors;
  FTopRow := 5;
  VR := Term.Height - FTopRow - 2;
  for J := 0 to VR - 1 do
  begin
    R := FTopRow + J;
    if J < FShown.Count then
      DrawSearchRow(R, FShown[J], J = FSel, Term.Width)
    else
    begin
      Term.GotoXY(1, R); Term.ClearToEOL;
    end;
  end;
  if FShown.Count = 0 then
  begin
    Term.GotoXY(3, FTopRow); Term.SetFG(clBrightBlack);
    Term.WriteStr('(no packages match)'); Term.ResetColors;
  end;
  DrawRule(Term.Height - 1, 1, Term.Width);
  Term.GotoXY(1, Term.Height); ColorHelp;
  Term.WriteStr(' Type to filter   ↑↓/Home/End Move   Enter Select   Esc Cancel ');
  Term.ResetColors;
  Term.ShowCursor;
  if FFilterFocused then
    Term.GotoXY(10 + Length(FFilter), 4)
  else
    Term.GotoXY(1, FTopRow + FSel);
  inherited DoPaint;
end;

function TPackageSearchForm.DoKeyDown(var Key: TKeyEvent): Boolean;
var VR: Integer; SR: TSearchResult; Ver: string;
begin
  Result := True;
  case Key.Code of
    kcEscape: Close(1);

    kcUp: begin
      if FSel > 0 then Dec(FSel); FFilterFocused := False; Invalidate;
    end;
    kcDown: begin
      if FSel < FShown.Count - 1 then Inc(FSel); FFilterFocused := False; Invalidate;
    end;
    kcPageUp: begin
      VR := Term.Height - FTopRow - 2; Dec(FSel, VR);
      if FSel < 0 then FSel := 0; FFilterFocused := False; Invalidate;
    end;
    kcPageDown: begin
      VR := Term.Height - FTopRow - 2; Inc(FSel, VR);
      if FSel >= FShown.Count then FSel := FShown.Count - 1;
      FFilterFocused := False; Invalidate;
    end;
    kcHome: begin FSel := 0; FFilterFocused := False; Invalidate; end;
    kcEnd:  begin
      if FShown.Count > 0 then FSel := FShown.Count - 1;
      FFilterFocused := False; Invalidate;
    end;

    kcEnter: begin
      if (FSel >= 0) and (FSel < FShown.Count) then
      begin
        SR := FShown[FSel];
        if SR.Versions.Count = 0 then
        begin
          FOutName := SR.Name; FOutVersion := ''; FAccepted := True; Close(1);
        end
        else
        begin
          Ver := '';
          if PickVersion(SR.Name, SR.Versions, Ver) then
          begin
            FOutName := SR.Name; FOutVersion := Ver; FAccepted := True; Close(1);
          end
          else
            Invalidate;
        end;
      end;
    end;

    kcBackspace: begin
      if Length(FFilter) > 0 then
      begin
        Delete(FFilter, Length(FFilter), 1);
        if FSel >= FShown.Count then FSel := 0;
        BuildShown; FFilterFocused := True; Invalidate;
      end;
    end;

    kcChar:
      if Key.Ch >= ' ' then
      begin
        FFilter := FFilter + Key.Ch; FSel := 0;
        BuildShown; FFilterFocused := True; Invalidate;
      end
      else
        Result := False;

    else
      Result := False;
  end;
end;

function TPackageSearchForm.RunModal: Boolean;
begin
  FAccepted := False;
  ModalResult := 0;
  Application.ShowModal(Self);
  Term.HideCursor;
  Result := FAccepted;
end;

function RunPackageSearch(AResolver: TDependencyResolver;
  out AOutName, AOutVersion: string;
  AExcludeNames: TStrings;
  const ABreadcrumb: string): Boolean;
var
  Form: TPackageSearchForm;
begin
  Form := TPackageSearchForm.Create;
  try
    Form.SetParams(AResolver, AExcludeNames, ABreadcrumb);
    Result := Form.RunModal;
    if Result then
    begin
      AOutName    := Form.OutName;
      AOutVersion := Form.OutVersion;
    end
    else
    begin
      AOutName    := '';
      AOutVersion := '';
    end;
  finally
    Form.Free;
  end;
end;

end.
