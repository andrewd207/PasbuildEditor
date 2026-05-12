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
  Rec:   INPUT_RECORD;
  Count: DWORD;
  KE:    KEY_EVENT_RECORD absolute Rec.Event;
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
    case KE.wVirtualKeyCode of
      VK_UP:     Result.Code := kcUp;
      VK_DOWN:   Result.Code := kcDown;
      VK_LEFT:   Result.Code := kcLeft;
      VK_RIGHT:  Result.Code := kcRight;
      VK_RETURN: Result.Code := kcEnter;
      VK_ESCAPE: Result.Code := kcEscape;
      VK_BACK:   Result.Code := kcBackspace;
      VK_DELETE: Result.Code := kcDelete;
      VK_HOME:   Result.Code := kcHome;
      VK_END:    Result.Code := kcEnd;
      VK_PRIOR:  Result.Code := kcPageUp;
      VK_NEXT:   Result.Code := kcPageDown;
      VK_TAB:    Result.Code := kcTab;
      else begin
        if KE.AsciiChar = #3 then
          Result.Code := kcCtrlC
        else if KE.AsciiChar = #19 then
          Result.Code := kcCtrlS
        else if KE.AsciiChar = #24 then
          Result.Code := kcCtrlX
        else if KE.AsciiChar <> #0 then
        begin
          Result.Code := kcChar;
          Result.Ch   := KE.AsciiChar;
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
