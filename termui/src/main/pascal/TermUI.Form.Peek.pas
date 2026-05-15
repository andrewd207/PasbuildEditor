{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Form.Peek;

{$mode objfpc}{$H+}
{$interfaces corba}

{ Partial-screen overlay form that opens from one edge of the terminal.

  The peek occupies a strip along one side — PeekSize columns (left/right)
  or rows (top/bottom).  TApplication paints the form beneath it first
  because Overlay = True, so underlying content remains visible.

  Usage:
    FPeek := TMyPeek.Create(psRight, 40, 'Details');
    Application.ShowModal(FPeek);   // or PushForm / PopForm

  Child controls should be positioned within the content area:
    Left  = peek.Left + 1    (inside the left border)
    Top   = peek.Top  + 2    (below the title/border row)
    Width = peek.Width - 2
    Height = peek.Height - 3  (top border + title + bottom border)

  Override SetBounds to intercept resize notifications — TApplication calls
  SetBounds(1,1,Term.Width,Term.Height) on resize, which is redirected to
  UpdateBounds so the peek stays anchored to its edge. }

interface

uses
  Classes, TermUI.Terminal, TermUI.Forms;

type
  TPeekSide = (psLeft, psRight, psTop, psBottom);

  TPeekForm = class(TForm)
  private
    FSide:     TPeekSide;
    FPeekSize: Integer;
    procedure UpdateBounds;
  protected
    procedure DoPaint; override;
  public
    constructor Create(ASide: TPeekSide; APeekSize: Integer;
      const ATitle: string = ''); reintroduce; virtual;
    { Intercepts TApplication resize calls and recalculates from Side+PeekSize. }
    procedure SetBounds(ALeft, ATop, AWidth, AHeight: Integer); override;

    { Content area coordinates — use these when placing child controls. }
    function ContentLeft:   Integer;
    function ContentTop:    Integer;
    function ContentWidth:  Integer;
    function ContentHeight: Integer;

    property Side:     TPeekSide read FSide;
    property PeekSize: Integer   read FPeekSize write FPeekSize;
  end;

implementation

constructor TPeekForm.Create(ASide: TPeekSide; APeekSize: Integer;
  const ATitle: string);
begin
  inherited Create(ATitle);
  Overlay   := True;
  FSide     := ASide;
  FPeekSize := APeekSize;
  UpdateBounds;
end;

procedure TPeekForm.UpdateBounds;
var W, H: Integer;
begin
  W := Term.Width;
  H := Term.Height;
  case FSide of
    psLeft:   inherited SetBounds(1,             1, FPeekSize, H);
    psRight:  inherited SetBounds(W-FPeekSize+1, 1, FPeekSize, H);
    psTop:    inherited SetBounds(1,             1, W,         FPeekSize);
    psBottom: inherited SetBounds(1,   H-FPeekSize+1, W,       FPeekSize);
  end;
end;

procedure TPeekForm.SetBounds(ALeft, ATop, AWidth, AHeight: Integer);
begin
  UpdateBounds;
end;

function TPeekForm.ContentLeft: Integer;
begin
  Result := Left + 1;
end;

function TPeekForm.ContentTop: Integer;
begin
  Result := Top + 2;  { border row + title row }
end;

function TPeekForm.ContentWidth: Integer;
begin
  Result := Width - 2;
end;

function TPeekForm.ContentHeight: Integer;
begin
  Result := Height - 3;  { top border + title + bottom border }
end;

procedure TPeekForm.DoPaint;
var
  X, Y, InnerW: Integer;
  TitleStr: string;
begin
  { Background fill }
  Term.SetBG(clBlue);
  Term.SetFG(clWhite);
  for Y := 1 to Height do
  begin
    GotoLocal(1, Y);
    for X := 1 to Width do
      Term.WriteStr(' ');
  end;

  InnerW := Width - 2;

  { Top border with title }
  Term.SetFG(clBrightWhite);
  GotoLocal(1, 1);
  Term.WriteStr('+');
  if (Title <> '') and (InnerW > 0) then
  begin
    TitleStr := ' ' + Title + ' ';
    if Length(TitleStr) > InnerW then
    begin
      TitleStr := Copy(TitleStr, 1, InnerW - 1) + '~';
    end;
    Term.WriteStr(TitleStr);
    for X := Length(TitleStr) + 1 to InnerW do
      Term.WriteStr('-');
  end
  else
    for X := 1 to InnerW do
      Term.WriteStr('-');
  Term.WriteStr('+');

  { Side borders }
  Term.SetFG(clBrightWhite);
  for Y := 2 to Height - 1 do
  begin
    GotoLocal(1, Y);
    Term.WriteStr('|');
    GotoLocal(Width, Y);
    Term.WriteStr('|');
  end;

  { Bottom border }
  GotoLocal(1, Height);
  Term.WriteStr('+');
  for X := 1 to InnerW do
    Term.WriteStr('-');
  Term.WriteStr('+');

  Term.ResetColors;
  inherited DoPaint;
end;

end.
