{
  termui-example-filedialog — demonstrates TFileDialog / helper functions.

  This program shows four scenarios in sequence:
    1. Open a single file (any type)         — RunOpenDialog helper
    2. Open a Pascal source file             — RunOpenDialog + FileFilter
    3. Save a file                           — RunSaveDialog helper
    4. Select a directory                    — RunDirDialog helper
    5. Low-level: construct TFileDialog by hand for full control

  TApplication / the terminal must be initialised before any dialog is shown.
  Tear it down with Application.Done before exiting.
}

program Main;

{$mode objfpc}{$H+}

{ cthreads must be the very first unit on UNIX — TTimer (used inside TermUI)
  spins a background thread, and the RTL needs thread support initialised
  before the first thread is created. }
{$IFDEF UNIX}
uses
  cthreads,
{$ELSE}
uses
{$ENDIF}
  SysUtils,
  { Core TermUI units needed to bootstrap the application.
    TermUI.Terminal automatically pulls in the platform back-end (Unix or
    Windows), so no platform unit needs to be listed here explicitly. }
  TermUI.Terminal,          { Term singleton — raw terminal access            }
  TermUI.Application,       { Application singleton — event loop, form stack  }
  TermUI.Forms,             { TForm base class                                }
  { The file dialog unit.  Exports TFileDialog plus three one-shot helpers. }
  TermUI.Form.FileDialog;


{ ── Demo helpers ─────────────────────────────────────────────────────────── }

{ Show a plain message on the terminal and wait for Enter.
  We do this outside of any form — the helpers below call Application.Done
  before we reach here, so direct Term writes are safe. }
procedure Pause(const AMsg: string);
begin
  { Clear the alt-screen and reset colours before writing plain text.
    Without this the output lands on top of whatever the last dialog drew. }
  Term.ResetColors;
  Term.ClearScreen;
  Term.GotoXY(1, 1);
  WriteLn(AMsg);
  WriteLn('Press Enter to continue...');
  ReadLn;
end;


{ ── Scenario 1: open any file ─────────────────────────────────────────────

  RunOpenDialog is the simplest entry point.  Pass:
    AInitialDir  — directory the dialog opens in; usually GetCurrentDir or
                   ExtractFilePath(someKnownFile).
    APath        — in/out: on entry ignored; on True return holds the chosen
                   absolute path.
    ATitle       — optional title shown in the header row (default 'Open').

  Returns True when the user confirmed a selection, False on Escape / cancel.

  The dialog handles all keyboard navigation internally:
    ↑ ↓            move selection in the file list
    Enter / Right  enter a directory or confirm a file
    Backspace      navigate up one directory (when filter is empty)
    Left           navigate up one directory
    Tab            move focus between the file list and the Filename field
    Ctrl+H         toggle hidden files (dotfiles)
    Typing         filters the list by substring in file list focus;
                   edits the filename in filename-field focus
    Esc            cancel and return False
}
procedure DemoOpenAny;
var
  Path: string;
begin
  Path := '';
  if RunOpenDialog(GetCurrentDir, Path) then
    Pause('You chose: ' + Path)
  else
    Pause('Open cancelled.');
end;


{ ── Scenario 2: open a Pascal source file ─────────────────────────────────

  For file-type filtering, construct TFileDialog directly and set FileFilter
  before calling RunModal.

  FileFilter is a semicolon-separated list of glob patterns that restricts
  which FILES appear in the list.  Directories are always shown so the user
  can still navigate.

  Examples:
    '*.pas'          — Pascal source only
    '*.pas;*.pp'     — Pascal source + program files
    '*.xml'          — XML files only
    '*'  (default)   — everything

  After RunModal returns, check Accepted.  If True, ResultPath holds the
  full absolute path the user confirmed.
}
procedure DemoOpenPascal;
var
  Dlg:  TFileDialog;
  Path: string;
begin
  Dlg := TFileDialog.Create('Open Pascal File');
  try
    { Define the named filters before SetParams.  The first filter added
      becomes the active one automatically.  Tab in the file list opens the
      filter picker showing these entries. }
    Dlg.AddFilter('Pascal files', '*.pas;*.pp');
    Dlg.AddFilter('All files',    '*');

    { Navigate to the current directory to start. }
    Dlg.SetParams(GetCurrentDir, fdOpen);

    if Dlg.RunModal then
      Path := Dlg.ResultPath
    else
      Path := '';
  finally
    Dlg.Free;
  end;

  if Path <> '' then
    Pause('Pascal file: ' + Path)
  else
    Pause('Open Pascal cancelled.');
