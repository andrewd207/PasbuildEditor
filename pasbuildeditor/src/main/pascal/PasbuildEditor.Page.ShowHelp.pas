{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Page.ShowHelp;

{$mode objfpc}{$H+}
{$R '../resources/help/help.rc'}

interface

{ Show the help page for ADocName (e.g. 'project', 'build', 'modules').
  AContextKey is the menu item label to scroll to; empty = show from top. }
procedure ShowHelpPage(const ADocName: string; const AContextKey: string = '');

implementation

uses
  Classes, SysUtils, fgl,
  TermUI.Terminal, TermUI.Menu;

const
  HELP_RES_PROJECT = 'HELP_PROJECT';
  HELP_RES_BUILD   = 'HELP_BUILD';
  HELP_RES_MODULES = 'HELP_MODULES';

{ ══════════════════════════════════════════════════════════════════════
  Display line types
  ══════════════════════════════════════════════════════════════════════ }

type
  TDisplayLineKind = (
    dlkBlank,
    dlkH1, dlkH2, dlkH3, dlkH4,
    dlkPara,
    dlkCode,
    dlkRule,
    dlkBullet
  );

  TDisplayLine = class
    Kind: TDisplayLineKind;
    Text: string;
    constructor Create(AKind: TDisplayLineKind; const AText: string);
  end;

  TDisplayLineList = specialize TFPGObjectList<TDisplayLine>;

  TTOCEntry = record
    Heading:  string;
    LineIdx:  Integer;
  end;

  TTOCList = array of TTOCEntry;

constructor TDisplayLine.Create(AKind: TDisplayLineKind; const AText: string);
begin
  inherited Create;
  Kind := AKind;
  Text := AText;
end;

{ ══════════════════════════════════════════════════════════════════════
  AsciiDoc parser helpers
  ══════════════════════════════════════════════════════════════════════ }

function ParseHeadingLine(const S: string; out ALevel: Integer;
  out AText: string): Boolean;
var
  I: Integer;
begin
  ALevel := 0;
  AText  := '';
  I := 1;
  while (I <= Length(S)) and (S[I] = '=') do
  begin
    Inc(ALevel);
    Inc(I);
  end;
  Result := (ALevel >= 1) and (ALevel <= 4) and (I <= Length(S)) and (S[I] = ' ');
  if Result then
    AText := Trim(Copy(S, I + 1, MaxInt))
  else
    ALevel := 0;
end;

{ Append word-wrapped lines of AText (at AWidth columns) to AList. }
procedure AppendWrapped(const AText: string; AWidth: Integer;
  AKind: TDisplayLineKind; AList: TDisplayLineList);
var
  Words:   TStringList;
  Line, W: string;
  I:       Integer;
begin
  if AWidth < 4 then AWidth := 4;
  Words := TStringList.Create;
  try
    Words.Delimiter     := ' ';
    Words.StrictDelimiter := True;
    Words.DelimitedText := AText;

    Line := '';
    for I := 0 to Words.Count - 1 do
    begin
      W := Words[I];
      if W = '' then Continue;

      if Line = '' then
      begin
        if Length(W) > AWidth then
          W := Copy(W, 1, AWidth);
        Line := W;
      end
      else if Length(Line) + 1 + Length(W) > AWidth then
      begin
        AList.Add(TDisplayLine.Create(AKind, Line));
        if Length(W) > AWidth then
          W := Copy(W, 1, AWidth);
        Line := W;
      end
      else
        Line := Line + ' ' + W;
    end;

    if Line <> '' then
      AList.Add(TDisplayLine.Create(AKind, Line));
  finally
    Words.Free;
  end;
end;

{ Build display lines + TOC from raw AsciiDoc text. }
procedure BuildDisplayLines(ARaw: TStringList; AContentWidth: Integer;
  ADisplay: TDisplayLineList; out ATOC: TTOCList; out ATOCCount: Integer);
var
  I, Level:  Integer;
  S, Txt:    string;
  InCode:    Boolean;
  InTable:   Boolean;

  procedure Push(AKind: TDisplayLineKind; const AText: string = '');
  begin
    ADisplay.Add(TDisplayLine.Create(AKind, AText));
  end;

  procedure AddTOC(const AHeading: string);
  begin
    if ATOCCount >= Length(ATOC) then
      SetLength(ATOC, ATOCCount + 16);
    ATOC[ATOCCount].Heading := AHeading;
    ATOC[ATOCCount].LineIdx := ADisplay.Count - 1;
    Inc(ATOCCount);
  end;

begin
  ATOCCount := 0;
  SetLength(ATOC, 16);
  InCode  := False;
  InTable := False;

  for I := 0 to ARaw.Count - 1 do
  begin
    S := ARaw[I];

    if S = '----' then
    begin
      InCode := not InCode;
      Push(dlkRule);
      Continue;
    end;

    if InCode then
    begin
      Push(dlkCode, S);
      Continue;
    end;

    if (Length(S) > 0) and (S[1] = '[') then Continue;
    if S = '|===' then begin InTable := not InTable; Continue; end;
    if InTable then Continue;
    if Copy(S, 1, 2) = '//' then Continue;

    if Trim(S) = '' then
    begin
      { Collapse consecutive blanks }
      if (ADisplay.Count > 0) and (ADisplay[ADisplay.Count - 1].Kind <> dlkBlank) then
        Push(dlkBlank);
      Continue;
    end;

    if ParseHeadingLine(S, Level, Txt) then
    begin
      case Level of
        1: Push(dlkH1, Txt);
        2: begin Push(dlkH2, Txt); AddTOC(Txt); end;
        3: Push(dlkH3, Txt);
        else Push(dlkH4, Txt);
      end;
      Continue;
    end;

    if (Length(S) >= 3) and (S = StringOfChar('-', Length(S))) then
    begin
      Push(dlkRule);
      Continue;
    end;

    if (Length(S) >= 2) and (S[1] in ['*', '-']) and (S[2] = ' ') then
    begin
      AppendWrapped(Copy(S, 3, MaxInt), AContentWidth - 2, dlkBullet, ADisplay);
      Continue;
    end;

    if (Length(S) >= 2) and (S[1] = '.') and (S[2] = ' ') then
    begin
      AppendWrapped(Copy(S, 3, MaxInt), AContentWidth - 2, dlkBullet, ADisplay);
      Continue;
    end;

    if (Length(S) > 0) and (S[1] = '|') then
    begin
      Push(dlkPara, Copy(S, 2, MaxInt));
      Continue;
    end;

    AppendWrapped(S, AContentWidth, dlkPara, ADisplay);
  end;
end;

{ ══════════════════════════════════════════════════════════════════════
  Inline markup renderer — renders one string with *bold*, _italic_, `mono`
  ══════════════════════════════════════════════════════════════════════ }

procedure RenderInline(const S: string; MaxCols: Integer);
var
  I, Col: Integer;
  InBold, InItal, InMono: Boolean;
  Ch: Char;
begin
  InBold := False;
  InItal := False;
  InMono := False;
  Col    := 0;
  I      := 1;
  while (I <= Length(S)) and (Col < MaxCols) do
  begin
    Ch := S[I];
    case Ch of
      '*': begin
        InBold := not InBold;
        if InBold then Term.SetFG(clBrightWhite)
        else Term.ResetColors;
      end;
      '_': begin
        InItal := not InItal;
        Term.SetUnderline(InItal);
      end;
      '`', '+': begin
        InMono := not InMono;
        if InMono then Term.SetFG(clCyan)
        else Term.ResetColors;
      end;
      else begin
        Term.WriteStr(Ch);
        Inc(Col);
      end;
    end;
    Inc(I);
  end;
  Term.ResetColors;
  Term.SetUnderline(False);
end;

{ ══════════════════════════════════════════════════════════════════════
  Layout
  ══════════════════════════════════════════════════════════════════════ }

const
  TOC_W     = 22;
  HELP_FOOT = ' ↑↓ Scroll   Tab/←→ Switch panel   Enter Jump   Esc Close ';

{ ══════════════════════════════════════════════════════════════════════
  Main help-page procedure
  ══════════════════════════════════════════════════════════════════════ }

procedure ShowHelpPage(const ADocName: string; const AContextKey: string);
var
  ResName:   string;
  ResStream: TResourceStream;
  RawLines:  TStringList;
  Display:   TDisplayLineList;
  TOC:       TTOCList;
  TOCCount:  Integer;
  ContentW:  Integer;
  ContentX:  Integer;

  TOCSel:     Integer;
  TOCScroll:  Integer;
  DispScroll: Integer;
  FocusTOC:   Boolean;

  K: TKeyEvent;

  function ContentRows: Integer;
  begin
    Result := Term.Height - 4;
    if Result < 1 then Result := 1;
  end;

  function TOCRows: Integer;
  begin
    Result := ContentRows;
  end;

  procedure TOCEnsureVisible;
  var VR: Integer;
  begin
    if TOCCount = 0 then Exit;
    VR := TOCRows;
    if TOCSel < TOCScroll then
      TOCScroll := TOCSel
    else if TOCSel >= TOCScroll + VR then
      TOCScroll := TOCSel - VR + 1;
    if TOCScroll < 0 then TOCScroll := 0;
  end;

  procedure ScrollToLine(LineIdx: Integer);
  begin
    DispScroll := LineIdx;
    if DispScroll < 0 then DispScroll := 0;
    if (Display.Count > 0) and (DispScroll >= Display.Count) then
      DispScroll := Display.Count - 1;
  end;

  procedure DrawTOCRow(ATOCIdx, ARow: Integer);
  var
    IsSel: Boolean;
    Txt:   string;
  begin
    Term.GotoXY(1, ARow);
    Term.ClearToEOL;
    if (ATOCIdx < 0) or (ATOCIdx >= TOCCount) then Exit;
    IsSel := (ATOCIdx = TOCSel);
    Txt := TOC[ATOCIdx].Heading;
    if Length(Txt) > TOC_W - 3 then
      Txt := Copy(Txt, 1, TOC_W - 4) + '…';
    if IsSel then
    begin
      if FocusTOC then
        begin Term.SetFG(clBlack); Term.SetBG(clCyan); end
      else
        begin Term.SetFG(clCyan); end;
      Term.WriteStr(' > ' + Txt);
    end
    else
    begin
      Term.SetFG(clBrightBlack);
      Term.WriteStr('   ' + Txt);
    end;
    Term.ResetColors;
  end;

  procedure DrawSeparator;
  var R: Integer;
  begin
    for R := 3 to Term.Height - 2 do
    begin
      Term.GotoXY(TOC_W + 1, R);
      Term.SetFG(clBrightBlack);
      Term.WriteStr('│');
      Term.ResetColors;
    end;
  end;

  procedure DrawContentRow(ADispIdx, ARow: Integer);
  var
    DL: TDisplayLine;
    W:  Integer;
  begin
    Term.GotoXY(ContentX, ARow);
    W := ContentW;
    Term.ResetColors;
    Term.WriteStr(StringOfChar(' ', W));
    Term.GotoXY(ContentX, ARow);

    if (ADispIdx < 0) or (ADispIdx >= Display.Count) then Exit;
    DL := Display[ADispIdx];

    case DL.Kind of
      dlkBlank: ;
      dlkRule: begin
        Term.SetFG(clBrightBlack);
        Term.WriteStr(StringOfChar('-', W));
        Term.ResetColors;
      end;
      dlkH1: begin
        Term.SetFG(clBrightCyan);
        Term.WriteStr(Copy(DL.Text, 1, W));
        Term.ResetColors;
      end;
      dlkH2: begin
        Term.SetFG(clBrightYellow);
        Term.SetUnderline(True);
        Term.WriteStr(Copy(DL.Text, 1, W));
        Term.SetUnderline(False);
        Term.ResetColors;
      end;
      dlkH3: begin
        Term.SetFG(clBrightGreen);
        Term.WriteStr(Copy(DL.Text, 1, W));
        Term.ResetColors;
      end;
      dlkH4: begin
        Term.SetFG(clGreen);
        Term.WriteStr(Copy(DL.Text, 1, W));
        Term.ResetColors;
      end;
      dlkCode: begin
        Term.SetFG(clBrightBlack);
        Term.WriteStr(Copy(DL.Text, 1, W));
        Term.ResetColors;
      end;
      dlkBullet: begin
        Term.SetFG(clBrightYellow);
        Term.WriteStr('• ');
        Term.ResetColors;
        RenderInline(Copy(DL.Text, 1, W - 2), W - 2);
      end;
      dlkPara:
        RenderInline(Copy(DL.Text, 1, W), W);
    end;
  end;

  procedure DrawAll;
  var
    R: Integer;
  begin
    Term.ClearScreen;
    DrawHeader('Help: ' + ADocName, 1);
    DrawSeparator;

    for R := 0 to TOCRows - 1 do
      DrawTOCRow(TOCScroll + R, 3 + R);

    for R := 0 to ContentRows - 1 do
      DrawContentRow(DispScroll + R, 3 + R);

    DrawRule(Term.Height - 1, 1, Term.Width);
    Term.GotoXY(1, Term.Height);
    Term.ClearToEOL;
    Term.SetFG(clBrightBlack);
    Term.WriteStr(HELP_FOOT);
    Term.ResetColors;

    Term.FlushOutput;
  end;

  procedure Rebuild;
  begin
    ContentX := TOC_W + 2;
    ContentW := Term.Width - ContentX + 1;
    if ContentW < 10 then ContentW := 10;
    Display.Clear;
    TOCCount := 0;
    SetLength(TOC, 16);
    BuildDisplayLines(RawLines, ContentW, Display, TOC, TOCCount);
    if (TOCSel >= 0) and (TOCSel < TOCCount) then
      ScrollToLine(TOC[TOCSel].LineIdx);
    TOCEnsureVisible;
  end;

  function FindContextTOC(const AKey: string): Integer;
  var I: Integer;
  begin
    Result := -1;
    if AKey = '' then Exit;
    for I := 0 to TOCCount - 1 do
      if SameText(TOC[I].Heading, AKey) then
        begin Result := I; Exit; end;
    for I := 0 to TOCCount - 1 do
      if Pos(LowerCase(AKey), LowerCase(TOC[I].Heading)) > 0 then
        begin Result := I; Exit; end;
  end;

begin
  RawLines := TStringList.Create;
  Display  := TDisplayLineList.Create(True);
  try
    ResName := 'HELP_' + UpperCase(ADocName);
    ResStream := TResourceStream.Create(HInstance, ResName, RT_RCDATA);
    try
      RawLines.LoadFromStream(ResStream);
    finally
      ResStream.Free;
    end;

    TOCCount   := 0;
    TOCSel     := 0;
    TOCScroll  := 0;
    DispScroll := 0;
    FocusTOC   := True;
    SetLength(TOC, 16);
    ContentX   := TOC_W + 2;
    ContentW   := Term.Width - ContentX + 1;

    Rebuild;

    if AContextKey <> '' then
    begin
      TOCSel := FindContextTOC(AContextKey);
      if TOCSel < 0 then TOCSel := 0;
    end;
    if (TOCSel >= 0) and (TOCSel < TOCCount) then
    begin
      ScrollToLine(TOC[TOCSel].LineIdx);
      TOCEnsureVisible;
    end;

    DrawAll;

    repeat
      K := Term.ReadKey;

      if Term.HasResized then
      begin
        Rebuild;
        DrawAll;
        Continue;
      end;

      case K.Code of
        kcEscape, kcF1:
          Exit;

        kcTab, kcLeft, kcRight:
        begin
          FocusTOC := not FocusTOC;
          DrawAll;
        end;

        kcUp:
          if FocusTOC then
          begin
            if TOCSel > 0 then
            begin
              Dec(TOCSel);
              TOCEnsureVisible;
              ScrollToLine(TOC[TOCSel].LineIdx);
              DrawAll;
            end;
          end
          else
          begin
            if DispScroll > 0 then begin Dec(DispScroll); DrawAll; end;
          end;

        kcDown:
          if FocusTOC then
          begin
            if TOCSel < TOCCount - 1 then
            begin
              Inc(TOCSel);
              TOCEnsureVisible;
              ScrollToLine(TOC[TOCSel].LineIdx);
              DrawAll;
            end;
          end
          else
          begin
            if DispScroll < Display.Count - 1 then begin Inc(DispScroll); DrawAll; end;
          end;

        kcPageUp:
          if FocusTOC then
          begin
            Dec(TOCSel, TOCRows);
            if TOCSel < 0 then TOCSel := 0;
            TOCEnsureVisible;
            if TOCCount > 0 then ScrollToLine(TOC[TOCSel].LineIdx);
            DrawAll;
          end
          else
          begin
            Dec(DispScroll, ContentRows);
            if DispScroll < 0 then DispScroll := 0;
            DrawAll;
          end;

        kcPageDown:
          if FocusTOC then
          begin
            Inc(TOCSel, TOCRows);
            if TOCSel >= TOCCount then TOCSel := TOCCount - 1;
            if TOCSel < 0 then TOCSel := 0;
            TOCEnsureVisible;
            if TOCCount > 0 then ScrollToLine(TOC[TOCSel].LineIdx);
            DrawAll;
          end
          else
          begin
            Inc(DispScroll, ContentRows);
            if DispScroll >= Display.Count then DispScroll := Display.Count - 1;
            if DispScroll < 0 then DispScroll := 0;
            DrawAll;
          end;

        kcHome:
          if FocusTOC then
          begin
            TOCSel := 0;
            TOCEnsureVisible;
            if TOCCount > 0 then ScrollToLine(TOC[0].LineIdx);
            DrawAll;
          end
          else
          begin
            DispScroll := 0;
            DrawAll;
          end;

        kcEnd:
          if FocusTOC then
          begin
            if TOCCount > 0 then TOCSel := TOCCount - 1;
            TOCEnsureVisible;
            if TOCCount > 0 then ScrollToLine(TOC[TOCSel].LineIdx);
            DrawAll;
          end
          else
          begin
            DispScroll := Display.Count - 1;
            if DispScroll < 0 then DispScroll := 0;
            DrawAll;
          end;

        kcEnter:
          if FocusTOC and (TOCCount > 0) then
          begin
            ScrollToLine(TOC[TOCSel].LineIdx);
            FocusTOC := False;
            DrawAll;
          end;

        kcChar:
          if UpCase(K.Ch) = 'Q' then Exit;
      end;
    until False;

  finally
    Display.Free;
    RawLines.Free;
  end;
end;

end.
