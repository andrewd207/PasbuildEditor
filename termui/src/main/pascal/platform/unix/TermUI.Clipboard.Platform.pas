{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Clipboard.Platform;

{$mode objfpc}{$H+}

interface

uses
  TermUI.Clipboard;

implementation

uses
  Classes, SysUtils, Math, Process, dynlibs, BaseUnix, Unix, SyncObjs;

{ ---- helpers ---- }

function EnvSet(const AName: string): Boolean;
begin
  Result := GetEnvironmentVariable(AName) <> '';
end;

function FindExecutable(const AName: string): Boolean;
var
  P: TProcess;
begin
  Result := False;
  P := TProcess.Create(nil);
  try
    P.Executable := '/usr/bin/which';
    P.Parameters.Add(AName);
    P.Options    := [poWaitOnExit, poNoConsole, poUsePipes];
    try
      P.Execute;
      Result := P.ExitStatus = 0;
    except
      Result := FileExists('/usr/bin/' + AName) or
                FileExists('/usr/local/bin/' + AName) or
                FileExists('/bin/' + AName);
    end;
  finally
    P.Free;
  end;
end;

{ ===========================================================================
  Wayland backend — uses wl-copy / wl-paste
  =========================================================================== }

type
  TWaylandClipboard = class(TClipboardPlatform)
  private
    FAvailable: Boolean;
  public
    constructor Create;
    function  Available: Boolean; override;
    procedure SetText(const AText: string); override;
    function  GetText: string; override;
  end;

constructor TWaylandClipboard.Create;
var
  HaveEnv, HaveCopy, HavePaste: Boolean;
begin
  inherited Create;
  HaveEnv    := EnvSet('WAYLAND_DISPLAY');
  HaveCopy   := HaveEnv and FindExecutable('wl-copy');
  HavePaste  := HaveEnv and FindExecutable('wl-paste');
  FAvailable := HaveEnv and HaveCopy and HavePaste;
end;

function TWaylandClipboard.Available: Boolean;
begin
  Result := FAvailable;
end;

procedure TWaylandClipboard.SetText(const AText: string);
var
  P:       TProcess;
  Data:    TBytes;
  Written: Integer;
  Chunk:   Integer;
begin
  P := TProcess.Create(nil);
  try
    P.Executable := 'wl-copy';
    P.Options    := [poUsePipes, poNoConsole];
    try
      P.Execute;
      Data := TEncoding.UTF8.GetBytes(AText);
      Written := 0;
      while Written < Length(Data) do
      begin
        Chunk := Length(Data) - Written;
        if Chunk > 4096 then Chunk := 4096;
        P.Input.Write(Data[Written], Chunk);
        Inc(Written, Chunk);
      end;
      P.CloseInput;
      { wl-copy stays running as a clipboard server — do not wait }
    except
    end;
  finally
    P.Free;
  end;
end;

function TWaylandClipboard.GetText: string;
var
  P:    TProcess;
  SS:   TStringStream;
  Buf:  array[0..4095] of Byte;
  N:    Integer;
begin
  Result := '';
  P  := TProcess.Create(nil);
  SS := TStringStream.Create('');
  try
    P.Executable := 'wl-paste';
    P.Parameters.Add('--no-newline');
    P.Options    := [poUsePipes, poNoConsole, poWaitOnExit];
    try
      P.Execute;
      repeat
        N := P.Output.NumBytesAvailable;
        if N <= 0 then Break;
        if N > SizeOf(Buf) then N := SizeOf(Buf);
        N := P.Output.Read(Buf, N);
        if N > 0 then SS.Write(Buf, N);
      until N = 0;
      if P.ExitStatus = 0 then
        Result := SS.DataString;
    except
    end;
  finally
    SS.Free;
    P.Free;
  end;
end;

{ ===========================================================================
  X11 backend — loaded via dlopen, no link-time dependency on libX11
  =========================================================================== }

{ ---- Minimal X11 types ---- }
type
  TXDisplay  = Pointer;
  TXWindow   = PtrUInt;
  TXAtom     = PtrUInt;
  TXTime     = PtrUInt;
  TXStatus   = cint;

const
  X_None          = TXAtom(0);
  CurrentTime     = TXTime(0);
  XA_ATOM         = TXAtom(4);
  SelectionRequest = 30;
  SelectionNotify  = 31;
  SelectionClear   = 29;
  PropertyNotify   = 28;
  ClientMessage    = 33;
  PropertyNewValue = 0;
  PropertyDelete   = 1;
  PropModeReplace  = 0;
  AnyPropertyType  = TXAtom(0);
  XA_STRING        = TXAtom(31);
  Success          = 0;
  NoEventMask      = 0;

{ XEvent is a fixed-size union of 24 platform-word fields (192 bytes on
  64-bit).  We only need to read specific sub-structs, so we overlay them
  with a raw array. }
const
  XEVENT_SIZE = 192;

type
  TXEventRaw = array[0..XEVENT_SIZE - 1] of Byte;

  TXSelectionRequestEvent = packed record
    EventType:  cint;       { = SelectionRequest }
    Serial:     PtrUInt;
    SendEvent:  cint;
    Display:    TXDisplay;
    Owner:      TXWindow;
    Requestor:  TXWindow;
    Selection:  TXAtom;
    Target:     TXAtom;
    AProperty:  TXAtom;
    Time:       TXTime;
  end;

  TXSelectionEvent = packed record
    EventType:  cint;       { = SelectionNotify }
    Serial:     PtrUInt;
    SendEvent:  cint;
    Display:    TXDisplay;
    Requestor:  TXWindow;
    Selection:  TXAtom;
    Target:     TXAtom;
    AProperty:  TXAtom;
    Time:       TXTime;
  end;

  TXSelectionClearEvent = packed record
    EventType:  cint;       { = SelectionClear }
    Serial:     PtrUInt;
    SendEvent:  cint;
    Display:    TXDisplay;
    Window:     TXWindow;
    Selection:  TXAtom;
    Time:       TXTime;
  end;

  TXClientMessageEvent = packed record
    EventType:  cint;
    Serial:     PtrUInt;
    SendEvent:  cint;
    Display:    TXDisplay;
    Window:     TXWindow;
    MessageType: TXAtom;
    Format:     cint;
    { data — 5 longs }
    Data:       array[0..4] of PtrUInt;
  end;

  PXAtom   = ^TXAtom;
  PCULong  = ^culong;

{ ---- dlopen function pointer types ---- }
type
  TXOpenDisplay       = function(name: PChar): TXDisplay; cdecl;
  TXCloseDisplay      = function(dpy: TXDisplay): cint; cdecl;
  TXDefaultRootWindow = function(dpy: TXDisplay): TXWindow; cdecl;
  TXDefaultScreen     = function(dpy: TXDisplay): cint; cdecl;
  TXCreateSimpleWindow = function(dpy: TXDisplay; parent: TXWindow;
                           x, y: cint; w, h: cuint; bw: cuint;
                           border, background: PtrUInt): TXWindow; cdecl;
  TXDestroyWindow     = function(dpy: TXDisplay; w: TXWindow): cint; cdecl;
  TXInternAtom        = function(dpy: TXDisplay; name: PChar; only_if_exists: cint): TXAtom; cdecl;
  TXSetSelectionOwner = function(dpy: TXDisplay; sel: TXAtom; owner: TXWindow; t: TXTime): cint; cdecl;
  TXGetSelectionOwner = function(dpy: TXDisplay; sel: TXAtom): TXWindow; cdecl;
  TXConvertSelection  = function(dpy: TXDisplay; sel, target, prop: TXAtom;
                           requestor: TXWindow; t: TXTime): cint; cdecl;
  TXNextEvent         = function(dpy: TXDisplay; event: Pointer): cint; cdecl;
  TXPending           = function(dpy: TXDisplay): cint; cdecl;
  TXSendEvent         = function(dpy: TXDisplay; w: TXWindow; propagate: cint;
                           mask: clong; event: Pointer): TXStatus; cdecl;
  TXGetWindowProperty = function(dpy: TXDisplay; w: TXWindow; prop: TXAtom;
                           offset, length: clong; del: cint; req_type: TXAtom;
                           actual_type: PXAtom; actual_format: Pcint;
                           nitems, bytes_after: PCULong; data: PPointer): cint; cdecl;
  TXChangeProperty    = function(dpy: TXDisplay; w: TXWindow; prop, atype: TXAtom;
                           format, mode: cint; data: Pointer; nelements: cint): cint; cdecl;
  TXDeleteProperty    = function(dpy: TXDisplay; w: TXWindow; prop: TXAtom): cint; cdecl;
  TXSelectInput       = function(dpy: TXDisplay; w: TXWindow; mask: clong): cint; cdecl;
  TXFlush             = function(dpy: TXDisplay): cint; cdecl;
  TXSync              = function(dpy: TXDisplay; discard: cint): cint; cdecl;
  TXFree              = function(data: Pointer): cint; cdecl;
  TXConnectionNumber  = function(dpy: TXDisplay): cint; cdecl;

{ ---- X11 symbol table ---- }
type
  TX11Lib = record
    Handle:            TLibHandle;
    OpenDisplay:       TXOpenDisplay;
    CloseDisplay:      TXCloseDisplay;
    DefaultRootWindow: TXDefaultRootWindow;
    DefaultScreen:     TXDefaultScreen;
    CreateSimpleWindow: TXCreateSimpleWindow;
    DestroyWindow:     TXDestroyWindow;
    InternAtom:        TXInternAtom;
    SetSelectionOwner: TXSetSelectionOwner;
    GetSelectionOwner: TXGetSelectionOwner;
    ConvertSelection:  TXConvertSelection;
    NextEvent:         TXNextEvent;
    Pending:           TXPending;
    SendEvent:         TXSendEvent;
    GetWindowProperty: TXGetWindowProperty;
    ChangeProperty:    TXChangeProperty;
    DeleteProperty:    TXDeleteProperty;
    SelectInput:       TXSelectInput;
    Flush:             TXFlush;
    Sync:              TXSync;
    Free_:             TXFree;
    ConnectionNumber:  TXConnectionNumber;
  end;

function LoadX11(out Lib: TX11Lib): Boolean;
var
  H: TLibHandle;

  function Sym(const AName: string): Pointer;
  begin
    Result := GetProcedureAddress(H, AName);
  end;

begin
  FillChar(Lib, SizeOf(Lib), 0);
  H := LoadLibrary('libX11.so.6');
  if H = NilHandle then
    H := LoadLibrary('libX11.so');
  if H = NilHandle then Exit(False);
  Lib.Handle            := H;
  Lib.OpenDisplay       := TXOpenDisplay(Sym('XOpenDisplay'));
  Lib.CloseDisplay      := TXCloseDisplay(Sym('XCloseDisplay'));
  Lib.DefaultRootWindow := TXDefaultRootWindow(Sym('XDefaultRootWindow'));
  Lib.DefaultScreen     := TXDefaultScreen(Sym('XDefaultScreen'));
  Lib.CreateSimpleWindow:= TXCreateSimpleWindow(Sym('XCreateSimpleWindow'));
  Lib.DestroyWindow     := TXDestroyWindow(Sym('XDestroyWindow'));
  Lib.InternAtom        := TXInternAtom(Sym('XInternAtom'));
  Lib.SetSelectionOwner := TXSetSelectionOwner(Sym('XSetSelectionOwner'));
  Lib.GetSelectionOwner := TXGetSelectionOwner(Sym('XGetSelectionOwner'));
  Lib.ConvertSelection  := TXConvertSelection(Sym('XConvertSelection'));
  Lib.NextEvent         := TXNextEvent(Sym('XNextEvent'));
  Lib.Pending           := TXPending(Sym('XPending'));
  Lib.SendEvent         := TXSendEvent(Sym('XSendEvent'));
  Lib.GetWindowProperty := TXGetWindowProperty(Sym('XGetWindowProperty'));
  Lib.ChangeProperty    := TXChangeProperty(Sym('XChangeProperty'));
  Lib.DeleteProperty    := TXDeleteProperty(Sym('XDeleteProperty'));
  Lib.SelectInput       := TXSelectInput(Sym('XSelectInput'));
  Lib.Flush             := TXFlush(Sym('XFlush'));
  Lib.Sync              := TXSync(Sym('XSync'));
  Lib.Free_             := TXFree(Sym('XFree'));
  Lib.ConnectionNumber  := TXConnectionNumber(Sym('XConnectionNumber'));
  { Verify the essential symbols loaded }
  Result := Assigned(Lib.OpenDisplay) and
            Assigned(Lib.CloseDisplay) and
            Assigned(Lib.InternAtom) and
            Assigned(Lib.SetSelectionOwner) and
            Assigned(Lib.ConvertSelection) and
            Assigned(Lib.NextEvent);
end;

{ ---- X11 event-loop thread ---- }

{ The thread owns a hidden X11 window and runs the event loop so we can:
    a) Respond to SelectionRequest events (serve our text to other apps).
    b) Request clipboard content from other apps via XConvertSelection.

  Communication with the main thread uses a mutex-protected record plus a
  pipe — writing one byte to the pipe's write end wakes the thread by
  making the X11 fd + pipe fd readable via select(). }

