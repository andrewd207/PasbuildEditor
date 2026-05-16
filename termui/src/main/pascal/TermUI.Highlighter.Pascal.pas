{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Highlighter.Pascal;

{$mode objfpc}{$H+}

{ Pascal / Object Pascal syntax highlighter for TTextEditor.

  Prepare does a single full-document pass to track multi-line comment state
  (brace comments and paren-star comments).  GetSpans then tokenises one line using the pre-computed
  start-of-line state.

  Color scheme:
    keywords             cyan
    comments (all kinds) bright black
    strings ''           yellow
    numbers              green
    compiler directives  bright yellow
    normal code          default
}

interface

uses
  Classes, SysUtils, Math,
  TermUI.Terminal, TermUI.Control.Editor;

type
  TPascalHighlighter = class(TTextHighlighter)
  private
    { Comment state at the START of each line:
      0 = normal  1 = inside brace comment  2 = inside paren-star comment }
    FLineState: array of Byte;
    procedure AppendSpan(var ASpans: TTextSpanArray; var ACount: Integer;
      ACol, ALen: Integer; AFG: TColor);
  public
    function  Name: string; override;
    procedure Prepare(ALines: TStrings); override;
    procedure GetSpans(ARow: Integer; const ALine: string;
      out ASpans: TTextSpanArray); override;
    { Highlight ALine given an explicit start-of-line comment state (0/1/2).
      Used by embedding highlighters (Markdown, AsciiDoc) so they can call
      Prepare once on the full document and reuse the per-line states. }
    procedure GetSpansWithState(const ALine: string; AState: Byte;
      out ASpans: TTextSpanArray);
    { Return the start-of-line comment state for the given row.
      Returns 0 if ARow is out of range (e.g. before Prepare is called). }
    function  LineState(ARow: Integer): Byte;
  end;

implementation

{ ── Keyword table (sorted, for binary search) ── }

const
  KW: array[0..92] of string = (
    'absolute',   'abstract',  'and',         'array',
    'as',         'asm',       'begin',        'break',
    'case',       'cdecl',     'class',        'const',
    'constructor','continue',  'default',      'destructor',
    'dispose',    'div',       'do',           'downto',
    'else',       'end',       'except',       'exit',
    'exports',    'external',  'false',        'far',
    'file',       'finalization','finally',    'for',
    'forward',    'function',  'goto',         'if',
    'implementation','in',     'inherited',    'initialization',
    'inline',     'interface', 'is',           'label',
    'library',    'message',   'mod',          'near',
    'new',        'nil',       'not',          'object',
    'of',         'on',        'operator',     'or',
    'out',        'overload',  'override',     'packed',
    'pascal',     'private',   'procedure',    'program',
    'property',   'protected', 'public',       'published',
    'raise',      'record',    'register',     'repeat',
    'result',     'self',      'set',          'shl',
    'shr',        'specialize','stdcall',      'string',
    'then',       'to',        'true',         'try',
    'type',       'unit',      'until',        'uses',
    'var',        'virtual',   'while',        'with',
    'xor'
  );

  { Keywords that are only valid as property specifiers }
  PropKW: array[0..2] of string = ('index', 'read', 'write');

function IsPropKeyword(const S: string): Boolean;
var
  L: string;
  I: Integer;
begin
  L := LowerCase(S);
  for I := 0 to High(PropKW) do
    if PropKW[I] = L then Exit(True);
  Result := False;
end;

function IsKeyword(const S: string): Boolean;
var
  Lo, Hi, Mid: Integer;
  L: string;
begin
  L  := LowerCase(S);
  Lo := 0;
  Hi := High(KW);
  while Lo <= Hi do
  begin
    Mid := (Lo + Hi) shr 1;
    if KW[Mid] = L then Exit(True)
    else if KW[Mid] < L then Lo := Mid + 1
    else Hi := Mid - 1;
  end;
  Result := False;
end;

{ ── TPascalHighlighter ── }

procedure TPascalHighlighter.AppendSpan(var ASpans: TTextSpanArray;
  var ACount: Integer; ACol, ALen: Integer; AFG: TColor);
begin
  if ALen <= 0 then Exit;
  if ACount >= Length(ASpans) then
    SetLength(ASpans, Max(8, Length(ASpans) * 2));
  ASpans[ACount].Col       := ACol;
  ASpans[ACount].Len       := ALen;
  ASpans[ACount].FG        := AFG;
  ASpans[ACount].BG        := clDefault;
  ASpans[ACount].Underline := False;
  Inc(ACount);
end;

function TPascalHighlighter.Name: string;
begin
  Result := 'Pascal';
end;

function TPascalHighlighter.LineState(ARow: Integer): Byte;
begin
  if (ARow >= 0) and (ARow < Length(FLineState)) then
    Result := FLineState[ARow]
  else
    Result := 0;
end;

procedure TPascalHighlighter.Prepare(ALines: TStrings);
var
  I, J, Len: Integer;
  S:     string;
  State: Byte;
begin
  SetLength(FLineState, ALines.Count + 1);
  State := 0;
  for I := 0 to ALines.Count - 1 do
  begin
    FLineState[I] := State;
    S   := ALines[I];
    Len := Length(S);
    J   := 1;
    while J <= Len do
    begin
      case State of
        1: (* inside { } *)
          begin
            if S[J] = '}' then State := 0;
            Inc(J);
          end;
        2: (* inside (* *) *)
          begin
            if (S[J] = '*') and (J < Len) and (S[J + 1] = ')') then
            begin
              State := 0;
              Inc(J, 2);
            end
            else
              Inc(J);
          end;
        else { normal }
          begin
            case S[J] of
              '''':
                begin
                  Inc(J);
                  while J <= Len do
                  begin
                    if S[J] = '''' then
                    begin
                      Inc(J);
                      if (J <= Len) and (S[J] = '''') then
                        Inc(J)
                      else
                        Break;
                    end
                    else
                      Inc(J);
                  end;
                end;
              '/':
                if (J < Len) and (S[J + 1] = '/') then
                  Break  { rest of line is a comment — state unchanged }
                else
                  Inc(J);
              '{':
                if (J < Len) and (S[J + 1] = '$') then
                begin
                  (* compiler directive — scan to closing brace *)
                  Inc(J, 2);
                  while (J <= Len) and (S[J] <> '}') do Inc(J);
                  if J <= Len then Inc(J);
                end
                else
                begin
                  State := 1;
                  Inc(J);
                end;
              '(':
                if (J < Len) and (S[J + 1] = '*') then
                begin
                  State := 2;
                  Inc(J, 2);
                end
                else
                  Inc(J);
              else
                Inc(J);
            end; { case S[J] }
          end;
      end; { case State }
    end; { while J }
  end;
  if ALines.Count > 0 then
    FLineState[ALines.Count] := State;
end;

procedure TPascalHighlighter.GetSpansWithState(const ALine: string;
  AState: Byte; out ASpans: TTextSpanArray);
var
  Len, J, K, WStart, Count: Integer;
  State: Byte;
  C:     Char;
  W:     string;
  Colors: array of TColor;
  RunColor: TColor;
  InProperty: Boolean;
begin
  ASpans := nil;
  Len    := Length(ALine);
  if Len = 0 then Exit;

  SetLength(Colors, Len);
  for K := 0 to Len - 1 do Colors[K] := clDefault;

  State      := AState;
  InProperty := False;
  J          := 1;
  while J <= Len do
  begin
    C := ALine[J];
    case State of
      1: (* inside { } *)
        begin
          Colors[J - 1] := clBrightBlack;
          if C = '}' then State := 0;
          Inc(J);
        end;
      2: (* inside (* *) *)
        begin
          Colors[J - 1] := clBrightBlack;
          if (C = '*') and (J < Len) and (ALine[J + 1] = ')') then
          begin
            Colors[J] := clBrightBlack;  { the closing paren }
            Inc(J, 2);
            State := 0;
          end
          else
            Inc(J);
        end;
      else { normal }
        begin
          case C of
            '/':
              if (J < Len) and (ALine[J + 1] = '/') then
              begin
                for K := J - 1 to Len - 1 do Colors[K] := clBrightBlack;
                Break;
              end
              else
                Inc(J);
            '{':
              if (J < Len) and (ALine[J + 1] = '$') then
              begin
                { compiler directive }
                K := J - 1;
                while (J <= Len) and (ALine[J] <> '}') do
                begin
                  Colors[J - 1] := clBrightYellow;
                  Inc(J);
                end;
                if J <= Len then
                begin
                  Colors[J - 1] := clBrightYellow;
                  Inc(J);
                end;
              end
              else
              begin
                Colors[J - 1] := clBrightBlack;
                State := 1;
                Inc(J);
              end;
            '(':
              if (J < Len) and (ALine[J + 1] = '*') then
              begin
                Colors[J - 1] := clBrightBlack;
                Colors[J]     := clBrightBlack;
                State := 2;
                Inc(J, 2);
              end
              else
                Inc(J);
            '''':
              begin
                Colors[J - 1] := clYellow;
                Inc(J);
                while J <= Len do
                begin
                  Colors[J - 1] := clYellow;
                  if ALine[J] = '''' then
                  begin
                    Inc(J);
                    if (J <= Len) and (ALine[J] = '''') then
                    begin
                      Colors[J - 1] := clYellow;
                      Inc(J);
                    end
                    else
                      Break;
                  end
                  else
                    Inc(J);
                end;
              end;
            '#':
              begin
                Colors[J - 1] := clYellow;
                Inc(J);
                if (J <= Len) and (ALine[J] = '$') then
                begin
                  Colors[J - 1] := clYellow;
                  Inc(J);
                  while (J <= Len) and
                        (ALine[J] in ['0'..'9', 'A'..'F', 'a'..'f']) do
                  begin
                    Colors[J - 1] := clYellow;
                    Inc(J);
                  end;
                end
                else
                begin
                  while (J <= Len) and (ALine[J] in ['0'..'9']) do
                  begin
                    Colors[J - 1] := clYellow;
                    Inc(J);
                  end;
                end;
              end;
            '$':
              begin
                Colors[J - 1] := clGreen;
                Inc(J);
                while (J <= Len) and
                      (ALine[J] in ['0'..'9', 'A'..'F', 'a'..'f', '_']) do
                begin
                  Colors[J - 1] := clGreen;
                  Inc(J);
                end;
              end;
            '%':
              begin
                Colors[J - 1] := clGreen;
                Inc(J);
                while (J <= Len) and (ALine[J] in ['0', '1', '_']) do
                begin
                  Colors[J - 1] := clGreen;
                  Inc(J);
                end;
              end;
            '0'..'9':
              begin
                Colors[J - 1] := clGreen;
                Inc(J);
                while (J <= Len) and
                      (ALine[J] in ['0'..'9', '.', '_', 'e', 'E', '+', '-']) do
                begin
                  Colors[J - 1] := clGreen;
                  Inc(J);
                end;
              end;
            'A'..'Z', 'a'..'z', '_':
              begin
                WStart := J;
                W      := C;
                Inc(J);
                while (J <= Len) and
                      (ALine[J] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
                begin
                  W := W + ALine[J];
                  Inc(J);
                end;
                if IsKeyword(W) then
                begin
                  for K := WStart - 1 to J - 2 do
                    Colors[K] := clCyan;
                  if LowerCase(W) = 'property' then
                    InProperty := True;
                end
                else if InProperty and IsPropKeyword(W) then
                  for K := WStart - 1 to J - 2 do
                    Colors[K] := clCyan;
              end;
            else
              Inc(J);
          end; { case C }
        end;
    end; { case State }
  end; { while J }

  { Convert per-character Colors to run-length-encoded spans }
  SetLength(ASpans, 8);
  Count := 0;
  J     := 0;
  while J < Len do
  begin
    if Colors[J] <> clDefault then
    begin
      RunColor := Colors[J];
      K := J + 1;
      while (K < Len) and (Colors[K] = RunColor) do Inc(K);
      AppendSpan(ASpans, Count, J, K - J, RunColor);
      J := K;
    end
    else
      Inc(J);
  end;
  SetLength(ASpans, Count);
end;

procedure TPascalHighlighter.GetSpans(ARow: Integer; const ALine: string;
  out ASpans: TTextSpanArray);
begin
  GetSpansWithState(ALine, LineState(ARow), ASpans);
end;

initialization
  RegisterHighlighter(TPascalHighlighter, '.pas;.pp;.inc');

end.