end;


{ ── Scenario 3: save a file ───────────────────────────────────────────────

  RunSaveDialog behaves like RunOpenDialog but:
    • The mode is fdSave: the Filename field starts focused so the user can
      type a new name immediately.
    • Selecting an existing file pre-fills the Filename field (so the user
      can overwrite it or edit the name).
    • The confirm button label reads "Save" in the hint bar.

  The second parameter to SetParams (or the AInitialFilename argument on the
  full constructor path) pre-populates the Filename field.  Pass '' to leave
  it empty.
}
procedure DemoSave;
var
  Path: string;
begin
  Path := '';

  { Pre-fill with a suggested filename so the user only has to pick a dir. }
  if RunSaveDialog(GetCurrentDir, Path, 'Save As') then
    Pause('Save to: ' + Path)
  else
    Pause('Save cancelled.');
end;


{ ── Scenario 4: select a directory ───────────────────────────────────────

  RunDirDialog uses mode fdSelectDir:
    • Files are greyed out and cannot be selected.
    • Pressing Enter on a directory navigates into it.
    • The "Select" action confirms the CURRENT directory shown in the path
      bar (not a highlighted entry) — the user presses Enter on the '.'
      entry or uses the Filename field left blank.

  Useful for choosing an output directory, a project root, etc.
}
procedure DemoSelectDir;
var
  Path: string;
begin
  Path := '';
  if RunDirDialog(GetCurrentDir, Path, 'Select Output Directory') then
    Pause('Directory: ' + Path)
  else
    Pause('Dir select cancelled.');
end;


{ ── Scenario 5: full manual construction ─────────────────────────────────

  Use TFileDialog directly when you need:
    • A pre-filled initial filename (third arg to SetParams).
    • Different starting directories per invocation.
    • Access to Accepted / ResultPath after the dialog closes (e.g. if you
      keep the instance alive).

  SetParams(AInitialDir, AMode, AInitialFilename)
    AInitialDir      — starting directory (must exist; falls back to '/' on error)
    AMode            — fdOpen, fdSave, or fdSelectDir
    AInitialFilename — pre-populate the Filename field (optional, default '')

  After RunModal:
    Dlg.Accepted    — True if the user confirmed
    Dlg.ResultPath  — full absolute path (only meaningful when Accepted = True)
}
procedure DemoManual;
var
  Dlg: TFileDialog;
begin
  Dlg := TFileDialog.Create('Export Config');
  try
    { Open in the home directory, save mode, suggest a filename. }
    Dlg.SetParams(GetUserDir, fdSave, 'config-export.xml');

    { Named filters — Tab opens the picker. }
    Dlg.AddFilter('XML files',  '*.xml');
    Dlg.AddFilter('All files',  '*');

    Dlg.RunModal;

    { Inspect results after RunModal returns. }
    if Dlg.Accepted then
      Pause('Export path: ' + Dlg.ResultPath)
    else
      Pause('Export cancelled.');
  finally
    Dlg.Free;  { always free — TFileDialog owns its internal TForm resources }
  end;
end;


{ ── Main ──────────────────────────────────────────────────────────────────── }

begin
  { Switch the terminal into raw (non-canonical) mode so that TermUI can read
    individual keypresses without waiting for Enter.  Must be done before any
    dialog is shown. }
  Term.EnableRawMode;

  { Hide the blinking cursor so it does not flicker during redraws. }
  Term.HideCursor;

  { Switch to the alternate screen buffer so the dialog output does not
    scroll the user's existing terminal history.  The original screen is
    restored by ExitAltScreen below. }
  Term.EnterAltScreen;
  try
    WriteLn('=== TFileDialog example ===');
    WriteLn('Five scenarios will run in sequence.');
    WriteLn('Press Enter to start...');
    ReadLn;

    WriteLn('--- 1. Open any file ---');
    DemoOpenAny;

    WriteLn('--- 2. Open a Pascal file (filtered) ---');
    DemoOpenPascal;

    WriteLn('--- 3. Save a file ---');
    DemoSave;

    WriteLn('--- 4. Select a directory ---');
    DemoSelectDir;

    WriteLn('--- 5. Manual construction with pre-filled filename ---');
    DemoManual;

    WriteLn('All scenarios done.');
  finally
    { Restore the terminal: leave the alternate screen, show the cursor, and
      turn off raw mode.  The finally block guarantees cleanup even on error. }
    Term.ExitAltScreen;
    Term.ShowCursor;
    Term.DisableRawMode;
  end;
end.
