{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Control.VBox;

{$mode objfpc}{$H+}
{$interfaces corba}

{ Vertical box layout container.

  Children are stacked top to bottom within the container's bounds.
  lhFixed children take exactly FixedSize rows.
  lhStretch children share the remaining rows equally; if the remainder
  does not divide evenly the extra rows go to the first stretch children. }

interface

uses
  Classes, TermUI.Control, TermUI.Control.Container;

type
  TVBox = class(TMultiContainerControl)
  protected
    procedure ArrangeChildren; override;
  end;

implementation

procedure TVBox.ArrangeChildren;
var
  I, Y, Remaining, StretchCount, StretchH, Extra, H: Integer;
begin
  Remaining    := Height;
  StretchCount := 0;
  for I := 0 to ChildCount - 1 do
    if GetChild(I).Visible then
    begin
      if FChildren[I].Hint = lhFixed then
        Dec(Remaining, FChildren[I].FixedSize)
      else
        Inc(StretchCount);
    end;

  if StretchCount > 0 then
  begin
    StretchH := Remaining div StretchCount;
    Extra    := Remaining - StretchH * StretchCount;
  end
  else
  begin
    StretchH := 0;
    Extra    := 0;
  end;

  Y := Top;
  for I := 0 to ChildCount - 1 do
  begin
    if not GetChild(I).Visible then Continue;
    if FChildren[I].Hint = lhFixed then
      H := FChildren[I].FixedSize
    else
    begin
      H := StretchH;
      if Extra > 0 then begin Inc(H); Dec(Extra); end;
    end;
    GetChild(I).SetBounds(Left, Y, Width, H);
    Inc(Y, H);
  end;
end;

end.
