{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Clipboard;

{$mode objfpc}{$H+}

interface

type
  { Abstract platform backend. Platform units subclass this and register an
    instance via RegisterClipboardPlatform. }
  TClipboardPlatform = class
  public
    { Push AText to the system clipboard. Silently ignored if unavailable. }
    procedure SetText(const AText: string); virtual; abstract;
    { Pull text from the system clipboard.  Returns empty string on failure. }
    function  GetText: string; virtual; abstract;
    { Returns True if the platform backend is functional. }
    function  Available: Boolean; virtual;
    destructor Destroy; override;
  end;

  { The application-level clipboard.  Always maintains its own internal copy
    so that copy/paste works even when no system clipboard is reachable.

    Typical usage:
      Clipboard.Text := 'hello';
      S := Clipboard.Text; }
  TClipboard = class
  private
    FText:     string;
    FPlatform: TClipboardPlatform;
  public
    constructor Create;
    destructor  Destroy; override;

    procedure SetText(const AText: string);
    function  GetText: string;

    property Text: string read GetText write SetText;

    { True when a functional platform backend is attached. }
    function  HasPlatform: Boolean;

    { Called by platform units (via RegisterClipboardPlatform) to attach the
      backend.  Takes ownership of APlatform. }
    procedure AttachPlatform(APlatform: TClipboardPlatform);
  end;

var
  Clipboard: TClipboard;

{ Called once from a platform unit's initialization section. }
procedure RegisterClipboardPlatform(APlatform: TClipboardPlatform);

implementation

uses
  SysUtils;

{ TClipboardPlatform }

function TClipboardPlatform.Available: Boolean;
begin
  Result := False;
end;

destructor TClipboardPlatform.Destroy;
begin
  inherited;
end;

{ TClipboard }

constructor TClipboard.Create;
begin
  inherited Create;
  FText     := '';
  FPlatform := nil;
end;

destructor TClipboard.Destroy;
begin
  FreeAndNil(FPlatform);
  inherited;
end;

procedure TClipboard.AttachPlatform(APlatform: TClipboardPlatform);
begin
  FreeAndNil(FPlatform);
  FPlatform := APlatform;
end;

function TClipboard.HasPlatform: Boolean;
begin
  Result := Assigned(FPlatform) and FPlatform.Available;
end;

procedure TClipboard.SetText(const AText: string);
begin
  FText := AText;
  if HasPlatform then
    FPlatform.SetText(AText);
end;

function TClipboard.GetText: string;
var
  PlatformText: string;
begin
  if HasPlatform then
  begin
    PlatformText := FPlatform.GetText;
    if PlatformText <> '' then
    begin
      FText := PlatformText;
      Exit(PlatformText);
    end;
  end;
  Result := FText;
end;

{ Registration }

procedure RegisterClipboardPlatform(APlatform: TClipboardPlatform);
begin
  if Assigned(Clipboard) then
    Clipboard.AttachPlatform(APlatform)
  else
    APlatform.Free;
end;

initialization
  Clipboard := TClipboard.Create;

finalization
  FreeAndNil(Clipboard);

end.
