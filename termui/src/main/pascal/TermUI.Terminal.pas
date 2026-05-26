{
  This file is part of the PasbuildEditor project.
  Copyright (c) 2026 Andrew Haines <andrewd207 @github>

  SPDX-License-Identifier: BSD-3-Clause

  Licensed under the BSD-3-Clause License. See LICENSE file for details.
}

unit TermUI.Terminal;

{$mode objfpc}{$H+}

interface

uses
  TermUI.StringUtils;

type
  TKeyCode = (
    kcNone,
    { Plain arrows }
    kcUp, kcDown, kcLeft, kcRight,
    { Shift+arrows }
    kcShiftUp, kcShiftDown, kcShiftLeft, kcShiftRight,
    { Shift+navigation }
    kcShiftHome, kcShiftEnd, kcShiftPageUp, kcShiftPageDown,
    { Ctrl+Shift combinations }
    kcShiftCtrlHome, kcShiftCtrlEnd,
    kcShiftCtrlLeft, kcShiftCtrlRight,
    { Alt+arrows }
    kcAltUp, kcAltDown, kcAltLeft, kcAltRight,
    { Ctrl+arrows }
    kcCtrlUp, kcCtrlDown, kcCtrlLeft, kcCtrlRight,
    { Navigation cluster }
    kcHome, kcEnd, kcPageUp, kcPageDown, kcInsert,
    kcCtrlHome, kcCtrlEnd,
    { Editing }
    kcEnter, kcEscape, kcBackspace, kcDelete,
    { Tab }
    kcTab, kcShiftTab, kcCtrlTab,
    { Printable character — Key.Ch holds the char }
    kcChar,
    { Ctrl+letter.  Ctrl+H/I/J/M/[ are already kcBackspace/kcTab/kcEnter/kcEscape. }
    kcCtrlA, kcCtrlB, kcCtrlC, kcCtrlD, kcCtrlE, kcCtrlF, kcCtrlG,
    kcCtrlK, kcCtrlL,
    kcCtrlN, kcCtrlO, kcCtrlP, kcCtrlQ, kcCtrlR,
    kcCtrlS, kcCtrlT, kcCtrlU, kcCtrlV, kcCtrlW,
    kcCtrlX, kcCtrlY, kcCtrlZ,
    kcCtrlSpace,
    { Function keys F1–F14 }
    kcF1, kcF2, kcF3, kcF4, kcF5, kcF6, kcF7,
    kcF8, kcF9, kcF10, kcF11, kcF12, kcF13, kcF14,
    { Alt + printable character — Key.Ch holds the character.
      On Unix: decoded from ESC + printable byte (xterm Alt encoding).
      On Windows: decoded from VK with LEFT_ALT_PRESSED / RIGHT_ALT_PRESSED. }
    kcAltChar,
    { Alt+F1 }
    kcAltF1,
    { Bracketed paste — Key.PasteText holds the pasted string.
      Fired when the terminal wraps a user paste in ESC[200~...ESC[201~. }
    kcBracketedPaste
  );

  TKeyEvent = record
    Code:      TKeyCode;
    Ch:        TUTF8Char;
    { Filled only when Code = kcBracketedPaste. }
    PasteText: string;
  end;

  T8BitColor = (
    p8Default, p8Black, p8Red, p8Green, p8Yellow, p8Blue, p8Magenta, p8Cyan,
    p8White, p8BrightBlack, p8BrightRed, p8BrightGreen, p8BrightYellow, p8BrightBlue, p8BrightMagenta, p8BrightCyan,
    p8BrightWhite, p8Background, p8Xterm16, p8Xterm17, p8Navy, p8Xterm19, p8Xterm20, p8Xterm21,
    p8DarkGreen, p8Xterm23, p8TealBlue, p8Xterm25, p8Xterm26, p8Xterm27, p8Green4, p8Xterm29,
    p8Teal, p8Xterm31, p8Xterm32, p8Xterm33, p8MidGreen, p8Xterm35, p8TealGreen, p8Xterm37,
    p8Xterm38, p8Xterm39, p8Green2, p8Xterm41, p8Xterm42, p8Xterm43, p8Xterm44, p8Xterm45,
    p8Lime, p8Xterm47, p8Xterm48, p8Xterm49, p8Xterm50, p8Aqua, p8DarkRed, p8Xterm53,
    p8Xterm54, p8Xterm55, p8Xterm56, p8Xterm57, p8Xterm58, p8Xterm59, p8Xterm60, p8Xterm61,
    p8Xterm62, p8Xterm63, p8Xterm64, p8Xterm65, p8Xterm66, p8Xterm67, p8Xterm68, p8Xterm69,
    p8Xterm70, p8Xterm71, p8Xterm72, p8Xterm73, p8Xterm74, p8Xterm75, p8Xterm76, p8Xterm77,
    p8Xterm78, p8Xterm79, p8Xterm80, p8Xterm81, p8Xterm82, p8Xterm83, p8Xterm84, p8Xterm85,
    p8Xterm86, p8Xterm87, p8Maroon, p8Xterm89, p8Purple, p8Xterm91, p8Xterm92, p8Xterm93,
    p8Brown, p8Xterm95, p8Xterm96, p8Xterm97, p8Xterm98, p8Xterm99, p8Olive, p8Xterm101,
    p8Xterm102, p8Xterm103, p8Xterm104, p8Xterm105, p8Xterm106, p8Xterm107, p8Xterm108, p8Xterm109,
    p8Xterm110, p8Xterm111, p8Xterm112, p8Xterm113, p8Xterm114, p8Xterm115, p8Xterm116, p8Xterm117,
    p8Xterm118, p8Xterm119, p8Xterm120, p8Xterm121, p8Xterm122, p8Xterm123, p8Xterm124, p8Xterm125,
    p8Xterm126, p8Xterm127, p8Xterm128, p8Xterm129, p8Xterm130, p8Xterm131, p8Xterm132, p8Xterm133,
    p8Xterm134, p8Xterm135, p8Xterm136, p8Xterm137, p8Xterm138, p8Xterm139, p8Xterm140, p8Xterm141,
    p8Xterm142, p8Xterm143, p8Xterm144, p8Xterm145, p8Xterm146, p8Xterm147, p8Xterm148, p8Xterm149,
    p8Xterm150, p8Xterm151, p8Xterm152, p8Xterm153, p8Xterm154, p8Xterm155, p8Xterm156, p8Xterm157,
    p8Xterm158, p8Xterm159, p8Xterm160, p8Xterm161, p8Xterm162, p8Xterm163, p8Xterm164, p8Xterm165,
    p8Xterm166, p8Xterm167, p8Xterm168, p8Xterm169, p8Xterm170, p8Xterm171, p8Xterm172, p8Xterm173,
    p8Xterm174, p8Xterm175, p8Xterm176, p8Xterm177, p8Xterm178, p8Xterm179, p8Xterm180, p8Xterm181,
    p8Xterm182, p8Xterm183, p8Xterm184, p8Xterm185, p8Xterm186, p8Xterm187, p8Xterm188, p8Xterm189,
    p8Xterm190, p8Xterm191, p8Xterm192, p8Xterm193, p8Xterm194, p8Xterm195, p8Xterm196, p8Xterm197,
    p8HotPink, p8Xterm199, p8Xterm200, p8Xterm201, p8Xterm202, p8Xterm203, p8Xterm204, p8Xterm205,
    p8Xterm206, p8Xterm207, p8DarkOrange, p8Xterm209, p8Xterm210, p8Xterm211, p8Xterm212, p8Xterm213,
    p8Orange, p8Xterm215, p8Xterm216, p8Xterm217, p8Pink, p8Xterm219, p8Gold, p8Xterm221,
    p8Xterm222, p8Xterm223, p8Xterm224, p8Xterm225, p8Xterm226, p8Xterm227, p8Xterm228, p8Xterm229,
    p8Xterm230, p8Xterm231, p8Xterm232, p8Xterm233, p8Xterm234, p8Xterm235, p8Xterm236, p8Xterm237,
    p8Xterm238, p8Xterm239, p8Xterm240, p8Xterm241, p8Xterm242, p8Xterm243, p8Grey, p8Xterm245,
    p8Xterm246, p8Xterm247, p8Xterm248, p8Xterm249, p8Silver, p8Xterm251, p8Xterm252, p8Xterm253,
    p8Xterm254, p8Xterm255
  );

  { Unified color: either an 8-bit palette reference or a 24-bit RGB triple.
    Encoding (LongInt, 32 bits):
      bits 24..31  tag byte: 0 = palette, 1 = RGB
      bits  0..15  palette: Ord(T8BitColor)
      bits  0..23  RGB:     (R shl 16) or (G shl 8) or B
    Build truecolor values with RGB(r,g,b).  When the terminal cannot do
    truecolor (Term.SupportsTrueColor = False), RGB values are converted at
    flush time to their nearest T8BitColor (6x6x6 cube + greyscale ramp). }
  TColor = type LongInt;

const
  clDefault            : TColor = 0;
  clBlack              : TColor = 1;
  clRed                : TColor = 2;
  clGreen              : TColor = 3;
  clYellow             : TColor = 4;
  clBlue               : TColor = 5;
  clMagenta            : TColor = 6;
  clCyan               : TColor = 7;
  clWhite              : TColor = 8;
  clBrightBlack        : TColor = 9;
  clBrightRed          : TColor = 10;
  clBrightGreen        : TColor = 11;
  clBrightYellow       : TColor = 12;
  clBrightBlue         : TColor = 13;
  clBrightMagenta      : TColor = 14;
  clBrightCyan         : TColor = 15;
  clBrightWhite        : TColor = 16;
  clBackground         : TColor = 17;
  clXterm16            : TColor = 18;
  clXterm17            : TColor = 19;
  clNavy               : TColor = 20;
  clXterm19            : TColor = 21;
  clXterm20            : TColor = 22;
  clXterm21            : TColor = 23;
  clDarkGreen          : TColor = 24;
  clXterm23            : TColor = 25;
  clTealBlue           : TColor = 26;
  clXterm25            : TColor = 27;
  clXterm26            : TColor = 28;
  clXterm27            : TColor = 29;
  clGreen4             : TColor = 30;
  clXterm29            : TColor = 31;
  clTeal               : TColor = 32;
  clXterm31            : TColor = 33;
  clXterm32            : TColor = 34;
  clXterm33            : TColor = 35;
  clMidGreen           : TColor = 36;
  clXterm35            : TColor = 37;
  clTealGreen          : TColor = 38;
  clXterm37            : TColor = 39;
  clXterm38            : TColor = 40;
  clXterm39            : TColor = 41;
  clGreen2             : TColor = 42;
  clXterm41            : TColor = 43;
  clXterm42            : TColor = 44;
  clXterm43            : TColor = 45;
  clXterm44            : TColor = 46;
  clXterm45            : TColor = 47;
  clLime               : TColor = 48;
  clXterm47            : TColor = 49;
  clXterm48            : TColor = 50;
  clXterm49            : TColor = 51;
  clXterm50            : TColor = 52;
  clAqua               : TColor = 53;
  clDarkRed            : TColor = 54;
  clXterm53            : TColor = 55;
  clXterm54            : TColor = 56;
  clXterm55            : TColor = 57;
  clXterm56            : TColor = 58;
  clXterm57            : TColor = 59;
  clXterm58            : TColor = 60;
  clXterm59            : TColor = 61;
  clXterm60            : TColor = 62;
  clXterm61            : TColor = 63;
  clXterm62            : TColor = 64;
  clXterm63            : TColor = 65;
  clXterm64            : TColor = 66;
  clXterm65            : TColor = 67;
  clXterm66            : TColor = 68;
  clXterm67            : TColor = 69;
  clXterm68            : TColor = 70;
  clXterm69            : TColor = 71;
  clXterm70            : TColor = 72;
  clXterm71            : TColor = 73;
  clXterm72            : TColor = 74;
  clXterm73            : TColor = 75;
  clXterm74            : TColor = 76;
  clXterm75            : TColor = 77;
  clXterm76            : TColor = 78;
  clXterm77            : TColor = 79;
  clXterm78            : TColor = 80;
  clXterm79            : TColor = 81;
  clXterm80            : TColor = 82;
  clXterm81            : TColor = 83;
  clXterm82            : TColor = 84;
  clXterm83            : TColor = 85;
  clXterm84            : TColor = 86;
  clXterm85            : TColor = 87;
  clXterm86            : TColor = 88;
  clXterm87            : TColor = 89;
  clMaroon             : TColor = 90;
  clXterm89            : TColor = 91;
  clPurple             : TColor = 92;
  clXterm91            : TColor = 93;
  clXterm92            : TColor = 94;
  clXterm93            : TColor = 95;
  clBrown              : TColor = 96;
  clXterm95            : TColor = 97;
  clXterm96            : TColor = 98;
  clXterm97            : TColor = 99;
  clXterm98            : TColor = 100;
  clXterm99            : TColor = 101;
  clOlive              : TColor = 102;
  clXterm101           : TColor = 103;
  clXterm102           : TColor = 104;
  clXterm103           : TColor = 105;
  clXterm104           : TColor = 106;
  clXterm105           : TColor = 107;
  clXterm106           : TColor = 108;
  clXterm107           : TColor = 109;
  clXterm108           : TColor = 110;
  clXterm109           : TColor = 111;
  clXterm110           : TColor = 112;
  clXterm111           : TColor = 113;
  clXterm112           : TColor = 114;
  clXterm113           : TColor = 115;
  clXterm114           : TColor = 116;
  clXterm115           : TColor = 117;
  clXterm116           : TColor = 118;
  clXterm117           : TColor = 119;
  clXterm118           : TColor = 120;
  clXterm119           : TColor = 121;
  clXterm120           : TColor = 122;
  clXterm121           : TColor = 123;
  clXterm122           : TColor = 124;
  clXterm123           : TColor = 125;
  clXterm124           : TColor = 126;
  clXterm125           : TColor = 127;
  clXterm126           : TColor = 128;
  clXterm127           : TColor = 129;
  clXterm128           : TColor = 130;
  clXterm129           : TColor = 131;
  clXterm130           : TColor = 132;
  clXterm131           : TColor = 133;
  clXterm132           : TColor = 134;
  clXterm133           : TColor = 135;
  clXterm134           : TColor = 136;
  clXterm135           : TColor = 137;
  clXterm136           : TColor = 138;
  clXterm137           : TColor = 139;
  clXterm138           : TColor = 140;
  clXterm139           : TColor = 141;
  clXterm140           : TColor = 142;
  clXterm141           : TColor = 143;
  clXterm142           : TColor = 144;
  clXterm143           : TColor = 145;
  clXterm144           : TColor = 146;
  clXterm145           : TColor = 147;
  clXterm146           : TColor = 148;
  clXterm147           : TColor = 149;
  clXterm148           : TColor = 150;
  clXterm149           : TColor = 151;
  clXterm150           : TColor = 152;
  clXterm151           : TColor = 153;
  clXterm152           : TColor = 154;
  clXterm153           : TColor = 155;
  clXterm154           : TColor = 156;
  clXterm155           : TColor = 157;
  clXterm156           : TColor = 158;
  clXterm157           : TColor = 159;
  clXterm158           : TColor = 160;
  clXterm159           : TColor = 161;
  clXterm160           : TColor = 162;
  clXterm161           : TColor = 163;
  clXterm162           : TColor = 164;
  clXterm163           : TColor = 165;
  clXterm164           : TColor = 166;
  clXterm165           : TColor = 167;
  clXterm166           : TColor = 168;
  clXterm167           : TColor = 169;
  clXterm168           : TColor = 170;
  clXterm169           : TColor = 171;
  clXterm170           : TColor = 172;
  clXterm171           : TColor = 173;
  clXterm172           : TColor = 174;
  clXterm173           : TColor = 175;
  clXterm174           : TColor = 176;
  clXterm175           : TColor = 177;
  clXterm176           : TColor = 178;
  clXterm177           : TColor = 179;
  clXterm178           : TColor = 180;
  clXterm179           : TColor = 181;
  clXterm180           : TColor = 182;
  clXterm181           : TColor = 183;
  clXterm182           : TColor = 184;
  clXterm183           : TColor = 185;
  clXterm184           : TColor = 186;
  clXterm185           : TColor = 187;
  clXterm186           : TColor = 188;
  clXterm187           : TColor = 189;
  clXterm188           : TColor = 190;
  clXterm189           : TColor = 191;
  clXterm190           : TColor = 192;
  clXterm191           : TColor = 193;
  clXterm192           : TColor = 194;
  clXterm193           : TColor = 195;
  clXterm194           : TColor = 196;
  clXterm195           : TColor = 197;
  clXterm196           : TColor = 198;
  clXterm197           : TColor = 199;
  clHotPink            : TColor = 200;
  clXterm199           : TColor = 201;
  clXterm200           : TColor = 202;
  clXterm201           : TColor = 203;
  clXterm202           : TColor = 204;
  clXterm203           : TColor = 205;
  clXterm204           : TColor = 206;
  clXterm205           : TColor = 207;
  clXterm206           : TColor = 208;
  clXterm207           : TColor = 209;
  clDarkOrange         : TColor = 210;
  clXterm209           : TColor = 211;
  clXterm210           : TColor = 212;
  clXterm211           : TColor = 213;
  clXterm212           : TColor = 214;
  clXterm213           : TColor = 215;
  clOrange             : TColor = 216;
  clXterm215           : TColor = 217;
  clXterm216           : TColor = 218;
  clXterm217           : TColor = 219;
  clPink               : TColor = 220;
  clXterm219           : TColor = 221;
  clGold               : TColor = 222;
  clXterm221           : TColor = 223;
  clXterm222           : TColor = 224;
  clXterm223           : TColor = 225;
  clXterm224           : TColor = 226;
  clXterm225           : TColor = 227;
  clXterm226           : TColor = 228;
  clXterm227           : TColor = 229;
  clXterm228           : TColor = 230;
  clXterm229           : TColor = 231;
  clXterm230           : TColor = 232;
  clXterm231           : TColor = 233;
  clXterm232           : TColor = 234;
  clXterm233           : TColor = 235;
  clXterm234           : TColor = 236;
  clXterm235           : TColor = 237;
  clXterm236           : TColor = 238;
  clXterm237           : TColor = 239;
  clXterm238           : TColor = 240;
  clXterm239           : TColor = 241;
  clXterm240           : TColor = 242;
  clXterm241           : TColor = 243;
  clXterm242           : TColor = 244;
  clXterm243           : TColor = 245;
  clGrey               : TColor = 246;
  clXterm245           : TColor = 247;
  clXterm246           : TColor = 248;
  clXterm247           : TColor = 249;
  clXterm248           : TColor = 250;
  clXterm249           : TColor = 251;
  clSilver             : TColor = 252;
  clXterm251           : TColor = 253;
  clXterm252           : TColor = 254;
  clXterm253           : TColor = 255;
  clXterm254           : TColor = 256;
  clXterm255           : TColor = 257;

  { Truecolor named colors — encoded as RGB (tag byte $01).  These reach
    24-bit values that the 256-palette can't represent.  On terminals without
    truecolor support, ToPalette() will pick the nearest 8-bit fallback. }
  clForestGreen        : TColor = $01022800;   { #022800 — very dark green }
  clBrick              : TColor = $013D0100;   { #3D0100 — very dark red   }

type

  { Named drawing characters used by controls and borders.
    TApplication.DrawChar / .DrawingChar[] provide the actual glyph based on
    the UseUnicodeBorders setting and any per-char override. }
  TDrawingChar = (
    { Box corners }
    dcTopLeft,      { + / ┌ }  dcTopRight,     { + / ┐ }
    dcBottomLeft,   { + / └ }  dcBottomRight,  { + / ┘ }
    { Lines }
    dcHoriz,        { - / ─ }  dcVert,         { | / │ }
    { T-junctions }
    dcTeeLeft,      { + / ├ }  dcTeeRight,     { + / ┤ }
    dcTeeTop,       { + / ┬ }  dcTeeBottom,    { + / ┴ }
    dcCross,        { + / ┼ }
    { Scrollbar track elements }
    dcScrollUp,     { ^ / ▲ }  dcScrollDown,   { v / ▼ }
    dcScrollThumb,  { # / █ }  dcScrollTrack,  { | / │ }
    { Combo box }
    dcComboLeft,    { [ / [ }  dcComboRight,   { ] / ] }
    dcComboArrow,   { v / ▼ }
    { File/directory indicators }
    dcDirIndicator,  { > / ▶ }
    { Parent-directory / go-up entry.  Alternatives: ⬆ (U+2B06, bolder),
      ↩ (U+21A9, back-hook), ⇡ (U+21E1, dashed).  ASCII fallback: ^ }
    dcDirParent,     { ^ / ↑ }
    { Navigation arrows (breadcrumbs, pagination — distinct from scrollbar arrows) }
    dcArrowLeft,     { < / ← }  dcArrowRight,    { > / → }
    dcArrowUp,       { ^ / ↑ }  dcArrowDown,     { v / ↓ }
    { Tree / hierarchy view }
    dcTreeCollapsed, { + / ▶ }  dcTreeExpanded,  { - / ▼ }
    dcTreeLeaf,      {   /   }
    dcTreeVert,      { | / │ }  dcTreeBranch,    { + / ├ }  dcTreeLast, { \ / └ }
    { List / selection markers }
    dcBullet,        { * / • }
    dcSelectedMark,  { > / ► }
    dcCheckOff,      { - / ☐ }  dcCheckOn,       { x / ☑ }
    dcRadioOff,      { ( ) / ○ }  dcRadioOn,     { (*) / ● }
    { Text overflow }
    dcEllipsis,      { ~ / … }
    { Progress bar }
    dcProgressFull,  { # / █ }  dcProgressEmpty, { . / ░ }
    { Misc UI chrome }
    dcClose,         { x / × }
    dcMenuIcon,      { = / ☰ }
    dcSeparator      { | / │ }
  );

  { Each buffer cell holds one Unicode codepoint as a UTF-8 sequence (1-4 bytes). }
  TScreenCell = record
    Ch:        TUtf8Char;
    FG, BG:    TColor;
    Underline: Boolean;
  end;

  TScreenBuffer = array of TScreenCell;

  TTerminal = class
  private
    FUseColor: Boolean;
    FTrueColor: Boolean;

    { Double buffer — back is what we're drawing into, front is what the
      terminal currently shows.  Flushed by FlushOutput. }
    FBack:     TScreenBuffer;
    FFront:    TScreenBuffer;
    FBufW:     Integer;
    FBufH:     Integer;

    { Current drawing state (pen) for back-buffer writes }
    FCurX:       Integer;   // 1-based column
    FCurY:       Integer;   // 1-based row
    FCurFG:      TColor;
    FCurBG:      TColor;
    FCurUL:      Boolean;
    FCursorWant:    Boolean;   // desired visibility; emitted once by FlushOutput
    FCursorX:       Integer;   // desired cursor display position (set by PlaceCursor)
    FCursorY:       Integer;
    FDirtyRows: array of Boolean;  // 0-based; FDirtyRows[Y-1] = True → row Y needs FlushRow

    procedure AllocBuffers(W, H: Integer);
    procedure BlankBuffer(var Buf: TScreenBuffer);
    function  CellIndex(X, Y: Integer): Integer; inline;

  protected
    procedure InitColor;
    { Subclasses call this to emit bytes directly to stdout (bypasses buffer). }
    procedure RawWrite(const S: RawByteString);

  public
    function Width: Integer; virtual; abstract;
    function Height: Integer; virtual; abstract;
    function IsTTY: Boolean; virtual;
    function UseColor: Boolean;
    { Whether the terminal can render 24-bit RGB SGR escapes (ESC[38;2;R;G;B m).
      Detected from $COLORTERM and $TERM at construction.  When False, every
      RGB TColor is converted to the nearest T8BitColor at flush time. }
    function SupportsTrueColor: Boolean;

    procedure EnableRawMode; virtual; abstract;
    procedure DisableRawMode; virtual; abstract;

    function HasResized: Boolean; virtual;

    function ReadKey: TKeyEvent; virtual; abstract;
    { Non-blocking variant: returns False on timeout, True + filled AKey on keypress. }
    function ReadKeyTimeout(out AKey: TKeyEvent; TimeoutMs: Integer): Boolean; virtual; abstract;
    { Discard all keypresses currently buffered in the terminal input queue.
      Use after a blocking operation (e.g. subprocess) to prevent stale input
      from being consumed by the next interactive control. }
    procedure DiscardPendingInput;

    { Buffer-aware drawing — these write into the back buffer. }
    procedure WriteStr(const S: string); virtual;
    procedure GotoXY(X, Y: Integer); virtual;
    procedure ClearScreen; virtual;
    procedure ClearToEOL; virtual;
    procedure SetFG(C: TColor); virtual;
    procedure SetBG(C: TColor); virtual;
    procedure ResetColors; virtual;
    procedure SetUnderline(AOn: Boolean); virtual;

    { Diff back vs front and emit only changed cells, then swap. }
    procedure FlushOutput; virtual;

    { Diff only one screen row (1-based) and emit changes for that row only.
      Does not require InvalidateFront — FFront is trusted for all other rows. }
    procedure FlushRow(Y: Integer);

    { Mark the entire front buffer as dirty so the next FlushOutput redraws
      every cell. Call this before overlaying ephemeral messages on top of a
      screen that was partially updated by an inline editor. }
    procedure InvalidateFront;

    { Mark a single screen row (1-based) as needing a FlushRow this frame.
      Calls outside 1..Height are silently ignored. }
    procedure HintDirtyRow(ARow: Integer);
    { True if any rows were marked dirty via HintDirtyRow. }
    function  HasDirtyRowHints: Boolean;
    { Flush each dirty row and clear its flag.  Call after painting. }
    procedure FlushDirtyRows;

    { Set where the visible terminal cursor should appear after FlushOutput.
      Separate from GotoXY (the drawing pen) so that subsequent paint calls
      do not silently move the cursor away from the edit point. }
    procedure PlaceCursor(X, Y: Integer); virtual;

    { Cursor visibility.
      ShowCursor / HideCursor record intent; FlushOutput emits the actual
      ESC sequence once at the end of the frame so overlays cannot
      accidentally override the editor's cursor.
      Override CommitCursorVisibility for platform-specific non-ANSI paths
      (e.g. Win32 SetConsoleCursorInfo). }
    procedure HideCursor; virtual;
    procedure ShowCursor; virtual;
    procedure CommitCursorVisibility(AWant: Boolean); virtual;

    procedure EnterAltScreen; virtual;
    procedure ExitAltScreen; virtual;

    { Enable/disable bracketed paste mode (ESC[?2004h / ESC[?2004l).
      When enabled the terminal wraps user-initiated pastes in ESC[200~...ESC[201~
      so they can be distinguished from typed input.  No-op on platforms that
      don't support it. }
    procedure EnableBracketedPaste; virtual;
    procedure DisableBracketedPaste; virtual;
  end;

type
  TTerminalFactory = function: TTerminal;

procedure RegisterTerminalFactory(AFactory: TTerminalFactory);
function Term: TTerminal;

{ ── Color helpers ── }

{ Construct a truecolor (24-bit RGB) TColor value. }
function RGB(R, G, B: Byte): TColor; inline;
{ True when C carries 24-bit RGB; False when it's a palette reference. }
function IsRGB(C: TColor): Boolean; inline;
{ R/G/B channel extractors.  Defined for any TColor; for palette colors
  they reflect the encoding of the palette index, not the rendered color. }
function RedOf  (C: TColor): Byte; inline;
function GreenOf(C: TColor): Byte; inline;
function BlueOf (C: TColor): Byte; inline;
{ Extract the palette index.  If C is RGB, returns ToPalette(C). }
function PaletteOf(C: TColor): T8BitColor;
{ Best 8-bit palette approximation of C.  For palette inputs, returns the
  index unchanged.  For RGB inputs, quantizes to the closer of the xterm
  6x6x6 cube and the 24-step greyscale ramp (235x235x235 brightness diff). }
function ToPalette(C: TColor): T8BitColor;

implementation

{ Pull in the platform back-end so its initialization section fires and calls
  RegisterTerminalFactory automatically.  The conditional matches the source
  paths declared in project.xml, so exactly one platform unit is compiled. }
uses
  SysUtils,
  {$IF defined(WINDOWS) or defined(UNIX)}
  TermUI.Terminal.Platform
  {$ENDIF}
  ;

{ ── ANSI code tables (same as before, now used only during flush) ── }

const
  FGCode: array[T8BitColor] of string = (
    '39', '30', '31', '32', '33', '34', '35', '36', '37',
    '90', '91', '92', '93', '94', '95', '96', '97',
    '30',          { clBackground — black foreground }
    '38;5;16', '38;5;17', '38;5;18', '38;5;19', '38;5;20', '38;5;21', '38;5;22', '38;5;23',
    '38;5;24', '38;5;25', '38;5;26', '38;5;27', '38;5;28', '38;5;29', '38;5;30', '38;5;31',
    '38;5;32', '38;5;33', '38;5;34', '38;5;35', '38;5;36', '38;5;37', '38;5;38', '38;5;39',
    '38;5;40', '38;5;41', '38;5;42', '38;5;43', '38;5;44', '38;5;45', '38;5;46', '38;5;47',
    '38;5;48', '38;5;49', '38;5;50', '38;5;51', '38;5;52', '38;5;53', '38;5;54', '38;5;55',
    '38;5;56', '38;5;57', '38;5;58', '38;5;59', '38;5;60', '38;5;61', '38;5;62', '38;5;63',
    '38;5;64', '38;5;65', '38;5;66', '38;5;67', '38;5;68', '38;5;69', '38;5;70', '38;5;71',
    '38;5;72', '38;5;73', '38;5;74', '38;5;75', '38;5;76', '38;5;77', '38;5;78', '38;5;79',
    '38;5;80', '38;5;81', '38;5;82', '38;5;83', '38;5;84', '38;5;85', '38;5;86', '38;5;87',
    '38;5;88', '38;5;89', '38;5;90', '38;5;91', '38;5;92', '38;5;93', '38;5;94', '38;5;95',
    '38;5;96', '38;5;97', '38;5;98', '38;5;99', '38;5;100', '38;5;101', '38;5;102', '38;5;103',
    '38;5;104', '38;5;105', '38;5;106', '38;5;107', '38;5;108', '38;5;109', '38;5;110', '38;5;111',
    '38;5;112', '38;5;113', '38;5;114', '38;5;115', '38;5;116', '38;5;117', '38;5;118', '38;5;119',
    '38;5;120', '38;5;121', '38;5;122', '38;5;123', '38;5;124', '38;5;125', '38;5;126', '38;5;127',
    '38;5;128', '38;5;129', '38;5;130', '38;5;131', '38;5;132', '38;5;133', '38;5;134', '38;5;135',
    '38;5;136', '38;5;137', '38;5;138', '38;5;139', '38;5;140', '38;5;141', '38;5;142', '38;5;143',
    '38;5;144', '38;5;145', '38;5;146', '38;5;147', '38;5;148', '38;5;149', '38;5;150', '38;5;151',
    '38;5;152', '38;5;153', '38;5;154', '38;5;155', '38;5;156', '38;5;157', '38;5;158', '38;5;159',
    '38;5;160', '38;5;161', '38;5;162', '38;5;163', '38;5;164', '38;5;165', '38;5;166', '38;5;167',
    '38;5;168', '38;5;169', '38;5;170', '38;5;171', '38;5;172', '38;5;173', '38;5;174', '38;5;175',
    '38;5;176', '38;5;177', '38;5;178', '38;5;179', '38;5;180', '38;5;181', '38;5;182', '38;5;183',
    '38;5;184', '38;5;185', '38;5;186', '38;5;187', '38;5;188', '38;5;189', '38;5;190', '38;5;191',
    '38;5;192', '38;5;193', '38;5;194', '38;5;195', '38;5;196', '38;5;197', '38;5;198', '38;5;199',
    '38;5;200', '38;5;201', '38;5;202', '38;5;203', '38;5;204', '38;5;205', '38;5;206', '38;5;207',
    '38;5;208', '38;5;209', '38;5;210', '38;5;211', '38;5;212', '38;5;213', '38;5;214', '38;5;215',
    '38;5;216', '38;5;217', '38;5;218', '38;5;219', '38;5;220', '38;5;221', '38;5;222', '38;5;223',
    '38;5;224', '38;5;225', '38;5;226', '38;5;227', '38;5;228', '38;5;229', '38;5;230', '38;5;231',
    '38;5;232', '38;5;233', '38;5;234', '38;5;235', '38;5;236', '38;5;237', '38;5;238', '38;5;239',
    '38;5;240', '38;5;241', '38;5;242', '38;5;243', '38;5;244', '38;5;245', '38;5;246', '38;5;247',
    '38;5;248', '38;5;249', '38;5;250', '38;5;251', '38;5;252', '38;5;253', '38;5;254', '38;5;255'
  );
  BGCode: array[T8BitColor] of string = (
    '49', '40', '41', '42', '43', '44', '45', '46', '47',
    '100', '101', '102', '103', '104', '105', '106', '107',
    '40',          { clBackground — black background }
    '48;5;16', '48;5;17', '48;5;18', '48;5;19', '48;5;20', '48;5;21', '48;5;22', '48;5;23',
    '48;5;24', '48;5;25', '48;5;26', '48;5;27', '48;5;28', '48;5;29', '48;5;30', '48;5;31',
    '48;5;32', '48;5;33', '48;5;34', '48;5;35', '48;5;36', '48;5;37', '48;5;38', '48;5;39',
    '48;5;40', '48;5;41', '48;5;42', '48;5;43', '48;5;44', '48;5;45', '48;5;46', '48;5;47',
    '48;5;48', '48;5;49', '48;5;50', '48;5;51', '48;5;52', '48;5;53', '48;5;54', '48;5;55',
    '48;5;56', '48;5;57', '48;5;58', '48;5;59', '48;5;60', '48;5;61', '48;5;62', '48;5;63',
    '48;5;64', '48;5;65', '48;5;66', '48;5;67', '48;5;68', '48;5;69', '48;5;70', '48;5;71',
    '48;5;72', '48;5;73', '48;5;74', '48;5;75', '48;5;76', '48;5;77', '48;5;78', '48;5;79',
    '48;5;80', '48;5;81', '48;5;82', '48;5;83', '48;5;84', '48;5;85', '48;5;86', '48;5;87',
    '48;5;88', '48;5;89', '48;5;90', '48;5;91', '48;5;92', '48;5;93', '48;5;94', '48;5;95',
    '48;5;96', '48;5;97', '48;5;98', '48;5;99', '48;5;100', '48;5;101', '48;5;102', '48;5;103',
    '48;5;104', '48;5;105', '48;5;106', '48;5;107', '48;5;108', '48;5;109', '48;5;110', '48;5;111',
    '48;5;112', '48;5;113', '48;5;114', '48;5;115', '48;5;116', '48;5;117', '48;5;118', '48;5;119',
    '48;5;120', '48;5;121', '48;5;122', '48;5;123', '48;5;124', '48;5;125', '48;5;126', '48;5;127',
    '48;5;128', '48;5;129', '48;5;130', '48;5;131', '48;5;132', '48;5;133', '48;5;134', '48;5;135',
    '48;5;136', '48;5;137', '48;5;138', '48;5;139', '48;5;140', '48;5;141', '48;5;142', '48;5;143',
    '48;5;144', '48;5;145', '48;5;146', '48;5;147', '48;5;148', '48;5;149', '48;5;150', '48;5;151',
    '48;5;152', '48;5;153', '48;5;154', '48;5;155', '48;5;156', '48;5;157', '48;5;158', '48;5;159',
    '48;5;160', '48;5;161', '48;5;162', '48;5;163', '48;5;164', '48;5;165', '48;5;166', '48;5;167',
    '48;5;168', '48;5;169', '48;5;170', '48;5;171', '48;5;172', '48;5;173', '48;5;174', '48;5;175',
    '48;5;176', '48;5;177', '48;5;178', '48;5;179', '48;5;180', '48;5;181', '48;5;182', '48;5;183',
    '48;5;184', '48;5;185', '48;5;186', '48;5;187', '48;5;188', '48;5;189', '48;5;190', '48;5;191',
    '48;5;192', '48;5;193', '48;5;194', '48;5;195', '48;5;196', '48;5;197', '48;5;198', '48;5;199',
    '48;5;200', '48;5;201', '48;5;202', '48;5;203', '48;5;204', '48;5;205', '48;5;206', '48;5;207',
    '48;5;208', '48;5;209', '48;5;210', '48;5;211', '48;5;212', '48;5;213', '48;5;214', '48;5;215',
    '48;5;216', '48;5;217', '48;5;218', '48;5;219', '48;5;220', '48;5;221', '48;5;222', '48;5;223',
    '48;5;224', '48;5;225', '48;5;226', '48;5;227', '48;5;228', '48;5;229', '48;5;230', '48;5;231',
    '48;5;232', '48;5;233', '48;5;234', '48;5;235', '48;5;236', '48;5;237', '48;5;238', '48;5;239',
    '48;5;240', '48;5;241', '48;5;242', '48;5;243', '48;5;244', '48;5;245', '48;5;246', '48;5;247',
    '48;5;248', '48;5;249', '48;5;250', '48;5;251', '48;5;252', '48;5;253', '48;5;254', '48;5;255'
  );

var
  GTerm:    TTerminal        = nil;
  GFactory: TTerminalFactory = nil;

{ ── Color helpers ── }

const
  CTagRGB     = $01000000;
  CTagMask    = $FF000000;
  CCubeSteps: array[0..5] of Integer = (0, 95, 135, 175, 215, 255);

function RGB(R, G, B: Byte): TColor;
begin
  Result := TColor(CTagRGB or (LongInt(R) shl 16) or (LongInt(G) shl 8) or LongInt(B));
end;

function IsRGB(C: TColor): Boolean;
begin
  Result := (LongInt(C) and CTagMask) = CTagRGB;
end;

function RedOf  (C: TColor): Byte; begin Result := (LongInt(C) shr 16) and $FF; end;
function GreenOf(C: TColor): Byte; begin Result := (LongInt(C) shr  8) and $FF; end;
function BlueOf (C: TColor): Byte; begin Result :=  LongInt(C)         and $FF; end;

function PaletteOf(C: TColor): T8BitColor;
begin
  if IsRGB(C) then
    Result := ToPalette(C)
  else
    Result := T8BitColor(LongInt(C) and $FFFF);
end;

{ Quantize a 0..255 channel to its index (0..5) in the 6x6x6 cube. }
function CubeIndex(V: Byte): Integer;
var Best, BestDiff, I, D: Integer;
begin
  Best := 0; BestDiff := MaxInt;
  for I := 0 to 5 do
  begin
    D := Abs(Integer(V) - CCubeSteps[I]);
    if D < BestDiff then begin BestDiff := D; Best := I; end;
  end;
  Result := Best;
end;

function ToPalette(C: TColor): T8BitColor;
var
  R, G, B, Ri, Gi, Bi, CubeIdx, GreyIdx, GreyV: Integer;
  CubeR, CubeG, CubeB, GreyDist, CubeDist: Integer;
begin
  if not IsRGB(C) then
  begin
    Result := T8BitColor(LongInt(C) and $FFFF);
    Exit;
  end;
  R := RedOf(C); G := GreenOf(C); B := BlueOf(C);

  { Cube candidate }
  Ri := CubeIndex(R); Gi := CubeIndex(G); Bi := CubeIndex(B);
  CubeR := CCubeSteps[Ri]; CubeG := CCubeSteps[Gi]; CubeB := CCubeSteps[Bi];
  CubeIdx  := 16 + 36*Ri + 6*Gi + Bi;
  CubeDist := Sqr(R - CubeR) + Sqr(G - CubeG) + Sqr(B - CubeB);

  { Greyscale candidate (xterm 232..255 = 8 + 10*i, i in 0..23) }
  GreyIdx := (R + G + B) div 3;
  if      GreyIdx < 8   then GreyIdx := 0
  else if GreyIdx > 238 then GreyIdx := 23
  else                       GreyIdx := (GreyIdx - 3) div 10;
  GreyV    := 8 + 10 * GreyIdx;
  GreyDist := Sqr(R - GreyV) + Sqr(G - GreyV) + Sqr(B - GreyV);

  if GreyDist < CubeDist then
    Result := T8BitColor(Ord(p8Xterm16) + (232 - 16) + GreyIdx)
  else
    Result := T8BitColor(Ord(p8Xterm16) + (CubeIdx - 16));
end;

{ SGR fragment for one color.  AKind is '38' (foreground) or '48' (background).
  If C is RGB and the terminal supports truecolor, emits 'K;2;R;G;B'.
  Otherwise falls back to the 256-color palette (converting RGB if needed). }
function ColorSGR(C: TColor; const AKind: string; ATrueColor: Boolean;
  const APalette: array of string): string;
begin
  if IsRGB(C) then
  begin
    if ATrueColor then
      Result := AKind + ';2;' + IntToStr(RedOf(C)) + ';' + IntToStr(GreenOf(C))
                + ';' + IntToStr(BlueOf(C))
    else
      Result := APalette[Ord(ToPalette(C))];
  end
  else
    Result := APalette[Ord(PaletteOf(C))];
end;

{ Detect truecolor support from environment.  Heuristic, not authoritative —
  matches the convention used by vim/neovim/fzf/bat/etc. }
function DetectTrueColor: Boolean;
var S: string;
begin
  S := LowerCase(GetEnvironmentVariable('COLORTERM'));
  if (S = 'truecolor') or (S = '24bit') then Exit(True);
  S := LowerCase(GetEnvironmentVariable('TERM'));
  Result := Pos('-direct', S) > 0;
end;

{ ── Buffer helpers ── }

procedure TTerminal.AllocBuffers(W, H: Integer);
begin
  FBufW := W;
  FBufH := H;
  SetLength(FBack,  W * H);
  SetLength(FFront, W * H);
  SetLength(FDirtyRows, H);
  FillChar(FDirtyRows[0], H * SizeOf(Boolean), 0);
  BlankBuffer(FBack);
  InvalidateFront;  { mark every front cell dirty so the first flush redraws all }
end;

procedure TTerminal.BlankBuffer(var Buf: TScreenBuffer);
var I: Integer;
begin
  for I := 0 to High(Buf) do
  begin
    Buf[I].Ch        := ' ';
    Buf[I].FG        := clDefault;
    Buf[I].BG        := clDefault;
    Buf[I].Underline := False;
  end;
end;

function TTerminal.CellIndex(X, Y: Integer): Integer;
begin
  Result := (Y - 1) * FBufW + (X - 1);
end;

{ ── Base class boilerplate ── }

function TTerminal.IsTTY: Boolean;
begin
  Result := False;
end;

function TTerminal.SupportsTrueColor: Boolean;
begin
  Result := FTrueColor;
end;

procedure TTerminal.InitColor;
var W, H: Integer;
begin
  FUseColor  := IsTTY;
  FTrueColor := FUseColor and DetectTrueColor;
  FCurX  := 1; FCurY  := 1;
  FCursorX := 1; FCursorY := 1;
  FCurFG := clDefault; FCurBG := clDefault; FCurUL := False;
  W := Width; H := Height;
  if W <= 0 then W := 80;
  if H <= 0 then H := 24;
  AllocBuffers(W, H);
end;

function TTerminal.UseColor: Boolean;
begin
  Result := FUseColor;
end;

function TTerminal.HasResized: Boolean;
begin
  Result := False;
end;

procedure TTerminal.DiscardPendingInput;
var
  Key: TKeyEvent;
begin
  while ReadKeyTimeout(Key, 0) do ;
end;

procedure TTerminal.RawWrite(const S: RawByteString);
begin
  System.Write(S);
end;

{ ── Buffer-aware drawing methods ── }

procedure TTerminal.GotoXY(X, Y: Integer);
begin
  FCurX := X;
  FCurY := Y;
end;

procedure TTerminal.SetFG(C: TColor);
begin
  FCurFG := C;
end;

procedure TTerminal.SetBG(C: TColor);
begin
  FCurBG := C;
end;

procedure TTerminal.ResetColors;
begin
  FCurFG := clDefault;
  FCurBG := clDefault;
  FCurUL := False;
end;

procedure TTerminal.SetUnderline(AOn: Boolean);
begin
  FCurUL := AOn;
end;

procedure TTerminal.WriteStr(const S: string);
var
  I, Idx, SeqLen: Integer;
  C: string;
begin
  I := 1;
  while I <= Length(S) do
  begin
    SeqLen := UTF8SeqLen(S, I);
    C := Copy(S, I, SeqLen);
    Inc(I, SeqLen);
    if C = #10 then begin Inc(FCurY); FCurX := 1; Continue; end;
    if C = #13 then begin FCurX := 1;             Continue; end;
    if (FCurX >= 1) and (FCurX <= FBufW) and
       (FCurY >= 1) and (FCurY <= FBufH) then
    begin
      Idx := CellIndex(FCurX, FCurY);
      FBack[Idx].Ch        := C;
      FBack[Idx].FG        := FCurFG;
      FBack[Idx].BG        := FCurBG;
      FBack[Idx].Underline := FCurUL;
    end;
    Inc(FCurX);  { one visual column per codepoint }
  end;
end;

procedure TTerminal.ClearScreen;
begin
  { Reallocate if terminal was resized }
  if (Width <> FBufW) or (Height <> FBufH) then
    AllocBuffers(Width, Height);
  BlankBuffer(FBack);
  FCurX := 1; FCurY := 1;
end;

procedure TTerminal.ClearToEOL;
var X, Idx: Integer;
begin
  for X := FCurX to FBufW do
  begin
    Idx := CellIndex(X, FCurY);
    FBack[Idx].Ch        := ' ';
    FBack[Idx].FG        := FCurFG;
    FBack[Idx].BG        := FCurBG;
    FBack[Idx].Underline := FCurUL;
  end;
end;

procedure TTerminal.InvalidateFront;
var I: Integer;
begin
  { Use #0 as sentinel — differs from every valid painted cell (spaces at minimum) }
  for I := 0 to High(FFront) do
    FFront[I].Ch := #0;
  { Reset cursor intent — each frame's paint decides fresh. }
  FCursorWant := False;
  FCursorX    := 1;
  FCursorY    := 1;
end;

{ ── Flush: diff and emit ── }

procedure TTerminal.FlushOutput;
var
  W, H:    Integer;
  X, Y:    Integer;
  Idx:     Integer;
  B, F:    TScreenCell;
  LastX:   Integer;
  LastY:          Integer;
  LastFG:         TColor;
  LastBG:         TColor;
  LastUL:         Boolean;
  Buf:            string;
  RowHadEmit:     Boolean;
  RowHadMultiByte: Boolean;

  procedure Emit(const S: string); inline;
  begin
    Buf := Buf + S;
  end;

begin
  W := Width;
  H := Height;

  { Grow buffers if terminal was resized between ClearScreen and Flush }
  if (W <> FBufW) or (H <> FBufH) then
    AllocBuffers(W, H);

  LastX  := -1; LastY  := -1;
  LastFG := clDefault; LastBG := clDefault; LastUL := False;
  { Hide cursor immediately so it does not flicker across the screen during
    the diff pass.  Restored to FCursorWant at the very end. }
  Buf    := #27'[?25l';
  CommitCursorVisibility(False);

  for Y := 1 to H do
  begin
    RowHadEmit     := False;
    RowHadMultiByte := False;

    for X := 1 to W do
    begin
      Idx := CellIndex(X, Y);
      B := FBack[Idx];
      F := FFront[Idx];

      if (B.Ch = F.Ch) and (B.FG = F.FG) and (B.BG = F.BG) and
         (B.Underline = F.Underline) then
        Continue;

      { Position cursor if needed }
      if (X <> LastX) or (Y <> LastY) then
      begin
        Emit(#27'[' + IntToStr(Y) + ';' + IntToStr(X) + 'f');
        LastX := X; LastY := Y;
      end;

      { Color / attribute changes }
      if FUseColor then
      begin
        if (B.FG <> LastFG) or (B.BG <> LastBG) or (B.Underline <> LastUL) then
        begin
          Emit(#27'[');
          Emit(ColorSGR(B.FG, '38', FTrueColor, FGCode));
          Emit(';');
          Emit(ColorSGR(B.BG, '48', FTrueColor, BGCode));
          if B.Underline then Emit(';4') else Emit(';24');
          Emit('m');
          LastFG := B.FG; LastBG := B.BG; LastUL := B.Underline;
        end;
      end;

      Emit(B.Ch);
      Inc(LastX);
      RowHadEmit := True;
      if (Length(B.Ch) > 0) and (Ord(B.Ch[1]) > $7F) then RowHadMultiByte := True;

      FFront[Idx] := B;
    end;

    { Multi-byte UTF-8 chars cause the terminal's visual cursor to lag behind
      our cell-grid LastX.  Trailing spaces that should clear the right edge of
      the row end up at wrong visual columns.  \e[K erases from the actual
      terminal cursor position to end of line, covering any uncovered cells. }
    if RowHadEmit and RowHadMultiByte then
      Emit(#27'[K');
  end;

  { Reposition the terminal cursor to the requested display position, not the
    drawing pen — they diverge whenever painting continues after PlaceCursor. }
  if FUseColor then Buf := Buf + #27'[0m';
  Buf := Buf + #27'[' + IntToStr(FCursorY) + ';' + IntToStr(FCursorX) + 'f';
  { Emit cursor visibility once, after all painting, so overlays cannot
    accidentally hide the cursor that a lower control requested. }
  if FCursorWant then Buf := Buf + #27'[?25h'
  else                 Buf := Buf + #27'[?25l';
  if Buf <> '' then
    RawWrite(Buf);
  Flush(Output);
  CommitCursorVisibility(FCursorWant);
end;

procedure TTerminal.FlushRow(Y: Integer);
var
  X, Idx:  Integer;
  B, F:    TScreenCell;
  LastX:   Integer;
  LastFG:  TColor;
  LastBG:  TColor;
  LastUL:  Boolean;
  Buf:     RawByteString;
begin
  if (Y < 1) or (Y > FBufH) then Exit;
  Buf    := #27'[?25l';
  CommitCursorVisibility(False);
  LastX  := -1;
  LastFG := clDefault; LastBG := clDefault; LastUL := False;
  for X := 1 to FBufW do
  begin
    Idx := CellIndex(X, Y);
    B := FBack[Idx];
    F := FFront[Idx];
    if (B.Ch = F.Ch) and (B.FG = F.FG) and (B.BG = F.BG) and
       (B.Underline = F.Underline) then
      Continue;
    if X <> LastX then
    begin
      Buf := Buf + #27'[' + IntToStr(Y) + ';' + IntToStr(X) + 'f';
      LastX := X;
    end;
    if FUseColor then
    begin
      if (B.FG <> LastFG) or (B.BG <> LastBG) or (B.Underline <> LastUL) then
      begin
        Buf := Buf + #27'[' + ColorSGR(B.FG, '38', FTrueColor, FGCode)
                   + ';' + ColorSGR(B.BG, '48', FTrueColor, BGCode);
        if B.Underline then Buf := Buf + ';4' else Buf := Buf + ';24';
        Buf := Buf + 'm';
        LastFG := B.FG; LastBG := B.BG; LastUL := B.Underline;
      end;
    end;
    Buf   := Buf + B.Ch;
    Inc(LastX);
    FFront[Idx] := B;
  end;
  if FUseColor then Buf := Buf + #27'[0m';
  Buf := Buf + #27'[' + IntToStr(FCursorY) + ';' + IntToStr(FCursorX) + 'f';
  if FCursorWant then Buf := Buf + #27'[?25h'
  else                 Buf := Buf + #27'[?25l';
  RawWrite(Buf);
  Flush(Output);
  CommitCursorVisibility(FCursorWant);
end;

procedure TTerminal.HintDirtyRow(ARow: Integer);
begin
  if (ARow >= 1) and (ARow <= Length(FDirtyRows)) then
    FDirtyRows[ARow - 1] := True;
end;

function TTerminal.HasDirtyRowHints: Boolean;
var I: Integer;
begin
  for I := 0 to High(FDirtyRows) do
    if FDirtyRows[I] then Exit(True);
  Result := False;
end;

procedure TTerminal.FlushDirtyRows;
var I: Integer;
begin
  for I := 0 to High(FDirtyRows) do
    if FDirtyRows[I] then
    begin
      FlushRow(I + 1);
      FDirtyRows[I] := False;
    end;
end;

procedure TTerminal.PlaceCursor(X, Y: Integer);
begin
  FCursorX := X;
  FCursorY := Y;
end;

procedure TTerminal.ShowCursor;
begin
  FCursorWant := True;
end;

procedure TTerminal.HideCursor;
begin
  FCursorWant := False;
end;

procedure TTerminal.CommitCursorVisibility(AWant: Boolean);
begin
  { Base: ANSI handled in FlushOutput's Buf.  Override for non-ANSI paths. }
end;

procedure TTerminal.EnterAltScreen;
begin
end;

procedure TTerminal.ExitAltScreen;
begin
end;

procedure TTerminal.EnableBracketedPaste;
begin
end;

procedure TTerminal.DisableBracketedPaste;
begin
end;

procedure RegisterTerminalFactory(AFactory: TTerminalFactory);
begin
  GFactory := AFactory;
end;

function Term: TTerminal;
begin
  if GTerm = nil then
  begin
    if not Assigned(GFactory) then
      raise Exception.Create('No terminal factory registered. ' +
        'Ensure the platform unit is in your uses clause.');
    GTerm := GFactory();
  end;
  Result := GTerm;
end;

finalization
  GTerm.Free;

end.
