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
  Windows, SysUtils;

type
  TWindowsClipboard = class(TClipboardPlatform)
  public
    function  Available: Boolean; override;
    procedure SetText(const AText: string); override;
    function  GetText: string; override;
  end;

function TWindowsClipboard.Available: Boolean;
begin
  Result := True;
end;

procedure TWindowsClipboard.SetText(const AText: string);
var
  WStr: WideString;
  Len:  Integer;
  Mem:  HGLOBAL;
  Ptr:  Pointer;
begin
  if not OpenClipboard(0) then Exit;
  try
    EmptyClipboard;
    WStr := UTF8Decode(AText);
    Len  := (Length(WStr) + 1) * SizeOf(WideChar);
    Mem  := GlobalAlloc(GMEM_MOVEABLE, Len);
    if Mem = 0 then Exit;
    Ptr  := GlobalLock(Mem);
    if Ptr = nil then
    begin
      GlobalFree(Mem);
      Exit;
    end;
    Move(WStr[1], Ptr^, Len);
    GlobalUnlock(Mem);
    SetClipboardData(CF_UNICODETEXT, Mem);
  finally
    CloseClipboard;
  end;
end;

function TWindowsClipboard.GetText: string;
var
  Mem: HGLOBAL;
  Ptr: PWideChar;
begin
  Result := '';
  if not IsClipboardFormatAvailable(CF_UNICODETEXT) then Exit;
  if not OpenClipboard(0) then Exit;
  try
    Mem := GetClipboardData(CF_UNICODETEXT);
    if Mem = 0 then Exit;
    Ptr := GlobalLock(Mem);
    if Ptr = nil then Exit;
    try
      Result := UTF8Encode(WideString(Ptr));
    finally
      GlobalUnlock(Mem);
    end;
  finally
    CloseClipboard;
  end;
end;

initialization
  RegisterClipboardPlatform(TWindowsClipboard.Create);

end.
