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

type
  TUTF8Char = RawByteString;

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

{ Inserts ACh into AStr before the character at 0-based position APos.
  APos = 0 prepends; APos = Length(AStr) appends. }
procedure InsertNeutral(var AStr: string; ACh: TUTF8Char; APos: Integer);

{ Returns the character at 0-based position AIndex. }
function CharFromIndex(const AStr: string; AIndex: Integer): Char;

{ Returns the number of bytes in the UTF-8 sequence starting at byte AStr[I]
  (1-based). Returns 1 for ASCII or invalid leading bytes. }
function UTF8SeqLen(const AStr: string; I: Integer): Integer;

{ Returns the number of UTF-8 codepoints in AStr. }
function UTF8VisualLen(const AStr: string): Integer;

type
  TStringHelper = type helper for String
  private
    function  GetIndex(AIndex: Integer): Char;
    procedure SetIndex(AIndex: Integer; AValue: Char);
    function  GetChar(ACharIdx: Integer): RawByteString;
    procedure SetChar(ACharIdx: Integer; const AValue: RawByteString);
    function  GetCharLength: Integer;
    function  GetSize: Integer;
    { Returns the 1-based byte position of the start of the 0-based char at ACharIdx.
      Returns Size+1 when ACharIdx is past the end. }
    function  CharBytePos(ACharIdx: Integer): Integer;
    { Returns the number of bytes spanned by ACharCount codepoints starting at
      1-based byte position AByteStart. }
    function  CharByteSpan(AByteStart, ACharCount: Integer): Integer;
  public
    { Byte-level indexed access (0-based). Existing callers use this. }
    property Index[AIndex: Integer]: Char read GetIndex write SetIndex;

    { UTF-8 codepoint access (0-based). Read returns the codepoint; write inserts AValue before position ACharIdx. }
    property Chars[ACharIdx: Integer]: TUtf8Char read GetChar write SetChar;

    { Number of UTF-8 codepoints (characters), not bytes. }
    property Length: Integer read GetCharLength;

    { Number of bytes in the underlying string storage. }
    property Size: Integer read GetSize;

    { Returns a substring of ACount codepoints starting at 0-based codepoint
      index AFrom. }
    function Copy(AFrom, ACount: Integer): string;

    { Removes ACount codepoints starting at 0-based codepoint index AFrom. }
    procedure Delete(AFrom, ACount: Integer);
  end;

  TRawByteStringHelper = type helper for RawbyteString
  private
    function  GetIndex(AIndex: Integer): Char;
    procedure SetIndex(AIndex: Integer; AValue: Char);
    function  GetChar(ACharIdx: Integer): RawByteString;
    procedure SetChar(ACharIdx: Integer; const AValue: RawByteString);
    function  GetCharLength: Integer;
    function  GetSize: Integer;
    { Returns the 1-based byte position of the start of the 0-based char at ACharIdx.
      Returns Size+1 when ACharIdx is past the end. }
    function  CharBytePos(ACharIdx: Integer): Integer;
    { Returns the number of bytes spanned by ACharCount codepoints starting at
      1-based byte position AByteStart. }
    function  CharByteSpan(AByteStart, ACharCount: Integer): Integer;
  public
    { Byte-level indexed access (0-based). Existing callers use this. }
    property Index[AIndex: Integer]: Char read GetIndex write SetIndex;

    { UTF-8 codepoint access (0-based). Read returns the codepoint; write inserts AValue before position ACharIdx. }
    property Chars[ACharIdx: Integer]: TUtf8Char read GetChar write SetChar;

    { Number of UTF-8 codepoints (characters), not bytes. }
    property Length: Integer read GetCharLength;

    { Number of bytes in the underlying string storage. }
    property Size: Integer read GetSize;

    { Returns a substring of ACount codepoints starting at 0-based codepoint
      index AFrom. }
    function Copy(AFrom, ACount: Integer): string;

    { Removes ACount codepoints starting at 0-based codepoint index AFrom. }
    procedure Delete(AFrom, ACount: Integer);
  end;

function CharIsOneOf(C: TUtf8Char; const A: array of Char): Boolean;

implementation

function CharIsOneOf(C: TUtf8Char; const A: array of Char): Boolean;
var
  I: Integer;
begin
  for I := Low(A) to High(A) do
    if A[I] = C then
    begin
      Result := True;
      Exit;
    end;
  Result := False;
end;




function CopyNeutral(const AStr: string; AFrom, ACount: Integer): string;
begin
  Result := AStr.Copy(AFrom, ACount);
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
  AStr.Delete(AFrom, ACount);
end;

procedure InsertNeutral(var AStr: string; ACh: TUTF8Char; APos: Integer);
begin
  AStr.Chars[APos] := ACh;
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
  while I <= System.Length(AStr) do
  begin
    Inc(Result);
    Inc(I, UTF8SeqLen(AStr, I));
  end;
end;

{ ── TStringHelper ── }

function TStringHelper.GetIndex(AIndex: Integer): Char;
begin
  Result := Self[AIndex + 1];