type
  TX11ThreadCmd = (tcNone, tcOwn, tcRequest, tcQuit);

  TX11SharedState = record
    Lock:        TCriticalSection;
    Cmd:         TX11ThreadCmd;
    OwnText:     string;        { text to advertise when we own the selection }
    ReplyReady:  Boolean;       { True when GetText result is ready }
    ReplyText:   string;        { result of a GetText request }
    WakePipe:    array[0..1] of cint; { [0]=read end, [1]=write end }
  end;

  TX11Thread = class(TThread)
  private
    FLib:    TX11Lib;
    FDpy:    TXDisplay;
    FWin:    TXWindow;
    FState:  ^TX11SharedState;
    { Interned atoms — initialised in SetupAtoms }
    AClipboard, AUTF8String, AString, ATargets, ATermUIClip, ADelete,
    AIncr, AWMProtocols, AWMDeleteWindow, ATermUIQuit: TXAtom;

    procedure SetupAtoms;
    procedure HandleSelectionRequest(var E: TXSelectionRequestEvent);
    procedure HandleSelectionClear(var E: TXSelectionClearEvent);
    procedure HandleSelectionNotify(var E: TXSelectionEvent);
    procedure DrainWakePipe;
    procedure SendWakeToSelf;
    function  PollEvents(TimeoutMs: Integer): Boolean;
  protected
    procedure Execute; override;
  end;

