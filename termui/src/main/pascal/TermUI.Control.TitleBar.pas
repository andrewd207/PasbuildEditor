{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Control.TitleBar;

{$mode objfpc}{$H+}

{ Single-row title bar control.

  Renders one row with a left-aligned Title and an optional right-aligned
  RightText separated by padding.  ForeColor / BackColor from TControl are
  honored; defaults are clBrightWhite on clBlue.

  Typical usage:
    FTitleBar := TTitleBar.Create;
    FTitleBar.Title     := 'My App';
    FTitleBar.RightText := 'F1 Help';
    AddChild(FTitleBar);
    { position it in ArrangeChildren: }
    FTitleBar.SetBounds(Left, Top, Width, 1); }

interface

uses
  SysUtils, TermUI.Terminal, TermUI.Control, TermUI.StringUtils;

type
  TTitleBar = class(TControl)
  private
    FTitle:     string;
    FRightText: string;
    procedure SetTitle(const AValue: string);
    procedure SetRightText(const AValue: string);
  protected
    procedure DoPaint; override;
  public
    constructor Create; override;
    property Title:     string read FTitle     write SetTitle;
    property RightText: string read FRightText write SetRightText;
  end;

implementation

constructor TTitleBar.Create;
begin
  inherited Create;
  Focusable := False;
end;

procedure TTitleBar.SetTitle(const AValue: string);
begin
  if FTitle = AValue then Exit;
  FTitle := AValue;
  Invalidate;
end;

procedure TTitleBar.SetRightText(const AValue: string);
begin
  if FRightText = AValue then Exit;
  FRightText := AValue;
  Invalidate;
end;

procedure TTitleBar.DoPaint;
var
  Bar:  string;
  TLen, RLen, Pad: Integer;
begin
  GotoLocal(1, 1);

  if BackColor <> clDefault then Term.SetBG(BackColor)
  else                           Term.SetBG(clBlue);
  if ForeColor <> clDefault then Term.SetFG(ForeColor)
  else                           Term.SetFG(clBrightWhite);

  TLen := Length(FTitle);
  RLen := Length(FRightText);
  Pad  := Width - 2 - TLen - RLen;
  if Pad < 0 then Pad := 0;

  Bar := ' ' + FTitle + StringOfChar(' ', Pad) + FRightText + ' ';
  { Ensure exact width }
  while Length(Bar) < Width do Bar := Bar + ' ';
  if Length(Bar) > Width then Bar := CopyNeutral(Bar, 0, Width);

  Term.WriteStr(Bar);
  Term.ResetColors;
  inherited DoPaint;
end;

end.
