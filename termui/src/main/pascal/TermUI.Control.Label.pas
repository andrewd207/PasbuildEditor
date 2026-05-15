{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Control.Label;

{$mode objfpc}{$H+}

{ Static text label control.

  Text may contain #10 line breaks for manual multi-line content.
  When WordWrap = True the text is also reflowed to fit Width automatically;
  DoBoundsChanged recomputes the wrapped lines so layout is always current.

  Alignment applies per display row.  Long lines that still exceed Width
  after wrapping are truncated with '~'. }

interface

uses
  Classes, SysUtils, TermUI.Terminal, TermUI.Control, TermUI.StringUtils;

type
  TLabelAlign = (laLeft, laCenter, laRight);

  TLabel = class(TControl)
  private
    FText:       string;
    FAlign:      TLabelAlign;
    FFG:         TColor;
    FFGSet:      Boolean;    { False = use terminal default }
    FBG:         TColor;
    FBGSet:      Boolean;
    FWordWrap:   Boolean;
    FLines:      TStringList;   { display lines, recomputed in RebuildLines }
    procedure SetText(const AValue: string);
    procedure SetAlign(AValue: TLabelAlign);
    procedure SetWordWrap(AValue: Boolean);
    procedure SetFG(AValue: TColor);
    procedure SetBG(AValue: TColor);
    procedure RebuildLines;
    procedure WrapLine(const ALine: string);
    function  AlignLine(const ALine: string): string;
  protected
    procedure DoPaint; override;
    procedure DoBoundsChanged; override;
  public
    constructor Create; override;
    destructor  Destroy; override;

    procedure ResetColors;

    property Text:     string      read FText      write SetText;
    property Align:    TLabelAlign read FAlign     write SetAlign;
    property WordWrap: Boolean     read FWordWrap  write SetWordWrap;
    { Set FG/BG to clDefault (and call ResetColors) to revert to terminal default. }
    property ForeColor: TColor     read FFG        write SetFG;
    property BackColor: TColor     read FBG        write SetBG;
  end;

implementation

constructor TLabel.Create;
begin
  inherited Create;
  FLines  := TStringList.Create;
  FFG     := clDefault;
  FBG     := clDefault;
  FFGSet  := False;
  FBGSet  := False;
end;

destructor TLabel.Destroy;
begin
  FLines.Free;
  inherited;
end;

procedure TLabel.ResetColors;
begin
  FFGSet := False;
  FBGSet := False;
  FFG    := clDefault;
  FBG    := clDefault;
  Invalidate;
end;

procedure TLabel.SetText(const AValue: string);
begin
  if FText = AValue then Exit;
  FText := AValue;
  RebuildLines;
  Invalidate;
end;

procedure TLabel.SetAlign(AValue: TLabelAlign);
begin
  if FAlign = AValue then Exit;
  FAlign := AValue;
  Invalidate;
end;

procedure TLabel.SetWordWrap(AValue: Boolean);
begin
  if FWordWrap = AValue then Exit;
  FWordWrap := AValue;
  RebuildLines;
  Invalidate;
end;

procedure TLabel.SetFG(AValue: TColor);
begin
  FFG    := AValue;
  FFGSet := AValue <> clDefault;
  Invalidate;
end;

procedure TLabel.SetBG(AValue: TColor);
begin
  FBG    := AValue;
  FBGSet := AValue <> clDefault;
  Invalidate;
end;

procedure TLabel.WrapLine(const ALine: string);
var
  Words:   TStringList;
  Current, W: string;
  I, W_: Integer;
begin
  if Width <= 0 then begin FLines.Add(ALine); Exit; end;
  Words := TStringList.Create;
  try
    Words.Delimiter       := ' ';
    Words.StrictDelimiter := True;
    Words.DelimitedText   := ALine;
    Current := '';
    for I := 0 to Words.Count - 1 do
    begin
      W := Words[I];
      if W = '' then Continue;
      W_ := UTF8VisualLen(W);
      if Current = '' then
      begin
        if W_ > Width then W := Copy(W, 1, Width - 1) + '~';
        Current := W;
      end
      else if UTF8VisualLen(Current) + 1 + W_ > Width then
      begin
        FLines.Add(Current);
        if W_ > Width then W := Copy(W, 1, Width - 1) + '~';
        Current := W;
      end
      else
        Current := Current + ' ' + W;
    end;
    if Current <> '' then FLines.Add(Current);
  finally
    Words.Free;
  end;
end;

procedure TLabel.RebuildLines;
var
  Raw: TStringList;
  I:   Integer;
  S:   string;
begin
  FLines.Clear;
  if FText = '' then Exit;
  Raw := TStringList.Create;
  try
    Raw.Text := FText;
    for I := 0 to Raw.Count - 1 do
    begin
      S := Raw[I];
      if FWordWrap and (Width > 0) then
        WrapLine(S)
      else
      begin
        if (Width > 0) and (UTF8VisualLen(S) > Width) then
          S := Copy(S, 1, Width - 1) + '~';
        FLines.Add(S);
      end;
    end;
  finally
    Raw.Free;
  end;
end;

function TLabel.AlignLine(const ALine: string): string;
var
  Len, Pad, PadL, PadR: Integer;
begin
  if Width <= 0 then Exit(ALine);
  Len := UTF8VisualLen(ALine);
  if Len >= Width then Exit(ALine);
  Pad := Width - Len;
  case FAlign of
    laLeft:   Result := ALine + StringOfChar(' ', Pad);
    laRight:  Result := StringOfChar(' ', Pad) + ALine;
    laCenter:
      begin
        PadL := Pad div 2;
        PadR := Pad - PadL;
        Result := StringOfChar(' ', PadL) + ALine + StringOfChar(' ', PadR);
      end;
  end;
end;

procedure TLabel.DoBoundsChanged;
begin
  RebuildLines;
end;

procedure TLabel.DoPaint;
var
  Row, I: Integer;
  S:      string;
begin
  if FFGSet then Term.SetFG(FFG);
  if FBGSet then Term.SetBG(FBG);

  for Row := 1 to Height do
  begin
    GotoLocal(1, Row);
    I := Row - 1;
    if I < FLines.Count then
      S := AlignLine(FLines[I])
    else
      S := StringOfChar(' ', Width);
    Term.WriteStr(S);
    Term.ClearToEOL;
  end;

  Term.ResetColors;
  inherited DoPaint;
end;

end.
