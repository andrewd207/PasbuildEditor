{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Form.CrashHandler;

{$mode objfpc}{$H+}

{ Floating crash-report dialog.

  Call ShowCrashDialog(E) from inside an except block.  It collects the
  exception message and stack frames (via BacktraceStrFunc, which returns
  file/line info when the binary is compiled with -gl), displays them in a
  centered read-only editor, and asks the user whether to continue or quit.

  Returns True  → caller should continue (swallow the exception).
  Returns False → caller should terminate. }

interface

uses
  Math, SysUtils,
  TermUI.Terminal,
  TermUI.Forms,
  TermUI.Control.Editor;

type
  TCrashForm = class(TForm)
  private
    FEditor:    TTextEditor;
    FFooter:    string;
    FCrashText: string;
    FResult:    Boolean;   { True = continue, False = quit }
  protected
    procedure DoPaint; override;
    procedure ArrangeChildren; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
  public
    constructor Create(const AText: string); reintroduce;
    property ContinueChosen: Boolean read FResult;
  end;

{ Collect exception info + stack frames and show the crash dialog.
  Must be called from inside an except block so ExceptAddr/ExceptFrames are live.
  Returns True if the user chose to continue, False if they chose to quit. }
function ShowCrashDialog(E: Exception): Boolean;

implementation

uses
  Classes,
  TermUI.Application,
  TermUI.Clipboard,
  TermUI.StringUtils;

{ ── TCrashForm ── }

constructor TCrashForm.Create(const AText: string);
var
  W, H, L, T: Integer;
begin
  inherited Create('! Unhandled Exception');
  Overlay := True;
  FResult    := False;
  FCrashText := AText;
  FFooter    := '[C] Continue   [Q] Quit   [Ctrl+C] Copy to clipboard';

  { 2-cell margin on all sides }
  W := Term.Width  - 4;
  H := Term.Height - 4;
  L := 3;
  T := 3;
  SetBounds(L, T, W, H);

  FEditor            := TTextEditor.Create;
  FEditor.ReadOnly   := True;
  FEditor.WordWrap   := True;
  FEditor.Lines.Text := AText;
  AddChild(FEditor);
  ArrangeChildren;
end;

procedure TCrashForm.ArrangeChildren;
begin
  if not Assigned(FEditor) then Exit;
  { Inside the border: left+1, top+1 (title is in the border row), width-2,
    height-4 leaves room for footer at Height-2 and bottom border at Height }
  FEditor.SetBounds(Left + 1, Top + 1, Width - 2, Height - 4);
end;

procedure TCrashForm.DoPaint;
var
  X, Y, InnerW: Integer;
  TitleStr, FootStr: string;
begin
  InnerW := Width - 2;

  { Fill background }
  Term.SetBG(clBlack);
  Term.SetFG(clBrightRed);
  for Y := 1 to Height do
  begin
    GotoLocal(1, Y);
    for X := 1 to Width do
      Term.WriteStr(' ');
  end;

  { Top border + title }
  Term.SetFG(clBrightYellow);
  GotoLocal(1, 1);
  Term.WriteStr(Application.DrawingChar[dcTopLeft]);
  TitleStr := ' ' + Title + ' ';
  if Length(TitleStr) > InnerW then
    TitleStr := Copy(TitleStr, 1, InnerW - 1) + '~';
  Term.WriteStr(TitleStr);
  for X := Length(TitleStr) + 1 to InnerW do
    Term.WriteStr(Application.DrawingChar[dcHoriz]);
  Term.WriteStr(Application.DrawingChar[dcTopRight]);

  { Side borders }
  for Y := 2 to Height - 1 do
  begin
    GotoLocal(1, Y);
    Term.WriteStr(Application.DrawingChar[dcVert]);
    GotoLocal(Width, Y);
    Term.WriteStr(Application.DrawingChar[dcVert]);
  end;

  { Footer row (second to last row inside the border) }
  GotoLocal(2, Height - 2);
  Term.SetFG(clBrightWhite);
  for X := 1 to InnerW do Term.WriteStr(' ');
  GotoLocal(2, Height - 2);
  FootStr := FFooter;
  if Length(FootStr) > InnerW then
    FootStr := Copy(FootStr, 1, InnerW);
  Term.WriteStr(FootStr);

  { Bottom border }
  Term.SetFG(clBrightYellow);
  GotoLocal(1, Height);
  Term.WriteStr(Application.DrawingChar[dcBottomLeft]);
  for X := 1 to InnerW do
    Term.WriteStr(Application.DrawingChar[dcHoriz]);
  Term.WriteStr(Application.DrawingChar[dcBottomRight]);

  Term.ResetColors;
  inherited DoPaint;
end;

function TCrashForm.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  Result := False;
  if Key.Code = kcCtrlC then
  begin
    if Clipboard.HasPlatform then
      Clipboard.Text := FCrashText;
    Result := True;
    Exit;
  end;
  if Key.Code = kcChar then
    case UpCase(Key.Ch) of
      'C': begin FResult := True;  Close(1); Result := True; end;
      'Q': begin FResult := False; Close(2); Result := True; end;
    end;
  if Key.Code = kcEscape then
  begin
    FResult := False;
    Close(-1);
    Result := True;
  end;
  if not Result then
    Result := inherited DoKeyDown(Key);
end;

{ ── ShowCrashDialog ── }

function CollectCrashText(E: Exception): string;
var
  SB:     TStringList;
  Addr:   CodePointer;
  Frames: PCodePointer;
  Count:  LongInt;
  I:      Integer;
begin
  SB := TStringList.Create;
  try
    SB.Add('Exception class: ' + E.ClassName);
    SB.Add('Message: ' + E.Message);
    SB.Add('');
    SB.Add('Stack trace:');
    try
      Addr   := ExceptAddr;
      Count  := ExceptFrameCount;
      Frames := ExceptFrames;
      if Addr <> nil then
        SB.Add('  ' + BacktraceStrFunc(Addr))
      else
        SB.Add('  (no exception address)');
      for I := 0 to Count - 1 do
        SB.Add('  ' + BacktraceStrFunc(Frames[I]));
    except
      SB.Add('  (stack corrupted — could not read frames)');
    end;
    Result := SB.Text;
  finally
    SB.Free;
  end;
end;

function ShowCrashDialog(E: Exception): Boolean;
var
  Text: string;
  Form: TCrashForm;
begin
  { Collect frame info while still inside the except block }
  Text := CollectCrashText(E);

  Form := TCrashForm.Create(Text);
  try
    Application.ShowModal(Form);
    Result := Form.ContinueChosen;
  finally
    Form.Free;
  end;
end;

initialization
  Application.OnShowException := @ShowCrashDialog;

end.
