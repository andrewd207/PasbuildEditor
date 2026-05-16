{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.PropertyEditor;

{$mode objfpc}{$H+}

{ TPropertyEditor — scrollable two-column grid: Name | Value.

  Data comes from an abstract TPropertyDataSource.  Two concrete sources are
  provided:

    TStringsDataSource  — wraps a TStrings whose items are 'Name=Value' pairs.
                          Editor type defaults to petText for all rows.
                          Call SetEditorType / SetChoices to override per-row.

    TRTTIDataSource     — reads published properties of any TObject via TypInfo.
                          Strings/integers/floats → petText.
                          Booleans/enumerations  → petFixedCombo (choices auto-
                          populated from type metadata).
                          Sets                   → petSet (checkbox picker popup).

  Editor types (TPropertyEditorType):
    petText        single-line TTextEdit
    petFixedCombo  read-only combo, picks from Choices list
    petDropDown    editable combo (csDropDown style)
    petSet         modal checkbox picker; GetChoices supplies the element names

  Navigation:
    Up / Down / Tab / Shift+Tab   move between rows (wraps, skips disabled)
    Enter                         open / commit the active row's editor
    Escape                        cancel edits and close the editor

  While a row editor is open all key events are forwarded to it.  The editor
  closes (and the value is written back to the data source) when:
    • Enter / OnAccept fires on a TTextEdit
    • A selection is confirmed on a combo
    • Escape / OnCancel fires

  The property editor does NOT own the DataSource — callers are responsible
  for freeing it.
}

interface

uses
  Classes, SysUtils, TypInfo, Contnrs,
  TermUI.Terminal, TermUI.Control, TermUI.Application,
  TermUI.Forms, TermUI.Control.LineEditor, TermUI.Control.ComboBox;

const
  mrOk     = 1;
  mrCancel = 2;

type
  TPropertyEditorType = (petText, petFixedCombo, petDropDown, petSet);

  { ── Data source ── }

  TPropertyDataSource = class
  public
    function  RowCount: Integer; virtual; abstract;
    function  RowName(I: Integer): string; virtual; abstract;
    function  GetValue(I: Integer): string; virtual; abstract;
    procedure SetValue(I: Integer; const AValue: string); virtual; abstract;
    function  EditorType(I: Integer): TPropertyEditorType; virtual;
    { For petFixedCombo / petDropDown: populate AChoices with valid options. }
    procedure GetChoices(I: Integer; AChoices: TStrings); virtual;
    function  IsEnabled(I: Integer): Boolean; virtual;
  end;

  TStringsDataSource = class(TPropertyDataSource)
  private
    FItems:    TStrings;
    FEdTypes:  array of TPropertyEditorType;
    FChoices:  array of TStringList;   { per-row choice lists, owned }
  public
    constructor Create(AItems: TStrings);
    destructor  Destroy; override;

    function  RowCount: Integer; override;
    function  RowName(I: Integer): string; override;
    function  GetValue(I: Integer): string; override;
    procedure SetValue(I: Integer; const AValue: string); override;
    function  EditorType(I: Integer): TPropertyEditorType; override;
    procedure GetChoices(I: Integer; AChoices: TStrings); override;

    { Call before use to set per-row editor type and optional choices. }
    procedure SetEditorType(I: Integer; AType: TPropertyEditorType);
    procedure AddChoice(I: Integer; const AChoice: string);
  end;

  TRTTIDataSource = class(TPropertyDataSource)
  private
    FObject:   TObject;
    FPropList: PPropList;
    FCount:    Integer;
    procedure BuildPropList;
    procedure SetRTTISetValue(PI: PPropInfo; const AValue: string);
  public
    constructor Create(AObject: TObject);
    destructor  Destroy; override;

    function  RowCount: Integer; override;
    function  RowName(I: Integer): string; override;
    function  GetValue(I: Integer): string; override;
    procedure SetValue(I: Integer; const AValue: string); override;
    function  EditorType(I: Integer): TPropertyEditorType; override;
    procedure GetChoices(I: Integer; AChoices: TStrings); override;
  end;

  { ── Set picker popup ── }

  { Modal form that lets the user toggle individual set-element checkboxes.
    Positions itself anchored to AnchorX/AnchorY (top-left of the value cell).
    Returns mrOk when Enter confirms, mrCancel on Escape.
    After ShowModal, read SelectedMask for the resulting bitmask. }
  TSetPickerForm = class(TForm)
  private
    FElements:    TStringList;   { element names, owned }
    FChecked:     array of Boolean;
    FCursor:      Integer;       { focused row (0-based) }
    FTopRow:      Integer;
    FAnchorX:     Integer;
    FAnchorY:     Integer;
    FSelectedMask: Cardinal;

    function  VisibleRows: Integer;
    procedure EnsureVisible;
    procedure DrawRow(AScreenY, AIdx: Integer);
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
  public
    constructor Create(const AElements: TStrings; ACurrentMask: Cardinal;
                       AAnchorX, AAnchorY, AWidth: Integer); reintroduce;
    destructor  Destroy; override;

    property SelectedMask: Cardinal read FSelectedMask;
  end;

  { ── Property editor control ── }

  TPropertyEditor = class(TControl)
  private
    FDataSource:   TPropertyDataSource;
    FActiveRow:    Integer;   { currently highlighted row, -1 = none }
    FTopRow:       Integer;
    FNameWidth:    Integer;   { columns for the name column }
    FEditing:      Boolean;   { True when an inline editor is open }
    FActiveEditor: TControl;  { editor currently open; nil when not editing }

    procedure SetDataSource(AValue: TPropertyDataSource);
    procedure SetNameWidth(AValue: Integer);
    function  VisibleRows: Integer;
    procedure EnsureVisible(ARow: Integer);
    function  NextRow(AFrom, ADir: Integer): Integer;

    procedure OpenEditor;
    procedure OpenSetPicker(ARow, AColX, ARowY, AColW: Integer; AElements: TStrings);
    procedure CommitEditor;
    procedure CancelEditor;
    procedure OnEditorAccept(Sender: TObject);
    procedure OnEditorCancel(Sender: TObject);
    procedure OnComboChange(Sender: TObject);

    procedure DrawRow(AScreenY, ADataRow: Integer);
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
    procedure DoBoundsChanged; override;
  public
    constructor Create; override;
    destructor  Destroy; override;

    procedure Refresh;   { rebuild from DataSource }

    property DataSource: TPropertyDataSource read FDataSource write SetDataSource;
    property NameWidth:  Integer             read FNameWidth  write SetNameWidth;
    property ActiveRow:  Integer             read FActiveRow;
    property Editing:    Boolean             read FEditing;
  end;

implementation

{ ── Helpers ── }

{ Parse a set string like '[llDebug, llWarning]' against an element name list
  and return the corresponding bitmask (bit N set ↔ Elements[N] present). }
function ParseSetMask(const ASetStr: string; AElements: TStrings): Cardinal;
var
  S, Token: string;
  I, P:     Integer;
begin
  Result := 0;
  S := Trim(ASetStr);
  { Strip optional brackets }
  if (Length(S) >= 2) and (S[1] = '[') and (S[Length(S)] = ']') then
    S := Copy(S, 2, Length(S) - 2);
  while S <> '' do
  begin
    P := Pos(',', S);
    if P > 0 then
    begin
      Token := Trim(Copy(S, 1, P - 1));
      S     := Trim(Copy(S, P + 1, MaxInt));
    end
    else
    begin
      Token := Trim(S);
      S     := '';
    end;
    I := AElements.IndexOf(Token);
    if I >= 0 then
      Result := Result or (Cardinal(1) shl I);
  end;
end;

{ Format a bitmask back to '[Elem1, Elem2]' using the element name list. }
function FormatSetMask(AMask: Cardinal; AElements: TStrings): string;
var
  I:    Integer;
  First: Boolean;
begin
  Result := '[';
  First  := True;
  for I := 0 to AElements.Count - 1 do
    if (AMask and (Cardinal(1) shl I)) <> 0 then
    begin
      if not First then Result := Result + ', ';
      Result := Result + AElements[I];
      First  := False;
    end;
  Result := Result + ']';
end;

{ ── TPropertyDataSource defaults ── }

function TPropertyDataSource.EditorType(I: Integer): TPropertyEditorType;
begin
  Result := petText;
end;

procedure TPropertyDataSource.GetChoices(I: Integer; AChoices: TStrings);
begin
  { nothing }
end;

function TPropertyDataSource.IsEnabled(I: Integer): Boolean;
begin
  Result := True;
end;

{ ── TStringsDataSource ── }

constructor TStringsDataSource.Create(AItems: TStrings);
begin
  inherited Create;
  FItems := AItems;
end;

destructor TStringsDataSource.Destroy;
var I: Integer;
begin
  for I := 0 to High(FChoices) do FChoices[I].Free;
  inherited;
end;

function TStringsDataSource.RowCount: Integer;
begin
  Result := FItems.Count;
end;

function TStringsDataSource.RowName(I: Integer): string;
begin
  Result := FItems.Names[I];
  if Result = '' then Result := FItems[I];
end;

function TStringsDataSource.GetValue(I: Integer): string;
begin
  Result := FItems.ValueFromIndex[I];
end;

procedure TStringsDataSource.SetValue(I: Integer; const AValue: string);
begin
  FItems[I] := FItems.Names[I] + '=' + AValue;
end;

function TStringsDataSource.EditorType(I: Integer): TPropertyEditorType;
begin
  if I < Length(FEdTypes) then Result := FEdTypes[I]
  else Result := petText;
end;

procedure TStringsDataSource.GetChoices(I: Integer; AChoices: TStrings);
begin
  if (I >= 0) and (I < Length(FChoices)) and Assigned(FChoices[I]) then
    AChoices.Assign(FChoices[I]);
end;

procedure TStringsDataSource.SetEditorType(I: Integer; AType: TPropertyEditorType);
begin
  if I >= Length(FEdTypes) then SetLength(FEdTypes, I + 1);
  FEdTypes[I] := AType;
end;

procedure TStringsDataSource.AddChoice(I: Integer; const AChoice: string);
begin
  if I >= Length(FChoices) then SetLength(FChoices, I + 1);
  if not Assigned(FChoices[I]) then FChoices[I] := TStringList.Create;
  FChoices[I].Add(AChoice);
end;

{ ── TRTTIDataSource ── }

constructor TRTTIDataSource.Create(AObject: TObject);
begin
  inherited Create;
  FObject := AObject;
  BuildPropList;
end;

destructor TRTTIDataSource.Destroy;
begin
  if Assigned(FPropList) then
    FreeMem(FPropList);
  inherited;
end;

procedure TRTTIDataSource.BuildPropList;
const
  WantedKinds = [tkInteger, tkChar, tkEnumeration, tkFloat,
                 tkString, tkLString, tkAString, tkInt64, tkBool, tkSet];
begin
  if not Assigned(FObject) then Exit;
  FCount := GetPropList(FObject.ClassInfo, WantedKinds, nil);
  if FCount <= 0 then Exit;
  GetMem(FPropList, FCount * SizeOf(Pointer));
  GetPropList(FObject.ClassInfo, WantedKinds, FPropList);
end;

function TRTTIDataSource.RowCount: Integer;
begin
  Result := FCount;
end;

function TRTTIDataSource.RowName(I: Integer): string;
begin
  if (I >= 0) and (I < FCount) then
    Result := FPropList^[I]^.Name
  else
    Result := '';
end;

function TRTTIDataSource.GetValue(I: Integer): string;
var
  PI: PPropInfo;
  K:  TTypeKind;
begin
  Result := '';
  if (I < 0) or (I >= FCount) or not Assigned(FPropList) then Exit;
  PI := FPropList^[I];
  K  := PI^.PropType^.Kind;
  case K of
    tkString, tkLString, tkAString:
      Result := GetStrProp(FObject, PI);
    tkInteger, tkChar:
      Result := IntToStr(GetOrdProp(FObject, PI));
    tkInt64:
      Result := IntToStr(GetInt64Prop(FObject, PI));
    tkFloat:
      Result := FloatToStr(GetFloatProp(FObject, PI));
    tkBool:
      if GetOrdProp(FObject, PI) <> 0 then Result := 'True'
      else Result := 'False';
    tkEnumeration:
      Result := GetEnumProp(FObject, PI);
    tkSet:
      Result := GetSetProp(FObject, PI, True);
  end;
end;

procedure TRTTIDataSource.SetValue(I: Integer; const AValue: string);
var
  PI:  PPropInfo;
  K:   TTypeKind;
  Ext: Extended;
begin
  if (I < 0) or (I >= FCount) or not Assigned(FPropList) then Exit;
  PI := FPropList^[I];
  K  := PI^.PropType^.Kind;
  try
    case K of
      tkString, tkLString, tkAString:
        SetStrProp(FObject, PI, AValue);
      tkInteger, tkChar:
        SetOrdProp(FObject, PI, StrToInt(AValue));
      tkInt64:
        SetInt64Prop(FObject, PI, StrToInt64(AValue));
      tkFloat:
        begin
          if not TryStrToFloat(AValue, Ext) then Exit;
          SetFloatProp(FObject, PI, Ext);
        end;
      tkBool:
        SetOrdProp(FObject, PI,
          Ord((AValue = 'True') or (AValue = 'true') or (AValue = '1')));
      tkEnumeration:
        SetEnumProp(FObject, PI, AValue);
      tkSet:
        SetRTTISetValue(PI, AValue);
    end;
  except
    { Swallow type-conversion errors }
  end;
end;

procedure TRTTIDataSource.SetRTTISetValue(PI: PPropInfo; const AValue: string);
var
  ElemNames: TStringList;
  ElemTD:    PTypeData;
  SetTD:     PTypeData;
  V:         Integer;
  Mask:      Cardinal;
begin
  ElemNames := TStringList.Create;
  try
    SetTD := GetTypeData(PI^.PropType);
    if Assigned(SetTD^.CompType) then
    begin
      ElemTD := GetTypeData(SetTD^.CompType);
      for V := ElemTD^.MinValue to ElemTD^.MaxValue do
        ElemNames.Add(GetEnumName(SetTD^.CompType, V));
    end;
    Mask := ParseSetMask(AValue, ElemNames);
    SetOrdProp(FObject, PI, Int64(Mask));
  finally
    ElemNames.Free;
  end;
end;

function TRTTIDataSource.EditorType(I: Integer): TPropertyEditorType;
var
  K: TTypeKind;
begin
  Result := petText;
  if (I < 0) or (I >= FCount) or not Assigned(FPropList) then Exit;
  K := FPropList^[I]^.PropType^.Kind;
  if K in [tkBool, tkEnumeration] then Result := petFixedCombo
  else if K = tkSet then Result := petSet;
end;

procedure TRTTIDataSource.GetChoices(I: Integer; AChoices: TStrings);
var
  PI: PPropInfo;
  TD: PTypeData;
  K:  TTypeKind;
  V:  Integer;
begin
  if (I < 0) or (I >= FCount) or not Assigned(FPropList) then Exit;
  PI := FPropList^[I];
  K  := PI^.PropType^.Kind;
  if K = tkBool then
  begin
    AChoices.Add('False');
    AChoices.Add('True');
  end
  else if K = tkEnumeration then
  begin
    TD := GetTypeData(PI^.PropType);
    for V := TD^.MinValue to TD^.MaxValue do
      AChoices.Add(GetEnumName(PI^.PropType, V));
  end
  else if K = tkSet then
  begin
    { CompType is the element enumeration type }
    TD := GetTypeData(PI^.PropType);
    if Assigned(TD^.CompType) then
    begin
      TD := GetTypeData(TD^.CompType);
      for V := TD^.MinValue to TD^.MaxValue do
        AChoices.Add(GetEnumName(GetTypeData(PI^.PropType)^.CompType, V));
    end;
  end;
end;

{ ── TSetPickerForm ── }

constructor TSetPickerForm.Create(const AElements: TStrings; ACurrentMask: Cardinal;
  AAnchorX, AAnchorY, AWidth: Integer);
const
  MaxRows = 12;
var
  I:      Integer;
  H:      Integer;
  TermH:  Integer;
begin
  inherited Create('');
  FElements := TStringList.Create;
  FElements.Assign(AElements);
  SetLength(FChecked, FElements.Count);
  for I := 0 to FElements.Count - 1 do
    FChecked[I] := (ACurrentMask and (Cardinal(1) shl I)) <> 0;
  FCursor      := 0;
  FTopRow      := 0;
  FAnchorX     := AAnchorX;
  FAnchorY     := AAnchorY;
  FSelectedMask := ACurrentMask;

  H := FElements.Count;
  if H > MaxRows then H := MaxRows;
  TermH := Term.Height;
  { Prefer below; flip above if not enough space }
  if FAnchorY + H > TermH then
    inherited SetBounds(FAnchorX, FAnchorY - H, AWidth, H)
  else
    inherited SetBounds(FAnchorX, FAnchorY, AWidth, H);
end;

destructor TSetPickerForm.Destroy;
begin
  FElements.Free;
  inherited;
end;

function TSetPickerForm.VisibleRows: Integer;
begin
  Result := Height;
  if Result < 1 then Result := 1;
end;

procedure TSetPickerForm.EnsureVisible;
var VR: Integer;
begin
  VR := VisibleRows;
  if FCursor < FTopRow then FTopRow := FCursor
  else if FCursor >= FTopRow + VR then FTopRow := FCursor - VR + 1;
  if FTopRow < 0 then FTopRow := 0;
end;

procedure TSetPickerForm.DrawRow(AScreenY, AIdx: Integer);
var
  IsSel: Boolean;
  Check: string;
  Name:  string;
  Line:  string;
begin
  IsSel := AIdx = FCursor;
  if FChecked[AIdx] then Check := '[x] '
  else Check := '[ ] ';
  Name := FElements[AIdx];

  if IsSel then
  begin
    Term.SetFG(clBlack);
    Term.SetBG(clCyan);
  end
  else
    Term.ResetColors;

  Term.GotoXY(Left, Top + AScreenY - 1);
  Line := Check + Name;
  while Length(Line) < Width do Line := Line + ' ';
  if Length(Line) > Width then Line := Copy(Line, 1, Width);
  Term.WriteStr(Line);
  Term.ResetColors;
end;

procedure TSetPickerForm.DoPaint;
var
  VR, I, Idx: Integer;
begin
  Term.ResetColors;
  VR := VisibleRows;
  for I := 0 to VR - 1 do
  begin
    Idx := FTopRow + I;
    if Idx < FElements.Count then
      DrawRow(I + 1, Idx)
    else
    begin
      Term.GotoXY(Left, Top + I);
      Term.WriteStr(StringOfChar(' ', Width));
    end;
  end;
end;

function TSetPickerForm.DoKeyDown(var Key: TKeyEvent): Boolean;
var
  I: Integer;
begin
  Result := True;
  case Key.Code of
    kcUp:
    begin
      if FCursor > 0 then
      begin
        Dec(FCursor);
        EnsureVisible;
        Invalidate;
      end;
    end;
    kcDown:
    begin
      if FCursor < FElements.Count - 1 then
      begin
        Inc(FCursor);
        EnsureVisible;
        Invalidate;
      end;
    end;
    kcChar:
      if Key.Ch = ' ' then
      begin
        FChecked[FCursor] := not FChecked[FCursor];
        Invalidate;
      end
      else
        Result := False;
    kcEnter:
    begin
      FSelectedMask := 0;
      for I := 0 to FElements.Count - 1 do
        if FChecked[I] then
          FSelectedMask := FSelectedMask or (Cardinal(1) shl I);
      Close(mrOk);
    end;
    kcEscape:
      Close(mrCancel);
  else
    Result := False;
  end;
end;

{ ── TPropertyEditor ── }

constructor TPropertyEditor.Create;
begin
  inherited Create;
  FActiveRow  := -1;
  FTopRow     := 0;
  FNameWidth  := 20;
  FEditing    := False;
  FActiveEditor := nil;
  Focusable   := True;
end;

destructor TPropertyEditor.Destroy;
begin
  FreeAndNil(FActiveEditor);
  inherited;
end;

procedure TPropertyEditor.SetDataSource(AValue: TPropertyDataSource);
begin
  FDataSource   := AValue;
  FActiveRow    := -1;
  FTopRow       := 0;
  FEditing      := False;
  FreeAndNil(FActiveEditor);
  if Assigned(FDataSource) and (FDataSource.RowCount > 0) then
    FActiveRow := NextRow(-1, +1);
  Invalidate;
end;

procedure TPropertyEditor.SetNameWidth(AValue: Integer);
begin
  if AValue < 4 then AValue := 4;
  FNameWidth := AValue;
  Invalidate;
end;

function TPropertyEditor.VisibleRows: Integer;
begin
  Result := Height;
  if Result < 1 then Result := 1;
end;

procedure TPropertyEditor.EnsureVisible(ARow: Integer);
var VR: Integer;
begin
  VR := VisibleRows;
  if ARow < FTopRow then FTopRow := ARow
  else if ARow >= FTopRow + VR then FTopRow := ARow - VR + 1;
  if FTopRow < 0 then FTopRow := 0;
end;

function TPropertyEditor.NextRow(AFrom, ADir: Integer): Integer;
var
  I, Total: Integer;
begin
  if not Assigned(FDataSource) then Exit(-1);
  Total := FDataSource.RowCount;
  I := AFrom + ADir;
  while (I >= 0) and (I < Total) do
  begin
    if FDataSource.IsEnabled(I) then Exit(I);
    Inc(I, ADir);
  end;
  Result := -1;
end;

{ ── Editor lifecycle ── }

procedure TPropertyEditor.OpenEditor;
var
  ET:      TPropertyEditorType;
  Choices: TStringList;
  Combo:   TComboBox;
  Edit:    TTextEdit;
  ColX:    Integer;
  RowY:    Integer;
  ColW:    Integer;
begin
  if not Assigned(FDataSource) or (FActiveRow < 0) then Exit;
  if FEditing then CommitEditor;

  ET   := FDataSource.EditorType(FActiveRow);
  ColX := Left + FNameWidth + 1;   { +1 for separator '|' }
  RowY := Top  + (FActiveRow - FTopRow);
  ColW := Width - FNameWidth - 1;
  if ColW < 1 then Exit;

  case ET of
    petText:
    begin
      Edit := TTextEdit.Create;
      Edit.SetBounds(ColX, RowY, ColW, 1);
      Edit.Text      := FDataSource.GetValue(FActiveRow);
      Edit.OnAccept  := @OnEditorAccept;
      Edit.OnCancel  := @OnEditorCancel;
      FActiveEditor  := Edit;
    end;

    petFixedCombo, petDropDown:
    begin
      Choices := TStringList.Create;
      try
        FDataSource.GetChoices(FActiveRow, Choices);
        Combo := TComboBox.Create;
        Combo.SetBounds(ColX, RowY, ColW, 1);
        if ET = petDropDown then Combo.Style := csDropDown
        else Combo.Style := csFixed;
        Combo.Items.Assign(Choices);
        Combo.RequireValidSelection := True;
        { Pre-select current value }
        Combo.SelectedIndex := Combo.Items.IndexOf(FDataSource.GetValue(FActiveRow));
        Combo.OnChange := @OnComboChange;
        FActiveEditor  := Combo;
      finally
        Choices.Free;
      end;
    end;

    petSet:
    begin
      { Modal picker — runs synchronously, no inline editor left open }
      Choices := TStringList.Create;
      try
        FDataSource.GetChoices(FActiveRow, Choices);
        if Choices.Count > 0 then
        begin
          OpenSetPicker(FActiveRow, ColX, RowY, ColW, Choices);
        end;
      finally
        Choices.Free;
      end;
      Exit;  { OpenSetPicker already committed/cancelled }
    end;
  end;

  if Assigned(FActiveEditor) then
  begin
    FEditing := True;
    FActiveEditor.GainFocus;
    Invalidate;
  end;
end;

procedure TPropertyEditor.OpenSetPicker(ARow, AColX, ARowY, AColW: Integer;
  AElements: TStrings);
var
  Picker:      TSetPickerForm;
  CurrentMask: Cardinal;
  NewValue:    string;
  Res:         Integer;
begin
  CurrentMask := ParseSetMask(FDataSource.GetValue(ARow), AElements);
  Picker := TSetPickerForm.Create(AElements, CurrentMask, AColX, ARowY, AColW);
  try
    Res := Application.ShowModal(Picker);
    if Res = mrOk then
    begin
      NewValue := FormatSetMask(Picker.SelectedMask, AElements);
      FDataSource.SetValue(ARow, NewValue);
    end;
  finally
    Picker.Free;
  end;
  Invalidate;
end;

procedure TPropertyEditor.CommitEditor;
var
  Edit:  TTextEdit;
  Combo: TComboBox;
begin
  if not FEditing or not Assigned(FActiveEditor) then Exit;
  if FActiveEditor is TTextEdit then
  begin
    Edit := TTextEdit(FActiveEditor);
    FDataSource.SetValue(FActiveRow, Edit.Text);
  end
  else if FActiveEditor is TComboBox then
  begin
    Combo := TComboBox(FActiveEditor);
    if Combo.SelectedIndex >= 0 then
      FDataSource.SetValue(FActiveRow, Combo.SelectedText);
  end;
  FEditing := False;
  FActiveEditor.LoseFocus;
  FreeAndNil(FActiveEditor);
  Invalidate;
end;

procedure TPropertyEditor.CancelEditor;
begin
  if not FEditing then Exit;
  FEditing := False;
  FActiveEditor.LoseFocus;
  FreeAndNil(FActiveEditor);
  Invalidate;
end;

procedure TPropertyEditor.OnEditorAccept(Sender: TObject);
begin
  CommitEditor;
end;

procedure TPropertyEditor.OnEditorCancel(Sender: TObject);
begin
  CancelEditor;
end;

procedure TPropertyEditor.OnComboChange(Sender: TObject);
begin
  CommitEditor;
end;

{ ── Painting ── }

procedure TPropertyEditor.DrawRow(AScreenY, ADataRow: Integer);
var
  IsActive: Boolean;
  IsDis:    Boolean;
  Name:     string;
  Val:      string;
  NameCol:  Integer;
  ValCol:   Integer;
  Line:     string;
begin
  IsActive := (ADataRow = FActiveRow);
  IsDis    := Assigned(FDataSource) and not FDataSource.IsEnabled(ADataRow);

  NameCol := FNameWidth;
  ValCol  := Width - FNameWidth - 1;  { -1 for '|' separator }
  if ValCol < 0 then ValCol := 0;

  Name := '';
  Val  := '';
  if Assigned(FDataSource) then
  begin
    Name := FDataSource.RowName(ADataRow);
    if not FEditing or (ADataRow <> FActiveRow) then
      Val := FDataSource.GetValue(ADataRow);
  end;

  { Truncate name }
  if Length(Name) > NameCol then Name := Copy(Name, 1, NameCol);
  while Length(Name) < NameCol do Name := Name + ' ';

  GotoLocal(1, AScreenY);

  if IsActive and not IsDis then
  begin
    Term.SetFG(clBlack);
    Term.SetBG(clCyan);
  end
  else if IsDis then
    Term.SetFG(clBrightBlack)
  else
    Term.ResetColors;

  { Name column }
  Term.WriteStr(Name);

  { Separator }
  if IsActive and not IsDis then Term.SetBG(clCyan)
  else Term.ResetColors;
  Term.WriteStr('|');

  { Value column — skip if the editor is actively painting here }
  if FEditing and IsActive then
  begin
    { Clear the value area so the editor can paint over it cleanly }
    Term.WriteStr(StringOfChar(' ', ValCol));
  end
  else
  begin
    if IsActive and not IsDis then
    begin
      Term.SetFG(clBlack);
      Term.SetBG(clCyan);
    end
    else if IsDis then
      Term.SetFG(clBrightBlack)
    else
      Term.ResetColors;
    Line := Val;
    if Length(Line) > ValCol then Line := Copy(Line, 1, ValCol);
    while Length(Line) < ValCol do Line := Line + ' ';
    Term.WriteStr(Line);
  end;

  Term.ResetColors;
end;

procedure TPropertyEditor.DoPaint;
var
  VR, I, Idx: Integer;
begin
  if not Assigned(FDataSource) then
  begin
    Term.ResetColors;
    for I := 1 to Height do
    begin
      GotoLocal(1, I);
      Term.WriteStr(StringOfChar(' ', Width));
    end;
    Exit;
  end;

  Term.ResetColors;
  VR := VisibleRows;

  for I := 0 to VR - 1 do
  begin
    Idx := FTopRow + I;
    if Idx < FDataSource.RowCount then
      DrawRow(I + 1, Idx)
    else
    begin
      GotoLocal(1, I + 1);
      Term.WriteStr(StringOfChar(' ', Width));
    end;
  end;

  { Let the active editor paint over its row }
  if FEditing and Assigned(FActiveEditor) then
    FActiveEditor.Paint;
end;

{ ── Input ── }

function TPropertyEditor.DoKeyDown(var Key: TKeyEvent): Boolean;
var
  NewRow: Integer;
begin
  Result := True;

  { Forward all keys to active editor first }
  if FEditing and Assigned(FActiveEditor) then
  begin
    if FActiveEditor.KeyDown(Key) then Exit;
    { Editor didn't consume — check for navigation/escape at our level }
    if Key.Code = kcEscape then
    begin
      CancelEditor;
      Exit;
    end;
    { Tab commits and moves to next row }
    if Key.Code in [kcTab, kcShiftTab] then
    begin
      CommitEditor;
      { fall through to navigate }
    end
    else
      Exit;
  end;

  case Key.Code of
    kcUp:
    begin
      NewRow := NextRow(FActiveRow, -1);
      if NewRow >= 0 then
      begin
        FActiveRow := NewRow;
        EnsureVisible(FActiveRow);
        Invalidate;
      end;
    end;

    kcDown:
    begin
      NewRow := NextRow(FActiveRow, +1);
      if NewRow >= 0 then
      begin
        FActiveRow := NewRow;
        EnsureVisible(FActiveRow);
        Invalidate;
      end;
    end;

    kcTab:
    begin
      NewRow := NextRow(FActiveRow, +1);
      if NewRow < 0 then NewRow := NextRow(-1, +1);  { wrap }
      if NewRow >= 0 then
      begin
        FActiveRow := NewRow;
        EnsureVisible(FActiveRow);
        Invalidate;
      end;
    end;

    kcShiftTab:
    begin
      if Assigned(FDataSource) then
        NewRow := NextRow(FActiveRow, -1)
      else
        NewRow := -1;
      if NewRow < 0 then
        NewRow := NextRow(FDataSource.RowCount, -1);  { wrap to last }
      if NewRow >= 0 then
      begin
        FActiveRow := NewRow;
        EnsureVisible(FActiveRow);
        Invalidate;
      end;
    end;

    kcEnter:
      OpenEditor;

    kcPageUp:
    begin
      FTopRow := FTopRow - VisibleRows;
      if FTopRow < 0 then FTopRow := 0;
      FActiveRow := FTopRow;
      Invalidate;
    end;

    kcPageDown:
    begin
      if Assigned(FDataSource) then
      begin
        FTopRow := FTopRow + VisibleRows;
        if FTopRow >= FDataSource.RowCount then
          FTopRow := FDataSource.RowCount - 1;
        FActiveRow := FTopRow;
        EnsureVisible(FActiveRow);
        Invalidate;
      end;
    end;

  else
    Result := False;
  end;
end;

procedure TPropertyEditor.DoBoundsChanged;
begin
  if FEditing and Assigned(FActiveEditor) then
    CancelEditor;
end;

procedure TPropertyEditor.Refresh;
begin
  FActiveRow := -1;
  FTopRow    := 0;
  FEditing   := False;
  FreeAndNil(FActiveEditor);
  if Assigned(FDataSource) and (FDataSource.RowCount > 0) then
    FActiveRow := NextRow(-1, +1);
  Invalidate;
end;

end.
