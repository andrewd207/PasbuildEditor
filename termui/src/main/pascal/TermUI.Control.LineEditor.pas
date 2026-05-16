{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Control.LineEditor;

{$mode objfpc}{$H+}

interface

uses
  Classes, TermUI.Terminal, TermUI.Control, TermUI.StringUtils;

type
  { Single-line text editor control.
    SetBounds defines the field area; the full width is used as the visible field.
    FCur is 1-based; FScroll is the number of bytes scrolled off the left edge. }
  TTextEdit = class(TControl)
  private
    FBuf:          string;
    FCur:          Integer;   { 1-based cursor position in FBuf }
    FScroll:       Integer;   { bytes scrolled off the left }
    FPasswordChar: Char;      { #0 = plain text }
    FPlaceholder:  string;
    FOnChange:     TNotifyEvent;
    FOnAccept:     TNotifyEvent;
    FOnCancel:     TNotifyEvent;
    procedure SetBuf(const AValue: string);
    procedure ClampScroll;
    function  WordLeft: Integer;
    function  WordRight: Integer;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
  public
    constructor Create; override;
    procedure Clear;
    property Text:         string       read FBuf         write SetBuf;
    property CursorPos:    Integer      read FCur;
    property PasswordChar: Char         read FPasswordChar write FPasswordChar;
    property Placeholder:  string       read FPlaceholder  write FPlaceholder;
    property OnChange:     TNotifyEvent read FOnChange     write FOnChange;
    property OnAccept:     TNotifyEvent read FOnAccept     write FOnAccept;
    property OnCancel:     TNotifyEvent read FOnCancel     write FOnCancel;
  end;

implementation

constructor TTextEdit.Create;
begin
  inherited Create;
  FCur          := 1;
  FScroll       := 0;
  FPasswordChar := #0;
end;

procedure TTextEdit.SetBuf(const AValue: string);
begin
  FBuf    := AValue;
  FCur    := Length(FBuf) + 1;
  FScroll := 0;
  ClampScroll;
  Invalidate;
end;

procedure TTextEdit.ClampScroll;
begin
  if FCur - FScroll < 1     then FScroll := FCur - 1;
  if FCur - FScroll > Width then FScroll := FCur - Width;
  if FScroll < 0 then FScroll := 0;
end;

function TTextEdit.WordLeft: Integer;
var I: Integer;
begin
  I := FCur - 1;
  while (I > 1) and (FBuf[I - 1] = ' ') do Dec(I);
  while (I > 1) and (FBuf[I - 1] <> ' ') do Dec(I);
  Result := I;
end;

function TTextEdit.WordRight: Integer;
var I, Len: Integer;
begin
  Len := Length(FBuf);
  I   := FCur;
  while (I <= Len) and (FBuf[I] <> ' ') do Inc(I);
  while (I <= Len) and (FBuf[I] = ' ')  do Inc(I);
  Result := I;
end;

procedure TTextEdit.DoPaint;
var
  Display: string;
  Pad:     Integer;
  I:       Integer;
begin
  ClampScroll;
  GotoLocal(1, 1);

  if (FBuf = '') and (FPlaceholder <> '') then
  begin
    Term.SetFG(clBrightBlack);
    Display := CopyNeutral(FPlaceholder, FScroll, Width);
  end
  else if FPasswordChar <> #0 then
  begin
    Term.ResetColors;
    Display := CopyNeutral(StringOfChar(FPasswordChar, Length(FBuf)), FScroll, Width);
  end
  else
  begin
    Term.ResetColors;
    Display := CopyNeutral(FBuf, FScroll, Width);
  end;

  Term.WriteStr(Display);
  Pad := Width - UTF8VisualLen(Display);
  for I := 1 to Pad do
    Term.WriteStr(' ');

  Term.ResetColors;
  Term.ShowCursor;
  GotoLocal(FCur - FScroll, 1);
  inherited DoPaint;
end;

function TTextEdit.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  Result := True;
  case Key.Code of
    kcLeft:      begin if FCur > 1               then Dec(FCur);      Invalidate; end;
    kcRight:     begin if FCur <= Length(FBuf)   then Inc(FCur);      Invalidate; end;
    kcHome:      begin FCur := 1;                                      Invalidate; end;
    kcEnd:       begin FCur := Length(FBuf) + 1;                      Invalidate; end;
    kcCtrlLeft:  begin FCur := WordLeft;                               Invalidate; end;
    kcCtrlRight: begin FCur := WordRight;                              Invalidate; end;
    kcBackspace:
      if FCur > 1 then
      begin
        DeleteNeutral(FBuf, FCur - 2, 1);
        Dec(FCur);
        Invalidate;
        if Assigned(FOnChange) then FOnChange(Self);
      end;
    kcDelete:
      if FCur <= Length(FBuf) then
      begin
        DeleteNeutral(FBuf, FCur - 1, 1);
        Invalidate;
        if Assigned(FOnChange) then FOnChange(Self);
      end;
    kcCtrlK:
      begin
        FBuf := Copy(FBuf, 1, FCur - 1);
        Invalidate;
        if Assigned(FOnChange) then FOnChange(Self);
      end;
    kcCtrlU:
      begin
        FBuf := Copy(FBuf, FCur, MaxInt);
        FCur := 1; FScroll := 0;
        Invalidate;
        if Assigned(FOnChange) then FOnChange(Self);
      end;
    kcEnter:  if Assigned(FOnAccept) then FOnAccept(Self);
    kcEscape: if Assigned(FOnCancel) then FOnCancel(Self);
    kcChar:
      if Key.Ch >= ' ' then
      begin
        Insert(Key.Ch, FBuf, FCur);
        Inc(FCur, System.Length(string(Key.Ch)));
        Invalidate;
        if Assigned(FOnChange) then FOnChange(Self);
      end;
  else
    Result := False;
  end;
end;

procedure TTextEdit.Clear;
begin
  FBuf    := '';
  FCur    := 1;
  FScroll := 0;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

end.
