{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.StringUtils;

{$mode objfpc}{$H+}
{$modeswitch typehelpers}

interface

const
  CStrLow = 0;

{ Returns the substring of AStr starting at AFrom with ACount characters.
  AFrom is 0-based, so 0 is always the first character. }
function CopyNeutral(const AStr: string; AFrom, ACount: Integer): string;

{ Searches for ASubStr in AStr. Returns True if found, setting AFoundPos to
  the 0-based index of the match. }
function PosNeutral(const ASubStr, AStr: string; out AFoundPos: Integer): Boolean;

{ Returns True if ASubStr is found anywhere in AStr. }
function PosNeutral(const ASubStr, AStr: string): Boolean;

{ Deletes ACount characters from AStr starting at 0-based position AFrom. }
procedure DeleteNeutral(var AStr: string; AFrom, ACount: Integer);

{ Returns the character at 0-based position AIndex. }
function CharFromIndex(const AStr: string; AIndex: Integer): Char;

{ Returns the number of bytes in the UTF-8 sequence starting at byte AStr[I]
  (1-based). Returns 1 for ASCII or invalid leading bytes. }
function UTF8SeqLen(const AStr: string; I: Integer): Integer;

{ Returns the visual display width of AStr in terminal columns, counting each
  UTF-8 codepoint as 1 column. }
function UTF8VisualLen(const AStr: string): Integer;

type
  TStringHelper = type helper for string
  private
    function  GetIndex(AIndex: Integer): Char;
    procedure SetIndex(AIndex: Integer; AValue: Char);
  public
    property Index[AIndex: Integer]: Char read GetIndex write SetIndex;
  end;

implementation

function CopyNeutral(const AStr: string; AFrom, ACount: Integer): string;
begin
  Result := Copy(AStr, AFrom + 1, ACount);
end;

function PosNeutral(const ASubStr, AStr: string; out AFoundPos: Integer): Boolean;
var
  P: Integer;
begin
  P := Pos(ASubStr, AStr);
  Result := P <> 0;
  if Result then
    AFoundPos := P - 1
  else
    AFoundPos := -1;
end;

function PosNeutral(const ASubStr, AStr: string): Boolean;
begin
  Result := Pos(ASubStr, AStr) <> 0;
end;

procedure DeleteNeutral(var AStr: string; AFrom, ACount: Integer);
begin
  Delete(AStr, AFrom + 1, ACount);
end;

function CharFromIndex(const AStr: string; AIndex: Integer): Char;
begin
  Result := AStr[AIndex + 1];
end;

function UTF8SeqLen(const AStr: string; I: Integer): Integer;
var B: Byte;
begin
  B := Ord(AStr[I]);
  if B < $80 then Result := 1
  else if B < $E0 then Result := 2
  else if B < $F0 then Result := 3
  else Result := 4;
end;

function UTF8VisualLen(const AStr: string): Integer;
var I: Integer;
begin
  Result := 0;
  I := 1;
  while I <= Length(AStr) do
  begin
    Inc(Result);
    Inc(I, UTF8SeqLen(AStr, I));
  end;
end;

function TStringHelper.GetIndex(AIndex: Integer): Char;
begin
  Result := Self[AIndex + 1];
end;

procedure TStringHelper.SetIndex(AIndex: Integer; AValue: Char);
begin
  Self[AIndex + 1] := AValue;
end;

end.
