{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.TreeView;

{$mode objfpc}{$H+}

{ Virtual treeview control for TermUI.

  Supports concrete mode (add TTreeNode via AddRoot/AddChild) and
  lazy loading (OnExpanding fires before a node is first expanded so
  the handler can populate children on demand).

  Nodes are optionally checkable with tri-state support.
  Tree guide-lines, node glyphs, and a right-side scroll indicator
  are all optional.

  Key bindings:
    Up / Down           move selection
    Home / End          first / last visible node
    PgUp / PgDn        page up/down
    Right               expand node (or move into first child if already open)
    Left                collapse node (or jump to parent if already collapsed)
    Enter               toggle expand/collapse; fires OnActivate
    Space               toggle checkbox (ShowCheckboxes=True) or toggle expand
}

interface

uses
  Classes, SysUtils, TermUI.Terminal, TermUI.Control, TermUI.Application;

type
  TCheckState = (csUnchecked, csChecked, csMixed);

  TTreeView = class;

  { A node in the tree.  Create nodes via TTreeView.AddRoot / TTreeNode.AddChild;
    do not construct directly. }
  TTreeNode = class
  private
    FOwner:      TTreeView;
    FParent:     TTreeNode;
    FChildren:   TList;
    FText:       string;
    FData:       Pointer;
    FGlyph:      Char;
    FHasGlyph:   Boolean;
    FExpanded:   Boolean;
    FEnabled:    Boolean;
    FCheckState: TCheckState;
    FLoaded:     Boolean;
    function  GetChild(I: Integer): TTreeNode;
    function  GetChildCount: Integer;
  public
    constructor Create(AOwner: TTreeView; AParent: TTreeNode; const AText: string);
    destructor  Destroy; override;

    { Add a child node and return it.  Sets Loaded := True on this node. }
    function  AddChild(const AText: string): TTreeNode;
    { Remove and free all children.  Resets Loaded to False (lazy state). }
    procedure Clear;

    property Text:       string     read FText       write FText;
    property Data:       Pointer    read FData       write FData;
    { Single-character icon drawn before the node text when HasGlyph is True. }
    property Glyph:      Char       read FGlyph      write FGlyph;
    property HasGlyph:   Boolean    read FHasGlyph   write FHasGlyph;
    property Parent:     TTreeNode  read FParent;
    property Children[I: Integer]: TTreeNode read GetChild;
    property ChildCount: Integer    read GetChildCount;
    property Expanded:   Boolean    read FExpanded;
    { Disabled nodes are rendered in dim color.  Space and Enter do not
      activate or toggle-check them, though the cursor may still land on them. }
    property Enabled:    Boolean    read FEnabled    write FEnabled;
    property CheckState: TCheckState read FCheckState write FCheckState;
    { False = never loaded; OnExpanding fires on first expand attempt.
      Set to True manually when the node is known to be a leaf. }
    property Loaded:     Boolean    read FLoaded     write FLoaded;
  end;

  TTreeNodeEvent      = procedure(Sender: TObject; Node: TTreeNode) of object;
  { Fires before a node expands (used for lazy loading).  Set DoExpand := False
    to veto the expansion (e.g. access-denied situations). }
  TTreeExpandingEvent = procedure(Sender: TObject; Node: TTreeNode;
                                  var DoExpand: Boolean) of object;

  TTreeView = class(TControl)
  private
    type
      TDisplayItem = record
        Node:     TTreeNode;
        Level:    Integer;
        IsLast:   Boolean;
        { Bit L is set if there is a vertical guide-line to draw at indent level L. }
        LineMask: QWord;
      end;

  private
    FRoots:          TList;
    FDisplay:        array of TDisplayItem;
    FDisplayCount:   Integer;
    FSel:            Integer;
    FTopRow:         Integer;
    FShowCheckboxes: Boolean;
    FShowLines:      Boolean;
    FIndentWidth:    Integer;
    FTriState:       Boolean;

    FOnSelectionChanged: TTreeNodeEvent;
    FOnActivate:         TTreeNodeEvent;
    FOnExpand:           TTreeNodeEvent;
    FOnCollapse:         TTreeNodeEvent;
    FOnChecked:          TTreeNodeEvent;
    FOnExpanding:        TTreeExpandingEvent;

    function  GetRoot(I: Integer): TTreeNode;
    function  GetRootCount: Integer;
    function  GetSelectedNode: TTreeNode;
    function  VisibleRows: Integer;
    procedure EnsureVisible;
    procedure RebuildDisplay;
    procedure RebuildRecurse(Node: TTreeNode; Level: Integer;
                             IsLast: Boolean; LineMask: QWord);
    procedure DrawRow(Row, Idx: Integer);
    procedure DrawScrollBar;
    procedure ExpandNode(Idx: Integer);
    procedure CollapseNode(Idx: Integer);
    procedure ToggleCheck(Idx: Integer);
    procedure UpdateParentCheckStates(Node: TTreeNode);
    function  FindDisplayIndex(Node: TTreeNode): Integer;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
    procedure DoBoundsChanged; override;
  public
    constructor Create; override;
    destructor  Destroy; override;

    { Add a root-level node and return it. }
    function  AddRoot(const AText: string): TTreeNode;
    { Remove and free all root nodes. }
    procedure Clear;
    { Call after any structural change made outside AddRoot/AddChild/Clear. }
    procedure InvalidateTree;

    property RootCount: Integer    read GetRootCount;
    property Roots[I: Integer]: TTreeNode read GetRoot;
    property Selection: TTreeNode  read GetSelectedNode;

    { Show checkbox glyphs (☐ / ☑) next to each node.  Default: False. }
    property ShowCheckboxes: Boolean  read FShowCheckboxes write FShowCheckboxes;
    { Draw vertical and branch guide-line characters.  Default: True. }
    property ShowLines:      Boolean  read FShowLines      write FShowLines;
    { Columns per indent level (includes the guide-line character).  Default: 2. }
    property IndentWidth:    Integer  read FIndentWidth    write FIndentWidth;
    { Propagate checked state to parent nodes as Mixed when children differ.
      Requires ShowCheckboxes = True.  Default: False. }
    property TriState:       Boolean  read FTriState       write FTriState;

    property OnSelectionChanged: TTreeNodeEvent      read FOnSelectionChanged
                                                      write FOnSelectionChanged;
    property OnActivate:         TTreeNodeEvent      read FOnActivate
                                                      write FOnActivate;
    property OnExpand:           TTreeNodeEvent      read FOnExpand
                                                      write FOnExpand;
    property OnCollapse:         TTreeNodeEvent      read FOnCollapse
                                                      write FOnCollapse;
    property OnChecked:          TTreeNodeEvent      read FOnChecked
                                                      write FOnChecked;
    { Fires before a node's children are first shown.  Add children inside the
      handler and set Node.Loaded := True if the node is a proven leaf. }
    property OnExpanding:        TTreeExpandingEvent read FOnExpanding
                                                      write FOnExpanding;
  end;

implementation

{ ── TTreeNode ── }

constructor TTreeNode.Create(AOwner: TTreeView; AParent: TTreeNode;
  const AText: string);
begin
  inherited Create;
  FOwner    := AOwner;
  FParent   := AParent;
  FChildren := TList.Create;
  FText     := AText;
  FEnabled  := True;
  FLoaded   := False;
end;

destructor TTreeNode.Destroy;
var I: Integer;
begin
  for I := 0 to FChildren.Count - 1 do
    TTreeNode(FChildren[I]).Free;
  FChildren.Free;
  inherited;
end;

function TTreeNode.AddChild(const AText: string): TTreeNode;
begin
  Result := TTreeNode.Create(FOwner, Self, AText);
  Result.FLoaded := True;
  FLoaded := True;
  FChildren.Add(Result);
end;

procedure TTreeNode.Clear;
var I: Integer;
begin
  for I := 0 to FChildren.Count - 1 do
    TTreeNode(FChildren[I]).Free;
  FChildren.Clear;
  FLoaded := False;
end;

function TTreeNode.GetChild(I: Integer): TTreeNode;
begin
  Result := TTreeNode(FChildren[I]);
end;

function TTreeNode.GetChildCount: Integer;
begin
  Result := FChildren.Count;
end;

{ ── TTreeView ── }

constructor TTreeView.Create;
begin
  inherited Create;
  FRoots       := TList.Create;
  FShowLines   := True;
  FIndentWidth := 2;
  FSel         := -1;
  FTopRow      := 0;
end;

destructor TTreeView.Destroy;
begin
  Clear;
  FRoots.Free;
  inherited;
end;

function TTreeView.GetRoot(I: Integer): TTreeNode;
begin
  Result := TTreeNode(FRoots[I]);
end;

function TTreeView.GetRootCount: Integer;
begin
  Result := FRoots.Count;
end;

function TTreeView.GetSelectedNode: TTreeNode;
begin
  if (FSel >= 0) and (FSel < FDisplayCount) then
    Result := FDisplay[FSel].Node
  else
    Result := nil;
end;

function TTreeView.VisibleRows: Integer;
begin
  Result := Height;
  if Result < 1 then Result := 1;
end;

procedure TTreeView.EnsureVisible;
var VR: Integer;
begin
  if FDisplayCount = 0 then Exit;
  if FSel < 0 then FSel := 0;
  if FSel >= FDisplayCount then FSel := FDisplayCount - 1;
  VR := VisibleRows;
  if FSel < FTopRow then
    FTopRow := FSel
  else if FSel >= FTopRow + VR then
    FTopRow := FSel - VR + 1;
  if FTopRow < 0 then FTopRow := 0;
end;

procedure TTreeView.RebuildDisplay;
var I: Integer;
begin
  FDisplayCount := 0;
  if Length(FDisplay) < 64 then
    SetLength(FDisplay, 64);
  for I := 0 to FRoots.Count - 1 do
    RebuildRecurse(TTreeNode(FRoots[I]), 0, I = FRoots.Count - 1, 0);
end;

procedure TTreeView.RebuildRecurse(Node: TTreeNode; Level: Integer;
  IsLast: Boolean; LineMask: QWord);
var
  I:         Integer;
  ChildMask: QWord;
begin
  if FDisplayCount >= Length(FDisplay) then
    SetLength(FDisplay, Length(FDisplay) * 2);

  FDisplay[FDisplayCount].Node     := Node;
  FDisplay[FDisplayCount].Level    := Level;
  FDisplay[FDisplayCount].IsLast   := IsLast;
  FDisplay[FDisplayCount].LineMask := LineMask;
  Inc(FDisplayCount);

  if not Node.Expanded then Exit;

  { Children inherit this node's line bit: set if we (the parent) are NOT last }
  if not IsLast then
    ChildMask := LineMask or  (QWord(1) shl Level)
  else
    ChildMask := LineMask and not (QWord(1) shl Level);

  for I := 0 to Node.ChildCount - 1 do
    RebuildRecurse(Node.Children[I], Level + 1, I = Node.ChildCount - 1,
                   ChildMask);
end;

procedure TTreeView.DrawRow(Row, Idx: Integer);
var
  Item:    TDisplayItem;
  Node:    TTreeNode;
  X, L:   Integer;
  IsSel:  Boolean;
  ColW:   Integer;
  Avail:  Integer;
  Txt:    string;
begin
  Item  := FDisplay[Idx];
  Node  := Item.Node;
  IsSel := Idx = FSel;

  { Right column reserved for scrollbar when content overflows }
  ColW := Width;
  if FDisplayCount > VisibleRows then Dec(ColW);

  GotoLocal(1, Row);
  if IsSel then
  begin
    Term.SetFG(clBlack);
    Term.SetBG(clCyan);
  end
  else if not Node.Enabled then
    Term.SetFG(clBrightBlack)
  else
    Term.ResetColors;

  { Clear the entire row up-front so we can write sparsely }
  Term.WriteStr(StringOfChar(' ', ColW));

  { ── Tree guide-lines (ancestor levels) ── }
  if FShowLines then
    for L := 0 to Item.Level - 1 do
    begin
      GotoLocal(1 + L * FIndentWidth, Row);
      if L = Item.Level - 1 then
      begin
        { Connector for the direct parent slot }
        if Item.IsLast then
          Application.DrawChar(dcTreeLast)
        else
          Application.DrawChar(dcTreeBranch);
      end
      else
      begin
        { Vertical continuation for a more-distant ancestor }
        if (Item.LineMask shr L) and 1 = 1 then
          Application.DrawChar(dcTreeVert)
        else
          Term.WriteStr(' ');
      end;
    end;

  { ── Expand indicator ── }
  X := 1 + Item.Level * FIndentWidth;
  GotoLocal(X, Row);
  if (not Node.Loaded) or (Node.ChildCount > 0) then
  begin
    if Node.Expanded then
      Application.DrawChar(dcTreeExpanded)
    else
      Application.DrawChar(dcTreeCollapsed);
  end
  else
    Application.DrawChar(dcTreeLeaf);
  Inc(X);

  { Space after indicator }
  GotoLocal(X, Row);
  Term.WriteStr(' ');
  Inc(X);

  { ── Checkbox ── }
  if FShowCheckboxes then
  begin
    GotoLocal(X, Row);
    case Node.CheckState of
      csUnchecked: Application.DrawChar(dcCheckOff);
      csChecked:   Application.DrawChar(dcCheckOn);
      csMixed:     Term.WriteStr('~');
    end;
    Inc(X);
    GotoLocal(X, Row);
    Term.WriteStr(' ');
    Inc(X);
  end;

  { ── Glyph ── }
  if Node.HasGlyph then
  begin
    GotoLocal(X, Row);
    Term.WriteStr(Node.Glyph);
    Inc(X);
    GotoLocal(X, Row);
    Term.WriteStr(' ');
    Inc(X);
  end;

  { ── Node text (truncated to available width) ── }
  Avail := ColW - X + 1;
  if Avail > 0 then
  begin
    GotoLocal(X, Row);
    Txt := Node.Text;
    if Length(Txt) > Avail then
      Txt := Copy(Txt, 1, Avail);
    Term.WriteStr(Txt);
  end;

  Term.ResetColors;
end;

procedure TTreeView.DrawScrollBar;
var
  VR, Total, ThumbH, ThumbTop, I: Integer;
begin
  VR    := VisibleRows;
  Total := FDisplayCount;
  if Total <= VR then Exit;

  { Thumb height proportional to visible fraction (at least 1 row) }
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

procedure TTreeView.DoPaint;
var
  VR, I, Idx: Integer;
begin
  Term.ResetColors;
  VR := VisibleRows;
  for I := 0 to VR - 1 do
  begin
    Idx := FTopRow + I;
    if Idx < FDisplayCount then
      DrawRow(I + 1, Idx)
    else
    begin
      GotoLocal(1, I + 1);
      Term.WriteStr(StringOfChar(' ', Width));
    end;
  end;
  DrawScrollBar;
end;

procedure TTreeView.ExpandNode(Idx: Integer);
var
  Node:  TTreeNode;
  Allow: Boolean;
begin
  if (Idx < 0) or (Idx >= FDisplayCount) then Exit;
  Node := FDisplay[Idx].Node;
  if Node.Expanded then Exit;

  Allow := True;
  if Assigned(FOnExpanding) then
    FOnExpanding(Self, Node, Allow);
  if not Allow then Exit;

  Node.FExpanded := True;
  Node.FLoaded   := True;

  RebuildDisplay;
  EnsureVisible;
  if Assigned(FOnExpand) then FOnExpand(Self, Node);
  Invalidate;
end;

procedure TTreeView.CollapseNode(Idx: Integer);
var
  Node: TTreeNode;
begin
  if (Idx < 0) or (Idx >= FDisplayCount) then Exit;
  Node := FDisplay[Idx].Node;
  if not Node.Expanded then Exit;

  Node.FExpanded := False;
  RebuildDisplay;
  EnsureVisible;
  if Assigned(FOnCollapse) then FOnCollapse(Self, Node);
  Invalidate;
end;

procedure TTreeView.ToggleCheck(Idx: Integer);
var
  Node: TTreeNode;
begin
  if (Idx < 0) or (Idx >= FDisplayCount) then Exit;
  Node := FDisplay[Idx].Node;
  if not Node.Enabled then Exit;
  case Node.FCheckState of
    csUnchecked: Node.FCheckState := csChecked;
    csChecked:   Node.FCheckState := csUnchecked;
    csMixed:     Node.FCheckState := csChecked;
  end;
  if FTriState then
    UpdateParentCheckStates(Node.Parent);
  if Assigned(FOnChecked) then FOnChecked(Self, Node);
  Invalidate;
end;

procedure TTreeView.UpdateParentCheckStates(Node: TTreeNode);
var
  I:            Integer;
  HasChecked, HasUnchecked: Boolean;
begin
  if Node = nil then Exit;
  HasChecked   := False;
  HasUnchecked := False;
  for I := 0 to Node.ChildCount - 1 do
    case Node.Children[I].CheckState of
      csChecked:   HasChecked   := True;
      csUnchecked: HasUnchecked := True;
      csMixed: begin HasChecked := True; HasUnchecked := True; end;
    end;
  if HasChecked and HasUnchecked then
    Node.FCheckState := csMixed
  else if HasChecked then
    Node.FCheckState := csChecked
  else
    Node.FCheckState := csUnchecked;
  UpdateParentCheckStates(Node.Parent);
end;

function TTreeView.FindDisplayIndex(Node: TTreeNode): Integer;
var I: Integer;
begin
  for I := 0 to FDisplayCount - 1 do
    if FDisplay[I].Node = Node then Exit(I);
  Result := -1;
end;

function TTreeView.DoKeyDown(var Key: TKeyEvent): Boolean;
var
  OldSel: Integer;
  Node:   TTreeNode;
  PIdx:   Integer;
  NewSel: Integer;
begin
  Result := True;
  OldSel := FSel;

  case Key.Code of
    kcUp:
      if FSel > 0 then Dec(FSel);

    kcDown:
      if FSel < FDisplayCount - 1 then Inc(FSel);

    kcHome:
      FSel := 0;

    kcEnd:
      if FDisplayCount > 0 then FSel := FDisplayCount - 1;

    kcPageUp:
      begin
        NewSel := FSel - VisibleRows + 1;
        if NewSel < 0 then NewSel := 0;
        FSel := NewSel;
      end;

    kcPageDown:
      begin
        NewSel := FSel + VisibleRows - 1;
        if NewSel >= FDisplayCount then NewSel := FDisplayCount - 1;
        FSel := NewSel;
      end;

    kcRight:
      begin
        if (FSel >= 0) and (FSel < FDisplayCount) then
        begin
          Node := FDisplay[FSel].Node;
          if Node.Expanded then
          begin
            { Already open — step into first visible child }
            if (FSel + 1 < FDisplayCount) and
               (FDisplay[FSel + 1].Level > FDisplay[FSel].Level) then
              Inc(FSel);
          end
          else
            ExpandNode(FSel);
        end;
      end;

    kcLeft:
      begin
        if (FSel >= 0) and (FSel < FDisplayCount) then
        begin
          Node := FDisplay[FSel].Node;
          if Node.Expanded then
            CollapseNode(FSel)
          else if Node.Parent <> nil then
          begin
            PIdx := FindDisplayIndex(Node.Parent);
            if PIdx >= 0 then FSel := PIdx;
          end;
        end;
      end;

    kcEnter:
      begin
        if (FSel >= 0) and (FSel < FDisplayCount) then
        begin
          Node := FDisplay[FSel].Node;
          if Node.Expanded then
            CollapseNode(FSel)
          else
            ExpandNode(FSel);
          if Node.Enabled and Assigned(FOnActivate) then FOnActivate(Self, Node);
        end;
      end;

    kcChar:
      if Key.Ch = ' ' then
      begin
        if FShowCheckboxes then
          ToggleCheck(FSel)
        else if (FSel >= 0) and (FSel < FDisplayCount) then
        begin
          Node := FDisplay[FSel].Node;
          if Node.Enabled then
          begin
            if Node.Expanded then CollapseNode(FSel) else ExpandNode(FSel);
          end;
        end;
      end
      else
        Result := False;

  else
    Result := False;
  end;

  if Result then
  begin
    if FSel <> OldSel then
    begin
      EnsureVisible;
      if Assigned(FOnSelectionChanged) then
        FOnSelectionChanged(Self, GetSelectedNode);
    end;
    Invalidate;
  end;
end;

procedure TTreeView.DoBoundsChanged;
begin
  EnsureVisible;
end;

function TTreeView.AddRoot(const AText: string): TTreeNode;
begin
  Result := TTreeNode.Create(Self, nil, AText);
  Result.FLoaded := True;
  FRoots.Add(Result);
  RebuildDisplay;
  if FSel < 0 then FSel := 0;
  Invalidate;
end;

procedure TTreeView.Clear;
var I: Integer;
begin
  for I := 0 to FRoots.Count - 1 do
    TTreeNode(FRoots[I]).Free;
  FRoots.Clear;
  FDisplayCount := 0;
  FSel          := -1;
  FTopRow       := 0;
  Invalidate;
end;

procedure TTreeView.InvalidateTree;
begin
  RebuildDisplay;
  EnsureVisible;
  Invalidate;
end;

end.
