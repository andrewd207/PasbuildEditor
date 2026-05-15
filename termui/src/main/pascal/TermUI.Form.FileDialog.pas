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
  Classes, SysUtils, Masks,
  TermUI.StringUtils, TermUI.Terminal,
  TermUI.Control, TermUI.Forms, TermUI.Application, TermUI.Menu;

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
    type TFocus = (fsList, fsFilename);
  private
    FMode:        TFileDialogMode;
    FCurrentDir:  string;
    FRaw:         array of TFileEntry;   { all entries loaded from disk }
    FRawCount:    Integer;
    FDisplay:     array of TFileEntry;   { filtered subset shown in list }
    FDisplayCount: Integer;
    FFilter:      string;                { live substring filter }
    FFileFilter:  string;                { glob pattern e.g. *.pas;*.pp }
    FSel:         Integer;
    FTopRow:      Integer;
    FFilename:    string;
    FFilenameCur: Integer;
    FFocus:       TFocus;
    FShowHidden:  Boolean;
    FAccepted:    Boolean;
    FResultPath:  string;

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

    procedure FilenameInsert(ACh: Char);
    procedure FilenameBackspace;
    procedure FilenameDelete;
    procedure FilenameMoveLeft;
    procedure FilenameMoveRight;
    procedure FilenameHome;
    procedure FilenameEnd;
    procedure FilenameCalcScroll(out AScroll: Integer);

  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
  public
    constructor Create(const ATitle: string = ''); override;

    procedure SetParams(const AInitialDir: string; AMode: TFileDialogMode;
      const AInitialFilename: string = '');
    function  RunModal: Boolean;

    { Semicolon-separated glob patterns for files.  '*' = all (default).
      Directories are always shown regardless of this filter. }
    property FileFilter:  string  read FFileFilter write FFileFilter;
    property Accepted:    Boolean read FAccepted;
    property ResultPath:  string  read FResultPath;
  end;

{ One-shot helpers }
function RunOpenDialog(const AInitialDir: string; var APath: string;
  const ATitle: string = 'Open'): Boolean;
function RunSaveDialog(const AInitialDir: string; var APath: string;
  const ATitle: string = 'Save'): Boolean;
function RunDirDialog(const AInitialDir: string; var APath: string;
  const ATitle: string = 'Select Folder'): Boolean;

implementation

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
  N:    Integer;
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
    var E := FRaw[N];
    var I := N - 1;
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
      if (FFilter = '') or
         PosNeutral(LowerCase(FFilter), LowerCase(FRaw[I].Name)) then
      begin
        FDisplay[FDisplayCount] := FRaw[I];
        Inc(FDisplayCount);
      end;
    end
    else
    begin
      if ((FFilter = '') or
          PosNeutral(LowerCase(FFilter), LowerCase(FRaw[I].Name))) and
         MatchesFileFilter(FRaw[I].Name) then
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
  FCurrentDir := IncludeTrailingPathDelimiter(FCurrentDir) + ADirName;
  FFilter     := '';
  FSel        := 0;
  FTopRow     := 0;
  LoadDir;
  Invalidate;
end;

procedure TFileDialog.NavigateUp;
var Parent: string;
begin
  Parent := ExcludeTrailingPathDelimiter(
              ExtractFileDir(ExcludeTrailingPathDelimiter(FCurrentDir)));
  if Parent = '' then Parent := PathDelim;
  FCurrentDir := Parent;
  FFilter     := '';
  FSel        := 0;
  FTopRow     := 0;
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
  if FSel < FTopRow then FTopRow := FSel;
  if FSel >= FTopRow + ListRows then FTopRow := FSel - ListRows + 1;
  if FTopRow < 0 then FTopRow := 0;
end;

{ ── Filename field ── }

procedure TFileDialog.FilenameCalcScroll(out AScroll: Integer);
var FieldW: Integer;
begin
  FieldW  := Term.Width - 12;
  AScroll := 0;
  if FFilenameCur - AScroll > FieldW then AScroll := FFilenameCur - FieldW;
  if FFilenameCur - 1 < AScroll      then AScroll := FFilenameCur - 1;
  if AScroll < 0 then AScroll := 0;
end;

procedure TFileDialog.FilenameInsert(ACh: Char);
begin Insert(ACh, FFilename, FFilenameCur); Inc(FFilenameCur); Invalidate; end;
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

{ ── Drawing ── }

