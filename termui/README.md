# TermUI

A terminal UI framework for Free Pascal / Lazarus. Provides an event-driven, double-buffered system for building full-screen terminal applications on Linux, macOS, BSD, and Windows.

## Architecture

```
Application (TApplication)
  └── Form Stack
        └── TForm
              └── TControl (children)
                    └── Widgets (Menu, FilteredPicker, PathPicker, AsciiDocViewer)
Terminal (TTerminal / platform driver)
```

The framework is layered:

1. **Terminal layer** — platform-specific driver (Unix/Windows), double-buffered drawing, ANSI output
2. **Control/Form layer** — base UI components with focus management and key dispatch
3. **Widget layer** — ready-made interactive components
4. **Application layer** — event loop, form stack, resize handling

---

## Units

### TermUI.Terminal

Platform-independent terminal abstraction with double buffering. Renders only changed cells on flush.

**Key types:**

| Type | Description |
|------|-------------|
| `TKeyCode` | Enum: arrow keys, Ctrl+C/S/X, F1/F2, Backspace, Enter, Tab, Esc, Page Up/Down, Home/End, Delete, `kcChar` for printable characters |
| `TKeyEvent` | Record: `Code: TKeyCode`, `Ch: Char` (for `kcChar`) |
| `TColor` | 16-color palette: `clDefault`, `clBlack`–`clWhite`, bright variants (`clBrightRed`, etc.) |
| `TScreenCell` | Single terminal cell: character, FG/BG color, underline flag |

**Drawing methods (write to back buffer):**

```pascal
GotoXY(X, Y);            // 1-based cursor position
SetFG(clCyan);
SetBG(clDefault);
SetUnderline(True);
ResetColors;
WriteStr('Hello');
ClearToEOL;
ClearScreen;
FlushOutput;             // diff-based render: emits ANSI only for changed cells
InvalidateFront;         // force full redraw on next flush
```

**Input:**

```pascal
Key := ReadKey;                    // blocking
Key := ReadKeyTimeout(16{ms});     // non-blocking (returns kcNone on timeout)
```

**Terminal management:**

```pascal
EnableRawMode / DisableRawMode;
EnterAltScreen / ExitAltScreen;
HideCursor / ShowCursor;
IsTTY: Boolean;
Width, Height: Integer;
```

**Platform drivers:**

- `TermUI.Terminal.Platform` (Unix) — uses `termios` raw mode, SIGWINCH for resize, `select()` for non-blocking input, full ESC sequence parsing (arrows, Ctrl+arrows, F-keys)
- `TermUI.Terminal.Platform` (Windows) — ANSI/VT mode on Windows 10+, legacy `ReadConsoleInput` fallback with native color attributes

---

### TermUI.Control

Abstract base for all visible, interactive elements.

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `Left, Top` | Integer | Position (1-based) |
| `Width, Height` | Integer | Size |
| `Visible, Enabled` | Boolean | State |
| `Invalidated` | Boolean | Dirty flag (read-only; set via `Invalidate`) |
| `OnKeyDown` | `TKeyDownEvent` | External key handler |
| `OnPaint` | `TNotifyEvent` | External paint handler |

**Methods:**

```pascal
SetBounds(L, T, W, H);    // atomic resize + invalidate
Invalidate;               // mark as needing repaint
Paint;                    // render if visible and invalidated
KeyDown(var Key): Bool;   // dispatch key; True = consumed
GotoLocal(X, Y);          // translate control-local coords to terminal
```

**Override points:**

```pascal
procedure DoPaint; virtual;                        // override to draw
function DoKeyDown(var Key: TKeyEvent): Bool; virtual; // return True to consume
```

---

### TermUI.Forms

Full-screen container managing child controls with focus cycling.

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `Title` | string | Form title |
| `ModalResult` | Integer | 0 = open, non-zero = closed |
| `OnActivate` | `TNotifyEvent` | Fired when pushed onto form stack |
| `OnDeactivate` | `TNotifyEvent` | Fired when popped |

**Methods:**

```pascal
AddControl(AControl);            // add owned child
ControlCount: Integer;
GetControl(Idx): TControl;
FocusNext / FocusPrev;           // Tab through enabled+visible children
FocusedControl: TControl;
Close(ModalResult);              // set result and deactivate
CloseCancel;                     // shorthand: Close(-1)
Invalidate;                      // cascades to all children
```

