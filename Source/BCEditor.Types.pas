unit BCEditor.Types;

interface {********************************************************************}

uses
  Windows,
  Classes, SysUtils,
  Forms, Graphics, Controls,
  BCEditor.Consts, BCEditor.Editor.Marks;

type
  TBCEditorArrayOfString = array of string;
  TBCEditorArrayOfSingle = array of Single;

  TBCEditorCharMethod = function(const AChar: Char): Boolean of object;

  TBCEditorCaretStyle = (csVerticalLine, csThinVerticalLine, csHorizontalLine, csThinHorizontalLine, csHalfBlock, csBlock);

  TBCEditorDropFilesEvent = procedure(ASender: TObject; APos: TPoint; AFiles: TStrings) of object;

  TBCEditorPaintEvent = procedure(ASender: TObject; ACanvas: TCanvas) of object;

  TBCEditorReplaceAction = (raCancel, raSkip, raReplace, raReplaceAll);

  TBCEditorMarkPanelPaintEvent = procedure(ASender: TObject; ACanvas: TCanvas; const ARect: TRect; const AFirstLine: Integer; const ALastLine: Integer) of object;
  TBCEditorMarkPanelLinePaintEvent = procedure(ASender: TObject; ACanvas: TCanvas; const ARect: TRect; const ALineNumber: Integer) of object;

  TBCEditorLinePaintEvent = procedure(ASender: TObject; ACanvas: TCanvas; const ARect: TRect; const ALineNumber: Integer) of object;

  TBCEditorCustomLineColorsEvent = procedure(ASender: TObject; const ALine: Integer; var AUseColors: Boolean;
    var AForeground: TColor; var ABackground: TColor) of object;

  TBCEditorTokenAddon = (taNone, taDoubleUnderline, taUnderline, taWaveLine);

  TBCEditorCustomTokenAttributeEvent = procedure(ASender: TObject; const AText: string; const ALine: Integer;
    const AChar: Integer; var AForegroundColor: TColor; var ABackgroundColor: TColor; var AStyles: TFontStyles;
    var ATokenAddon: TBCEditorTokenAddon; var ATokenAddonColor: TColor) of object;

  TBCEditorCreateFileStreamEvent = procedure(ASender: TObject; const AFileName: string; var AStream: TStream) of object;

  TBCEditorOption = (
    eoAutoIndent, { Will indent the caret on new lines with the same amount of leading white space as the preceding line }
    eoDragDropEditing, { Allows you to select a block of text and drag it within the document to another location }
    eoDropFiles, { Allows the editor accept OLE file drops }
    eoTrimTrailingLines, { Empty lines at the end of text will be removed while saving }
    eoTrimTrailingSpaces { Spaces at the end of lines will be removed while saving }
  );
  TBCEditorOptions = set of TBCEditorOption;

  TBCEditorCaretOption = (
    coRightMouseClickMove { When clicking with the right mouse for a popup menu, move the cursor to that location }
  );
  TBCEditorCaretMultiEditOption = (
    meoShowActiveLine,
    meoShowGhost { Ghost caret follows mouse cursor when moved }
  );

  TBCEditorTextEntryMode = (temInsert, temOverwrite);

  TBCEditorScrollOption = (
    soHalfPage, { When scrolling with page-up and page-down commands, only scroll a half page at a time }
    soHintFollows, { The scroll hint follows the mouse when scrolling vertically }
    soPastEndOfFile, { Allows the cursor to go past the end of file }
    soPastEndOfLine, { Allows the cursor to go past the last character into the white space at the end of a line }
    soShowVerticalScrollHint, { Shows a hint of the visible line numbers when scrolling vertically }
    soWheelClickMove { Scrolling by mouse move after wheel click. }
  );

  TBCEditorTabOption = (
    toColumns,
    toPreviousLineIndent,
    toSelectedBlockIndent,
    toTabsToSpaces
  );

  PBCEditorSelectionMode = ^TBCEditorSelectionMode;
  TBCEditorSelectionMode = (
    smColumn,
    smNormal
  );

  TBCEditorSelectionOption = (
    soALTSetsColumnMode,
    soExpandRealNumbers,
    soTermsCaseSensitive,
    soToEndOfLine,
    soTripleClickRowSelect
  );

  TBCEditorSearchEvent = (
    seInvalidate,
    seChange
  );

  TBCEditorReplaceChanges = (
    rcEngineUpdate
  );

  TBCEditorSearchOption = (
    soBackwards,
    soCaseSensitive,
    soEntireScope,
    soHighlightResults,
    soSearchOnTyping,
    soWholeWordsOnly,
    soWrapAround
  );
  TBCEditorSyncEditOption = (
    seCaseSensitive
  );
  TBCEditorSyncEditOptions = set of TBCEditorSyncEditOption;

  TBCEditorReplaceOption = (
    roBackwards,
    roCaseSensitive,
    roEntireScope,
    roPrompt,
    roReplaceAll,
    roSelectedOnly,
    roWholeWordsOnly
  );

  TBCEditorSearchEngine = (
    seNormal,
    seRegularExpression
  );

  TBCEditorSearchMapOption = (
    moShowActiveLine
  );

  TBCEditorCompletionProposalOption = (
    cpoAutoInvoke,
    cpoAutoConstraints,
    cpoAddHighlighterKeywords,
    cpoCaseSensitive,
    cpoFiltered,
    cpoParseItemsFromText,
    cpoResizeable,
    cpoShowShadow,
    cpoUseHighlighterColumnFont
  );

  TBCEditorLeftMarginBookMarkPanelOption = (
    bpoToggleBookmarkByClick,
    bpoToggleMarkByClick
  );

  TBCEditorRightMarginOption = (
    rmoMouseMove,
    rmoShowMovingHint
  );

  PBCEditorTextPosition = ^TBCEditorTextPosition;
  TBCEditorTextPosition = record
    Char: Integer;
    Line: Integer;
    class operator Equal(a, b: TBCEditorTextPosition): Boolean;
    class operator GreaterThan(a, b: TBCEditorTextPosition): Boolean;
    class operator GreaterThanOrEqual(a, b: TBCEditorTextPosition): Boolean;
    class operator LessThan(a, b: TBCEditorTextPosition): Boolean;
    class operator LessThanOrEqual(a, b: TBCEditorTextPosition): Boolean;
    class operator NotEqual(a, b: TBCEditorTextPosition): Boolean;
    function ToString(): string; inline;
  end;

  PBCEditorDisplayPosition = ^TBCEditorDisplayPosition;
  TBCEditorDisplayPosition = record
    Column: Integer;
    Row: Integer;
    class operator Equal(a, b: TBCEditorDisplayPosition): Boolean;
    class operator NotEqual(a, b: TBCEditorDisplayPosition): Boolean;
    function ToString(): string; inline;
  end;

  TBCEditorBreakType = (
    btUnspecified,
    btAny,
    btTerm
  );
  TBCEditorRangeType = (
    ttUnspecified,
    ttAddress,
    ttAssemblerComment,
    ttAssemblerReservedWord,
    ttAttribute,
    ttBlockComment,
    ttCharacter,
    ttDirective,
    ttHexNumber,
    ttHighlightedBlock,
    ttHighlightedBlockSymbol,
    ttLineComment,
    ttMailtoLink,
    ttMethod,
    ttMethodName,
    ttNumber,
    ttReservedWord,
    ttString,
    ttSymbol,
    ttWebLink
  );


  TBCEditorKeyPressWEvent = procedure(ASender: TObject; var AKey: Char) of object;

  TBCEditorContextHelpEvent = procedure(ASender: TObject; AWord: string) of object;

  TBCEditorMouseCursorEvent = procedure(ASender: TObject; const ALineCharPos: TBCEditorTextPosition; var ACursor: TCursor) of object;

  TBCEditorEmptySpace = (
    esNone,
    esNoneChar,
    esSpace,
    esTab
  );

  TBCEditorTokenHelper = record
    Background: TColor;
    Border: TColor;
    CharsBefore: Integer;
    EmptySpace: TBCEditorEmptySpace;
    ExpandedCharsBefore: Integer;
    FontStyle: TFontStyles;
    Foreground: TColor;
    IsItalic: Boolean;
    Length: Integer;
    TokenAddon: TBCEditorTokenAddon;
    TokenAddonColor: TColor;
    Text: string;
  end;

  TBCEditorSpecialCharsEndOfLineStyle = (
    eolArrow,
    eolEnter,
    eolPilcrow
  );

  TBCEditorSpecialCharsOption = (
    scoTextColor,
    scoMiddleColor,
    scoShowOnlyInSelection
  );
  TBCEditorSpecialCharsStyle = (scsDot, scsSolid);

  TBCEditorTabConvertProc = function(const ALine: string; ATabWidth: Integer; var AHasTabs: Boolean;
    const ATabChar: Char = BCEDITOR_SPACE_CHAR): string;

  TBCEditorLeftMarginLineNumberOption = (
    lnoIntens,
    lnoLeadingZeros,
    lnoAfterLastLine
  );

  TBCEditorMatchingPairOption = (
    mpoHighlightAfterToken,
    mpoHighlightUnmatched,
    mpoUnderline,
    mpoUseMatchedColor
  );

  TBCEditorMinimapOption = (
    moShowBookmarks,
    moShowIndentGuides,
    moShowSearchResults,
    moShowSpecialChars
  );

  TBCEditorMinimapAlign = (maLeft, maRight);
  TBCEditorSearchMapAlign = (saLeft, saRight);

  TBCEditorUndoOption = (
    uoGroupUndo,
    uoUndoAfterLoad,
    uoUndoAfterSave
  );

  TBCEditorCase = (cNone=-1, cUpper=0, cLower=1, cAlternating=2, cSentence=3, cTitle=4, cOriginal=5);

  TBCEditorKeyCharType = (ctFoldOpen, ctFoldClose, ctSkipOpen, ctSkipClose);

  TBCEditorSortOrder = (soAsc, soDesc);

  TBCEditorWordWrapWidth = (wwwPage, wwwRightMargin);

  TBCEditorCodeFoldingMarkStyle = (msCircle, msSquare, msTriangle);
  TBCEditorCodeFoldingHintIndicatorMarkStyle = (imsThreeDots, imsTriangle);
  TBCEditorCodeFoldingChanges = (fcEnabled, fcRefresh, fcRescan);

  TBCEditorCodeFoldingOption = (
    cfoAutoPadding,
    cfoAutoWidth,
    cfoFoldMultilineComments,
    cfoHighlightFoldingLine,
    cfoHighlightIndentGuides,
    cfoHighlightMatchingPair,
    cfoShowCollapsedLine,
    cfoShowIndentGuides,
    cfoShowTreeLine,
    cfoUncollapseByHintClick
  );

  TBCEditorTokenInfoOption = (
    tioAutoSize
  );

  TBCEditorLeftMarginBorderStyle = (mbsNone, mbsMiddle, mbsRight);

  TBCEditorScrollHintFormat = (shfTopLineOnly, shfTopToBottom);

  TBCEditorMinimapIndicatorOption = (ioInvertBlending, ioShowBorder, ioUseBlending);

  TBCEditorCodeFoldingHintIndicatorOption = (hioShowBorder, hioShowMark);

  TBCEditorCaretOptions = set of TBCEditorCaretOption;
  TBCEditorCaretMultiEditOptions = set of TBCEditorCaretMultiEditOption;
  TBCEditorLeftMarginLineNumberOptions = set of TBCEditorLeftMarginLineNumberOption;
  TBCEditorMatchingPairOptions = set of TBCEditorMatchingPairOption;
  TBCEditorSearchOptions = set of TBCEditorSearchOption;
  TBCEditorSearchMapOptions = set of TBCEditorSearchMapOption;
  TBCEditorLeftMarginBookMarkPanelOptions = set of TBCEditorLeftMarginBookMarkPanelOption;
  TBCEditorReplaceOptions = set of TBCEditorReplaceOption;
  TBCEditorRightMarginOptions = set of TBCEditorRightMarginOption;
  TBCEditorScrollOptions = set of TBCEditorScrollOption;
  TBCEditorSelectionOptions = set of TBCEditorSelectionOption;
  TBCEditorSpecialCharsOptions = set of TBCEditorSpecialCharsOption;
  TBCEditorTabOptions = set of TBCEditorTabOption;
  TBCEditorTokenInfoOptions = set of TBCEditorTokenInfoOption;
  TUndoOptions = set of TBCEditorUndoOption;
  TBCEditorCompletionProposalOptions = set of TBCEditorCompletionProposalOption;
  TBCEditorCodeFoldingOptions = set of TBCEditorCodeFoldingOption;
  TBCEditorCodeFoldingHintIndicatorOptions = set of TBCEditorCodeFoldingHintIndicatorOption;
  TItemType = (ritUnspecified, ritMultiLineString, ritSingleLineString, ritMultiLineComment, ritSingleLineComment);

  TCaretChangedEvent = procedure(ASender: TObject; X, Y: Integer) of object;
  TMarginClickEvent = procedure(ASender: TObject; AButton: TMouseButton; X, Y, ALine: Integer; AMark: TBCEditorMark) of object;
  TScrollEvent = procedure(ASender: TObject; AScrollBar: TScrollBarKind) of object;
  TSelectedEvent = procedure(Sender: TObject; var ASelectedItem: string) of object;
  TValidateEvent = procedure(ASender: TObject; Shift: TShiftState; EndToken: Char) of object;

  TBCEditorQuadColor = packed record
  case Boolean of
    True: (Blue, Green, Red, Alpha: Byte);
    False: (Quad: Cardinal);
  end;
  PBCEditorQuadColor = ^TBCEditorQuadColor;

