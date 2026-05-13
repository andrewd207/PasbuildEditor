{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Dialog.About;

{$mode objfpc}{$H+}

interface

{ Show the full-screen About / license page. Blocks until the user presses a
  non-scroll key. }
procedure ShowAboutPage;

implementation

uses
  Classes, SysUtils,
  TermUI.Terminal, TermUI.Menu,
  PasbuildEditor.Consts,
  PasbuildEditor.UI.Colors;

procedure ShowAboutPage;

  procedure WriteRow(Row: Integer; const S: string; AFG: TColor = clDefault);
  begin
    Term.GotoXY(1, Row);
    Term.ClearToEOL;
    if AFG <> clDefault then Term.SetFG(AFG);
    Term.WriteStr('  ' + S);
    Term.ResetColors;
  end;

  procedure WriteURL(Row: Integer; const S: string);
  begin
    Term.GotoXY(1, Row);
    Term.ClearToEOL;
    Term.SetFG(clBrightBlack);
    Term.WriteStr('    ');
    Term.SetFG(clCyan);
    Term.WriteStr(S);
    Term.ResetColors;
  end;

var
  W, Row, I:    Integer;
  LicLines:     TStringList;
  LicStartRow:  Integer;
  LicPaneRows:  Integer;
  LicScrollOff: Integer;
  K:            TKeyEvent;
  MaxScroll:    Integer;

  procedure DrawLicensePane;
  var J, R: Integer;
  begin
    for J := 0 to LicPaneRows - 1 do
    begin
      R := LicStartRow + J;
      I := LicScrollOff + J;
      Term.GotoXY(1, R);
      Term.ClearToEOL;
      if I < LicLines.Count then
      begin
        if Trim(LicLines[I]) <> '' then
        begin
          ColorRule;
          Term.WriteStr('  ' + LicLines[I]);
          Term.ResetColors;
        end;
      end;
    end;
    Term.GotoXY(1, Term.Height);
    Term.ClearToEOL;
    ColorHelp;
    Term.WriteStr(' ↑↓ Scroll license   Any other key to return ');
    if MaxScroll > 0 then
    begin
      Term.GotoXY(Term.Width - 8, Term.Height);
      Term.WriteStr(IntToStr(LicScrollOff + 1) + '/' + IntToStr(MaxScroll + 1));
    end;
    Term.ResetColors;
    Term.FlushOutput;
  end;

begin
  LicLines := TStringList.Create;
  try
    LicLines.Text := LICENSE_TEXT;

    repeat
      Term.ClearScreen;
      W := Term.Width;
      DrawHeader('About', 1);

      Row := 4;
      Term.SetFG(clBrightCyan);
      Term.GotoXY(1, Row); Term.ClearToEOL;
      Term.WriteStr('  ' + APP_TITLE + '  v' + APP_VERSION);
      Term.ResetColors;

      Inc(Row);
      WriteRow(Row, AUTHOR_COPYRIGHT, clBrightBlack);
      Inc(Row);
      WriteURL(Row, AUTHOR_URL);
      Inc(Row);
      WriteURL(Row, APP_URL);

      Inc(Row, 2);
      WriteRow(Row, 'A console editor for pasbuild project.xml files.', clDefault);

      Inc(Row, 2);
      WriteRow(Row, 'Special thanks', clBrightBlack);
      Inc(Row);
      Term.GotoXY(1, Row); Term.ClearToEOL;
      Term.WriteStr('  Thanks to ');
      Term.SetFG(clBrightCyan);
      Term.WriteStr(PASBUILD_AUTHOR);
      Term.ResetColors;
      Term.WriteStr(' for creating pasbuild.');
      Inc(Row);
      WriteURL(Row, PASBUILD_AUTHOR_URL);
      Inc(Row);
      WriteURL(Row, PASBUILD_URL);

      Inc(Row, 2);
      DrawRule(Row, 1, W);
      Inc(Row);
      Term.GotoXY(1, Row); Term.ClearToEOL;
      ColorHeader;
      Term.WriteStr('  License');
      Term.ResetColors;
      Inc(Row);

      LicStartRow  := Row;
      LicPaneRows  := Term.Height - 2 - LicStartRow + 1;
      if LicPaneRows < 1 then LicPaneRows := 1;
      MaxScroll    := LicLines.Count - LicPaneRows;
      if MaxScroll < 0 then MaxScroll := 0;
      LicScrollOff := 0;

      DrawRule(Term.Height - 1, 1, W);
      DrawLicensePane;

      repeat
        K := Term.ReadKey;
        if Term.HasResized then Break;
        case K.Code of
          kcUp: begin
            if LicScrollOff > 0 then begin Dec(LicScrollOff); DrawLicensePane; end;
          end;
          kcDown: begin
            if LicScrollOff < MaxScroll then begin Inc(LicScrollOff); DrawLicensePane; end;
          end;
          kcPageUp: begin
            LicScrollOff := LicScrollOff - LicPaneRows;
            if LicScrollOff < 0 then LicScrollOff := 0;
            DrawLicensePane;
          end;
          kcPageDown: begin
            LicScrollOff := LicScrollOff + LicPaneRows;
            if LicScrollOff > MaxScroll then LicScrollOff := MaxScroll;
            DrawLicensePane;
          end;
          else Exit;
        end;
      until False;
    until False;

  finally
    LicLines.Free;
  end;
end;

end.