**Key dispatch chain:**
1. Focused child gets first chance
2. Tab key cycles focus automatically
3. Unhandled keys bubble to form's `OnKeyDown`

---

### TermUI.Application

Singleton event loop and form stack manager.

**Form stack:**

```pascal
Application.PushForm(AForm);     // push + activate
Application.PopForm;             // pop + activate previous
Application.ActiveForm: TForm;
```

**Event loop:**

```pascal
Application.Run;                 // loop until Terminate
Application.Terminate;
Application.Resume;
Application.ProcessMessages;     // one cycle: resize → repaint → input → dispatch
```

**Modal dialogs:**

```pascal
Result := Application.ShowModal(AForm);   // push, spin until ModalResult <> 0, pop
```

Each `ProcessMessages` cycle:
1. Check for terminal resize; resize active form if needed
2. Repaint active form if invalidated
3. `ReadKeyTimeout(16ms)` — non-blocking
4. Dispatch key to active form, or fire `OnIdle`

**Properties:**

| Property | Description |
|----------|-------------|
| `OnKeyDown` | App-level fallback for unhandled keys |
| `OnIdle` | Fired each idle cycle (no key received) |

---

### TermUI.Menu

Scrollable, searchable menu with keyboard navigation and status bar.

**TMenuItem:**

```pascal
// Normal item
TMenuItem.Create(Label_, Action, Value, Hotkey, Hint);

// Parse '&' from label as hotkey (e.g. '&Open' → hotkey 'O', displayed underlined)
TMenuItem.CreateEmbeddedHotkey(Label_, Action, Value, Hint);

// Non-selectable section header
TMenuItem.CreateHeader(Label_);

// Visual separator line
TMenuItem.CreateSeparator;
```

**Item properties:**

| Property | Type | Description |
|----------|------|-------------|
| `Label_` | string | Primary text |
| `Value` | string | Right-aligned secondary text |
| `Hint` | string | Gray suffix on headers |
| `Desc` | string | Status bar description for this item |
| `Hotkey` | Char | Single-character quick-jump key |
| `Enabled` | Boolean | Greyed out if false |
| `DimItem, DimValue` | Boolean | Dim color rendering |
| `MarkOld` | Boolean | Visual "old/stale" indicator |
| `Action` | `TNotifyEvent` | Called on selection |

**TMenu keyboard shortcuts:**

| Key | Action |
|-----|--------|
| Up/Down | Move selection |
| Page Up/Down | Scroll by page |
| Home/End | Jump to first/last selectable |
| Enter / Right | Select item, close menu |
| Esc / Left | Cancel (Left sets `ExitedLeft` flag) |
| Delete | Set `DeletePressed` flag, close |
| F1 / F2 | Set `FF1Pressed` / `FF2Pressed` flags, close |
| Letter | Jump to item with matching hotkey |

**Output flags (check after ShowModal):**

```pascal
Menu.ExitedLeft: Boolean;     // user pressed Left
Menu.DeletePressed: Boolean;  // user pressed Delete
Menu.FF1Pressed: Boolean;     // user pressed F1
Menu.FF2Pressed: Boolean;     // user pressed F2
Menu.SelectedItem: TMenuItem; // the selected item (nil if cancelled)
```

**Rendering features:**
- Selection marker (`>`)
- Hotkey underline highlighting
- Right-aligned value column
- Per-item status description bar
- Help footer with version

---

### TermUI.FilteredPicker

Real-time filtered list picker with live substring search.

**TFilteredPickerItem:**

```pascal
Item.Label_ := 'identifier';  // searched and returned on confirm
Item.Desc   := 'description'; // also searched, displayed alongside
```

**TFilteredPicker keyboard shortcuts:**

| Key | Action |
|-----|--------|
| Up/Down | Move through filtered list |
| Page Up/Down | Bulk scroll |
| Home/End | Jump to start/end |
| Any character | Append to search filter, reset list |
| Backspace/Delete | Edit search |
| Enter (first press) | Stage selection: pre-fills search with selected label |
| Enter (second press) | Confirm staged selection |
| Esc | Cancel |

**Staging behavior:** The first Enter pre-fills the search box with the selected item's label (allowing refinement). A second Enter confirms. If the list is empty the first Enter also confirms.

**One-shot helper:**

```pascal
var
  Items: array of TFilteredPickerItem;
  Result: string;
begin
  // populate Items...
  if RunFilteredPicker('Title', Items, Result, InitialValue) then
    // Result holds the selected Label_
end;
```

