{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.PathPicker;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, TermUI.Terminal, TermUI.Menu;

{ Full-screen recursive path picker. ABaseDir is the root to browse.
  ADirsOnly=True restricts selection to directories.
  APath is both the initial value and the result. Returns True on accept. }
function RunPathPicker(const ABaseDir, APrompt: string;
  ADirsOnly: Boolean; var APath: string): Boolean;

implementation

function RunPathPicker(const ABaseDir, APrompt: string;
  ADirsOnly: Boolean; var APath: string): Boolean;
var
  Filter:        string;
  Shown:         TStringList;
  FilterFocused: Boolean;
  NeedRefresh:   Boolean;
  K:             TKeyEvent;
  Sel:           Integer;
  TopRow, VR:    Integer;
  AbsPath:       string;
  ShowHidden:    Boolean;

  { Recursively collect all entries under ADir (relative to ABaseDir) into Shown. }
  procedure CollectAll(const ARelDir: string);
  var
    SR:       TSearchRec;
    AbsDir:   string;
    RelEntry: string;
  begin
    AbsDir := IncludeTrailingPathDelimiter(ABaseDir) + ARelDir;
    if FindFirst(AbsDir + '*', faAnyFile, SR) = 0 then
    try
      repeat
        if (SR.Name = '.') or (SR.Name = '..') then Continue;
        if (not ShowHidden) and (SR.Name[1] = '.') then Continue;
        if (SR.Attr and faDirectory) <> 0 then
        begin
          RelEntry := ARelDir + SR.Name + PathDelim;
          Shown.Add(RelEntry);
          CollectAll(RelEntry);
        end
        else if not ADirsOnly then
          Shown.Add(ARelDir + SR.Name);
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;

  procedure BuildShown;
  var
    All:      TStringList;
    SaveShown: TStringList;
    I:        Integer;
    NamePart: string;
  begin
    NamePart := ExtractFileName(ExcludeTrailingPathDelimiter(Filter));
    ShowHidden := (NamePart <> '') and (NamePart[1] = '.');
    All := TStringList.Create;
    try
      SaveShown := Shown;
      Shown := All;
      CollectAll('');
      Shown := SaveShown;
      Shown.Clear;
      for I := 0 to All.Count - 1 do
        if (Filter = '') or
           (Pos(LowerCase(Filter), LowerCase(All[I])) > 0) then
          Shown.Add(All[I]);
    finally
      All.Free;
    end;
  end;

  procedure DrawScreen;
  var RI, R: Integer; Entry: string;
  begin
    Term.ClearScreen;
    DrawHeader(APrompt, 1);

    Term.GotoXY(1, 3);
    Term.ClearToEOL;
    if FilterFocused then
    begin
      Term.SetFG(clWhite);
      Term.SetBG(clBlue);
    end
    else
    begin
      Term.SetFG(clBrightBlack);
      Term.SetBG(clDefault);
    end;
    Term.WriteStr(' Path: ' + PadRight(Filter, Term.Width - 9));
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
        Entry := Shown[RI];
        if (not FilterFocused) and (RI = Sel) then
        begin
          Term.SetFG(clBlack);
          Term.SetBG(clCyan);
          Term.WriteStr(' > ' + Entry);
        end
        else
        begin
          if (Length(Entry) > 0) and (Entry[Length(Entry)] = PathDelim) then
            Term.SetFG(clCyan)    // directory
          else
            Term.ResetColors;
          Term.WriteStr('   ' + Entry);
        end;
        Term.ResetColors;
      end;
    end;

    if Shown.Count = 0 then
    begin
      Term.GotoXY(3, TopRow);
      Term.SetFG(clBrightBlack);
      Term.WriteStr('(no matches)');
      Term.ResetColors;
    end;

    DrawRule(Term.Height - 1, 1, Term.Width);
    Term.GotoXY(1, Term.Height);
    Term.SetFG(clBrightBlack);
    Term.WriteStr(' Type path   ↑↓ Browse   Enter Accept   Esc Cancel ');
    Term.ResetColors;
    if FilterFocused then
      Term.GotoXY(8 + Length(Filter), 3)
    else
      Term.GotoXY(1, TopRow + Sel);
    Term.FlushOutput;
  end;

begin
  Result        := False;
  Filter        := APath;
  Sel           := 0;
  FilterFocused := True;
  TopRow        := 4;
  Shown := TStringList.Create;
  try
    BuildShown;
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
            { Populate filter from list selection, return focus to filter box }
            Filter := Shown[Sel];
            BuildShown;
            Sel := 0;
            FilterFocused := True;
            NeedRefresh := True;
          end
          else
          begin
            { Enter in filter box — check existence then accept }
            if Filter <> '' then
            begin
              AbsPath := IncludeTrailingPathDelimiter(ABaseDir) + Filter;
              if not DirectoryExists(AbsPath) and not FileExists(AbsPath) then
              begin
                Term.HideCursor;
                if Confirm('Path does not exist. Create folder?', True) then
                  ForceDirectories(AbsPath);
                Term.ShowCursor;
                DrawScreen;
              end;
            end;
            APath  := Filter;
            Result := True;
            Break;
          end;
        end;

        kcBackspace: begin
          if Length(Filter) > 0 then
          begin
            Delete(Filter, Length(Filter), 1);
            BuildShown;
            Sel := 0;
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
  end;
end;

end.