procedure TX11Thread.SetupAtoms;

  function IA(const N: string): TXAtom;
  begin
    Result := FLib.InternAtom(FDpy, PChar(N), 0);
  end;

begin
  AClipboard        := IA('CLIPBOARD');
  AUTF8String       := IA('UTF8_STRING');
  AString           := XA_STRING;
  ATargets          := IA('TARGETS');
  ATermUIClip       := IA('TERMUI_CLIPBOARD');
  ADelete           := IA('DELETE');
  AIncr             := IA('INCR');
  AWMProtocols      := IA('WM_PROTOCOLS');
  AWMDeleteWindow   := IA('WM_DELETE_WINDOW');
  ATermUIQuit       := IA('_TERMUI_QUIT');
end;

procedure TX11Thread.DrainWakePipe;
var
  B: Byte;
begin
  while FpRead(FState^.WakePipe[0], B, 1) = 1 do ;
end;

procedure TX11Thread.SendWakeToSelf;
var
  B: Byte;
begin
  B := 1;
  FpWrite(FState^.WakePipe[1], B, 1);
end;

{ Wait up to TimeoutMs for either the X11 fd or the wake pipe to be readable.
  Returns True if any data is available. }
function TX11Thread.PollEvents(TimeoutMs: Integer): Boolean;
var
  XFd, PipeFd: cint;
  FdSet:       TFDSet;
  TV:          TimeVal;
