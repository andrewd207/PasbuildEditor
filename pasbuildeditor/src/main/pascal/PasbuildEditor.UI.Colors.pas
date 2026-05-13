{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.UI.Colors;

{$mode objfpc}{$H+}

interface

uses
  TermUI.Terminal;

procedure ColorNormal;
procedure ColorSelFG;
procedure ColorValue;
procedure ColorHelp;
procedure ColorSearch;
procedure ColorSource;
procedure ColorNew;
procedure ColorOld;
procedure ColorHeader;
procedure ColorRule;

implementation

procedure ColorNormal;  begin Term.ResetColors; end;
procedure ColorSelFG;   begin Term.SetFG(clBlack); Term.SetBG(clCyan); end;
procedure ColorValue;   begin Term.SetFG(clGreen); end;
procedure ColorHelp;    begin Term.SetFG(clBrightBlack); end;
procedure ColorSearch;  begin Term.SetFG(clWhite); Term.SetBG(clBlue); end;
procedure ColorSource;  begin Term.SetFG(clBrightBlack); end;
procedure ColorNew;     begin Term.SetFG(clBrightGreen); end;
procedure ColorOld;     begin Term.SetFG(clYellow); end;
procedure ColorHeader;  begin Term.SetFG(clBrightYellow); end;
procedure ColorRule;    begin Term.SetFG(clBrightBlack); end;

end.