end;

procedure TStringHelper.SetIndex(AIndex: Integer; AValue: Char);
begin
  Self[AIndex + 1] := AValue;
end;

function TStringHelper.CharBytePos(ACharIdx: Integer): Integer;
var CharCount: Integer;
begin
  Result := 1;
  CharCount := 0;
  while (Result <= System.Length(Self)) and (CharCount < ACharIdx) do
  begin
    Inc(Result, UTF8SeqLen(Self, Result));
    Inc(CharCount);
  end;
end;

function TStringHelper.CharByteSpan(AByteStart, ACharCount: Integer): Integer;
var I, CharCount: Integer;
begin
  I := AByteStart;
  CharCount := 0;
  while (I <= System.Length(Self)) and (CharCount < ACharCount) do
  begin
    Inc(I, UTF8SeqLen(Self, I));
    Inc(CharCount);
  end;
  Result := I - AByteStart;
end;

function TStringHelper.GetChar(ACharIdx: Integer): RawByteString;
var BytePos, SeqLen: Integer;
begin
  BytePos := CharBytePos(ACharIdx);
  if BytePos > System.Length(Self) then
    Result := ''
  else
  begin
    SeqLen := UTF8SeqLen(Self, BytePos);
    Result := System.Copy(Self, BytePos, SeqLen);
  end;
end;

procedure TStringHelper.SetChar(ACharIdx: Integer; const AValue: RawByteString);
begin
  System.Insert(RawByteString(AValue), Self, CharBytePos(ACharIdx));
end;

function TStringHelper.GetCharLength: Integer;
begin
  Result := UTF8VisualLen(Self);
end;

function TStringHelper.GetSize: Integer;
begin
  Result := System.Length(Self);
end;

function TStringHelper.Copy(AFrom, ACount: Integer): string;
var ByteStart, ByteLen: Integer;
begin
  ByteStart := CharBytePos(AFrom);
  ByteLen   := CharByteSpan(ByteStart, ACount);
  Result    := System.Copy(Self, ByteStart, ByteLen);
end;

procedure TStringHelper.Delete(AFrom, ACount: Integer);
var ByteStart, ByteLen: Integer;
begin
  ByteStart := CharBytePos(AFrom);
  ByteLen   := CharByteSpan(ByteStart, ACount);
  System.Delete(Self, ByteStart, ByteLen);
end;

{ ─TRawByteStringHelper─  ── }

function TRawByteStringHelper.GetIndex(AIndex: Integer): Char;
begin
  Result := Self[AIndex + 1];
end;

procedure TRawByteStringHelper.SetIndex(AIndex: Integer; AValue: Char);
begin
  Self[AIndex + 1] := AValue;
end;

function TRawByteStringHelper.CharBytePos(ACharIdx: Integer): Integer;
var CharCount: Integer;
begin
  Result := 1;
  CharCount := 0;
  while (Result <= System.Length(Self)) and (CharCount < ACharIdx) do
  begin
    Inc(Result, UTF8SeqLen(Self, Result));
    Inc(CharCount);
  end;
end;

function TRawByteStringHelper.CharByteSpan(AByteStart, ACharCount: Integer): Integer;
var I, CharCount: Integer;
begin
  I := AByteStart;
  CharCount := 0;
  while (I <= System.Length(Self)) and (CharCount < ACharCount) do
  begin
    Inc(I, UTF8SeqLen(Self, I));
    Inc(CharCount);
  end;
  Result := I - AByteStart;
end;

function TRawByteStringHelper.GetChar(ACharIdx: Integer): RawByteString;
var BytePos, SeqLen: Integer;
begin
  BytePos := CharBytePos(ACharIdx);
  if BytePos > System.Length(Self) then
    Result := ''
  else
  begin
    SeqLen := UTF8SeqLen(Self, BytePos);
    Result := System.Copy(Self, BytePos, SeqLen);
  end;
end;

procedure TRawByteStringHelper.SetChar(ACharIdx: Integer; const AValue: RawByteString);
begin
  System.Insert(RawByteString(AValue), Self, CharBytePos(ACharIdx));
end;

function TRawByteStringHelper.GetCharLength: Integer;
begin
  Result := UTF8VisualLen(Self);
end;

function TRawByteStringHelper.GetSize: Integer;
begin
  Result := System.Length(Self);
end;

function TRawByteStringHelper.Copy(AFrom, ACount: Integer): string;
var ByteStart, ByteLen: Integer;
begin
  ByteStart := CharBytePos(AFrom);
  ByteLen   := CharByteSpan(ByteStart, ACount);
  Result    := System.Copy(Self, ByteStart, ByteLen);
end;

procedure TRawByteStringHelper.Delete(AFrom, ACount: Integer);
var ByteStart, ByteLen: Integer;
begin
  ByteStart := CharBytePos(AFrom);
  ByteLen   := CharByteSpan(ByteStart, ACount);
  System.Delete(Self, ByteStart, ByteLen);
end;


end.
