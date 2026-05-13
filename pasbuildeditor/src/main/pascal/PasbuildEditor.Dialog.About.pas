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
  TermUI.Terminal, TermUI.Menu, TermUI.Forms, TermUI.Application,
  PasbuildEditor.Consts,
  PasbuildEditor.UI.Colors;

type
  TAboutForm = class(TForm)
  private
    FLicLines:    TStringList;
    FLicStartRow: Integer;
    FLicPaneRows: Integer;
    FLicScrollOff: Integer;
    FMaxScroll:   Integer;

    procedure ComputeLayout;
    procedure DrawStaticContent;
  protected
    procedure DoPaint; override;
    function  DoKeyDown(var Key: TKeyEvent): Boolean; override;
  public
    constructor Create(const ATitle: string = ''); override;
    destructor  Destroy; override;
  end;

constructor TAboutForm.Create(const ATitle: string);
begin
  inherited Create(ATitle);
  FLicLines := TStringList.Create;
  FLicLines.Text := LICENSE_TEXT;
  FLicScrollOff := 0;
end;

destructor TAboutForm.Destroy;
begin
  FLicLines.Free;
  inherited;
end;

procedure TAboutForm.ComputeLayout;
begin
  { LicStartRow is set during DrawStaticContent; approximate here }
  FLicStartRow  := 17;  { updated precisely in DrawStaticContent }
  FLicPaneRows  := Term.Height - 2 - FLicStartRow + 1;
  if FLicPaneRows < 1 then FLicPaneRows := 1;
  FMaxScroll    := FLicLines.Count - FLicPaneRows;
  if FMaxScroll < 0 then FMaxScroll := 0;
  if FLicScrollOff > FMaxScroll then FLicScrollOff := FMaxScroll;
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
  Inc(Row);

  FLicStartRow := Row;
  FLicPaneRows := Term.Height - 2 - FLicStartRow + 1;
  if FLicPaneRows < 1 then FLicPaneRows := 1;
  FMaxScroll   := FLicLines.Count - FLicPaneRows;
  if FMaxScroll < 0 then FMaxScroll := 0;
  if FLicScrollOff > FMaxScroll then FLicScrollOff := FMaxScroll;
  DrawRule(Term.Height - 1, 1, Term.Width);
end;

procedure TAboutForm.DoPaint;
var J, R, I: Integer;
begin
  DrawStaticContent;

  for J := 0 to FLicPaneRows - 1 do
  begin
    R := FLicStartRow + J;
    I := FLicScrollOff + J;
    Term.GotoXY(1, R); Term.ClearToEOL;
    if (I < FLicLines.Count) and (Trim(FLicLines[I]) <> '') then
    begin
      ColorRule;
      Term.WriteStr('  ' + FLicLines[I]);
      Term.ResetColors;
    end;
  end;

  Term.GotoXY(1, Term.Height); Term.ClearToEOL;
  ColorHelp;
  Term.WriteStr(' ↑↓ Scroll license   Any other key to return ');
  if FMaxScroll > 0 then
  begin
    Term.GotoXY(Term.Width - 8, Term.Height);
    Term.WriteStr(IntToStr(FLicScrollOff + 1) + '/' + IntToStr(FMaxScroll + 1));
  end;
  Term.ResetColors;

  inherited DoPaint;
end;

function TAboutForm.DoKeyDown(var Key: TKeyEvent): Boolean;
begin
  Result := True;
  case Key.Code of
    kcUp:
      if FLicScrollOff > 0 then begin Dec(FLicScrollOff); Invalidate; end;
    kcDown:
      if FLicScrollOff < FMaxScroll then begin Inc(FLicScrollOff); Invalidate; end;
    kcPageUp: begin
      FLicScrollOff := FLicScrollOff - FLicPaneRows;
      if FLicScrollOff < 0 then FLicScrollOff := 0;
      Invalidate;
    end;
    kcPageDown: begin
      FLicScrollOff := FLicScrollOff + FLicPaneRows;
      if FLicScrollOff > FMaxScroll then FLicScrollOff := FMaxScroll;
      Invalidate;
    end;
    else begin
      Close(1);
      Result := False;
    end;
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
