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
  Classes, SysUtils, Math,
  TermUI.Terminal, TermUI.Menu, TermUI.Forms, TermUI.Application,
  TermUI.Control.Editor,
  PasbuildEditor.Consts,
  PasbuildEditor.UI.Colors;

const
  { Row at which the scrollable license text starts.
    Matches the number of static header rows drawn by DrawStaticContent. }
  LIC_START_ROW = 18;

type
  TAboutForm = class(TForm)
  private
    FLicEditor: TTextEditor;  { read-only scroll view for license text }

    procedure DrawStaticContent;
  protected
    procedure DoPaint; override;
    procedure DoBoundsChanged; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
  public
    constructor Create(const ATitle: string = ''); override;
  end;

constructor TAboutForm.Create(const ATitle: string);
begin
  inherited Create(ATitle);

  FLicEditor          := TTextEditor.Create;
  FLicEditor.ReadOnly := True;
  FLicEditor.Lines.Text := LICENSE_TEXT;
  AddChild(FLicEditor);

  FLicEditor.SetBounds(1, LIC_START_ROW, Width,
    Max(1, Height - LIC_START_ROW - 1));
end;

procedure TAboutForm.DoBoundsChanged;
begin
  if FLicEditor = nil then Exit;
  FLicEditor.SetBounds(1, LIC_START_ROW, Width,
    Max(1, Height - LIC_START_ROW - 1));
end;

procedure TAboutForm.DrawStaticContent;
var Row: Integer;

  procedure WriteRow(R: Integer; const S: string; AFG: TColor);
  begin
    Term.GotoXY(1, R); Term.ClearToEOL;
    if AFG <> clDefault then Term.SetFG(AFG);
    Term.WriteStr('  ' + S);
    Term.ResetColors;
  end;

  procedure WriteURL(R: Integer; const S: string);
  begin
    Term.GotoXY(1, R); Term.ClearToEOL;
    Term.SetFG(clBrightBlack); Term.WriteStr('    ');
    Term.SetFG(clCyan); Term.WriteStr(S);
    Term.ResetColors;
  end;

begin
  Term.ClearScreen;
  DrawHeader('About', 1);

  Row := 4;
  Term.SetFG(clBrightCyan);
  Term.GotoXY(1, Row); Term.ClearToEOL;
  Term.WriteStr('  ' + APP_TITLE + '  v' + APP_VERSION);
  Term.ResetColors;
  Inc(Row);
  WriteRow(Row, AUTHOR_COPYRIGHT, clBrightBlack); Inc(Row);
  WriteURL(Row, AUTHOR_URL); Inc(Row);
  WriteURL(Row, APP_URL);    Inc(Row, 2);
  WriteRow(Row, 'A console editor for pasbuild project.xml files.', clDefault); Inc(Row, 2);
  WriteRow(Row, 'Special thanks', clBrightBlack); Inc(Row);
  Term.GotoXY(1, Row); Term.ClearToEOL;
  Term.WriteStr('  Thanks to ');
  Term.SetFG(clBrightCyan); Term.WriteStr(PASBUILD_AUTHOR);
  Term.ResetColors; Term.WriteStr(' for creating pasbuild.');
  Inc(Row);
  WriteURL(Row, PASBUILD_AUTHOR_URL); Inc(Row);
  WriteURL(Row, PASBUILD_URL);        Inc(Row, 2);
  DrawRule(Row, 1, Term.Width); Inc(Row);
  Term.GotoXY(1, Row); Term.ClearToEOL;
  ColorHeader; Term.WriteStr('  License'); Term.ResetColors;
  { Row is now LIC_START_ROW — license editor occupies LIC_START_ROW..Height-2 }

  DrawRule(Term.Height - 1, 1, Term.Width);
  Term.GotoXY(1, Term.Height); Term.ClearToEOL;
  ColorHelp;
  Term.WriteStr(' ↑↓/PgUp/PgDn Scroll license   Any other key to return ');
  Term.ResetColors;
end;

procedure TAboutForm.DoPaint;
begin
  DrawStaticContent;
  inherited DoPaint;  { paints FLicEditor child }
end;

function TAboutForm.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  { Scroll keys go to FLicEditor via normal focus dispatch }
  Result := inherited DoKeyDown(Key);
  if Result then
    Invalidate  { ensure form repaints after scroll }
  else
  begin
    Close(1);
    Result := True;
  end;
end;

procedure ShowAboutPage;
var
  Form: TAboutForm;
begin
  Form := TAboutForm.Create;
  try
    Application.ShowModal(Form);
  finally
    Form.Free;
  end;
end;

end.
