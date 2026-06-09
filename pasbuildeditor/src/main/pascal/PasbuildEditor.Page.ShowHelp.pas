{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit PasbuildEditor.Page.ShowHelp;

{$mode objfpc}{$H+}
{$R '../resources/help/help.res'}

interface

{ Show the help page for ADocName (e.g. 'project', 'build', 'modules').
  AContextKey is the menu item label to scroll to; empty = show from top. }
procedure ShowHelpPage(const ADocName: string; const AContextKey: string = '');

implementation

uses
  Classes, SysUtils,
  TermUI.Application, TermUI.AsciiDocViewer;

procedure ShowHelpPage(const ADocName: string; const AContextKey: string);
var
  Form:      TAsciiDocViewer;
  ResStream: TResourceStream;
  RawLines:  TStringList;
begin
  if ADocName = '' then Exit;
  RawLines := TStringList.Create;
  try
    try
      ResStream := TResourceStream.Create(HInstance, 'HELP_' + UpperCase(ADocName), RT_RCDATA);
    except
      on E: EResNotFound do
      begin
        RawLines.Free;
        Exit;
      end;
    end;
    try
      RawLines.LoadFromStream(ResStream);
    finally
      ResStream.Free;
    end;
    Form := TAsciiDocViewer.Create;
    try
      Form.SetContent(RawLines, ADocName, AContextKey);
      Application.ShowModal(Form);
    finally
      Form.Free;
    end;
  finally
    RawLines.Free;
  end;
end;

end.
