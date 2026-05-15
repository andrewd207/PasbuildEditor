{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Highlighter.XML;

{$mode objfpc}{$H+}

{ XML / HTML syntax highlighter for TTextEditor.

  Single-pass per-line tokenizer.  Handles multi-line comments and CDATA
  sections via a per-line state array computed in Prepare.

  Color scheme:
    Tag name / <  >  />  </    bright cyan
    Attribute name              yellow
    Attribute value  "..."      green
    Comment   <!-- ... -->      bright black (dim)
    CDATA     <![CDATA[ ... ]]> bright black
    PI        <?...?>           magenta
    Text content                default
}

interface

uses
  Classes, SysUtils, TermUI.Terminal, TermUI.Control.Editor, TermUI.StringUtils;

type
  TXMLHighlighter = class(TTextHighlighter)
  private
    type TLineState = (lsNormal, lsComment, lsCDATA);

  private
    FStates: array of TLineState;

    procedure AppendSpan(var ASpans: TTextSpanArray; var ACount: Integer;
      ACol, ALen: Integer; AFG: TColor);
    procedure TokenizeLine(const ALine: string; AStartState: TLineState;
      out ASpans: TTextSpanArray; out AEndState: TLineState);
  public
    procedure Prepare(ALines: TStrings); override;
    procedure GetSpans(ARow: Integer; const ALine: string;
      out ASpans: TTextSpanArray); override;
  end;

implementation

procedure TXMLHighlighter.AppendSpan(var ASpans: TTextSpanArray;
  var ACount: Integer; ACol, ALen: Integer; AFG: TColor);
begin
  if ALen <= 0 then Exit;
  if ACount >= Length(ASpans) then
    SetLength(ASpans, ACount + 16);
  ASpans[ACount].Col       := ACol;
  ASpans[ACount].Len       := ALen;
  ASpans[ACount].FG        := AFG;
  ASpans[ACount].BG        := clDefault;
  ASpans[ACount].Underline := False;
  Inc(ACount);
end;

procedure TXMLHighlighter.TokenizeLine(const ALine: string;
  AStartState: TLineState; out ASpans: TTextSpanArray; out AEndState: TLineState);
var
  Len, I, Start: Integer;
  State:         TLineState;
  Count:         Integer;
  Q:             Char;

  function Ahead(const S: string): Boolean;
  var J: Integer;
  begin
    if I + Length(S) - 1 > Len then Exit(False);
    for J := 1 to Length(S) do
      if ALine[I + J - 1] <> S[J] then Exit(False);
    Result := True;
  end;

begin
  SetLength(ASpans, 32);
  Count := 0;
  Len   := Length(ALine);
  State := AStartState;
  I     := 1;

  while I <= Len do
  begin
    case State of

      lsComment:
      begin
        Start := I;
        while I <= Len do
        begin
          if Ahead('-->') then
          begin
            Inc(I, 3);
            AppendSpan(ASpans, Count, Start - 1, I - Start, clBrightBlack);
            State := lsNormal;
            Break;
          end;
          Inc(I);
        end;
        if State = lsComment then
        begin
          AppendSpan(ASpans, Count, Start - 1, Len - Start + 1, clBrightBlack);
          I := Len + 1;
        end;
      end;

      lsCDATA:
      begin
        Start := I;
        while I <= Len do
        begin
          if Ahead(']]>') then
          begin
            Inc(I, 3);
            AppendSpan(ASpans, Count, Start - 1, I - Start, clBrightBlack);
            State := lsNormal;
            Break;
          end;
          Inc(I);
        end;
        if State = lsCDATA then
        begin
          AppendSpan(ASpans, Count, Start - 1, Len - Start + 1, clBrightBlack);
          I := Len + 1;
        end;
      end;

      lsNormal:
      begin
        if ALine[I] = '<' then
        begin
          if Ahead('<!--') then
          begin
            { Comment start }
            Start := I;
            Inc(I, 4);
            State := lsComment;
            while I <= Len do
            begin
              if Ahead('-->') then
              begin
                Inc(I, 3);
                AppendSpan(ASpans, Count, Start - 1, I - Start, clBrightBlack);
                State := lsNormal;
                Break;
              end;
              Inc(I);
            end;
            if State = lsComment then
            begin
              AppendSpan(ASpans, Count, Start - 1, Len - Start + 1, clBrightBlack);
              I := Len + 1;
            end;
          end
          else if Ahead('<![CDATA[') then
          begin
            Start := I;
            Inc(I, 9);
            State := lsCDATA;
            while I <= Len do
            begin
              if Ahead(']]>') then
              begin
                Inc(I, 3);
                AppendSpan(ASpans, Count, Start - 1, I - Start, clBrightBlack);
                State := lsNormal;
                Break;
              end;
              Inc(I);
            end;
            if State = lsCDATA then
            begin
              AppendSpan(ASpans, Count, Start - 1, Len - Start + 1, clBrightBlack);
              I := Len + 1;
            end;
          end
          else
          begin
            { Tag: < tagname attrs > — tokenize manually }
            Start := I; { '<' position (0-based = I-1) }
            Inc(I);     { skip '<' }
            { optional / for closing tag }
            if (I <= Len) and (ALine[I] = '/') then Inc(I);
            { optional ? for PI }
            if (I <= Len) and (ALine[I] = '?') then
            begin
              { Processing instruction — color whole PI magenta }
              AppendSpan(ASpans, Count, Start - 1, 2, clMagenta);
              Inc(I);
              { tag name }
              Start := I;
              while (I <= Len) and (ALine[I] > ' ') and
                    (ALine[I] <> '>') and (ALine[I] <> '?') do Inc(I);
              AppendSpan(ASpans, Count, Start - 1, I - Start, clMagenta);
              { rest until ?> }
              Start := I;
              while I <= Len do
              begin
                if Ahead('?>') then
                begin
                  AppendSpan(ASpans, Count, Start - 1, I - Start, clMagenta);
                  AppendSpan(ASpans, Count, I - 1, 2, clMagenta);
                  Inc(I, 2);
                  Break;
                end;
                Inc(I);
              end;
            end
            else
            begin
              { Normal tag }
              AppendSpan(ASpans, Count, Start - 1, I - Start, clBrightCyan);
              { tag name }
              Start := I;
              while (I <= Len) and (ALine[I] > ' ') and
                    (ALine[I] <> '>') and (ALine[I] <> '/') do Inc(I);
              AppendSpan(ASpans, Count, Start - 1, I - Start, clBrightCyan);
              { attributes until > or /> }
              while (I <= Len) and (ALine[I] <> '>') do
              begin
                if ALine[I] = '/' then
                begin
                  AppendSpan(ASpans, Count, I - 1, 1, clBrightCyan);
                  Inc(I);
                end
                else if ALine[I] = '>' then
                  Break
                else if ALine[I] <= ' ' then
                  Inc(I)   { skip whitespace }
                else
                begin
                  { attribute name }
                  Start := I;
                  while (I <= Len) and (ALine[I] > ' ') and
                        (ALine[I] <> '=') and (ALine[I] <> '>') do Inc(I);
                  AppendSpan(ASpans, Count, Start - 1, I - Start, clYellow);
                  { = }
                  if (I <= Len) and (ALine[I] = '=') then
                  begin
                    Inc(I);
                    { value: "..." or '...' }
                    if (I <= Len) and ((ALine[I] = '"') or (ALine[I] = '''')) then
                    begin
                      Q := ALine[I];
                      Start := I;
                      Inc(I);
                      while (I <= Len) and (ALine[I] <> Q) do Inc(I);
                      if I <= Len then Inc(I);
                      AppendSpan(ASpans, Count, Start - 1, I - Start, clGreen);
                    end;
                  end;
                end;
              end;
              { closing > }
              if (I <= Len) and (ALine[I] = '>') then
              begin
                AppendSpan(ASpans, Count, I - 1, 1, clBrightCyan);
                Inc(I);
              end;
            end;
          end;
        end
        else
          Inc(I);  { plain text character — no span = default color }
      end;

    end; { case }
  end;

  SetLength(ASpans, Count);
  AEndState := State;
end;

procedure TXMLHighlighter.Prepare(ALines: TStrings);
var
  I:        Integer;
  State:    TLineState;
  EndState: TLineState;
  Dummy:    TTextSpanArray;
begin
  SetLength(FStates, ALines.Count + 1);
  State := lsNormal;
  for I := 0 to ALines.Count - 1 do
  begin
    FStates[I] := State;
    TokenizeLine(ALines[I], State, Dummy, EndState);
    State := EndState;
  end;
  if ALines.Count <= Length(FStates) then
    FStates[ALines.Count] := State;
end;

procedure TXMLHighlighter.GetSpans(ARow: Integer; const ALine: string;
  out ASpans: TTextSpanArray);
var
  StartState, EndState: TLineState;
begin
  if (ARow >= 0) and (ARow < Length(FStates)) then
    StartState := FStates[ARow]
  else
    StartState := lsNormal;
  TokenizeLine(ALine, StartState, ASpans, EndState);
end;

initialization
  RegisterHighlighter(TXMLHighlighter, '.xml;.html;.htm;.xhtml;.svg;.xsl;.xslt;.rss;.atom;.plist');

end.
