{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.PathPicker;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, TermUI.StringUtils, TermUI.Terminal, TermUI.Control,
     TermUI.Forms, TermUI.Application, TermUI.Menu;

{ Full-screen recursive path picker. ABaseDir is the root to browse.
  ADirsOnly=True restricts selection to directories.
  APath is both the initial value and the result. Returns True on accept. }
function RunPathPicker(const ABaseDir, APrompt: string;
  ADirsOnly: Boolean; var APath: string): Boolean;

implementation

type
  TPathPicker = class(TForm)
  private
    FBaseDir:       string;
    FPrompt_:       string;
    FDirsOnly:      Boolean;
    FFilter:        string;
    FShown:         TStringList;
    FFilterFocused: Boolean;
    FSel:           Integer;
    FTopRow:        Integer;
    FVR:            Integer;
    FShowHidden:    Boolean;
    FAccepted:      Boolean;
    FResultPath:    string;

    procedure CollectAll(const ARelDir: string);
    procedure BuildShown;
    procedure PlaceCursor;
    procedure RefreshScreen;
    procedure HandleAccept;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
  public
    constructor Create(const ATitle: string = ''); override;
    destructor Destroy; override;

    procedure SetParams(const ABaseDir, APrompt: string;
      ADirsOnly: Boolean; const AInitialPath: string);

    function RunModal: Boolean;

    property Accepted:    Boolean read FAccepted;
    property ResultPath:  string  read FResultPath;
  end;

{ ══════════════════════════════════════════════════════════════════════
  TPathPicker implementation
  ══════════════════════════════════════════════════════════════════════ }

constructor TPathPicker.Create(const ATitle: string);
begin
  inherited Create(ATitle);
  FShown         := TStringList.Create;
  FFilterFocused := True;
  FSel           := 0;
  FTopRow        := 4;
  FVR            := 0;
  FShowHidden    := False;
  FAccepted      := False;
end;

destructor TPathPicker.Destroy;
begin
  FShown.Free;
  inherited;
end;

procedure TPathPicker.SetParams(const ABaseDir, APrompt: string;
  ADirsOnly: Boolean; const AInitialPath: string);
begin
  FBaseDir   := ABaseDir;
  FPrompt_   := APrompt;
  FDirsOnly  := ADirsOnly;
  FFilter    := AInitialPath;
  FAccepted  := False;
  FResultPath := '';
  BuildShown;
  Invalidate;
end;

procedure TPathPicker.CollectAll(const ARelDir: string);
var
  SR:       TSearchRec;
  AbsDir:   string;
  RelEntry: string;
begin
  AbsDir := IncludeTrailingPathDelimiter(FBaseDir) + ARelDir;
  if FindFirst(AbsDir + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then Continue;
      if (not FShowHidden) and (CharFromIndex(SR.Name, 0) = '.') then Continue;
      if (SR.Attr and faDirectory) <> 0 then
      begin
        RelEntry := ARelDir + SR.Name + PathDelim;
        FShown.Add(RelEntry);
        CollectAll(RelEntry);
      end
      else if not FDirsOnly then
        FShown.Add(ARelDir + SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

procedure TPathPicker.BuildShown;
var
  All:      TStringList;
  NamePart: string;
  I:        Integer;
begin
  NamePart    := ExtractFileName(ExcludeTrailingPathDelimiter(FFilter));
  FShowHidden := (NamePart <> '') and (NamePart.Index[0] = '.');
  All := TStringList.Create;
  try
    { swap FShown so CollectAll writes into All }
    FShown.Clear;
    CollectAll('');
    All.Assign(FShown);
    FShown.Clear;
    for I := 0 to All.Count - 1 do
      if (FFilter = '') or
         PosNeutral(LowerCase(FFilter), LowerCase(All[I])) then
        FShown.Add(All[I]);
  finally
    All.Free;
  end;
end;

procedure TPathPicker.PlaceCursor;
begin
  if FFilterFocused then
    Term.GotoXY(8 + Length(FFilter), 3)
  else
    Term.GotoXY(1, FTopRow + FSel);
end;

procedure TPathPicker.RefreshScreen;
begin
  DoPaint;
  Term.FlushOutput;
end;

procedure TPathPicker.DoPaint;
var RI, R: Integer; Entry: string;
begin
  FTopRow := 4;
  FVR     := Term.Height - FTopRow - 2;

  Term.HideCursor;
  Term.ClearScreen;
  DrawHeader(FPrompt_, 1);

  Term.GotoXY(1, 3);
  Term.ClearToEOL;
  if FFilterFocused then
  begin
    Term.SetFG(clWhite);
    Term.SetBG(clBlue);
  end
  else
  begin
    Term.SetFG(clBrightBlack);
    Term.SetBG(clDefault);
  end;
  Term.WriteStr(' Path: ' + PadRight(FFilter, Term.Width - 9));
  Term.ResetColors;

  for RI := 0 to FVR - 1 do
  begin
    R := FTopRow + RI;
    Term.GotoXY(1, R);
    Term.ClearToEOL;
    if RI < FShown.Count then
    begin
      Entry := FShown[RI];
      if (not FFilterFocused) and (RI = FSel) then
      begin
        Term.SetFG(clBlack);
        Term.SetBG(clCyan);
        Term.WriteStr(' > ' + Entry);
      end
      else
      begin
        if (Length(Entry) > 0) and (Entry.Index[Length(Entry) - 1] = PathDelim) then
          Term.SetFG(clCyan)
        else
          Term.ResetColors;
        Term.WriteStr('   ' + Entry);
      end;
      Term.ResetColors;
    end;
  end;

  if FShown.Count = 0 then
  begin
    Term.GotoXY(3, FTopRow);
    Term.SetFG(clBrightBlack);
    Term.WriteStr('(no matches)');
    Term.ResetColors;
  end;

  DrawRule(Term.Height - 1, 1, Term.Width);
  Term.GotoXY(1, Term.Height);
  Term.SetFG(clBrightBlack);
  Term.WriteStr(' Type path   ↑↓ Browse   Enter Accept   Esc Cancel ');
  Term.ResetColors;

  Term.ShowCursor;
  PlaceCursor;
  inherited DoPaint;
end;

procedure TPathPicker.HandleAccept;
var
  AbsPath: string;
begin
  if FFilter <> '' then
  begin
    AbsPath := IncludeTrailingPathDelimiter(FBaseDir) + FFilter;
    if not DirectoryExists(AbsPath) and not FileExists(AbsPath) then
    begin
      Term.HideCursor;
      if Confirm('Path does not exist. Create folder?', True) then
        ForceDirectories(AbsPath);
      Term.ShowCursor;
      RefreshScreen;
      Exit;
    end;
  end;
  FResultPath := FFilter;
  FAccepted   := True;
  Term.HideCursor;
  Close(1);
end;

function TPathPicker.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  Result := True;
  case Key.Code of
    kcEscape: Close(1);  // FAccepted stays False

    kcUp: begin
      if FFilterFocused then
      begin
        FFilterFocused := False;
        if FSel >= FShown.Count then FSel := 0;
      end
      else if FSel > 0 then Dec(FSel);
      RefreshScreen;
    end;

    kcDown: begin
      if FFilterFocused then
      begin
        FFilterFocused := False;
        if FSel >= FShown.Count then FSel := 0;
      end
      else if FSel < FShown.Count - 1 then Inc(FSel);
      RefreshScreen;
    end;

    kcPageUp: begin
      FVR := Term.Height - FTopRow - 2;
      FFilterFocused := False;
      Dec(FSel, FVR); if FSel < 0 then FSel := 0;
      RefreshScreen;
    end;

    kcPageDown: begin
      FVR := Term.Height - FTopRow - 2;
      FFilterFocused := False;
      Inc(FSel, FVR);
      if FSel >= FShown.Count then FSel := FShown.Count - 1;
      if FSel < 0 then FSel := 0;
      RefreshScreen;
    end;

    kcHome: begin FFilterFocused := False; FSel := 0; RefreshScreen; end;
    kcEnd:  begin
      FFilterFocused := False;
      if FShown.Count > 0 then FSel := FShown.Count - 1;
      RefreshScreen;
    end;

    kcEnter: begin
      if (not FFilterFocused) and (FSel >= 0) and (FSel < FShown.Count) then
      begin
        FFilter        := FShown[FSel];
        BuildShown;
        FSel           := 0;
        FFilterFocused := True;
        RefreshScreen;
      end
      else
        HandleAccept;
    end;

    kcBackspace: begin
      if Length(FFilter) > 0 then
      begin
        DeleteNeutral(FFilter, Length(FFilter) - 1, 1);
        BuildShown;
        FSel           := 0;
        FFilterFocused := True;
        RefreshScreen;
      end;
    end;

    kcChar: begin
      FFilter        := FFilter + Key.Ch;
      BuildShown;
      FSel           := 0;
      FFilterFocused := True;
      RefreshScreen;
    end;

    else
      Result := False;  // unhandled — bubbles to Application.OnKeyDown
  end;
end;

function TPathPicker.RunModal: Boolean;
begin
  FAccepted   := False;
  ModalResult := 0;
  Application.ShowModal(Self);
  Result := FAccepted;
end;

{ ══════════════════════════════════════════════════════════════════════
  Standalone helper
  ══════════════════════════════════════════════════════════════════════ }

function RunPathPicker(const ABaseDir, APrompt: string;
  ADirsOnly: Boolean; var APath: string): Boolean;
var
  Picker: TPathPicker;
begin
  Picker := TPathPicker.Create;
  try
    Picker.SetParams(ABaseDir, APrompt, ADirsOnly, APath);
    Result := Picker.RunModal;
    if Result then
      APath := Picker.ResultPath;
  finally
    Picker.Free;
  end;
end;

end.
