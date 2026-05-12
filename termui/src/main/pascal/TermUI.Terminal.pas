unit TermUI.Terminal;

{$mode objfpc}{$H+}

interface

type
  TKeyCode = (
    kcNone,
    kcUp, kcDown, kcLeft, kcRight,
    kcEnter, kcEscape, kcBackspace, kcDelete,
    kcHome, kcEnd, kcPageUp, kcPageDown, kcTab,
    kcChar,
    kcCtrlC,  // Ctrl+C
    kcCtrlS,  // Ctrl+S — save
    kcCtrlX,  // Ctrl+X — save and exit
    kcF1
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
    clBrightBlue,  clBrightMagenta, clBrightCyan,  clBrightWhite
  );

  TScreenCell = record
    Ch:        Char;
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
    FCurX:     Integer;   // 1-based column
    FCurY:     Integer;   // 1-based row
    FCurFG:    TColor;
    FCurBG:    TColor;
    FCurUL:    Boolean;

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

    { Mark the entire front buffer as dirty so the next FlushOutput redraws
      every cell. Call this before overlaying ephemeral messages on top of a
      screen that was partially updated by an inline editor. }
    procedure InvalidateFront;

    { Cursor visibility — go direct; cursor is not buffered. }
    procedure HideCursor; virtual; abstract;
    procedure ShowCursor; virtual; abstract;

    procedure EnterAltScreen; virtual;
    procedure ExitAltScreen; virtual;
  end;

type
  TTerminalFactory = function: TTerminal;

procedure RegisterTerminalFactory(AFactory: TTerminalFactory);
function Term: TTerminal;

implementation

uses SysUtils;

{ ── ANSI code tables (same as before, now used only during flush) ── }

const
  FGCode: array[TColor] of Integer = (
    39, 30, 31, 32, 33, 34, 35, 36, 37,
    90, 91, 92, 93, 94, 95, 96, 97
  );
  BGCode: array[TColor] of Integer = (
    49, 40, 41, 42, 43, 44, 45, 46, 47,
    100, 101, 102, 103, 104, 105, 106, 107
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
  BlankBuffer(FFront);
  { Mark front as all-invalid so first flush redraws everything }
  FillChar(FFront[0], Length(FFront) * SizeOf(TScreenCell), $FF);
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
begin
  FUseColor := IsTTY;
  FCurX  := 1; FCurY  := 1;
  FCurFG := clDefault; FCurBG := clDefault; FCurUL := False;
  AllocBuffers(80, 24);  { sensible default; resize on first flush }
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
  I, Idx: Integer;
  C: Char;
begin
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if C = #10 then
    begin
      Inc(FCurY);
      FCurX := 1;
      Continue;
    end;
    if C = #13 then
    begin
      FCurX := 1;
      Continue;
    end;
    if (FCurX >= 1) and (FCurX <= FBufW) and
       (FCurY >= 1) and (FCurY <= FBufH) then
    begin
      Idx := CellIndex(FCurX, FCurY);
      FBack[Idx].Ch        := C;
      FBack[Idx].FG        := FCurFG;
      FBack[Idx].BG        := FCurBG;
      FBack[Idx].Underline := FCurUL;
    end;
    Inc(FCurX);
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
begin
  FillChar(FFront[0], Length(FFront) * SizeOf(TScreenCell), $FF);
end;

{ ── Flush: diff and emit ── }

procedure TTerminal.FlushOutput;
var
  W, H:    Integer;
  X, Y:    Integer;
  Idx:     Integer;
  B, F:    TScreenCell;
  LastX:   Integer;
  LastY:   Integer;
  LastFG:  TColor;
  LastBG:  TColor;
  LastUL:  Boolean;
  Buf:     string;

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
  Buf    := '';

  for Y := 1 to H do
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

      FFront[Idx] := B;
    end;

  { Always reposition cursor to the logical pen position and reset attributes }
  if FUseColor then Buf := Buf + #27'[0m';
  Buf := Buf + #27'[' + IntToStr(FCurY) + ';' + IntToStr(FCurX) + 'f';
  if Buf <> '' then
    RawWrite(Buf);
  Flush(Output);
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
