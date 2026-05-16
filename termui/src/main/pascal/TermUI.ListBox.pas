{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.ListBox;

{$mode objfpc}{$H+}
{$interfaces corba}

{ TListBox — a scrollable single-selection list of string items.

  Items is a TObservedStringList.  TListBox implements ITermUIObserver and
  attaches itself to the list automatically.  Any mutation to Items fires the
  appropriate notification and the listbox recalculates and repaints itself:
    ooBeginUpdate → set suppress flag (defer repaint)
    ooAdd/ooInsert → grow enabled array; repaint if not suppressed
    ooDelete       → shrink enabled array; clamp selection; repaint
    ooClear        → reset everything; repaint
    ooChange       → repaint the affected row
    ooEndUpdate    → clear suppress flag; full repaint
    ooFreeing      → detach from the list

  Individual items can be disabled via ItemEnabled[]; disabled items are
  skipped during keyboard navigation and rendered in dim colour.

  Key bindings:
    Up / Down     move selection (skips disabled items)
    Home / End    first / last enabled item
    PgUp / PgDn   page up / page down
    Enter         fire OnActivate
}

interface

uses
  Classes, SysUtils,
  TermUI.Terminal, TermUI.Control, TermUI.Application,
  TermUI.Observer, TermUI.ObservedStringList;

type
  TListBoxItemEvent = procedure(Sender: TObject; Index: Integer) of object;

  TListBox = class(TControl, ITermUIObserver)
  private
    FItems:      TObservedStringList;
    FEnabled:    array of Boolean;
    FSel:        Integer;
    FTopRow:     Integer;
    FSuppressed: Boolean;   { True between ooBeginUpdate and ooEndUpdate }

    FOnSelectionChanged: TListBoxItemEvent;
    FOnActivate:         TListBoxItemEvent;

    function  GetItemEnabled(I: Integer): Boolean;
    procedure SetItemEnabled(I: Integer; AValue: Boolean);
    function  GetItemCount: Integer;
    function  VisibleRows: Integer;
    procedure EnsureVisible;
    procedure SyncEnabledArray;
    procedure GrowEnabledArray(ANewIndex: Integer);
    procedure ShrinkEnabledArray(ADeletedIndex: Integer);
    function  NextEnabled(AFrom, ADir: Integer): Integer;
    procedure DrawRow(Row, Idx: Integer);
    procedure DrawScrollBar;

  protected
    { ITermUIObserver }
    procedure ObservedChanged(ASender: TObject;
                              ANotify: TObserverNotification);

    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
    procedure DoBoundsChanged; override;

  public
    constructor Create; override;
    destructor  Destroy; override;

    { The string items.  Mutate directly; TListBox observes automatically. }
    property Items: TObservedStringList read FItems;
    function  AddItem(const AText: string): Integer;
    procedure Clear;

    property ItemEnabled[I: Integer]: Boolean read GetItemEnabled
                                              write SetItemEnabled;
    property ItemCount: Integer read GetItemCount;
    property SelectedIndex: Integer read FSel;
    function SelectedText: string;

    property OnSelectionChanged: TListBoxItemEvent read FOnSelectionChanged
                                                    write FOnSelectionChanged;
    property OnActivate:         TListBoxItemEvent read FOnActivate
                                                    write FOnActivate;
  end;

implementation

constructor TListBox.Create;
begin
  inherited Create;
  FItems := TObservedStringList.Create;
  FItems.AttachObserver(Self);
  FSel := -1;
end;

destructor TListBox.Destroy;
begin
  if Assigned(FItems) then
  begin
    FItems.DetachObserver(Self);
    FItems.Free;
  end;
  inherited;
end;

{ ── ITermUIObserver ── }

procedure TListBox.ObservedChanged(ASender: TObject;
  ANotify: TObserverNotification);
begin
  case ANotify.Operation of
    ooBeginUpdate:
      FSuppressed := True;

    ooEndUpdate:
      begin
        FSuppressed := False;
        SyncEnabledArray;
        EnsureVisible;
        Invalidate;
      end;

    ooAdd, ooInsert:
      begin
        GrowEnabledArray(ANotify.Index);
        if FSel < 0 then FSel := 0;
        if not FSuppressed then
        begin
          EnsureVisible;
          Invalidate;
        end;
      end;

    ooDelete:
      begin
        ShrinkEnabledArray(ANotify.Index);
        if FSel >= FItems.Count then
          FSel := FItems.Count - 1;
        if not FSuppressed then
        begin
          EnsureVisible;
          Invalidate;
        end;
      end;

    ooClear:
      begin
        SetLength(FEnabled, 0);
        FSel    := -1;
        FTopRow := 0;
        if not FSuppressed then
          Invalidate;
      end;

    ooChange:
      begin
        if not FSuppressed then
          Invalidate;
      end;

    ooFreeing:
      { The list is going away from under us — detach gracefully. }
      FItems := nil;
  end;
end;

{ ── internals ── }

function TListBox.GetItemCount: Integer;
begin
  if Assigned(FItems) then Result := FItems.Count else Result := 0;
end;

function TListBox.GetItemEnabled(I: Integer): Boolean;
begin
  if (I < 0) or (I >= Length(FEnabled)) then Result := True
  else Result := FEnabled[I];
end;

procedure TListBox.SetItemEnabled(I: Integer; AValue: Boolean);
begin
  SyncEnabledArray;
  if (I >= 0) and (I < Length(FEnabled)) then
  begin
    FEnabled[I] := AValue;
    Invalidate;
  end;
end;

function TListBox.SelectedText: string;
begin
  if Assigned(FItems) and (FSel >= 0) and (FSel < FItems.Count) then
    Result := FItems[FSel]
  else
    Result := '';
end;

function TListBox.VisibleRows: Integer;
begin
  Result := Height;
  if Result < 1 then Result := 1;
end;

procedure TListBox.EnsureVisible;
var VR: Integer;
begin
  if (not Assigned(FItems)) or (FItems.Count = 0) then Exit;
  if FSel < 0 then FSel := 0;
  if FSel >= FItems.Count then FSel := FItems.Count - 1;
  VR := VisibleRows;
  if FSel < FTopRow then FTopRow := FSel
  else if FSel >= FTopRow + VR then FTopRow := FSel - VR + 1;
  if FTopRow < 0 then FTopRow := 0;
end;

procedure TListBox.SyncEnabledArray;
var Old, I: Integer;
begin
  if not Assigned(FItems) then Exit;
  if Length(FEnabled) < FItems.Count then
  begin
    Old := Length(FEnabled);
    SetLength(FEnabled, FItems.Count);
    for I := Old to FItems.Count - 1 do FEnabled[I] := True;
  end;
end;

procedure TListBox.GrowEnabledArray(ANewIndex: Integer);
var OldLen, I: Integer;
begin
  OldLen := Length(FEnabled);
  if ANewIndex >= OldLen then
  begin
    SetLength(FEnabled, ANewIndex + 1);
    for I := OldLen to Length(FEnabled) - 1 do FEnabled[I] := True;
  end
  else
  begin
    SetLength(FEnabled, Length(FEnabled) + 1);
    Move(FEnabled[ANewIndex], FEnabled[ANewIndex + 1],
         (Length(FEnabled) - ANewIndex - 1) * SizeOf(Boolean));
    FEnabled[ANewIndex] := True;
  end;
end;

procedure TListBox.ShrinkEnabledArray(ADeletedIndex: Integer);
var Len: Integer;
begin
  Len := Length(FEnabled);
  if ADeletedIndex < Len - 1 then
    Move(FEnabled[ADeletedIndex + 1], FEnabled[ADeletedIndex],
         (Len - ADeletedIndex - 1) * SizeOf(Boolean));
  if Len > 0 then SetLength(FEnabled, Len - 1);
end;

function TListBox.NextEnabled(AFrom, ADir: Integer): Integer;
var I: Integer;
begin
  I := AFrom;
  while (I >= 0) and (I < FItems.Count) do
  begin
    if GetItemEnabled(I) then Exit(I);
    Inc(I, ADir);
  end;
  Result := -1;
end;

function TListBox.AddItem(const AText: string): Integer;
begin
  Result := FItems.Add(AText);
end;

procedure TListBox.Clear;
begin
  FSel    := -1;
  FTopRow := 0;
  FItems.Clear;
end;

procedure TListBox.DrawRow(Row, Idx: Integer);
var
  IsSel: Boolean;
  ColW:  Integer;
  Avail: Integer;
  Txt:   string;
begin
  IsSel := Idx = FSel;
  ColW  := Width;
  if FItems.Count > VisibleRows then Dec(ColW);

  GotoLocal(1, Row);

  if IsSel then
  begin
    Term.SetFG(clBlack);
    Term.SetBG(clCyan);
  end
  else if not GetItemEnabled(Idx) then
    Term.SetFG(clBrightBlack)
  else
    Term.ResetColors;

  Term.WriteStr(StringOfChar(' ', ColW));
  GotoLocal(2, Row);

  Avail := ColW - 1;
  if Avail < 0 then Avail := 0;
  Txt := FItems[Idx];
  if Length(Txt) > Avail then Txt := Copy(Txt, 1, Avail);
  Term.WriteStr(Txt);
  Term.ResetColors;
end;

procedure TListBox.DrawScrollBar;
var
  VR, Total, ThumbH, ThumbTop, I: Integer;
begin
  VR    := VisibleRows;
  Total := FItems.Count;
  if Total <= VR then Exit;

  ThumbH := VR * VR div Total;
  if ThumbH < 1 then ThumbH := 1;
  if Total - VR > 0 then
    ThumbTop := FTopRow * (VR - ThumbH) div (Total - VR)
  else
    ThumbTop := 0;

  Term.ResetColors;
  for I := 0 to VR - 1 do
  begin
    GotoLocal(Width, I + 1);
    if (I >= ThumbTop) and (I < ThumbTop + ThumbH) then
      Application.DrawChar(dcScrollThumb)
    else
      Application.DrawChar(dcScrollTrack);
  end;
end;

procedure TListBox.DoPaint;
var
  VR, I, Idx: Integer;
begin
  if not Assigned(FItems) then Exit;
  Term.ResetColors;
  VR := VisibleRows;
  for I := 0 to VR - 1 do
  begin
    Idx := FTopRow + I;
    if Idx < FItems.Count then
      DrawRow(I + 1, Idx)
    else
    begin
      GotoLocal(1, I + 1);
      Term.WriteStr(StringOfChar(' ', Width));
    end;
  end;
  DrawScrollBar;
end;

function TListBox.DoKeyDown(var Key: TKeyEvent): Boolean;
var
  OldSel, NewSel: Integer;
begin
  Result := True;
  if not Assigned(FItems) then begin Result := False; Exit; end;
  OldSel := FSel;
  NewSel := FSel;

  case Key.Code of
    kcUp:       NewSel := NextEnabled(FSel - 1, -1);
    kcDown:     NewSel := NextEnabled(FSel + 1, +1);
    kcHome:     NewSel := NextEnabled(0, +1);
    kcEnd:      NewSel := NextEnabled(FItems.Count - 1, -1);

    kcPageUp:
      begin
        NewSel := FSel - VisibleRows + 1;
        if NewSel < 0 then NewSel := 0;
        NewSel := NextEnabled(NewSel, +1);
      end;

    kcPageDown:
      begin
        NewSel := FSel + VisibleRows - 1;
        if NewSel >= FItems.Count then NewSel := FItems.Count - 1;
        NewSel := NextEnabled(NewSel, -1);
      end;

    kcEnter:
      begin
        if (FSel >= 0) and GetItemEnabled(FSel) and Assigned(FOnActivate) then
          FOnActivate(Self, FSel);
      end;

  else
    Result := False;
  end;

  if Result then
  begin
    if (NewSel >= 0) and (NewSel <> OldSel) then
    begin
      FSel := NewSel;
      EnsureVisible;
      if Assigned(FOnSelectionChanged) then
        FOnSelectionChanged(Self, FSel);
    end;
    Invalidate;
  end;
end;

procedure TListBox.DoBoundsChanged;
begin
  EnsureVisible;
end;

end.