begin
  XFd    := FLib.ConnectionNumber(FDpy);
  PipeFd := FState^.WakePipe[0];
  fpFD_ZERO(FdSet);
  fpFD_SET(XFd,    FdSet);
  fpFD_SET(PipeFd, FdSet);
  TV.tv_sec  := TimeoutMs div 1000;
  TV.tv_usec := (TimeoutMs mod 1000) * 1000;
  Result := fpSelect(Max(XFd, PipeFd) + 1, @FdSet, nil, nil, @TV) > 0;
end;

procedure TX11Thread.HandleSelectionRequest(var E: TXSelectionRequestEvent);
var
  Notify: TXSelectionEvent;
  Targets: array[0..2] of TXAtom;
  Text:   string;

  procedure Refuse;
  begin
    Notify.AProperty := X_None;
    FLib.SendEvent(FDpy, Notify.Requestor, 0, NoEventMask, @Notify);
  end;

begin
  FillChar(Notify, SizeOf(Notify), 0);
  Notify.EventType  := SelectionNotify;
  Notify.Display    := FDpy;
  Notify.Requestor  := E.Requestor;
  Notify.Selection  := E.Selection;
  Notify.Target     := E.Target;
  Notify.AProperty  := E.AProperty;
  Notify.Time       := E.Time;

  if E.AProperty = X_None then
  begin
    Refuse;
    Exit;
  end;

  FState^.Lock.Acquire;
  Text := FState^.OwnText;
  FState^.Lock.Release;

  if E.Target = ATargets then
  begin
    Targets[0] := ATargets;
    Targets[1] := AUTF8String;
    Targets[2] := AString;
    FLib.ChangeProperty(FDpy, E.Requestor, E.AProperty, XA_ATOM, 32,
      PropModeReplace, @Targets[0], 3);
  end
  else if (E.Target = AUTF8String) or (E.Target = AString) then
  begin
    FLib.ChangeProperty(FDpy, E.Requestor, E.AProperty, E.Target, 8,
      PropModeReplace, PChar(Text), Length(Text));
  end
  else
  begin
    Refuse;
    Exit;
  end;

  FLib.SendEvent(FDpy, Notify.Requestor, 0, NoEventMask, @Notify);
