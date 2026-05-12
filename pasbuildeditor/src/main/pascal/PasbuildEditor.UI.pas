unit PasbuildEditor.UI;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, fgl, Process,
  TermUI.Terminal,
  TermUI.Menu,
  TermUI.PathPicker,
  PasbuildEditor.ProjectModel,
  PasbuildEditor.DependencyResolver,
  PasbuildEditor.Profiles,
  PasbuildEditor.Consts,
  PasbuildEditor.Strings;

{ Semver-aware comparison: returns >0 if A is newer than B. }
function CompareSemver(const A, B: string): Integer;

{ Sort a version list newest-first in place. }
procedure SortVersionsNewest(Versions: TPackageVersionList);

{ Full-screen package search + version picker.
  Returns True and sets AOutName / AOutVersion on success. }
function RunPackageSearch(AResolver: TDependencyResolver;
  out AOutName, AOutVersion: string;
  AExcludeNames: TStrings = nil;
  const ABreadcrumb: string = ''): Boolean;

{ Top-level entry point: build menus from AProject and run the UI loop. }
procedure RunUI(AProject: TProjectBase; AParentPOM: TProjectPOM = nil);

implementation

{ ══════════════════════════════════════════════════════════════════════
  Colour helpers (local to this unit)
  ══════════════════════════════════════════════════════════════════════ }

procedure ColorNormal;  begin Term.ResetColors; end;
procedure ColorSelFG;   begin Term.SetFG(clBlack); Term.SetBG(clCyan); end;
procedure ColorValue;   begin Term.SetFG(clGreen); end;
procedure ColorHelp;    begin Term.SetFG(clBrightBlack); end;
procedure ColorSearch;  begin Term.SetFG(clWhite); Term.SetBG(clBlue); end;
procedure ColorSource;  begin Term.SetFG(clBrightBlack); end;
procedure ColorNew;     begin Term.SetFG(clBrightGreen); end;
procedure ColorOld;     begin Term.SetFG(clYellow); end;
procedure ColorHeader;  begin Term.SetFG(clBrightYellow); end;
procedure ColorRule;    begin Term.SetFG(clBrightBlack); end;

