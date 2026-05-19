{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Control.LineEditor;

{$mode objfpc}{$H+}
{$modeswitch typehelpers}

interface

uses
  Classes, TermUI.Terminal, TermUI.Control, TermUI.StringUtils;

type
  { Single-line text editor control.
    SetBounds defines the field area; the full width is used as the visible field.

    All string positions are 0-based UTF-8 character (codepoint) indices:
      FCur    0-based char position of the insertion cursor.
              0 = before the first char; FBuf.Length = after the last char.
      FScroll 0-based char offset scrolled off the left edge.
  }
  TTextEdit = class(TControl)
  private
    FBuf:          string;
    FCur:          Integer;   { 0-based char cursor position }
    FScroll:       Integer;   { 0-based char scroll offset  }
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
    procedure Invalidate; override;
    procedure DoGainFocus; override;
    procedure DoLoseFocus; override;
  public
    constructor Create; override;
    procedure Clear;
    { Replace chars [AFrom..ATo) (0-based, ATo exclusive) with AReplacement.
      Cursor is placed immediately after the inserted text.
      Fires OnChange but not OnAccept. }
    procedure ReplaceRange(AFrom, ATo: Integer; const AReplacement: string);
    property Text:         string       read FBuf         write SetBuf;
    property CursorPos:    Integer      read FCur;   { 0-based char index }
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
  FCur          := 0;
  FScroll       := 0;
  FPasswordChar := #0;
end;

procedure TTextEdit.SetBuf(const AValue: string);
begin
  FBuf    := AValue;
  FCur    := FBuf.Length;   { place cursor after last char }
  FScroll := 0;
  ClampScroll;
  Invalidate;
end;

procedure TTextEdit.ClampScroll;
begin
  { Keep FCur in the visible window [FScroll .. FScroll + Width - 1]. }
  if FCur < FScroll then FScroll := FCur;
  if FCur - FScroll >= Width then FScroll := FCur - Width + 1;
  if FScroll < 0 then FScroll := 0;
end;

function TTextEdit.WordLeft: Integer;
var I: Integer;
begin
  I := FCur;
  while (I > 0) and (FBuf.Chars[I - 1] = ' ') do Dec(I);
  while (I > 0) and (FBuf.Chars[I - 1] <> ' ') do Dec(I);
  Result := I;
end;

function TTextEdit.WordRight: Integer;
var
  Len: Integer;
  I:   Integer;
begin
  Len := FBuf.Length;
  I   := FCur;
  while (I < Len) and (FBuf.Chars[I] <> ' ') do Inc(I);
  while (I < Len) and (FBuf.Chars[I] = ' ')  do Inc(I);
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
    { Build a mask the same char length as FBuf, then scroll it }
    Display := CopyNeutral(
      StringOfChar(FPasswordChar, FBuf.Length), FScroll, Width);
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
  if ShowCursor then
  begin
    Term.ShowCursor;
    Term.PlaceCursor(Left + (FCur - FScroll), Top);
  end;
  inherited DoPaint;
end;

function TTextEdit.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  Result := True;
  case Key.Code of
    kcLeft:
      begin
        if FCur > 0 then Dec(FCur);
        Invalidate;
      end;
    kcRight:
      begin
        if FCur < FBuf.Length then Inc(FCur);
        Invalidate;
      end;
    kcHome:      begin FCur := 0;           Invalidate; end;
    kcEnd:       begin FCur := FBuf.Length; Invalidate; end;
    kcCtrlLeft:  begin FCur := WordLeft;    Invalidate; end;
    kcCtrlRight: begin FCur := WordRight;   Invalidate; end;

    kcBackspace:
      if FCur > 0 then
      begin
        FBuf.Delete(FCur - 1, 1);
        Dec(FCur);
        Invalidate;
        if Assigned(FOnChange) then FOnChange(Self);
      end;

    kcDelete:
      if FCur < FBuf.Length then
      begin
        FBuf.Delete(FCur, 1);
        Invalidate;
        if Assigned(FOnChange) then FOnChange(Self);
      end;

    kcCtrlK:   { kill to end of line }
      begin
        FBuf := FBuf.Copy(0, FCur);
        Invalidate;
        if Assigned(FOnChange) then FOnChange(Self);
      end;

    kcCtrlU:   { kill to start of line }
      begin
        FBuf := FBuf.Copy(FCur, FBuf.Length - FCur);
        FCur := 0; FScroll := 0;
        Invalidate;
        if Assigned(FOnChange) then FOnChange(Self);
      end;

    kcEnter:  if Assigned(FOnAccept) then FOnAccept(Self);
    kcEscape: if Assigned(FOnCancel) then FOnCancel(Self);

    kcChar:
      if Key.Ch >= ' ' then
      begin
        InsertNeutral(FBuf, Key.Ch, FCur);
        Inc(FCur);   { always 1 codepoint regardless of UTF-8 byte width }
        Invalidate;
        if Assigned(FOnChange) then FOnChange(Self);
      end;
  else
    Result := False;
  end;
end;

procedure TTextEdit.ReplaceRange(AFrom, ATo: Integer; const AReplacement: string);
begin
  if AFrom < 0 then AFrom := 0;
  if ATo > FBuf.Length then ATo := FBuf.Length;
  FBuf := FBuf.Copy(0, AFrom) + AReplacement + FBuf.Copy(ATo, FBuf.Length - ATo);
  FCur := AFrom + AReplacement.Length;
  ClampScroll;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTextEdit.Clear;
begin
  FBuf    := '';
  FCur    := 0;
  FScroll := 0;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTextEdit.DoGainFocus;
begin
  ShowCursor := True;
  Invalidate;
end;

procedure TTextEdit.DoLoseFocus;
begin
  ShowCursor := False;
  Term.HideCursor;
  Invalidate;
end;

procedure TTextEdit.Invalidate;
begin
  inherited Invalidate;
  if Top > 0 then
    Term.HintDirtyRow(Top);
end;

end.
