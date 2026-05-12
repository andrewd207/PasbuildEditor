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
  BaseUnix, termio, SysUtils;

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
begin
  if not FRawMode then Exit;
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
  B, B2, B3, B4, B5, Bx: Byte;
begin
  Result.Code := kcNone;
  Result.Ch   := #0;

  if not ReadByte(B) then Exit;

  case B of
    3:  Result.Code := kcCtrlC;
    19: Result.Code := kcCtrlS;
    24: Result.Code := kcCtrlX;
    27: begin
      if not ReadByte(B2, 50) then
      begin
        Result.Code := kcEscape;
        Exit;
      end;
      if B2 = Ord('O') then
      begin
        if ReadByte(B3, 50) and (B3 = Ord('P')) then
          Result.Code := kcF1;
      end
      else if B2 = Ord('[') then
      begin
        if not ReadByte(B3, 50) then Exit;
        case B3 of
          Ord('A'): Result.Code := kcUp;
          Ord('B'): Result.Code := kcDown;
          Ord('C'): Result.Code := kcRight;
          Ord('D'): Result.Code := kcLeft;
          Ord('H'): Result.Code := kcHome;
          Ord('F'): Result.Code := kcEnd;
          Ord('5'): begin ReadByte(Bx, 50); Result.Code := kcPageUp; end;
          Ord('6'): begin ReadByte(Bx, 50); Result.Code := kcPageDown; end;
          Ord('3'): begin ReadByte(Bx, 50); Result.Code := kcDelete; end;
          Ord('1'): begin
            { ESC [ 1 ; 5 C  = Ctrl+Right,  ESC [ 1 ; 5 D = Ctrl+Left }
            if ReadByte(B4, 50) and (B4 = Ord(';')) and
               ReadByte(B5, 50) and (B5 = Ord('5')) and
               ReadByte(Bx, 50) then
            begin
              if Bx = Ord('C') then Result.Code := kcCtrlRight
              else if Bx = Ord('D') then Result.Code := kcCtrlLeft;
            end;
          end;
          Ord('['): begin
            if ReadByte(B4, 50) and (B4 = Ord('A')) then
              Result.Code := kcF1;
          end;
        end;
      end
      else
        Result.Code := kcEscape;
    end;
    13, 10: Result.Code := kcEnter;
    127, 8: Result.Code := kcBackspace;
    9:      Result.Code := kcTab;
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
