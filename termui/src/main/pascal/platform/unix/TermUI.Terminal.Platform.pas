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
  BaseUnix, termio, SysUtils, StrUtils;

{$IF DEFINED(LINUX)}
const TIOCGWINSZ_VAL = $5413;
{$ELSEIF DEFINED(DARWIN) OR DEFINED(FREEBSD) OR DEFINED(NETBSD) OR DEFINED(OPENBSD)}
const TIOCGWINSZ_VAL = $40087468;
{$ELSE}
const TIOCGWINSZ_VAL = $5413;
{$ENDIF}

{ ---- Resize flag set by SIGWINCH ---- }

var
  GResizeFlag: cint = 0;

procedure SigWinchHandler({%H-}ASig: cint); cdecl;
begin
  GResizeFlag := 1;
end;

type
  TUnixTerminal = class(TTerminal)
  private
    FOldTermios:  Termios;
    FRawMode:     Boolean;
    FPeeked:      Boolean;
    FPeekedByte:  Byte;

    function ReadByte(out B: Byte; TimeoutMs: Integer = -1): Boolean;
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

    function ReadKeyTimeout(out AKey: TKeyEvent; TimeoutMs: Integer): Boolean; override;

    procedure HideCursor; override;
    procedure ShowCursor; override;
    procedure EnterAltScreen; override;
    procedure ExitAltScreen; override;
  end;

constructor TUnixTerminal.Create;
begin
  inherited Create;
  FRawMode    := False;
  FPeeked     := False;
  FPeekedByte := 0;
  fpSignal(SIGWINCH, @SigWinchHandler);
  InitColor;
end;

destructor TUnixTerminal.Destroy;
begin
  if FRawMode then DisableRawMode;
  inherited;
end;

function TUnixTerminal.IsTTY: Boolean;
begin
  Result := IsATTY(StdOut) <> 0;
end;

function TUnixTerminal.HasResized: Boolean;
begin
  Result := GResizeFlag <> 0;
  GResizeFlag := 0;
end;

function TUnixTerminal.Width: Integer;
var
  WS: TWinSize;
begin
  Result := 80;
  if fpIOCtl(StdOutputHandle, TIOCGWINSZ_VAL, @WS) = 0 then
    Result := WS.ws_col;
  if Result <= 0 then Result := 80;
end;

function TUnixTerminal.Height: Integer;
var
  WS: TWinSize;
begin
  Result := 24;
  if fpIOCtl(StdOutputHandle, TIOCGWINSZ_VAL, @WS) = 0 then
    Result := WS.ws_row;
  if Result <= 0 then Result := 24;
end;

procedure TUnixTerminal.EnableRawMode;
var
  Raw: Termios;
begin
  tcgetattr(StdInputHandle, FOldTermios);
  Raw := FOldTermios;
  Raw.c_lflag := Raw.c_lflag and not (ICANON or ECHO or ISIG);
  Raw.c_iflag := Raw.c_iflag and not IXON;
  Raw.c_cc[VMIN]  := 1;
  Raw.c_cc[VTIME] := 0;
  tcsetattr(StdInputHandle, TCSAFLUSH, Raw);
  FRawMode := True;
end;

procedure TUnixTerminal.DisableRawMode;
var
  Dummy: Byte;
