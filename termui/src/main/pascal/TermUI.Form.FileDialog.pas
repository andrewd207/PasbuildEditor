{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Form.FileDialog;

{$mode objfpc}{$H+}

{ Full-filesystem file dialog — open, save, or directory selection.

  Unlike TPathPicker (which recurses from a fixed base), this dialog shows
  one directory at a time and lets the user navigate anywhere on the
  filesystem.

  Layout:
    Row 1        : title / header
    Row 2        : current path  +  FileFilter hint
    Row 3        : separator
    Rows 4..H-4  : file/directory list  (name left, size right)
    Row H-3      : separator
    Row H-2      : Filename: field
    Row H-1      : separator
    Row H        : key hint bar

  Focus states:
    fsList     — arrows navigate; typing filters; Backspace navigates up
                 when filter is empty
    fsFilename — inline editor on the filename row; Tab returns to list

  Symlinks are shown in a distinct color on platforms that set faSymLink.

  FileFilter is a semicolon-separated list of glob patterns applied to
  file names (e.g. "*.pas;*.pp").  Directories are always shown. }

interface

uses
  Classes, SysUtils, fpMasks,
  TermUI.StringUtils, TermUI.Terminal,
  TermUI.Control, TermUI.Control.ComboBox, TermUI.Forms, TermUI.Application, TermUI.Menu;

type
  TFileDialogMode = (fdOpen, fdSave, fdSelectDir);

  TFileEntry = record
    Name:      string;
    IsDir:     Boolean;
    IsSymlink: Boolean;
    Size:      Int64;
  end;

  TFileDialog = class(TForm)
  private
    type TFocus = (fsList, fsFilename, fsFilterCombo);
  private
    FMode:        TFileDialogMode;
    FCurrentDir:  string;
    FRaw:         array of TFileEntry;   { all entries loaded from disk }
    FRawCount:    Integer;
    FDisplay:     array of TFileEntry;   { filtered subset shown in list }
    FDisplayCount: Integer;
    FFileFilter:  string;                { glob pattern e.g. *.pas;*.pp }
    FSel:         Integer;
    FTopRow:      Integer;
    FFilename:    string;
    FFilenameCur: Integer;
    FFocus:       TFocus;
    FShowHidden:   Boolean;
    FAccepted:     Boolean;
    FResultPath:   string;
    FFilterCombo:  TComboBox;            { nil when no filters have been added }
    FWantExtensions: string;
    FSearchActive:   Boolean;
    FSearchText:     string;
    FSearchCursor:   Integer;   { 0-based insert position within FSearchText }
    FSearchPrevSel:  Integer;
    FSearchMatched:  Boolean;

    procedure SetFileFilter(const AValue: string);
    procedure OnFilterChanged(Sender: TObject);
    function  HeaderRows: Integer;
    function  FooterRows: Integer;
    function  ListRows: Integer;
    procedure LoadDir;
    procedure RebuildDisplay;
    function  MatchesFileFilter(const AName: string): Boolean;
    procedure NavigateInto(const ADirName: string);
    procedure NavigateUp;
    procedure SelectCurrent;
    procedure HandleAccept;
    procedure EnsureSelVisible;

    procedure DrawPath;
    procedure DrawList;
    procedure DrawFilenameField;
    procedure DrawHintBar;
    procedure PlaceCursor;

    procedure FilenameInsert(ACh: TUTF8Char);
    procedure FilenameBackspace;
    procedure FilenameDelete;
    procedure FilenameMoveLeft;
    procedure FilenameMoveRight;
    procedure FilenameHome;
    procedure FilenameEnd;
    function  FieldLabelWidth: Integer;
    procedure FilenameCalcScroll(out AScroll: Integer);

    procedure ActivateSearch(ACh: TUTF8Char);
    procedure DeactivateSearch(AAccept: Boolean);
    procedure SearchMatch;
    function  DefaultExtension: string;
    function  HasWantedExtension(const AName: string): Boolean;
    function  ApplyWantExtension(const AName: string): string;

  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
    procedure ArrangeChildren; override;
  public
    constructor Create(const ATitle: string = ''); override;
    destructor  Destroy; override;

    procedure SetParams(const AInitialDir: string; AMode: TFileDialogMode;
      const AInitialFilename: string = '');
    function  RunModal: Boolean;

    { Add a named file-type filter shown in the filter combo on the path row.
      The first filter added becomes active immediately.
      Tab in the file list moves focus to the combo; Tab/Esc closes it.
      Example: AddFilter('Pascal files', '*.pas;*.pp') }
    procedure AddFilter(const AName, APattern: string);

    { Semicolon-separated glob patterns for files.  '*' = all (default).
      Directories are always shown regardless of this filter.
      Can be set before or after SetParams; the display updates immediately. }
    property FileFilter:      string  read FFileFilter      write SetFileFilter;
    { Semicolon-separated list of extensions (leading dot required, e.g. ".pas;.pp;.lpr").
      On a Save dialog, if the typed or searched name has none of these extensions
      (case-insensitive), the first extension in the list is appended automatically. }
    property WantExtensions:  string  read FWantExtensions  write FWantExtensions;
    property Accepted:        Boolean read FAccepted;
    property ResultPath:      string  read FResultPath;
  end;

{ One-shot helpers }
function RunOpenDialog(const AInitialDir: string; var APath: string;
  const ATitle: string = 'Open'): Boolean;
function RunSaveDialog(const AInitialDir: string; var APath: string;
  const ATitle: string = 'Save'): Boolean;
function RunDirDialog(const AInitialDir: string; var APath: string;
  const ATitle: string = 'Select Folder'): Boolean;

implementation

uses Math;

const
  HEADER_ROWS = 3;
  FOOTER_ROWS = 3;
  SIZE_COL_W  = 6;   { right-aligned size field width incl. leading space }

{ ── Size formatting ── }

function FormatSize(ASize: Int64): string;
const
  KB = Int64(1024);
  MB = Int64(1024) * KB;
  GB = Int64(1024) * MB;
begin
  if ASize < KB then
    Result := IntToStr(ASize) + 'B'
  else if ASize < MB then
  begin
    if ASize mod KB < 100 then
      Result := IntToStr(ASize div KB) + 'K'
    else
      Result := Format('%.1fK', [ASize / KB]);
  end
  else if ASize < GB then
  begin
    if ASize mod MB < 100 * KB then
      Result := IntToStr(ASize div MB) + 'M'
    else
      Result := Format('%.1fM', [ASize / MB]);
  end
  else
  begin
    if ASize mod GB < 100 * MB then
      Result := IntToStr(ASize div GB) + 'G'
    else
      Result := Format('%.1fG', [ASize / GB]);
  end;
end;

{ ── Layout helpers ── }

function TFileDialog.HeaderRows: Integer; begin Result := HEADER_ROWS; end;
function TFileDialog.FooterRows: Integer; begin Result := FOOTER_ROWS; end;

function TFileDialog.ListRows: Integer;
begin
  Result := Term.Height - HEADER_ROWS - FOOTER_ROWS;
  if Result < 1 then Result := 1;
end;

{ ── Directory loading ── }

procedure TFileDialog.LoadDir;
var
  SR:   TSearchRec;
  N, I: Integer;
  E:    TFileEntry;
begin
  FRawCount := 0;
  SetLength(FRaw, 64);
  if FindFirst(IncludeTrailingPathDelimiter(FCurrentDir) + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then Continue;
      if (not FShowHidden) and (SR.Name <> '') and (SR.Name[1] = '.') then Continue;
      if FRawCount >= Length(FRaw) then
        SetLength(FRaw, Length(FRaw) * 2);
      with FRaw[FRawCount] do
      begin
        Name      := SR.Name;
        IsDir     := (SR.Attr and faDirectory) <> 0;
        IsSymlink := (SR.Attr and faSymLink)   <> 0;
        if IsDir then Size := 0 else Size := SR.Size;
      end;
      Inc(FRawCount);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  { Sort: dirs first, then files; alphabetical within each group }
  { Simple insertion sort — directory listings are small }
  for N := 1 to FRawCount - 1 do
  begin
    E := FRaw[N];
    I := N - 1;
    while (I >= 0) and
          ((FRaw[I].IsDir < E.IsDir) or
           ((FRaw[I].IsDir = E.IsDir) and
            (CompareText(FRaw[I].Name, E.Name) > 0))) do
    begin
      FRaw[I + 1] := FRaw[I];
      Dec(I);
    end;
    FRaw[I + 1] := E;
  end;
  RebuildDisplay;
end;

procedure TFileDialog.SetFileFilter(const AValue: string);
begin
  if FFileFilter = AValue then Exit;
  FFileFilter := AValue;
  if FRawCount > 0 then
  begin
    RebuildDisplay;
    Invalidate;
  end;
end;

function ExtractPattern(const AComboItem: string): string;
{ Items are "Name | Pattern" — return everything after the last " | " }
var P: Integer;
begin
  P := Pos(' | ', AComboItem);
  if P > 0 then Result := Copy(AComboItem, P + 3, MaxInt)
  else          Result := AComboItem;
end;

procedure TFileDialog.OnFilterChanged(Sender: TObject);
begin
  if not Assigned(FFilterCombo) then Exit;
  if (FFilterCombo.SelectedIndex >= 0) and
     (FFilterCombo.SelectedIndex < FFilterCombo.Items.Count) then
  begin
    FFileFilter := ExtractPattern(
      FFilterCombo.Items[FFilterCombo.SelectedIndex]);
    FSel := 0; FTopRow := 0;
    RebuildDisplay;
  end;
  { After dropdown closes, return focus to the file list }
  FFocus := fsList;
  Invalidate;
end;

procedure TFileDialog.AddFilter(const AName, APattern: string);
begin
  if not Assigned(FFilterCombo) then
  begin
    FFilterCombo                       := TComboBox.Create;
    FFilterCombo.Style                 := csFixed;
    FFilterCombo.RequireValidSelection := True;
    FFilterCombo.OpenOnFocus           := True;
    FFilterCombo.TextAlign             := taRight;
    FFilterCombo.ForeColor             := clYellow;
    FFilterCombo.OnChange              := @OnFilterChanged;
    ArrangeChildren;
  end;
  FFilterCombo.Items.Add(AName + ' | ' + APattern);
  if FFilterCombo.Items.Count = 1 then
  begin
    FFilterCombo.SelectedIndex := 0;
    FFileFilter := APattern;
    if FRawCount > 0 then
    begin
      RebuildDisplay;
      Invalidate;
    end;
  end;
end;

function TFileDialog.MatchesFileFilter(const AName: string): Boolean;
var
  Patterns: TStringList;
  I:        Integer;
begin
  if (FFileFilter = '') or (FFileFilter = '*') then Exit(True);
  Patterns := TStringList.Create;
  try
    Patterns.Delimiter     := ';';
    Patterns.DelimitedText := FFileFilter;
    for I := 0 to Patterns.Count - 1 do
      if MatchesMask(AName, Trim(Patterns[I])) then Exit(True);
  finally
    Patterns.Free;
  end;
  Result := False;
end;

procedure TFileDialog.RebuildDisplay;
var I: Integer;
begin
  FDisplayCount := 0;
  SetLength(FDisplay, FRawCount + 1);  { +1 for '..' }
  { Always offer parent dir unless at root }
  if FCurrentDir <> PathDelim then
  begin
    FDisplay[0].Name      := '..';
    FDisplay[0].IsDir     := True;
    FDisplay[0].IsSymlink := False;
    FDisplay[0].Size      := 0;
    FDisplayCount         := 1;
  end;
  for I := 0 to FRawCount - 1 do
  begin
    if (FMode = fdSelectDir) and not FRaw[I].IsDir then Continue;
    if FRaw[I].IsDir then
    begin
      FDisplay[FDisplayCount] := FRaw[I];
      Inc(FDisplayCount);
    end
    else
    begin
      if MatchesFileFilter(FRaw[I].Name) then
      begin
        FDisplay[FDisplayCount] := FRaw[I];
        Inc(FDisplayCount);
      end;
    end;
  end;
  if FSel >= FDisplayCount then
    FSel := Max(0, FDisplayCount - 1);
  EnsureSelVisible;
end;

procedure TFileDialog.NavigateInto(const ADirName: string);
begin
  FCurrentDir   := IncludeTrailingPathDelimiter(FCurrentDir) + ADirName;
  FSearchActive := False;
  FSearchText   := '';
  FSel          := 0;
  FTopRow       := 0;
  LoadDir;
  Invalidate;
end;

procedure TFileDialog.NavigateUp;
var Parent: string;
begin
  Parent := ExcludeTrailingPathDelimiter(
              ExtractFileDir(ExcludeTrailingPathDelimiter(FCurrentDir)));
  if Parent = '' then Parent := PathDelim;
  FCurrentDir   := Parent;
  FSearchActive := False;
  FSearchText   := '';
  FSel          := 0;
  FTopRow       := 0;
  LoadDir;
  Invalidate;
end;

procedure TFileDialog.SelectCurrent;
var E: TFileEntry;
begin
  if (FSel < 0) or (FSel >= FDisplayCount) then Exit;
  E := FDisplay[FSel];
  if E.Name = '..' then
  begin
    NavigateUp;
    Exit;
  end;
  if E.IsDir then
  begin
    if FMode = fdSelectDir then
    begin
      FFilename    := E.Name;
      FFilenameCur := Length(FFilename) + 1;
      FFocus       := fsFilename;
      Invalidate;
    end
    else
      NavigateInto(E.Name);
  end
  else
  begin
    FFilename    := E.Name;
    FFilenameCur := Length(FFilename) + 1;
    FFocus       := fsFilename;
    Invalidate;
  end;
end;

procedure TFileDialog.HandleAccept;
var FullPath: string;
begin
  if FFilename = '' then Exit;
  FullPath := IncludeTrailingPathDelimiter(FCurrentDir) + FFilename;
  case FMode of
    fdOpen:      if not FileExists(FullPath)     then Exit;
    fdSave:      ;
    fdSelectDir: if not DirectoryExists(FullPath) then Exit;
  end;
  FResultPath := FullPath;
  FAccepted   := True;
  Close(1);
end;

procedure TFileDialog.EnsureSelVisible;
begin
  if FSel < 0 then Exit;
  if FSel < FTopRow then FTopRow := FSel;
  if FSel >= FTopRow + ListRows then FTopRow := FSel - ListRows + 1;
  if FTopRow < 0 then FTopRow := 0;
end;

{ ── Filename field ── }

function TFileDialog.FieldLabelWidth: Integer;
begin
  if FMode = fdSelectDir then Result := 12   { ' Directory: ' }
  else                        Result := 11;  { ' Filename: ' }
end;

procedure TFileDialog.FilenameCalcScroll(out AScroll: Integer);
var FieldW: Integer;
begin
  FieldW  := Term.Width - FieldLabelWidth;
  AScroll := 0;
  if FFilenameCur - AScroll > FieldW then AScroll := FFilenameCur - FieldW;
  if FFilenameCur - 1 < AScroll      then AScroll := FFilenameCur - 1;
  if AScroll < 0 then AScroll := 0;
end;

procedure TFileDialog.FilenameInsert(ACh: TUTF8Char);
begin Insert(string(ACh), FFilename, FFilenameCur); Inc(FFilenameCur, System.Length(string(ACh))); Invalidate; end;
procedure TFileDialog.FilenameBackspace;
begin
  if FFilenameCur > 1 then
  begin DeleteNeutral(FFilename, FFilenameCur-2, 1); Dec(FFilenameCur); Invalidate; end;
end;
procedure TFileDialog.FilenameDelete;
begin
  if FFilenameCur <= Length(FFilename) then
  begin DeleteNeutral(FFilename, FFilenameCur-1, 1); Invalidate; end;
end;
procedure TFileDialog.FilenameMoveLeft;
begin if FFilenameCur > 1 then begin Dec(FFilenameCur); Invalidate; end; end;
procedure TFileDialog.FilenameMoveRight;
begin if FFilenameCur <= Length(FFilename) then begin Inc(FFilenameCur); Invalidate; end; end;
procedure TFileDialog.FilenameHome;
begin FFilenameCur := 1; Invalidate; end;
procedure TFileDialog.FilenameEnd;
begin FFilenameCur := Length(FFilename) + 1; Invalidate; end;

{ ── Inline search ── }

function TFileDialog.DefaultExtension: string;
var P: Integer;
begin
  P := Pos(';', FWantExtensions);
  if P > 0 then Result := Copy(FWantExtensions, 1, P - 1)
  else           Result := FWantExtensions;
end;

function TFileDialog.HasWantedExtension(const AName: string): Boolean;
var
  Exts: TStringList;
  I:    Integer;
  Lo, Ext: string;
begin
  Result := False;
  if FWantExtensions = '' then Exit;
  Lo   := LowerCase(AName);
  Exts := TStringList.Create;
  try
    Exts.Delimiter     := ';';
    Exts.DelimitedText := FWantExtensions;
    for I := 0 to Exts.Count - 1 do
    begin
      Ext := LowerCase(Trim(Exts[I]));
      if (Ext <> '') and
         (Copy(Lo, Length(Lo) - Length(Ext) + 1, MaxInt) = Ext) then
        Exit(True);
    end;
  finally
    Exts.Free;
  end;
end;

function TFileDialog.ApplyWantExtension(const AName: string): string;
begin
  if (FWantExtensions <> '') and (FMode = fdSave) and
     not HasWantedExtension(AName) then
    Result := AName + DefaultExtension
  else
    Result := AName;
end;

procedure TFileDialog.SearchMatch;
{ Move selection to the first entry whose name starts with FSearchText
  (case-insensitive).  Falls back to a substring match if no prefix found.
  Sets FSearchMatched to True if any match was found. }
var I:  Integer;
    Lo: string;
begin
  FSearchMatched := False;
  Lo := LowerCase(FSearchText);
  if Lo = '' then Exit;
  { Prefix match first }
  for I := 0 to FDisplayCount - 1 do
  begin
    if FDisplay[I].Name = '..' then Continue;
    if Pos(Lo, LowerCase(FDisplay[I].Name)) = 1 then
    begin
      FSel           := I;
      FSearchMatched := True;
      EnsureSelVisible;
      Exit;
    end;
  end;
  { Substring fallback }
  for I := 0 to FDisplayCount - 1 do
  begin
    if FDisplay[I].Name = '..' then Continue;
    if PosNeutral(Lo, LowerCase(FDisplay[I].Name)) then
    begin
      FSel           := I;
      FSearchMatched := True;
      EnsureSelVisible;
      Exit;
    end;
  end;
  { No match — deselect }
  FSel := -1;
end;

procedure TFileDialog.ActivateSearch(ACh: TUTF8Char);
begin
  FSearchPrevSel := FSel;
  FSearchText    := ACh;
  FSearchCursor  := 1;   { after the first character }
  FSearchActive  := True;
  FTopRow        := 0;   { scroll to top so the edit row is always visible }
  SearchMatch;
  Invalidate;
end;

procedure TFileDialog.DeactivateSearch(AAccept: Boolean);
begin
  FSearchActive := False;
  FSearchText   := '';
  if not AAccept then
    FSel := FSearchPrevSel;
  EnsureSelVisible;
  Invalidate;
end;

{ ── Drawing ── }

procedure TFileDialog.ArrangeChildren;
const
  COMBO_W = 32;  { reserved width for the filter combo on the path row }
var
  ComboLeft: Integer;
begin
  if not Assigned(FFilterCombo) then Exit;
  ComboLeft := Width - COMBO_W + 1;
  if ComboLeft < 2 then ComboLeft := 2;
  FFilterCombo.SetBounds(ComboLeft, 2, Width - ComboLeft + 1, 1);
end;

procedure TFileDialog.DrawPath;
const
  COMBO_W = 32;
var
  PathStr, Shown: string;
  PathAvail: Integer;
begin
  Term.GotoXY(1, 2);
  Term.ClearToEOL;
  PathStr   := FCurrentDir;
  PathAvail := Width - COMBO_W - 1;  { chars available for path text }
  if PathAvail < 4 then PathAvail := 4;

  if Length(PathStr) > PathAvail then
    Shown := '~' + Copy(PathStr, Length(PathStr) - PathAvail + 2, MaxInt)
  else
    Shown := PathStr;

  Term.WriteStr(' ');
  Term.SetFG(clBrightCyan);
  Term.WriteStr(Shown);
  Term.ResetColors;
  DrawRule(3, 1, Width);
end;

procedure TFileDialog.DrawList;
var
  RI, Idx, NameW: Integer;
  E:              TFileEntry;
  Name, SizeStr, Line, EditStr: string;
  Row:            Integer;
  IsSelected:     Boolean;
begin
  NameW := Term.Width - SIZE_COL_W;

  for RI := 0 to ListRows - 1 do
  begin
    Row := HEADER_ROWS + 1 + RI;
    Idx := FTopRow + RI;
    Term.GotoXY(1, Row);
    Term.ClearToEOL;
    if Idx >= FDisplayCount then Continue;

    E          := FDisplay[Idx];
    IsSelected := (FFocus = fsList) and (Idx = FSel);

    { Search edit overlays the '..' row while search is active }
    if (E.Name = '..') and FSearchActive then
    begin
      Term.SetFG(clBlack);
      Term.SetBG(clCyan);
      { Insert cursor marker '_' at FSearchCursor position }
      EditStr := FSearchText;
      if FSearchCursor < Length(EditStr) then
        EditStr[FSearchCursor + 1] := '_'
      else
        EditStr := EditStr + '_';
      Name := '/ ' + EditStr;
      Name := Name + StringOfChar(' ', Term.Width - Length(Name));
      Term.WriteStr(Copy(Name, 1, Term.Width));
      Term.ResetColors;
      Continue;
    end;

    { Name prefix + truncation }
    if E.Name = '..' then
      Name := ' ' + Application.DrawingChar[dcDirParent] + ' ..'
    else if E.IsDir then
      Name := ' ' + Application.DrawingChar[dcDirIndicator] + ' ' + E.Name
    else
      Name := '  ' + E.Name;
    if Length(Name) > NameW then
      Name := Copy(Name, 1, NameW - 1) + '~';

    { Size string — blank for dirs and '..' }
    if E.IsDir then
      SizeStr := ''
    else
      SizeStr := FormatSize(E.Size);

    { Apply colors }
    if IsSelected then
    begin
      Term.SetFG(clBlack);
      Term.SetBG(clCyan);
    end
    else if E.IsSymlink then
      Term.SetFG(clBrightYellow)
    else if E.IsDir then
      Term.SetFG(clBrightCyan)
    else
      Term.ResetColors;

    { Write name, pad to NameW, then right-align size }
    Term.WriteStr(Name);
    Line := StringOfChar(' ', NameW - Length(Name));
    Term.WriteStr(Line);
    if SizeStr <> '' then
    begin
      if IsSelected then
        Term.SetFG(clBlack)
      else
        Term.ResetColors;
      Term.WriteStr(StringOfChar(' ', SIZE_COL_W - Length(SizeStr)));
      Term.WriteStr(SizeStr);
    end
    else
      Term.WriteStr(StringOfChar(' ', SIZE_COL_W));

    Term.ResetColors;
  end;

  if FDisplayCount = 0 then
  begin
    Term.GotoXY(3, HEADER_ROWS + 1);
    Term.SetFG(clBrightBlack);
    Term.WriteStr('(empty directory)');
    Term.ResetColors;
  end;
end;

procedure TFileDialog.DrawFilenameField;
var
  H, FieldW, Scroll: Integer;
  VisStr: string;
begin
  H      := Term.Height;
  FieldW := Term.Width - FieldLabelWidth;
  DrawRule(H - 2, 1, Term.Width);
  Term.GotoXY(1, H - 1);
  Term.ClearToEOL;
  if FFocus = fsFilename then Term.SetFG(clBrightWhite)
  else                        Term.SetFG(clBrightBlack);
  if FMode = fdSelectDir then Term.WriteStr(' Directory: ')
  else                        Term.WriteStr(' Filename: ');
  Term.ResetColors;
  FilenameCalcScroll(Scroll);
  VisStr := CopyNeutral(FFilename, Scroll, FieldW);
  Term.WriteStr(VisStr);
  Term.ClearToEOL;
end;

procedure TFileDialog.DrawHintBar;
var H: Integer;
begin
  H := Term.Height;
  DrawRule(H, 1, Term.Width);
  Term.GotoXY(1, H);
  Term.SetFG(clBrightBlack);
  case FFocus of
    fsList:
      if FSearchActive then
        Term.WriteStr(' Type to search  Enter Confirm  Esc Cancel search  Backspace Delete')
      else
        Term.WriteStr(' ↑↓ Browse  ← Up  → Open  Enter Select  Tab Filename  H Hidden  Esc Cancel');
    fsFilename:
      Term.WriteStr(' Enter Accept  Tab List  ↑↓ Browse  Esc Cancel');
  end;
  Term.ClearToEOL;
  Term.ResetColors;
end;

procedure TFileDialog.PlaceCursor;
var Scroll, H: Integer;
begin
  case FFocus of
    fsList:
      if FSearchActive then
        Term.GotoXY(3 + FSearchCursor, HEADER_ROWS + 1)
      else if FSel >= 0 then
        Term.GotoXY(1, HEADER_ROWS + 1 + (FSel - FTopRow));
    fsFilename:
      begin
        FilenameCalcScroll(Scroll);
        H := Term.Height;
        Term.GotoXY(FieldLabelWidth + (FFilenameCur - Scroll), H - 1);
      end;
  end;
end;

{ ── DoPaint / DoKeyDown ── }

procedure TFileDialog.DoPaint;
begin
  Term.ClearScreen;
  DrawHeader(Title, 1);
  DrawPath;
  if Assigned(FFilterCombo) then
  begin
    FFilterCombo.Invalidate;
    FFilterCombo.Paint;
  end;
  DrawList;
  DrawFilenameField;
  DrawHintBar;
  Term.ShowCursor;
  PlaceCursor;
  inherited DoPaint;
end;

function TFileDialog.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  Result := True;

  if FFocus = fsFilename then
  begin
    case Key.Code of
      kcEscape:    Close(1);
      kcEnter:     HandleAccept;
      kcTab:
        { Forward: fsFilename → fsFilterCombo → (land on fsList) }
        begin
          if Assigned(FFilterCombo) then
          begin
            FFocus := fsFilterCombo;
            FFilterCombo.GainFocus;
            FFocus := fsList;  { always land on fsList going forward past combo }
            Invalidate;
          end
          else
            begin FFocus := fsList; Invalidate; end;
        end;
      kcShiftTab:  { Backward: fsFilename → fsList }
        begin FFocus := fsList; Invalidate; end;
      kcUp:        begin FFocus := fsList; Invalidate; end;
      kcDown:      begin FFocus := fsList; Invalidate; end;
      kcLeft:      FilenameMoveLeft;
      kcRight:     FilenameMoveRight;
      kcHome:      FilenameHome;
      kcEnd:       FilenameEnd;
      kcBackspace: FilenameBackspace;
      kcDelete:    FilenameDelete;
      kcChar:      if Key.Ch >= ' ' then FilenameInsert(Key.Ch);
    else
      Result := False;
    end;
    Exit;
  end;

  if FFocus = fsFilterCombo then
  begin
    { Route to combo; on Esc/Tab the combo's OnChange fires and resets FFocus }
    if Assigned(FFilterCombo) then
      Result := FFilterCombo.KeyDown(Key)
    else
      Result := False;
    if Result then Invalidate;
    Exit;
  end;

  { fsList — search active: only search keys have effect }
  if FSearchActive then
  begin
    case Key.Code of
      kcEnter:
        begin
          if FSearchMatched then
          begin
            DeactivateSearch(True);
            { Cursor landed on a file → populate filename field }
            if (FSel >= 0) and (FSel < FDisplayCount) and
               not FDisplay[FSel].IsDir then
            begin
              FFilename    := ApplyWantExtension(FDisplay[FSel].Name);
              FFilenameCur := Length(FFilename) + 1;
              FFocus       := fsFilename;
            end;
          end
          else if FMode = fdSave then
          begin
            { No match in a Save dialog → use typed text as filename }
            FFilename    := ApplyWantExtension(FSearchText);
            FFilenameCur := Length(FFilename) + 1;
            FSearchActive := False;
            FSearchText   := '';
            FSel          := FSearchPrevSel;
            EnsureSelVisible;
            FFocus := fsFilename;
          end
          else
            DeactivateSearch(False);  { no match in Open — just cancel search }
          Invalidate;
        end;
      kcEscape:
        DeactivateSearch(False);
      kcLeft:
        begin
          if FSearchCursor > 0 then Dec(FSearchCursor);
          Invalidate;
        end;
      kcRight:
        begin
          if FSearchCursor < Length(FSearchText) then Inc(FSearchCursor);
          Invalidate;
        end;
      kcHome:
        begin FSearchCursor := 0; Invalidate; end;
      kcEnd:
        begin FSearchCursor := Length(FSearchText); Invalidate; end;
      kcBackspace:
        begin
          if FSearchCursor > 0 then
          begin
            DeleteNeutral(FSearchText, FSearchCursor - 1, 1);
            Dec(FSearchCursor);
            if FSearchText = '' then
              DeactivateSearch(False)
            else
            begin
              SearchMatch;
              Invalidate;
            end;
          end;
        end;
      kcDelete:
        begin
          if FSearchCursor < Length(FSearchText) then
          begin
            DeleteNeutral(FSearchText, FSearchCursor, 1);
            if FSearchText = '' then
              DeactivateSearch(False)
            else
            begin
              SearchMatch;
              Invalidate;
            end;
          end;
        end;
      kcChar:
        if Key.Ch >= ' ' then
        begin
          InsertNeutral(FSearchText, Key.Ch, FSearchCursor);
          Inc(FSearchCursor, System.Length(string(Key.Ch)));
          SearchMatch;
          Invalidate;
        end;
    else
      { All other keys consumed silently while search is open }
    end;
    Exit;
  end;

  { fsList — normal navigation }
  case Key.Code of
    kcEscape: Close(1);

    kcUp:
      begin
        if FSel > 0 then Dec(FSel)
        else if FSel < 0 then FSel := 0;
        EnsureSelVisible; Invalidate;
      end;
    kcDown:
      begin
        if FSel < FDisplayCount - 1 then Inc(FSel);
        EnsureSelVisible; Invalidate;
      end;
    kcPageUp:
      begin
        Dec(FSel, ListRows - 1);
        if FSel < 0 then FSel := 0;
        EnsureSelVisible; Invalidate;
      end;
    kcPageDown:
      begin
        Inc(FSel, ListRows - 1);
        if FSel >= FDisplayCount then FSel := Max(0, FDisplayCount - 1);
        EnsureSelVisible; Invalidate;
      end;
    kcHome: begin FSel := 0;                              EnsureSelVisible; Invalidate; end;
    kcEnd:  begin FSel := Max(0, FDisplayCount - 1);      EnsureSelVisible; Invalidate; end;
    kcEnter: SelectCurrent;
    kcTab:
      { Forward: fsList → fsFilename }
      begin FFocus := fsFilename; Invalidate; end;
    kcShiftTab:
      { Backward: fsList → fsFilterCombo → (land on fsFilename) }
      begin
        if Assigned(FFilterCombo) then
        begin
          FFocus := fsFilterCombo;
          FFilterCombo.GainFocus;
          FFocus := fsFilename;  { always land on fsFilename going backward past combo }
          Invalidate;
        end
        else
          begin FFocus := fsFilename; Invalidate; end;
      end;

    kcLeft:
      NavigateUp;

    kcRight:
      begin
        if (FSel >= 0) and (FSel < FDisplayCount) then
        begin
          if FDisplay[FSel].Name = '..' then
            NavigateUp
          else if FDisplay[FSel].IsDir then
            NavigateInto(FDisplay[FSel].Name)
          else
          begin
            FFilename    := ApplyWantExtension(FDisplay[FSel].Name);
            FFilenameCur := Length(FFilename) + 1;
            FFocus       := fsFilename;
            Invalidate;
          end;
        end;
      end;

    kcChar:
      begin
        if (Key.Ch = 'h') or (Key.Ch = 'H') then
        begin
          FShowHidden := not FShowHidden;
          FSel := 0; FTopRow := 0;
          LoadDir; Invalidate;
        end
        else if Key.Ch >= ' ' then
          ActivateSearch(Key.Ch);
      end;

  else
    Result := False;
  end;
end;

{ ── Constructor / SetParams / RunModal ── }

constructor TFileDialog.Create(const ATitle: string);
begin
  inherited Create(ATitle);
  FFileFilter  := '*';
  FFilenameCur := 1;
  FFocus       := fsList;
end;

destructor TFileDialog.Destroy;
begin
  FFilterCombo.Free;
  inherited;
end;

procedure TFileDialog.SetParams(const AInitialDir: string;
  AMode: TFileDialogMode; const AInitialFilename: string);
begin
  FMode        := AMode;
  FAccepted    := False;
  FResultPath  := '';
  FFilename    := AInitialFilename;
  FFilenameCur := Length(FFilename) + 1;
  FSel         := 0;
  FTopRow      := 0;
  FFocus       := fsList;
  FCurrentDir  := ExcludeTrailingPathDelimiter(AInitialDir);
  if not DirectoryExists(FCurrentDir) then
    FCurrentDir := GetUserDir;
  if FCurrentDir = '' then FCurrentDir := PathDelim;
  LoadDir;
  Invalidate;
end;

function TFileDialog.RunModal: Boolean;
begin
  FAccepted   := False;
  ModalResult := 0;
  Application.ShowModal(Self);
  Result := FAccepted;
end;

{ ── One-shot helpers ── }

function RunOpenDialog(const AInitialDir: string; var APath: string;
  const ATitle: string): Boolean;
var D: TFileDialog;
begin
  D := TFileDialog.Create(ATitle);
  try
    D.SetParams(AInitialDir, fdOpen, ExtractFileName(APath));
    Result := D.RunModal;
    if Result then APath := D.ResultPath;
  finally D.Free; end;
end;

function RunSaveDialog(const AInitialDir: string; var APath: string;
  const ATitle: string): Boolean;
var D: TFileDialog;
begin
  D := TFileDialog.Create(ATitle);
  try
    D.SetParams(AInitialDir, fdSave, ExtractFileName(APath));
    Result := D.RunModal;
    if Result then APath := D.ResultPath;
  finally D.Free; end;
end;

function RunDirDialog(const AInitialDir: string; var APath: string;
  const ATitle: string): Boolean;
var D: TFileDialog;
begin
  D := TFileDialog.Create(ATitle);
  try
    D.SetParams(AInitialDir, fdSelectDir, '');
    Result := D.RunModal;
    if Result then APath := D.ResultPath;
  finally D.Free; end;
end;

end.