function Point(const APosition: TBCEditorTextPosition): TPoint; overload; inline;
function Max(const A, B: TBCEditorTextPosition): TBCEditorTextPosition; overload; inline;
function Min(const A, B: TBCEditorTextPosition): TBCEditorTextPosition; overload; inline;
function TextPosition(const AChar, ALine: Integer): TBCEditorTextPosition; overload; inline;
function TextPosition(const APos: TPoint): TBCEditorTextPosition; overload; inline;

const
  InvalidTextPosition: TBCEditorTextPosition = (Char: -1; Line: -1);

implementation {***************************************************************}

function Max(const A, B: TBCEditorTextPosition): TBCEditorTextPosition;
begin
  if (A > B) then
    Result := A
  else
    Result := B;
end;

function Min(const A, B: TBCEditorTextPosition): TBCEditorTextPosition;
begin
  if (A < B) then
    Result := A
  else
    Result := B;
end;

function Point(const APosition: TBCEditorTextPosition): TPoint;
begin
  Result.X := APosition.Char;
  Result.Y := APosition.Line;
end;

function TextPosition(const AChar, ALine: Integer): TBCEditorTextPosition;
begin
  Result.Char := AChar;
  Result.Line := ALine;
end;

function TextPosition(const APos: TPoint): TBCEditorTextPosition;
begin
  Result.Char := APos.X;
  Result.Line := APos.Y;