end;

procedure TX11Thread.HandleSelectionClear(var E: TXSelectionClearEvent);
begin
  FState^.Lock.Acquire;
  FState^.OwnText := '';
  FState^.Lock.Release;
end;

procedure TX11Thread.HandleSelectionNotify(var E: TXSelectionEvent);
var
  ActualType:   TXAtom;
  ActualFormat: cint;
  NItems, BytesAfter: culong;
  Data:         Pointer;
  S:            string;
begin
  if (E.Selection <> AClipboard) or (E.Target <> AUTF8String) or
     (E.AProperty = X_None) then
  begin
    FState^.Lock.Acquire;
    FState^.ReplyText  := '';
    FState^.ReplyReady := True;
    FState^.Lock.Release;
    Exit;
  end;

  Data := nil;
  FLib.GetWindowProperty(FDpy, FWin, E.AProperty, 0, High(clong), 1 {delete},
    AnyPropertyType, @ActualType, @ActualFormat, @NItems, @BytesAfter, @Data);
  if Assigned(Data) then
  begin
    SetString(S, PChar(Data), NItems);
    FLib.Free_(Data);
  end;

  FState^.Lock.Acquire;
  FState^.ReplyText  := S;
  FState^.ReplyReady := True;
  FState^.Lock.Release;
end;

procedure TX11Thread.Execute;
var
  Ev:  TXEventRaw;
  Cmd: TX11ThreadCmd;
  Dummy: cint;
begin
  while not Terminated do
  begin
    { Block until X11 or wake pipe has data (up to 200 ms to check Terminated). }
    if not PollEvents(200) then Continue;

    DrainWakePipe;

    { Check for a command from the main thread. }
    FState^.Lock.Acquire;
    Cmd := FState^.Cmd;
    FState^.Cmd := tcNone;
    FState^.Lock.Release;

    case Cmd of
      tcQuit: Break;
      tcOwn:
        begin
          FLib.SetSelectionOwner(FDpy, AClipboard, FWin, CurrentTime);
          FLib.Flush(FDpy);
        end;
      tcRequest:
        begin
          FLib.ConvertSelection(FDpy, AClipboard, AUTF8String, ATermUIClip,
            FWin, CurrentTime);
          FLib.Flush(FDpy);
        end;
    end;

    { Drain all pending X11 events. }
    while FLib.Pending(FDpy) > 0 do
    begin
      FillChar(Ev, SizeOf(Ev), 0);
      FLib.NextEvent(FDpy, @Ev);
      Dummy := pcint(@Ev)^;
      case Dummy of
        SelectionRequest:
          HandleSelectionRequest(TXSelectionRequestEvent((@Ev)^));
        SelectionClear:
          HandleSelectionClear(TXSelectionClearEvent((@Ev)^));
        SelectionNotify:
          HandleSelectionNotify(TXSelectionEvent((@Ev)^));
      end;
    end;
  end;
end;

{ ---- TX11Clipboard ---- }

type
  TX11Clipboard = class(TClipboardPlatform)
  private
    FLib:    TX11Lib;
    FDpy:    TXDisplay;
    FWin:    TXWindow;
    FThread: TX11Thread;
    FState:  TX11SharedState;
    FLoaded: Boolean;

    procedure IssueCmd(ACmd: TX11ThreadCmd);
  public
    constructor Create;
    destructor  Destroy; override;
    function  Available: Boolean; override;
    procedure SetText(const AText: string); override;
    function  GetText: string; override;
  end;

constructor TX11Clipboard.Create;
var
  Root: TXWindow;
const
  PropertyChangeMask = $400000;
