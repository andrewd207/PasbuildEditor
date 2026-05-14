{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Terminal.Platform;

{$mode objfpc}{$H+}

interface

uses TermUI.Terminal;

implementation

uses
  Windows, SysUtils, StrUtils;

{ ENABLE_VIRTUAL_TERMINAL_PROCESSING — not yet in older FPC Windows headers }
const
  ENABLE_VIRTUAL_TERMINAL_PROCESSING = $0004;

{ Windows console attribute bits for the colour fallback path }
const
  WinFGAttr: array[TColor] of Word = (
    0,                                                 // clDefault → reset to 0
    0,                                                 // clBlack
    FOREGROUND_RED,
    FOREGROUND_GREEN,
    FOREGROUND_RED or FOREGROUND_GREEN,                // clYellow
    FOREGROUND_BLUE,
    FOREGROUND_RED or FOREGROUND_BLUE,                 // clMagenta
    FOREGROUND_GREEN or FOREGROUND_BLUE,               // clCyan
    FOREGROUND_RED or FOREGROUND_GREEN or FOREGROUND_BLUE,  // clWhite
    FOREGROUND_INTENSITY,                              // clBrightBlack (dark grey)
    FOREGROUND_RED or FOREGROUND_INTENSITY,
    FOREGROUND_GREEN or FOREGROUND_INTENSITY,
    FOREGROUND_RED or FOREGROUND_GREEN or FOREGROUND_INTENSITY,
    FOREGROUND_BLUE or FOREGROUND_INTENSITY,
    FOREGROUND_RED or FOREGROUND_BLUE or FOREGROUND_INTENSITY,
    FOREGROUND_GREEN or FOREGROUND_BLUE or FOREGROUND_INTENSITY,
    FOREGROUND_RED or FOREGROUND_GREEN or FOREGROUND_BLUE or FOREGROUND_INTENSITY
  );
  WinBGAttr: array[TColor] of Word = (
    0,
    0,
    BACKGROUND_RED,
    BACKGROUND_GREEN,
    BACKGROUND_RED or BACKGROUND_GREEN,
    BACKGROUND_BLUE,
    BACKGROUND_RED or BACKGROUND_BLUE,
    BACKGROUND_GREEN or BACKGROUND_BLUE,
    BACKGROUND_RED or BACKGROUND_GREEN or BACKGROUND_BLUE,
    BACKGROUND_INTENSITY,
    BACKGROUND_RED or BACKGROUND_INTENSITY,
    BACKGROUND_GREEN or BACKGROUND_INTENSITY,
    BACKGROUND_RED or BACKGROUND_GREEN or BACKGROUND_INTENSITY,
    BACKGROUND_BLUE or BACKGROUND_INTENSITY,
    BACKGROUND_RED or BACKGROUND_BLUE or BACKGROUND_INTENSITY,
    BACKGROUND_GREEN or BACKGROUND_BLUE or BACKGROUND_INTENSITY,
    BACKGROUND_RED or BACKGROUND_GREEN or BACKGROUND_BLUE or BACKGROUND_INTENSITY
  );

{ ANSI FG/BG tables — used when virtual terminal processing is available }
const
  AnsiFGBase: array[TColor] of Integer = (
    39, 30, 31, 32, 33, 34, 35, 36, 37,
    90, 91, 92, 93, 94, 95, 96, 97
  );
  AnsiBGBase: array[TColor] of Integer = (
    49, 40, 41, 42, 43, 44, 45, 46, 47,
    100, 101, 102, 103, 104, 105, 106, 107
  );

type
  TWindowsTerminal = class(TTerminal)
  private
    FHOut:        THandle;
    FHIn:         THandle;
    FOldInMode:   DWORD;
    FOldOutMode:  DWORD;
    FAnsiMode:    Boolean;  // True when ENABLE_VIRTUAL_TERMINAL_PROCESSING succeeded
    FRawMode:     Boolean;
    FCurFG:       TColor;
    FCurBG:       TColor;
    FResizeFlag:  Boolean;

    procedure ApplyConsoleAttr;
  public
    constructor Create;
    destructor Destroy; override;

    function Width: Integer; override;
    function Height: Integer; override;
    function IsTTY: Boolean; override;
    function HasResized: Boolean; override;

    procedure EnableRawMode; override;
    procedure DisableRawMode; override;
    function ReadKey: TKeyEvent; override;

    procedure GotoXY(X, Y: Integer); override;
    procedure ClearScreen; override;
    procedure ClearToEOL; override;
    procedure SetFG(C: TColor); override;
    procedure SetBG(C: TColor); override;
    procedure ResetColors; override;
    procedure HideCursor; override;
    procedure ShowCursor; override;
    procedure SetUnderline(AOn: Boolean); override;
    procedure EnterAltScreen; override;
    procedure ExitAltScreen; override;
  end;

{ ---- TWindowsTerminal ---- }

constructor TWindowsTerminal.Create;
var
  OutMode: DWORD;
begin
  inherited Create;
  FHOut := GetStdHandle(STD_OUTPUT_HANDLE);
  FHIn  := GetStdHandle(STD_INPUT_HANDLE);
  FRawMode     := False;
  FAnsiMode    := False;
  FCurFG       := clDefault;
  FCurBG       := clDefault;
  FResizeFlag  := False;

  { Try to enable ANSI / VT processing on the output handle }
  GetConsoleMode(FHOut, OutMode);
  FOldOutMode := OutMode;
  if SetConsoleMode(FHOut, OutMode or ENABLE_VIRTUAL_TERMINAL_PROCESSING) then
    FAnsiMode := True;

  GetConsoleMode(FHIn, FOldInMode);

  InitColor;
end;

destructor TWindowsTerminal.Destroy;
begin
  if FRawMode then DisableRawMode;
  { Restore output mode in case we changed it }
  SetConsoleMode(FHOut, FOldOutMode);
  inherited;
end;

function TWindowsTerminal.IsTTY: Boolean;
var
  Mode: DWORD;
begin
  Result := GetConsoleMode(FHOut, Mode);
end;

function TWindowsTerminal.HasResized: Boolean;
begin
  Result := FResizeFlag;
  FResizeFlag := False;
end;

function TWindowsTerminal.Width: Integer;
var
  Info: CONSOLE_SCREEN_BUFFER_INFO;
begin
  Result := 80;
  if GetConsoleScreenBufferInfo(FHOut, Info) then
    Result := Info.srWindow.Right - Info.srWindow.Left + 1;
end;

function TWindowsTerminal.Height: Integer;
var
  Info: CONSOLE_SCREEN_BUFFER_INFO;
begin
  Result := 24;
  if GetConsoleScreenBufferInfo(FHOut, Info) then
    Result := Info.srWindow.Bottom - Info.srWindow.Top + 1;
end;

procedure TWindowsTerminal.EnableRawMode;
var
  Mode: DWORD;
begin
  GetConsoleMode(FHIn, Mode);
  FOldInMode := Mode;
  Mode := Mode and not (ENABLE_LINE_INPUT or ENABLE_ECHO_INPUT or ENABLE_PROCESSED_INPUT);
  Mode := Mode or ENABLE_VIRTUAL_TERMINAL_INPUT or ENABLE_WINDOW_INPUT;
  SetConsoleMode(FHIn, Mode);
  FRawMode := True;
end;

procedure TWindowsTerminal.DisableRawMode;
begin
  if not FRawMode then Exit;
  SetConsoleMode(FHIn, FOldInMode);
  FRawMode := False;
end;

function TWindowsTerminal.ReadKey: TKeyEvent;
var
  Rec:    INPUT_RECORD;
  Count:  DWORD;
  KE:     KEY_EVENT_RECORD absolute Rec.Event;
  Ctrl:   Boolean;
  Shift:  Boolean;
  Alt:    Boolean;
begin
  Result.Code := kcNone;
  Result.Ch   := #0;
  repeat
    ReadConsoleInput(FHIn, Rec, 1, Count);
    if Count = 0 then Continue;
    if Rec.EventType = WINDOW_BUFFER_SIZE_EVENT then
    begin
      FResizeFlag := True;
      Continue;
    end;
    if (Rec.EventType <> KEY_EVENT) or not KE.bKeyDown then
      Continue;

    Ctrl  := (KE.dwControlKeyState and (LEFT_CTRL_PRESSED  or RIGHT_CTRL_PRESSED))  <> 0;
    Shift := (KE.dwControlKeyState and SHIFT_PRESSED) <> 0;
    Alt   := (KE.dwControlKeyState and (LEFT_ALT_PRESSED or RIGHT_ALT_PRESSED)) <> 0;

    case KE.wVirtualKeyCode of
      VK_UP:    if Ctrl then Result.Code := kcCtrlUp
                else if Shift then Result.Code := kcShiftUp
                else if Alt   then Result.Code := kcAltUp
                else               Result.Code := kcUp;
      VK_DOWN:  if Ctrl then Result.Code := kcCtrlDown
                else if Shift then Result.Code := kcShiftDown
                else if Alt   then Result.Code := kcAltDown
                else               Result.Code := kcDown;
      VK_LEFT:  if Ctrl then Result.Code := kcCtrlLeft
                else if Shift then Result.Code := kcShiftLeft
                else if Alt   then Result.Code := kcAltLeft
                else               Result.Code := kcLeft;
      VK_RIGHT: if Ctrl then Result.Code := kcCtrlRight
                else if Shift then Result.Code := kcShiftRight
                else if Alt   then Result.Code := kcAltRight
                else               Result.Code := kcRight;
      VK_HOME:  if Ctrl then Result.Code := kcCtrlHome else Result.Code := kcHome;
      VK_END:   if Ctrl then Result.Code := kcCtrlEnd  else Result.Code := kcEnd;
      VK_RETURN:  Result.Code := kcEnter;
      VK_ESCAPE:  Result.Code := kcEscape;
      VK_BACK:    Result.Code := kcBackspace;
      VK_DELETE:  Result.Code := kcDelete;
      VK_INSERT:  Result.Code := kcInsert;
      VK_PRIOR:   Result.Code := kcPageUp;
      VK_NEXT:    Result.Code := kcPageDown;
      VK_TAB:     if Shift then Result.Code := kcShiftTab else Result.Code := kcTab;
      VK_F1:  Result.Code := kcF1;
      VK_F2:  Result.Code := kcF2;
      VK_F3:  Result.Code := kcF3;
      VK_F4:  Result.Code := kcF4;
      VK_F5:  Result.Code := kcF5;
      VK_F6:  Result.Code := kcF6;
      VK_F7:  Result.Code := kcF7;
      VK_F8:  Result.Code := kcF8;
      VK_F9:  Result.Code := kcF9;
      VK_F10: Result.Code := kcF10;
      VK_F11: Result.Code := kcF11;
      VK_F12: Result.Code := kcF12;
      VK_F13: Result.Code := kcF13;
      VK_F14: Result.Code := kcF14;
      else begin
        { Map Ctrl+letter via the ASCII control char value }
        case KE.AsciiChar of
          #1:  Result.Code := kcCtrlA;
          #2:  Result.Code := kcCtrlB;
          #3:  Result.Code := kcCtrlC;
          #4:  Result.Code := kcCtrlD;
          #5:  Result.Code := kcCtrlE;
          #6:  Result.Code := kcCtrlF;
          #7:  Result.Code := kcCtrlG;
          #11: Result.Code := kcCtrlK;
          #12: Result.Code := kcCtrlL;
          #14: Result.Code := kcCtrlN;
          #15: Result.Code := kcCtrlO;
          #16: Result.Code := kcCtrlP;
          #17: Result.Code := kcCtrlQ;
          #18: Result.Code := kcCtrlR;
          #19: Result.Code := kcCtrlS;
          #20: Result.Code := kcCtrlT;
          #21: Result.Code := kcCtrlU;
          #22: Result.Code := kcCtrlV;
          #23: Result.Code := kcCtrlW;
          #24: Result.Code := kcCtrlX;
          #25: Result.Code := kcCtrlY;
          #26: Result.Code := kcCtrlZ;
          #0: ;  { modifier-only keydown with no character — ignore }
          else begin
            Result.Code := kcChar;
            Result.Ch   := KE.AsciiChar;
          end;
        end;
      end;
    end;
  until Result.Code <> kcNone;
end;

procedure TWindowsTerminal.GotoXY(X, Y: Integer);
var
  Coord: COORD;
  Info:  CONSOLE_SCREEN_BUFFER_INFO;
begin
  if FAnsiMode then
  begin
    WriteStr(#27'[' + IntToStr(Y) + ';' + IntToStr(X) + 'f');
  end
  else
  begin
    GetConsoleScreenBufferInfo(FHOut, Info);
    Coord.X := Info.srWindow.Left + X - 1;
    Coord.Y := Info.srWindow.Top  + Y - 1;
    SetConsoleCursorPosition(FHOut, Coord);
  end;
end;

procedure TWindowsTerminal.ClearScreen;
var
  Info:    CONSOLE_SCREEN_BUFFER_INFO;
  Origin:  COORD;
  Written: DWORD;
  Cells:   DWORD;
begin
  if FAnsiMode then
  begin
    WriteStr(#27'[2J');
    GotoXY(1, 1);
  end
  else
  begin
    GetConsoleScreenBufferInfo(FHOut, Info);
    Origin.X := 0;
    Origin.Y := 0;
    Cells    := Info.dwSize.X * Info.dwSize.Y;
    FillConsoleOutputCharacter(FHOut, ' ', Cells, Origin, Written);
    FillConsoleOutputAttribute(FHOut, Info.wAttributes, Cells, Origin, Written);
    SetConsoleCursorPosition(FHOut, Origin);
  end;
end;

procedure TWindowsTerminal.ClearToEOL;
var
  Info:    CONSOLE_SCREEN_BUFFER_INFO;
  Written: DWORD;
  Len:     DWORD;
begin
  if FAnsiMode then
    WriteStr(#27'[K')
  else
  begin
    GetConsoleScreenBufferInfo(FHOut, Info);
    Len := Info.dwSize.X - Info.dwCursorPosition.X;
    FillConsoleOutputCharacter(FHOut, ' ', Len, Info.dwCursorPosition, Written);
    FillConsoleOutputAttribute(FHOut, Info.wAttributes, Len, Info.dwCursorPosition, Written);
  end;
end;

procedure TWindowsTerminal.ApplyConsoleAttr;
var
  Attr: Word;
begin
  if not UseColor then Exit;
  Attr := WinFGAttr[FCurFG] or WinBGAttr[FCurBG];
  if Attr = 0 then Attr := FOREGROUND_RED or FOREGROUND_GREEN or FOREGROUND_BLUE; // default white-on-black
  SetConsoleTextAttribute(FHOut, Attr);
end;

procedure TWindowsTerminal.SetFG(C: TColor);
begin
  if not UseColor then Exit;
  if FAnsiMode then
    WriteStr(#27'[' + IntToStr(AnsiFGBase[C]) + 'm')
  else
  begin
    FCurFG := C;
    ApplyConsoleAttr;
  end;
end;

procedure TWindowsTerminal.SetBG(C: TColor);
begin
  if not UseColor then Exit;
  if FAnsiMode then
    WriteStr(#27'[' + IntToStr(AnsiBGBase[C]) + 'm')
  else
  begin
    FCurBG := C;
    ApplyConsoleAttr;
  end;
end;

procedure TWindowsTerminal.ResetColors;
begin
  if not UseColor then Exit;
  if FAnsiMode then
    WriteStr(#27'[0m')
  else
  begin
    FCurFG := clDefault;
    FCurBG := clDefault;
    SetConsoleTextAttribute(FHOut, FOREGROUND_RED or FOREGROUND_GREEN or FOREGROUND_BLUE);
  end;
end;

procedure TWindowsTerminal.HideCursor;
var
  CI: CONSOLE_CURSOR_INFO;
begin
  if FAnsiMode then
    WriteStr(#27'[?25l')
  else
  begin
    GetConsoleCursorInfo(FHOut, CI);
    CI.bVisible := False;
    SetConsoleCursorInfo(FHOut, CI);
  end;
end;

procedure TWindowsTerminal.SetUnderline(AOn: Boolean);
begin
  { Only available in ANSI/VT mode; legacy console has no underline attribute }
  if FAnsiMode and UseColor then
    WriteStr(IfThen(AOn, #27'[4m', #27'[24m'));
end;

procedure TWindowsTerminal.ShowCursor;
var
  CI: CONSOLE_CURSOR_INFO;
begin
  if FAnsiMode then
    WriteStr(#27'[?25h')
  else
  begin
    GetConsoleCursorInfo(FHOut, CI);
    CI.bVisible := True;
    SetConsoleCursorInfo(FHOut, CI);
  end;
end;

procedure TWindowsTerminal.EnterAltScreen;
begin
  if FAnsiMode then
  begin
    WriteStr(#27'[?1049h');
    WriteStr(#27'[?7l');
    ClearScreen;
  end;
end;

procedure TWindowsTerminal.ExitAltScreen;
begin
  if FAnsiMode then
  begin
    WriteStr(#27'[?7h');
    WriteStr(#27'[?1049l');
  end;
end;

{ ---- factory ---- }

function CreateWindowsTerminal: TTerminal;
begin
  Result := TWindowsTerminal.Create;
end;

initialization
  RegisterTerminalFactory(@CreateWindowsTerminal);

end.
