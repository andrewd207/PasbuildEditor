program TestRunner;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes,
  fpcunit,
  testregistry,
  consoletestrunner,
  PBE.Test.ProjectModel;

var
  Application: TTestRunner;

begin
  Application := TTestRunner.Create(nil);
  try
    Application.Initialize;
    Application.Title := 'PasbuildEditor Tests';
    Application.Run;
  finally
    Application.Free;
  end;
end.