end;

{ TBCEditorDisplayPosition ****************************************************}

class operator TBCEditorDisplayPosition.Equal(a, b: TBCEditorDisplayPosition): Boolean;
begin
  Result := (a.Column = b.Column) and (a.Row = b.Row);
end;

class operator TBCEditorDisplayPosition.NotEqual(a, b: TBCEditorDisplayPosition): Boolean;
begin
  Result := (a.Column <> b.Column) or (a.Row <> b.Row);
end;

function TBCEditorDisplayPosition.ToString(): string;
begin
  Result := '(' + IntToStr(Column) + ',' + IntToStr(Row) + ')';
end;

{ TBCEditorTextPosition *******************************************************}

class operator TBCEditorTextPosition.Equal(a, b: TBCEditorTextPosition): Boolean;
begin
  Result := (a.Char = b.Char) and (a.Line = b.Line);
end;

class operator TBCEditorTextPosition.GreaterThan(a, b: TBCEditorTextPosition): Boolean;
begin
  Result := (a.Line > b.Line) or (a.Char > b.Char) and (a.Line = b.Line);
end;

class operator TBCEditorTextPosition.GreaterThanOrEqual(a, b: TBCEditorTextPosition): Boolean;
begin
  Result := (a.Line > b.Line) or (a.Char >= b.Char) and (a.Line = b.Line);
end;

class operator TBCEditorTextPosition.LessThan(a, b: TBCEditorTextPosition): Boolean;
begin
  Result := (a.Line < b.Line) or (a.Char < b.Char) and (a.Line = b.Line);
end;

class operator TBCEditorTextPosition.LessThanOrEqual(a, b: TBCEditorTextPosition): Boolean;
begin
  Result := (a.Line < b.Line) or (a.Char <= b.Char) and (a.Line = b.Line);
end;

class operator TBCEditorTextPosition.NotEqual(a, b: TBCEditorTextPosition): Boolean;
begin
  Result := (a.Char <> b.Char) or (a.Line <> b.Line);
end;

function TBCEditorTextPosition.ToString(): string;
begin
  Result := '(' + IntToStr(Char) + ',' + IntToStr(Line) + ')';
end;

end.
