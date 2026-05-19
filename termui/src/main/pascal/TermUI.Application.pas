{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Application;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, TermUI.Terminal, TermUI.Control, TermUI.Forms, TermUI.Clipboard;

type
  { Called by ShowExceptionMessage.  Return True to continue, False to terminate. }
  TExceptionShowFunc = function(E: Exception): Boolean;

type
  { The application event loop. There is one global instance: Application.

    Typical usage:
      Application.PushForm(MyMainForm);
      Application.Run;

    Modal sub-page:
      Result := Application.ShowModal(MyDialog);
      // ShowModal spins ProcessMessages until MyDialog.Close is called.

    App-level key handling:
      Application.OnKeyDown := @HandleGlobalKey;
      // HandleGlobalKey receives keys not consumed by the active form or its children. }
  TFormArray = array of TForm;

  TApplication = class
  private
    FTerminated:       Boolean;
    FFormStack:        TFormArray;
    FOnKeyDown:        TKeyDownEvent;
    FOnIdle:           TNotifyEvent;
    FOnPostPaint:      TNotifyEvent;
    FHelpKey:          TKeyCode;
    FUseUnicodeBorders:  Boolean;
    FDrawingChars:       array[TDrawingChar] of string;
    FOnShowException:    TExceptionShowFunc;
    function  GetActiveForm: TForm;
    function  AnyInvalidated: Boolean;
    procedure DispatchKey(var Key: TKeyEvent);
    procedure RepaintActive;
    procedure HandleResize;
    procedure InitDrawingChars;
    function  GetDrawingChar(ABc: TDrawingChar): string;
    procedure SetDrawingChar(ABc: TDrawingChar; const AValue: string);
    procedure SetUseUnicodeBorders(AValue: Boolean);
  public
    destructor Destroy; override;

    { Main event loop — returns when Terminate is called. }
    procedure Run;

    { Process one cycle of input + repaint. Non-blocking if no key is waiting
      (16 ms timeout). Call this in a modal sub-loop:
        while AForm.ModalResult = 0 do Application.ProcessMessages; }
    procedure ProcessMessages;

    procedure Terminate;
    { Clear the terminated flag — call to resume after a cancelled quit. }
    procedure Resume;

    { Push/pop the active form. The top of the stack is the active form. }
    procedure PushForm(AForm: TForm);
    procedure PopForm;
    { Wipe the form stack without freeing forms — call before showing the crash
      dialog so dangling freed pointers don't get repainted. }
    procedure ClearFormStack;

    { Push AForm, spin ProcessMessages until AForm.ModalResult <> 0, pop and return
      the ModalResult. The caller owns AForm. }
    function  ShowModal(AForm: TForm): Integer;

    { Peek management — any TForm with Overlay = True can be used as a peek.
      ShowPeek pushes if not already visible; HidePeek removes from anywhere
      in the stack; TogglePeek does one or the other.  The caller owns AForm. }
    procedure ShowPeek(AForm: TForm);
    procedure HidePeek(AForm: TForm);
    procedure TogglePeek(AForm: TForm);
    function  PeekVisible(AForm: TForm): Boolean;

    property Terminated: Boolean       read FTerminated;
    property ActiveForm: TForm         read GetActiveForm;
    property OnKeyDown:  TKeyDownEvent read FOnKeyDown  write FOnKeyDown;
    { Fired each ProcessMessages cycle when there is no pending input. }
    property OnIdle:     TNotifyEvent  read FOnIdle     write FOnIdle;
    { Fired after the form stack has been repainted.  Use to draw overlays that
      must appear above all forms without being in the form stack. }
    property OnPostPaint: TNotifyEvent read FOnPostPaint write FOnPostPaint;
    { Read-only view of the form stack — for overlays that need to invalidate
      the top form when hiding themselves. }
    property FormStack: TFormArray read FFormStack;
    { Key that triggers the help propagation chain. Defaults to kcF1.
      Set to kcNone to disable the built-in help key entirely. }
    property HelpKey:    TKeyCode      read FHelpKey    write FHelpKey;

    { When True (default), border and widget glyphs use Unicode box-drawing
      characters.  When False, safe ASCII fallbacks are used.  Changing this
      property resets all chars to the new defaults; per-char overrides are lost. }
    property UseUnicodeBorders: Boolean
      read FUseUnicodeBorders write SetUseUnicodeBorders;

    { Read or override a single drawing character.  The array is indexed by
      TDrawingChar.  Writing replaces the default for that slot only.
        Application.DrawingChar[dcTopLeft] := '╔'; }
    property DrawingChar[ABc: TDrawingChar]: string
      read GetDrawingChar write SetDrawingChar;

    { Write the glyph for ABc to the terminal at the current cursor position. }
    procedure DrawChar(ABc: TDrawingChar);

    { Return a string of ACount repetitions of the glyph for ABc.
      Useful for drawing horizontal or vertical lines in one WriteStr call. }
    function  RepeatChar(ABc: TDrawingChar; ACount: Integer): string;

    { Show an exception dialog.  Calls OnShowException if set; if the handler
      returns False (or none is registered) the application is terminated.
      Must be called from inside an except block so frame info is still live. }
    procedure ShowExceptionMessage(E: Exception);

    { Set this to override the default crash dialog.  The function receives the
      active exception and returns True to continue or False to terminate.
      TermUI.Form.CrashHandler sets this automatically when included in uses. }
    property OnShowException: TExceptionShowFunc
      read FOnShowException write FOnShowException;
  end;

var
  Application: TApplication;

implementation

uses
  {$IF defined(WINDOWS) or defined(UNIX)}
  TermUI.Clipboard.Platform
  {$ENDIF}
  ;

function TApplication.GetActiveForm: TForm;
var N: Integer;
begin
  N := Length(FFormStack);
  if N > 0 then
    Result := FFormStack[N - 1]
  else
    Result := nil;
end;

procedure TApplication.DispatchKey(var Key: TKeyEvent);
var
  AF: TForm;
begin
  AF := GetActiveForm;
  if Assigned(AF) then
  begin
    if (FHelpKey <> kcNone) and (Key.Code = FHelpKey) then
      if AF.Help then Exit;
    if AF.KeyDown(Key) then Exit;
  end;
  if Assigned(FOnKeyDown) then
    FOnKeyDown(Self, Key);
end;

function TApplication.AnyInvalidated: Boolean;
var I, J: Integer; F: TForm;
begin
  for I := 0 to High(FFormStack) do
  begin
    F := FFormStack[I];
    if F.Invalidated then Exit(True);
    for J := 0 to F.ChildCount - 1 do
      if F.GetChild(J).Invalidated then Exit(True);
  end;
  Result := False;
end;

procedure TApplication.RepaintActive;
var
  N, First, I: Integer;
begin
  N := Length(FFormStack);
  if N = 0 then Exit;
  if not AnyInvalidated then Exit;
  { Walk down to find the topmost non-overlay; paint from there upward so all
    overlay layers appear on top of live content. }
  First := N - 1;
  while (First > 0) and FFormStack[First].Overlay do
    Dec(First);
  for I := First to N - 1 do
  begin
    FFormStack[I].Invalidate;
    FFormStack[I].Paint;
  end;
  if Assigned(FOnPostPaint) then
    FOnPostPaint(Self);
  Term.FlushOutput;
end;

procedure TApplication.HandleResize;
var
  I: Integer;
begin
  { Notify every form in the stack — overlays override SetBounds to
    recalculate from their Side+PeekSize rather than using the passed values. }
  for I := 0 to High(FFormStack) do
    FFormStack[I].SetBounds(1, 1, Term.Width, Term.Height);
  { Terminal may have cleared the screen on resize; force full redraw. }
  Term.InvalidateFront;
  if Length(FFormStack) > 0 then
    FFormStack[High(FFormStack)].Invalidate;
end;

destructor TApplication.Destroy;
begin
  SetLength(FFormStack, 0);
  inherited;
end;

procedure TApplication.PushForm(AForm: TForm);
var N: Integer;
begin
  N := Length(FFormStack);
  SetLength(FFormStack, N + 1);
  FFormStack[N] := AForm;
  AForm.Invalidate;
  if Assigned(AForm.OnActivate) then
    AForm.OnActivate(AForm);
end;

procedure TApplication.PopForm;
var
  N:  Integer;
  AF: TForm;
begin
  N := Length(FFormStack);
  if N = 0 then Exit;
  AF := FFormStack[N - 1];
  if Assigned(AF.OnDeactivate) then
    AF.OnDeactivate(AF);
  SetLength(FFormStack, N - 1);
  if N - 1 > 0 then
    FFormStack[N - 2].Invalidate;
end;

procedure TApplication.ProcessMessages;
var
  Key:    TKeyEvent;
  HadKey: Boolean;
begin
  if Term.HasResized then
    HandleResize;
  { Auto-pop any overlay that called Close from within its own key handler. }
  while (Length(FFormStack) > 0) and
        FFormStack[High(FFormStack)].Overlay and
        (FFormStack[High(FFormStack)].ModalResult <> 0) do
    PopForm;
  RepaintActive;
  CheckSynchronize;
  HadKey := Term.ReadKeyTimeout(Key, 16);
  if HadKey then
    DispatchKey(Key)
  else
  begin
    if Assigned(FOnIdle) then
      FOnIdle(Self);
  end;
end;

procedure TApplication.ClearFormStack;
begin
  SetLength(FFormStack, 0);
end;

procedure TApplication.Run;
begin
  FTerminated := False;
  while not FTerminated do
  begin
    try
      ProcessMessages;
    except
      on E: Exception do
      begin
        { Free any dangling form-stack pointers left by exception unwind
          through menu/page procedures, then show the crash dialog while
          the terminal is still in raw/alt-screen mode. }
        ClearFormStack;
        ShowExceptionMessage(E);
        if FTerminated then Break;
        { User chose Continue — loop resumes; OnIdle will re-enter the UI. }
      end;
    end;
  end;
end;

function TApplication.ShowModal(AForm: TForm): Integer;
begin
  AForm.ModalResult := 0;
  PushForm(AForm);
  try
    while (AForm.ModalResult = 0) and not FTerminated do
      ProcessMessages;
  finally
    PopForm;
  end;
  Result := AForm.ModalResult;
end;

function TApplication.PeekVisible(AForm: TForm): Boolean;
var I: Integer;
begin
  for I := 0 to High(FFormStack) do
    if FFormStack[I] = AForm then Exit(True);
  Result := False;
end;

procedure TApplication.ShowPeek(AForm: TForm);
begin
  if not PeekVisible(AForm) then
  begin
    AForm.ModalResult := 0;
    PushForm(AForm);
  end;
end;

procedure TApplication.HidePeek(AForm: TForm);
var
  N, I, J: Integer;
begin
  N := Length(FFormStack);
  for I := N - 1 downto 0 do
    if FFormStack[I] = AForm then
    begin
      if Assigned(AForm.OnDeactivate) then
        AForm.OnDeactivate(AForm);
      for J := I to N - 2 do
        FFormStack[J] := FFormStack[J + 1];
      SetLength(FFormStack, N - 1);
      if Length(FFormStack) > 0 then
        FFormStack[High(FFormStack)].Invalidate;
      Exit;
    end;
end;

procedure TApplication.TogglePeek(AForm: TForm);
begin
  if PeekVisible(AForm) then
    HidePeek(AForm)
  else
    ShowPeek(AForm);
end;

procedure TApplication.Terminate;
begin
  FTerminated := True;
end;

procedure TApplication.Resume;
begin
  FTerminated := False;
end;

procedure TApplication.InitDrawingChars;
begin
  if FUseUnicodeBorders then
  begin
    FDrawingChars[dcTopLeft]     := '┌';  FDrawingChars[dcTopRight]    := '┐';
    FDrawingChars[dcBottomLeft]  := '└';  FDrawingChars[dcBottomRight] := '┘';
    FDrawingChars[dcHoriz]       := '─';  FDrawingChars[dcVert]        := '│';
    FDrawingChars[dcTeeLeft]     := '├';  FDrawingChars[dcTeeRight]    := '┤';
    FDrawingChars[dcTeeTop]      := '┬';  FDrawingChars[dcTeeBottom]   := '┴';
    FDrawingChars[dcCross]       := '┼';
    FDrawingChars[dcScrollUp]    := '▲';  FDrawingChars[dcScrollDown]  := '▼';
    FDrawingChars[dcScrollThumb] := '█';  FDrawingChars[dcScrollTrack] := '│';
    FDrawingChars[dcComboLeft]      := '[';   FDrawingChars[dcComboRight]    := ']';
    FDrawingChars[dcComboArrow]     := '▼';
    FDrawingChars[dcDirIndicator]   := '❯';
    FDrawingChars[dcDirParent]      := '↑';
    FDrawingChars[dcArrowLeft]      := '←';   FDrawingChars[dcArrowRight]    := '→';
    FDrawingChars[dcArrowUp]        := '↑';   FDrawingChars[dcArrowDown]     := '↓';
    FDrawingChars[dcTreeCollapsed]  := '▶';   FDrawingChars[dcTreeExpanded]  := '▼';
    FDrawingChars[dcTreeLeaf]       := ' ';
    FDrawingChars[dcTreeVert]       := '│';   FDrawingChars[dcTreeBranch]    := '├';
    FDrawingChars[dcTreeLast]       := '└';
    FDrawingChars[dcBullet]         := '•';
    FDrawingChars[dcSelectedMark]   := '►';
    FDrawingChars[dcCheckOff]       := '☐';   FDrawingChars[dcCheckOn]       := '☑';
    FDrawingChars[dcRadioOff]       := '○';   FDrawingChars[dcRadioOn]       := '●';
    FDrawingChars[dcEllipsis]       := '…';
    FDrawingChars[dcProgressFull]   := '█';   FDrawingChars[dcProgressEmpty] := '░';
    FDrawingChars[dcClose]          := '×';
    FDrawingChars[dcMenuIcon]       := '☰';
    FDrawingChars[dcSeparator]      := '│';
  end
  else
  begin
    FDrawingChars[dcTopLeft]     := '+';  FDrawingChars[dcTopRight]    := '+';
    FDrawingChars[dcBottomLeft]  := '+';  FDrawingChars[dcBottomRight] := '+';
    FDrawingChars[dcHoriz]       := '-';  FDrawingChars[dcVert]        := '|';
    FDrawingChars[dcTeeLeft]     := '+';  FDrawingChars[dcTeeRight]    := '+';
    FDrawingChars[dcTeeTop]      := '+';  FDrawingChars[dcTeeBottom]   := '+';
    FDrawingChars[dcCross]       := '+';
    FDrawingChars[dcScrollUp]    := '^';  FDrawingChars[dcScrollDown]  := 'v';
    FDrawingChars[dcScrollThumb] := '#';  FDrawingChars[dcScrollTrack] := '|';
    FDrawingChars[dcComboLeft]      := '[';   FDrawingChars[dcComboRight]    := ']';
    FDrawingChars[dcComboArrow]     := 'v';
    FDrawingChars[dcDirIndicator]   := '>';
    FDrawingChars[dcDirParent]      := '^';
    FDrawingChars[dcArrowLeft]      := '<';   FDrawingChars[dcArrowRight]    := '>';
    FDrawingChars[dcArrowUp]        := '^';   FDrawingChars[dcArrowDown]     := 'v';
    FDrawingChars[dcTreeCollapsed]  := '+';   FDrawingChars[dcTreeExpanded]  := '-';
    FDrawingChars[dcTreeLeaf]       := ' ';
    FDrawingChars[dcTreeVert]       := '|';   FDrawingChars[dcTreeBranch]    := '+';
    FDrawingChars[dcTreeLast]       := '\';
    FDrawingChars[dcBullet]         := '*';
    FDrawingChars[dcSelectedMark]   := '>';
    FDrawingChars[dcCheckOff]       := '-';   FDrawingChars[dcCheckOn]       := 'x';
    FDrawingChars[dcRadioOff]       := 'o';   FDrawingChars[dcRadioOn]       := '*';
    FDrawingChars[dcEllipsis]       := '~';
    FDrawingChars[dcProgressFull]   := '#';   FDrawingChars[dcProgressEmpty] := '.';
    FDrawingChars[dcClose]          := 'x';
    FDrawingChars[dcMenuIcon]       := '=';
    FDrawingChars[dcSeparator]      := '|';
  end;
end;

procedure TApplication.SetUseUnicodeBorders(AValue: Boolean);
begin
  FUseUnicodeBorders := AValue;
  InitDrawingChars;
end;

function TApplication.GetDrawingChar(ABc: TDrawingChar): string;
begin
  Result := FDrawingChars[ABc];
end;

procedure TApplication.SetDrawingChar(ABc: TDrawingChar; const AValue: string);
begin
  FDrawingChars[ABc] := AValue;
end;

procedure TApplication.DrawChar(ABc: TDrawingChar);
begin
  Term.WriteStr(FDrawingChars[ABc]);
end;

function TApplication.RepeatChar(ABc: TDrawingChar; ACount: Integer): string;
var I: Integer;
begin
  Result := '';
  for I := 1 to ACount do
    Result := Result + FDrawingChars[ABc];
end;

procedure TApplication.ShowExceptionMessage(E: Exception);
var
  ShouldContinue: Boolean;
  SavedOnIdle:    TNotifyEvent;
begin
  { Suppress OnIdle while the crash dialog is visible so the dialog's
    ShowModal spin-loop cannot re-enter RunProjectUI through the idle hook. }
  SavedOnIdle := FOnIdle;
  FOnIdle     := nil;
  try
    if Assigned(FOnShowException) then
      ShouldContinue := FOnShowException(E)
    else
      ShouldContinue := False;
  finally
    FOnIdle := SavedOnIdle;
  end;
  if not ShouldContinue then
    Terminate;
end;

initialization
  Application := TApplication.Create;
  Application.HelpKey := kcF1;
  Application.UseUnicodeBorders := True;

finalization
  FreeAndNil(Application);

end.