begin
  if not FRawMode then Exit;
  { Drain any pending stdin bytes (e.g. trailing ESC sequence bytes that
    arrived after the 50 ms read timeout, or terminal responses to the
    ExitAltScreen/ShowCursor sequences) so they don't leak to the shell. }
  FPeeked := False;
  while ReadByte(Dummy, 0) do ;
  tcsetattr(StdInputHandle, TCSAFLUSH, FOldTermios);
  FRawMode := False;
end;

function TUnixTerminal.ReadByte(out B: Byte; TimeoutMs: Integer = -1): Boolean;
var
  FDS: TFDSet;
  TV:  TimeVal;
  PTV: PTimeVal;
  Res: cint;
begin
  if FPeeked then
  begin
    B := FPeekedByte;
    FPeeked := False;
    Result := True;
    Exit;
  end;
  Result := False;
  repeat
    fpFD_ZERO(FDS);
    fpFD_SET(StdInputHandle, FDS);
    if TimeoutMs < 0 then
      PTV := nil
    else
    begin
      TV.tv_sec  := TimeoutMs div 1000;
      TV.tv_usec := (TimeoutMs mod 1000) * 1000;
      PTV := @TV;
    end;
    Res := fpSelect(StdInputHandle + 1, @FDS, nil, nil, PTV);
    if Res > 0 then
    begin
      Result := fpRead(StdInputHandle, B, 1) = 1;
      Exit;
    end
    else if Res = 0 then
      Exit  // timeout
    else
    begin
      { Res < 0 — on EINTR (e.g. SIGWINCH) return False so the caller can
        check HasResized and redraw immediately rather than blocking again. }
      Exit;
    end;
  until False;
end;

function TUnixTerminal.ReadKey: TKeyEvent;
var
  B, B2: Byte;
  Params: string;
  Final:  Byte;
  P1, P2, P3: Integer;

  { Read CSI parameter bytes (digits, semicolons, and other non-final bytes)
    until a final byte: @, A–Z, a–z, or ~.  Returns the final in AFinal. }
  function ReadCSIParams(out AFinal: Byte): string;
  var Bn: Byte;
  begin
    Result := '';
    AFinal := 0;
    while ReadByte(Bn, 50) do
    begin
      if (Bn = Ord('~')) or
         ((Bn >= Ord('@')) and (Bn <= Ord('Z'))) or
         ((Bn >= Ord('a')) and (Bn <= Ord('z'))) then
      begin
        AFinal := Bn;
        Exit;
      end;
      Result := Result + Chr(Bn);
    end;
  end;

  { Parse 'N', 'N;M', or 'N;M;K' into AP1/AP2/AP3; missing parts default to 0. }
  procedure ParseParams(const S: string; out AP1, AP2: Integer); overload;
  var Sep: Integer;
  begin
    AP1 := 0; AP2 := 0;
    Sep := Pos(';', S);
    if Sep = 0 then
    begin
      if S <> '' then AP1 := StrToIntDef(S, 0);
    end
    else
    begin
      AP1 := StrToIntDef(Copy(S, 1, Sep - 1), 0);
      AP2 := StrToIntDef(Copy(S, Sep + 1, MaxInt), 0);
    end;
  end;

  procedure ParseParams(const S: string; out AP1, AP2, AP3: Integer); overload;
  var Sep1, Sep2: Integer;
  begin
    AP1 := 0; AP2 := 0; AP3 := 0;
    Sep1 := Pos(';', S);
    if Sep1 = 0 then begin AP1 := StrToIntDef(S, 0); Exit; end;
    AP1  := StrToIntDef(Copy(S, 1, Sep1 - 1), 0);
    Sep2 := PosEx(';', S, Sep1 + 1);
    if Sep2 = 0 then begin AP2 := StrToIntDef(Copy(S, Sep1 + 1, MaxInt), 0); Exit; end;
    AP2 := StrToIntDef(Copy(S, Sep1 + 1, Sep2 - Sep1 - 1), 0);
    AP3 := StrToIntDef(Copy(S, Sep2 + 1, MaxInt), 0);
  end;

  { Map a base directional key code with an xterm modifier number (P2).
    Modifier: 2=Shift, 3=Alt, 5=Ctrl; 0/1 = plain (returns ABase). }
  function ModKey(ABase: TKeyCode; AMod: Integer): TKeyCode;
  begin
    Result := ABase;
    case AMod of
      2: case ABase of
           kcUp:    Result := kcShiftUp;
           kcDown:  Result := kcShiftDown;
           kcLeft:  Result := kcShiftLeft;
           kcRight: Result := kcShiftRight;
         end;
      3: case ABase of
           kcUp:    Result := kcAltUp;
           kcDown:  Result := kcAltDown;
           kcLeft:  Result := kcAltLeft;
           kcRight: Result := kcAltRight;
         end;
      5: case ABase of
           kcUp:    Result := kcCtrlUp;
           kcDown:  Result := kcCtrlDown;
           kcLeft:  Result := kcCtrlLeft;
           kcRight: Result := kcCtrlRight;
           kcHome:  Result := kcCtrlHome;
           kcEnd:   Result := kcCtrlEnd;
         end;
    end;
  end;

begin
  Result.Code := kcNone;
  Result.Ch   := #0;

  if not ReadByte(B) then Exit;

  case B of
    1:   Result.Code := kcCtrlA;
    2:   Result.Code := kcCtrlB;
    3:   Result.Code := kcCtrlC;
    4:   Result.Code := kcCtrlD;
    5:   Result.Code := kcCtrlE;
    6:   Result.Code := kcCtrlF;
    7:   Result.Code := kcCtrlG;
    8:   Result.Code := kcBackspace;   { Ctrl+H }
    9:   Result.Code := kcTab;         { Ctrl+I }
    10:  Result.Code := kcEnter;       { Ctrl+J / LF }
    11:  Result.Code := kcCtrlK;
    12:  Result.Code := kcCtrlL;
    13:  Result.Code := kcEnter;       { Ctrl+M / CR }
    14:  Result.Code := kcCtrlN;
    15:  Result.Code := kcCtrlO;
    16:  Result.Code := kcCtrlP;
    17:  Result.Code := kcCtrlQ;
    18:  Result.Code := kcCtrlR;
    19:  Result.Code := kcCtrlS;
    20:  Result.Code := kcCtrlT;
    21:  Result.Code := kcCtrlU;
    22:  Result.Code := kcCtrlV;
    23:  Result.Code := kcCtrlW;
    24:  Result.Code := kcCtrlX;
    25:  Result.Code := kcCtrlY;
    26:  Result.Code := kcCtrlZ;
    27: begin
      if not ReadByte(B2, 50) then begin Result.Code := kcEscape; Exit; end;
      case B2 of
        Ord('O'): begin
          { SS3 sequences: ESC O P/Q/R/S = F1-F4; A/B/C/D/H/F = arrows/home/end }
          if ReadByte(B2, 50) then
            case B2 of
              Ord('P'): Result.Code := kcF1;
              Ord('Q'): Result.Code := kcF2;
              Ord('R'): Result.Code := kcF3;
              Ord('S'): Result.Code := kcF4;
              Ord('A'): Result.Code := kcUp;
              Ord('B'): Result.Code := kcDown;
              Ord('C'): Result.Code := kcRight;
              Ord('D'): Result.Code := kcLeft;
              Ord('H'): Result.Code := kcHome;
              Ord('F'): Result.Code := kcEnd;
            end;
        end;
        Ord('['): begin
          Params := ReadCSIParams(Final);
          if Final = 0 then Exit;
          ParseParams(Params, P1, P2);
          { modifyOtherKeys: ESC[27;<mod>;<key>~ — re-parse all three fields }
          if (Chr(Final) = '~') and (P1 = 27) then
          begin
            ParseParams(Params, P1, P2, P3);
            { P2=modifier (5=Ctrl, 2=Shift), P3=ASCII key code }
            if (P2 = 5) and (P3 = 9) then Result.Code := kcCtrlTab
            else if (P2 = 2) and (P3 = 9) then Result.Code := kcShiftTab;
            Exit;
          end;

          { Linux console F1–F5: ESC [ [ A–E (Params accumulates '[') }
          if (Params = '[') and (Final >= Ord('A')) and (Final <= Ord('E')) then
          begin
            Result.Code := TKeyCode(Ord(kcF1) + (Final - Ord('A')));
            Exit;
          end;

          case Chr(Final) of
            'A': Result.Code := ModKey(kcUp,    P2);
            'B': Result.Code := ModKey(kcDown,  P2);
            'C': Result.Code := ModKey(kcRight, P2);
            'D': Result.Code := ModKey(kcLeft,  P2);
            'H': Result.Code := ModKey(kcHome,  P2);
            'F': Result.Code := ModKey(kcEnd,   P2);
            'Z': Result.Code := kcShiftTab;
            { SS3 F-key letters when sent as CSI instead of SS3 }
            'P': Result.Code := kcF1;
            'Q': Result.Code := kcF2;
            'R': Result.Code := kcF3;
            'S': Result.Code := kcF4;
            '~': case P1 of
              1:  Result.Code := ModKey(kcHome, P2);
              2:  Result.Code := kcInsert;
              3:  Result.Code := kcDelete;
              4:  Result.Code := ModKey(kcEnd, P2);
              5:  Result.Code := kcPageUp;
              6:  Result.Code := kcPageDown;
              7:  Result.Code := kcHome;
              8:  Result.Code := kcEnd;
              11: Result.Code := kcF1;
              12: Result.Code := kcF2;
              13: Result.Code := kcF3;
              14: Result.Code := kcF4;
              15: Result.Code := kcF5;
              17: Result.Code := kcF6;
              18: Result.Code := kcF7;
              19: Result.Code := kcF8;
              20: Result.Code := kcF9;
              21: Result.Code := kcF10;
              23: Result.Code := kcF11;
              24: Result.Code := kcF12;
              25: Result.Code := kcF13;
              26: Result.Code := kcF14;
            end;
          end;
        end;
        else
          Result.Code := kcEscape;
      end;
    end;
    127: Result.Code := kcBackspace;
    else begin
      Result.Code := kcChar;
      Result.Ch   := Char(B);
    end;
  end;
end;

function TUnixTerminal.ReadKeyTimeout(out AKey: TKeyEvent; TimeoutMs: Integer): Boolean;
var B: Byte;
begin
  Result := ReadByte(B, TimeoutMs);
  if not Result then Exit;
  FPeeked     := True;
  FPeekedByte := B;
  AKey := ReadKey;
end;

procedure TUnixTerminal.HideCursor;
begin
  RawWrite(#27'[?25l');
end;

procedure TUnixTerminal.ShowCursor;
begin
  RawWrite(#27'[?25h');
end;

procedure TUnixTerminal.EnterAltScreen;
begin
  RawWrite(#27'[?1049h');  // switch to alternate buffer, save cursor
  RawWrite(#27'[?7l');     // disable line wrap
end;

procedure TUnixTerminal.ExitAltScreen;
begin
  RawWrite(#27'[?7h');     // re-enable line wrap
  RawWrite(#27'[?1049l'); // restore main buffer and cursor
end;

function CreateUnixTerminal: TTerminal;
begin
  Result := TUnixTerminal.Create;
end;

initialization
  RegisterTerminalFactory(@CreateUnixTerminal);

end.
