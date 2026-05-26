{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.ColorPicker;

{$mode objfpc}{$H+}

{ TColorPicker — 2D color grid + hex edit field returning a TColor.

  Layout (fills available bounds):

      ┌── grid ───────────────────────────────────────────┐
      │ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ │ row 0 (lightness ~0)
      │ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ │
      │ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ │ middle rows
      │ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ │ (full saturation)
      │ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ ░░ │ row N (lightness ~1)
      ├───────────────────────────────────────────────────┤
      │ #RRGGBB  rgb(R,G,B)   [clMidGreen]                │ status line
      │ Hex: [______]    Sample: ░░                       │ editable input
      └───────────────────────────────────────────────────┘

  Each cell maps a grid position (gx, gy) to a 24-bit RGB color via HSL:
    hue        = gx / (cellsW - 1) * 360°
    lightness  = gy / (cellsH - 1)
    saturation = 1 - |2*lightness - 1|

  Result: top row is black, bottom row is white, middle rows are a fully
  saturated rainbow.  Every cell is a true RGB color, so the picker reaches
  any 24-bit value the terminal can render (when SupportsTrueColor is true)
  — and the hex field reaches the rest (decimal, $hex, 0xhex input).

  Keys:
    Arrow keys           navigate grid (when grid is focused)
    Enter (in grid)      copy current grid color's hex into the field
                         and switch focus to the field
    Enter (in field)     parse the field, fire OnActivate(parsed color)
    Tab                  toggle focus between grid and field
    Esc                  no-op here; the host form should handle cancel

  Modal helper:
    if TColorPicker.PickColor(MyColor) then ...
}

interface

uses
  Classes, SysUtils, Math, TypInfo,
  TermUI.Terminal, TermUI.Control, TermUI.Application, TermUI.Forms;

type
  TColorPickerEvent = procedure(Sender: TObject; AColor: TColor) of object;

  TColorPicker = class(TControl)
  private
    FCellW:       Integer;   { width in chars of one swatch (default 2) }
    FGridX:       Integer;   { grid cursor }
    FGridY:       Integer;
    FCellsW:      Integer;   { recomputed in DoBoundsChanged }
    FCellsH:      Integer;
    FFocusField:  Boolean;
    FHexText:     string;
    FCaret:       Integer;   { 1-based caret position in FHexText }
    FParsed:      TColor;
    FParsedOk:    Boolean;
    FOnActivate:         TColorPickerEvent;
    FOnSelectionChanged: TColorPickerEvent;

    procedure RecomputeLayout;
    function  GridColor(GX, GY: Integer): TColor;
    function  HslToRGB(H, S, L: Double): TColor;
    function  HexOf(C: TColor): string;
    function  CurrentDisplayColor: TColor;
    procedure UpdateParsed;
    function  ParseInput(const S: string; out AColor: TColor): Boolean;
    function  MatchedName(C: TColor): string;

    procedure DrawGrid;
    procedure DrawStatus;
    procedure DrawField;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
    procedure DoBoundsChanged; override;
  public
    constructor Create; override;

    function  SelectedColor: TColor;
    procedure SetInitial(AColor: TColor);

    property OnActivate:         TColorPickerEvent read FOnActivate
                                                    write FOnActivate;
    property OnSelectionChanged: TColorPickerEvent read FOnSelectionChanged
                                                    write FOnSelectionChanged;

    class function PickColor(out AResult: TColor;
      AInitial: TColor = 0;   { 0 = clDefault; can't use the typed const as a default }
      const ATitle: string = 'Pick a color'): Boolean;
  end;

implementation

const
  CMinCellsW = 4;
  CMinCellsH = 3;
  CStatusRows = 2;   { status line + hex field row }

constructor TColorPicker.Create;
begin
  inherited Create;
  FCellW      := 2;
  FGridX      := 0;
  FGridY      := 0;
  FFocusField := False;
  FHexText    := '#000000';
  FCaret      := Length(FHexText) + 1;
  UpdateParsed;
end;

procedure TColorPicker.RecomputeLayout;
begin
  FCellsW := Width div FCellW;
  FCellsH := Height - CStatusRows;
  if FCellsW < CMinCellsW then FCellsW := CMinCellsW;
  if FCellsH < CMinCellsH then FCellsH := CMinCellsH;
  if FGridX >= FCellsW then FGridX := FCellsW - 1;
  if FGridY >= FCellsH then FGridY := FCellsH - 1;
end;

procedure TColorPicker.DoBoundsChanged;
begin
  inherited;
  RecomputeLayout;
end;

{ ── Color math ── }

function TColorPicker.HslToRGB(H, S, L: Double): TColor;
var
  C, X, M, R, G, B: Double;
  Hp: Double;
begin
  C := (1 - Abs(2 * L - 1)) * S;
  Hp := H / 60.0;
  X := C * (1 - Abs(FMod(Hp, 2.0) - 1));
  if      Hp < 1 then begin R := C; G := X; B := 0; end
  else if Hp < 2 then begin R := X; G := C; B := 0; end
  else if Hp < 3 then begin R := 0; G := C; B := X; end
  else if Hp < 4 then begin R := 0; G := X; B := C; end
  else if Hp < 5 then begin R := X; G := 0; B := C; end
  else                begin R := C; G := 0; B := X; end;
  M := L - C / 2;
  Result := RGB(Round((R + M) * 255), Round((G + M) * 255), Round((B + M) * 255));
end;

function TColorPicker.GridColor(GX, GY: Integer): TColor;
var Hue, Lit, Sat: Double;
begin
  if FCellsW <= 1 then Hue := 0
  else                 Hue := GX / (FCellsW - 1) * 360.0;
  if FCellsH <= 1 then Lit := 0.5
  else                 Lit := GY / (FCellsH - 1);
  Sat := 1.0 - Abs(2.0 * Lit - 1.0);
  Result := HslToRGB(Hue, Sat, Lit);
end;

function TColorPicker.HexOf(C: TColor): string;
var R, G, B: Byte;
begin
  if IsRGB(C) then begin R := RedOf(C); G := GreenOf(C); B := BlueOf(C); end
  else begin
    { Resolve a palette entry to a representative RGB via the cube/grey ramp
      so the hex string is always meaningful. }
    if PaletteOf(C) = p8Default then begin R := 0; G := 0; B := 0; end
    else begin
      { Roundtrip: not perfect for ANSI 0..15 (terminal-themed), but fine for
        the cube entries that the grid is built on. }
      R := RedOf(C); G := GreenOf(C); B := BlueOf(C);
    end;
  end;
  Result := Format('#%.2x%.2x%.2x', [R, G, B]);
end;

function TColorPicker.CurrentDisplayColor: TColor;
begin
  if FFocusField and FParsedOk then
    Result := FParsed
  else
    Result := GridColor(FGridX, FGridY);
end;

{ ── Hex / decimal parsing ── }

function HexDigit(C: Char; out V: Integer): Boolean;
begin
  Result := True;
  case C of
    '0'..'9': V := Ord(C) - Ord('0');
    'a'..'f': V := Ord(C) - Ord('a') + 10;
    'A'..'F': V := Ord(C) - Ord('A') + 10;
  else
    Result := False;
  end;
end;

function ParseHexBody(const S: string; out V: LongInt): Boolean;
var I, D: Integer;
begin
  Result := False;
  if S = '' then Exit;
  V := 0;
  for I := 1 to Length(S) do
  begin
    if not HexDigit(S[I], D) then Exit;
    V := (V shl 4) or D;
  end;
  Result := True;
end;

function TColorPicker.ParseInput(const S: string; out AColor: TColor): Boolean;
var
  T: string;
  V, Code: LongInt;
begin
  Result := False;
  T := Trim(S);
  if T = '' then Exit;

  { Hex forms: $RRGGBB, 0xRRGGBB, #RRGGBB → always interpreted as truecolor RGB }
  if (T[1] = '$') or ((Length(T) >= 2) and (T[1] = '0') and (LowerCase(T[2]) = 'x'))
     or (T[1] = '#') then
  begin
    if      T[1] = '$' then T := Copy(T, 2, MaxInt)
    else if T[1] = '#' then T := Copy(T, 2, MaxInt)
    else                    T := Copy(T, 3, MaxInt);
    if not ParseHexBody(T, V) then Exit;
    AColor := RGB((V shr 16) and $FF, (V shr 8) and $FF, V and $FF);
    Result := True;
    Exit;
  end;

  { Decimal: <= 257 → palette index; otherwise → raw TColor }
  Val(T, V, Code);
  if Code <> 0 then Exit;
  if (V >= 0) and (V <= 257) then
    AColor := TColor(V)
  else
    AColor := TColor(V);
  Result := True;
end;

procedure TColorPicker.UpdateParsed;
begin
  FParsedOk := ParseInput(FHexText, FParsed);
end;

{ ── Named-color reverse lookup ── }

function TColorPicker.MatchedName(C: TColor): string;
var
  P: T8BitColor;
  N: string;
begin
  Result := '';
  if IsRGB(C) then Exit;            { only palette entries map to a cl* name }
  P := PaletteOf(C);
  N := GetEnumName(TypeInfo(T8BitColor), Ord(P));
  if N = '' then Exit;
  { strip the p8 prefix }
  if (Length(N) > 2) and (N[1] = 'p') and (N[2] = '8') then
    Delete(N, 1, 2);
  { skip the unnamed Xterm* entries — they have no friendly cl* name }
  if (Length(N) >= 5) and (Copy(N, 1, 5) = 'Xterm') then Exit;
  Result := 'cl' + N;
end;

{ ── Painting ── }

procedure TColorPicker.DrawGrid;
var
  GX, GY, X, I: Integer;
  C: TColor;
  IsCur: Boolean;
begin
  for GY := 0 to FCellsH - 1 do
  begin
    GotoLocal(1, GY + 1);
    for GX := 0 to FCellsW - 1 do
    begin
      C := GridColor(GX, GY);
      IsCur := (GX = FGridX) and (GY = FGridY) and (not FFocusField);
      Term.SetBG(C);
      if IsCur then
      begin
        { brackets to mark the selection — visible on any color }
        Term.SetFG(clBlack);
        Term.WriteStr('[]');
      end
      else
      begin
        Term.SetFG(C);
        Term.WriteStr('  ');
      end;
    end;
    Term.ResetColors;
    { trailing pad — clear any partial cell columns }
    X := FCellsW * FCellW;
    for I := X + 1 to Width do Term.WriteStr(' ');
  end;
end;

procedure TColorPicker.DrawStatus;
var
  Y: Integer;
  C: TColor;
  S, Nm: string;
begin
  Y := FCellsH + 1;
  C := CurrentDisplayColor;

  GotoLocal(1, Y);
  Term.ResetColors;
  S := HexOf(C) + '   rgb(' + IntToStr(RedOf(C)) + ',' + IntToStr(GreenOf(C))
       + ',' + IntToStr(BlueOf(C)) + ')';
  Nm := MatchedName(C);
  if Nm <> '' then S := S + '   [' + Nm + ']';
  if Length(S) > Width then S := Copy(S, 1, Width);
  Term.WriteStr(S);
  for Y := Length(S) + 1 to Width do Term.WriteStr(' ');
end;

procedure TColorPicker.DrawField;
var
  Y, FieldX, FieldW, SampleX, SampleW, I: Integer;
  C: TColor;
  Label_, SampleLabel: string;
begin
  Y := FCellsH + 2;
  GotoLocal(1, Y);
  Term.ResetColors;
  Label_      := 'Hex: ';
  SampleLabel := '  Sample: ';
  Term.WriteStr(Label_);

  FieldX := Length(Label_) + 1;
  FieldW := 12;
  if FieldX + FieldW > Width - (Length(SampleLabel) + 4) then
    FieldW := Width - (Length(SampleLabel) + 4) - FieldX;
  if FieldW < 4 then FieldW := 4;

  { field box }
  if FFocusField then
  begin
    Term.SetFG(clBlack); Term.SetBG(clWhite);
  end
  else
  begin
    Term.SetFG(clBrightBlack); Term.SetBG(clDefault);
  end;
  Term.WriteStr('[');
  if Length(FHexText) > FieldW - 2 then
    Term.WriteStr(Copy(FHexText, 1, FieldW - 2))
  else
  begin
    Term.WriteStr(FHexText);
    for I := Length(FHexText) + 1 to FieldW - 2 do Term.WriteStr(' ');
  end;
  Term.WriteStr(']');
  Term.ResetColors;

  { sample — takes all remaining horizontal space }
  Term.WriteStr(SampleLabel);
  SampleX := FieldX + FieldW + Length(SampleLabel);
  SampleW := Width - SampleX + 1;
  if SampleW < 2 then SampleW := 2;

  if FFocusField and FParsedOk then C := FParsed
  else if FFocusField           then C := clDefault
  else                               C := GridColor(FGridX, FGridY);

  if FFocusField and (not FParsedOk) then
  begin
    Term.SetFG(clBrightRed);
    Term.WriteStr(' invalid hex/value');
    for I := Length(' invalid hex/value') + 1 to SampleW do Term.WriteStr(' ');
  end
  else
  begin
    Term.SetBG(C); Term.SetFG(C);
    for I := 1 to SampleW do Term.WriteStr(' ');
  end;
  Term.ResetColors;

  { place text-cursor in field when focused, for visual caret feedback }
  if FFocusField then
  begin
    I := FCaret;
    if I < 1 then I := 1;
    if I > FieldW - 1 then I := FieldW - 1;
    Term.PlaceCursor(Left + FieldX + I - 1, Top + Y - 1);
  end;
end;

procedure TColorPicker.DoPaint;
begin
  if (FCellsW = 0) or (FCellsH = 0) then RecomputeLayout;
  Term.ResetColors;
  DrawGrid;
  DrawStatus;
  DrawField;
end;

{ ── Input ── }

function TColorPicker.DoKeyDown(var Key: TKeyEvent): Boolean;
var
  OldX, OldY: Integer;
  Notify:     Boolean;
begin
  Result := True;
  Notify := False;

  if FFocusField then
  begin
    case Key.Code of
      kcTab:
        FFocusField := False;
      kcEnter:
        begin
          UpdateParsed;
          if FParsedOk and Assigned(FOnActivate) then
            FOnActivate(Self, FParsed);
        end;
      kcBackspace:
        if FCaret > 1 then
        begin
          Delete(FHexText, FCaret - 1, 1);
          Dec(FCaret);
          UpdateParsed;
        end;
      kcDelete:
        if FCaret <= Length(FHexText) then
        begin
          Delete(FHexText, FCaret, 1);
          UpdateParsed;
        end;
      kcLeft:
        if FCaret > 1 then Dec(FCaret);
      kcRight:
        if FCaret <= Length(FHexText) then Inc(FCaret);
      kcHome:
        FCaret := 1;
      kcEnd:
        FCaret := Length(FHexText) + 1;
      kcChar:
        begin
          Insert(Key.Ch, FHexText, FCaret);
          Inc(FCaret, Length(Key.Ch));
          UpdateParsed;
        end;
    else
      Result := False;
    end;
  end
  else
  begin
    OldX := FGridX; OldY := FGridY;
    case Key.Code of
      kcTab:    FFocusField := True;
      kcLeft:   if FGridX > 0            then Dec(FGridX);
      kcRight:  if FGridX < FCellsW - 1  then Inc(FGridX);
      kcUp:     if FGridY > 0            then Dec(FGridY);
      kcDown:   if FGridY < FCellsH - 1  then Inc(FGridY);
      kcHome:   begin FGridX := 0; FGridY := 0; end;
      kcEnd:    begin FGridX := FCellsW - 1; FGridY := FCellsH - 1; end;
      kcEnter:
        begin
          FHexText    := HexOf(GridColor(FGridX, FGridY));
          FCaret      := Length(FHexText) + 1;
          FFocusField := True;
          UpdateParsed;
        end;
    else
      Result := False;
    end;
    if (FGridX <> OldX) or (FGridY <> OldY) then Notify := True;
  end;

  if Result then
  begin
    if Notify and Assigned(FOnSelectionChanged) then
      FOnSelectionChanged(Self, CurrentDisplayColor);
    Invalidate;
  end;
end;

function TColorPicker.SelectedColor: TColor;
begin
  if FFocusField and FParsedOk then
    Result := FParsed
  else
    Result := GridColor(FGridX, FGridY);
end;

procedure TColorPicker.SetInitial(AColor: TColor);
begin
  FHexText := HexOf(AColor);
  FCaret   := Length(FHexText) + 1;
  UpdateParsed;
  Invalidate;
end;

{ ── Modal helper ── }

type
  TPickerForm = class(TForm)
  private
    FPicker: TColorPicker;
    procedure OnAccepted(Sender: TObject; AColor: TColor);
  protected
    procedure ArrangeChildren; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
  public
    constructor Create(const ATitle: string); override;
    property Picker: TColorPicker read FPicker;
  end;

constructor TPickerForm.Create(const ATitle: string);
begin
  inherited Create(ATitle);
  FPicker := TColorPicker.Create;
  FPicker.OnActivate := @OnAccepted;
  AddChild(FPicker);
end;

procedure TPickerForm.ArrangeChildren;
begin
  if Assigned(FPicker) then
    FPicker.SetBounds(Left + 1, Top + 1, Width - 2, Height - 2);
end;

procedure TPickerForm.OnAccepted(Sender: TObject; AColor: TColor);
begin
  Close(1);
end;

function TPickerForm.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  Result := True;
  case Key.Code of
    kcEscape: CloseCancel;
  else
    Result := inherited DoKeyDown(Key);
  end;
end;

class function TColorPicker.PickColor(out AResult: TColor;
  AInitial: TColor; const ATitle: string): Boolean;
var
  Form: TPickerForm;
  W, H, X, Y, MR: Integer;
begin
  Result := False;
  AResult := AInitial;
  W := Term.Width  - 4;  if W > 64 then W := 64;
  H := Term.Height - 4;  if H > 24 then H := 24;
  X := (Term.Width  - W) div 2 + 1;
  Y := (Term.Height - H) div 2 + 1;
  Form := TPickerForm.Create(ATitle);
  try
    Form.SetBounds(X, Y, W, H);
    Form.Picker.SetInitial(AInitial);
    MR := Application.ShowModal(Form);
    if MR = 1 then
    begin
      AResult := Form.Picker.SelectedColor;
      Result := True;
    end;
  finally
    Form.Free;
  end;
end;

end.
