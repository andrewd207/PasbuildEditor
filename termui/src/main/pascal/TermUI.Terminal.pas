{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Terminal;

{$mode objfpc}{$H+}

interface

type
  TKeyCode = (
    kcNone,
    { Plain arrows }
    kcUp, kcDown, kcLeft, kcRight,
    { Shift+arrows }
    kcShiftUp, kcShiftDown, kcShiftLeft, kcShiftRight,
    { Alt+arrows }
    kcAltUp, kcAltDown, kcAltLeft, kcAltRight,
    { Ctrl+arrows }
    kcCtrlUp, kcCtrlDown, kcCtrlLeft, kcCtrlRight,
    { Navigation cluster }
    kcHome, kcEnd, kcPageUp, kcPageDown, kcInsert,
    kcCtrlHome, kcCtrlEnd,
    { Editing }
    kcEnter, kcEscape, kcBackspace, kcDelete,
    { Tab }
    kcTab, kcShiftTab, kcCtrlTab,
    { Printable character — Key.Ch holds the char }
    kcChar,
    { Ctrl+letter.  Ctrl+H/I/J/M/[ are already kcBackspace/kcTab/kcEnter/kcEscape. }
    kcCtrlA, kcCtrlB, kcCtrlC, kcCtrlD, kcCtrlE, kcCtrlF, kcCtrlG,
    kcCtrlK, kcCtrlL,
    kcCtrlN, kcCtrlO, kcCtrlP, kcCtrlQ, kcCtrlR,
    kcCtrlS, kcCtrlT, kcCtrlU, kcCtrlV, kcCtrlW,
    kcCtrlX, kcCtrlY, kcCtrlZ,
    { Function keys F1–F14 }
    kcF1, kcF2, kcF3, kcF4, kcF5, kcF6, kcF7,
    kcF8, kcF9, kcF10, kcF11, kcF12, kcF13, kcF14,
    { Alt + printable character — Key.Ch holds the character.
      On Unix: decoded from ESC + printable byte (xterm Alt encoding).
      On Windows: decoded from VK with LEFT_ALT_PRESSED / RIGHT_ALT_PRESSED. }
    kcAltChar,
    { Alt+F1 }
    kcAltF1
  );

  TKeyEvent = record
    Code: TKeyCode;
    Ch:   Char;
  end;

  TColor = (
    clDefault,
    clBlack,       clRed,           clGreen,       clYellow,
    clBlue,        clMagenta,       clCyan,        clWhite,
    clBrightBlack, clBrightRed,     clBrightGreen, clBrightYellow,
    clBrightBlue,  clBrightMagenta, clBrightCyan,  clBrightWhite,
    { Concrete stand-in for the terminal background color (black).
      Use this instead of clDefault when you need a legible inversion —
      clDefault swapped with clDefault is still clDefault. }
    clBackground
  );

  { Named drawing characters used by controls and borders.
    TApplication.DrawChar / .DrawingChar[] provide the actual glyph based on
    the UseUnicodeBorders setting and any per-char override. }
  TDrawingChar = (
    { Box corners }
    dcTopLeft,      { + / ┌ }  dcTopRight,     { + / ┐ }
    dcBottomLeft,   { + / └ }  dcBottomRight,  { + / ┘ }
    { Lines }
    dcHoriz,        { - / ─ }  dcVert,         { | / │ }
    { T-junctions }
    dcTeeLeft,      { + / ├ }  dcTeeRight,     { + / ┤ }
    dcTeeTop,       { + / ┬ }  dcTeeBottom,    { + / ┴ }
    dcCross,        { + / ┼ }
    { Scrollbar track elements }
    dcScrollUp,     { ^ / ▲ }  dcScrollDown,   { v / ▼ }
    dcScrollThumb,  { # / █ }  dcScrollTrack,  { | / │ }
    { Combo box }
    dcComboLeft,    { [ / [ }  dcComboRight,   { ] / ] }
    dcComboArrow,   { v / ▼ }
    { File/directory indicators }
    dcDirIndicator,  { > / ▶ }
    { Parent-directory / go-up entry.  Alternatives: ⬆ (U+2B06, bolder),
      ↩ (U+21A9, back-hook), ⇡ (U+21E1, dashed).  ASCII fallback: ^ }
    dcDirParent,     { ^ / ↑ }
    { Navigation arrows (breadcrumbs, pagination — distinct from scrollbar arrows) }
    dcArrowLeft,     { < / ← }  dcArrowRight,    { > / → }
    dcArrowUp,       { ^ / ↑ }  dcArrowDown,     { v / ↓ }
    { Tree / hierarchy view }
    dcTreeCollapsed, { + / ▶ }  dcTreeExpanded,  { - / ▼ }
    dcTreeLeaf,      {   /   }
    dcTreeVert,      { | / │ }  dcTreeBranch,    { + / ├ }  dcTreeLast, { \ / └ }
    { List / selection markers }
    dcBullet,        { * / • }
    dcSelectedMark,  { > / ► }
    dcCheckOff,      { - / ☐ }  dcCheckOn,       { x / ☑ }
    dcRadioOff,      { ( ) / ○ }  dcRadioOn,     { (*) / ● }
    { Text overflow }
    dcEllipsis,      { ~ / … }
    { Progress bar }
    dcProgressFull,  { # / █ }  dcProgressEmpty, { . / ░ }
    { Misc UI chrome }
    dcClose,         { x / × }
    dcMenuIcon,      { = / ☰ }
    dcSeparator      { | / │ }
  );

  { Each buffer cell holds one Unicode codepoint as a UTF-8 sequence (1-4 bytes). }
  TScreenCell = record
    Ch:        string[4];
    FG, BG:    TColor;
    Underline: Boolean;
  end;

  TScreenBuffer = array of TScreenCell;

  TTerminal = class
  private
    FUseColor: Boolean;

    { Double buffer — back is what we're drawing into, front is what the
      terminal currently shows.  Flushed by FlushOutput. }
    FBack:     TScreenBuffer;
    FFront:    TScreenBuffer;
    FBufW:     Integer;
    FBufH:     Integer;

    { Current drawing state (pen) for back-buffer writes }
    FCurX:       Integer;   // 1-based column
    FCurY:       Integer;   // 1-based row
    FCurFG:      TColor;
    FCurBG:      TColor;
    FCurUL:      Boolean;
    FCursorWant:    Boolean;   // desired visibility; emitted once by FlushOutput
    FCursorX:       Integer;   // desired cursor display position (set by PlaceCursor)
    FCursorY:       Integer;
    FDirtyRowHint:  Integer;   // -1 = full flush; >=1 = only this screen row changed

    procedure AllocBuffers(W, H: Integer);
    procedure BlankBuffer(var Buf: TScreenBuffer);
    function  CellIndex(X, Y: Integer): Integer; inline;

  protected
    procedure InitColor;
    { Subclasses call this to emit bytes directly to stdout (bypasses buffer). }
    procedure RawWrite(const S: string);

  public
    function Width: Integer; virtual; abstract;
    function Height: Integer; virtual; abstract;
    function IsTTY: Boolean; virtual;
    function UseColor: Boolean;

    procedure EnableRawMode; virtual; abstract;
    procedure DisableRawMode; virtual; abstract;

    function HasResized: Boolean; virtual;

    function ReadKey: TKeyEvent; virtual; abstract;
    { Non-blocking variant: returns False on timeout, True + filled AKey on keypress. }
    function ReadKeyTimeout(out AKey: TKeyEvent; TimeoutMs: Integer): Boolean; virtual; abstract;

    { Buffer-aware drawing — these write into the back buffer. }
    procedure WriteStr(const S: string); virtual;
    procedure GotoXY(X, Y: Integer); virtual;
    procedure ClearScreen; virtual;
    procedure ClearToEOL; virtual;
    procedure SetFG(C: TColor); virtual;
    procedure SetBG(C: TColor); virtual;
    procedure ResetColors; virtual;
    procedure SetUnderline(AOn: Boolean); virtual;

    { Diff back vs front and emit only changed cells, then swap. }
    procedure FlushOutput; virtual;

    { Diff only one screen row (1-based) and emit changes for that row only.
      Does not require InvalidateFront — FFront is trusted for all other rows. }
    procedure FlushRow(Y: Integer);

    { Mark the entire front buffer as dirty so the next FlushOutput redraws
      every cell. Call this before overlaying ephemeral messages on top of a
      screen that was partially updated by an inline editor. }
    procedure InvalidateFront;

    { Signal that only one screen row (1-based) changed this frame.
      Application.RepaintActive reads this and calls FlushRow instead of
      FlushOutput, avoiding full-screen cursor sweep. Pass -1 to clear. }
    procedure HintDirtyRow(ARow: Integer);
    function  TakeDirtyRowHint: Integer;

    { Set where the visible terminal cursor should appear after FlushOutput.
      Separate from GotoXY (the drawing pen) so that subsequent paint calls
      do not silently move the cursor away from the edit point. }
    procedure PlaceCursor(X, Y: Integer); virtual;

    { Cursor visibility.
      ShowCursor / HideCursor record intent; FlushOutput emits the actual
      ESC sequence once at the end of the frame so overlays cannot
      accidentally override the editor's cursor.
      Override CommitCursorVisibility for platform-specific non-ANSI paths
      (e.g. Win32 SetConsoleCursorInfo). }
    procedure HideCursor; virtual;
    procedure ShowCursor; virtual;
    procedure CommitCursorVisibility(AWant: Boolean); virtual;

    procedure EnterAltScreen; virtual;
    procedure ExitAltScreen; virtual;
  end;

type
  TTerminalFactory = function: TTerminal;

procedure RegisterTerminalFactory(AFactory: TTerminalFactory);
function Term: TTerminal;

implementation

{ Pull in the platform back-end so its initialization section fires and calls
  RegisterTerminalFactory automatically.  The conditional matches the source
  paths declared in project.xml, so exactly one platform unit is compiled. }
uses
  SysUtils, TermUI.StringUtils,
  {$IF defined(WINDOWS) or defined(UNIX)}
  TermUI.Terminal.Platform
  {$ENDIF}
  ;

{ ── ANSI code tables (same as before, now used only during flush) ── }

const
  FGCode: array[TColor] of Integer = (
    39, 30, 31, 32, 33, 34, 35, 36, 37,
    90, 91, 92, 93, 94, 95, 96, 97,
    30  { clBackground — black foreground }
  );
  BGCode: array[TColor] of Integer = (
    49, 40, 41, 42, 43, 44, 45, 46, 47,
    100, 101, 102, 103, 104, 105, 106, 107,
    40  { clBackground — black background }
  );

var
  GTerm:    TTerminal        = nil;
  GFactory: TTerminalFactory = nil;

{ ── Buffer helpers ── }

procedure TTerminal.AllocBuffers(W, H: Integer);
begin
  FBufW := W;
  FBufH := H;
  SetLength(FBack,  W * H);
  SetLength(FFront, W * H);
  BlankBuffer(FBack);
  InvalidateFront;  { mark every front cell dirty so the first flush redraws all }
end;

procedure TTerminal.BlankBuffer(var Buf: TScreenBuffer);
var I: Integer;
begin
  for I := 0 to High(Buf) do
  begin
    Buf[I].Ch        := ' ';
    Buf[I].FG        := clDefault;
    Buf[I].BG        := clDefault;
    Buf[I].Underline := False;
  end;
end;

function TTerminal.CellIndex(X, Y: Integer): Integer;
begin
  Result := (Y - 1) * FBufW + (X - 1);
end;

{ ── Base class boilerplate ── }

function TTerminal.IsTTY: Boolean;
begin
  Result := False;
end;

procedure TTerminal.InitColor;
var W, H: Integer;
begin
  FUseColor := IsTTY;
  FCurX  := 1; FCurY  := 1;
  FCursorX := 1; FCursorY := 1;
  FCurFG := clDefault; FCurBG := clDefault; FCurUL := False;
  FDirtyRowHint := -1;
  W := Width; H := Height;
  if W <= 0 then W := 80;
  if H <= 0 then H := 24;
  AllocBuffers(W, H);
end;

function TTerminal.UseColor: Boolean;
begin
  Result := FUseColor;
end;

function TTerminal.HasResized: Boolean;
begin
  Result := False;
end;

procedure TTerminal.RawWrite(const S: string);
begin
  System.Write(S);
end;

{ ── Buffer-aware drawing methods ── }

procedure TTerminal.GotoXY(X, Y: Integer);
begin
  FCurX := X;
  FCurY := Y;
end;

procedure TTerminal.SetFG(C: TColor);
begin
  FCurFG := C;
end;

procedure TTerminal.SetBG(C: TColor);
begin
  FCurBG := C;
end;

procedure TTerminal.ResetColors;
begin
  FCurFG := clDefault;
  FCurBG := clDefault;
  FCurUL := False;
end;

procedure TTerminal.SetUnderline(AOn: Boolean);
begin
  FCurUL := AOn;
end;

procedure TTerminal.WriteStr(const S: string);
var
  I, Idx, SeqLen: Integer;
  C: string;
begin
  I := 1;
  while I <= Length(S) do
  begin
    SeqLen := UTF8SeqLen(S, I);
    C := Copy(S, I, SeqLen);
    Inc(I, SeqLen);
    if C = #10 then begin Inc(FCurY); FCurX := 1; Continue; end;
    if C = #13 then begin FCurX := 1;             Continue; end;
    if (FCurX >= 1) and (FCurX <= FBufW) and
       (FCurY >= 1) and (FCurY <= FBufH) then
    begin
      Idx := CellIndex(FCurX, FCurY);
      FBack[Idx].Ch        := C;
      FBack[Idx].FG        := FCurFG;
      FBack[Idx].BG        := FCurBG;
      FBack[Idx].Underline := FCurUL;
    end;
    Inc(FCurX);  { one visual column per codepoint }
  end;
end;

procedure TTerminal.ClearScreen;
begin
  { Reallocate if terminal was resized }
  if (Width <> FBufW) or (Height <> FBufH) then
    AllocBuffers(Width, Height);
  BlankBuffer(FBack);
  FCurX := 1; FCurY := 1;
end;

procedure TTerminal.ClearToEOL;
var X, Idx: Integer;
begin
  for X := FCurX to FBufW do
  begin
    Idx := CellIndex(X, FCurY);
    FBack[Idx].Ch        := ' ';
    FBack[Idx].FG        := FCurFG;
    FBack[Idx].BG        := FCurBG;
    FBack[Idx].Underline := FCurUL;
  end;
end;

procedure TTerminal.InvalidateFront;
var I: Integer;
begin
  { Use #0 as sentinel — differs from every valid painted cell (spaces at minimum) }
  for I := 0 to High(FFront) do
    FFront[I].Ch := #0;
  { Reset cursor intent — each frame's paint decides fresh. }
  FCursorWant := False;
  FCursorX    := 1;
  FCursorY    := 1;
end;

{ ── Flush: diff and emit ── }

procedure TTerminal.FlushOutput;
var
  W, H:    Integer;
  X, Y:    Integer;
  Idx:     Integer;
  B, F:    TScreenCell;
  LastX:   Integer;
  LastY:          Integer;
  LastFG:         TColor;
  LastBG:         TColor;
  LastUL:         Boolean;
  Buf:            string;
  RowHadEmit:     Boolean;
  RowHadMultiByte: Boolean;

  procedure Emit(const S: string); inline;
  begin
    Buf := Buf + S;
  end;

begin
  W := Width;
  H := Height;

  { Grow buffers if terminal was resized between ClearScreen and Flush }
  if (W <> FBufW) or (H <> FBufH) then
    AllocBuffers(W, H);

  LastX  := -1; LastY  := -1;
  LastFG := clDefault; LastBG := clDefault; LastUL := False;
  { Hide cursor immediately so it does not flicker across the screen during
    the diff pass.  Restored to FCursorWant at the very end. }
  Buf    := #27'[?25l';
  CommitCursorVisibility(False);

  for Y := 1 to H do
  begin
    RowHadEmit     := False;
    RowHadMultiByte := False;

    for X := 1 to W do
    begin
      Idx := CellIndex(X, Y);
      B := FBack[Idx];
      F := FFront[Idx];

      if (B.Ch = F.Ch) and (B.FG = F.FG) and (B.BG = F.BG) and
         (B.Underline = F.Underline) then
        Continue;

      { Position cursor if needed }
      if (X <> LastX) or (Y <> LastY) then
      begin
        Emit(#27'[' + IntToStr(Y) + ';' + IntToStr(X) + 'f');
        LastX := X; LastY := Y;
      end;

      { Color / attribute changes }
      if FUseColor then
      begin
        if (B.FG <> LastFG) or (B.BG <> LastBG) or (B.Underline <> LastUL) then
        begin
          Emit(#27'[');
          Emit(IntToStr(FGCode[B.FG]));
          Emit(';');
          Emit(IntToStr(BGCode[B.BG]));
          if B.Underline then Emit(';4') else Emit(';24');
          Emit('m');
          LastFG := B.FG; LastBG := B.BG; LastUL := B.Underline;
        end;
      end;

      Emit(B.Ch);
      Inc(LastX);
      RowHadEmit := True;
      if (Length(B.Ch) > 0) and (Ord(B.Ch[1]) > $7F) then RowHadMultiByte := True;

      FFront[Idx] := B;
    end;

    { Multi-byte UTF-8 chars cause the terminal's visual cursor to lag behind
      our cell-grid LastX.  Trailing spaces that should clear the right edge of
      the row end up at wrong visual columns.  \e[K erases from the actual
      terminal cursor position to end of line, covering any uncovered cells. }
    if RowHadEmit and RowHadMultiByte then
      Emit(#27'[K');
  end;

  { Reposition the terminal cursor to the requested display position, not the
    drawing pen — they diverge whenever painting continues after PlaceCursor. }
  if FUseColor then Buf := Buf + #27'[0m';
  Buf := Buf + #27'[' + IntToStr(FCursorY) + ';' + IntToStr(FCursorX) + 'f';
  { Emit cursor visibility once, after all painting, so overlays cannot
    accidentally hide the cursor that a lower control requested. }
  if FCursorWant then Buf := Buf + #27'[?25h'
  else                 Buf := Buf + #27'[?25l';
  if Buf <> '' then
    RawWrite(Buf);
  Flush(Output);
  CommitCursorVisibility(FCursorWant);
end;

procedure TTerminal.FlushRow(Y: Integer);
var
  X, Idx:  Integer;
  B, F:    TScreenCell;
  LastX:   Integer;
  LastFG:  TColor;
  LastBG:  TColor;
  LastUL:  Boolean;
  Buf:     string;
begin
  if (Y < 1) or (Y > FBufH) then Exit;
  Buf    := #27'[?25l';
  CommitCursorVisibility(False);
  LastX  := -1;
  LastFG := clDefault; LastBG := clDefault; LastUL := False;
  for X := 1 to FBufW do
  begin
    Idx := CellIndex(X, Y);
    B := FBack[Idx];
    F := FFront[Idx];
    if (B.Ch = F.Ch) and (B.FG = F.FG) and (B.BG = F.BG) and
       (B.Underline = F.Underline) then
      Continue;
    if X <> LastX then
    begin
      Buf := Buf + #27'[' + IntToStr(Y) + ';' + IntToStr(X) + 'f';
      LastX := X;
    end;
    if FUseColor then
    begin
      if (B.FG <> LastFG) or (B.BG <> LastBG) or (B.Underline <> LastUL) then
      begin
        Buf := Buf + #27'[' + IntToStr(FGCode[B.FG]) + ';' + IntToStr(BGCode[B.BG]);
        if B.Underline then Buf := Buf + ';4' else Buf := Buf + ';24';
        Buf := Buf + 'm';
        LastFG := B.FG; LastBG := B.BG; LastUL := B.Underline;
      end;
    end;
    Buf   := Buf + B.Ch;
    Inc(LastX);
    FFront[Idx] := B;
  end;
  if FUseColor then Buf := Buf + #27'[0m';
  Buf := Buf + #27'[' + IntToStr(FCursorY) + ';' + IntToStr(FCursorX) + 'f';
  if FCursorWant then Buf := Buf + #27'[?25h'
  else                 Buf := Buf + #27'[?25l';
  RawWrite(Buf);
  Flush(Output);
  CommitCursorVisibility(FCursorWant);
end;

procedure TTerminal.HintDirtyRow(ARow: Integer);
begin
  FDirtyRowHint := ARow;
end;

function TTerminal.TakeDirtyRowHint: Integer;
begin
  Result := FDirtyRowHint;
  FDirtyRowHint := -1;
end;

procedure TTerminal.PlaceCursor(X, Y: Integer);
begin
  FCursorX := X;
  FCursorY := Y;
end;

procedure TTerminal.ShowCursor;
begin
  FCursorWant := True;
end;

procedure TTerminal.HideCursor;
begin
  FCursorWant := False;
end;

procedure TTerminal.CommitCursorVisibility(AWant: Boolean);
begin
  { Base: ANSI handled in FlushOutput's Buf.  Override for non-ANSI paths. }
end;

procedure TTerminal.EnterAltScreen;
begin
end;

procedure TTerminal.ExitAltScreen;
begin
end;

procedure RegisterTerminalFactory(AFactory: TTerminalFactory);
begin
  GFactory := AFactory;
end;

function Term: TTerminal;
begin
  if GTerm = nil then
  begin
    if not Assigned(GFactory) then
      raise Exception.Create('No terminal factory registered. ' +
        'Ensure the platform unit is in your uses clause.');
    GTerm := GFactory();
  end;
  Result := GTerm;
end;

finalization
  GTerm.Free;

end.