---

### TermUI.PathPicker

Recursive directory/file browser with filtering and optional directory creation.

**Features:**
- Recursive enumeration from a base directory
- Directories-only mode
- Substring filter on path
- Hidden files shown when filter starts with `.`
- Prompts to create missing directories on accept

**Keyboard shortcuts:**

| Key | Action |
|-----|--------|
| Up/Down | Move selection |
| Page Up/Down | Bulk scroll |
| Home/End | Jump to bounds |
| Enter (on directory) | Descend: update filter, rebuild list |
| Enter (on file or empty filter) | Accept selection |
| Backspace | Remove last path component |
| Any character | Append to filter |
| Tab | Toggle focus between filter field and file list |
| Esc | Cancel |

Directories are displayed with a trailing `/` in cyan.

**One-shot helper:**

```pascal
var Path: string;
begin
  if RunPathPicker(BaseDir, 'Select a file', {DirsOnly=}False, Path) then
    // Path holds the selected path
end;
```

---

### TermUI.AsciiDocViewer

Full-featured AsciiDoc-subset viewer with table of contents and syntax highlighting.

**Supported syntax:**
- Headings: `= H1`, `== H2`, `=== H3`, `==== H4`
- Paragraphs with word-wrap
- Fenced code blocks (indented or `----` delimited)
- Bullet lists (`* item`, `- item`)
- Horizontal rules (`---`, `***`)
- Tables (basic)
- Comments (`//`)
- Inline markup: `` `monospace` ``, `*bold*`, `_italic_`

**UI layout:**
- Left pane (22 cols): table of contents from H2 headings, scrollable
- Separator: vertical line
- Right pane: word-wrapped document content
- Help footer with navigation hints

**Keyboard shortcuts:**

| Key | Action |
|-----|--------|
| Tab / Left / Right | Toggle focus: TOC ↔ Content |
| Up/Down | Scroll within active pane |
| Page Up/Down | Bulk scroll |
| Home/End | Jump to bounds |
| Enter (on TOC item) | Jump content to that section |
| Esc / Q | Close |

**Colors:** H1 cyan, H2 yellow, H3/H4 green, code blocks dark background, bullets yellow, inline monospace highlighted.

**Loading content:**

```pascal
Viewer := TAsciiDocViewer.Create;
Viewer.SetContent(Lines, 'Title', 'SectionKey');  // ContextKey scrolls to that H2 on open
Application.ShowModal(Viewer);
```

---

## Quick Start

```pascal
uses
  TermUI.Application, TermUI.Menu, TermUI.Terminal;

var
  Menu: TMenu;
begin
  Application.Initialize;
  Application.Terminal.EnterAltScreen;

  Menu := TMenu.Create;
  Menu.Title := 'Main Menu';
  Menu.Items.Add(TMenuItem.Create('Open',   @DoOpen,  '', 'O', ''));
  Menu.Items.Add(TMenuItem.Create('Save',   @DoSave,  '', 'S', ''));
  Menu.Items.Add(TMenuItem.CreateSeparator);
  Menu.Items.Add(TMenuItem.Create('Quit',   @DoQuit,  '', 'Q', ''));

  Application.ShowModal(Menu);

  Application.Terminal.ExitAltScreen;
  Application.Finalize;
end;
```

---

## Platform Support

| Feature | Linux/macOS/BSD | Windows 10+ | Windows (legacy) |
|---------|----------------|-------------|-----------------|
| Raw mode | `termios` | VT processing | `ReadConsoleInput` |
| Colors | ANSI 16-color | ANSI 16-color | Console attributes |
| Resize | SIGWINCH | `WINDOW_BUFFER_SIZE_EVENT` | same |
| Ctrl+arrows | Yes | Yes | Partial |
| Alternate screen | Yes | Yes | No |

---

## Project Layout

```
termui/
  src/
    main/
      pascal/
        TermUI.Application.pas
        TermUI.AsciiDocViewer.pas
        TermUI.Control.pas
        TermUI.FilteredPicker.pas
        TermUI.Forms.pas
        TermUI.Menu.pas
        TermUI.PathPicker.pas
        TermUI.Terminal.pas
        platform/
          unix/   TermUI.Terminal.Platform.pas
          windows/ TermUI.Terminal.Platform.pas
  pasbuildeditor_termui.lpk   (Lazarus package)
  project.xml
```