begin
  inherited Create;
  FLoaded := False;
  FState.Lock := TCriticalSection.Create;
  FState.Cmd  := tcNone;
  FState.WakePipe[0] := -1;
  FState.WakePipe[1] := -1;

  if not EnvSet('DISPLAY') then Exit;

  if not LoadX11(FLib) then Exit;

  FDpy := FLib.OpenDisplay(nil);
  if FDpy = nil then
  begin
    UnloadLibrary(FLib.Handle);
    FLib.Handle := NilHandle;
    Exit;
  end;

  Root := FLib.DefaultRootWindow(FDpy);
  FWin := FLib.CreateSimpleWindow(FDpy, Root, 0, 0, 1, 1, 0, 0, 0);
  FLib.SelectInput(FDpy, FWin, PropertyChangeMask);
  FLib.Flush(FDpy);

  if FpPipe(FState.WakePipe) <> 0 then
  begin
    FLib.DestroyWindow(FDpy, FWin);
    FLib.CloseDisplay(FDpy);
    UnloadLibrary(FLib.Handle);
    FLib.Handle := NilHandle;
    Exit;
  end;

  { Put the read end in non-blocking mode so DrainWakePipe never blocks
    on an empty pipe.  Without this, the second FpRead in the drain loop
    waits forever and the destructor's FThread.WaitFor hangs the process
    at finalization time.  The actual idle-sleep lives in PollEvents
    (select() with a 200 ms timeout); the drain only runs after select
    reports data, then exits the moment the pipe is empty. }
  FpFcntl(FState.WakePipe[0], F_SetFl,
          FpFcntl(FState.WakePipe[0], F_GetFl) or O_NONBLOCK);

  FThread        := TX11Thread.Create(True);
  FThread.FLib   := FLib;
  FThread.FDpy   := FDpy;
  FThread.FWin   := FWin;
  FThread.FState := @FState;
  FThread.FreeOnTerminate := False;
  FThread.SetupAtoms;
  FThread.Start;

  FLoaded := True;
end;

destructor TX11Clipboard.Destroy;
var
  B: Byte;
begin
  if FLoaded then
  begin
    { Signal thread to quit. }
    FState.Lock.Acquire;
    FState.Cmd := tcQuit;
    FState.Lock.Release;
    B := 1;
    FpWrite(FState.WakePipe[1], B, 1);
    FThread.WaitFor;
    FThread.Free;

    FpClose(FState.WakePipe[0]);
    FpClose(FState.WakePipe[1]);

    FLib.DestroyWindow(FDpy, FWin);
    FLib.CloseDisplay(FDpy);
    UnloadLibrary(FLib.Handle);
  end;
  FState.Lock.Free;
  inherited;
end;

function TX11Clipboard.Available: Boolean;
begin
  Result := FLoaded;
end;

procedure TX11Clipboard.IssueCmd(ACmd: TX11ThreadCmd);
var
  B: Byte;
begin
  FState.Lock.Acquire;
  FState.Cmd := ACmd;
  FState.Lock.Release;
  B := 1;
  FpWrite(FState.WakePipe[1], B, 1);
end;

procedure TX11Clipboard.SetText(const AText: string);
begin
  FState.Lock.Acquire;
  FState.OwnText := AText;
  FState.Lock.Release;
  IssueCmd(tcOwn);
end;

function TX11Clipboard.GetText: string;
const
  TimeoutMs = 500;
var
  Deadline: QWord;
  Ready:    Boolean;
begin
  Result := '';

  FState.Lock.Acquire;
  if FState.OwnText <> '' then
  begin
    Result := FState.OwnText;
    FState.Lock.Release;
    Exit;
  end;
  FState.ReplyReady := False;
  FState.ReplyText  := '';
  FState.Lock.Release;

  IssueCmd(tcRequest);

  Deadline := GetTickCount64 + TimeoutMs;
  repeat
    Sleep(5);
    FState.Lock.Acquire;
    Ready := FState.ReplyReady;
    if Ready then
      Result := FState.ReplyText;
    FState.Lock.Release;
  until Ready or (GetTickCount64 >= Deadline);
end;

{ ===========================================================================
  Factory: pick the best available backend
  =========================================================================== }

function CreateUnixClipboard: TClipboardPlatform;
var
  W: TWaylandClipboard;
  X: TX11Clipboard;
begin
  W := TWaylandClipboard.Create;
  if W.Available then Exit(W);
  W.Free;

  X := TX11Clipboard.Create;
  if X.Available then Exit(X);
  X.Free;

  Result := nil;
end;

var
  GInitPlatform: TClipboardPlatform;

initialization
  GInitPlatform := CreateUnixClipboard;
  if Assigned(GInitPlatform) then
    RegisterClipboardPlatform(GInitPlatform);

end.
