{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.ObservedStringList;

{$mode objfpc}{$H+}
{$interfaces corba}

{ TObservedStringList — a TStringList that implements both ITermUIObserved
  and ITermUIObserver.

  Observed behaviour:
    Any structural mutation (Add, Insert, Delete, Clear, item assignment,
    LoadFromFile, Assign, Sort, …) fires the appropriate TNotification to
    all attached ITermUIObserver instances.

    BeginUpdate / EndUpdate (called directly OR by TStrings.LoadFromFile,
    Assign, Sort, etc.) are intercepted via the virtual SetUpdateState hook:
      - First BeginUpdate (0 → 1) fires ooBeginUpdate immediately.
      - Mutations during an update are queued.
      - ooClear in the queue discards all prior queued items.
      - Final EndUpdate (1 → 0) replays the queue then fires ooEndUpdate.

  Observer behaviour:
    TObservedStringList can itself observe another ITermUIObserved source
    (e.g. relay filtered views), implementing ITermUIObserver.

  Notification subclass:
    TObservedStringList.TNotification extends TObserverNotification with
    an optional Text field (the new string value for ooAdd/ooInsert/ooChange).
    Controls that only need Operation + Index can use the base class fields.
}

interface

uses
  Classes, SysUtils, Contnrs, TermUI.Observer;

type
  TObservedStringList = class(TStringList, ITermUIObserved, ITermUIObserver)
  public
    type
      { Extended notification carrying the string value for mutations. }
      TNotification = class(TObserverNotification)
      public
        Text: string;
        constructor Create(AOp: TObservedOperation; AIndex: Integer = -1;
                           const AText: string = '');
      end;

  private
    FObservers:      TList;       { stores ITermUIObserver as Pointer (CORBA) }
    FObsUpdateCount: Integer;     { our own nesting counter — separate from TStrings' }
    FQueue:          TObjectList; { owned; TObserverNotification items queued during update }

    procedure FireToAll(ANotif: TObserverNotification);
    procedure EnqueueOrFire(ANotif: TObserverNotification);
    procedure FlushQueue;

  protected
    { Hook point for TStrings.BeginUpdate / EndUpdate. }
    procedure SetUpdateState(Updating: Boolean); override;

    { TStringList mutation hooks. }
    procedure InsertItem(Index: Integer; const S: string;
                         AObject: TObject); override;
    procedure Put(Index: Integer; const S: string); override;

  public
    constructor Create;
    destructor  Destroy; override;

    { ITermUIObserved }
    procedure AttachObserver(AObserver: ITermUIObserver);
    procedure DetachObserver(AObserver: ITermUIObserver);

    { ITermUIObserver — so a list can relay notifications from another source. }
    procedure ObservedChanged(ASender: TObject;
                              ANotify: TObserverNotification);

    { Direct overrides to fire notifications. }
    procedure Delete(Index: Integer); override;
    procedure Clear; override;
    procedure Exchange(Index1, Index2: Integer); override;
  end;

implementation

{ ── TNotification ── }

constructor TObservedStringList.TNotification.Create(AOp: TObservedOperation;
  AIndex: Integer; const AText: string);
begin
  inherited Create(AOp, AIndex);
  Text := AText;
end;

{ ── TObservedStringList ── }

constructor TObservedStringList.Create;
begin
  inherited Create;
  FObservers := TList.Create;
  FQueue     := TObjectList.Create(True);  { owns items }
end;

destructor TObservedStringList.Destroy;
var
  Notif: TNotification;
begin
  Notif := TNotification.Create(ooFreeing);
  FireToAll(Notif);
  Notif.Free;
  FQueue.Free;
  FObservers.Free;
  inherited;
end;

{ ── ITermUIObserved ── }

procedure TObservedStringList.AttachObserver(AObserver: ITermUIObserver);
begin
  if FObservers.IndexOf(Pointer(AObserver)) < 0 then
    FObservers.Add(Pointer(AObserver));
end;

procedure TObservedStringList.DetachObserver(AObserver: ITermUIObserver);
var I: Integer;
begin
  I := FObservers.IndexOf(Pointer(AObserver));
  if I >= 0 then FObservers.Delete(I);
end;

{ ── ITermUIObserver ── }

procedure TObservedStringList.ObservedChanged(ASender: TObject;
  ANotify: TObserverNotification);
begin
  { Relay: pass through to our own observers. }
  FireToAll(ANotify);
end;

{ ── internal dispatch ── }

procedure TObservedStringList.FireToAll(ANotif: TObserverNotification);
var I: Integer;
begin
  for I := 0 to FObservers.Count - 1 do
    ITermUIObserver(FObservers[I]).ObservedChanged(Self, ANotif);
end;

procedure TObservedStringList.EnqueueOrFire(ANotif: TObserverNotification);
var I: Integer;
begin
  if FObsUpdateCount > 0 then
  begin
    { ooClear makes all prior queued ops irrelevant — drop them. }
    if ANotif.Operation = ooClear then
      FQueue.Clear;
    FQueue.Add(ANotif);   { queue takes ownership }
  end
  else
  begin
    FireToAll(ANotif);
    ANotif.Free;
  end;
end;

procedure TObservedStringList.FlushQueue;
var
  I:     Integer;
  Notif: TObserverNotification;
begin
  for I := 0 to FQueue.Count - 1 do
  begin
    Notif := TObserverNotification(FQueue[I]);
    FireToAll(Notif);
  end;
  FQueue.Clear;   { TObjectList frees the items }
end;

{ ── TStrings.BeginUpdate / EndUpdate hook ── }

procedure TObservedStringList.SetUpdateState(Updating: Boolean);
var
  Notif: TNotification;
begin
  if Updating then
  begin
    if FObsUpdateCount = 0 then
    begin
      { First level of nesting — notify observers immediately }
      Notif := TNotification.Create(ooBeginUpdate);
      FireToAll(Notif);
      Notif.Free;
    end;
    Inc(FObsUpdateCount);
  end
  else
  begin
    if FObsUpdateCount > 0 then
      Dec(FObsUpdateCount);
    if FObsUpdateCount = 0 then
    begin
      FlushQueue;
      Notif := TNotification.Create(ooEndUpdate);
      FireToAll(Notif);
      Notif.Free;
    end;
  end;
  inherited SetUpdateState(Updating);
end;

{ ── mutation overrides ── }

procedure TObservedStringList.InsertItem(Index: Integer; const S: string;
  AObject: TObject);
var
  Op: TObservedOperation;
begin
  inherited InsertItem(Index, S, AObject);
  { Add calls Insert(Count-1, S) after the insert, so Index = Count-1 means append }
  if Index = Count - 1 then
    Op := ooAdd
  else
    Op := ooInsert;
  EnqueueOrFire(TNotification.Create(Op, Index, S));
end;

procedure TObservedStringList.Put(Index: Integer; const S: string);
begin
  inherited Put(Index, S);
  EnqueueOrFire(TNotification.Create(ooChange, Index, S));
end;

procedure TObservedStringList.Delete(Index: Integer);
begin
  inherited Delete(Index);
  EnqueueOrFire(TNotification.Create(ooDelete, Index));
end;

procedure TObservedStringList.Clear;
begin
  inherited Clear;
  EnqueueOrFire(TNotification.Create(ooClear));
end;

procedure TObservedStringList.Exchange(Index1, Index2: Integer);
begin
  inherited Exchange(Index1, Index2);
  { Two ooChange notifications cover both positions }
  EnqueueOrFire(TNotification.Create(ooChange, Index1, Strings[Index1]));
  EnqueueOrFire(TNotification.Create(ooChange, Index2, Strings[Index2]));
end;

end.