procedure TFileDialog.DrawPath;
var PathStr, Shown, FilterHint: string;
begin
  Term.GotoXY(1, 2);
  Term.ClearToEOL;
  PathStr := FCurrentDir;
  FilterHint := '';
  if (FFileFilter <> '') and (FFileFilter <> '*') then
    FilterHint := '  [' + FFileFilter + ']';
  if Length(PathStr) + Length(FilterHint) > Term.Width - 2 then
    Shown := '~' + Copy(PathStr, Length(PathStr) - (Term.Width - 4 - Length(FilterHint)), MaxInt)
  else
    Shown := PathStr;
  Term.WriteStr(' ');
  Term.SetFG(clBrightCyan);
  Term.WriteStr(Shown);
  if FilterHint <> '' then
  begin
    Term.SetFG(clBrightBlack);
    Term.WriteStr(FilterHint);
  end;
  Term.ResetColors;
  DrawRule(3, 1, Term.Width);
end;

procedure TFileDialog.DrawList;
var
  RI, Idx, NameW: Integer;
  E:              TFileEntry;
  Name, SizeStr, Line: string;
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

    { Name prefix + truncation }
    if E.Name = '..' then
      Name := ' [..] ..'
    else if E.IsDir then
      Name := ' [+] ' + E.Name
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
      if not IsSelected then Term.SetFG(clBrightBlack);
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
    if FFilter <> '' then
      Term.WriteStr('(no matches for "' + FFilter + '")')
    else
      Term.WriteStr('(empty directory)');
    Term.ResetColors;
  end;

  { Live filter indicator in first header row margin }
  if FFilter <> '' then
  begin
    Term.GotoXY(Term.Width - Length(FFilter) - 3, 3);
    Term.SetFG(clBrightBlack);
    Term.WriteStr(' /' + FFilter + '/');
    Term.ResetColors;
  end;
end;

procedure TFileDialog.DrawFilenameField;
var
  H, FieldW, Scroll: Integer;
  Visible: string;
begin
  H      := Term.Height;
  FieldW := Term.Width - 12;
  DrawRule(H - 2, 1, Term.Width);
  Term.GotoXY(1, H - 1);
  Term.ClearToEOL;
  if FFocus = fsFilename then Term.SetFG(clBrightWhite)
  else                        Term.SetFG(clBrightBlack);
  Term.WriteStr(' Filename: ');
  Term.ResetColors;
  FilenameCalcScroll(Scroll);
  Visible := CopyNeutral(FFilename, Scroll, FieldW);
  Term.WriteStr(Visible);
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
      Term.WriteStr(' ↑↓ Browse  Enter Select  Tab Filename  H Hidden  Esc Cancel');
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
      Term.GotoXY(1, HEADER_ROWS + 1 + (FSel - FTopRow));
    fsFilename:
      begin
        FilenameCalcScroll(Scroll);
        H := Term.Height;
        Term.GotoXY(11 + (FFilenameCur - Scroll), H - 1);
      end;
  end;
end;

{ ── DoPaint / DoKeyDown ── }

procedure TFileDialog.DoPaint;
begin
  Term.ClearScreen;
  DrawHeader(Title, 1);
  DrawPath;
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
      kcTab:       begin FFocus := fsList; Invalidate; end;
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

  { fsList }
  case Key.Code of
    kcEscape: Close(1);

    kcUp:
      begin
        if FSel > 0 then Dec(FSel);
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
    kcEnter:     SelectCurrent;
    kcTab:       begin FFocus := fsFilename; Invalidate; end;

    kcBackspace:
      begin
        if FFilter <> '' then
        begin
          DeleteNeutral(FFilter, Length(FFilter) - 1, 1);
          FSel := 0; FTopRow := 0;
          RebuildDisplay; Invalidate;
        end
        else
          NavigateUp;
      end;

    kcChar:
      begin
        case Key.Ch of
          'h', 'H':
            begin
              FShowHidden := not FShowHidden;
              FSel := 0; FTopRow := 0;
              LoadDir; Invalidate;
            end;
        else
          if Key.Ch >= ' ' then
          begin
            FFilter := FFilter + Key.Ch;
            FSel    := 0; FTopRow := 0;
            RebuildDisplay; Invalidate;
          end;
        end;
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

procedure TFileDialog.SetParams(const AInitialDir: string;
  AMode: TFileDialogMode; const AInitialFilename: string);
begin
  FMode        := AMode;
  FAccepted    := False;
  FResultPath  := '';
  FFilename    := AInitialFilename;
  FFilenameCur := Length(FFilename) + 1;
  FFilter      := '';
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
