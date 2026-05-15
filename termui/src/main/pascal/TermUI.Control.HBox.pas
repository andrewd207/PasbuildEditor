{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Control.HBox;

{$mode objfpc}{$H+}
{$interfaces corba}

{ Horizontal box layout container.

  Children are placed left to right within the container's bounds.
  lhFixed children take exactly FixedSize columns.
  lhStretch children share the remaining columns equally; if the remainder
  does not divide evenly the extra columns go to the first stretch children. }

interface

uses
  Classes, TermUI.Control, TermUI.Control.Container;

type
  THBox = class(TMultiContainerControl)
  protected
    procedure ArrangeChildren; override;
  end;

implementation

procedure THBox.ArrangeChildren;
var
  I, X, Remaining, StretchCount, StretchW, Extra, W: Integer;
begin
  Remaining    := Width;
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
    StretchW := Remaining div StretchCount;
    Extra    := Remaining - StretchW * StretchCount;
  end
  else
  begin
    StretchW := 0;
    Extra    := 0;
  end;

  X := Left;
  for I := 0 to ChildCount - 1 do
  begin
    if not GetChild(I).Visible then Continue;
    if FChildren[I].Hint = lhFixed then
      W := FChildren[I].FixedSize
    else
    begin
      W := StretchW;
      if Extra > 0 then begin Inc(W); Dec(Extra); end;
    end;
    GetChild(I).SetBounds(X, Top, W, Height);
    Inc(X, W);
  end;
end;

end.