{ ══════════════════════════════════════════════════════════════════════
  Version sorting
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
  Result  := False;
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

{ Return the <name> from a module's project.xml given its absolute directory. }
function ModuleNameFromAbsDir(const AAbsModDir: string): string;
var
  XmlPath: string;
  Sub:     TProjectBase;
begin
  Result  := ExtractFileName(ExcludeTrailingPathDelimiter(AAbsModDir));
  XmlPath := IncludeTrailingPathDelimiter(AAbsModDir) + 'project.xml';
  if not FileExists(XmlPath) then Exit;
  try
    Sub := TProjectBase.LoadFromFile(XmlPath);
    try
      if Sub.Name <> '' then Result := Sub.Name;
    finally
      Sub.Free;
    end;
  except
  end;
end;

{ Compute a relative path from AFromDir to AToDir (both absolute, no trailing sep). }
function ComputeRelativePath(const AFromDir, AToDir: string): string;
var
  From, To_: string;
  FromParts, ToParts: TStringList;
  Common, I: Integer;
  Rel: string;
begin
  From := ExcludeTrailingPathDelimiter(AFromDir);
  To_  := ExcludeTrailingPathDelimiter(AToDir);
  if SameFileName(From, To_) then begin Result := '.'; Exit; end;
  FromParts := TStringList.Create;
  ToParts   := TStringList.Create;
  try
    FromParts.Delimiter := PathDelim;
    ToParts.Delimiter   := PathDelim;
    FromParts.StrictDelimiter := True;
    ToParts.StrictDelimiter   := True;
    FromParts.DelimitedText := From;
    ToParts.DelimitedText   := To_;
    Common := 0;
    while (Common < FromParts.Count) and (Common < ToParts.Count) and
          SameFileName(FromParts[Common], ToParts[Common]) do
      Inc(Common);
    Rel := '';
    for I := Common to FromParts.Count - 1 do
      Rel := Rel + '..' + PathDelim;
    for I := Common to ToParts.Count - 1 do
    begin
      if I > Common then Rel := Rel + PathDelim;
      Rel := Rel + ToParts[I];
    end;
    if (Rel <> '') and (Rel[Length(Rel)] = PathDelim) then
      SetLength(Rel, Length(Rel) - 1);
    Result := Rel;
  finally
    FromParts.Free;
    ToParts.Free;
  end;
end;

function RunPackageSearch(AResolver: TDependencyResolver;
  out AOutName, AOutVersion: string;
  AExcludeNames: TStrings = nil;
  const ABreadcrumb: string = ''): Boolean;
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

{ ══════════════════════════════════════════════════════════════════════
  Project editing — menu builders
  ══════════════════════════════════════════════════════════════════════ }

type
  TUIController = class
  private
    FProject:    TProjectBase;
    FBreadcrumb: string;
    FResolver:   TDependencyResolver;
    FModified:   Boolean;
    FIsRoot:     Boolean;
    FParent:     TUIController;
    FParentPOM:  TProjectPOM;
    FLastMenuLabel: string;

    procedure SetModified;
    function PromptSaveOnQuit: Boolean;
    procedure ShowAboutPage;
    procedure RunProjectMenu;
    procedure RunCommonMenu(P: TProjectCommon);
    function RunPasbuildInitInteractive(const AWorkDir: string): Boolean;
    procedure RunCreateModuleWizard(P: TProjectPOM);
    procedure RunPOMMenu(P: TProjectPOM);
    procedure RunProfileEditMenu(P: TProjectBase; AProfile: TProfile);
    procedure RunProfilesMenu(P: TProjectBase);
    function  RunDepDetailMenu(P: TProjectCommon; Dep: TDependency): Boolean;
    procedure RunDepsMenu(P: TProjectCommon);
    procedure RunModuleDepsMenu(P: TProjectCommon);
    procedure RunStringListMenu(const ATitle: string; AList: TStringList);
    procedure RunUnitPathsMenu(P: TProjectCommon);
    procedure SaveProject;
  public
    constructor Create(AProject: TProjectBase; const ABreadcrumb: string;
      AResolver: TDependencyResolver; AIsRoot: Boolean = False;
      AParent: TUIController = nil; AParentPOM: TProjectPOM = nil);
    procedure Run;
  end;

constructor TUIController.Create(AProject: TProjectBase;
  const ABreadcrumb: string; AResolver: TDependencyResolver;
  AIsRoot: Boolean; AParent: TUIController; AParentPOM: TProjectPOM);
begin
  inherited Create;
  FProject    := AProject;
  FBreadcrumb := ABreadcrumb;
  FResolver   := AResolver;
  FModified   := False;
  FIsRoot     := AIsRoot;
  FParent     := AParent;
  FParentPOM  := AParentPOM;
end;

procedure TUIController.SetModified;
begin
  FModified := True;
end;

function TUIController.PromptSaveOnQuit: Boolean;
var
  K: TKeyEvent;
begin
  Result := True;
  if not FModified then Exit;

  Term.InvalidateFront;
  Term.GotoXY(1, Term.Height - 1);
  Term.ClearToEOL;
  Term.SetFG(clBrightYellow);
  Term.WriteStr(' Unsaved changes — [Enter/Y] Save & quit   [N] Discard   [Esc] Cancel ');
  Term.ResetColors;
  Term.ShowCursor;
  Term.FlushOutput;

  repeat
    K := Term.ReadKey;
    if K.Code = kcEnter then
    begin
      Term.HideCursor;
      SaveProject;
      Exit;
    end;
    if K.Code = kcChar then
      case UpCase(K.Ch) of
        'Y': begin
          Term.HideCursor;
          SaveProject;
          Exit;
        end;
        'N': begin
          Term.HideCursor;
          Exit;
        end;
      end;
    if K.Code in [kcEscape] then
    begin
      Term.HideCursor;
      GQuitRequested  := False;
      GCtrlCRequested := False;
      GCtrlXRequested := False;
      Result := False;
      Exit;
    end;
    if K.Code = kcCtrlC then
    begin
      Term.HideCursor;
      GQuitRequested := True;
      Exit;
    end;
  until False;
end;

procedure TUIController.SaveProject;
begin
  if FProject.FileName = '' then Exit;
  try
    FProject.SaveToFile;
    FModified := False;
    Term.InvalidateFront;
    Term.GotoXY(1, Term.Height - 1);
    Term.ClearToEOL;
    Term.SetFG(clGreen);
    Term.WriteStr(' Saved: ' + FProject.FileName);
    Term.ResetColors;
    Term.FlushOutput;
    if GQuitRequested then
      Sleep(500)
    else
      Term.ReadKey;
  except
    on E: Exception do
    begin
      ShowStatusMsg('Error saving: ' + E.Message, clRed);
      Exit;
    end;
  end;
  if Assigned(FParent) and FParent.FModified then
    if Confirm('Parent project also has unsaved changes. Save parent now?', True) then
      FParent.SaveProject;
end;

procedure TUIController.RunStringListMenu(const ATitle: string; AList: TStringList);
var
  SMenu: TMenu;
  SSel:  TMenuItem;
  SVal:  string;
  J:     Integer;
begin
  repeat
    SMenu := TMenu.Create(ATitle);
    try
      SMenu.AddHeader(ExtractFileName(ATitle) + ' (' + IntToStr(AList.Count) + ')');
      SMenu.AddSeparator;
      for J := 0 to AList.Count - 1 do
        SMenu.Add(TMenuItem.Create(AList[J], nil));
      SMenu.AddSeparator;
      SMenu.Add(TMenuItem.Create('Add entry', nil, '', 'A'));

      SSel := SMenu.Run;
      if GSaveRequested then begin SaveProject; GSaveRequested := False; Continue; end;
      if GQuitRequested or GCtrlCRequested or GCtrlXRequested or
         ((SSel = nil) and (SMenu.UnhandledChar = #0)) then Break;

      if SSel.Label_ = 'Add entry' then
      begin
        if EditLine('Value', '', SVal, SMenu.SelectedRow) and (SVal <> '') then
        begin
          if not IsValidIdentifier(SVal) then
            Confirm('Invalid identifier "' + SVal +
              '". Use A-Z, a-z, _ and digits (not first char).', False)
          else
          begin
            AList.Add(SVal);
            SetModified;
          end;
        end;
      end
      else if SMenu.DeletePressed then
      begin
        if Confirm('Remove "' + SSel.Label_ + '"?') then
        begin
          J := AList.IndexOf(SSel.Label_);
          if J >= 0 then begin AList.Delete(J); SetModified; end;
        end;
      end
      else
      begin
        SVal := SSel.Label_;
        if EditLine('Edit', SVal, SVal, SMenu.SelectedRow) and (SVal <> '') and (SVal <> SSel.Label_) then
        begin
          if not IsValidIdentifier(SVal) then
            Confirm('Invalid identifier "' + SVal +
              '". Use A-Z, a-z, _ and digits (not first char).', False)
          else
          begin
            J := AList.IndexOf(SSel.Label_);
            if J >= 0 then begin AList[J] := SVal; SetModified; end;
          end;
        end;
      end;
    finally
      SMenu.Free;
    end;
  until GQuitRequested or GCtrlCRequested or GCtrlXRequested;
end;

procedure TUIController.RunProfileEditMenu(P: TProjectBase; AProfile: TProfile);
var
  Menu:      TMenu;
  Sel, It:   TMenuItem;
  NewVal:    string;
  LastLabel: string;
  I:         Integer;
  NewProf:   TProfile;
begin
  LastLabel := '';
  repeat
    Menu := TMenu.Create(FBreadcrumb + ' > Profile: ' + AProfile.ID);
    try
      Menu.AddHeader('Profile: ' + AProfile.ID);
      Menu.AddSeparator;
      Menu.Add(TMenuItem.Create('ID', nil, AProfile.ID, 'I'));
      It := TMenuItem.Create('Defines', nil,
        IfThen(AProfile.Defines.Count = 0, '(none)',
               JoinTruncated(AProfile.Defines, ' ', 35)), 'D');
      It.DimValue := (AProfile.Defines.Count = 0); Menu.Add(It);
      It := TMenuItem.Create('Compiler options', nil,
        IfThen(AProfile.CompilerOptions.Count = 0, '(none)',
               JoinTruncated(AProfile.CompilerOptions, ' ', 35)), 'C');
      It.DimValue := (AProfile.CompilerOptions.Count = 0); Menu.Add(It);
      Menu.AddSeparator;
      Menu.Add(TMenuItem.Create('Delete profile', nil, '', 'X'));
      Menu.Add(TMenuItem.Create('Duplicate profile', nil, '', 'U'));

      if LastLabel <> '' then Menu.SelectByLabel(LastLabel);
      Sel := Menu.Run;
      if GSaveRequested then begin SaveProject; GSaveRequested := False; Continue; end;
      if GQuitRequested or GCtrlCRequested or GCtrlXRequested or
         ((Sel = nil) and (Menu.UnhandledChar = #0)) then Break;

      LastLabel := Sel.Label_;
      case Sel.Label_ of
        'ID':
          begin
            NewVal := AProfile.ID;
            if EditLine('Profile ID', NewVal, NewVal, Menu.SelectedRow) and (NewVal <> '') and
               not SameText(NewVal, AProfile.ID) then
            begin
              if not IsValidIdentifier(NewVal) then
                ShowStatusMsg('Invalid identifier "' + NewVal +
                  '". Use A-Z, a-z, _ and digits (not first char).', clRed)
              else
              begin
                for I := 0 to P.Profiles.Count - 1 do
                  if (P.Profiles[I] <> AProfile) and SameText(P.Profiles[I].ID, NewVal) then
                  begin
                    ShowStatusMsg('Profile "' + NewVal + '" already exists.', clRed);
                    NewVal := '';
                    Break;
                  end;
                if NewVal <> '' then
                begin
                  AProfile.ID := NewVal;
                  SetModified;
                end;
              end;
            end;
          end;
        'Defines':
          RunStringListMenu(FBreadcrumb + ' > Profile: ' + AProfile.ID + ' > Defines',
            AProfile.Defines);
        'Compiler options':
          RunStringListMenu(FBreadcrumb + ' > Profile: ' + AProfile.ID + ' > Compiler options',
            AProfile.CompilerOptions);
        'Delete profile':
          if Confirm('Delete profile "' + AProfile.ID + '"?') then
          begin
            P.RemoveProfile(AProfile);
            SetModified;
            Break;
          end;
        'Duplicate profile':
          begin
            NewVal := AProfile.ID + '_copy';
            if EditLine('New profile ID', NewVal, NewVal, Menu.SelectedRow) and (NewVal <> '') then
            begin
              if not IsValidIdentifier(NewVal) then
              begin
                ShowStatusMsg('Invalid identifier "' + NewVal +
                  '". Use A-Z, a-z, _ and digits (not first char).', clRed);
                NewVal := '';
              end;
              if NewVal <> '' then
              begin
                NewVal := Trim(NewVal);
                I := -1;
                if NewVal <> '' then
                  for I := 0 to P.Profiles.Count - 1 do
                    if SameText(P.Profiles[I].ID, NewVal) then
                    begin
                      ShowStatusMsg('Profile "' + NewVal + '" already exists.', clRed);
                      NewVal := '';
                      Break;
                    end;
                if NewVal <> '' then
                begin
                  NewProf    := P.AddProfile;
                  NewProf.ID := NewVal;
                  for I := 0 to AProfile.Defines.Count - 1 do
                    NewProf.Defines.Add(AProfile.Defines[I]);
                  for I := 0 to AProfile.CompilerOptions.Count - 1 do
                    NewProf.CompilerOptions.Add(AProfile.CompilerOptions[I]);
                  SetModified;
                  RunProfileEditMenu(P, NewProf);
                end;
              end;
            end;
          end;
      end;
    finally
      Menu.Free;
    end;
  until GQuitRequested or GCtrlCRequested or GCtrlXRequested;
end;

procedure TUIController.RunProfilesMenu(P: TProjectBase);
var
  Menu:        TMenu;
  Prof:        TProfile;
  I:           Integer;
  Templates:   TProfileTemplateArray;
  Sel:         TMenuItem;
  TplMenu:     TMenu;
  Tpl:         TProfileTemplate;
  NewProf:     TProfile;
  NewName:     string;
  ProfSummary: string;
begin
  repeat
    Menu := TMenu.Create(FBreadcrumb + ' > Profiles');
    try
      Menu.AddHeader('Profiles (' + IntToStr(P.Profiles.Count) + ')');
      Menu.AddSeparator;
      for I := 0 to P.Profiles.Count - 1 do
      begin
        Prof := P.Profiles[I];
        ProfSummary := '';
        if Prof.Defines.Count > 0 then
          ProfSummary := 'defines: ' + JoinTruncated(Prof.Defines, ' ', 25);
        if Prof.CompilerOptions.Count > 0 then
        begin
          if ProfSummary <> '' then ProfSummary := ProfSummary + '  ';
          ProfSummary := ProfSummary + 'options: ' + JoinTruncated(Prof.CompilerOptions, ' ', 25);
        end;
        if ProfSummary = '' then ProfSummary := '(empty)';
        Menu.Add(TMenuItem.Create(Prof.ID, nil, ProfSummary));
      end;
      Menu.AddSeparator;
      Menu.Add(TMenuItem.Create('Add profile from template', nil));
      Menu.Add(TMenuItem.Create('Add blank profile', nil));

      Sel := Menu.Run;
      if GSaveRequested then begin SaveProject; GSaveRequested := False; Continue; end;
      if GQuitRequested or GCtrlCRequested or GCtrlXRequested or ((Sel = nil) and (Menu.UnhandledChar = #0)) then Break;

      if Sel.Label_ = 'Add profile from template' then
      begin
        TplMenu := TMenu.Create('Choose template');
        try
          Templates := TBuiltinProfiles.Templates;
          for I := 0 to High(Templates) do
            TplMenu.Add(TMenuItem.Create(Templates[I].Name, nil,
              Templates[I].Description));
          Sel := TplMenu.Run;
          if (not GQuitRequested) and (not GCtrlCRequested) and Assigned(Sel) then
          begin
            NewProf := nil;
            for I := 0 to P.Profiles.Count - 1 do
              if SameText(P.Profiles[I].ID, Sel.Label_) then
              begin
                NewProf := P.Profiles[I];
                Break;
              end;
            if Assigned(NewProf) then
              ShowStatusMsg('Profile "' + Sel.Label_ + '" already exists.', clRed)
            else
            begin
              Tpl     := TBuiltinProfiles.FindTemplate(Sel.Label_);
              NewProf := P.AddProfile;
              TBuiltinProfiles.ApplyTemplate(NewProf, Tpl);
              SetModified;
            end;
          end;
        finally
          TplMenu.Free;
        end;
      end
      else if Sel.Label_ = 'Add blank profile' then
      begin
        if EditLine('Profile ID', '', NewName, Menu.SelectedRow) and (NewName <> '') then
        begin
          if not IsValidIdentifier(NewName) then
            ShowStatusMsg('Invalid identifier "' + NewName +
              '". Use A-Z, a-z, _ and digits (not first char).', clRed)
          else
          begin
            NewProf := nil;
            for I := 0 to P.Profiles.Count - 1 do
              if SameText(P.Profiles[I].ID, NewName) then
              begin
                NewProf := P.Profiles[I];
                Break;
              end;
            if Assigned(NewProf) then
              ShowStatusMsg('Profile "' + NewName + '" already exists.', clRed)
            else
            begin
              NewProf    := P.AddProfile;
              NewProf.ID := NewName;
              SetModified;
            end;
          end;
        end;
      end
      else if Menu.DeletePressed then
      begin
        for I := 0 to P.Profiles.Count - 1 do
          if P.Profiles[I].ID = Sel.Label_ then
          begin
            if Confirm('Delete profile "' + Sel.Label_ + '"?') then
            begin
              P.RemoveProfile(P.Profiles[I]);
              SetModified;
            end;
            Break;
          end;
      end
      else
      begin
        for I := 0 to P.Profiles.Count - 1 do
          if P.Profiles[I].ID = Sel.Label_ then
          begin
            RunProfileEditMenu(P, P.Profiles[I]);
            Break;
          end;
      end;
    finally
      Menu.Free;
    end;
  until GQuitRequested or GCtrlCRequested or GCtrlXRequested;
end;

function TUIController.RunDepDetailMenu(P: TProjectCommon; Dep: TDependency): Boolean;
var
  SubMenu:   TMenu;
  SubSel:    TMenuItem;
  Versions:  TPackageVersionList;
  AllPkgs:   TPackageInfoList;
  I, Shown:  Integer;
  Ver:       TPackageVersion;
  Item:      TMenuItem;
  UniqVers:  TStringList;
  VerStr:    string;
begin
  Result := False;
  AllPkgs := nil;
  UniqVers := TStringList.Create;
  try
    if Assigned(FResolver) then
    begin
      AllPkgs := FResolver.ListAllPackages;
      try
        for I := 0 to AllPkgs.Count - 1 do
          if SameText(AllPkgs[I].Name, Dep.Name) then
          begin
            Versions := AllPkgs[I].Versions;
            SortVersionsNewest(Versions);
            for Ver in Versions do
              if UniqVers.IndexOf(Ver.Version) < 0 then
                UniqVers.Add(Ver.Version);
            Break;
          end;
      finally
        AllPkgs.Free;
      end;
    end;

    SubMenu := TMenu.Create(FBreadcrumb + ' > ' + Dep.Name);
    try
      SubMenu.AddHeader(Dep.Name + ' ' + Dep.Version);
      SubMenu.AddSeparator;

      Shown := 0;
      for I := 0 to UniqVers.Count - 1 do
      begin
        if Shown >= 5 then Break;
        VerStr := UniqVers[I];
        if SameText(VerStr, Dep.Version) then
          Item := TMenuItem.Create(VerStr, nil, '(current)')
        else
        begin
          Item := TMenuItem.Create(VerStr, nil);
          if CompareSemver(VerStr, Dep.Version) < 0 then
            Item.MarkOld := True;
        end;
        SubMenu.Add(Item);
        Inc(Shown);
      end;

      SubMenu.AddSeparator;
      SubMenu.Add(TMenuItem.Create('Remove dependency', nil, '', 'R'));

      SubSel := SubMenu.Run;
      if GSaveRequested then begin SaveProject; GSaveRequested := False; end;
      if GQuitRequested or GCtrlCRequested or GCtrlXRequested or (SubSel = nil) then Exit;

      if SubSel.Label_ = 'Remove dependency' then
      begin
        if Confirm('Remove dependency "' + Dep.Name + '"?') then
        begin
          P.RemoveDependency(Dep);
          SetModified;
          Result := True;
        end;
      end
      else
      begin
        if not SameText(SubSel.Label_, Dep.Version) then
        begin
          Dep.Version := SubSel.Label_;
          SetModified;
        end;
      end;
    finally
      SubMenu.Free;
    end;
  finally
    UniqVers.Free;
  end;
end;

procedure TUIController.RunDepsMenu(P: TProjectCommon);
var
  Menu:        TMenu;
  Sel, It:     TMenuItem;
  I:           Integer;
  Dep:         TDependency;
  PkgName, PkgVer: string;
  ModuleNames: TStringList;
  PomDir, AbsModDir, ModName: string;
begin
  repeat
    Menu := TMenu.Create(FBreadcrumb + ' > Dependencies');
    try
      Menu.AddHeader('External dependencies (' + IntToStr(P.Dependencies.Count) + ')');
      Menu.AddSeparator;
      for I := 0 to P.Dependencies.Count - 1 do
      begin
        Dep := P.Dependencies[I];
        It := TMenuItem.Create(Dep.Name, nil, Dep.Version);
        It.Desc := SDescDepVersion;
        Menu.Add(It);
      end;
      Menu.AddSeparator;
      It := TMenuItem.Create('Add dependency', nil);
      It.Desc := SDescDependencies;
      Menu.Add(It);

      Sel := Menu.Run;
      if GSaveRequested then begin SaveProject; GSaveRequested := False; Continue; end;
      if GQuitRequested or GCtrlCRequested or GCtrlXRequested or ((Sel = nil) and (Menu.UnhandledChar = #0)) then Break;

      if Sel.Label_ = 'Add dependency' then
      begin
        ModuleNames := TStringList.Create;
        try
          if Assigned(FParentPOM) then
          begin
            PomDir := ExcludeTrailingPathDelimiter(
                        ExtractFilePath(ExpandFileName(FParentPOM.FileName)));
            for I := 0 to FParentPOM.Modules.Count - 1 do
            begin
              AbsModDir := ExpandFileName(
                IncludeTrailingPathDelimiter(PomDir) + FParentPOM.Modules[I].Path);
              ModName := ModuleNameFromAbsDir(AbsModDir);
              if ModName <> '' then
                ModuleNames.Add(ModName);
            end;
          end;
          if RunPackageSearch(FResolver, PkgName, PkgVer, ModuleNames,
               FBreadcrumb + ' > Add Dependency') then
          begin
            if PkgVer = '' then
              EditLine('Version for ' + PkgName, '', PkgVer);
            if (PkgName <> '') and (PkgVer <> '') then
            begin
              Dep := nil;
              for I := 0 to P.Dependencies.Count - 1 do
                if SameText(P.Dependencies[I].Name, PkgName) then
                begin
                  Dep := P.Dependencies[I];
                  Break;
                end;
              if Assigned(Dep) then
              begin
                if Dep.Version <> PkgVer then
                begin
                  Dep.Version := PkgVer;
                  SetModified;
                end;
              end
              else
              begin
                P.AddDependency(PkgName, PkgVer);
                SetModified;
              end;
            end;
          end;
        finally
          ModuleNames.Free;
        end;
      end
      else
      begin
        Dep := nil;
        for I := 0 to P.Dependencies.Count - 1 do
          if P.Dependencies[I].Name = Sel.Label_ then
          begin
            Dep := P.Dependencies[I];
            Break;
          end;
        if Assigned(Dep) then
          RunDepDetailMenu(P, Dep);
      end;
    finally
      Menu.Free;
    end;
  until GQuitRequested or GCtrlCRequested or GCtrlXRequested;
end;

procedure TUIController.RunModuleDepsMenu(P: TProjectCommon);
var
  Menu:       TMenu;
  Sel:        TMenuItem;
  I:          Integer;
  Modl:       TModule;
  ModPath:    string;
  ModName:    string;
  Already:    Boolean;
  AddMenu:    TMenu;
  AddSel:     TMenuItem;
  PomDir:     string;
  ProjectDir: string;
  AbsModDir:  string;
  StorePath:  string;
  SelfItem:   TMenuItem;
  SortedMods: TStringList;
begin
  ProjectDir := ExcludeTrailingPathDelimiter(
                  ExtractFilePath(ExpandFileName(FProject.FileName)));
  PomDir     := ExcludeTrailingPathDelimiter(
                  ExtractFilePath(ExpandFileName(FParentPOM.FileName)));
  repeat
    Menu := TMenu.Create(FBreadcrumb + ' > Module Dependencies');
    try
      Menu.AddHeader('Module dependencies (' + IntToStr(P.ModuleDependencies.Count) + ')');
      Menu.AddSeparator;
      for I := 0 to P.ModuleDependencies.Count - 1 do
      begin
        ModPath   := P.ModuleDependencies[I];
        AbsModDir := ExpandFileName(IncludeTrailingPathDelimiter(ProjectDir) + ModPath);
        ModName   := ModuleNameFromAbsDir(AbsModDir);
        Menu.Add(TMenuItem.Create(ModName, nil, ModPath));
      end;
      Menu.AddSeparator;
      Menu.Add(TMenuItem.Create('Add module dependency', nil, '', 'A'));

      Sel := Menu.Run;
      if GSaveRequested then begin SaveProject; GSaveRequested := False; Continue; end;
      if GQuitRequested or GCtrlCRequested or GCtrlXRequested or ((Sel = nil) and (Menu.UnhandledChar = #0)) then Break;

      if Sel.Label_ = 'Add module dependency' then
      begin
        AddMenu := TMenu.Create(FBreadcrumb + ' > Add Module Dependency');
        try
          AddMenu.AddHeader('Sibling modules');
          AddMenu.AddSeparator;
          SortedMods := TStringList.Create;
          try
            SortedMods.Duplicates := dupAccept;
            for I := 0 to FParentPOM.Modules.Count - 1 do
            begin
              Modl      := FParentPOM.Modules[I];
              AbsModDir := ExpandFileName(IncludeTrailingPathDelimiter(PomDir) + Modl.Path);
              StorePath := ComputeRelativePath(ProjectDir,
                             ExcludeTrailingPathDelimiter(AbsModDir));
              Already   := P.ModuleDependencies.IndexOf(StorePath) >= 0;
              ModName   := ModuleNameFromAbsDir(AbsModDir);
              if StorePath = '.' then
                SortedMods.Add(#0 + ModName + '=' + StorePath)
              else if not Already then
                SortedMods.Add(ModName + '=' + StorePath);
            end;
            SortedMods.Sort;
            for I := 0 to SortedMods.Count - 1 do
            begin
              ModName   := SortedMods.Names[I];
              StorePath := SortedMods.ValueFromIndex[I];
              if (Length(ModName) > 0) and (ModName[1] = #0) then
              begin
                ModName := Copy(ModName, 2, MaxInt) + ' (current)';
                SelfItem         := TMenuItem.Create(ModName, nil, StorePath);
                SelfItem.DimItem := True;
                SelfItem.Enabled := False;
                AddMenu.Add(SelfItem);
              end
              else
                AddMenu.Add(TMenuItem.Create(ModName, nil, StorePath));
            end;
          finally
            SortedMods.Free;
          end;
          AddSel := AddMenu.Run;
          if GSaveRequested then begin SaveProject; GSaveRequested := False; Continue; end;
          if GQuitRequested or GCtrlCRequested or GCtrlXRequested then Break;
          if Assigned(AddSel) then
          begin
            P.ModuleDependencies.Add(AddSel.Value);
            SetModified;
          end;
        finally
          AddMenu.Free;
        end;
      end
      else
      begin
        ModPath := Sel.Value;
        if Confirm('Remove module dependency "' + Sel.Label_ + '"?') then
        begin
          I := P.ModuleDependencies.IndexOf(ModPath);
          if I >= 0 then
          begin
            P.ModuleDependencies.Delete(I);
            SetModified;
          end;
        end;
      end;
    finally
      Menu.Free;
    end;
  until GQuitRequested or GCtrlCRequested or GCtrlXRequested;
end;

{ Full-screen condition picker with live filter. }
function RunConditionPicker(AProject: TProjectBase; AParentPOM: TProjectPOM;
  var ACondition: string): Boolean;
const
  KNOWN: array[0..5] of string = (
    'LINUX', 'DARWIN', 'WINDOWS', 'FREEBSD', 'NETBSD', 'OPENBSD');
var
  All:          TStringList;
  Shown:        TStringList;
  Filter:       string;
  Sel:          Integer;
  FilterFocused: Boolean;
  NeedRefresh:  Boolean;
  K:            TKeyEvent;
  I:            Integer;
  TopRow, VR:  Integer;

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
  Result    := False;
  Filter    := ACondition;
  Sel       := 0;
  FilterFocused := True;
  TopRow    := 4;

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

        kcCtrlC: begin GCtrlCRequested := True; Break; end;
        kcCtrlS: begin GSaveRequested  := True; Break; end;
        kcCtrlX: begin GCtrlXRequested := True; Break; end;

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

function RunUnitPathEditor(AProject: TProjectBase; AParentPOM: TProjectPOM;
  const ABreadcrumb, ABaseDir: string;
  var APath, ACondition: string): Boolean;
var
  Menu:      TMenu;
  Sel, It:   TMenuItem;
  NewVal:    string;
  LastLabel: string;
begin
  Result    := False;
  LastLabel := '';
  repeat
    Menu := TMenu.Create(ABreadcrumb);
    try
      Menu.AddHeader('Unit Path');
      Menu.AddSeparator;
      Menu.Add(TMenuItem.Create('Path',      nil, APath,      'P'));
      It := TMenuItem.Create('Condition', nil,
        IfThen(ACondition = '', '(none)', ACondition), 'C');
      It.DimValue := (ACondition = ''); Menu.Add(It);
      Menu.AddSeparator;
      Menu.Add(TMenuItem.Create('OK',     nil, '', 'O'));
      Menu.Add(TMenuItem.Create('Cancel', nil, '', 'X'));

      if LastLabel <> '' then Menu.SelectByLabel(LastLabel);
      Sel := Menu.Run;
      if GQuitRequested or GCtrlCRequested or GCtrlXRequested or GSaveRequested then Break;
      if Sel = nil then Break;
      LastLabel := Sel.Label_;

      if Sel.Label_ = 'Path' then
      begin
        NewVal := APath;
        if RunPathPicker(ABaseDir, ABreadcrumb + ' > Path', True, NewVal) then APath := NewVal;
      end
      else if Sel.Label_ = 'Condition' then
      begin
        NewVal := ACondition;
        if RunConditionPicker(AProject, AParentPOM, NewVal) then ACondition := NewVal;
      end
      else if Sel.Label_ = 'OK' then
      begin
        if APath <> '' then
        begin
          if SameFileName(
               ExcludeTrailingPathDelimiter(ExpandFileName(
                 IncludeTrailingPathDelimiter(ABaseDir) + APath)),
               ExcludeTrailingPathDelimiter(ExpandFileName(ABaseDir))) then
            ShowStatusMsg('Path cannot be the same as the source directory.', clRed)
          else
            Result := True;
        end;
        if Result then Break;
      end
      else if Sel.Label_ = 'Cancel' then
        Break;
    finally
      Menu.Free;
    end;
  until GQuitRequested or GCtrlCRequested or GCtrlXRequested;
end;

procedure TUIController.RunUnitPathsMenu(P: TProjectCommon);
var
  Menu:      TMenu;
  Sel:       TMenuItem;
  I:         Integer;
  CP:        TConditionalPath;
  Path, Cond: string;
  LastLabel: string;
  Common, First, Other, OtherDir: string;
  ProjectDir, SrcBaseDir: string;
begin
  LastLabel  := '';
  ProjectDir := ExtractFilePath(ExpandFileName(FProject.FileName));
  if (P is TProjectCommon) and (TProjectCommon(P).SourceDirectory <> '') then
    SrcBaseDir := ExpandFileName(IncludeTrailingPathDelimiter(ProjectDir) +
                    TProjectCommon(P).SourceDirectory)
  else
    SrcBaseDir := ProjectDir;
  repeat
    Menu := TMenu.Create(FBreadcrumb + ' > Unit Paths');
    try
      Menu.AddHeader('Unit paths (' + IntToStr(P.UnitPaths.Count) + ')');
      Menu.AddSeparator;
      for I := 0 to P.UnitPaths.Count - 1 do
      begin
        CP := P.UnitPaths[I];
        if CP.Condition <> '' then
          Menu.Add(TMenuItem.Create(CP.Path, nil, '[' + CP.Condition + ']'))
        else
          Menu.Add(TMenuItem.Create(CP.Path, nil));
      end;
      Menu.AddSeparator;
      Menu.Add(TMenuItem.Create('Add path', nil, '', 'A'));

      if LastLabel <> '' then Menu.SelectByLabel(LastLabel);
      Sel := Menu.Run;
      if GSaveRequested then begin SaveProject; GSaveRequested := False; Continue; end;
      if GQuitRequested or GCtrlCRequested or GCtrlXRequested or
         ((Sel = nil) and (Menu.UnhandledChar = #0)) then Break;
      if Sel = nil then Continue;
      LastLabel := Sel.Label_;

      if Sel.Label_ = 'Add path' then
      begin
        Path := '';
        if P.UnitPaths.Count > 0 then
        begin
          First  := ExcludeTrailingPathDelimiter(P.UnitPaths[0].Path);
          Common := ExtractFilePath(First);
          for I := 1 to P.UnitPaths.Count - 1 do
          begin
            Other    := ExcludeTrailingPathDelimiter(P.UnitPaths[I].Path);
            OtherDir := ExtractFilePath(Other);
            while (Common <> '') and
                  (Pos(LowerCase(ExcludeTrailingPathDelimiter(Common)),
                       LowerCase(OtherDir)) <> 1) do
              Common := ExtractFilePath(ExcludeTrailingPathDelimiter(Common));
          end;
          Path := Common;
        end;
        Cond := '';
        if RunUnitPathEditor(FProject, FParentPOM, FBreadcrumb + ' > Unit Paths > Add',
             SrcBaseDir, Path, Cond) and (Path <> '') then
        begin
          P.AddUnitPath(Path, Cond);
          SetModified;
          LastLabel := Path;
        end;
      end
      else
      begin
        CP := nil;
        for I := 0 to P.UnitPaths.Count - 1 do
          if P.UnitPaths[I].Path = Sel.Label_ then begin CP := P.UnitPaths[I]; Break; end;
        if not Assigned(CP) then Continue;

        Path := CP.Path;
        Cond := CP.Condition;
        if RunUnitPathEditor(FProject, FParentPOM,
             FBreadcrumb + ' > Unit Paths > ' + Path, SrcBaseDir, Path, Cond) then
        begin
          P.RemoveUnitPath(CP);
          P.AddUnitPath(Path, Cond);
          SetModified;
          LastLabel := Path;
        end
        else
        begin
          if Menu.ExitedLeft then
          begin
            if Confirm('Remove path ' + CP.Path + '?') then
            begin
              P.RemoveUnitPath(CP);
              SetModified;
              LastLabel := '';
            end;
          end;
        end;
      end;
    finally
      Menu.Free;
    end;
  until GQuitRequested or GCtrlCRequested or GCtrlXRequested;
end;

procedure TUIController.RunCommonMenu(P: TProjectCommon);
var
  Menu:      TMenu;
  Sel:       TMenuItem;
  It:        TMenuItem;
  NewVal:    string;
  LastLabel: string;
  DepNames:  TStringList;
  DepVal:    string;
  DI:        Integer;
begin
  LastLabel := '';
  repeat
    Menu := TMenu.Create(FBreadcrumb);
    try
      Menu.AddHeader('Build');
      if P.ProjectType = ptApplication then
      begin
        It := TMenuItem.Create('Main source', nil, P.MainSource, 'S');
        It.Desc := SDescMainSource; Menu.Add(It);
      end;
      It := TMenuItem.Create('Output directory', nil, P.OutputDirectory, 'O');
      It.Desc := SDescOutputDir; Menu.Add(It);
      It := TMenuItem.Create('Source directory', nil, P.SourceDirectory, 'C');
      It.Desc := SDescSourceDir; Menu.Add(It);
      if P.ProjectType = ptApplication then
      begin
        It := TMenuItem.Create('Executable name', nil, P.ExecutableName, 'X');
        It.Desc := SDescExeName; Menu.Add(It);
      end;
      Menu.AddSeparator;
      It := TMenuItem.Create('Unit paths', nil,
        IntToStr(P.UnitPaths.Count) + ' entries', 'U');
      It.Desc := SDescUnitPaths; Menu.Add(It);
      It := TMenuItem.Create('Defines', nil,
        IfThen(P.Defines.Count = 0, '(none)',
               JoinTruncated(P.Defines, ' ', 35)), 'F');
      It.DimValue := (P.Defines.Count = 0);
      It.Desc := SDescDefines; Menu.Add(It);
      Menu.AddSeparator;
      DepNames := TStringList.Create;
      try
        for DI := 0 to P.Dependencies.Count - 1 do
          DepNames.Add(P.Dependencies[DI].Name);
        if DepNames.Count = 0 then DepVal := '(none)'
        else DepVal := JoinTruncated(DepNames, ', ', 35);
      finally
        DepNames.Free;
      end;
      It := TMenuItem.Create('Dependencies', nil, DepVal, 'D');
      It.DimValue := (P.Dependencies.Count = 0);
      It.Desc := SDescDependencies; Menu.Add(It);
      if Assigned(FParentPOM) then
      begin
        DepNames := TStringList.Create;
        try
          for DI := 0 to P.ModuleDependencies.Count - 1 do
            DepNames.Add(P.ModuleDependencies[DI]);
          if DepNames.Count = 0 then DepVal := '(none)'
          else DepVal := JoinTruncated(DepNames, ', ', 35);
        finally
          DepNames.Free;
        end;
        It := TMenuItem.Create('Module dependencies', nil, DepVal, 'M');
        It.DimValue := (P.ModuleDependencies.Count = 0);
        It.Desc := SDescModuleDeps; Menu.Add(It);
      end;

      if LastLabel <> '' then Menu.SelectByLabel(LastLabel);
      Sel := Menu.Run;

      if GSaveRequested then begin SaveProject; GSaveRequested := False; Continue; end;
      if GQuitRequested or GCtrlCRequested or GCtrlXRequested or ((Sel = nil) and (Menu.UnhandledChar = #0)) then Break;
      LastLabel := Sel.Label_;

      case Sel.Label_ of
        'Main source': begin
          NewVal := P.MainSource;
          if RunPathPicker(ExtractFilePath(ExpandFileName(FProject.FileName)),
               FBreadcrumb + ' > Main Source', False, NewVal) then
            begin P.MainSource := NewVal; SetModified; end;
        end;
        'Output directory': begin
          NewVal := P.OutputDirectory;
          if RunPathPicker(ExtractFilePath(ExpandFileName(FProject.FileName)),
               FBreadcrumb + ' > Output Directory', True, NewVal) then
            begin P.OutputDirectory := NewVal; SetModified; end;
        end;
        'Source directory': begin
          NewVal := P.SourceDirectory;
          if RunPathPicker(ExtractFilePath(ExpandFileName(FProject.FileName)),
               FBreadcrumb + ' > Source Directory', True, NewVal) then
            begin P.SourceDirectory := NewVal; SetModified; end;
        end;
        'Executable name':
          if EditLine('Executable name', P.ExecutableName, NewVal, Menu.SelectedRow) then
            begin P.ExecutableName := NewVal; SetModified; end;
        'Unit paths':          RunUnitPathsMenu(P);
        'Defines':
          RunStringListMenu(FBreadcrumb + ' > Defines', P.Defines);
        'Dependencies':        RunDepsMenu(P);
        'Module dependencies': RunModuleDepsMenu(P);
      end;
    finally
      Menu.Free;
    end;
  until GQuitRequested or GCtrlCRequested or GCtrlXRequested;
end;

{ ══════════════════════════════════════════════════════════════════════
  pasbuild init — dynamic prompt parsing via TProcess stdout polling
  ══════════════════════════════════════════════════════════════════════ }

function ParseInitPrompt(const Line: string;
  out AQuestion, ADefault: string; AOptions: TStringList): Boolean;
var
  S:              string;
  L, I:          Integer;
  P1, P2:        Integer;
  D1, D2:        Integer;
  OptStr:        string;
  Start:         Integer;
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

function TUIController.RunPasbuildInitInteractive(const AWorkDir: string): Boolean;
const
  IDLE_POLL_MS  = 5;
  PROMPT_IDLE   = 20;
var
  Proc:     TProcess;
  Accum:    string;
  Buf:      array[0..511] of Byte;
  N, Idle:  Integer;
  LastNL:   Integer;
  LastLine: string;
  I:        Integer;
  Question, Default_: string;
  Options:  TStringList;
  PickMenu: TMenu;
  PickSel:  TMenuItem;
  Answer:   string;
begin
  Result  := False;
  Options := TStringList.Create;
  Proc    := TProcess.Create(nil);
  try
    Proc.Executable      := 'pasbuild';
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

      if Options.Count > 0 then
      begin
        PickMenu := TMenu.Create(Question);
        try
          for I := 0 to Options.Count - 1 do
            PickMenu.Add(TMenuItem.Create(Options[I], nil));
          if Default_ <> '' then PickMenu.SelectByLabel(Default_);
          PickSel := PickMenu.Run;
          if GQuitRequested or GCtrlCRequested or GCtrlXRequested or (PickSel = nil) then
          begin
            Proc.Terminate(1);
            Exit;
          end;
          Answer := PickSel.Label_;
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
    Result := True;
  finally
    Options.Free;
    Proc.Free;
  end;
end;

procedure TUIController.RunCreateModuleWizard(P: TProjectPOM);
var
  FolderName: string;
  FullDir:    string;
  ModPath:    string;
  I:          Integer;

  procedure ShowMsg(const S: string; AColor: TColor);
  begin
    Term.GotoXY(1, Term.Height - 1);
    Term.ClearToEOL;
    Term.SetFG(AColor);
    Term.WriteStr(' ' + S);
    Term.ResetColors;
    Term.FlushOutput;
    Term.ReadKey;
  end;

begin
  if not EditLine('New module folder name', '', FolderName) or (FolderName = '') then Exit;

  FullDir := IncludeTrailingPathDelimiter(ExtractFilePath(FProject.FileName)) + FolderName;
  if DirectoryExists(FullDir) then
  begin
    ShowMsg('Folder already exists: ' + FullDir, clRed);
    Exit;
  end;

  ModPath := FolderName;
  for I := 0 to P.Modules.Count - 1 do
    if SameText(P.Modules[I].Path, ModPath) then
    begin
      ShowMsg('Module already listed: ' + FolderName, clRed);
      Exit;
    end;

  if not ForceDirectories(FullDir) then
  begin
    ShowMsg('Could not create directory: ' + FullDir, clRed);
    Exit;
  end;

  if RunPasbuildInitInteractive(FullDir) then
  begin
    P.AddModule(ModPath, True);
    SetModified;
    ShowMsg('Created ' + FolderName + ' and added to modules.', clBrightCyan);
  end
  else
  begin
    if not FileExists(FullDir + '/project.xml') then
      RemoveDir(FullDir);
  end;
end;

procedure TUIController.RunPOMMenu(P: TProjectPOM);
var
  Menu:        TMenu;
  Sel:         TMenuItem;
  Item:        TMenuItem;
  I:           Integer;
  LastLabel:   string;
  NewPath:     string;
  SR:          TSearchRec;
  BaseDir:     string;
  CandPath:    string;
  AlreadyIn:   Boolean;
  Added:       Integer;
  Modl:        TModule;
  SelIdx:      Integer;
  SubProject:  TProjectBase;
  Sub:         TUIController;
  ModFilePath: string;
  UChar:       Char;
  ScanMenu:    TMenu;
  ScanSel:     TMenuItem;
  CandName:    string;

  function ModuleAtMenuIdx(Idx: Integer): TModule;
  var J: Integer;
  begin
    Result := nil;
    J := Idx - 2;  // 2 = header + separator
    if (J >= 0) and (J < P.Modules.Count) then
      Result := P.Modules[J];
  end;

begin
  LastLabel := '';
  repeat
    Menu := TMenu.Create(FBreadcrumb + ' > Modules');
    try
      Item := TMenuItem.CreateHeader('Modules (' + IntToStr(P.Modules.Count) + ')');
      Item.Hint := '[E]nable  [D]isable';
      Menu.Add(Item);
      Menu.AddSeparator;
      for I := 0 to P.Modules.Count - 1 do
      begin
        Modl     := P.Modules[I];
        CandName := ModuleNameFromAbsDir(
          IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(FProject.FileName)))
          + Modl.Path);
        if Modl.ActiveByDefault then
          Item := TMenuItem.Create(CandName, nil, Modl.Path)
        else
        begin
          Item := TMenuItem.Create(CandName + ' (disabled)', nil, Modl.Path);
          Item.DimItem := True;
        end;
        Menu.Add(Item);
      end;
      Menu.AddSeparator;
      Menu.Add(TMenuItem.Create('Create new module',    nil, '', 'N'));
      Menu.Add(TMenuItem.Create('Scan folder for modules', nil, '', 'A'));
      Menu.Add(TMenuItem.Create('Add existing path',    nil, '', 'X'));

      if LastLabel <> '' then Menu.SelectByLabel(LastLabel);
      Sel   := Menu.Run;
      SelIdx := Menu.Selected;
      UChar  := Menu.UnhandledChar;

      if GSaveRequested then begin SaveProject; GSaveRequested := False; Continue; end;
      if GQuitRequested or GCtrlCRequested or GCtrlXRequested then Break;

      if (Sel = nil) and (UChar <> #0) then
      begin
        Modl := ModuleAtMenuIdx(SelIdx);
        if Assigned(Modl) then
        begin
          CandName := ModuleNameFromAbsDir(
            IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(FProject.FileName)))
            + Modl.Path);
          case UpCase(UChar) of
            'E': begin
              Modl.ActiveByDefault := True;
              SetModified;
              LastLabel := CandName;
            end;
            'D': begin
              Modl.ActiveByDefault := False;
              SetModified;
              LastLabel := CandName + ' (disabled)';
            end;
          end;
        end;
        Continue;
      end;

      if Sel = nil then Break;
      LastLabel := Sel.Label_;

      if Sel.Label_ = 'Create new module' then
      begin
        RunCreateModuleWizard(P);
        LastLabel := '';
      end
      else if Sel.Label_ = 'Scan folder for modules' then
      begin
        BaseDir := ExtractFilePath(FProject.FileName);
        ScanMenu := TMenu.Create(FBreadcrumb + ' > Scan — Found Modules');
        try
          ScanMenu.AddHeader('Select a module to add');
          ScanMenu.AddSeparator;
          Added := 0;
          if FindFirst(BaseDir + '*', faDirectory, SR) = 0 then
          try
            repeat
              if (SR.Name = '.') or (SR.Name = '..') then Continue;
              if (SR.Attr and faDirectory) = 0 then Continue;
              if not FileExists(BaseDir + SR.Name + PathDelim + 'project.xml') then Continue;
              CandPath := SR.Name;
              AlreadyIn := False;
              for I := 0 to P.Modules.Count - 1 do
                if SameText(P.Modules[I].Path, CandPath) then
                begin
                  AlreadyIn := True;
                  Break;
                end;
              if not AlreadyIn then
              begin
                CandName := ModuleNameFromAbsDir(BaseDir + CandPath);
                ScanMenu.Add(TMenuItem.Create(CandName, nil, CandPath));
                Inc(Added);
              end;
            until FindNext(SR) <> 0;
          finally
            FindClose(SR);
          end;
          if Added = 0 then
          begin
            Term.GotoXY(1, Term.Height - 1);
            Term.ClearToEOL;
            Term.SetFG(clBrightBlack);
            Term.WriteStr(' No new modules found.  Press any key.');
            Term.ResetColors;
            Term.FlushOutput;
            Term.ReadKey;
          end
          else
          begin
            ScanSel := ScanMenu.Run;
            if Assigned(ScanSel) then
            begin
              P.AddModule(ScanSel.Value, True);
              SetModified;
            end;
          end;
        finally
          ScanMenu.Free;
        end;
        LastLabel := '';
      end
      else if Sel.Label_ = 'Add existing path' then
      begin
        NewPath := '';
        if RunPathPicker(ExtractFilePath(ExpandFileName(FProject.FileName)),
             FBreadcrumb + ' > Add Module Path', True, NewPath) and (NewPath <> '') then
        begin
          AlreadyIn := False;
          for I := 0 to P.Modules.Count - 1 do
            if SameText(P.Modules[I].Path, NewPath) then
            begin
              AlreadyIn := True;
              Break;
            end;
          if AlreadyIn then
          begin
            Term.GotoXY(1, Term.Height - 1);
            Term.ClearToEOL;
            Term.SetFG(clRed);
            Term.WriteStr(' Module already in list: ' + NewPath + '  (press any key)');
            Term.ResetColors;
            Term.ReadKey;
          end
          else
          begin
            P.AddModule(NewPath, True);
            SetModified;
          end;
        end;
      end
      else if Menu.DeletePressed then
      begin
        Modl := ModuleAtMenuIdx(SelIdx);
        if Assigned(Modl) and
           Confirm('Remove module "' + Modl.Path + '" from project? (no files deleted)') then
        begin
          P.RemoveModule(Modl);
          SetModified;
          LastLabel := '';
        end;
      end
      else
      begin
        Modl := ModuleAtMenuIdx(SelIdx);
        if Assigned(Modl) then
        begin
          BaseDir     := ExtractFilePath(FProject.FileName);
          ModFilePath := BaseDir + Modl.Path;
          if not SameText(ExtractFileName(ModFilePath), 'project.xml') then
            ModFilePath := IncludeTrailingPathDelimiter(ModFilePath) + 'project.xml';
          if FileExists(ModFilePath) then
          begin
            try
              SubProject := TProjectBase.LoadFromFile(ModFilePath);
              try
                Sub := TUIController.Create(SubProject,
                  FBreadcrumb + ' > ' + Modl.Path, FResolver, False, Self,
                  TProjectPOM(FProject));
                try
                  Sub.Run;
                  if Sub.FModified then SetModified;
                finally
                  Sub.Free;
                end;
              finally
                SubProject.Free;
              end;
            except
              on E: Exception do
              begin
                Term.GotoXY(1, Term.Height - 1);
                Term.ClearToEOL;
                Term.SetFG(clRed);
                Term.WriteStr(' Cannot open ' + ModFilePath + ': ' + E.Message);
                Term.ResetColors;
                Term.ReadKey;
              end;
            end;
          end
          else
          begin
            Term.GotoXY(1, Term.Height - 1);
            Term.ClearToEOL;
            Term.SetFG(clRed);
            Term.WriteStr(' File not found: ' + ModFilePath + ' — press any key.');
            Term.ResetColors;
            Term.ReadKey;
          end;
          if not GQuitRequested and not GCtrlXRequested then
            GCtrlCRequested := False;
        end;
      end;
    finally
      Menu.Free;
    end;
  until GQuitRequested or GCtrlCRequested or GCtrlXRequested;
end;

procedure TUIController.ShowAboutPage;

  procedure WriteRow(Row: Integer; const S: string; AFG: TColor = clDefault);
  begin
    Term.GotoXY(1, Row);
    Term.ClearToEOL;
    if AFG <> clDefault then Term.SetFG(AFG);
    Term.WriteStr('  ' + S);
    Term.ResetColors;
  end;

  procedure WriteURL(Row: Integer; const S: string);
  begin
    Term.GotoXY(1, Row);
    Term.ClearToEOL;
    Term.SetFG(clBrightBlack);
    Term.WriteStr('    ');
    Term.SetFG(clCyan);
    Term.WriteStr(S);
    Term.ResetColors;
  end;

var
  W, Row, I:    Integer;
  LicLines:     TStringList;
  LicStartRow:  Integer;
  LicPaneRows:  Integer;
  LicScrollOff: Integer;
  K:            TKeyEvent;
  MaxScroll:    Integer;

  procedure DrawLicensePane;
  var J, R: Integer;
  begin
    for J := 0 to LicPaneRows - 1 do
    begin
      R := LicStartRow + J;
      I := LicScrollOff + J;
      Term.GotoXY(1, R);
      Term.ClearToEOL;
      if I < LicLines.Count then
      begin
        if Trim(LicLines[I]) <> '' then
        begin
          ColorRule;
          Term.WriteStr('  ' + LicLines[I]);
          Term.ResetColors;
        end;
      end;
    end;
    Term.GotoXY(1, Term.Height);
    Term.ClearToEOL;
    ColorHelp;
    Term.WriteStr(' ↑↓ Scroll license   Any other key to return ');
    if MaxScroll > 0 then
    begin
      Term.GotoXY(Term.Width - 8, Term.Height);
      Term.WriteStr(IntToStr(LicScrollOff + 1) + '/' + IntToStr(MaxScroll + 1));
    end;
    Term.ResetColors;
    Term.FlushOutput;
  end;

begin
  LicLines := TStringList.Create;
  try
    LicLines.Text := LICENSE_TEXT;

    repeat
      Term.ClearScreen;
      W := Term.Width;
      DrawHeader('About', 1);

      Row := 4;
      Term.SetFG(clBrightCyan);
      Term.GotoXY(1, Row); Term.ClearToEOL;
      Term.WriteStr('  ' + APP_TITLE + '  v' + APP_VERSION);
      Term.ResetColors;

      Inc(Row);
      WriteRow(Row, AUTHOR_COPYRIGHT, clBrightBlack);
      Inc(Row);
      WriteURL(Row, AUTHOR_URL);
      Inc(Row);
      WriteURL(Row, APP_URL);

      Inc(Row, 2);
      WriteRow(Row, 'A console editor for pasbuild project.xml files.', clDefault);

      Inc(Row, 2);
      WriteRow(Row, 'Special thanks', clBrightBlack);
      Inc(Row);
      Term.GotoXY(1, Row); Term.ClearToEOL;
      Term.WriteStr('  Thanks to ');
      Term.SetFG(clBrightCyan);
      Term.WriteStr(PASBUILD_AUTHOR);
      Term.ResetColors;
      Term.WriteStr(' for creating pasbuild.');
      Inc(Row);
      WriteURL(Row, PASBUILD_AUTHOR_URL);
      Inc(Row);
      WriteURL(Row, PASBUILD_URL);

      Inc(Row, 2);
      DrawRule(Row, 1, W);
      Inc(Row);
      Term.GotoXY(1, Row); Term.ClearToEOL;
      ColorHeader;
      Term.WriteStr('  License');
      Term.ResetColors;
      Inc(Row);

      LicStartRow  := Row;
      LicPaneRows  := Term.Height - 2 - LicStartRow + 1;
      if LicPaneRows < 1 then LicPaneRows := 1;
      MaxScroll    := LicLines.Count - LicPaneRows;
      if MaxScroll < 0 then MaxScroll := 0;
      LicScrollOff := 0;

      DrawRule(Term.Height - 1, 1, W);
      DrawLicensePane;

      repeat
        K := Term.ReadKey;
        if Term.HasResized then Break;
        case K.Code of
          kcUp: begin
            if LicScrollOff > 0 then begin Dec(LicScrollOff); DrawLicensePane; end;
          end;
          kcDown: begin
            if LicScrollOff < MaxScroll then begin Inc(LicScrollOff); DrawLicensePane; end;
          end;
          kcPageUp: begin
            LicScrollOff := LicScrollOff - LicPaneRows;
            if LicScrollOff < 0 then LicScrollOff := 0;
            DrawLicensePane;
          end;
          kcPageDown: begin
            LicScrollOff := LicScrollOff + LicPaneRows;
            if LicScrollOff > MaxScroll then LicScrollOff := MaxScroll;
            DrawLicensePane;
          end;
          else Exit;
        end;
      until False;
    until False;

  finally
    LicLines.Free;
  end;
end;

procedure TUIController.RunProjectMenu;
var
  Menu:      TMenu;
  Sel:       TMenuItem;
  It:        TMenuItem;
  NewVal:    string;
  ProfNames: TStringList;
  ProfVal:   string;
  ModNames:  TStringList;
  ModVal:    string;
  ModXML:    string;
  ModChild:  TProjectBase;
  I:         Integer;
begin
  repeat
    Menu := TMenu.Create(FBreadcrumb);
    try
      Menu.AddHeader('Identity  [' + FProject.ProjectTypeLabel + ']');
      It := TMenuItem.Create('Name', nil, FProject.Name, 'N');
      It.Desc := SDescName; Menu.Add(It);

      It := TMenuItem.Create('Version', nil, '', 'V');
      if FProject.Version <> '' then
        It.Value := FProject.Version
      else if Assigned(FParentPOM) and (FParentPOM.Version <> '') then
        begin It.Value := FParentPOM.Version + ' (inherited)'; It.DimValue := True; end
      else
        begin It.Value := '(inherited)'; It.DimValue := True; end;
      It.Desc := SDescVersion; Menu.Add(It);

      It := TMenuItem.Create('Author', nil, '', 'A');
      if FProject.Author <> '' then
        It.Value := FProject.Author
      else if Assigned(FParentPOM) and (FParentPOM.Author <> '') then
        begin It.Value := FParentPOM.Author + ' (inherited)'; It.DimValue := True; end;
      It.Desc := SDescAuthor; Menu.Add(It);

      It := TMenuItem.Create('License', nil, '', 'L');
      if FProject.License <> '' then
        It.Value := FProject.License
      else if Assigned(FParentPOM) and (FParentPOM.License <> '') then
        begin It.Value := FParentPOM.License + ' (inherited)'; It.DimValue := True; end;
      It.Desc := SDescLicense; Menu.Add(It);

      It := TMenuItem.Create('Description', nil, '', 'D');
      if FProject.Description <> '' then
        It.Value := FProject.Description
      else if Assigned(FParentPOM) and (FParentPOM.Description <> '') then
        begin It.Value := FParentPOM.Description + ' (inherited)'; It.DimValue := True; end;
      It.Desc := SDescDescription; Menu.Add(It);

      It := TMenuItem.Create('Project URL', nil, '', 'U');
      if FProject.ProjectUrl <> '' then
        It.Value := FProject.ProjectUrl
      else if Assigned(FParentPOM) and (FParentPOM.ProjectUrl <> '') then
        begin It.Value := FParentPOM.ProjectUrl + ' (inherited)'; It.DimValue := True; end;
      It.Desc := SDescProjectUrl; Menu.Add(It);

      It := TMenuItem.Create('Repo URL', nil, '', 'R');
      if FProject.RepoUrl <> '' then
        It.Value := FProject.RepoUrl
      else if Assigned(FParentPOM) and (FParentPOM.RepoUrl <> '') then
        begin It.Value := FParentPOM.RepoUrl + ' (inherited)'; It.DimValue := True; end;
      It.Desc := SDescRepoUrl; Menu.Add(It);
      Menu.AddSeparator;

      ProfNames := TStringList.Create;
      try
        for I := 0 to FProject.Profiles.Count - 1 do
          ProfNames.Add(FProject.Profiles[I].ID);
        if ProfNames.Count = 0 then
          ProfVal := '(none)'
        else
          ProfVal := JoinTruncated(ProfNames, ', ', 30);
      finally
        ProfNames.Free;
      end;
      It := TMenuItem.Create('Profiles', nil, ProfVal, 'P');
      It.DimValue := (FProject.Profiles.Count = 0);
      It.Desc := SDescProfiles; Menu.Add(It);

      if FProject is TProjectCommon then
      begin
        It := TMenuItem.Create('Build / Dependencies', nil, '', 'B');
        It.Desc := SDescBuildDeps;
        Menu.Add(It);
      end;
      if FProject is TProjectPOM then
      begin
        ModNames := TStringList.Create;
        try
          for I := 0 to TProjectPOM(FProject).Modules.Count - 1 do
          begin
            ModXML := IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(FProject.FileName)))
              + IncludeTrailingPathDelimiter(TProjectPOM(FProject).Modules[I].Path)
              + 'project.xml';
            if FileExists(ModXML) then
            begin
              ModChild := TProjectBase.LoadFromFile(ModXML);
              try
                ModNames.Add(ModChild.Name);
              finally
                ModChild.Free;
              end;
            end
            else
              ModNames.Add(TProjectPOM(FProject).Modules[I].Path);
          end;
          if ModNames.Count = 0 then
            ModVal := '(none)'
          else
            ModVal := JoinTruncated(ModNames, ', ', 30);
        finally
          ModNames.Free;
        end;
        It := TMenuItem.Create('Modules / Children', nil, ModVal, 'M');
        It.DimValue := (TProjectPOM(FProject).Modules.Count = 0);
        Menu.Add(It);
      end;

      if FLastMenuLabel <> '' then Menu.SelectByLabel(FLastMenuLabel);
      Sel := Menu.Run;

      if (Menu.Selected >= 0) and (Menu.Selected < Menu.Items.Count) then
        FLastMenuLabel := Menu.Items[Menu.Selected].Label_;

      if Menu.F1Pressed then begin ShowAboutPage; Continue; end;

      if GSaveRequested then begin SaveProject; GSaveRequested := False; Continue; end;

      if (Sel = nil) and (Menu.UnhandledChar <> #0) then Continue;
      if (Sel = nil) and (not GQuitRequested) and (not GCtrlCRequested) and (not GCtrlXRequested) then
      begin
        if Menu.ExitedLeft and FIsRoot then Continue;
        if FIsRoot then GQuitRequested := True;
        Break;
      end;

      if GCtrlCRequested or GQuitRequested or GCtrlXRequested then
        Break;

      case Sel.Label_ of
        'Name':
          if EditLine('Name', FProject.Name, NewVal, Menu.SelectedRow) then
            begin FProject.Name := NewVal; SetModified; end;
        'Version':
          if EditLine('Version', FProject.Version, NewVal, Menu.SelectedRow) then
            begin FProject.Version := NewVal; SetModified; end;
        'Author':
          if EditLine('Author', FProject.Author, NewVal, Menu.SelectedRow) then
            begin FProject.Author := NewVal; SetModified; end;
        'License':
          if EditLine('License', FProject.License, NewVal, Menu.SelectedRow) then
            begin FProject.License := NewVal; SetModified; end;
        'Description':
          if EditLine('Description', FProject.Description, NewVal, Menu.SelectedRow) then
            begin FProject.Description := NewVal; SetModified; end;
        'Project URL':
          if EditLine('Project URL', FProject.ProjectUrl, NewVal, Menu.SelectedRow) then
            begin FProject.ProjectUrl := NewVal; SetModified; end;
        'Repo URL':
          if EditLine('Repo URL', FProject.RepoUrl, NewVal, Menu.SelectedRow) then
            begin FProject.RepoUrl := NewVal; SetModified; end;
        'Profiles':             RunProfilesMenu(FProject);
        'Build / Dependencies': RunCommonMenu(TProjectCommon(FProject));
        'Modules / Children':   RunPOMMenu(TProjectPOM(FProject));
      end;
    finally
      Menu.Free;
    end;
  until GQuitRequested or GCtrlCRequested or GCtrlXRequested;
end;

procedure TUIController.Run;
begin
  GQuitRequested  := False;
  GCtrlCRequested := False;
  GCtrlXRequested := False;
  RunProjectMenu;
  if GCtrlXRequested then
  begin
    GCtrlXRequested := False;
    GQuitRequested  := True;
    if FModified then SaveProject;
  end
  else if GQuitRequested or GCtrlCRequested then
  begin
    GQuitRequested  := True;
    GCtrlCRequested := False;
    if not PromptSaveOnQuit then
    begin
      GQuitRequested  := False;
      GCtrlCRequested := False;
      Run;
    end;
  end;
end;

{ ══════════════════════════════════════════════════════════════════════
  Public entry point
  ══════════════════════════════════════════════════════════════════════ }

procedure RunUI(AProject: TProjectBase; AParentPOM: TProjectPOM);
var
  Ctrl: TUIController;
begin
  AppTitle   := APP_TITLE;
  AppVersion := APP_VERSION;
  Term.EnableRawMode;
  Term.HideCursor;
  Term.EnterAltScreen;
  try
    Ctrl := TUIController.Create(AProject, AProject.Name, DefaultResolver, True, nil, AParentPOM);
    try
      Ctrl.Run;
    finally
      Ctrl.Free;
    end;
  finally
    Term.ExitAltScreen;
    Term.ShowCursor;
    Term.DisableRawMode;
  end;
end;

end.
