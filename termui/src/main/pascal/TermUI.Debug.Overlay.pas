{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Debug.Overlay;

{$mode objfpc}{$H+}

{ Floating debug log overlay.

  Draws a panel along the right edge of the terminal, on top of everything
  else, without taking focus or participating in the form stack.

  Usage:
    DebugLog('something happened');          // always safe to call
    DebugOverlay.Toggle;                     // show/hide (or use F10)

  The overlay registers itself with Application.OnPostPaint so it is
  repainted at the end of every ProcessMessages cycle.  DebugLog also
  triggers an immediate repaint + flush so log calls during blocking
  operations (subprocess waits, etc.) appear instantly. }

interface

uses
  Math, Classes, SysUtils;

type
  TDebugOverlay = class
  private
    FLines:    TStringList;
    FVisible:  Boolean;
    FMaxLines: Integer;
    FWidth:    Integer;
    procedure PaintNow;
  public
    constructor Create(AMaxLines: Integer = 50; AWidth: Integer = 48);
    destructor Destroy; override;

    { Append a timestamped message.  Triggers an immediate repaint if visible. }
    procedure Log(const AMsg: string);
    procedure LogFmt(const AFmt: string; const AArgs: array of const);

    procedure Toggle;
    procedure Show;
    procedure Hide;

    { Hook for Application.OnPostPaint — called after every form-stack repaint. }
    procedure AfterPaint(Sender: TObject);

    property Visible:  Boolean read FVisible;
    property MaxLines: Integer read FMaxLines;
    property Width:    Integer read FWidth;
  end;

{ Global instance — created automatically when this unit is in uses. }
var
  DebugOverlay: TDebugOverlay;

{ Convenience wrappers that forward to DebugOverlay.Log/LogFmt. }
procedure DebugLog(const AMsg: string);
procedure DebugLogFmt(const AFmt: string; const AArgs: array of const);

implementation

uses
  TermUI.Terminal,
  TermUI.Application;

{ ── TDebugOverlay ── }

constructor TDebugOverlay.Create(AMaxLines: Integer; AWidth: Integer);
begin
  inherited Create;
  FLines    := TStringList.Create;
  FVisible  := False;
  FMaxLines := AMaxLines;
  FWidth    := AWidth;
end;

destructor TDebugOverlay.Destroy;
begin
  FLines.Free;
  inherited;
end;

procedure TDebugOverlay.Log(const AMsg: string);
var
  TimeStamp: string;
  Line:      string;
begin
  TimeStamp := FormatDateTime('hh:nn:ss', Now);
  Line      := TimeStamp + ' ' + AMsg;
  FLines.Add(Line);
  while FLines.Count > FMaxLines do
    FLines.Delete(0);
  if FVisible then
  begin
    PaintNow;
    Term.FlushOutput;
  end;
end;

procedure TDebugOverlay.LogFmt(const AFmt: string; const AArgs: array of const);
begin
  Log(Format(AFmt, AArgs));
end;

procedure TDebugOverlay.Toggle;
begin
  FVisible := not FVisible;
  if FVisible then
  begin
    PaintNow;
    Term.FlushOutput;
  end
  else
  begin
    { Force a full repaint of the underlying forms to erase us. }
    if Length(Application.FormStack) > 0 then
      Application.FormStack[High(Application.FormStack)].Invalidate;
  end;
end;

procedure TDebugOverlay.Show;
begin
  if not FVisible then Toggle;
end;

procedure TDebugOverlay.Hide;
begin
  if FVisible then Toggle;
end;

procedure TDebugOverlay.AfterPaint(Sender: TObject);
begin
  if FVisible then
    PaintNow;
end;

procedure TDebugOverlay.PaintNow;
var
  W, H:     Integer;
  PanelW:   Integer;
  PanelL:   Integer;
  InnerW:   Integer;
  I, Row:   Integer;
  LineIdx:  Integer;
  S:        string;
  MaxRows:  Integer;
begin
  W      := Term.Width;
  H      := Term.Height;
  PanelW := Min(FWidth, W);
  PanelL := W - PanelW + 1;
  InnerW := PanelW - 2;
  MaxRows := H - 2;  { rows available for log lines }

  { Background }
  Term.SetBG(clBlack);
  Term.SetFG(clGreen);
  for I := 1 to H do
  begin
    Term.GotoXY(PanelL, I);
    Term.WriteStr(StringOfChar(' ', PanelW));
  end;

  { Top border }
  Term.SetFG(clBrightGreen);
  Term.GotoXY(PanelL, 1);
  Term.WriteStr(Application.DrawingChar[dcTopLeft]);
  S := ' Debug ';
  Term.WriteStr(S);
  for I := Length(S) + 1 to InnerW do
    Term.WriteStr(Application.DrawingChar[dcHoriz]);
  Term.WriteStr(Application.DrawingChar[dcTopRight]);

  { Side borders }
  for I := 2 to H - 1 do
  begin
    Term.GotoXY(PanelL, I);
    Term.WriteStr(Application.DrawingChar[dcVert]);
    Term.GotoXY(PanelL + PanelW - 1, I);
    Term.WriteStr(Application.DrawingChar[dcVert]);
  end;

  { Bottom border }
  Term.GotoXY(PanelL, H);
  Term.WriteStr(Application.DrawingChar[dcBottomLeft]);
  for I := 1 to InnerW do
    Term.WriteStr(Application.DrawingChar[dcHoriz]);
  Term.WriteStr(Application.DrawingChar[dcBottomRight]);

  { Log lines — show the most recent ones that fit, newest at the bottom }
  Term.SetFG(clGreen);
  Term.SetBG(clBlack);
  Row := MaxRows;  { work upward from bottom }
  for LineIdx := FLines.Count - 1 downto 0 do
  begin
    if Row < 1 then Break;
    S := FLines[LineIdx];
    if Length(S) > InnerW then
      S := Copy(S, 1, InnerW);
    Term.GotoXY(PanelL + 1, Row + 1);  { +1 for top border row }
    Term.WriteStr(S);
    { Pad remainder of inner width }
    if Length(S) < InnerW then
      Term.WriteStr(StringOfChar(' ', InnerW - Length(S)));
    Dec(Row);
  end;

  Term.ResetColors;
end;

{ ── Global convenience ── }

procedure DebugLog(const AMsg: string);
begin
  DebugOverlay.Log(AMsg);
end;

procedure DebugLogFmt(const AFmt: string; const AArgs: array of const);
begin
  DebugOverlay.LogFmt(AFmt, AArgs);
end;

initialization
  DebugOverlay := TDebugOverlay.Create;
  Application.OnPostPaint := @DebugOverlay.AfterPaint;

finalization
  FreeAndNil(DebugOverlay);

end.
