{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.AsciiDocViewer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fgl,
  TermUI.StringUtils,
  TermUI.Terminal, TermUI.Menu, TermUI.Forms, TermUI.Application;

{ ══════════════════════════════════════════════════════════════════════
  Display line types (public so TDisplayLineList generic can be used as field)
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
    constructor Create(AKind: TDisplayLineKind; const AText: String);
  end;

  TDisplayLineList = specialize TFPGObjectList<TDisplayLine>;

  TTOCEntry = record
    Heading: string;
    LineIdx: Integer;
  end;

  TTOCList = array of TTOCEntry;

{ ══════════════════════════════════════════════════════════════════════
  TAsciiDocViewer — full-screen AsciiDoc viewer with TOC + content pane
  ══════════════════════════════════════════════════════════════════════ }

  TAsciiDocViewer = class(TForm)
  private
    FTitle:      string;
    FRawLines:   TStringList;
    FDisplay:    TDisplayLineList;
    FTOC:        TTOCList;
    FTOCCount:   Integer;
    FContentW:   Integer;
    FContentX:   Integer;
    FTOCSel:     Integer;
    FTOCScroll:  Integer;
    FDispScroll: Integer;
    FFocusTOC:   Boolean;

    function  ContentRows: Integer;
    procedure TOCEnsureVisible;
    procedure ScrollToLine(LineIdx: Integer);
    procedure Rebuild;
    procedure DrawTOCRow(ATOCIdx, ARow: Integer);
    procedure DrawSeparator;
    procedure DrawContentRow(ADispIdx, ARow: Integer);
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
  public
    constructor Create(const ATitle: string = ''); override;
    destructor  Destroy; override;

    { Load content from ARawLines (caller retains ownership).
      ATitle appears in the header. AContextKey scrolls to a matching TOC entry. }
    procedure SetContent(ARawLines: TStringList; const ATitle: string;
      const AContextKey: string = '');
  end;

implementation

{ ══════════════════════════════════════════════════════════════════════
  TDisplayLine
  ══════════════════════════════════════════════════════════════════════ }

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
    AText := Trim(CopyNeutral(S, I, MaxInt))
  else
    ALevel := 0;
end;

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
    Words.Delimiter       := ' ';
    Words.StrictDelimiter := True;
    Words.DelimitedText   := AText;
    Line := '';
    for I := 0 to Words.Count - 1 do
    begin
      W := Words[I];
      if W = '' then Continue;
      if Line = '' then
      begin
        if UTF8VisualLen(W) > AWidth then W := CopyNeutral(W, 0, AWidth);
        Line := W;
      end
      else if UTF8VisualLen(Line) + 1 + UTF8VisualLen(W) > AWidth then
      begin
        AList.Add(TDisplayLine.Create(AKind, Line));
        if UTF8VisualLen(W) > AWidth then W := CopyNeutral(W, 0, AWidth);
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

procedure BuildDisplayLines(ARaw: TStringList; AContentWidth: Integer;
  ADisplay: TDisplayLineList; var ATOC: TTOCList; out ATOCCount: Integer);
var
  I, Level: Integer;
  S, Txt:   string;
  InCode:   Boolean;
  InTable:  Boolean;

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

var
  ParaBuf: string;

  procedure FlushPara;
  begin
    if ParaBuf <> '' then
    begin
      AppendWrapped(ParaBuf, AContentWidth, dlkPara, ADisplay);
      ParaBuf := '';
    end;
  end;

begin
  ATOCCount := 0;
  SetLength(ATOC, 16);
  InCode  := False;
  InTable := False;
  ParaBuf := '';

  for I := 0 to ARaw.Count - 1 do
  begin
    S := ARaw[I];

    if S = '----' then
    begin
      FlushPara;
      InCode := not InCode;
      Push(dlkRule);
      Continue;
    end;

    if InCode then
    begin
      Push(dlkCode, S);
      Continue;
    end;

    if (S.Length > 0) and (S.Chars[0] = '[') then Continue;
    if S = '|===' then begin InTable := not InTable; Continue; end;
    if InTable then Continue;
    if CopyNeutral(S, 0, 2) = '//' then Continue;

    if Trim(S) = '' then
    begin
      FlushPara;
      if (ADisplay.Count > 0) and (ADisplay[ADisplay.Count - 1].Kind <> dlkBlank) then
        Push(dlkBlank);
      Continue;
    end;

    if ParseHeadingLine(S, Level, Txt) then
    begin
      FlushPara;
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
      FlushPara;
      Push(dlkRule);
      Continue;
    end;

    if (Length(S) >= 2) and (S.Chars[0].Index[0] in ['*', '-']) and (S.Chars[1].Index[0] = ' ') then
    begin
      FlushPara;
      AppendWrapped(CopyNeutral(S, 2, MaxInt), AContentWidth - 2, dlkBullet, ADisplay);
      Continue;
    end;

    if (Length(S) >= 2) and (S.Chars[0].Index[0] = '.') and (S.Chars[1].Index[0] = ' ') then
    begin
      FlushPara;
      AppendWrapped(CopyNeutral(S, 2, MaxInt), AContentWidth - 2, dlkBullet, ADisplay);
      Continue;
    end;

    if (Length(S) > 0) and (S.Chars[0].Index[0] = '|') then
    begin
      FlushPara;
      Push(dlkPara, CopyNeutral(S, 1, MaxInt));
      Continue;
    end;

    if ParaBuf = '' then
      ParaBuf := S
    else
      ParaBuf := ParaBuf + ' ' + Trim(S);
  end;
  FlushPara;
end;

{ ══════════════════════════════════════════════════════════════════════
  Inline markup renderer
  ══════════════════════════════════════════════════════════════════════ }

procedure RenderInline(const S: RawByteString; MaxCols: Integer);
var
  I, Col, SeqLen: Integer;
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
        Inc(I);
      end;
      '_': begin
        InItal := not InItal;
        Term.SetUnderline(InItal);
        Inc(I);
      end;
      '`', '+': begin
        InMono := not InMono;
        if InMono then Term.SetFG(clCyan)
        else Term.ResetColors;
        Inc(I);
      end;
      else begin
        SeqLen := UTF8SeqLen(S, I);
        Term.WriteStr(Copy(S, I, SeqLen));
        Inc(Col);
        Inc(I, SeqLen);
      end;
    end;
  end;
  Term.ResetColors;
  Term.SetUnderline(False);
end;

{ ══════════════════════════════════════════════════════════════════════
  TAsciiDocViewer
  ══════════════════════════════════════════════════════════════════════ }

const
  TOC_W     = 22;
  HELP_FOOT = ' ↑↓ Scroll   Tab/←→ Switch panel   Enter Jump   Esc Close ';

constructor TAsciiDocViewer.Create(const ATitle: String);
begin
  inherited Create(ATitle);
  FRawLines   := TStringList.Create;
  FDisplay    := TDisplayLineList.Create(True);
  FTOCCount   := 0;
  FTOCSel     := 0;
  FTOCScroll  := 0;
  FDispScroll := 0;
  FFocusTOC   := True;
  SetLength(FTOC, 16);
end;

destructor TAsciiDocViewer.Destroy;
begin
  FDisplay.Free;
  FRawLines.Free;
  inherited;
end;

procedure TAsciiDocViewer.SetContent(ARawLines: TStringList;
  const ATitle: String; const AContextKey: String);
var
  I: Integer;

  function FindContextTOC(const AKey: RawByteString): Integer;
  var J: Integer;
  begin
    Result := -1;
    if AKey = '' then Exit;
    for J := 0 to FTOCCount - 1 do
      if SameText(FTOC[J].Heading, AKey) then begin Result := J; Exit; end;
    for J := 0 to FTOCCount - 1 do
      if PosNeutral(LowerCase(AKey), LowerCase(FTOC[J].Heading)) then begin Result := J; Exit; end;
  end;

begin
  FTitle := ATitle;
  FRawLines.Assign(ARawLines);
  FContentX := TOC_W + 2;
  FContentW := Term.Width - FContentX + 1;
  if FContentW < 10 then FContentW := 10;
  Rebuild;
  if AContextKey <> '' then
  begin
    I := FindContextTOC(AContextKey);
    if I < 0 then I := 0;
    FTOCSel := I;
  end;
  if (FTOCSel >= 0) and (FTOCSel < FTOCCount) then
  begin
    ScrollToLine(FTOC[FTOCSel].LineIdx);
    TOCEnsureVisible;
  end;
  Invalidate;
end;

function TAsciiDocViewer.ContentRows: Integer;
begin
  Result := Term.Height - 4;
  if Result < 1 then Result := 1;
end;

procedure TAsciiDocViewer.TOCEnsureVisible;
var VR: Integer;
begin
  if FTOCCount = 0 then Exit;
  VR := ContentRows;
  if FTOCSel < FTOCScroll then FTOCScroll := FTOCSel
  else if FTOCSel >= FTOCScroll + VR then FTOCScroll := FTOCSel - VR + 1;
  if FTOCScroll < 0 then FTOCScroll := 0;
end;

procedure TAsciiDocViewer.ScrollToLine(LineIdx: Integer);
begin
  FDispScroll := LineIdx;
  if FDispScroll < 0 then FDispScroll := 0;
  if (FDisplay.Count > 0) and (FDispScroll >= FDisplay.Count) then
    FDispScroll := FDisplay.Count - 1;
end;

procedure TAsciiDocViewer.Rebuild;
begin
  FContentX := TOC_W + 2;
  FContentW := Term.Width - FContentX + 1;
  if FContentW < 10 then FContentW := 10;
  FDisplay.Clear;
  FTOCCount := 0;
  SetLength(FTOC, 16);
  BuildDisplayLines(FRawLines, FContentW, FDisplay, FTOC, FTOCCount);
  if (FTOCSel >= 0) and (FTOCSel < FTOCCount) then
    ScrollToLine(FTOC[FTOCSel].LineIdx);
  TOCEnsureVisible;
end;

procedure TAsciiDocViewer.DrawTOCRow(ATOCIdx, ARow: Integer);
var IsSel: Boolean; Txt: RawByteString;
begin
  Term.GotoXY(1, ARow); Term.ClearToEOL;
  if (ATOCIdx < 0) or (ATOCIdx >= FTOCCount) then Exit;
  IsSel := (ATOCIdx = FTOCSel);
  Txt := FTOC[ATOCIdx].Heading;
  if Length(Txt) > TOC_W - 3 then Txt := CopyNeutral(Txt, 0, TOC_W - 4) + '>';
  if IsSel then
  begin
    if FFocusTOC then begin Term.SetFG(clBlack); Term.SetBG(clCyan); end
    else Term.SetFG(clCyan);
    Term.WriteStr(' > ' + Txt);
  end
  else
  begin
    Term.SetFG(clBrightBlack);
    Term.WriteStr('   ' + Txt);
  end;
  Term.ResetColors;
end;

procedure TAsciiDocViewer.DrawSeparator;
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

procedure TAsciiDocViewer.DrawContentRow(ADispIdx, ARow: Integer);
var DL: TDisplayLine; W: Integer;
begin
  Term.GotoXY(FContentX, ARow);
  W := FContentW;
  Term.ResetColors;
  Term.WriteStr(StringOfChar(' ', W));
  Term.GotoXY(FContentX, ARow);
  if (ADispIdx < 0) or (ADispIdx >= FDisplay.Count) then Exit;
  DL := FDisplay[ADispIdx];
  case DL.Kind of
    dlkBlank: ;
    dlkRule:   begin Term.SetFG(clBrightBlack);  Term.WriteStr(StringOfChar('-', W)); Term.ResetColors; end;
    dlkH1:     begin Term.SetFG(clBrightCyan);   Term.WriteStr(CopyNeutral(DL.Text, 0, W)); Term.ResetColors; end;
    dlkH2:     begin Term.SetFG(clBrightYellow); Term.SetUnderline(True); Term.WriteStr(CopyNeutral(DL.Text, 0, W)); Term.SetUnderline(False); Term.ResetColors; end;
    dlkH3:     begin Term.SetFG(clBrightGreen);  Term.WriteStr(CopyNeutral(DL.Text, 0, W)); Term.ResetColors; end;
    dlkH4:     begin Term.SetFG(clGreen);        Term.WriteStr(CopyNeutral(DL.Text, 0, W)); Term.ResetColors; end;
    dlkCode:   begin Term.SetFG(clBrightBlack);  Term.WriteStr(CopyNeutral(DL.Text, 0, W)); Term.ResetColors; end;
    dlkBullet: begin
      Term.SetFG(clBrightYellow); Term.WriteStr('• '); Term.ResetColors;
      RenderInline(CopyNeutral(DL.Text, 0, W - 2), W - 2);
    end;
    dlkPara: RenderInline(CopyNeutral(DL.Text, 0, W), W);
  end;
end;

procedure TAsciiDocViewer.DoPaint;
var R: Integer;
begin
  Term.ClearScreen;
  DrawHeader('Help: ' + FTitle, 1);
  DrawSeparator;
  for R := 0 to ContentRows - 1 do DrawTOCRow(FTOCScroll + R, 3 + R);
  for R := 0 to ContentRows - 1 do DrawContentRow(FDispScroll + R, 3 + R);
  DrawRule(Term.Height - 1, 1, Term.Width);
  Term.GotoXY(1, Term.Height); Term.ClearToEOL;
  Term.SetFG(clBrightBlack); Term.WriteStr(HELP_FOOT); Term.ResetColors;
  inherited DoPaint;
end;

function TAsciiDocViewer.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  Result := True;
  case Key.Code of
    kcEscape, kcF1: Close(1);

    kcTab, kcLeft, kcRight:
    begin
      FFocusTOC := not FFocusTOC;
      Invalidate;
    end;

    kcUp:
      if FFocusTOC then
      begin
        if FTOCSel > 0 then begin Dec(FTOCSel); TOCEnsureVisible; ScrollToLine(FTOC[FTOCSel].LineIdx); Invalidate; end;
      end
      else if FDispScroll > 0 then begin Dec(FDispScroll); Invalidate; end;

    kcDown:
      if FFocusTOC then
      begin
        if FTOCSel < FTOCCount - 1 then begin Inc(FTOCSel); TOCEnsureVisible; ScrollToLine(FTOC[FTOCSel].LineIdx); Invalidate; end;
      end
      else if FDispScroll < FDisplay.Count - 1 then begin Inc(FDispScroll); Invalidate; end;

    kcPageUp:
      if FFocusTOC then
      begin
        Dec(FTOCSel, ContentRows); if FTOCSel < 0 then FTOCSel := 0;
        TOCEnsureVisible; if FTOCCount > 0 then ScrollToLine(FTOC[FTOCSel].LineIdx); Invalidate;
      end
      else begin Dec(FDispScroll, ContentRows); if FDispScroll < 0 then FDispScroll := 0; Invalidate; end;

    kcPageDown:
      if FFocusTOC then
      begin
        Inc(FTOCSel, ContentRows);
        if FTOCSel >= FTOCCount then FTOCSel := FTOCCount - 1;
        if FTOCSel < 0 then FTOCSel := 0;
        TOCEnsureVisible; if FTOCCount > 0 then ScrollToLine(FTOC[FTOCSel].LineIdx); Invalidate;
      end
      else begin
        Inc(FDispScroll, ContentRows);
        if FDispScroll >= FDisplay.Count then FDispScroll := FDisplay.Count - 1;
        if FDispScroll < 0 then FDispScroll := 0;
        Invalidate;
      end;

    kcHome:
      if FFocusTOC then
      begin
        FTOCSel := 0; TOCEnsureVisible;
        if FTOCCount > 0 then ScrollToLine(FTOC[0].LineIdx); Invalidate;
      end
      else begin FDispScroll := 0; Invalidate; end;

    kcEnd:
      if FFocusTOC then
      begin
        if FTOCCount > 0 then FTOCSel := FTOCCount - 1;
        TOCEnsureVisible; if FTOCCount > 0 then ScrollToLine(FTOC[FTOCSel].LineIdx); Invalidate;
      end
      else begin
        FDispScroll := FDisplay.Count - 1;
        if FDispScroll < 0 then FDispScroll := 0;
        Invalidate;
      end;

    kcEnter:
      if FFocusTOC and (FTOCCount > 0) then
      begin
        ScrollToLine(FTOC[FTOCSel].LineIdx); FFocusTOC := False; Invalidate;
      end;

    kcChar:
      if (Key.Ch = 'Q') or (Key.Ch = 'q') then Close(1)
      else Result := False;

    else
      Result := False;
  end;
end;

end.
