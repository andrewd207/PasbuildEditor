{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Observer;

{$mode objfpc}{$H+}
{$interfaces corba}

{ Lightweight observer / observed interfaces for TermUI controls.

  Design:
    ITermUIObserved  — implemented by any object whose state can be watched
                       (TObservedStringList, TTreeView node collections, …)
    ITermUIObserver  — implemented by controls that react to state changes
                       (TListBox, TComboBox, TTreeView, …)

  Notification objects:
    TObserverNotification is the base class.  Each observed type may declare
    its own public nested subclass (e.g. TObservedStringList.TNotification)
    to carry extra fields without losing the common Operation/Index pair.

    The observed object creates the notification, fires it to all attached
    observers, then frees it.  During BeginUpdate/EndUpdate the notifications
    are queued; ownership stays with the queue until they are replayed and
    freed at EndUpdate.

  BeginUpdate / EndUpdate:
    Implemented inside TObservedStringList (and any other observed class)
    using SetUpdateState.  On the first BeginUpdate (nesting 0→1), an
    ooBeginUpdate notification is fired immediately so observers can suppress
    intermediate repaints.  Subsequent changes are queued.  If ooClear is
    enqueued, all prior queued notifications are discarded (a clear makes them
    irrelevant).  EndUpdate flushes the queue then fires ooEndUpdate.

  Interfaces are declared CORBA — no IUnknown / ref-counting overhead.
  Implementing classes need no QueryInterface / _AddRef / _Release stubs.
}

interface

type
  TObservedOperation = (
    ooBeginUpdate,   { batch of changes starting; observer should suppress partial repaints }
    ooEndUpdate,     { batch done; observer should do a full refresh }
    ooAdd,           { item appended; Index = new item's position }
    ooInsert,        { item inserted; Index = inserted position }
    ooDelete,        { item removed;  Index = former position }
    ooChange,        { item replaced; Index = position }
    ooClear,         { all items removed }
    ooFreeing        { observed object is about to be freed; observer should detach }
  );

  { Base notification.  Extend this as a public nested class of the observed
    type when extra fields are needed; declare the subclass inside the unit
    that introduces the new observed class. }
  TObserverNotification = class
  public
    Operation: TObservedOperation;
    Index:     Integer;   { -1 when the operation has no specific index }
    constructor Create(AOp: TObservedOperation; AIndex: Integer = -1);
  end;

  { Implemented by objects that react to state changes in an observed object. }
  ITermUIObserver = interface
    ['{1D2E3F4A-5B6C-7D8E-9F0A-ABCDEF012345}']
    { Called synchronously by the observed object.  Do not free ANotify. }
    procedure ObservedChanged(ASender: TObject;
                              ANotify: TObserverNotification);
  end;

  { Implemented by objects whose state can be watched. }
  ITermUIObserved = interface
    ['{9A3B5C7D-E1F2-4806-BCDA-123456789ABC}']
    procedure AttachObserver(AObserver: ITermUIObserver);
    procedure DetachObserver(AObserver: ITermUIObserver);
  end;

implementation

constructor TObserverNotification.Create(AOp: TObservedOperation;
  AIndex: Integer);
begin
  inherited Create;
  Operation := AOp;
  Index     := AIndex;
end;

end.
