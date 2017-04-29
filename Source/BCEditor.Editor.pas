unit BCEditor.Editor;

interface {********************************************************************}

uses
  Windows, Messages,
  Classes, SysUtils, Contnrs, UITypes, StrUtils, Generics.Collections,
  Forms, StdActns, Controls, Graphics, StdCtrls, ExtCtrls, Dialogs, Consts,
  BCEditor.Consts, BCEditor.Editor.ActiveLine,
  BCEditor.Editor.Marks, BCEditor.Editor.Caret, BCEditor.Editor.CodeFolding,
  BCEditor.Types, BCEditor.Editor.CompletionProposal,
  BCEditor.Editor.CompletionProposal.PopupWindow, BCEditor.Editor.Glyph, BCEditor.Editor.InternalImage,
  BCEditor.Editor.KeyCommands, BCEditor.Editor.LeftMargin, BCEditor.Editor.MatchingPair,
  BCEditor.Editor.Replace, BCEditor.Editor.RightMargin, BCEditor.Editor.Scroll, BCEditor.Editor.Search,
  BCEditor.Editor.Selection, BCEditor.Editor.SpecialChars,
  BCEditor.Editor.Tabs, BCEditor.Editor.WordWrap,
  BCEditor.Editor.CodeFolding.Hint.Form, BCEditor.Highlighter,
  BCEditor.KeyboardHandler, BCEditor.Lines, BCEditor.PaintHelper, BCEditor.Editor.SyncEdit,
  BCEditor.Editor.TokenInfo, BCEditor.Utils, BCEditor.Editor.TokenInfo.PopupWindow;

type
  TCustomBCEditor = class(TCustomControl)
  strict private type
    TBCEditorLines = class(BCEditor.Lines.TBCEditorLines);
    TBCEditorReplace = class(BCEditor.Editor.Replace.TBCEditorReplace);
    TBCEditorSearch = class(BCEditor.Editor.Search.TBCEditorSearch);
    TBCEditorSpecialChars = class(BCEditor.Editor.SpecialChars.TBCEditorSpecialChars);

    TState = set of (esRowsChanged, esCaretMoved, esScrolled,
      esLinesCleared, esLinesDeleted, esLinesInserted, esLinesUpdated,
      esIgnoreNextChar, esCaretVisible, esDblClicked, esWaitForDragging,
      esCodeFoldingInfoClicked, esInSelection, esDragging, esFind, esReplace,
      esRowsUpdating);

    TMatchingPairTokenMatch = record
      Position: TBCEditorTextPosition;
      Token: string;
    end;

    TMatchingPairTokenResult = (
      trCloseAndOpenTokenFound,
      trCloseTokenFound,
      trNotFound,
      trOpenTokenFound,
      trOpenAndCloseTokenFound
    );

    TMultiCarets = class(TList<TBCEditorDisplayPosition>)
    private
      function GetColumn(AIndex: Integer): Integer; inline;
      function GetRow(AIndex: Integer): Integer; inline;
      procedure PutColumn(AIndex: Integer; AValue: Integer); inline;
      procedure PutRow(AIndex: Integer; AValue: Integer); inline;
    public
      property Column[Index: Integer]: Integer read GetColumn write PutColumn;
      property Row[Index: Integer]: Integer read GetRow write PutRow;
    end;

    TRow = record
    type
      TFlags = set of (rfFirstRowOfLine, rfLastRowOfLine);
    public
      Flags: TFlags;
      Index: Integer;
      Length: Integer;
      Line: Integer;
      Width: Integer;
    end;

    TRows = class(TList<TRow>)
    strict private
      FEditor: TCustomBCEditor;
      FMaxLength: Integer;
      FMaxLengthRow: Integer;
      FMaxWidth: Integer;
      FMaxWidthRow: Integer;
      function GetLine(ARow: Integer): Integer; inline;
      function GetMaxLength(): Integer;
      function GetMaxWidth(): Integer;
      function GetText(ARow: Integer): string; inline;
      procedure PutLine(ARow: Integer; AValue: Integer); inline;
    strict protected
      property Editor: TCustomBCEditor read FEditor;
    public
      procedure Add(const AFlags: TRow.TFlags; const ALine: Integer;
        const AIndex, ALength, AWidth: Integer); inline;
      procedure Clear();
      constructor Create(const AEditor: TCustomBCEditor);
      procedure Delete(ARow: Integer);
      procedure Insert(ARow: Integer;
        const AFlags: TRow.TFlags; const ALine: Integer;
        const AIndex, ALength, AWidth: Integer);
      property Line[Row: Integer]: Integer read GetLine write PutLine;
      property MaxLength: Integer read GetMaxLength;
      property MaxWidth: Integer read GetMaxWidth;
      property Text[Row: Integer]: string read GetText;
    end;

    TSearchResult = record
      BeginPosition: TBCEditorTextPosition;
      EndPosition: TBCEditorTextPosition;
    end;

  strict private const
    DefaultOptions = [eoAutoIndent, eoDragDropEditing];
    DefaultUndoOptions = [uoGroupUndo];
    UM_FREE_COMPLETIONPROPOSAL_POPUPWINDOW = WM_USER;
  strict private
    FActiveLine: TBCEditorActiveLine;
    FAllCodeFoldingRanges: TBCEditorCodeFolding.TAllRanges;
    FAltEnabled: Boolean;
    FAlwaysShowCaret: Boolean;
    FAlwaysShowCaretBeforePopup: Boolean;
    FBackgroundColor: TColor;
    FBookmarkList: TBCEditorMarkList;
    FBorderStyle: TBorderStyle;
    FCaret: TBCEditorCaret;
    FCaretCreated: Boolean;
    FCaretOffset: TPoint;
    FChainedEditor: TCustomBCEditor;
    FCodeFolding: TBCEditorCodeFolding;
    FCodeFoldingDelayTimer: TTimer;
    FCodeFoldingHintForm: TBCEditorCodeFoldingHintForm;
    FCodeFoldingRangeFromLine: array of TBCEditorCodeFolding.TRanges.TRange;
    FCodeFoldingRangeToLine: array of TBCEditorCodeFolding.TRanges.TRange;
    FCodeFoldingTreeLine: array of Boolean;
    FCommandDrop: Boolean;
    FCompletionProposal: TBCEditorCompletionProposal;
    FCompletionProposalPopupWindow: TBCEditorCompletionProposalPopupWindow;
    FCompletionProposalTimer: TTimer;
    FCurrentMatchingPair: TMatchingPairTokenResult;
    FCurrentMatchingPairMatch: TBCEditorHighlighter.TMatchingPairMatch;
    FDoubleClickTime: Cardinal;
    FDragBeginTextCaretPosition: TBCEditorTextPosition;
    FDrawMultiCarets: Boolean;
    FFontDummy: TFont;
    FForegroundColor: TColor;
    FHideSelection: Boolean;
    FHideSelectionBeforeSearch: Boolean;
    FHideScrollBars: Boolean;
    FHighlightedFoldRange: TBCEditorCodeFolding.TRanges.TRange;
    FHighlighter: TBCEditorHighlighter;
    FHookedCommandHandlers: TObjectList;
    FHorzTextPos: Integer;
    FHWheelAccumulator: Integer;
    FInternalBookmarkImage: TBCEditorInternalImage;
    FIsScrolling: Boolean;
    FItalicOffset: Byte;
    FItalicOffsetCache: array [AnsiChar] of Byte;
    FKeyboardHandler: TBCEditorKeyboardHandler;
    FKeyCommands: TBCEditorKeyCommands;
    FLastDblClick: Cardinal;
    FLastKey: Word;
    FLastLineNumberCount: Integer;
    FLastRow: Integer;
    FLastShiftState: TShiftState;
    FLastSortOrder: TBCEditorSortOrder;
    FLastTopLine: Integer;
    FLeftMargin: TBCEditorLeftMargin;
    FLeftMarginCharWidth: Integer;
    FLeftMarginWidth: Integer;
    FLineBreakSignWidth: Integer;
    FLineHeight: Integer;
    FLines: TBCEditorLines;
    FLineSpacing: Integer;
    FMarkList: TBCEditorMarkList;
    FMatchingPair: TBCEditorMatchingPair;
    FMatchingPairMatchStack: array of TMatchingPairTokenMatch;
    FMouseDownTextPosition: TBCEditorTextPosition;
    FMouseDownX: Integer;
    FMouseDownY: Integer;
    FMouseMoveScrollCursors: array [0 .. 7] of HCursor;
    FMouseMoveScrolling: Boolean;
    FMouseMoveScrollingPoint: TPoint;
    FMouseMoveScrollTimer: TTimer;
    FMouseOverURI: Boolean;
    FMultiCaretPosition: TBCEditorDisplayPosition;
    FMultiCarets: TMultiCarets;
    FMultiCaretTimer: TTimer;
    FOldMouseMovePoint: TPoint;
    FOnAfterBookmarkPlaced: TNotifyEvent;
    FOnAfterDeleteBookmark: TNotifyEvent;
    FOnAfterDeleteMark: TNotifyEvent;
    FOnAfterLinePaint: TBCEditorLinePaintEvent;
    FOnAfterMarkPanelPaint: TBCEditorMarkPanelPaintEvent;
    FOnAfterMarkPlaced: TNotifyEvent;
    FOnBeforeCompletionProposalExecute: TBCEditorCompletionProposalEvent;
    FOnBeforeDeleteMark: TBCEditorMarkEvent;
    FOnBeforeMarkPanelPaint: TBCEditorMarkPanelPaintEvent;
    FOnBeforeMarkPlaced: TBCEditorMarkEvent;
    FOnBeforeTokenInfoExecute: TBCEditorTokenInfoEvent;
    FOnCaretChanged: TBCEditorCaretChangedEvent;
    FOnChainCaretMoved: TNotifyEvent;
    FOnChainLinesCleared: TNotifyEvent;
    FOnChainLinesDeleted: TBCEditorLines.TChangeEvent;
    FOnChainLinesInserted: TBCEditorLines.TChangeEvent;
    FOnChainLinesUpdated: TBCEditorLines.TChangeEvent;
    FOnChange: TNotifyEvent;
    FOnCommandProcessed: TBCEditorProcessCommandEvent;
    FOnCompletionProposalCanceled: TNotifyEvent;
    FOnCompletionProposalSelected: TBCEditorCompletionProposalPopupWindowSelectedEvent;
    FOnContextHelp: TBCEditorContextHelpEvent;
    FOnCreateFileStream: TBCEditorCreateFileStreamEvent;
    FOnCustomLineColors: TBCEditorCustomLineColorsEvent;
    FOnCustomTokenAttribute: TBCEditorCustomTokenAttributeEvent;
    FOnDropFiles: TBCEditorDropFilesEvent;
    FOnKeyPressW: TBCEditorKeyPressWEvent;
    FOnLeftMarginClick: TBCEditorMarginClickEvent;
    FOnMarkPanelLinePaint: TBCEditorMarkPanelLinePaintEvent;
    FOnModified: TNotifyEvent;
    FOnPaint: TBCEditorPaintEvent;
    FOnProcessCommand: TBCEditorProcessCommandEvent;
    FOnProcessUserCommand: TBCEditorProcessCommandEvent;
    FOnReplaceText: TBCEditorReplaceEvent;
    FOnRightMarginMouseUp: TNotifyEvent;
    FOnScroll: TBCEditorScrollEvent;
    FOnSelectionChanged: TNotifyEvent;
    FOptions: TBCEditorOptions;
    FOriginalLines: TBCEditorLines;
    FPaintHelper: TBCEditorPaintHelper;
    FReplace: TBCEditorReplace;
    FRescanCodeFolding: Boolean;
    FRightMargin: TBCEditorRightMargin;
    FRightMarginMovePosition: Integer;
    FRows: TRows;
    FSaveSelectionMode: TBCEditorSelectionMode;
    FScroll: TBCEditorScroll;
    FScrollDeltaX: Integer;
    FScrollDeltaY: Integer;
    FScrollTimer: TTimer;
    FSearch: TBCEditorSearch;
    FSearchFindDialog: TFindDialog;
    FSearchReplaceDialog: TReplaceDialog;
    FSearchResults: TList<TSearchResult>;
    FSearchStatus: string;
    FSelectedCaseCycle: TBCEditorCase;
    FSelectedCaseText: string;
    FSelection: TBCEditorSelection;
    FSpecialChars: TBCEditorSpecialChars;
    FSpecialCharsText: string;
    FState: TState;
    FSyncEdit: TBCEditorSyncEdit;
    FTabSignWidth: Integer;
    FTabs: TBCEditorTabs;
    FTextEntryMode: TBCEditorTextEntryMode;
    FTextWidth: Integer;
    FTokenInfo: TBCEditorTokenInfo;
    FTokenInfoPopupWindow: TBCEditorTokenInfoPopupWindow;
    FTokenInfoTimer: TTimer;
    FTokenInfoTokenRect: TRect;
    FTopRow: Integer;
    FUpdateCount: Integer;
    FURIOpener: Boolean;
    FVisibleRows: Integer;
    FWantReturns: Boolean;
    FWheelScrollLines: UINT;
    FWindowProducedMessage: Boolean;
    FWordWrap: TBCEditorWordWrap;
    FWordWrapIndicator: TBitmap;
    procedure ActiveLineChanged(Sender: TObject);
    procedure AfterLinesUpdate(Sender: TObject);
    procedure BeforeLinesUpdate(Sender: TObject);
    procedure BookmarkListChange(Sender: TObject);
    procedure CaretChanged(ASender: TObject);
    procedure CheckIfAtMatchingKeywords;
    procedure ClearCodeFolding;
    function ClientAndRowToDisplayPosition(const X, ARow: Integer; const ALineText: string = ''): TBCEditorDisplayPosition;
    function ClientToDisplay(const X, Y: Integer): TBCEditorDisplayPosition; inline;
    function ClientToDisplayRow(const X, Y: Integer): Integer;
    function CodeFoldingCollapsableFoldRangeForLine(const ALine: Integer): TBCEditorCodeFolding.TRanges.TRange;
    function CodeFoldingFoldRangeForLineTo(const ALine: Integer): TBCEditorCodeFolding.TRanges.TRange;
    procedure CodeFoldingLinesDeleted(const ALine: Integer);
    procedure CodeFoldingOnChange(AEvent: TBCEditorCodeFoldingChanges);
    function CodeFoldingRangeForLine(const ALine: Integer): TBCEditorCodeFolding.TRanges.TRange;
    procedure CodeFoldingResetCaches;
    function CodeFoldingTreeEndForLine(const ALine: Integer): Boolean;
    function CodeFoldingTreeLineForLine(const ALine: Integer): Boolean;
    procedure CollapseCodeFoldingRange(const ARange: TBCEditorCodeFolding.TRanges.TRange);
    procedure CompletionProposalTimerHandler(EndLine: TObject);
    function ComputeIndentText(const IndentCount: Integer): string;
    procedure ComputeScroll(const APoint: TPoint);
    function ComputeTextColumns(const AToken: string; const AColumnIndex: Integer): Integer;
    function ComputeTokenWidth(const AText: string; const ALength: Integer; const AColumnIndex: Integer): Integer;
    procedure DeleteChar;
    procedure DeleteLastWordOrBeginningOfLine(const ACommand: TBCEditorCommand);
    procedure DeleteLine;
    procedure DeleteLineFromRows(const ALine: Integer);
    procedure DeleteWordOrEndOfLine(const ACommand: TBCEditorCommand);
    function DisplayToClient(ADisplayPosition: TBCEditorDisplayPosition): TPoint;
    function DisplayToText(const ADisplayPosition: TBCEditorDisplayPosition): TBCEditorTextPosition;
    procedure DoBackspace();
    procedure DoBlockComment;
    procedure DoChar(const AChar: Char);
    procedure DoCutToClipboard;
    procedure DoEditorBottom(const ACommand: TBCEditorCommand); inline;
    procedure DoEditorTop(const ACommand: TBCEditorCommand); inline;
    procedure DoEndKey(const ASelectionCommand: Boolean);
    procedure DoHomeKey(const ASelectionCommand: Boolean);
    procedure DoImeStr(AData: Pointer);
    procedure DoInsertText(const AText: string);
    procedure DoLeftMarginAutoSize;
    procedure DoLineBreak();
    procedure DoLineComment;
    function DoOnCodeFoldingHintClick(const AClient: TPoint): Boolean;
    procedure DoPageLeftOrRight(const ACommand: TBCEditorCommand);
    procedure DoPageTopOrBottom(const ACommand: TBCEditorCommand);
    procedure DoPageUpOrDown(const ACommand: TBCEditorCommand);
    procedure DoPasteFromClipboard;
    function DoReplaceText(): Integer;
    procedure DoScroll(const ACommand: TBCEditorCommand);
    function DoSearch(ABeginPosition, AEndPosition: TBCEditorTextPosition): Boolean;
    function DoSearchFind(const First: Boolean; const Action: TSearchFind): Boolean;
    procedure DoSearchFindClose(Sender: TObject);
    procedure DoSearchFindExecute(Sender: TObject);
    function DoSearchNext(APosition: TBCEditorTextPosition;
      out ASearchResult: TSearchResult; const WrapAround: Boolean = False): Boolean;
    function DoSearchPrevious(APosition: TBCEditorTextPosition;
      out ASearchResult: TSearchResult; const WrapAround: Boolean = False): Boolean;
    function DoSearchReplace(const Action: TSearchReplace): Boolean;
    procedure DoSearchReplaceExecute(Sender: TObject);
    procedure DoSearchReplaceFind(Sender: TObject);
    procedure DoSetBookmark(const ACommand: TBCEditorCommand; AData: Pointer);
    procedure DoShiftTabKey;
    procedure DoSyncEdit;
    procedure DoTabKey;
    procedure DoToggleBookmark;
    procedure DoToggleMark;
    procedure DoToggleSelectedCase(const ACommand: TBCEditorCommand);
    procedure DoTokenInfo;
    procedure DoWordLeft(const ACommand: TBCEditorCommand);
    procedure DoWordRight(const ACommand: TBCEditorCommand);
    procedure DrawCaret;
    procedure ExpandCodeFoldingRange(const ARange: TBCEditorCodeFolding.TRanges.TRange);
    function FindHookedCommandEvent(const AHookedCommandEvent: TBCEditorHookedCommandEvent): Integer;
    procedure FindWords(const AWord: string; AList: TList; ACaseSensitive: Boolean; AWholeWordsOnly: Boolean);
    procedure FontChanged(ASender: TObject);
    procedure FreeMultiCarets;
    function GetCanPaste: Boolean;
    function GetCanRedo: Boolean;
    function GetCanUndo: Boolean;
    function GetCaretPos(): TPoint;
    function GetCharAt(APos: TPoint): Char; inline;
    function GetCharWidth(): Integer; inline;
    function GetCommentAtTextPosition(const ATextPosition: TBCEditorTextPosition): string;
    function GetDisplayCaretPosition(): TBCEditorDisplayPosition; inline;
    function GetHighlighterAttributeAtRowColumn(const ATextPosition: TBCEditorTextPosition;
      var AToken: string; var ATokenType: TBCEditorRangeType; var AColumn: Integer;
      var AHighlighterAttribute: TBCEditorHighlighter.TAttribute): Boolean;
    function GetHookedCommandHandlersCount: Integer;
    function GetLeadingExpandedLength(const AStr: string; const ABorder: Integer = 0): Integer;
    function GetLeftMarginWidth: Integer;
    function GetLineIndentLevel(const ALine: Integer): Integer;
    function GetMarkBackgroundColor(const ALine: Integer): TColor;
    function GetMatchingToken(const ATextCaretPosition: TBCEditorTextPosition;
      var AMatchingPairMatch: TBCEditorHighlighter.TMatchingPairMatch): TMatchingPairTokenResult;
    function GetModified(): Boolean;
    function GetMouseMoveScrollCursorIndex: Integer;
    function GetMouseMoveScrollCursors(const AIndex: Integer): HCursor;
    function GetSearchResultCount: Integer;
    function GetSelectionAvailable(): Boolean;
    function GetSelectionBeginPosition(): TBCEditorTextPosition;
    function GetSelectionEndPosition(): TBCEditorTextPosition;
    function GetSelectionMode(): TBCEditorSelectionMode;
    function GetSelStart(): Integer;
    function GetSelText(): string;
    function GetText: string;
    function GetTextBetween(ATextBeginPosition, ATextEndPosition: TBCEditorTextPosition): string;
    function GetUndoOptions(): TBCEditorUndoOptions;
    function GetVisibleChars(const ARow: Integer; const ALineText: string = ''): Integer;
    function GetWordAt(ATextPos: TPoint): string; inline;
    function GetWordAtTextPosition(const ATextPosition: TBCEditorTextPosition): string;
    procedure InitCodeFolding;
    procedure InsertLine();
    procedure InsertLineIntoRows(const ALine: Integer; const ANewLine: Boolean); overload;
    function InsertLineIntoRows(const ALine: Integer; const ARow: Integer): Integer; overload;
    function IsCommentAtCaretPosition: Boolean;
    function IsKeywordAtPosition(const APosition: TBCEditorTextPosition;
      const APOpenKeyWord: PBoolean = nil; const AHighlightAfterToken: Boolean = True): Boolean;
    function IsKeywordAtPositionOrAfter(const APosition: TBCEditorTextPosition): Boolean;
    function IsMultiEditCaretFound(const ALine: Integer): Boolean;
    function IsTextPositionInSearchBlock(const ATextPosition: TBCEditorTextPosition): Boolean;
    function IsWordSelected: Boolean;
    function LeftSpaceCount(const AText: string; AWantTabs: Boolean = False): Integer;
    function LeftTrimLength(const AText: string): Integer;
    procedure MouseMoveScrollTimerHandler(ASender: TObject);
    procedure MoveCaretAndSelection(ABeforeTextPosition, AAfterTextPosition: TBCEditorTextPosition; const ASelectionCommand: Boolean);
    procedure MoveCaretHorizontally(const Cols: Integer; const SelectionCommand: Boolean);
    procedure MoveCaretVertically(const ARows: Integer; const SelectionCommand: Boolean);
    procedure MoveCharLeft;
    procedure MoveCharRight;
    procedure MoveLineDown;
    procedure MoveLineUp;
    procedure MultiCaretTimerHandler(ASender: TObject);
    function NextWordPosition(const ATextPosition: TBCEditorTextPosition): TBCEditorTextPosition; overload;
    procedure OnCodeFoldingDelayTimer(ASender: TObject);
    procedure OnTokenInfoTimer(ASender: TObject);
    procedure OpenLink(const AURI: string; ARangeType: TBCEditorRangeType);
    procedure PaintCaretBlock(ADisplayCaretPosition: TBCEditorDisplayPosition);
    function PreviousWordPosition(const ATextPosition: TBCEditorTextPosition): TBCEditorTextPosition; overload;
    procedure RemoveDuplicateMultiCarets;
    procedure ReplaceChanged(AEvent: TBCEditorReplaceChanges);
    function RescanHighlighterRangesFrom(const ALine: Integer): Integer;
    procedure RightMarginChanged(ASender: TObject);
    procedure ScrollChanged(ASender: TObject);
    procedure ScrollTimerHandler(ASender: TObject);
    procedure SearchChanged(AEvent: TBCEditorSearchEvent);
    procedure SelectionChanged(ASender: TObject);
    procedure SetActiveLine(const AValue: TBCEditorActiveLine);
    procedure SetBackgroundColor(const AValue: TColor);
    procedure SetBorderStyle(const AValue: TBorderStyle);
    procedure SetCaretPos(AValue: TPoint);
    procedure SetCodeFolding(const AValue: TBCEditorCodeFolding);
    procedure SetDefaultKeyCommands;
    procedure SetDisplayCaretPosition(const ADisplayCaretPosition: TBCEditorDisplayPosition);
    procedure SetForegroundColor(const AValue: TColor);
    procedure SetHorzTextPos(AValue: Integer);
    procedure SetKeyCommands(const AValue: TBCEditorKeyCommands);
    procedure SetLeftMargin(const AValue: TBCEditorLeftMargin);
    procedure SetModified(const AValue: Boolean);
    procedure SetMouseMoveScrollCursors(const AIndex: Integer; const AValue: HCursor);
    procedure SetOptions(const AValue: TBCEditorOptions);
    procedure SetRightMargin(const AValue: TBCEditorRightMargin);
    procedure SetScroll(const AValue: TBCEditorScroll);
    procedure SetSearch(const AValue: TBCEditorSearch);
    procedure SetSelectedWord;
    procedure SetSelection(const AValue: TBCEditorSelection);
    procedure SetSelectionBeginPosition(const AValue: TBCEditorTextPosition);
    procedure SetSelectionEndPosition(const AValue: TBCEditorTextPosition);
    procedure SetSelectionMode(const AValue: TBCEditorSelectionMode);
    procedure SetSelLength(const AValue: Integer); inline;
    procedure SetSelStart(const AValue: Integer); inline;
    procedure SetSelText(const AValue: string); inline;
    procedure SetSpecialChars(const AValue: TBCEditorSpecialChars);
    procedure SetSyncEdit(const AValue: TBCEditorSyncEdit);
    procedure SetTabs(const AValue: TBCEditorTabs);
    procedure SetText(const AValue: string); inline;
    procedure SetTextEntryMode(const AValue: TBCEditorTextEntryMode);
    procedure SetTokenInfo(const AValue: TBCEditorTokenInfo);
    procedure SetTopRow(const AValue: Integer);
    procedure SetUndoOptions(AOptions: TBCEditorUndoOptions);
    procedure SetWordBlock(const ATextPosition: TBCEditorTextPosition);
    procedure SetWordWrap(const AValue: TBCEditorWordWrap);
    function ShortCutPressed: Boolean;
    procedure SizeOrFontChanged(const AFontChanged: Boolean);
    procedure SpecialCharsChanged(ASender: TObject);
    procedure SwapInt(var ALeft: Integer; var ARight: Integer);
    procedure SyncEditChanged(ASender: TObject);
    procedure TabsChanged(ASender: TObject);
    procedure UMFreeCompletionProposalPopupWindow(var AMessage: TMessage); message UM_FREE_COMPLETIONPROPOSAL_POPUPWINDOW;
    procedure UpdateFoldRanges(const ACurrentLine: Integer; const ALineCount: Integer); overload;
    procedure UpdateFoldRanges(AFoldRanges: TBCEditorCodeFolding.TRanges; const ALineCount: Integer); overload;
    procedure UpdateRows(const ALine: Integer);
    procedure UpdateScrollBars(const AUpdateRows: Boolean = True);
    procedure UpdateWordWrap(const AValue: Boolean);
    procedure WMCaptureChanged(var AMessage: TMessage); message WM_CAPTURECHANGED;
    procedure WMChar(var AMessage: TWMChar); message WM_CHAR;
    procedure WMClear(var AMessage: TMessage); message WM_CLEAR;
    procedure WMCopy(var AMessage: TMessage); message WM_COPY;
    procedure WMCut(var AMessage: TMessage); message WM_CUT;
    procedure WMDropFiles(var AMessage: TMessage); message WM_DROPFILES;
    procedure WMEraseBkgnd(var AMessage: TMessage); message WM_ERASEBKGND;
    procedure WMGetDlgCode(var AMessage: TWMGetDlgCode); message WM_GETDLGCODE;
    procedure WMGetText(var AMessage: TWMGetText); message WM_GETTEXT;
    procedure WMGetTextLength(var AMessage: TWMGetTextLength); message WM_GETTEXTLENGTH;
    procedure WMHScroll(var AMessage: TWMScroll); message WM_HSCROLL;
    procedure WMIMEChar(var AMessage: TMessage); message WM_IME_CHAR;
    procedure WMIMEComposition(var AMessage: TMessage); message WM_IME_COMPOSITION;
    procedure WMIMENotify(var AMessage: TMessage); message WM_IME_NOTIFY;
    procedure WMKillFocus(var AMessage: TWMKillFocus); message WM_KILLFOCUS;
    procedure WMMouseHWheel(var AMessage: TWMMouseWheel); message WM_MOUSEHWHEEL;
    procedure WMNCPaint(var AMessage: TMessage); message WM_NCPAINT;
    procedure WMPaint(var AMessage: TWMPaint); message WM_PAINT;
    procedure WMPaste(var AMessage: TMessage); message WM_PASTE;
    procedure WMSetCursor(var AMessage: TWMSetCursor); message WM_SETCURSOR;
    procedure WMSetFocus(var AMessage: TWMSetFocus); message WM_SETFOCUS;
    procedure WMSetText(var AMessage: TWMSetText); message WM_SETTEXT;
    procedure WMSettingChange(var AMessage: TWMSettingChange); message WM_SETTINGCHANGE;
    procedure WMUndo(var AMessage: TMessage); message WM_UNDO;
    procedure WMVScroll(var AMessage: TWMScroll); message WM_VSCROLL;
    procedure WordWrapChanged(ASender: TObject);
    function WordWrapWidth: Integer;
  protected
    procedure AddCaret(const ADisplayPosition: TBCEditorDisplayPosition);
    function CaretInView: Boolean;
    procedure CaretMoved(ASender: TObject);
    procedure ChainLinesCaretChanged(ASender: TObject);
    procedure ChainLinesCleared(ASender: TObject);
    procedure ChainLinesDeleted(ASender: TObject; const ALine: Integer);
    procedure ChainLinesInserted(ASender: TObject; const ALine: Integer);
    procedure ChainLinesUpdated(ASender: TObject; const ALine: Integer);
    procedure ChangeScale(M, D: Integer); override;
    procedure ClearBookmarks;
    procedure ClearMarks;
    procedure ClearMatchingPair;
    procedure ClearUndo;
    procedure CollapseCodeFoldingLevel(const AFirstLevel: Integer; const ALastLevel: Integer);
    function CollapseCodeFoldingLines(const AFirstLine: Integer = -1; const ALastLine: Integer = -1): Integer;
    function CreateLines(): BCEditor.Lines.TBCEditorLines;
    procedure CreateParams(var AParams: TCreateParams); override;
    procedure CreateWnd; override;
    procedure DblClick; override;
    function DeleteBookmark(const ALine: Integer; const AIndex: Integer): Boolean; overload;
    procedure DeleteBookmark(ABookmark: TBCEditorMark); overload;
    procedure DeleteMark(AMark: TBCEditorMark);
    procedure DestroyWnd; override;
    procedure DoBlockIndent(const ACommand: TBCEditorCommand);
    procedure DoCompletionProposal(); virtual;
    procedure DoCopyToClipboard(const AText: string);
    procedure DoKeyPressW(var AMessage: TWMKey);
    function DoMouseWheelDown(Shift: TShiftState; MousePos: TPoint): Boolean; override;
    function DoMouseWheelUp(Shift: TShiftState; MousePos: TPoint): Boolean; override;
    procedure DoOnCommandProcessed(ACommand: TBCEditorCommand; const AChar: Char; AData: Pointer);
    procedure DoOnLeftMarginClick(AButton: TMouseButton; AShift: TShiftState; X, Y: Integer);
    procedure DoOnPaint;
    procedure DoOnProcessCommand(var ACommand: TBCEditorCommand; var AChar: Char; AData: Pointer); virtual;
    function DoOnReplaceText(const APattern, AReplaceText: string;
      APosition: TBCEditorTextPosition): TBCEditorReplaceAction;
    procedure DoOnSearchMapClick(AButton: TMouseButton; X, Y: Integer);
    function DoSearchMatchNotFoundWrapAroundDialog: Boolean; virtual;
    procedure DoSearchStringNotFoundDialog; virtual;
    procedure DoTripleClick;
    procedure DragCanceled; override;
    procedure DragOver(ASource: TObject; X, Y: Integer; AState: TDragState; var AAccept: Boolean); override;
    procedure ExpandCodeFoldingLevel(const AFirstLevel: Integer; const ALastLevel: Integer);
    function ExpandCodeFoldingLines(const AFirstLine: Integer = -1; const ALastLine: Integer = -1): Integer;
    procedure FillRect(const ARect: TRect); inline;
    function FindFirst(): Boolean;
    function FindNext(const AHandleNotFound: Boolean = True): Boolean;
    function FindPrevious(const AHandleNotFound: Boolean = True): Boolean;
    procedure FreeHintForm(var AForm: TBCEditorCodeFoldingHintForm);
    procedure FreeTokenInfoPopupWindow;
    function GetBookmark(const AIndex: Integer; var ATextPosition: TBCEditorTextPosition): Boolean;
    function GetColorsFileName(const AFileName: string): string;
    function GetReadOnly: Boolean; virtual;
    function GetRows(): TRows;
    function GetSelLength: Integer;
    function GetTextPositionOfMouse(out ATextPosition: TBCEditorTextPosition): Boolean;
    procedure GotoBookmark(const AIndex: Integer);
    procedure GotoLineAndCenter(const ALine: Integer; const AChar: Integer = 1);
    procedure GotoNextBookmark;
    procedure GotoPreviousBookmark;
    procedure HideCaret;
    function IsCommentChar(const AChar: Char): Boolean;
    function IsEmptyChar(const AChar: Char): Boolean; inline;
    function IsWordBreakChar(const AChar: Char): Boolean; inline;
    procedure KeyDown(var AKey: Word; AShift: TShiftState); override;
    procedure KeyPressW(var AKey: Char);
    procedure KeyUp(var AKey: Word; AShift: TShiftState); override;
    procedure LeftMarginChanged(ASender: TObject);
    procedure LineDeleted(ASender: TObject; const ALine: Integer);
    procedure LineInserted(ASender: TObject; const ALine: Integer);
    procedure LineUpdated(ASender: TObject; const ALine: Integer); virtual;
    procedure LinesCleared(ASender: TObject);
    procedure LinesHookChanged;
    procedure MarkListChange(ASender: TObject);
    procedure MouseDown(AButton: TMouseButton; AShift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(AShift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(AButton: TMouseButton; AShift: TShiftState; X, Y: Integer); override;
    procedure NotifyHookedCommandHandlers(AAfterProcessing: Boolean; var ACommand: TBCEditorCommand; var AChar: Char; AData: Pointer);
    procedure Paint; override;
    procedure PaintCodeFolding(AClipRect: TRect; AFirstRow, ALastRow: Integer);
    procedure PaintCodeFoldingCollapsedLine(AFoldRange: TBCEditorCodeFolding.TRanges.TRange; const ALineRect: TRect);
    procedure PaintCodeFoldingCollapseMark(AFoldRange: TBCEditorCodeFolding.TRanges.TRange;
      const ATokenPosition, ATokenLength, ALine: Integer; ALineRect: TRect);
    procedure PaintCodeFoldingLine(AClipRect: TRect; ALine: Integer);
    procedure PaintGuides(const AFirstRow, ALastRow: Integer);
    procedure PaintLeftMargin(const AClipRect: TRect; const AFirstRow, ALastTextRow, ALastRow: Integer);
    procedure PaintMouseMoveScrollPoint;
    procedure PaintRightMargin(AClipRect: TRect);
    procedure PaintRightMarginMove;
    procedure PaintSearchMap(AClipRect: TRect);
    procedure PaintSyncItems;
    procedure PaintTextLines(AClipRect: TRect; const AFirstRow, ALastRow: Integer);
    procedure ReadState(Reader: TReader); override;
    procedure RescanCodeFoldingRanges;
    procedure ResetCaret;
    procedure Resize(); override;
    procedure ScanCodeFoldingRanges; virtual;
    procedure ScanMatchingPair();
    procedure SetAlwaysShowCaret(const AValue: Boolean);
    procedure SetBookmark(const AIndex: Integer; const ATextPosition: TBCEditorTextPosition);
    procedure SetCaretAndSelection(ACaretPosition, ASelBeginPosition,
      ASelEndPosition: TBCEditorTextPosition);
    procedure SetLineColor(const ALine: Integer; const AForegroundColor, ABackgroundColor: TColor);
    procedure SetLineColorToDefault(const ALine: Integer);
    procedure SetMark(const AIndex: Integer; const ATextPosition: TBCEditorTextPosition; const AImageIndex: Integer;
      const AColor: TColor = clNone);
    procedure SetName(const AValue: TComponentName); override;
    procedure SetHideScrollBars(AValue: Boolean); virtual;
    procedure SetHideSelection(AValue: Boolean); virtual;
    procedure SetOption(const AOption: TBCEditorOption; const AEnabled: Boolean);
    procedure SetReadOnly(const AValue: Boolean); virtual;
    procedure SetUndoOption(const AOption: TBCEditorUndoOption; const AEnabled: Boolean);
    procedure SetUpdateState(AUpdating: Boolean); virtual;
    procedure SetWantReturns(const AValue: Boolean);
    procedure ShowCaret;
    procedure ScrollToCaret(ACenterVertical: Boolean = False; AScrollAlways: Boolean = False);
    function TextToDisplay(const ATextPosition: TBCEditorTextPosition): TBCEditorDisplayPosition;
    procedure ToggleBookmark(const AIndex: Integer = -1);
    procedure UpdateCaret();
    procedure UpdateMouseCursor;
    function WordBegin(const ATextPosition: TBCEditorTextPosition): TBCEditorTextPosition; overload;
    function WordEnd(): TBCEditorTextPosition; overload; inline;
    function WordEnd(const ATextPosition: TBCEditorTextPosition): TBCEditorTextPosition; overload;
    property AllCodeFoldingRanges: TBCEditorCodeFolding.TAllRanges read FAllCodeFoldingRanges;
    property AlwaysShowCaret: Boolean read FAlwaysShowCaret write SetAlwaysShowCaret;
    property HideScrollBars: Boolean read FHideScrollBars write SetHideScrollBars default True;
    property HideSelection: Boolean read FHideSelection write SetHideSelection default True;
    property HorzTextPos: Integer read FHorzTextPos write SetHorzTextPos;
    property LeftMarginWidth: Integer read FLeftMarginWidth;
    property OnAfterBookmarkPlaced: TNotifyEvent read FOnAfterBookmarkPlaced write FOnAfterBookmarkPlaced;
    property OnAfterDeleteBookmark: TNotifyEvent read FOnAfterDeleteBookmark write FOnAfterDeleteBookmark;
    property OnAfterDeleteMark: TNotifyEvent read FOnAfterDeleteMark write FOnAfterDeleteMark;
    property OnAfterLinePaint: TBCEditorLinePaintEvent read FOnAfterLinePaint write FOnAfterLinePaint;
    property OnAfterMarkPanelPaint: TBCEditorMarkPanelPaintEvent read FOnAfterMarkPanelPaint write FOnAfterMarkPanelPaint;
    property OnAfterMarkPlaced: TNotifyEvent read FOnAfterMarkPlaced write FOnAfterMarkPlaced;
    property OnBeforeCompletionProposalExecute: TBCEditorCompletionProposalEvent read FOnBeforeCompletionProposalExecute write FOnBeforeCompletionProposalExecute;
    property OnBeforeDeleteMark: TBCEditorMarkEvent read FOnBeforeDeleteMark write FOnBeforeDeleteMark;
    property OnBeforeMarkPanelPaint: TBCEditorMarkPanelPaintEvent read FOnBeforeMarkPanelPaint write FOnBeforeMarkPanelPaint;
    property OnBeforeMarkPlaced: TBCEditorMarkEvent read FOnBeforeMarkPlaced write FOnBeforeMarkPlaced;
    property OnBeforeTokenInfoExecute: TBCEditorTokenInfoEvent read FOnBeforeTokenInfoExecute write FOnBeforeTokenInfoExecute;
    property OnCaretChanged: TBCEditorCaretChangedEvent read FOnCaretChanged write FOnCaretChanged;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnCommandProcessed: TBCEditorProcessCommandEvent read FOnCommandProcessed write FOnCommandProcessed;
    property OnCompletionProposalCanceled: TNotifyEvent read FOnCompletionProposalCanceled write FOnCompletionProposalCanceled;
    property OnCompletionProposalSelected: TBCEditorCompletionProposalPopupWindowSelectedEvent read FOnCompletionProposalSelected write FOnCompletionProposalSelected;
    property OnContextHelp: TBCEditorContextHelpEvent read FOnContextHelp write FOnContextHelp;
    property OnCreateFileStream: TBCEditorCreateFileStreamEvent read FOnCreateFileStream write FOnCreateFileStream;
    property OnCustomLineColors: TBCEditorCustomLineColorsEvent read FOnCustomLineColors write FOnCustomLineColors;
    property OnCustomTokenAttribute: TBCEditorCustomTokenAttributeEvent read FOnCustomTokenAttribute write FOnCustomTokenAttribute;
    property OnDropFiles: TBCEditorDropFilesEvent read FOnDropFiles write FOnDropFiles;
    property OnKeyPress: TBCEditorKeyPressWEvent read FOnKeyPressW write FOnKeyPressW;
    property OnLeftMarginClick: TBCEditorMarginClickEvent read FOnLeftMarginClick write FOnLeftMarginClick;
    property OnMarkPanelLinePaint: TBCEditorMarkPanelLinePaintEvent read FOnMarkPanelLinePaint write FOnMarkPanelLinePaint;
    property OnModified: TNotifyEvent read FOnModified write FOnModified;
    property OnPaint: TBCEditorPaintEvent read FOnPaint write FOnPaint;
    property OnProcessCommand: TBCEditorProcessCommandEvent read FOnProcessCommand write FOnProcessCommand;
    property OnProcessUserCommand: TBCEditorProcessCommandEvent read FOnProcessUserCommand write FOnProcessUserCommand;
    property OnReplaceText: TBCEditorReplaceEvent read FOnReplaceText write FOnReplaceText;
    property OnRightMarginMouseUp: TNotifyEvent read FOnRightMarginMouseUp write FOnRightMarginMouseUp;
    property OnScroll: TBCEditorScrollEvent read FOnScroll write FOnScroll;
    property OnSelectionChanged: TNotifyEvent read FOnSelectionChanged write FOnSelectionChanged;
    property Options: TBCEditorOptions read FOptions write SetOptions default DefaultOptions;
    property Rows: TRows read GetRows;
    property TextWidth: Integer read FTextWidth;
    property TopRow: Integer read FTopRow write SetTopRow;
    property UndoOptions: TBCEditorUndoOptions read GetUndoOptions write SetUndoOptions default DefaultUndoOptions;
    property VisibleRows: Integer read FVisibleRows;
    property WordWrap: TBCEditorWordWrap read FWordWrap write SetWordWrap;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure AddHighlighterKeywords(AStringList: TStrings);
    procedure AddKeyCommand(ACommand: TBCEditorCommand; AShift: TShiftState; AKey: Word;
      ASecondaryShift: TShiftState = []; ASecondaryKey: Word = 0);
    procedure AddKeyDownHandler(AHandler: TKeyEvent);
    procedure AddKeyPressHandler(AHandler: TBCEditorKeyPressWEvent);
    procedure AddKeyUpHandler(AHandler: TKeyEvent);
    procedure AddMouseCursorHandler(AHandler: TBCEditorMouseCursorEvent);
    procedure AddMouseDownHandler(AHandler: TMouseEvent);
    procedure AddMouseUpHandler(AHandler: TMouseEvent);
    procedure AddMultipleCarets(const ADisplayPosition: TBCEditorDisplayPosition);
    procedure Assign(ASource: TPersistent); override;
    procedure BeginUndoBlock();
    procedure BeginUpdate();
    procedure ChainEditor(AEditor: TCustomBCEditor);
    procedure Clear;
    function ClientToText(const X, Y: Integer): TPoint;
    function CharAtCursor(): Char; deprecated 'Use CharAt[CaretPos]'; // 2017-04-05
    procedure CommandProcessor(ACommand: TBCEditorCommand; AChar: Char; AData: Pointer);
    procedure CopyToClipboard;
    function CreateFileStream(const AFileName: string): TStream; virtual;
    procedure CutToClipboard;
    procedure DeleteWhitespace;
    procedure DoRedo(); inline; deprecated 'Use Redo()'; // 2017-02-12
    procedure DoUndo(); inline; deprecated 'Use Undo()'; // 2017-02-12
    procedure DragDrop(ASource: TObject; X, Y: Integer); override;
    procedure EndUndoBlock();
    procedure EndUpdate();
    function ExecuteAction(Action: TBasicAction): Boolean; override;
    procedure ExecuteCommand(ACommand: TBCEditorCommand; AChar: Char; AData: Pointer); virtual;
    procedure ExportToHTML(const AFileName: string; const ACharSet: string = ''; AEncoding: TEncoding = nil); overload;
    procedure ExportToHTML(AStream: TStream; const ACharSet: string = ''; AEncoding: TEncoding = nil); overload;
    procedure FindAll;
    function GetHighlighterFileName(const AFileName: string): string;
    function GetWordAtPixels(const X, Y: Integer): string; deprecated 'Use WordAt[ClientToText()]'; // 2017-03-16
    procedure HookEditorLines(ALines: TBCEditorLines; AUndo, ARedo: TBCEditorLines.TUndoList);
    procedure LoadFromFile(const AFileName: string; AEncoding: TEncoding = nil); deprecated 'Use Lines.LoadFromFile'; // 2017-03-10
    procedure LoadFromStream(AStream: TStream; AEncoding: TEncoding = nil); deprecated 'Use Lines.LoadFromStream'; // 2017-03-10
    procedure Notification(AComponent: TComponent; AOperation: TOperation); override;
    procedure PasteFromClipboard();
    function PixelsToTextPosition(const X, Y: Integer): TBCEditorTextPosition; deprecated 'Use ClientToText'; // 2017-03-13
    procedure Redo(); inline;
    procedure RegisterCommandHandler(const AHookedCommandEvent: TBCEditorHookedCommandEvent; AHandlerData: Pointer);
    procedure RemoveChainedEditor;
    procedure RemoveKeyDownHandler(AHandler: TKeyEvent);
    procedure RemoveKeyPressHandler(AHandler: TBCEditorKeyPressWEvent);
    procedure RemoveKeyUpHandler(AHandler: TKeyEvent);
    procedure RemoveMouseCursorHandler(AHandler: TBCEditorMouseCursorEvent);
    procedure RemoveMouseDownHandler(AHandler: TMouseEvent);
    procedure RemoveMouseUpHandler(AHandler: TMouseEvent);
    function ReplaceText(): Integer;
    procedure SaveToFile(const AFileName: string; AEncoding: TEncoding = nil);
    procedure SaveToStream(AStream: TStream; AEncoding: TEncoding = nil);
    function SearchStatus: string;
    procedure SelectAll;
    function SelectedText(): string; deprecated 'Use SelText'; // 2017-03-16
    procedure Sort(const ASortOrder: TBCEditorSortOrder = soAsc; const ACaseSensitive: Boolean = False);
    function SplitTextIntoWords(AStringList: TStrings; const ACaseSensitive: Boolean): string;
    function TextCaretPosition(): TBCEditorTextPosition; deprecated 'Use CaretPos'; // 2017-02-12
    procedure ToggleSelectedCase(const ACase: TBCEditorCase = cNone);
    function TranslateKeyCode(const ACode: Word; const AShift: TShiftState; var AData: Pointer): TBCEditorCommand;
    procedure Undo(); inline;
    procedure UnhookEditorLines;
    function UpdateAction(Action: TBasicAction): Boolean; override;
    procedure UnregisterCommandHandler(AHookedCommandEvent: TBCEditorHookedCommandEvent);
    procedure WndProc(var AMessage: TMessage); override;
    function WordAtCursor(): string; deprecated 'Use WordAt[CaretPos]'; // 2017-03-13
    function WordAtMouse(): string; deprecated 'Use WordAt[ClientToText()]'; // 2017-03-13
    property ActiveLine: TBCEditorActiveLine read FActiveLine write SetActiveLine;
    property BackgroundColor: TColor read FBackgroundColor write SetBackgroundColor default clWindow;
    property Bookmarks: TBCEditorMarkList read FBookmarkList;
    property BorderStyle: TBorderStyle read FBorderStyle write SetBorderStyle default bsSingle;
    property CanPaste: Boolean read GetCanPaste;
    property CanRedo: Boolean read GetCanRedo;
    property CanUndo: Boolean read GetCanUndo;
    property Caret: TBCEditorCaret read FCaret write FCaret;
    property CaretPos: TPoint read GetCaretPos write SetCaretPos;
    property CharAt[Pos: TPoint]: Char read GetCharAt;
    property CharWidth: Integer read GetCharWidth;
    property CodeFolding: TBCEditorCodeFolding read FCodeFolding write SetCodeFolding;
    property CompletionProposal: TBCEditorCompletionProposal read FCompletionProposal write FCompletionProposal;
    property Cursor default crIBeam;
    property DisplayCaretPosition: TBCEditorDisplayPosition read GetDisplayCaretPosition write SetDisplayCaretPosition;
    property ForegroundColor: TColor read FForegroundColor write SetForegroundColor default clWindowText;
    property Highlighter: TBCEditorHighlighter read FHighlighter;
    property IsScrolling: Boolean read FIsScrolling;
    property KeyCommands: TBCEditorKeyCommands read FKeyCommands write SetKeyCommands stored False;
    property LeftMargin: TBCEditorLeftMargin read FLeftMargin write SetLeftMargin;
    property LineHeight: Integer read FLineHeight;
    property Lines: TBCEditorLines read FLines;
    property LineSpacing: Integer read FLineSpacing write FLineSpacing default 0;
    property Marks: TBCEditorMarkList read FMarkList;
    property MatchingPair: TBCEditorMatchingPair read FMatchingPair write FMatchingPair;
    property Modified: Boolean read GetModified write SetModified;
    property MouseMoveScrollCursors[const AIndex: Integer]: HCursor read GetMouseMoveScrollCursors write SetMouseMoveScrollCursors;
    property ParentColor default False;
    property ParentFont default False;
    property ReadOnly: Boolean read GetReadOnly write SetReadOnly default False;
    property Replace: TBCEditorReplace read FReplace write FReplace;
    property RightMargin: TBCEditorRightMargin read FRightMargin write SetRightMargin;
    property Scroll: TBCEditorScroll read FScroll write SetScroll;
    property Search: TBCEditorSearch read FSearch write SetSearch;
    property SearchResultCount: Integer read GetSearchResultCount;
    property Selection: TBCEditorSelection read FSelection write SetSelection;
    property SelectionAvailable: Boolean read GetSelectionAvailable;
    property SelectionBeginPosition: TBCEditorTextPosition read GetSelectionBeginPosition write SetSelectionBeginPosition;
    property SelectionEndPosition: TBCEditorTextPosition read GetSelectionEndPosition write SetSelectionEndPosition;
    property SelectionMode: TBCEditorSelectionMode read GetSelectionMode write SetSelectionMode;
    property SelLength: Integer read GetSelLength write SetSelLength;
    property SelStart: Integer read GetSelStart write SetSelStart; // 0-based
    property SelText: string read GetSelText write SetSelText;
    property SpecialChars: TBCEditorSpecialChars read FSpecialChars write SetSpecialChars;
    property State: TState read FState;
    property SyncEdit: TBCEditorSyncEdit read FSyncEdit write SetSyncEdit;
    property Tabs: TBCEditorTabs read FTabs write SetTabs;
    property TabStop default True;
    property Text: string read GetText write SetText;
    property TextBetween[ATextBeginPosition, ATextEndPosition: TBCEditorTextPosition]: string read GetTextBetween;
    property TextEntryMode: TBCEditorTextEntryMode read FTextEntryMode write SetTextEntryMode default temInsert;
    property TokenInfo: TBCEditorTokenInfo read FTokenInfo write SetTokenInfo;
    property URIOpener: Boolean read FURIOpener write FURIOpener;
    property WantReturns: Boolean read FWantReturns write SetWantReturns default True;
    property WordAt[ATextPos: TPoint]: string read GetWordAt;
    property UpdateCount: Integer read FUpdateCount;
  end;

  TBCEditor = class(TCustomBCEditor)
  public
    property AlwaysShowCaret;
    property Canvas;
  published
    property ActiveLine;
    property Align;
    property Anchors;
    property BorderStyle;
    property Caret;
    property CodeFolding;
    property CompletionProposal;
    property Constraints;
    property Ctl3D;
    property Cursor;
    property Enabled;
    property Font;
    property Height;
    property HideScrollBars;
    property HideSelection;
    property Highlighter;
    property ImeMode;
    property ImeName;
    property KeyCommands;
    property LeftMargin;
    property Lines;
    property LineSpacing;
    property MatchingPair;
    property Name;
    property OnAfterBookmarkPlaced;
    property OnAfterDeleteBookmark;
    property OnAfterDeleteMark;
    property OnAfterLinePaint;
    property OnAfterMarkPanelPaint;
    property OnAfterMarkPlaced;
    property OnBeforeCompletionProposalExecute;
    property OnBeforeDeleteMark;
    property OnBeforeMarkPanelPaint;
    property OnBeforeMarkPlaced;
    property OnBeforeTokenInfoExecute;
    property OnCaretChanged;
    property OnChange;
    property OnClick;
    property OnCommandProcessed;
    property OnCompletionProposalCanceled;
    property OnCompletionProposalSelected;
    property OnContextHelp;
    property OnContextPopup;
    property OnCreateFileStream;
    property OnCustomLineColors;
    property OnCustomTokenAttribute;
    property OnDblClick;
    property OnDragDrop;
    property OnDragOver;
    property OnDropFiles;
    property OnEndDock;
    property OnEndDrag;
    property OnEnter;
    property OnExit;
    property OnKeyDown;
    property OnKeyPress;
    property OnKeyUp;
    property OnLeftMarginClick;
    property OnMarkPanelLinePaint;
    property OnModified;
    property OnMouseDown;
    property OnMouseMove;
    property OnMouseUp;
    property OnMouseWheel;
    property OnMouseWheelDown;
    property OnMouseWheelUp;
    property OnPaint;
    property OnProcessCommand;
    property OnProcessUserCommand;
    property OnReplaceText;
    property OnRightMarginMouseUp;
    property OnScroll;
    property OnSelectionChanged;
    property OnStartDock;
    property OnStartDrag;
    property Options;
    property ParentColor;
    property ParentCtl3D;
    property ParentFont;
    property ParentShowHint;
    property PopupMenu;
    property ReadOnly;
    property Replace;
    property RightMargin;
    property Scroll;
    property Search;
    property Selection;
    property ShowHint;
    property SpecialChars;
    property SyncEdit;
    property TabOrder;
    property Tabs;
    property TabStop;
    property Tag;
    property TextEntryMode;
    property TokenInfo;
    property UndoOptions;
    property Visible;
    property WantReturns;
    property Width;
    property WordWrap;
  end;

  EBCEditorBaseException = class(Exception);

implementation {***************************************************************}

{$R BCEditor.res}

uses
  ShellAPI, Imm,
  Math, Types, Character, RegularExpressions,
  Clipbrd, Menus,
  BCEditor.Language, BCEditor.Export.HTML, Vcl.Themes, BCEditor.StyleHooks;

resourcestring
  SBCEditorLineIsNotVisible = 'Line is not visible';

type
  TBCEditorAccessWinControl = class(TWinControl);

var
  GScrollHintWindow: THintWindow;
  GRightMarginHintWindow: THintWindow;

function DisplayPosition(const AColumn: Integer; const ARow: Integer): TBCEditorDisplayPosition;
begin
  Result.Column := AColumn;
  Result.Row := ARow;
end;

function GetScrollHint: THintWindow;
begin
  if not Assigned(GScrollHintWindow) then
  begin
    GScrollHintWindow := THintWindow.Create(Application);
    GScrollHintWindow.DoubleBuffered := True;
  end;
  Result := GScrollHintWindow;
end;

function GetRightMarginHint: THintWindow;
begin
  if not Assigned(GRightMarginHintWindow) then
  begin
    GRightMarginHintWindow := THintWindow.Create(Application);
    GRightMarginHintWindow.DoubleBuffered := True;
  end;
  Result := GRightMarginHintWindow;
end;

function IsCombiningDiacriticalMark(const AChar: Char): Boolean;
begin
  case Word(AChar) of
    $0300..$036F, $1DC0..$1DFF, $20D0..$20FF:
      Result := True
  else
    Result := False;
  end;
end;

function MessageDialog(const AMessage: string; ADlgType: TMsgDlgType; AButtons: TMsgDlgButtons): Integer;
begin
  with CreateMessageDialog(AMessage, ADlgType, AButtons) do
  try
    HelpContext := 0;
    HelpFile := '';
    Position := poMainFormCenter;
    Result := ShowModal;
  finally
    Free;
  end;
end;

function MiddleColor(AColor1, AColor2: TColor): TColor;
var
  LBlue: Byte;
  LBlue1: Byte;
  LBlue2: Byte;
  LGreen: Byte;
  LGreen1: Byte;
  LGreen2: Byte;
  LRed: Byte;
  LRed1: Byte;
  LRed2: Byte;
begin
  LRed1 := GetRValue(AColor1);
  LRed2 := GetRValue(AColor2);
  LGreen1 := GetRValue(AColor1);
  LGreen2 := GetRValue(AColor2);
  LBlue1 := GetRValue(AColor1);
  LBlue2 := GetRValue(AColor2);

  LRed := (LRed1 + LRed2) div 2;
  LGreen := (LGreen1 + LGreen2) div 2;
  LBlue := (LBlue1 + LBlue2) div 2;

  Result := RGB(LRed, LGreen, LBlue);
end;

{ TCustomBCEditor.TMultiCarets ************************************************}

function TCustomBCEditor.TMultiCarets.GetColumn(AIndex: Integer): Integer;
begin
  Result := List[AIndex].Column;
end;

function TCustomBCEditor.TMultiCarets.GetRow(AIndex: Integer): Integer;
begin
  Result := List[AIndex].Row;
end;

procedure TCustomBCEditor.TMultiCarets.PutColumn(AIndex: Integer; AValue: Integer);
begin
  List[AIndex].Column := AValue;
end;

procedure TCustomBCEditor.TMultiCarets.PutRow(AIndex: Integer; AValue: Integer);
begin
  List[AIndex].Row := AValue;
end;

{ TBCCustomEditor.TRows *******************************************************}

procedure TCustomBCEditor.TRows.Add(const AFlags: TRow.TFlags;
  const ALine: Integer; const AIndex, ALength, AWidth: Integer);
begin
  Insert(Count, AFlags, ALine, AIndex, ALength, AWidth);
end;

procedure TCustomBCEditor.TRows.Clear();
begin
  inherited;

  FMaxLength := -1;
  FMaxLengthRow := -1;
end;

constructor TCustomBCEditor.TRows.Create(const AEditor: TCustomBCEditor);
begin
  inherited Create();

  FEditor := AEditor;

  FMaxLength := -1;
  FMaxLengthRow := -1;
end;

procedure TCustomBCEditor.TRows.Delete(ARow: Integer);
begin
  inherited;

  if (FMaxLengthRow = ARow) then
  begin
    FMaxLength := -1;
    FMaxLengthRow := -1;
  end
  else if (FMaxLengthRow > ARow) then
    Dec(FMaxLengthRow);
  if (FMaxWidthRow = ARow) then
  begin
    FMaxWidth := -1;
    FMaxWidthRow := -1;
  end
  else if (FMaxLengthRow > ARow) then
    Dec(FMaxLengthRow);
end;

function TCustomBCEditor.TRows.GetLine(ARow: Integer): Integer;
begin
  Result := Items[ARow].Line;
end;

function TCustomBCEditor.TRows.GetMaxLength(): Integer;
var
  LRow: Integer;
begin
  if ((FMaxLength < 0) and (Count > 0)) then
    for LRow := 0 to Count - 1 do
      if (Items[LRow].Length > FMaxLength) then
      begin
        FMaxLengthRow := LRow;
        FMaxLength := Items[LRow].Length;
      end;

  Result := FMaxLength;
end;

function TCustomBCEditor.TRows.GetMaxWidth(): Integer;
var
  LRow: Integer;
begin
  if ((FMaxWidth < 0) and (Count > 0)) then
    for LRow := 0 to Count - 1 do
      if (Items[LRow].Width > FMaxWidth) then
      begin
        FMaxWidthRow := LRow;
        FMaxWidth := Items[LRow].Width;
      end;

  Result := FMaxWidth;
end;

function TCustomBCEditor.TRows.GetText(ARow: Integer): string;
begin
  Assert((0 <= ARow) and (ARow < Count));

  Result := Copy(Editor.Lines.Lines[Items[ARow].Line].Text, 1 + Items[ARow].Index, Items[ARow].Length);
end;

procedure TCustomBCEditor.TRows.Insert(ARow: Integer; const AFlags: TRow.TFlags;
  const ALine: Integer; const AIndex, ALength, AWidth: Integer);
var
  LItem: TRow;
begin
  Assert((0 <= ARow) and (ARow <= Count));

  LItem.Flags := AFlags;
  LItem.Index := AIndex;
  LItem.Length := ALength;
  LItem.Line := ALine;
  LItem.Width := AWidth;

  inherited Insert(ARow, LItem);

  if ((FMaxLength >= 0) and (ALength > FMaxLength)) then
  begin
    FMaxLength := ALength;
    FMaxLengthRow := ARow;
  end
  else if (FMaxLengthRow >= ARow) then
    Inc(FMaxLengthRow);

  if ((FMaxWidth >= 0) and (AWidth > FMaxWidth)) then
  begin
    FMaxWidth := AWidth;
    FMaxWidthRow := ARow;
  end
  else if (FMaxWidthRow >= ARow) then
    Inc(FMaxWidthRow);
end;

procedure TCustomBCEditor.TRows.PutLine(ARow: Integer; AValue: Integer);
begin
  Assert((0 <= ARow) and (ARow < Count));

  List[ARow].Line := AValue;
end;

{ TBCCustomEditor *************************************************************}

constructor TCustomBCEditor.Create(AOwner: TComponent);
var
  LIndex: Integer;
begin
  inherited Create(AOwner);

  Width := 185;
  Height := 89;
  Cursor := crIBeam;
  Color := clWindow;
  DoubleBuffered := False;
  ControlStyle := ControlStyle + [csOpaque, csSetCaption, csNeedsBorderPaint];

  FBackgroundColor := clWindow;
  FForegroundColor := clWindowText;
  FBorderStyle := bsSingle;
  FDoubleClickTime := GetDoubleClickTime;
  FHWheelAccumulator := 0;
  FLastSortOrder := soDesc;
  FSelectedCaseText := '';
  FURIOpener := False;
  FRows := TRows.Create(Self);
  FMultiCaretPosition.Row := -1;

  { Code folding }
  FAllCodeFoldingRanges := TBCEditorCodeFolding.TAllRanges.Create;
  FCodeFolding := TBCEditorCodeFolding.Create;
  FCodeFolding.OnChange := CodeFoldingOnChange;
  FCodeFoldingDelayTimer := TTimer.Create(Self);
  FCodeFoldingDelayTimer.OnTimer := OnCodeFoldingDelayTimer;
  { Matching pair }
  FMatchingPair := TBCEditorMatchingPair.Create;
  { Line spacing }
  FLineSpacing := 0;
  { Special chars }
  FSpecialChars := TBCEditorSpecialChars.Create;
  FSpecialChars.OnChange := SpecialCharsChanged;
  { Caret }
  FCaret := TBCEditorCaret.Create;
  FCaret.OnChange := CaretChanged;
  FCaretCreated := False;
  { Text buffer }
  FLines := TBCEditorLines(CreateLines());
  FOriginalLines := Lines;
  Lines.OnAfterUpdate := AfterLinesUpdate;
  Lines.OnBeforeUpdate := BeforeLinesUpdate;
  Lines.OnCaretMoved := CaretMoved;
  Lines.OnCleared := LinesCleared;
  Lines.OnDeleted := LineDeleted;
  Lines.OnInserted := LineInserted;
  Lines.OnUpdated := LineUpdated;
  Lines.OnSelChange := SelectionChanged;
  { Font }
  FFontDummy := TFont.Create;
  FFontDummy.Name := 'Courier New';
  FFontDummy.Size := 9;
  Font.Assign(FFontDummy);
  Font.OnChange := FontChanged;
  { Painting }
  FItalicOffset := 0;
  FLineHeight := 0;
  FTextWidth := MaxInt;
  FVisibleRows := MaxInt;
  FPaintHelper := TBCEditorPaintHelper.Create([], FFontDummy);
  ParentFont := False;
  ParentColor := False;
  FCommandDrop := False;
  { Active line, selection }
  FSelection := TBCEditorSelection.Create;
  FHideSelection := True;
  { Bookmarks }
  FBookmarkList := TBCEditorMarkList.Create(Self);
  FBookmarkList.OnChange := BookmarkListChange;
  { Marks }
  FMarkList := TBCEditorMarkList.Create(Self);
  FMarkList.OnChange := MarkListChange;
  { Right edge }
  FRightMargin := TBCEditorRightMargin.Create;
  FRightMargin.OnChange := RightMarginChanged;
  { Tabs }
  TabStop := True;
  FTabs := TBCEditorTabs.Create;
  FTabs.OnChange := TabsChanged;
  { Text }
  FTextEntryMode := temInsert;
  FKeyboardHandler := TBCEditorKeyboardHandler.Create;
  FKeyCommands := TBCEditorKeyCommands.Create(Self);
  SetDefaultKeyCommands;
  FWantReturns := True;
  FTopRow := 0;
  FOptions := DefaultOptions;
  { Completion proposal }
  FCompletionProposal := TBCEditorCompletionProposal.Create(Self);
  FCompletionProposalTimer := TTimer.Create(Self);
  FCompletionProposalTimer.Enabled := False;
  FCompletionProposalTimer.OnTimer := CompletionProposalTimerHandler;
  { Search }
  FSearch := TBCEditorSearch.Create;
  FSearch.OnChange := SearchChanged;
  FSearchResults := TList<TSearchResult>.Create();
  FSearchFindDialog := nil;
  FSearchReplaceDialog := nil;
  FReplace := TBCEditorReplace.Create;
  FReplace.OnChange := ReplaceChanged;
  { Scroll }
  FHideScrollBars := True;
  FScroll := TBCEditorScroll.Create;
  FScroll.OnChange := ScrollChanged;
  FScrollTimer := TTimer.Create(Self);
  FScrollTimer.Enabled := False;
  FScrollTimer.Interval := 100;
  FScrollTimer.OnTimer := ScrollTimerHandler;
  FMouseMoveScrollTimer := TTimer.Create(Self);
  FMouseMoveScrollTimer.Enabled := False;
  FMouseMoveScrollTimer.Interval := 100;
  FMouseMoveScrollTimer.OnTimer := MouseMoveScrollTimerHandler;
  { Active line }
  FActiveLine := TBCEditorActiveLine.Create;
  FActiveLine.OnChange := ActiveLineChanged;
  { Word wrap }
  FWordWrap := TBCEditorWordWrap.Create;
  FWordWrap.OnChange := WordWrapChanged;
  FWordWrapIndicator := TBitmap.Create();
  { Sync edit }
  FSyncEdit := TBCEditorSyncEdit.Create;
  FSyncEdit.OnChange := SyncEditChanged;
  { Token info }
  FTokenInfo := TBCEditorTokenInfo.Create;
  FTokenInfoTimer := TTimer.Create(Self);
  FTokenInfoTimer.Enabled := False;
  FTokenInfoTimer.OnTimer := OnTokenInfoTimer;
  { LeftMargin }
  FLeftMargin := TBCEditorLeftMargin.Create(Self);
  FLeftMargin.OnChange := LeftMarginChanged;
  FLeftMarginCharWidth := CharWidth;
  FLeftMarginWidth := GetLeftMarginWidth;
  { Do update character constraints }
  FontChanged(nil);
  TabsChanged(nil);
  { Highlighter }
  FHighlighter := TBCEditorHighlighter.Create(Self);
  { Mouse wheel scroll cursors }
  for LIndex := 0 to 7 do
    FMouseMoveScrollCursors[LIndex] := LoadCursor(HInstance, PChar(BCEDITOR_MOUSE_MOVE_SCROLL + IntToStr(LIndex)));

  if (not SystemParametersInfo(SPI_GETWHEELSCROLLLINES, 0, @FWheelScrollLines, 0)) then
    FWheelScrollLines := 3;
end;

destructor TCustomBCEditor.Destroy;
begin
  ClearCodeFolding;
  FCodeFolding.Free;
  FCodeFoldingDelayTimer.Free;
  FAllCodeFoldingRanges.Free;
  FHighlighter.Free;
  FHighlighter := nil;
  if Assigned(FChainedEditor) or (Lines <> FOriginalLines) then
    RemoveChainedEditor;
  if Assigned(FCompletionProposalPopupWindow) then
    FCompletionProposalPopupWindow.Free;
  FreeTokenInfoPopupWindow;
  { Do not use FreeAndNil, it first nil and then frees causing problems with code accessing FHookedCommandHandlers
    while destruction }
  FHookedCommandHandlers.Free;
  FHookedCommandHandlers := nil;
  FBookmarkList.Free;
  FMarkList.Free;
  FKeyCommands.Free;
  FKeyCommands := nil;
  FKeyboardHandler.Free;
  FSelection.Free;
  FLeftMargin.Free;
  FLeftMargin := nil; { Notification has a check }
  FWordWrap.Free;
  FWordWrapIndicator.Free();
  FPaintHelper.Free;
  FInternalBookmarkImage.Free;
  FFontDummy.Free;
  FOriginalLines.Free;
  FActiveLine.Free;
  FRightMargin.Free;
  FScroll.Free;
  FSearch.Free;
  FSearchResults.Free();
  FReplace.Free;
  FTabs.Free;
  FSpecialChars.Free;
  FCaret.Free;
  FreeMultiCarets;
  FMatchingPair.Free;
  FCompletionProposal.Free;
  FSyncEdit.Free;
  FTokenInfoTimer.Free;
  FTokenInfo.Free;
  if Assigned(FCodeFoldingHintForm) then
    FCodeFoldingHintForm.Release;
  FRows.Free();

  inherited Destroy;
end;

procedure TCustomBCEditor.ActiveLineChanged(Sender: TObject);
begin
  if not (csLoading in ComponentState) then
  begin
    if Sender is TBCEditorActiveLine then
      Invalidate;
    if Sender is TBCEditorGlyph then
      Invalidate;
  end;
end;

procedure TCustomBCEditor.AddCaret(const ADisplayPosition: TBCEditorDisplayPosition);

  procedure Add(ADisplayCaretPosition: TBCEditorDisplayPosition);
  var
    LIndex: Integer;
  begin
    for LIndex := 0 to FMultiCarets.Count - 1 do
      if (FMultiCarets[LIndex] = ADisplayCaretPosition) then
        Exit;
    FMultiCarets.Add(ADisplayCaretPosition);
  end;

begin
  if (ADisplayPosition.Row < Rows.Count) then
  begin
    if not Assigned(FMultiCarets) then
    begin
      FDrawMultiCarets := True;
      FMultiCarets := TMultiCarets.Create();
      FMultiCaretTimer := TTimer.Create(Self);
      FMultiCaretTimer.Interval := GetCaretBlinkTime;
      FMultiCaretTimer.OnTimer := MultiCaretTimerHandler;
      FMultiCaretTimer.Enabled := True;
    end;

    Add(ADisplayPosition);
  end;
end;

procedure TCustomBCEditor.AddHighlighterKeywords(AStringList: TStrings);
var
  LChar: Char;
  LIndex: Integer;
  LKeywordStringList: TStringList;
  LStringList: TStringList;
  LWord: string;
  LWordList: string;
begin
  LStringList := TStringList.Create;
  LKeywordStringList := TStringList.Create;
  LWordList := AStringList.Text;
  try
    FHighlighter.AddKeywords(LKeywordStringList);
    for LIndex := 0 to LKeywordStringList.Count - 1 do
    begin
      LWord := LKeywordStringList.Strings[LIndex];
      if Length(LWord) > 1 then
      begin
        LChar := LWord[1];
        if LChar.IsLower or LChar.IsUpper or (LChar = BCEDITOR_UNDERSCORE) then
          if Pos(LWord + BCEDITOR_CARRIAGE_RETURN + BCEDITOR_LINEFEED, LWordList) = 0 then { No duplicates }
            LWordList := LWordList + LWord + BCEDITOR_CARRIAGE_RETURN + BCEDITOR_LINEFEED;
      end;
    end;
    LStringList.Text := LWordList;
    LStringList.Sort;
    AStringList.Assign(LStringList);
  finally
    LKeywordStringList.Free;
    LStringList.Free;
  end;
end;

procedure TCustomBCEditor.AddKeyCommand(ACommand: TBCEditorCommand; AShift: TShiftState; AKey: Word;
  ASecondaryShift: TShiftState; ASecondaryKey: Word);
var
  LKeyCommand: TBCEditorKeyCommand;
begin
  LKeyCommand := KeyCommands.NewItem;
  with LKeyCommand do
  begin
    Command := ACommand;
    Key := AKey;
    SecondaryKey := ASecondaryKey;
    ShiftState := AShift;
    SecondaryShiftState := ASecondaryShift;
  end;
end;

procedure TCustomBCEditor.AddKeyDownHandler(AHandler: TKeyEvent);
begin
  FKeyboardHandler.AddKeyDownHandler(AHandler);
end;

procedure TCustomBCEditor.AddKeyPressHandler(AHandler: TBCEditorKeyPressWEvent);
begin
  FKeyboardHandler.AddKeyPressHandler(AHandler);
end;

procedure TCustomBCEditor.AddKeyUpHandler(AHandler: TKeyEvent);
begin
  FKeyboardHandler.AddKeyUpHandler(AHandler);
end;

procedure TCustomBCEditor.AddMouseCursorHandler(AHandler: TBCEditorMouseCursorEvent);
begin
  FKeyboardHandler.AddMouseCursorHandler(AHandler);
end;

procedure TCustomBCEditor.AddMouseDownHandler(AHandler: TMouseEvent);
begin
  FKeyboardHandler.AddMouseDownHandler(AHandler);
end;

procedure TCustomBCEditor.AddMouseUpHandler(AHandler: TMouseEvent);
begin
  FKeyboardHandler.AddMouseUpHandler(AHandler);
end;

procedure TCustomBCEditor.AddMultipleCarets(const ADisplayPosition: TBCEditorDisplayPosition);
var
  LBeginRow: Integer;
  LDisplayPosition: TBCEditorDisplayPosition;
  LEndRow: Integer;
  LRow: Integer;
begin
  LDisplayPosition := DisplayCaretPosition;

  if (LDisplayPosition.Row < Rows.Count) then
  begin
    if Assigned(FMultiCarets) and (FMultiCarets.Count > 0) then
    begin
      LBeginRow := FMultiCarets.Last().Row;
      LDisplayPosition.Column := FMultiCarets.Last().Column;
    end
    else
      LBeginRow := LDisplayPosition.Row;
    LEndRow := ADisplayPosition.Row;
    if LBeginRow > LEndRow then
      SwapInt(LBeginRow, LEndRow);

    for LRow := LBeginRow to LEndRow do
    begin
      LDisplayPosition.Row := LRow;
      AddCaret(LDisplayPosition);
    end;
  end;
end;

procedure TCustomBCEditor.AfterLinesUpdate(Sender: TObject);
begin
  EndUpdate();
end;

procedure TCustomBCEditor.Assign(ASource: TPersistent);
begin
  if Assigned(ASource) and (ASource is TCustomBCEditor) then
    with ASource as TCustomBCEditor do
    begin
      Self.FActiveLine.Assign(FActiveLine);
      Self.FCaret.Assign(FCaret);
      Self.FCodeFolding.Assign(FCodeFolding);
      Self.FCompletionProposal.Assign(FCompletionProposal);
      Self.FKeyCommands.Assign(FKeyCommands);
      Self.LeftMargin.Assign(LeftMargin);
      Self.FMatchingPair.Assign(FMatchingPair);
      Self.FReplace.Assign(FReplace);
      Self.FRightMargin.Assign(FRightMargin);
      Self.FScroll.Assign(FScroll);
      Self.FSearch.Assign(FSearch);
      Self.FSelection.Assign(FSelection);
      Self.FSpecialChars.Assign(FSpecialChars);
      Self.FSyncEdit.Assign(FSyncEdit);
      Self.FTabs.Assign(FTabs);
      Self.FWordWrap.Assign(FWordWrap);
    end
  else
    inherited Assign(ASource);
end;

procedure TCustomBCEditor.BeforeLinesUpdate(Sender: TObject);
begin
  BeginUpdate();
end;

procedure TCustomBCEditor.BeginUndoBlock;
begin
  Lines.BeginUpdate();
end;

procedure TCustomBCEditor.BeginUpdate();
begin
  if (FUpdateCount = 0) then SetUpdateState(True);
  Inc(FUpdateCount);
end;

procedure TCustomBCEditor.BookmarkListChange(Sender: TObject);
begin
  Invalidate;
end;

procedure TCustomBCEditor.CaretChanged(ASender: TObject);
begin
  if FCaret.MultiEdit.Enabled then
    FreeMultiCarets;
  ResetCaret;
end;

function TCustomBCEditor.CaretInView: Boolean;
var
  LCaretPoint: TPoint;
begin
  LCaretPoint := DisplayToClient(DisplayCaretPosition);
  Result := PtInRect(ClientRect, LCaretPoint);
end;

procedure TCustomBCEditor.ChainEditor(AEditor: TCustomBCEditor);
begin
  if Highlighter.FileName = '' then
    Highlighter.LoadFromFile(AEditor.Highlighter.FileName);
  if Highlighter.Colors.FileName = '' then
    Highlighter.Colors.LoadFromFile(AEditor.Highlighter.Colors.FileName);

  HookEditorLines(AEditor.Lines, AEditor.Lines.UndoList, AEditor.Lines.RedoList);
  InitCodeFolding;
  FChainedEditor := AEditor;
  AEditor.FreeNotification(Self);
end;

procedure TCustomBCEditor.ChainLinesCaretChanged(ASender: TObject);
begin
  if Assigned(FOnChainCaretMoved) then
    FOnChainCaretMoved(ASender);
  FOriginalLines.OnCaretMoved(ASender);
end;

procedure TCustomBCEditor.ChainLinesCleared(ASender: TObject);
begin
  if Assigned(FOnChainLinesCleared) then
    FOnChainLinesCleared(ASender);
  FOriginalLines.OnCleared(ASender);
end;

procedure TCustomBCEditor.ChainLinesDeleted(ASender: TObject; const ALine: Integer);
begin
  if Assigned(FOnChainLinesDeleted) then
    FOnChainLinesDeleted(ASender, ALine);
  FOriginalLines.OnDeleted(ASender, ALine);
end;

procedure TCustomBCEditor.ChainLinesInserted(ASender: TObject; const ALine: Integer);
begin
  if Assigned(FOnChainLinesInserted) then
    FOnChainLinesInserted(ASender, ALine);
  FOriginalLines.OnInserted(ASender, ALine);
end;

procedure TCustomBCEditor.ChainLinesUpdated(ASender: TObject; const ALine: Integer);
begin
  if Assigned(FOnChainLinesUpdated) then
    FOnChainLinesUpdated(ASender, ALine);
  FOriginalLines.OnUpdated(ASender, ALine);
end;

procedure TCustomBCEditor.ChangeScale(M, D: Integer);
begin
  FCompletionProposal.ChangeScale(M, D);
end;

function TCustomBCEditor.CharAtCursor(): Char;
begin
  if (Lines.Count = 0) then
    Result := BCEDITOR_NONE_CHAR
  else
    Result := Lines.Char[Lines.CaretPosition];
end;

procedure TCustomBCEditor.CheckIfAtMatchingKeywords;
var
  LIsKeyWord: Boolean;
  LLine: Integer;
  LNewFoldRange: TBCEditorCodeFolding.TRanges.TRange;
  LOpenKeyWord: Boolean;
begin
  LIsKeyWord := IsKeywordAtPosition(Lines.CaretPosition,
    @LOpenKeyWord, mpoHighlightAfterToken in FMatchingPair.Options);

  LNewFoldRange := nil;

  LLine := Lines.CaretPosition.Line + 1;

  if LIsKeyWord and LOpenKeyWord then
    LNewFoldRange := CodeFoldingRangeForLine(LLine)
  else
  if LIsKeyWord and not LOpenKeyWord then
    LNewFoldRange := CodeFoldingFoldRangeForLineTo(LLine);

  if LNewFoldRange <> FHighlightedFoldRange then
  begin
    FHighlightedFoldRange := LNewFoldRange;
    Invalidate;
  end;
end;

procedure TCustomBCEditor.Clear;
begin
  Lines.Clear();
  FRows.Clear();
  FMultiCaretPosition.Row := -1;
  ClearCodeFolding();
  ClearMatchingPair;
  ClearBookmarks;
  FMarkList.Clear;
  HorzTextPos := 0;
  TopRow := 0;
  Invalidate;
  UpdateScrollBars;
end;

procedure TCustomBCEditor.ClearBookmarks;
begin
  while FBookmarkList.Count > 0 do
    DeleteBookmark(FBookmarkList[0]);
end;

procedure TCustomBCEditor.ClearCodeFolding;
begin
  ExpandCodeFoldingLines();
  FAllCodeFoldingRanges.ClearAll;
  SetLength(FCodeFoldingTreeLine, 0);
  SetLength(FCodeFoldingRangeFromLine, 0);
  SetLength(FCodeFoldingRangeToLine, 0);
end;

procedure TCustomBCEditor.ClearMarks();
begin
  while FMarkList.Count > 0 do
    DeleteMark(FMarkList[0]);
end;

procedure TCustomBCEditor.ClearMatchingPair();
begin
  FCurrentMatchingPair := trNotFound;
end;

procedure TCustomBCEditor.ClearUndo();
begin
  Lines.ClearUndo();
end;

function TCustomBCEditor.ClientAndRowToDisplayPosition(const X, ARow: Integer; const ALineText: string = ''): TBCEditorDisplayPosition;
var
  LChar: string;
  LCharLength: Integer;
  LCharsBefore: Integer;
  LFontStyles: TFontStyles;
  LHighlighterAttribute: TBCEditorHighlighter.TAttribute;
  LLength: Integer;
  LLine: Integer;
  LLineText: string;
  LNextTokenText: string;
  LPreviousFontStyles: TFontStyles;
  LRow: Integer;
  LTextWidth: Integer;
  LTokenBeginPos: PChar;
  LTokenEndPos: PChar;
  LTokenPos: PChar;
  LTokenText: string;
  LTokenLength: Integer;
  LTokenWidth: Integer;
  LXInEditor: Integer;
begin
  if (X < LeftMarginWidth) then
    Result := DisplayPosition(0, ARow)
  else if (Rows.Count = 0) then
    Result := DisplayPosition((X - LeftMarginWidth) div CharWidth, ARow)
  else if (ARow >= Rows.Count) then
    Result := DisplayPosition((X - LeftMarginWidth) div CharWidth, Rows[Rows.Count - 1].Line + ARow - Rows.Count + 1)
  else
  begin
    Result := DisplayPosition(0, ARow);

    LLine := Rows[ARow].Line;

    if (ALineText <> '') then
      LLineText := ALineText
    else
      LLineText := Lines.ExpandedStrings[LLine];

    if (LLine = 0) then
      FHighlighter.ResetCurrentRange()
    else
      FHighlighter.SetCurrentRange(Lines.Lines[LLine - 1].Range);
    FHighlighter.SetCurrentLine(LLineText);

    LRow := Lines.Lines[LLine].FirstRow;

    LFontStyles := [];
    LPreviousFontStyles := [];
    LTextWidth := 0;
    LCharsBefore := 0;
    LXInEditor := X + HorzTextPos - LeftMarginWidth + 4;
    LLength := 0;

    LHighlighterAttribute := FHighlighter.GetTokenAttribute;
    if Assigned(LHighlighterAttribute) then
      LPreviousFontStyles := LHighlighterAttribute.FontStyles;
    FPaintHelper.SetStyle(LPreviousFontStyles);
    while not FHighlighter.GetEndOfLine do
    begin
      if LNextTokenText = '' then
        FHighlighter.GetTokenText(LTokenText)
      else
        LTokenText := LNextTokenText;
      LNextTokenText := '';

      LTokenLength := Length(LTokenText);
      LHighlighterAttribute := FHighlighter.GetTokenAttribute;
      if Assigned(LHighlighterAttribute) then
        LFontStyles := LHighlighterAttribute.FontStyles;
      if LFontStyles <> LPreviousFontStyles then
      begin
        FPaintHelper.SetStyle(LFontStyles);
        LPreviousFontStyles := LFontStyles;
      end;

      if WordWrap.Enabled then
        if LRow < ARow then
          if LLength + LTokenLength > Rows[LRow].Length then
          begin
            LNextTokenText := Copy(LTokenText, Rows[LRow].Length - LLength + 1, LTokenLength);
            LTokenLength := Rows[LRow].Length - LLength;
            LTokenText := Copy(LTokenText, 1, LTokenLength);

            Inc(LRow);
            LLength := 0;
            LTextWidth := 0;
            Inc(LCharsBefore, ComputeTextColumns(LTokenText, LCharsBefore));
            Continue;
          end;

      if LRow = ARow then
      begin
        LTokenWidth := ComputeTokenWidth(LTokenText, LTokenLength, LCharsBefore);
        if ((LXInEditor > 0) and (LTextWidth + LTokenWidth > LXInEditor)) then
        begin
          LTokenBeginPos := @LTokenText[1];
          LTokenPos := LTokenBeginPos;
          LTokenEndPos := @LTokenText[Length(LTokenText)];

          while (LTextWidth < LXInEditor) do
          begin
            while (LTokenPos + 1 <= LTokenEndPos)
              and (((LTokenPos + 1)^.GetUnicodeCategory in [TUnicodeCategory.ucCombiningMark, TUnicodeCategory.ucNonSpacingMark])
                or (LTokenPos^ <> BCEDITOR_NONE_CHAR)
                  and (LTokenPos^.GetUnicodeCategory = TUnicodeCategory.ucNonSpacingMark)
                  and not IsCombiningDiacriticalMark(LTokenPos^)) do
              Inc(LTokenPos);

            LCharLength := LTokenPos - LTokenBeginPos + 1;
            LChar := LeftStr(LTokenText, LCharLength);
            Inc(LTextWidth, ComputeTokenWidth(LChar, LCharLength, LCharsBefore));
            Inc(LCharsBefore, LCharLength);
            if LTextWidth <= LXInEditor then
              Inc(Result.Column, LCharLength);
          end;
          Exit;
        end
        else
        begin
          LTextWidth := LTextWidth + LTokenWidth;
          Inc(Result.Column, LTokenLength);
        end;
      end;

      Inc(LLength, LTokenLength);
      Inc(LCharsBefore, ComputeTextColumns(LTokenText, LCharsBefore));

      FHighlighter.Next;
    end;
    Inc(Result.Column, (X - LeftMarginWidth - LTextWidth + HorzTextPos) div CharWidth);
  end;
end;

function TCustomBCEditor.ClientToDisplay(const X, Y: Integer): TBCEditorDisplayPosition;
begin
  Result := ClientAndRowToDisplayPosition(X, ClientToDisplayRow(X, Y));
end;

function TCustomBCEditor.ClientToDisplayRow(const X, Y: Integer): Integer;
begin
  Result := Max(0, TopRow + Y div LineHeight);
end;

function TCustomBCEditor.ClientToText(const X, Y: Integer): TPoint;
begin
  Result := Point(DisplayToText(ClientToDisplay(X, Y)));
end;

function TCustomBCEditor.CodeFoldingCollapsableFoldRangeForLine(const ALine: Integer): TBCEditorCodeFolding.TRanges.TRange;
var
  LCodeFoldingRange: TBCEditorCodeFolding.TRanges.TRange;
begin
  LCodeFoldingRange := CodeFoldingRangeForLine(ALine);
  if (not Assigned(LCodeFoldingRange) or not LCodeFoldingRange.Collapsable) then
    Result := nil
  else
    Result := LCodeFoldingRange;
end;

function TCustomBCEditor.CodeFoldingFoldRangeForLineTo(const ALine: Integer): TBCEditorCodeFolding.TRanges.TRange;
var
  LCodeFoldingRange: TBCEditorCodeFolding.TRanges.TRange;
begin
  Result := nil;

  if (ALine < Length(FCodeFoldingRangeToLine)) then
  begin
    LCodeFoldingRange := FCodeFoldingRangeToLine[ALine];
    if Assigned(LCodeFoldingRange) then
      if (LCodeFoldingRange.LastLine = ALine) and not LCodeFoldingRange.ParentCollapsed then
        Result := LCodeFoldingRange;
  end;
end;

procedure TCustomBCEditor.CodeFoldingLinesDeleted(const ALine: Integer);
var
  LCodeFoldingRange: TBCEditorCodeFolding.TRanges.TRange;
begin
  LCodeFoldingRange := CodeFoldingRangeForLine(ALine);
  if Assigned(LCodeFoldingRange) then
    FAllCodeFoldingRanges.Delete(LCodeFoldingRange);
  UpdateFoldRanges(ALine, -1);
  LeftMarginChanged(Self);
end;

procedure TCustomBCEditor.CodeFoldingOnChange(AEvent: TBCEditorCodeFoldingChanges);
begin
  if AEvent = fcEnabled then
  begin
    if not FCodeFolding.Visible then
      ExpandCodeFoldingLines
    else
      InitCodeFolding;
  end
  else
  if AEvent = fcRescan then
  begin
    InitCodeFolding;
    if FHighlighter.FileName <> '' then
      FHighlighter.LoadFromFile(FHighlighter.FileName);
  end;

  FLeftMarginWidth := GetLeftMarginWidth;

  Invalidate;
end;

function TCustomBCEditor.CodeFoldingRangeForLine(const ALine: Integer): TBCEditorCodeFolding.TRanges.TRange;
begin
  Result := nil;
  if (ALine < Length(FCodeFoldingRangeFromLine)) then
    Result := FCodeFoldingRangeFromLine[ALine]
end;

procedure TCustomBCEditor.CodeFoldingResetCaches;
var
  LCodeFoldingRange: TBCEditorCodeFolding.TRanges.TRange;
  LIndex: Integer;
  LIndexRange: Integer;
  LLength: Integer;
begin
  if (FCodeFolding.Visible) then
  begin
    LLength := Lines.Count;
    SetLength(FCodeFoldingTreeLine, 0);
    SetLength(FCodeFoldingTreeLine, LLength);
    SetLength(FCodeFoldingRangeFromLine, 0);
    SetLength(FCodeFoldingRangeFromLine, LLength);
    SetLength(FCodeFoldingRangeToLine, 0);
    SetLength(FCodeFoldingRangeToLine, LLength);
    for LIndex := FAllCodeFoldingRanges.AllCount - 1 downto 0 do
    begin
      LCodeFoldingRange := FAllCodeFoldingRanges[LIndex];
      if Assigned(LCodeFoldingRange) then
        if (not LCodeFoldingRange.ParentCollapsed
          and ((LCodeFoldingRange.FirstLine <> LCodeFoldingRange.LastLine)
            or LCodeFoldingRange.RegionItem.TokenEndIsPreviousLine and (LCodeFoldingRange.FirstLine = LCodeFoldingRange.LastLine))) then
          begin
            FCodeFoldingRangeFromLine[LCodeFoldingRange.FirstLine] := LCodeFoldingRange;

            if LCodeFoldingRange.Collapsable then
            begin
              for LIndexRange := LCodeFoldingRange.FirstLine + 1 to LCodeFoldingRange.LastLine - 1 do
                FCodeFoldingTreeLine[LIndexRange] := True;

              FCodeFoldingRangeToLine[LCodeFoldingRange.LastLine] := LCodeFoldingRange;
            end;
          end;
    end;
  end;
end;

function TCustomBCEditor.CodeFoldingTreeEndForLine(const ALine: Integer): Boolean;
begin
  Result := Assigned(FCodeFoldingRangeToLine[ALine]);
end;

function TCustomBCEditor.CodeFoldingTreeLineForLine(const ALine: Integer): Boolean;
begin
  Result := FCodeFoldingTreeLine[ALine]
end;

procedure TCustomBCEditor.CollapseCodeFoldingLevel(const AFirstLevel: Integer; const ALastLevel: Integer);
var
  LFirstLine: Integer;
  LLastLine: Integer;
  LLevel: Integer;
  LLine: Integer;
  LRange: TBCEditorCodeFolding.TRanges.TRange;
  LRangeLevel: Integer;
begin
  if (SelectionAvailable) then
  begin
    LFirstLine := Lines.SelBeginPosition.Line;
    LLastLine := Lines.SelEndPosition.Line;
  end
  else
  begin
    LFirstLine := Lines.BOFPosition.Line;
    LLastLine := Lines.EOFPosition.Line;
  end;

  BeginUpdate();

  LLevel := -1;
  for LLine := LFirstLine to LLastLine do
  begin
    LRange := FCodeFoldingRangeFromLine[LLine];
    if (Assigned(LRange)) then
    begin
      if (LLevel = -1) then
        LLevel := LRange.FoldRangeLevel;
      LRangeLevel := LRange.FoldRangeLevel - LLevel;
      if ((AFirstLevel <= LRangeLevel) and (LRangeLevel <= ALastLevel)
        and not LRange.Collapsed and LRange.Collapsable) then
        CollapseCodeFoldingRange(LRange);
    end;
  end;

  CheckIfAtMatchingKeywords();

  EndUpdate();
end;

function TCustomBCEditor.CollapseCodeFoldingLines(const AFirstLine: Integer = -1; const ALastLine: Integer = -1): Integer;
var
  LFirstLine: Integer;
  LLastLine: Integer;
  LLine: Integer;
  LRange: TBCEditorCodeFolding.TRanges.TRange;
begin
  if (AFirstLine >= 0) then
    LFirstLine := AFirstLine
  else
    LFirstLine := 0;
  if (ALastLine >= 0) then
    LLastLine := ALastLine
  else if (AFirstLine >= 0) then
    LLastLine := AFirstLine
  else
    LLastLine := Lines.Count - 1;

  BeginUpdate();

  Result := 0;
  for LLine := LFirstLine to LLastLine do
  begin
    LRange := FCodeFoldingRangeFromLine[LLine];
    if (Assigned(LRange) and not LRange.Collapsed and LRange.Collapsable) then
    begin
      CollapseCodeFoldingRange(LRange);
      Inc(Result);
    end;
  end;

  CheckIfAtMatchingKeywords();

  EndUpdate();
end;

procedure TCustomBCEditor.CollapseCodeFoldingRange(const ARange: TBCEditorCodeFolding.TRanges.TRange);
var
  LLine: Integer;
begin
  if (not ARange.Collapsed) then
  begin
    if ((ARange.FirstLine < Lines.CaretPosition.Line) and (Lines.CaretPosition.Line <= ARange.LastLine)) then
      Lines.CaretPosition := TextPosition(Lines.CaretPosition.Char, ARange.FirstLine);

    for LLine := ARange.FirstLine + 1 to ARange.LastLine do
      DeleteLineFromRows(LLine);

    ARange.Collapsed := True;
    ARange.SetParentCollapsedOfSubCodeFoldingRanges(True, ARange.FoldRangeLevel);
  end;
end;

procedure TCustomBCEditor.CommandProcessor(ACommand: TBCEditorCommand; AChar: Char; AData: Pointer);
var
  LCollapsedCount: Integer;
  LDisplayCaret1Position: TBCEditorDisplayPosition;
  LIndex1: Integer;
  LIndex2: Integer;
  LLine: Integer;
  LNewSelectionBeginPosition: TBCEditorTextPosition;
  LNewSelectionEndPosition: TBCEditorTextPosition;
begin
  { First the program event handler gets a chance to process the command }
  DoOnProcessCommand(ACommand, AChar, AData);

  if ACommand <> ecNone then
  begin
    { Notify hooked command handlers before the command is executed inside of the class }
    NotifyHookedCommandHandlers(False, ACommand, AChar, AData);

    FRescanCodeFolding := (ACommand = ecCut) or (ACommand = ecPaste) or (ACommand = ecDeleteLine) or
      SelectionAvailable and ((ACommand = ecLineBreak) or (ACommand = ecBackspace) or (ACommand = ecChar)) or
      ((ACommand = ecChar) or (ACommand = ecBackspace) or (ACommand = ecTab) or (ACommand = ecDeleteChar) or
      (ACommand = ecLineBreak)) and IsKeywordAtPosition(Lines.CaretPosition) or (ACommand = ecBackspace) and IsCommentAtCaretPosition or
      ((ACommand = ecChar) and CharInSet(AChar, FHighlighter.SkipOpenKeyChars + FHighlighter.SkipCloseKeyChars));

    if (FCodeFolding.Visible) then
      case (ACommand) of
        ecBackspace, ecDeleteChar, ecDeleteWord, ecDeleteLastWord, ecDeleteLine,
        ecClear, ecLineBreak, ecChar, ecString, ecImeStr, ecCut, ecPaste,
        ecBlockIndent, ecBlockUnindent, ecTab:
          if (SelectionAvailable) then
          begin
            LNewSelectionBeginPosition := Lines.SelBeginPosition;
            LNewSelectionEndPosition := Lines.SelEndPosition;
            LCollapsedCount := 0;
            for LLine := LNewSelectionBeginPosition.Line to LNewSelectionEndPosition.Line do
              LCollapsedCount := ExpandCodeFoldingLines(LLine + 1);
            if LCollapsedCount <> 0 then
            begin
              Inc(LNewSelectionEndPosition.Line, LCollapsedCount);
              LNewSelectionEndPosition.Char := Length(Lines.Lines[LNewSelectionEndPosition.Line].Text);
            end;
            Lines.BeginUpdate();
            try
              Lines.SelBeginPosition := LNewSelectionBeginPosition;
              Lines.SelEndPosition := LNewSelectionEndPosition;
            finally
              Lines.EndUpdate();
            end;
          end
          else
            ExpandCodeFoldingLines(Lines.CaretPosition.Line + 1);
      end;

    if Assigned(FMultiCarets) and (FMultiCarets.Count > 0) then
    begin
      case ACommand of
        ecChar, ecBackspace, ecLineBegin, ecLineEnd:
          for LIndex1 := 0 to FMultiCarets.Count - 1 do
          begin
            LDisplayCaret1Position := FMultiCarets[LIndex1];
            DisplayCaretPosition := LDisplayCaret1Position;
            ExecuteCommand(ACommand, AChar, AData);

            for LIndex2 := 0 to FMultiCarets.Count - 1 do
            begin
              if (FMultiCarets[LIndex2] = LDisplayCaret1Position) then
                case ACommand of
                  ecChar:
                    FMultiCarets.Column[LIndex2] := FMultiCarets.Column[LIndex2] + 1;
                  ecBackspace:
                    FMultiCarets.Column[LIndex2] := FMultiCarets.Column[LIndex2] - 1;
                end
              else
              begin
                case ACommand of
                  ecLineBegin:
                    FMultiCarets.Column[LIndex2] := 1;
                  ecLineEnd:
                    FMultiCarets.Column[LIndex2] := Lines.ExpandedStringLengths[FMultiCarets.Row[LIndex2] - 1] + 1;
                end;
              end;
            end;
          end;
        ecUndo:
          begin
            FreeMultiCarets;
            ExecuteCommand(ACommand, AChar, AData);
          end;
      end;
      RemoveDuplicateMultiCarets;
    end
    else
    if ACommand < ecUserFirst then
      ExecuteCommand(ACommand, AChar, AData);

    { Notify hooked command handlers after the command was executed inside of the class }
    NotifyHookedCommandHandlers(True, ACommand, AChar, AData);
  end;
  DoOnCommandProcessed(ACommand, AChar, AData);
end;

procedure TCustomBCEditor.CompletionProposalTimerHandler(EndLine: TObject);
begin
  FCompletionProposalTimer.Enabled := False;
  DoCompletionProposal;
end;

function TCustomBCEditor.ComputeIndentText(const IndentCount: Integer): string;
begin
  if (not (eoAutoIndent in FOptions)) then
    Result := ''
  else if (toTabsToSpaces in FTabs.Options) then
    Result := StringOfChar(BCEDITOR_SPACE_CHAR, IndentCount)
  else
  begin
    Result := StringOfChar(BCEDITOR_TAB_CHAR, IndentCount div FTabs.Width);
    Result := Result + StringOfChar(BCEDITOR_SPACE_CHAR, IndentCount mod FTabs.Width);
  end;
end;

procedure TCustomBCEditor.ComputeScroll(const APoint: TPoint);
var
  LCursorIndex: Integer;
  LScrollBounds: TRect;
  LScrollBoundsLeft: Integer;
  LScrollBoundsRight: Integer;
begin
  if FMouseMoveScrolling then
  begin
    if (APoint.X < ClientRect.Left) or (APoint.X > ClientRect.Right) or (APoint.Y < ClientRect.Top) or
      (APoint.Y > ClientRect.Bottom) then
    begin
      FMouseMoveScrollTimer.Enabled := False;
      Exit;
    end;

    LCursorIndex := GetMouseMoveScrollCursorIndex;
    case LCursorIndex of
      scNorthWest, scWest, scSouthWest:
        FScrollDeltaX := (APoint.X - FMouseMoveScrollingPoint.X) div CharWidth - 1;
      scNorthEast, scEast, scSouthEast:
        FScrollDeltaX := (APoint.X - FMouseMoveScrollingPoint.X) div CharWidth + 1;
    else
      FScrollDeltaX := 0;
    end;

    case LCursorIndex of
      scNorthWest, scNorth, scNorthEast:
        FScrollDeltaY := (APoint.Y - FMouseMoveScrollingPoint.Y) div LineHeight - 1;
      scSouthWest, scSouth, scSouthEast:
        FScrollDeltaY := (APoint.Y - FMouseMoveScrollingPoint.Y) div LineHeight + 1;
    else
      FScrollDeltaY := 0;
    end;

    FMouseMoveScrollTimer.Enabled := (FScrollDeltaX <> 0) or (FScrollDeltaY <> 0);
  end
  else
  begin
    if not MouseCapture and not Dragging then
    begin
      FScrollTimer.Enabled := False;
      Exit;
    end;

    LScrollBoundsLeft := LeftMarginWidth;
    LScrollBoundsRight := LScrollBoundsLeft + TextWidth + 4;

    LScrollBounds := Bounds(LScrollBoundsLeft, 0, LScrollBoundsRight, VisibleRows * LineHeight);

    if BorderStyle = bsNone then
      InflateRect(LScrollBounds, -2, -2);

    if APoint.X < LScrollBounds.Left then
      FScrollDeltaX := (APoint.X - LScrollBounds.Left) div CharWidth - 1
    else
    if APoint.X >= LScrollBounds.Right then
      FScrollDeltaX := (APoint.X - LScrollBounds.Right) div CharWidth + 1
    else
      FScrollDeltaX := 0;

    if APoint.Y < LScrollBounds.Top then
      FScrollDeltaY := (APoint.Y - LScrollBounds.Top) div LineHeight - 1
    else
    if APoint.Y >= LScrollBounds.Bottom then
      FScrollDeltaY := (APoint.Y - LScrollBounds.Bottom) div LineHeight + 1
    else
      FScrollDeltaY := 0;

    FScrollTimer.Enabled := (FScrollDeltaX <> 0) or (FScrollDeltaY <> 0);
  end;
end;

function TCustomBCEditor.ComputeTextColumns(const AToken: string; const AColumnIndex: Integer): Integer;
var
  LPToken: PChar;
begin
  LPToken := PChar(AToken);
  if LPToken^ = BCEDITOR_TAB_CHAR then
  begin
    if toColumns in FTabs.Options then
      Result := FTabs.Width - AColumnIndex mod FTabs.Width
    else
      Result := FTabs.Width;
  end
  else
    Result := Length(AToken);
end;

function TCustomBCEditor.ComputeTokenWidth(const AText: string; const ALength: Integer; const AColumnIndex: Integer): Integer;
var
  LSize: TSize;
begin
  if ((AText = '') or (ALength = 0)) then
    Result := 0
  else
    case (AText[1]) of
      BCEDITOR_NONE_CHAR:
        Result := ALength * FPaintHelper.FontStock.CharWidth;
      BCEDITOR_SPACE_CHAR:
        Result := ALength * FPaintHelper.FontStock.CharWidth;
      BCEDITOR_TAB_CHAR:
        begin
          if (toColumns in FTabs.Options) then
            Result := FTabs.Width - AColumnIndex mod FTabs.Width
          else
            Result := FTabs.Width;
          Result := Result * FPaintHelper.FontStock.CharWidth + (ALength - 1) * FPaintHelper.FontStock.CharWidth * FTabs.Width;
        end
      else
        begin
          LSize.cx := 0;
          LSize.cy := 0;
          if (not GetTextExtentPoint32(FPaintHelper.StockBitmap.Canvas.Handle, PChar(AText), ALength, LSize)) then
            // Sometimes GetTextExtentPoint32 fails. But why?
            // Obsolete Canvas.Handle?
            // Lack of GDI resources?
            Result := 0
          else
            Result := LSize.cx;
        end;
    end;
end;

procedure TCustomBCEditor.CopyToClipboard();
begin
  if (SelectionAvailable) then
    DoCopyToClipboard(SelText);
end;

function TCustomBCEditor.CreateFileStream(const AFileName: string): TStream;
begin
  if Assigned(FOnCreateFileStream) then
    FOnCreateFileStream(Self, AFileName, Result)
  else
    Result := TFileStream.Create(AFileName, fmOpenRead);
end;

function TCustomBCEditor.CreateLines(): BCEditor.Lines.TBCEditorLines;
begin
  Result := BCEditor.Lines.TBCEditorLines.Create(Self);
end;

procedure TCustomBCEditor.CreateParams(var AParams: TCreateParams);
const
  LBorderStyles: array [TBorderStyle] of DWORD = (0, WS_BORDER);
  LClassStylesOff = CS_VREDRAW or CS_HREDRAW;
begin
  StrDispose(WindowText);
  WindowText := nil;

  inherited CreateParams(AParams);

  with AParams do
  begin
    WindowClass.Style := WindowClass.Style and not LClassStylesOff;
    Style := Style or LBorderStyles[FBorderStyle] or WS_CLIPCHILDREN;

    if NewStyleControls and Ctl3D and (FBorderStyle = bsSingle) then
    begin
      Style := Style and not WS_BORDER;
      ExStyle := ExStyle or WS_EX_CLIENTEDGE;
    end;
  end;
end;

procedure TCustomBCEditor.CreateWnd;
begin
  inherited;

  if (eoDropFiles in FOptions) and not (csDesigning in ComponentState) then
    DragAcceptFiles(Handle, True);

  if (not FCaretCreated) then
  begin
    FCaretCreated := True;
    FontChanged(nil);
  end
  else
    UpdateScrollBars();

  EnableScrollBar(Handle, SB_VERT, ESB_ENABLE_BOTH);
  EnableScrollBar(Handle, SB_HORZ, ESB_ENABLE_BOTH);
end;

procedure TCustomBCEditor.CutToClipboard;
begin
  CommandProcessor(ecCut, BCEDITOR_NONE_CHAR, nil);
end;

procedure TCustomBCEditor.DblClick;
var
  LClient: TPoint;
  LScreen: TPoint;
  LTextLinesLeft: Integer;
  LTextLinesRight: Integer;
begin
  if (not GetCursorPos(LScreen)) then
    RaiseLastOSError();

  LClient := ScreenToClient(LScreen);

  LTextLinesLeft := LeftMargin.Width + FCodeFolding.GetWidth();
  LTextLinesRight := ClientWidth;

  if (FSearch.Map.Visible) then
    if (Search.Map.Align = saLeft) then
      Inc(LTextLinesLeft, FSearch.Map.Width)
    else
      Dec(LTextLinesRight, FSearch.Map.Width);

  if ((LTextLinesLeft <= LClient.X) and (LClient.X < LTextLinesRight)) then
  begin
    SetWordBlock(Lines.CaretPosition);
    inherited;
    Include(FState, esDblClicked);
    MouseCapture := False;
  end
  else
    inherited;
end;

function TCustomBCEditor.DeleteBookmark(const ALine: Integer; const AIndex: Integer): Boolean;
var
  LBookmark: TBCEditorMark;
  LIndex: Integer;
begin
  Result := False;
  LIndex := 0;
  while LIndex < FBookmarkList.Count do
  begin
    LBookmark := FBookmarkList.Items[LIndex];
    if LBookmark.Line = ALine then
    begin
      if LBookmark.Index = AIndex then
        Result := True;
      DeleteBookmark(LBookmark);
    end
    else
      Inc(LIndex);
  end;
end;

procedure TCustomBCEditor.DeleteBookmark(ABookmark: TBCEditorMark);
begin
  if Assigned(ABookmark) then
  begin
    FBookmarkList.Remove(ABookmark);
    if Assigned(FOnAfterDeleteBookmark) then
      FOnAfterDeleteBookmark(Self);
  end;
end;

procedure TCustomBCEditor.DeleteChar();
begin
  if (SelectionAvailable) then
    SelText := ''
  else if ((Lines.CaretPosition.Line < Lines.Count)
    and (Lines.CaretPosition.Char < Length(Lines.Lines[Lines.CaretPosition.Line].Text))) then
    Lines.DeleteText(Lines.CaretPosition, TextPosition(Lines.CaretPosition.Char + 1, Lines.CaretPosition.Line))
  else if (Lines.CaretPosition.Line < Lines.Count - 1) then
    Lines.DeleteText(Lines.CaretPosition, Lines.BOLPosition[Lines.CaretPosition.Line + 1]);
end;

procedure TCustomBCEditor.DeleteLastWordOrBeginningOfLine(const ACommand: TBCEditorCommand);
var
  LNewCaretPosition: TBCEditorTextPosition;
begin
  if (ACommand = ecDeleteLastWord) then
    LNewCaretPosition := PreviousWordPosition(Lines.CaretPosition)
  else
    LNewCaretPosition := Lines.BOLPosition[Lines.CaretPosition.Line];
  if (LNewCaretPosition <> Lines.CaretPosition) then
    if (Lines.CaretPosition.Line < Lines.Count) then
      Lines.DeleteText(LNewCaretPosition, Min(Lines.CaretPosition, Lines.EOLPosition[Lines.CaretPosition.Line]))
    else
      Lines.CaretPosition := LnewCaretPosition;
end;

procedure TCustomBCEditor.DeleteLine();
begin
  if (SelectionAvailable) then
    Lines.SelBeginPosition := Lines.CaretPosition
  else if (Lines.CaretPosition.Line < Lines.Count) then
    Lines.Delete(Lines.CaretPosition.Line);
end;

procedure TCustomBCEditor.DeleteLineFromRows(const ALine: Integer);
var
  LDeletedRows: Integer;
  LFirstLine: Integer;
  LFirstRow: Integer;
  LLastRow: Integer;
  LLeftRow: Integer;
  LLine: Integer;
  LRightRow: Integer;
  LRow: Integer;
begin
  if (FRows.Count > 0) then
  begin
    ClearMatchingPair();

    LRow := 0;
    LLeftRow := 0;
    LRightRow := FRows.Count - 1;
    while (LLeftRow <= LRightRow) do
    begin
      LRow := (LLeftRow + LRightRow) div 2;
      case (Sign(FRows[LRow].Line - ALine)) of
        -1: begin LLeftRow := LRow + 1; Inc(LRow); end;
        0: break;
        1: begin LRightRow := LRow - 1; Dec(LRow); end;
      end;
    end;

    if (LLeftRow <= LRightRow) then
    begin
      while ((LRow > 0) and not (rfFirstRowOfLine in FRows[LRow].Flags)) do
        Dec(LRow);

      LFirstRow := LRow;

      if ((0 <= LFirstRow) and (LFirstRow < FRows.Count)) then
      begin
        while ((LRow < FRows.Count) and (FRows[LRow].Line = ALine)) do
          Inc(LRow);

        LDeletedRows := LRow - LFirstRow;
        LLastRow := LRow - 1;

        if ((LFirstRow <= FMultiCaretPosition.Row) and (FMultiCaretPosition.Row <= LLastRow)) then
          FMultiCaretPosition.Row := -1
        else if (FMultiCaretPosition.Row > FLastRow) then
          Dec(FMultiCaretPosition.Row, LDeletedRows);

        if ((ALine < Lines.Count) and (Lines.Lines[ALine].FirstRow = LFirstRow)) then
        begin
          // Line still in Lines
          Lines.SetFirstRow(ALine, -1);
          LFirstLine := ALine + 1;
        end
        else if ((ALine < Lines.Count) and (Lines.Lines[ALine].FirstRow = LRow)) then
          // Line deleted from Lines
          LFirstLine := ALine
        else
          // Last Line deleted from Lines
          LFirstLine := Lines.Count;

        for LLine := LFirstLine to Lines.Count - 1 do
          Lines.SetFirstRow(LLine, Lines.Lines[LLine].FirstRow - LDeletedRows);

        for LRow := LRow - 1 downto LFirstRow do
          FRows.Delete(LRow);

        for LRow := LFirstRow to FRows.Count - 1 do
          FRows.Line[LRow] := FRows[LRow].Line - 1;
      end;
    end;

    if (UpdateCount > 0) then
      Include(FState, esRowsChanged)
    else
    begin
      ClearMatchingPair();
      UpdateScrollBars();
      Invalidate();
    end;
  end;
end;

procedure TCustomBCEditor.DeleteMark(AMark: TBCEditorMark);
begin
  if Assigned(AMark) then
  begin
    if Assigned(FOnBeforeDeleteMark) then
      FOnBeforeDeleteMark(Self, AMark);
    FMarkList.Remove(AMark);
    if Assigned(FOnAfterDeleteMark) then
      FOnAfterDeleteMark(Self);
  end
end;

procedure TCustomBCEditor.DeleteWhitespace;

  function DeleteWhitespace(const AText: string): string;
  var
    LIndex: Integer;
    LIndex2: Integer;
  begin
    SetLength(Result, Length(AText));
    LIndex2 := 0;
    for LIndex := 1 to Length(AText) do
      if not AText[LIndex].IsWhiteSpace then
      begin
        Inc(LIndex2);
        Result[LIndex2] := AText[LIndex];
      end;
    SetLength(Result, LIndex2);
  end;

var
  LStrings: TStringList;
begin
  if ReadOnly then
    Exit;

  if SelectionAvailable then
  begin
    LStrings := TStringList.Create;
    try
      LStrings.Text := SelText;
      SelText := DeleteWhitespace(LStrings.Text);
    finally
      LStrings.Free;
    end;
  end
  else
    Text := DeleteWhitespace(Text);
end;

procedure TCustomBCEditor.DeleteWordOrEndOfLine(const ACommand: TBCEditorCommand);
var
  LEndPosition: TBCEditorTextPosition;
begin
  if (Lines.CaretPosition.Line < Lines.Count) then
  begin
    case (ACommand) of
      ecDeleteWord:
        if ((Lines.CaretPosition.Char < Length(Lines.Lines[Lines.CaretPosition.Line].Text))
          and not IsWordBreakChar(Lines.Char[Lines.CaretPosition])) then
        begin
          LEndPosition := WordEnd(Lines.CaretPosition);
          while ((LEndPosition.Char < Length(Lines.Lines[LEndPosition.Line].Text)) and IsEmptyChar(Lines.Char[LEndPosition])) do
            Inc(LEndPosition.Char);
        end
        else
          LEndPosition := NextWordPosition(Lines.CaretPosition);
      ecDeleteEndOfLine:
        LEndPosition := Lines.EOLPosition[Lines.CaretPosition.Line];
      else raise ERangeError.Create('ACommand: ' + IntToStr(Ord(ACommand)));
    end;

    if (LEndPosition > Lines.CaretPosition) then
      Lines.DeleteText(Lines.CaretPosition, LEndPosition);
  end;
end;

procedure TCustomBCEditor.DestroyWnd;
begin
  if (eoDropFiles in FOptions) and not (csDesigning in ComponentState) then
    DragAcceptFiles(Handle, False);

  inherited;
end;

function TCustomBCEditor.DisplayToClient(ADisplayPosition: TBCEditorDisplayPosition): TPoint;
var
  LCharsBefore: Integer;
  LFontStyles: TFontStyles;
  LHighlighterAttribute: TBCEditorHighlighter.TAttribute;
  LLength: Integer;
  LLine: Integer;
  LLineText: string;
  LNextTokenText: string;
  LPreviousFontStyles: TFontStyles;
  LRow: Integer;
  LTokenText: string;
  LTokenLength: Integer;
begin
  if (Rows.Count = 0) then
    Result := Point(LeftMarginWidth + ADisplayPosition.Column * CharWidth - HorzTextPos, (ADisplayPosition.Row - TopRow) * LineHeight)
  else if (ADisplayPosition.Row >= Rows.Count) then
    Result := Point(LeftMarginWidth + ADisplayPosition.Column * CharWidth - HorzTextPos, (Lines.Count - Rows[Rows.Count - 1].Line - 1 + ADisplayPosition.Row - TopRow) * LineHeight)
  else
  begin
    Result := Point(0, (ADisplayPosition.Row - TopRow) * LineHeight);

    LLine := Rows[ADisplayPosition.Row].Line;

    if (LLine = 0) then
      FHighlighter.ResetCurrentRange
    else
      FHighlighter.SetCurrentRange(Lines.Lines[LLine - 1].Range);

    LLineText := Lines.ExpandedStrings[LLine];

    FHighlighter.SetCurrentLine(LLineText);

    LRow := Lines.Lines[LLine].FirstRow;

    LLength := 0;
    LCharsBefore := 0;
    LFontStyles := [];
    LPreviousFontStyles := [];

    while not FHighlighter.GetEndOfLine do
    begin
      if LNextTokenText = '' then
        FHighlighter.GetTokenText(LTokenText)
      else
        LTokenText := LNextTokenText;
      LNextTokenText := '';
      LHighlighterAttribute := FHighlighter.GetTokenAttribute;
      if Assigned(LHighlighterAttribute) then
        LFontStyles := LHighlighterAttribute.FontStyles;
      if LFontStyles <> LPreviousFontStyles then
      begin
        FPaintHelper.SetStyle(LFontStyles);
        LPreviousFontStyles := LFontStyles;
      end;

      LTokenLength := Length(LTokenText);

      if WordWrap.Enabled then
        if LRow < ADisplayPosition.Row then
          if LLength + LTokenLength > Rows[LRow].Length then
          begin
            LNextTokenText := Copy(LTokenText, Rows[LRow].Length - LLength + 1, LTokenLength);
            LTokenLength := Rows[LRow].Length - LLength;
            LTokenText := Copy(LTokenText, 1, LTokenLength);

            Inc(LRow);
            LLength := 0;
            Inc(LCharsBefore, ComputeTextColumns(LTokenText, LCharsBefore));
            Continue;
          end;

      if LRow = ADisplayPosition.Row then
      begin
        if LLength + LTokenLength > ADisplayPosition.Column then
        begin
          Inc(Result.X, ComputeTokenWidth(LTokenText, ADisplayPosition.Column - LLength, LCharsBefore));
          Inc(LLength, LTokenLength);
          Break;
        end;

        Inc(Result.X, ComputeTokenWidth(LTokenText, Length(LTokenText), LCharsBefore));
      end;

      Inc(LLength, LTokenLength);
      Inc(LCharsBefore, ComputeTextColumns(LTokenText, LCharsBefore));

      FHighlighter.Next;
    end;

    if LLength <= ADisplayPosition.Column then
      Inc(Result.X, (ADisplayPosition.Column - LLength) * CharWidth);

    Inc(Result.X, LeftMarginWidth - HorzTextPos);
  end;
end;

function TCustomBCEditor.DisplayToText(const ADisplayPosition: TBCEditorDisplayPosition): TBCEditorTextPosition;
var
  LChar: Integer;
  LLineEndPos: PChar;
  LLinePos: PChar;
  LResultChar: Integer;
  LRow: Integer;
begin
  if (Rows.Count = 0) then
    Result := TextPosition(ADisplayPosition.Column, ADisplayPosition.Row)
  else if (ADisplayPosition.Row >= Rows.Count) then
    Result := TextPosition(ADisplayPosition.Column, Rows[Rows.Count - 1].Line + ADisplayPosition.Row - Rows.Count + 1)
  else
  begin
    Result := TextPosition(ADisplayPosition.Column, Rows[ADisplayPosition.Row].Line);

    if (WordWrap.Enabled) then
    begin
      Assert(Lines.Lines[Result.Line].FirstRow >= 0);

      LRow := ADisplayPosition.Row;
      while (LRow > Lines.Lines[Result.Line].FirstRow) do
      begin
        Dec(LRow);
        Inc(Result.Char, Rows[LRow].Length);
      end;

      if (Lines.Lines[Result.Line].Text <> '') then
      begin
        LLinePos := @Lines.Lines[Result.Line].Text[1];
        LLineEndPos := @Lines.Lines[Result.Line].Text[1 + Result.Char];
        while (LLinePos < LLineEndPos) do
        begin
          if (LLinePos^ = BCEDITOR_TAB_CHAR) then
            Dec(Result.Char, FTabs.Width - 1);
          Inc(LLinePos);
        end;
      end;
    end
    else
    begin
      if (Lines.Lines[Result.Line].Text <> '') then
      begin
        LLinePos := @Lines.Lines[Result.Line].Text[1];
        LLineEndPos := @Lines.Lines[Result.Line].Text[Length(Lines.Lines[Result.Line].Text)];
        LChar := 0;
        LResultChar := 0;
        while LChar < Result.Char do
        begin
          if (LLinePos <= LLineEndPos) then
          begin
            if (LLinePos^ = BCEDITOR_TAB_CHAR) then
            begin
              if toColumns in FTabs.Options then
                Inc(LChar, FTabs.Width - LChar mod FTabs.Width)
              else
                Inc(LChar, FTabs.Width)
            end
            else
              Inc(LChar);
            Inc(LLinePos);
          end
          else
            Inc(LChar);
          Inc(LResultChar);
        end;
        while ((LLinePos <= LLineEndPos)
          and ((LLinePos^.GetUnicodeCategory in [TUnicodeCategory.ucCombiningMark, TUnicodeCategory.ucNonSpacingMark])
            or ((LLinePos - 1)^ <> BCEDITOR_NONE_CHAR)
              and ((LLinePos - 1)^.GetUnicodeCategory = TUnicodeCategory.ucNonSpacingMark)
              and not IsCombiningDiacriticalMark((LLinePos - 1)^))) do
        begin
          Inc(LResultChar);
          Inc(LLinePos);
        end;
        Result.Char := LResultChar;
      end;
    end;
  end;
end;

procedure TCustomBCEditor.DoBackspace();
var
  LBackCounterLine: Integer;
  LNewCaretPosition: TBCEditorTextPosition;
  LFoldRange: TBCEditorCodeFolding.TRanges.TRange;
  LLength: Integer;
  LSpaceCount1: Integer;
  LSpaceCount2: Integer;
  LVisualSpaceCount1: Integer;
  LVisualSpaceCount2: Integer;
begin
  Lines.BeginUpdate();
  try
    if (SelectionAvailable) then
    begin
      if FSyncEdit.Active then
      begin
        if Lines.CaretPosition.Char < FSyncEdit.EditBeginPosition.Char then
          Exit;
        FSyncEdit.MoveEndPositionChar(-Lines.SelEndPosition.Char + Lines.SelBeginPosition.Char);
      end;
      SelText := '';
    end
    else if (Lines.CaretPosition > Lines.BOFPosition) then
    begin
      if (FSyncEdit.Active) then
      begin
        if Lines.CaretPosition.Char <= FSyncEdit.EditBeginPosition.Char then
          Exit;
        FSyncEdit.MoveEndPositionChar(-1);
      end;

      if ((Lines.CaretPosition.Line < Lines.Count)
        and (Lines.CaretPosition.Char > Length(Lines.Lines[Lines.CaretPosition.Line].Text))) then
      begin
        if (Length(Lines.Lines[Lines.CaretPosition.Line].Text) > 0) then
          Lines.CaretPosition := Lines.EOLPosition[Lines.CaretPosition.Line]
        else
        begin
          LSpaceCount1 := Lines.CaretPosition.Char;
          LSpaceCount2 := 0;
          if LSpaceCount1 > 0 then
          begin
            LBackCounterLine := Lines.CaretPosition.Line;
            while LBackCounterLine >= 0 do
            begin
              LSpaceCount2 := LeftSpaceCount(Lines.Lines[LBackCounterLine].Text);
              if LSpaceCount2 < LSpaceCount1 then
                Break;
              Dec(LBackCounterLine);
            end;
            if (LBackCounterLine = -1) and (LSpaceCount2 > LSpaceCount1) then
              LSpaceCount2 := 0;
          end;
          if LSpaceCount2 = LSpaceCount1 then
            LSpaceCount2 := 0;

          Lines.CaretPosition := TextPosition(Lines.CaretPosition.Char - (LSpaceCount1 - LSpaceCount2), Lines.CaretPosition.Line);
        end;
      end
      else if ((Lines.CaretPosition.Line < Lines.Count)
        and (Lines.CaretPosition.Char > 0)) then
      begin
        LSpaceCount1 := LeftSpaceCount(Lines.Lines[Lines.CaretPosition.Line].Text);
        LSpaceCount2 := 0;
        if ((Lines.CaretPosition.Char < Length(Lines.Lines[Lines.CaretPosition.Line].Text) - 1)
          and (Lines.Char[Lines.CaretPosition] = BCEDITOR_SPACE_CHAR)
            or (LSpaceCount1 <> Lines.CaretPosition.Char)) then
        begin
          LNewCaretPosition := TextPosition(Lines.CaretPosition.Char - 1, Lines.CaretPosition.Line);
          if (Lines.Char[LNewCaretPosition].IsSurrogate()) then
            Dec(LNewCaretPosition.Char);
        end
        else
        begin
          LVisualSpaceCount1 := GetLeadingExpandedLength(Lines.Lines[Lines.CaretPosition.Line].Text);
          LVisualSpaceCount2 := 0;
          LBackCounterLine := Lines.CaretPosition.Line - 1;
          while LBackCounterLine >= 0 do
          begin
            LVisualSpaceCount2 := GetLeadingExpandedLength(Lines.Lines[LBackCounterLine].Text);
            if LVisualSpaceCount2 < LVisualSpaceCount1 then
            begin
              LSpaceCount2 := LeftSpaceCount(Lines.Lines[LBackCounterLine].Text);
              Break;
            end;
            Dec(LBackCounterLine);
          end;

          if ((LSpaceCount2 > 0)
            and ((LBackCounterLine >= 0) or (LSpaceCount2 <= LSpaceCount1))
            and (LSpaceCount2 <> LSpaceCount1)) then
          begin
            LNewCaretPosition := Lines.CaretPosition;

            LLength := GetLeadingExpandedLength(Lines.Lines[Lines.CaretPosition.Line].Text, LNewCaretPosition.Char);
            while ((LNewCaretPosition.Char > 0) and (LLength > LVisualSpaceCount2)) do
            begin
              Dec(LNewCaretPosition.Char);
              LLength := GetLeadingExpandedLength(Lines.Lines[Lines.CaretPosition.Line].Text, LNewCaretPosition.Char);
            end;
          end
          else
          begin
            LNewCaretPosition := TextPosition(Lines.CaretPosition.Char - 1, Lines.CaretPosition.Line);
            LVisualSpaceCount2 := LVisualSpaceCount1 - (LVisualSpaceCount1 mod FTabs.Width);
            if (LVisualSpaceCount2 = LVisualSpaceCount1) then
              LVisualSpaceCount2 := Max(LVisualSpaceCount2 - FTabs.Width, 0);

            LLength := GetLeadingExpandedLength(Lines.Lines[Lines.CaretPosition.Line].Text, LNewCaretPosition.Char - 1);
            while (LNewCaretPosition.Char > 0) and (LLength > LVisualSpaceCount2) do
            begin
              Dec(LNewCaretPosition.Char);
              LLength := GetLeadingExpandedLength(Lines.Lines[Lines.CaretPosition.Line].Text, LNewCaretPosition.Char);
            end;
          end;
        end;

        Lines.Backspace(LNewCaretPosition, Lines.CaretPosition);
      end
      else if (Lines.CaretPosition.Line >= Lines.Count) then
        if (Lines.CaretPosition.Char > 0) then
          Lines.CaretPosition := TextPosition(0, Lines.CaretPosition.Line)
        else if (Lines.CaretPosition.Line = Lines.Count) then
          Lines.CaretPosition := Lines.EOLPosition[Lines.CaretPosition.Line - 1]
        else
          Lines.CaretPosition := TextPosition(0, Lines.CaretPosition.Line - 1)
      else if (Lines.CaretPosition.Line > 0) then
      begin
        LNewCaretPosition := Lines.EOLPosition[Lines.CaretPosition.Line - 1];

        LFoldRange := CodeFoldingFoldRangeForLineTo(LNewCaretPosition.Line);
        if (Assigned(LFoldRange) and LFoldRange.Collapsed) then
        begin
          LNewCaretPosition.Line := LFoldRange.FirstLine;
          Inc(LNewCaretPosition.Char, Length(Lines.Lines[LNewCaretPosition.Line].Text) + 1);
        end;

        Lines.DeleteText(LNewCaretPosition, Lines.CaretPosition);
      end
      else
        Lines.CaretPosition := Lines.BOFPosition;
    end;

    if (FSyncEdit.Active) then
      DoSyncEdit();
  finally
    Lines.EndUpdate();
  end;
end;

procedure TCustomBCEditor.DoBlockComment();
var
  LBeginPosition: TBCEditorTextPosition;
  LCommentIndex: Integer;
  LCommentLength: Integer;
  LEndPosition: TBCEditorTextPosition;
  LIndentText: string;
  LIndex: Integer;
  LLinesDeleted: Integer;
  LText: string;
begin
  LCommentLength := Length(FHighlighter.Comments.BlockComments);

  if (LCommentLength = 0) then
    // No BlockComment defined in the Highlighter
  else
  begin
    LBeginPosition := Min(Lines.SelBeginPosition, Lines.SelEndPosition);
    LEndPosition := Max(Lines.SelBeginPosition, Lines.SelEndPosition);

    if (LEndPosition <> Lines.BOFPosition) then
    begin
      LText := Trim(Lines.TextBetween[LBeginPosition, LEndPosition]);

      LCommentIndex := -2;
      LIndex := 0;
      while (LIndex + 1 < LCommentLength) do
        if ((Length(LText) >= Length(FHighlighter.Comments.BlockComments[LIndex]) + Length(FHighlighter.Comments.BlockComments[LIndex + 1]))
          and (LeftStr(LText, Length(FHighlighter.Comments.BlockComments[LIndex])) = FHighlighter.Comments.BlockComments[LIndex])
          and (RightStr(LText, Length(FHighlighter.Comments.BlockComments[LIndex + 1])) = FHighlighter.Comments.BlockComments[LIndex + 1])) then
        begin
          LCommentIndex := LIndex;
          break;
        end
        else
          Inc(LIndex, 2);

      if (LCommentIndex < 0) then
      begin
        LBeginPosition.Char := 0;
        if (LEndPosition.Line < Lines.Count - 1) then
          LEndPosition := Lines.BOLPosition[LEndPosition.Line]
        else
          LEndPosition := Lines.EOLPosition[LEndPosition.Line];

        LText := Trim(Lines.TextBetween[LBeginPosition, LEndPosition]);

        LCommentIndex := -2;
        LIndex := 0;
        while (LIndex + 1 < LCommentLength) do
          if ((Length(LText) >= Length(FHighlighter.Comments.BlockComments[LIndex]) + Length(FHighlighter.Comments.BlockComments[LIndex + 1]))
            and (LeftStr(LText, Length(FHighlighter.Comments.BlockComments[LIndex])) = FHighlighter.Comments.BlockComments[LIndex])
            and (RightStr(LText, Length(FHighlighter.Comments.BlockComments[LIndex + 1])) = FHighlighter.Comments.BlockComments[LIndex + 1])) then
          begin
            LCommentIndex := LIndex;
            break;
          end
          else
            Inc(LIndex, 2);
      end;


      Lines.BeginUpdate();
      try
        if (LCommentIndex >= 0) then
        begin
          LText := Lines.TextBetween[LBeginPosition, LEndPosition];

          LBeginPosition := Lines.CharIndexToPosition(LeftTrimLength(LText), LBeginPosition);
          LEndPosition := Lines.CharIndexToPosition(Length(Trim(LText)), LBeginPosition);

          LLinesDeleted := 0;
          Lines.DeleteText(LBeginPosition, TextPosition(LBeginPosition.Char + Length(FHighlighter.Comments.BlockComments[LIndex]), LBeginPosition.Line));
          if (Trim(Lines.Lines[LBeginPosition.Line].Text) = '') then
          begin
            Lines.Delete(LBeginPosition.Line);
            Dec(LEndPosition.Line);
            LBeginPosition.Char := 0;
            Inc(LLinesDeleted);
          end;

          Lines.DeleteText(LEndPosition, TextPosition(LEndPosition.Char, LEndPosition.Line));
          if (Trim(Lines.Lines[LEndPosition.Line].Text) = '') then
          begin
            Lines.Delete(LEndPosition.Line);
            Dec(LEndPosition.Line);
            Inc(LLinesDeleted);
          end;

          if ((LLinesDeleted = 2) and (LEndPosition >= LBeginPosition)) then
            Lines.DeleteIndent(LBeginPosition, TextPosition(LBeginPosition.Char, LEndPosition.Line), ComputeIndentText(Tabs.Width), Lines.SelMode);
        end;

        Inc(LCommentIndex, 2);

        if (LCommentIndex < LCommentLength) then
        begin
          Lines.SelMode := smNormal;

          LIndentText := ComputeIndentText(LeftSpaceCount(Lines.Lines[LBeginPosition.Line].Text));

          Lines.InsertText(LBeginPosition, LIndentText + FHighlighter.Comments.BlockComments[LCommentIndex] + Lines.LineBreak);
          Inc(LEndPosition.Line);

          if ((LEndPosition.Char = 0) and (LEndPosition.Line > LBeginPosition.Line)) then
            LEndPosition := Lines.EOLPosition[LEndPosition.Line - 1];
          Lines.InsertText(LEndPosition, Lines.LineBreak + LIndentText + FHighlighter.Comments.BlockComments[LCommentIndex + 1]);

          Lines.InsertIndent(Lines.BOLPosition[LBeginPosition.Line + 1], TextPosition(LBeginPosition.Char, LEndPosition.Line + 1), ComputeIndentText(Tabs.Width), Lines.SelMode);
          Inc(LEndPosition.Line);
        end;

        if (LEndPosition.Line < Lines.Count - 1) then
        begin
          LEndPosition := Lines.BOLPosition[LEndPosition.Line + 1];
          SetCaretAndSelection(LEndPosition, LBeginPosition, LEndPosition);
        end
        else
          Lines.CaretPosition := Lines.BOFPosition;
      finally
        Lines.EndUpdate();
      end;
    end;
  end;
end;

procedure TCustomBCEditor.DoBlockIndent(const ACommand: TBCEditorCommand);
var
  LIndentText: string;
  LTextBeginPosition: TBCEditorTextPosition;
  LTextEndPosition: TBCEditorTextPosition;
begin
  if (Lines.Count > 0) then
  begin
    if (SelectionAvailable and (Lines.SelMode = smColumn)) then
      LTextBeginPosition := Min(Lines.SelBeginPosition, Lines.SelEndPosition)
    else
      LTextBeginPosition := Lines.BOLPosition[Min(Lines.SelBeginPosition, Lines.SelEndPosition).Line];
    LTextEndPosition := TextPosition(LTextBeginPosition.Char, Max(Lines.SelBeginPosition, Lines.SelEndPosition).Line);
    if (LTextEndPosition = LTextBeginPosition) then
      if (LTextEndPosition.Line < Lines.Count - 1) then
        LTextEndPosition := Lines.BOLPosition[LTextEndPosition.Line + 1]
      else
        LTextEndPosition := Lines.EOLPosition[LTextEndPosition.Line];

    LIndentText := ComputeIndentText(FTabs.Width);

    Lines.BeginUpdate();
    try
      case (ACommand) of
        ecBlockIndent:
          Lines.InsertIndent(LTextBeginPosition, LTextEndPosition,
            LIndentText, Lines.SelMode);
        ecBlockUnindent:
          Lines.DeleteIndent(LTextBeginPosition, LTextEndPosition,
            LIndentText, Lines.SelMode);
        else raise ERangeError.Create('ACommand: ' + IntToStr(Ord(ACommand)));
      end;

      if (not SelectionAvailable) then
      begin
        LTextBeginPosition.Char := 0;
        if (LTextEndPosition.Char > 0) then
          LTextEndPosition.Char := Length(Lines.Lines[LTextEndPosition.Line].Text);
        SetCaretAndSelection(LTextEndPosition, LTextBeginPosition, LTextEndPosition);
      end;
    finally
      Lines.EndUpdate();
    end;
  end;
end;

procedure TCustomBCEditor.DoChar(const AChar: Char);
begin
  DoInsertText(AChar);
end;

procedure TCustomBCEditor.DoCompletionProposal();
var
  LCanExecute: Boolean;
  LColumnIndex: Integer;
  LControl: TWinControl;
  LCurrentInput: string;
  LIndex: Integer;
  LItem: TBCEditorCompletionProposalItems.TItem;
  LItems: TStrings;
  LPoint: TPoint;
begin
  Assert(FCompletionProposal.CompletionColumnIndex < FCompletionProposal.Columns.Count);

  LPoint := ClientToScreen(DisplayToClient(DisplayCaretPosition));
  Inc(LPoint.Y, LineHeight);

  FCompletionProposalPopupWindow := TBCEditorCompletionProposalPopupWindow.Create(Self);
  with FCompletionProposalPopupWindow do
  begin
    LControl := Self;
    while Assigned(LControl) and not (LControl is TCustomForm) do
      LControl := LControl.Parent;
    if LControl is TCustomForm then
      PopupParent := TCustomForm(LControl);
    OnCanceled := FOnCompletionProposalCanceled;
    OnSelected := FOnCompletionProposalSelected;
    Assign(FCompletionProposal);

    LItems := TStringList.Create;
    try
      if cpoParseItemsFromText in FCompletionProposal.Options then
        SplitTextIntoWords(LItems, False);
      if cpoAddHighlighterKeywords in FCompletionProposal.Options then
        AddHighlighterKeywords(LItems);
      Items.Clear;
      for LIndex := 0 to LItems.Count - 1 do
      begin
        LItem := Items.Add;
        LItem.Value := LItems[LIndex];
        { Add empty items for columns }
        for LColumnIndex := 1 to FCompletionProposal.Columns.Count - 1 do
          FCompletionProposal.Columns[LColumnIndex].Items.Add;
      end;
    finally
      LItems.Free;
    end;

    LCurrentInput := GetCurrentInput();
    LCanExecute := True;
    if Assigned(FOnBeforeCompletionProposalExecute) then
      FOnBeforeCompletionProposalExecute(Self, FCompletionProposal.Columns,
        LCurrentInput, LCanExecute);
    if LCanExecute then
    begin
      FAlwaysShowCaretBeforePopup := AlwaysShowCaret;
      AlwaysShowCaret := True;
      Execute(LCurrentInput, LPoint)
    end
    else
    begin
      FCompletionProposalPopupWindow.Free;
      FCompletionProposalPopupWindow := nil;
    end;
  end;
end;

procedure TCustomBCEditor.DoCopyToClipboard(const AText: string);
var
  ClipboardData: Pointer;
  Global: HGLOBAL;
  Opened: Boolean;
  Retry: Integer;
begin
  if (AText <> '') then
  begin
    Retry := 0;
    repeat
      Opened := OpenClipboard(Handle);
      if (not Opened) then
      begin
        Sleep(50);
        Inc(Retry);
      end;
    until (Opened or (Retry = 10));

    if (not Opened) then
      raise EClipboardException.CreateFmt(SCannotOpenClipboard, [SysErrorMessage(GetLastError)])
    else
      try
        EmptyClipboard();
        Global := GlobalAlloc(GMEM_MOVEABLE or GMEM_DDESHARE, (Length(AText) + 1) * SizeOf(Char));
        if (Global <> 0) then
        try
          ClipboardData := GlobalLock(Global);
          if (Assigned(ClipboardData)) then
          begin
            StrPCopy(ClipboardData, AText);
            SetClipboardData(CF_UNICODETEXT, Global);
          end;
        finally
          GlobalUnlock(Global);
        end;
      finally
        CloseClipboard();
      end;
  end;
end;

procedure TCustomBCEditor.DoCutToClipboard;
begin
  if not ReadOnly and SelectionAvailable then
  begin
    DoCopyToClipboard(SelText);
    SelText := '';
  end;
end;

procedure TCustomBCEditor.DoEditorBottom(const ACommand: TBCEditorCommand);
begin
  MoveCaretAndSelection(Lines.CaretPosition, Lines.EOFPosition, ACommand = ecSelectionEditorBottom);
end;

procedure TCustomBCEditor.DoEditorTop(const ACommand: TBCEditorCommand);
begin
  MoveCaretAndSelection(Lines.CaretPosition, Lines.BOFPosition, ACommand = ecSelectionEditorTop);
end;

procedure TCustomBCEditor.DoEndKey(const ASelectionCommand: Boolean);
var
  LNewCaretPosition: TBCEditorTextPosition;
begin
  if (Lines.CaretPosition.Line < Lines.Count) then
    LNewCaretPosition := Lines.EOLPosition[Lines.CaretPosition.Line]
  else
    LNewCaretPosition := TextPosition(0, Lines.CaretPosition.Line);
  MoveCaretAndSelection(Lines.CaretPosition, LNewCaretPosition, ASelectionCommand);
end;

procedure TCustomBCEditor.DoHomeKey(const ASelectionCommand: Boolean);
var
  LLeftSpaceCount: Integer;
  LNewCaretPosition: TBCEditorTextPosition;
begin
  LNewCaretPosition := Lines.CaretPosition;
  if (Lines.CaretPosition.Line < Lines.Count) then
  begin
    LLeftSpaceCount := LeftSpaceCount(Lines.Lines[LNewCaretPosition.Line].Text);
    if (LNewCaretPosition.Char > LLeftSpaceCount) then
      LNewCaretPosition.Char := LLeftSpaceCount
    else
      LNewCaretPosition.Char := 0;
  end
  else
    LNewCaretPosition := Lines.BOLPosition[LNewCaretPosition.Line];

  MoveCaretAndSelection(Lines.CaretPosition, LNewCaretPosition, ASelectionCommand);
end;

procedure TCustomBCEditor.DoImeStr(AData: Pointer);
begin
  DoInsertText(StrPas(PChar(AData)));
end;

procedure TCustomBCEditor.DoInsertText(const AText: string);
begin
  BeginUpdate();
  try
    if (SelectionAvailable) then
      SelText := AText
    else if ((FTextEntryMode = temOverwrite)
      and (Lines.CaretPosition.Line < Lines.Count)
      and (Lines.CaretPosition.Char < Length(Lines.Lines[Lines.CaretPosition.Line].Text))) then
    begin
      Lines.ReplaceText(Lines.CaretPosition, TextPosition(Lines.CaretPosition.Char + 1, Lines.CaretPosition.Line), AText);
      if (FSyncEdit.Active) then
        FSyncEdit.MoveEndPositionChar(Length(AText));
    end
    else
    begin
      Lines.InsertText(Lines.CaretPosition, AText);
      if (FSyncEdit.Active) then
        FSyncEdit.MoveEndPositionChar(Length(AText));
    end;

    if (FSyncEdit.Active) then
      DoSyncEdit();
  finally
    EndUpdate();
  end;
end;

procedure TCustomBCEditor.DoKeyPressW(var AMessage: TWMKey);
var
  LForm: TCustomForm;
  LKey: Char;
begin
  LKey := Char(AMessage.CharCode);

  if FCompletionProposal.Enabled and FCompletionProposal.Trigger.Enabled then
  begin
    if Pos(LKey, FCompletionProposal.Trigger.Chars) > 0 then
    begin
      FCompletionProposalTimer.Interval := FCompletionProposal.Trigger.Interval;
      FCompletionProposalTimer.Enabled := True;
    end
    else
      FCompletionProposalTimer.Enabled := False;
  end;

  LForm := GetParentForm(Self);
  if Assigned(LForm) and (LForm <> TWinControl(Self)) and LForm.KeyPreview and (LKey <= High(AnsiChar)) and
    TBCEditorAccessWinControl(LForm).DoKeyPress(AMessage) then
    Exit;

  if csNoStdEvents in ControlStyle then
    Exit;

  if Assigned(FOnKeyPressW) then
    FOnKeyPressW(Self, LKey);

  if LKey <> BCEDITOR_NONE_CHAR then
    KeyPressW(LKey);
end;

procedure TCustomBCEditor.DoLeftMarginAutoSize;
var
  LWidth: Integer;
begin
  if LeftMargin.Autosize then
  begin
    if LeftMargin.LineNumbers.Visible then
      LeftMargin.AutosizeDigitCount(Lines.Count);

    FPaintHelper.SetBaseFont(LeftMargin.Font);
    LWidth := LeftMargin.RealLeftMarginWidth(CharWidth);
    FLeftMarginCharWidth := CharWidth;
    FPaintHelper.SetBaseFont(Font);

    if LeftMargin.Width <> LWidth then
    begin
      LeftMargin.OnChange := nil;
      LeftMargin.Width := LWidth;
      LeftMargin.OnChange := LeftMarginChanged;
      if HandleAllocated then
      begin
        FTextWidth := ClientWidth - LeftMarginWidth;
        if WordWrap.Enabled then
        begin
          FRows.Clear();
          FMultiCaretPosition.Row := -1;
        end;
        UpdateScrollBars;
        Invalidate;
      end;
    end;
    FLeftMarginWidth := GetLeftMarginWidth();
  end;
end;

procedure TCustomBCEditor.DoLineBreak();
var
  LInsertText: string;
begin
  if (SelectionAvailable) then
    SelText := ''
  else if (Lines.CaretPosition.Line >= Lines.Count) then
    Lines.CaretPosition := Lines.BOLPosition[Lines.CaretPosition.Line + 1]
  else if (FTextEntryMode = temInsert) then
  begin
    LInsertText := Lines.LineBreak;
    if ((Lines.CaretPosition.Char > 0) and (eoAutoIndent in FOptions)) then
      LInsertText := LInsertText + ComputeIndentText(Min(Lines.CaretPosition.Char, LeftSpaceCount(Lines.Lines[Lines.CaretPosition.Line].Text, True)));
    Lines.InsertText(Lines.CaretPosition, LInsertText);
  end
  else
  begin
    if ((Lines.CaretPosition.Char > 0) and (eoAutoIndent in FOptions)) then
      Lines.CaretPosition := TextPosition(Min(Lines.CaretPosition.Char, LeftSpaceCount(Lines.Lines[Lines.CaretPosition.Line].Text, True)), Lines.CaretPosition.Line + 1)
    else
      Lines.CaretPosition := Lines.BOLPosition[Lines.CaretPosition.Line + 1];
  end;
end;

procedure TCustomBCEditor.DoLineComment();
var
  LBeginPosition: TBCEditorTextPosition;
  LComment: Integer;
  LCommentsCount: Integer;
  LCurrentComment: Integer;
  LEndPosition: TBCEditorTextPosition;
  LOpenToken: string;
begin
  LCommentsCount := Length(FHighlighter.Comments.LineComments);
  if (LCommentsCount > 0) then
  begin
    if (SelectionAvailable and (Lines.SelMode = smColumn)) then
      LBeginPosition := Min(Lines.SelBeginPosition, Lines.SelEndPosition)
    else
      LBeginPosition := Lines.BOLPosition[Min(Lines.SelBeginPosition, Lines.SelEndPosition).Line];
    LEndPosition := TextPosition(LBeginPosition.Char, Max(Lines.SelBeginPosition, Lines.SelEndPosition).Line);

    if (LBeginPosition.Line < Lines.Count) then
    begin
      LCurrentComment := -1;
      for LComment := LCommentsCount - 1 downto 0 do
        if (Copy(Lines.Lines[LBeginPosition.Line].Text, 1 + LBeginPosition.Char, Length(FHighlighter.Comments.LineComments[LComment])) = FHighlighter.Comments.LineComments[LComment]) then
          LCurrentComment := LComment;
      if (LCurrentComment < 0) then
        LOpenToken := ''
      else
        LOpenToken := FHighlighter.Comments.LineComments[LCurrentComment];

      Lines.BeginUpdate();
      try
        if (LCurrentComment >= 0) then
        begin
          Lines.DeleteIndent(LBeginPosition, LEndPosition,
            FHighlighter.Comments.LineComments[LCurrentComment], Lines.SelMode);
        end;

        if ((LCurrentComment < 0)
          or (LBeginPosition.Line <> LEndPosition.Line) and (LCurrentComment < LCommentsCount - 1)) then
        begin
          Inc(LCurrentComment);

          Lines.InsertIndent(LBeginPosition, LEndPosition,
            FHighlighter.Comments.LineComments[LCurrentComment], Lines.SelMode);
        end;

        if (not SelectionAvailable) then
        begin
          LBeginPosition.Char := 0;
          if (LEndPosition.Char > 0) then
            LEndPosition := Lines.EOLPosition[LEndPosition.Line];
          SetCaretAndSelection(LEndPosition, LBeginPosition, LEndPosition);
        end;
      finally
        Lines.EndUpdate();
      end;
    end;
  end;
end;

function TCustomBCEditor.DoMouseWheelDown(Shift: TShiftState; MousePos: TPoint): Boolean;
var
  LDisplayCaretPosition: TBCEditorDisplayPosition;
begin
  Result := inherited;

  if (not Result) then
  begin
    if (ssCtrl in Shift) then
      TopRow := TopRow + VisibleRows shr Ord(soHalfPage in FScroll.Options)
    else if (ssShift in Shift) then
    begin
      LDisplayCaretPosition := DisplayCaretPosition;
      Result := LDisplayCaretPosition.Row < Rows.Count - 2;
      if (Result) then
        DisplayCaretPosition := DisplayPosition(LDisplayCaretPosition.Column, Min(Rows.Count - 1, LDisplayCaretPosition.Row + Integer(FWheelScrollLines)));
    end
    else
      TopRow := TopRow + Integer(FWheelScrollLines);
    Result := True;
  end;
end;

function TCustomBCEditor.DoMouseWheelUp(Shift: TShiftState; MousePos: TPoint): Boolean;
var
  LDisplayCaretPosition: TBCEditorDisplayPosition;
begin
  Result := inherited;

  if (not Result) then
  begin
    if (ssCtrl in Shift) then
      TopRow := TopRow - VisibleRows shr Ord(soHalfPage in FScroll.Options)
    else if (ssShift in Shift) then
    begin
      LDisplayCaretPosition := DisplayCaretPosition;
      Result := LDisplayCaretPosition.Row > 0;
      if (Result) then
        DisplayCaretPosition := DisplayPosition(LDisplayCaretPosition.Column, Max(0, (LDisplayCaretPosition.Row - Integer(FWheelScrollLines))));
    end
    else
      TopRow := TopRow - Integer(FWheelScrollLines);
    Result := True;
  end;
end;

function TCustomBCEditor.DoOnCodeFoldingHintClick(const AClient: TPoint): Boolean;
var
  LCollapseMarkRect: TRect;
  LFoldRange: TBCEditorCodeFolding.TRanges.TRange;
  LRow: Integer;
begin
  LRow := ClientToDisplayRow(AClient.X, AClient.Y);

  if (LRow >= Rows.Count) then
    Result := False
  else
  begin
    Result := False;

    LFoldRange := CodeFoldingCollapsableFoldRangeForLine(Rows[LRow].Line);

    if Assigned(LFoldRange) and LFoldRange.Collapsed then
    begin
      LCollapseMarkRect := LFoldRange.CollapseMarkRect;
      OffsetRect(LCollapseMarkRect, -LeftMarginWidth, 0);

      if LCollapseMarkRect.Right > LeftMarginWidth then
        if PtInRect(LCollapseMarkRect, AClient) then
        begin
          FreeHintForm(FCodeFoldingHintForm);
          ExpandCodeFoldingRange(LFoldRange);
          Exit(True);
        end;
    end;
  end;
end;

procedure TCustomBCEditor.DoOnCommandProcessed(ACommand: TBCEditorCommand; const AChar: Char; AData: Pointer);

  function IsPreviousFoldTokenEndPreviousLine(const ALine: Integer): Boolean;
  var
    LIndex: Integer;
  begin
    LIndex := ALine;
    while (LIndex > 0) and not Assigned(FCodeFoldingRangeToLine[LIndex]) do
    begin
      if Assigned(FCodeFoldingRangeFromLine[LIndex]) then
        Exit(False);
      Dec(LIndex);
    end;
    Result := Assigned(FCodeFoldingRangeToLine[LIndex]) and FCodeFoldingRangeToLine[LIndex].RegionItem.TokenEndIsPreviousLine
  end;

begin
  if FCodeFolding.Visible then
  begin
    if FRescanCodeFolding or ((ACommand = ecChar) or (ACommand = ecBackspace) or (ACommand = ecDeleteChar) or
      (ACommand = ecLineBreak)) and IsKeywordAtPositionOrAfter(Lines.CaretPosition) or (ACommand = ecUndo) or
      (ACommand = ecRedo) then
      FRescanCodeFolding := True;
  end;

  if cfoShowIndentGuides in CodeFolding.Options then
    case ACommand of
      ecCut, ecPaste, ecUndo, ecRedo, ecBackspace, ecDeleteChar:
        CheckIfAtMatchingKeywords;
    end;

  if Assigned(FOnCommandProcessed) then
    FOnCommandProcessed(Self, ACommand, AChar, AData);

  if FCodeFolding.Visible then
    if ((ACommand = ecChar) or (ACommand = ecLineBreak)) and IsPreviousFoldTokenEndPreviousLine(Lines.CaretPosition.Line) then
      FRescanCodeFolding := True;
end;

procedure TCustomBCEditor.DoOnLeftMarginClick(AButton: TMouseButton; AShift: TShiftState; X, Y: Integer);
var
  LCodeFoldingRegion: Boolean;
  LFoldRange: TBCEditorCodeFolding.TRanges.TRange;
  LIndex: Integer;
  LLine: Integer;
  LMark: TBCEditorMark;
  LRow: Integer;
  LSelBeginPosition: TBCEditorTextPosition;
  LTextCaretPosition: TBCEditorTextPosition;
begin
  LRow := ClientToDisplayRow(X, Y);
  if (LRow < Rows.Count) then
  begin
    LSelBeginPosition := Lines.SelBeginPosition;
    LLine := Rows[LRow].Line;
    LTextCaretPosition := DisplayToText(DisplayPosition(0, LRow));

    Lines.BeginUpdate();
    try
      Lines.CaretPosition := LTextCaretPosition;
      if (ssShift in AShift) then
      begin
        Lines.SelBeginPosition := LSelBeginPosition;
        Lines.SelEndPosition := LTextCaretPosition;
      end;

      if (X < LeftMargin.MarksPanel.Width) and (Y div LineHeight <= DisplayCaretPosition.Row - TopRow) then
      begin
        if LeftMargin.Bookmarks.Visible and (bpoToggleBookmarkByClick in LeftMargin.MarksPanel.Options) then
          DoToggleBookmark
        else
        if LeftMargin.Marks.Visible and (bpoToggleMarkByClick in LeftMargin.MarksPanel.Options) then
          DoToggleMark
      end;

      LCodeFoldingRegion := (X >= LeftMarginWidth - FCodeFolding.GetWidth) and (X <= LeftMarginWidth);

      if (FCodeFolding.Visible and LCodeFoldingRegion) then
      begin
        LFoldRange := CodeFoldingCollapsableFoldRangeForLine(LLine);

        if Assigned(LFoldRange) then
        begin
          if LFoldRange.Collapsed then
            ExpandCodeFoldingRange(LFoldRange)
          else
            CollapseCodeFoldingRange(LFoldRange);
          Invalidate;
          Exit;
        end;
      end;

      if Assigned(FOnLeftMarginClick) then
        if LLine - 1 < Lines.Count then
        for LIndex := 0 to FMarkList.Count - 1 do
        begin
          LMark := FMarkList.Items[LIndex];
          if LMark.Line = LLine - 1 then
          begin
            FOnLeftMarginClick(Self, AButton, X, Y, LLine - 1, LMark);
            Break;
          end;
        end;
    finally
      Lines.EndUpdate();
    end;
  end;
end;

procedure TCustomBCEditor.DoOnPaint;
begin
  if Assigned(FOnPaint) then
  begin
    Canvas.Font.Assign(Font);
    Canvas.Brush.Color := FBackgroundColor;
    FOnPaint(Self, Canvas);
  end;
end;

procedure TCustomBCEditor.DoOnProcessCommand(var ACommand: TBCEditorCommand; var AChar: Char; AData: Pointer);
begin
  if ACommand < ecUserFirst then
  begin
    if Assigned(FOnProcessCommand) then
      FOnProcessCommand(Self, ACommand, AChar, AData);
  end
  else
  if Assigned(FOnProcessUserCommand) then
    FOnProcessUserCommand(Self, ACommand, AChar, AData);
end;

function TCustomBCEditor.DoOnReplaceText(const APattern, AReplaceText: string;
  APosition: TBCEditorTextPosition): TBCEditorReplaceAction;
begin
  if (not Assigned(FOnReplaceText)) then
    Result := raCancel
  else
    FOnReplaceText(Self, APattern, AReplaceText, APosition, Result);
end;

procedure TCustomBCEditor.DoOnSearchMapClick(AButton: TMouseButton; X, Y: Integer);
var
  LHeight: Double;
begin
  LHeight := ClientRect.Height / Max(Lines.Count, 1);
  GotoLineAndCenter(Round(Y / LHeight));
end;

procedure TCustomBCEditor.DoPageLeftOrRight(const ACommand: TBCEditorCommand);
var
  LVisibleChars: Integer;
begin
  LVisibleChars := GetVisibleChars(DisplayCaretPosition.Row);
  if ACommand in [ecPageLeft, ecSelectionPageLeft] then
    LVisibleChars := -LVisibleChars;
  MoveCaretHorizontally(LVisibleChars, ACommand in [ecSelectionPageLeft, ecSelectionPageRight]);
end;

procedure TCustomBCEditor.DoPageTopOrBottom(const ACommand: TBCEditorCommand);
var
  LRowCount: Integer;
begin
  case (ACommand) of
    ecPageTop,
    ecSelectionPageTop:
      LRowCount := 0;
    ecPageBottom,
    ecSelectionPageBottom:
      LRowCount := VisibleRows - 1;
    else raise ERangeError.Create('ACommand: ' + IntToStr(Ord(ACommand)));
  end;

  MoveCaretAndSelection(Lines.CaretPosition, DisplayToText(DisplayPosition(DisplayCaretPosition.Column, TopRow + LRowCount)), ACommand in [ecSelectionPageTop, ecSelectionPageBottom]);
end;

procedure TCustomBCEditor.DoPageUpOrDown(const ACommand: TBCEditorCommand);
var
  LRowCount: Integer;
begin
  case (ACommand) of
    ecPageUp,
    ecSelectionPageUp:
      LRowCount := - (VisibleRows shr Ord(soHalfPage in FScroll.Options));
    ecPageDown,
    ecSelectionPageDown:
      LRowCount := VisibleRows shr Ord(soHalfPage in FScroll.Options);
    else raise ERangeError.Create('ACommand: ' + IntToStr(Ord(ACommand)));
  end;

  TopRow := TopRow + LRowCount;
  MoveCaretVertically(LRowCount, ACommand in [ecSelectionPageUp, ecSelectionPageDown]);
end;

procedure TCustomBCEditor.DoPasteFromClipboard();
var
  ClipboardData: Pointer;
  Global: HGLOBAL;
  Opened: Boolean;
  Retry: Integer;
  Text: string;
begin
  if (IsClipboardFormatAvailable(CF_UNICODETEXT)) then
  begin
    Retry := 0;
    repeat
      Opened := OpenClipboard(Handle);
      if (not Opened) then
      begin
        Sleep(50);
        Inc(Retry);
      end;
    until (Opened or (Retry = 10));

    if (not Opened) then
      raise EClipboardException.CreateFmt(SCannotOpenClipboard, [SysErrorMessage(GetLastError)])
    else
    begin
      try
        Global := GetClipboardData(CF_UNICODETEXT);
        if (Global <> 0) then
        begin
          ClipboardData := GlobalLock(Global);
          if (Assigned(ClipboardData)) then
          begin
            SetString(Text, PChar(ClipboardData), GlobalSize(Global) div SizeOf(Text[1]));
            if ((Length(Text) > 0) and (Text[Length(Text)] = #0)) then
              SetLength(Text, Length(Text) - 1);
          end;
          GlobalUnlock(Global);
        end;
      finally
        CloseClipboard();
      end;

      Lines.BeginUpdate();
      try
        Lines.UndoGroupBreak();
        DoInsertText(Text);
      finally
        Lines.EndUpdate();
      end;
    end;
  end;
end;

procedure TCustomBCEditor.DoRedo();
begin
  Redo();
end;

function TCustomBCEditor.DoReplaceText(): Integer;
var
  LActionReplace: TBCEditorReplaceAction;
  LBeginPosition: TBCEditorTextPosition;
  LEndPosition: TBCEditorTextPosition;
  LFindLength: Integer;
  LFindEndPosition: TBCEditorTextPosition;
  LPromptReplace: Boolean;
  LSearch: TBCEditorLines.TSearch;
  LSearchPosition: TBCEditorTextPosition;
  LSearchResult: TSearchResult;
  LSuccess: Boolean;
begin
  if (Length(Replace.Pattern) = 0) then
    Result := 0
  else
  begin
    Result := 0;

    FSearchResults.Clear();
    ClearCodeFolding();

    LPromptReplace := (roPrompt in FReplace.Options) and Assigned(OnReplaceText);

    Include(FState, esReplace);
    if (LPromptReplace) then
      Lines.UndoList.BeginUpdate()
    else
      Lines.BeginUpdate();
    try
      LSearch := TBCEditorLines.TSearch.Create(Lines, Replace.BeginPosition, Replace.EndPosition,
        roCaseSensitive in Replace.Options, roWholeWordsOnly in Replace.Options, Replace.Engine = seRegularExpression, roBackwards in Replace.Options,
        Replace.Pattern, Replace.ReplaceText);

      if (roBackwards in FReplace.Options) then
        LSearchPosition := LEndPosition
      else
        LSearchPosition := LBeginPosition;

      if (roReplaceAll in Replace.Options) then
        LActionReplace := raReplaceAll
      else
        LActionReplace := raReplace;

      repeat
        LSuccess := False; // Debug 2017-04-06

        try
          LSuccess := LSearch.Find(LSearchPosition, LFindLength);
        except
          // Debug 2017-04-06
          on E: Exception do
            E.RaiseOuterException(EAssertionFailed.Create(
              'Backwards: ' + BoolToStr(roBackwards in FReplace.Options, True) + #13#10
              + 'BeginPosition: ' + Replace.BeginPosition.ToString() + #13#10
              + 'EndPosition: ' + Replace.EndPosition.ToString() + #13#10
              + 'LSearchPosition: ' + LSearchPosition.ToString() + #13#10
              + 'Lines.Count: ' + IntToStr(Lines.Count)));
        end;
        if (not LSuccess) then
          LActionReplace := raCancel;

        if ((LActionReplace <> raCancel) and LPromptReplace) then
        begin
          LFindEndPosition := Lines.CharIndexToPosition(LFindLength, LSearchPosition);
          SetCaretAndSelection(LFindEndPosition, LSearchPosition, LFindEndPosition);
          LActionReplace := DoOnReplaceText(Replace.Pattern, Replace.ReplaceText, LSearchResult.BeginPosition);
        end;
        if (LActionReplace in [raReplace, raReplaceAll]) then
        begin
          LSearch.Replace();
          Inc(Result);
        end;
      until (LActionReplace = raCancel);

      FSearchStatus := LSearch.ErrorMessage;
      LSearch.Free();
    finally
      if (LPromptReplace) then
        Lines.UndoList.EndUpdate()
      else
        Lines.EndUpdate();
      Exclude(FState, esReplace);

      InitCodeFolding();

      if (LPromptReplace and CanFocus) then
        SetFocus();
    end;
  end;
end;

procedure TCustomBCEditor.DoScroll(const ACommand: TBCEditorCommand);
var
  LDisplayCaretRow: Integer;
begin
  LDisplayCaretRow := DisplayCaretPosition.Row;
  if ((LDisplayCaretRow >= TopRow) and (LDisplayCaretRow < TopRow + VisibleRows)) then
    if ACommand = ecScrollUp then
    begin
      TopRow := TopRow - 1;
      if LDisplayCaretRow > TopRow + VisibleRows - 1 then
        MoveCaretVertically((TopRow + VisibleRows - 1) - LDisplayCaretRow, False);
    end
    else
    begin
      TopRow := TopRow + 1;
      if LDisplayCaretRow < TopRow then
        MoveCaretVertically(TopRow - LDisplayCaretRow, False);
    end;

  ScrollToCaret();
end;

function TCustomBCEditor.DoSearch(ABeginPosition, AEndPosition: TBCEditorTextPosition): Boolean;
var
  LFindLength: Integer;
  LPosition: TBCEditorTextPosition;
  LSearch: TBCEditorLines.TSearch;
  LSearchResult: TSearchResult;
begin
  if ((Length(Search.Pattern) = 0) or (ABeginPosition = AEndPosition)) then
  begin
    FSearchStatus := SBCEditorPatternIsEmpty;
    Result := False;
  end
  else
  begin
    FSearchStatus := '';
    FSearchResults.Clear();

    if (soBackwards in Search.Options) then
      LPosition := AEndPosition
    else
      LPosition := ABeginPosition;

    if ((soBackwards in Search.Options) and (LPosition = Lines.BOFPosition)) then
      Result := False
    else
    begin
      LSearch := TBCEditorLines.TSearch.Create(Lines, ABeginPosition, AEndPosition,
        soCaseSensitive in Search.Options, soWholeWordsOnly in Search.Options, Search.Engine = seRegularExpression, soBackwards in Search.Options,
        Search.Pattern, '');

      repeat
        if (soBackwards in Search.Options) then
          if (LPosition.Char > 0) then
            Dec(LPosition.Char)
          else
            LPosition := Lines.EOLPosition[LPosition.Line - 1];

        Result := LSearch.Find(LPosition, LFindLength);

        if (Result) then
        begin
          LSearchResult.BeginPosition := LPosition;
          LSearchResult.EndPosition := Lines.CharIndexToPosition(LFindLength, LSearchResult.BeginPosition);
          if (soBackwards in Search.Options) then
            FSearchResults.Insert(0, LSearchResult)
          else
            FSearchResults.Add(LSearchResult);
        end;

        if (Result and not (soBackwards in Search.Options)) then
          if (LPosition.Char < Length(Lines.Lines[LPosition.Line].Text)) then
            Inc(LPosition.Char)
          else
            LPosition := Lines.BOLPosition[LPosition.Line];
      until (not Result or (ABeginPosition >= AEndPosition));

      FSearchStatus := LSearch.ErrorMessage;
      LSearch.Free();

      Result := FSearchResults.Count > 0;
    end;
  end;
end;

function TCustomBCEditor.DoSearchFind(const First: Boolean; const Action: TSearchFind): Boolean;
begin
  if (not Assigned(FSearchFindDialog)) then
  begin
    FSearchFindDialog := TFindDialog.Create(Self);
    FSearchFindDialog.Options := FSearchFindDialog.Options - [frMatchCase, frWholeWord] + [frDown];
    if (soBackwards in Search.Options) then
      FSearchFindDialog.Options := FSearchFindDialog.Options - [frDown];
    if (soCaseSensitive in Search.Options) then
      FSearchFindDialog.Options := FSearchFindDialog.Options + [frMatchCase];
    if (soWholeWordsOnly in Search.Options) then
      FSearchFindDialog.Options := FSearchFindDialog.Options + [frWholeWord];
    FSearchFindDialog.OnFind := DoSearchFindExecute;
    FSearchFindDialog.OnClose := DoSearchFindClose;
  end;

  FHideSelectionBeforeSearch := HideSelection;
  HideSelection := False;

  FSearchFindDialog.Execute();

  Result := True;
end;

procedure TCustomBCEditor.DoSearchFindClose(Sender: TObject);
begin
  HideSelection := FHideSelectionBeforeSearch;
end;

procedure TCustomBCEditor.DoSearchFindExecute(Sender: TObject);
begin
  Search.Engine := seNormal;
  Search.Pattern :=  TFindDialog(Sender).FindText;
  if (frDown in TFindDialog(Sender).Options) then
    Search.Options := Search.Options - [soBackwards]
  else
    Search.Options := Search.Options + [soBackwards];
  if (frMatchCase in TFindDialog(Sender).Options) then
    Search.Options := Search.Options + [soCaseSensitive]
  else
    Search.Options := Search.Options - [soCaseSensitive];
  if (frWholeWord in TFindDialog(Sender).Options) then
    Search.Options := Search.Options + [soWholeWordsOnly]
  else
    Search.Options := Search.Options - [soWholeWordsOnly];

  FindNext();
end;

function TCustomBCEditor.DoSearchMatchNotFoundWrapAroundDialog: Boolean;
begin
  Result := MessageDialog(Format(SBCEditorSearchMatchNotFound, [Lines.LineBreak + Lines.LineBreak]), mtConfirmation, [mbYes, mbNo]) = mrYes;
end;

function TCustomBCEditor.DoSearchNext(APosition: TBCEditorTextPosition;
  out ASearchResult: TSearchResult; const WrapAround: Boolean = False): Boolean;
var
  LIndex: Integer;
  LLeft: Integer;
  LMiddle: Integer;
  LRight: Integer;
begin
  Result := FSearchResults.Count > 0;

  if (Result) then
  begin
    if (APosition <= FSearchResults[0].BeginPosition) then
      LIndex := 0
    else if (APosition <= FSearchResults[FSearchResults.Count - 1].BeginPosition) then
    begin
      LIndex := -1;

      LLeft := 0;
      LRight := FSearchResults.Count - 1;

      while (LIndex < 0) do
      begin
        LMiddle := (LLeft + LRight) div 2;
        if (FSearchResults[LMiddle].BeginPosition < APosition) then
          LLeft := LMiddle + 1
        else if ((FSearchResults[LMiddle - 1].BeginPosition < APosition)
          and (APosition <= FSearchResults[LMiddle].BeginPosition)) then
          LIndex := LMiddle
        else
          LRight := LMiddle - 1;
      end;
    end
    else if (WrapAround or DoSearchMatchNotFoundWrapAroundDialog) then
      LIndex := 0
    else
      LIndex := -1;

    Result := LIndex >= 0;

    if (Result) then
      ASearchResult := FSearchResults[LIndex];
  end;
end;

function TCustomBCEditor.DoSearchPrevious(APosition: TBCEditorTextPosition;
  out ASearchResult: TSearchResult; const WrapAround: Boolean = False): Boolean;
var
  LIndex: Integer;
  LLeft: Integer;
  LMiddle: Integer;
  LRight: Integer;
begin
  Result := FSearchResults.Count > 0;

  if (Result) then
  begin
    if (APosition > FSearchResults[FSearchResults.Count - 1].BeginPosition) then
      LIndex := FSearchResults.Count - 1
    else if (APosition > FSearchResults[0].BeginPosition) then
    begin
      LIndex := -1;

      LLeft := 0;
      LRight := FSearchResults.Count - 1;

      while (LIndex < 0) do
      begin
        LMiddle := (LLeft + LRight) div 2;
        if (FSearchResults[LMiddle].BeginPosition < APosition) then
          LLeft := LMiddle + 1
        else if ((FSearchResults[LMiddle - 1].BeginPosition < APosition)
          and (APosition <= FSearchResults[LMiddle].BeginPosition)) then
          LIndex := LMiddle - 1
        else
          LRight := LMiddle - 1;
      end;
    end
    else if (WrapAround or DoSearchMatchNotFoundWrapAroundDialog) then
      LIndex := FSearchResults.Count - 1
    else
      LIndex := -1;

    Result := LIndex >= 0;
    if (Result) then
      ASearchResult := FSearchResults[LIndex];
  end;
end;

function TCustomBCEditor.DoSearchReplace(const Action: TSearchReplace): Boolean;
begin
  if (not Assigned(FSearchReplaceDialog)) then
  begin
    FSearchReplaceDialog := TReplaceDialog.Create(Self);
    FSearchReplaceDialog.FindText := Replace.Pattern;
    FSearchReplaceDialog.ReplaceText := Replace.ReplaceText;
    FSearchReplaceDialog.Options := FSearchReplaceDialog.Options - [frMatchCase, frWholeWord, frReplaceAll] + [frDown];
    if (roBackwards in Replace.Options) then
      FSearchReplaceDialog.Options := FSearchReplaceDialog.Options - [frDown];
    if (roCaseSensitive in Replace.Options) then
      FSearchReplaceDialog.Options := FSearchReplaceDialog.Options + [frMatchCase];
    if (roReplaceAll in Replace.Options) then
      FSearchReplaceDialog.Options := FSearchReplaceDialog.Options + [frReplaceAll];
    if (roWholeWordsOnly in Replace.Options) then
      FSearchReplaceDialog.Options := FSearchReplaceDialog.Options + [frWholeWord];
    FSearchReplaceDialog.OnClose := DoSearchFindClose;
    FSearchReplaceDialog.OnFind := DoSearchReplaceFind;
    FSearchReplaceDialog.OnReplace := DoSearchReplaceExecute;
  end;

  FHideSelectionBeforeSearch := HideSelection;
  HideSelection := False;

  FSearchReplaceDialog.Execute();

  Result := True;
end;

procedure TCustomBCEditor.DoSearchReplaceExecute(Sender: TObject);
begin
  Replace.Engine := seNormal;
  Replace.Pattern := TReplaceDialog(Sender).FindText;
  Replace.ReplaceText := TReplaceDialog(Sender).ReplaceText;
  if (frMatchCase in TReplaceDialog(Sender).Options) then
    Replace.Options := Replace.Options + [roCaseSensitive]
  else
    Replace.Options := Replace.Options - [roCaseSensitive];
  if (frWholeWord in TReplaceDialog(Sender).Options) then
    Replace.Options := Replace.Options + [roWholeWordsOnly]
  else
    Replace.Options := Replace.Options - [roWholeWordsOnly];
  if (frReplaceAll in TReplaceDialog(Sender).Options) then
    Replace.Options := Replace.Options + [roReplaceAll]
  else
    Replace.Options := Replace.Options - [roReplaceAll];

  if (SelectionAvailable) then
  begin
    Replace.BeginPosition := Lines.SelBeginPosition;
    Replace.EndPosition := Lines.EOFPosition;
  end
  else
  begin
    Replace.BeginPosition := Lines.CaretPosition;
    Replace.EndPosition := Lines.EOFPosition;
  end;

  DoReplaceText();
end;

procedure TCustomBCEditor.DoSearchReplaceFind(Sender: TObject);
begin
  Search.Engine := seNormal;
  if (frDown in TReplaceDialog(Sender).Options) then
    Search.Options := Search.Options - [soBackwards]
  else
    Search.Options := Search.Options + [soBackwards];
  if (frMatchCase in TReplaceDialog(Sender).Options) then
    Search.Options := Search.Options + [soCaseSensitive]
  else
    Search.Options := Search.Options - [soCaseSensitive];
  if (frWholeWord in TReplaceDialog(Sender).Options) then
    Search.Options := Search.Options + [soWholeWordsOnly]
  else
    Search.Options := Search.Options - [soWholeWordsOnly];
  Search.Pattern := TReplaceDialog(Sender).FindText;

  FindNext();
end;

procedure TCustomBCEditor.DoSearchStringNotFoundDialog;
begin
  MessageDialog(Format(SBCEditorSearchStringNotFound, [Search.Pattern]), mtInformation, [mbOK]);
end;

procedure TCustomBCEditor.DoSetBookmark(const ACommand: TBCEditorCommand; AData: Pointer);
var
  LIndex: Integer;
  LTextCaretPosition: TBCEditorTextPosition;
begin
  LTextCaretPosition := Lines.CaretPosition;
  LIndex := ACommand - ecSetBookmark1;
  if Assigned(AData) then
    LTextCaretPosition := TBCEditorTextPosition(AData^);
  if not DeleteBookmark(LTextCaretPosition.Line, LIndex) then
    SetBookmark(LIndex, LTextCaretPosition);
end;

procedure TCustomBCEditor.DoShiftTabKey;
var
  LNewCaretPosition: TBCEditorTextPosition;
  LTabWidth: Integer;
begin
  if ((toSelectedBlockIndent in FTabs.Options) and SelectionAvailable) then
    DoBlockIndent(ecBlockUnindent)
  else
  begin
    if (toTabsToSpaces in FTabs.Options) then
      LTabWidth := FTabs.Width
    else
      LTabWidth := 1;
    LNewCaretPosition := TextPosition(Max(0, Lines.CaretPosition.Char - LTabWidth + 1), Lines.CaretPosition.Line);

    if ((LNewCaretPosition <> Lines.CaretPosition)
      and (Copy(Lines.Lines[Lines.CaretPosition.Line].Text, 1 + LNewCaretPosition.Char, LTabWidth) = BCEDITOR_TAB_CHAR)) then
      Lines.DeleteText(LNewCaretPosition, Lines.CaretPosition);
  end;
end;

procedure TCustomBCEditor.DoSyncEdit;
var
  LDifference: Integer;
  LEditText: string;
  LIndex1: Integer;
  LIndex2: Integer;
  LTextBeginPosition: TBCEditorTextPosition;
  LTextCaretPosition: TBCEditorTextPosition;
  LTextEndPosition: TBCEditorTextPosition;
  LTextSameLinePosition: TBCEditorTextPosition;
begin
  LTextCaretPosition := Lines.CaretPosition;

  Lines.BeginUpdate();
  try
    LEditText := Copy(Lines.Lines[FSyncEdit.EditBeginPosition.Line].Text, 1 + FSyncEdit.EditBeginPosition.Char,
      FSyncEdit.EditEndPosition.Char - FSyncEdit.EditBeginPosition.Char);
    LDifference := Length(LEditText) - FSyncEdit.EditWidth;
    for LIndex1 := 0 to FSyncEdit.SyncItems.Count - 1 do
    begin
      LTextBeginPosition := PBCEditorTextPosition(FSyncEdit.SyncItems.Items[LIndex1])^;

      if (LTextBeginPosition.Line = FSyncEdit.EditBeginPosition.Line) and
        (LTextBeginPosition.Char < FSyncEdit.EditBeginPosition.Char) then
      begin
        FSyncEdit.MoveBeginPositionChar(LDifference);
        FSyncEdit.MoveEndPositionChar(LDifference);
        Inc(LTextCaretPosition.Char, LDifference);
      end;

      if (LTextBeginPosition.Line = FSyncEdit.EditBeginPosition.Line) and
        (LTextBeginPosition.Char > FSyncEdit.EditBeginPosition.Char) then
      begin
        Inc(LTextBeginPosition.Char, LDifference);
        PBCEditorTextPosition(FSyncEdit.SyncItems.Items[LIndex1])^.Char := LTextBeginPosition.Char;
      end;

      LTextEndPosition := LTextBeginPosition;
      Inc(LTextEndPosition.Char, FSyncEdit.EditWidth);

      Lines.DeleteText(LTextBeginPosition, LTextEndPosition);
      Lines.InsertText(LTextBeginPosition, LEditText);

      LIndex2 := LIndex1 + 1;
      if LIndex2 < FSyncEdit.SyncItems.Count then
      begin
        LTextSameLinePosition := PBCEditorTextPosition(FSyncEdit.SyncItems.Items[LIndex2])^;

        while (LIndex2 < FSyncEdit.SyncItems.Count) and (LTextSameLinePosition.Line = LTextBeginPosition.Line) do
        begin
          PBCEditorTextPosition(FSyncEdit.SyncItems.Items[LIndex2])^.Char := LTextSameLinePosition.Char + LDifference;

          Inc(LIndex2);
          if LIndex2 < FSyncEdit.SyncItems.Count then
            LTextSameLinePosition := PBCEditorTextPosition(FSyncEdit.SyncItems.Items[LIndex2])^;
        end;
      end;
    end;
    FSyncEdit.EditWidth := FSyncEdit.EditEndPosition.Char - FSyncEdit.EditBeginPosition.Char;
    Lines.CaretPosition := LTextCaretPosition;
  finally
    Lines.EndUpdate();
  end;
end;

procedure TCustomBCEditor.DoTabKey;
var
  LChangeScrollPastEndOfLine: Boolean;
  LCharCount: Integer;
  LDisplayCaretPosition: TBCEditorDisplayPosition;
  LLengthAfterLine: Integer;
  LPreviousLine: Integer;
  LPreviousLineCharCount: Integer;
  LTabText: string;
  LTextCaretPosition: TBCEditorTextPosition;
begin
  if ((Lines.SelBeginPosition.Line <> Lines.SelEndPosition.Line)
    and (toSelectedBlockIndent in FTabs.Options)) then
    DoBlockIndent(ecBlockIndent)
  else if (SelectionAvailable or
    (Lines.CaretPosition.Line >= Lines.Count)) then
  begin
    if (not (toTabsToSpaces in FTabs.Options)) then
    begin
      LTabText := StringOfChar(BCEDITOR_TAB_CHAR, FTabs.Width div FTabs.Width);
      LTabText := LTabText + StringOfChar(BCEDITOR_TAB_CHAR, FTabs.Width mod FTabs.Width);
    end
    else if (toColumns in FTabs.Options) then
      LTabText := StringOfChar(BCEDITOR_SPACE_CHAR, FTabs.Width - (DisplayCaretPosition.Column - 1) mod FTabs.Width)
    else
      LTabText := StringOfChar(BCEDITOR_SPACE_CHAR, FTabs.Width);
    DoInsertText(LTabText);
  end
  else
  begin
    Lines.BeginUpdate();
    try
      LTextCaretPosition := Lines.CaretPosition;

      LDisplayCaretPosition := DisplayCaretPosition;
      LLengthAfterLine := Max(0, LDisplayCaretPosition.Column - Lines.ExpandedStringLengths[LTextCaretPosition.Line]);

      if LLengthAfterLine > 1 then
        LCharCount := LLengthAfterLine
      else
        LCharCount := FTabs.Width;

      if toPreviousLineIndent in FTabs.Options then
        if Trim(Lines.Lines[LTextCaretPosition.Line].Text) = '' then
        begin
          LPreviousLine := LTextCaretPosition.Line - 1;
          while (LPreviousLine >= 0) and (Lines.Lines[LPreviousLine].Text = '') do
            Dec(LPreviousLine);
          LPreviousLineCharCount := LeftSpaceCount(Lines.Lines[LPreviousLine].Text, True);
          if LPreviousLineCharCount > LTextCaretPosition.Char + 1 then
            LCharCount := LPreviousLineCharCount - LeftSpaceCount(Lines.Lines[LTextCaretPosition.Line].Text, True)
        end;

      if LLengthAfterLine > 1 then
        LTextCaretPosition := Lines.BOLPosition[LTextCaretPosition.Line];

      if (not (toTabsToSpaces in FTabs.Options)) then
      begin
        LTabText := StringOfChar(BCEDITOR_TAB_CHAR, LCharCount div FTabs.Width);
        LTabText := LTabText + StringOfChar(BCEDITOR_TAB_CHAR, LCharCount mod FTabs.Width);
      end
      else if (toColumns in FTabs.Options) then
        LTabText := StringOfChar(BCEDITOR_SPACE_CHAR, LCharCount - (LDisplayCaretPosition.Column - 1) mod FTabs.Width)
      else
        LTabText := StringOfChar(BCEDITOR_SPACE_CHAR, LCharCount);

      if FTextEntryMode = temInsert then
        Lines.InsertText(LTextCaretPosition, LTabText);

      LChangeScrollPastEndOfLine := not (soPastEndOfLine in FScroll.Options);
      try
        if LChangeScrollPastEndOfLine then
          FScroll.SetOption(soPastEndOfLine, True);
        if FTextEntryMode = temOverwrite then
          LTabText := StringReplace(LTabText, BCEDITOR_TAB_CHAR, StringOfChar(BCEDITOR_SPACE_CHAR, FTabs.Width),
            [rfReplaceAll]);
        Lines.CaretPosition := TextPosition(LTextCaretPosition.Char + Length(LTabText), Lines.CaretPosition.Line);
      finally
        if LChangeScrollPastEndOfLine then
          FScroll.SetOption(soPastEndOfLine, False);
      end;
    finally
      Lines.EndUpdate();
    end;
  end;
end;

procedure TCustomBCEditor.DoToggleBookmark;
var
  LIndex: Integer;
  LMark: TBCEditorMark;
  LMarkIndex: Integer;
begin
  LMarkIndex := 0;
  for LIndex := 0 to FBookmarkList.Count - 1 do
  begin
    LMark := FBookmarkList.Items[LIndex];
    if LMark.Line = Lines.CaretPosition.Line then
    begin
      DeleteBookmark(LMark);
      Exit;
    end;
    if LMark.Index > LMarkIndex then
      LMarkIndex := LMark.Index;
  end;
  LMarkIndex := Max(BCEDITOR_BOOKMARK_IMAGE_COUNT, LMarkIndex + 1);
  SetBookmark(LMarkIndex, Lines.CaretPosition);
end;

procedure TCustomBCEditor.DoToggleMark;
var
  LIndex: Integer;
  LMark: TBCEditorMark;
  LMarkIndex: Integer;
begin
  LMarkIndex := 0;
  for LIndex := 0 to FMarkList.Count - 1 do
  begin
    LMark := FMarkList.Items[LIndex];
    if LMark.Line = Lines.CaretPosition.Line then
    begin
      DeleteMark(LMark);
      Exit;
    end;
    if LMark.Index > LMarkIndex then
      LMarkIndex := LMark.Index;
  end;
  Inc(LMarkIndex);
  SetMark(LMarkIndex, Lines.CaretPosition, LeftMargin.Marks.DefaultImageIndex);
end;

procedure TCustomBCEditor.DoToggleSelectedCase(const ACommand: TBCEditorCommand);

  function ToggleCase(const AValue: string): string;
  var
    LIndex: Integer;
    LValue: string;
  begin
    Result := AnsiUpperCase(AValue);
    LValue := AnsiLowerCase(AValue);
    for LIndex := 1 to Length(AValue) do
      if Result[LIndex] = AValue[LIndex] then
        Result[LIndex] := LValue[LIndex];
  end;

  function TitleCase(const AValue: string): string;
  var
    LIndex: Integer;
    LLength: Integer;
    LValue: string;
  begin
    Result := '';
    LIndex := 1;
    LLength := Length(AValue);
    while LIndex <= LLength do
    begin
      LValue := AValue[LIndex];
      if LIndex > 1 then
      begin
        if AValue[LIndex - 1] = ' ' then
          LValue := AnsiUpperCase(LValue)
        else
          LValue := AnsiLowerCase(LValue);
      end
      else
        LValue := AnsiUpperCase(LValue);
      Result := Result + LValue;
      Inc(LIndex);
    end;
  end;

var
  LSelectedText: string;
begin
  if (SelectionAvailable) then
  begin
    LSelectedText := SelText;
    case (ACommand) of
      ecUpperCase,
      ecUpperCaseBlock:
        SelText := AnsiUpperCase(LSelectedText);
      ecLowerCase,
      ecLowerCaseBlock:
        SelText := AnsiLowerCase(LSelectedText);
      ecAlternatingCase,
      ecAlternatingCaseBlock:
        SelText := ToggleCase(LSelectedText);
      ecSentenceCase:
        SelText := AnsiUpperCase(LSelectedText[1]) +
          AnsiLowerCase(Copy(LSelectedText, 2, Length(LSelectedText)));
      ecTitleCase:
        SelText := TitleCase(LSelectedText);
      else ERangeError.Create('ACommand: ' + IntToStr(Ord(ACommand)));
    end;
  end;
end;

procedure TCustomBCEditor.DoTokenInfo;

  function MouseInTokenInfoRect: Boolean;
  var
    LPoint: TPoint;
    LPointLeftTop: TPoint;
    LPointRightBottom: TPoint;
    LRect: TRect;
  begin
    GetCursorPos(LPoint);
    LRect := FTokenInfoTokenRect;
    Result := PtInRect(LRect, LPoint);
    if not Result then
    begin
      with FTokenInfoPopupWindow.ClientRect do
      begin
        LPointLeftTop := Point(Left, Top);
        LPointRightBottom := Point(Left + Width, Top + Height);
      end;
      with FTokenInfoPopupWindow do
      begin
        LPointLeftTop := ClientToScreen(LPointLeftTop);
        LPointRightBottom := ClientToScreen(LPointRightBottom);
      end;
      LRect := Rect(LPointLeftTop.X, LPointLeftTop.Y, LPointRightBottom.X, LPointRightBottom.Y);
      Result := PtInRect(LRect, LPoint);
    end;
  end;

begin
  if Assigned(FTokenInfoPopupWindow) then
  begin
    if not MouseInTokenInfoRect then
      FreeTokenInfoPopupWindow;
  end
  else
  with FTokenInfoTimer do
  begin
    Enabled := False;
    Interval := FTokenInfo.DelayInterval;
    Enabled := True;
  end;
end;

procedure TCustomBCEditor.DoTripleClick();
begin
  Lines.BeginUpdate();
  try
    Lines.SelBeginPosition := Lines.BOLPosition[Lines.CaretPosition.Line];
    Lines.SelEndPosition := Lines.EOLPosition[Lines.CaretPosition.Line];
  finally
    Lines.EndUpdate();
  end;

  FLastDblClick := 0;
end;

procedure TCustomBCEditor.DoUndo();
begin
  Undo();
end;

procedure TCustomBCEditor.DoWordLeft(const ACommand: TBCEditorCommand);
var
  LNewCaretPosition: TBCEditorTextPosition;
begin
  if ((Lines.CaretPosition.Line = 0) and (Lines.Count = 0)) then
    Lines.CaretPosition := Lines.BOFPosition
  else if (Lines.CaretPosition.Line < Lines.Count) then
  begin
    LNewCaretPosition := Lines.CaretPosition;
    if (LNewCaretPosition.Line >= Lines.Count) then
      LNewCaretPosition := Lines.EOLPosition[Lines.Count - 1];
    if ((LNewCaretPosition.Char = 0)
      or (LNewCaretPosition.Char >= Length(Lines.Lines[LNewCaretPosition.Line].Text))
      or IsWordBreakChar(Lines.Lines[LNewCaretPosition.Line].Text[1 + LNewCaretPosition.Char - 1])) then
      LNewCaretPosition := PreviousWordPosition(LNewCaretPosition);
    if ((LNewCaretPosition.Char > 0)
      and ((LNewCaretPosition = Lines.CaretPosition) or (LNewCaretPosition.Char < Length(Lines.Lines[LNewCaretPosition.Line].Text)))
      and not IsWordBreakChar(Lines.Lines[LNewCaretPosition.Line].Text[1 + LNewCaretPosition.Char - 1])) then
      LNewCaretPosition := WordBegin(LNewCaretPosition);
    MoveCaretAndSelection(Lines.CaretPosition, LNewCaretPosition, ACommand = ecSelectionWordLeft);
  end
  else if (Lines.CaretPosition.Line = Lines.Count) then
    Lines.CaretPosition := Lines.EOLPosition[Lines.CaretPosition.Line - 1]
  else
    Lines.CaretPosition := Lines.BOLPosition[Lines.CaretPosition.Line - 1];
end;

procedure TCustomBCEditor.DoWordRight(const ACommand: TBCEditorCommand);
var
  LNewCaretPosition: TBCEditorTextPosition;
begin
  LNewCaretPosition := Lines.CaretPosition;
  if (LNewCaretPosition.Line < Lines.Count) then
  begin
    if ((LNewCaretPosition.Char < Length(Lines.Lines[LNewCaretPosition.Line].Text))
      and not IsWordBreakChar(Lines.Char[LNewCaretPosition])) then
    begin
      LNewCaretPosition := WordEnd();
      Inc(LNewCaretPosition.Char);
      while ((LNewCaretPosition.Char < Length(Lines.Lines[LNewCaretPosition.Line].Text))) and IsEmptyChar(Lines.Char[LNewCaretPosition]) do
        Inc(LNewCaretPosition.Char);
    end;
    if ((LNewCaretPosition.Char >= Length(Lines.Lines[LNewCaretPosition.Line].Text))
      or IsWordBreakChar(Lines.Char[LNewCaretPosition])) then
      LNewCaretPosition := NextWordPosition(LNewCaretPosition);
    MoveCaretAndSelection(Lines.CaretPosition, LNewCaretPosition, ACommand = ecSelectionWordRight);
  end;
end;

procedure TCustomBCEditor.DragCanceled;
begin
  FScrollTimer.Enabled := False;
  Exclude(FState, esDragging);
  inherited;
end;

procedure TCustomBCEditor.DragDrop(ASource: TObject; X, Y: Integer);
var
  LChangeScrollPastEndOfLine: Boolean;
  LDoDrop: Boolean;
  LDragDropText: string;
  LDropAfter: Boolean;
  LDropMove: Boolean;
  LNewCaretPosition: TBCEditorTextPosition;
begin
  if (ReadOnly or not (ASource is TCustomBCEditor) or not TCustomBCEditor(ASource).SelectionAvailable) then
    inherited
  else
  begin
    BeginUpdate();

    Lines.BeginUpdate();
    try
      Lines.UndoGroupBreak();

      inherited;

      LNewCaretPosition := TextPosition(ClientToText(X, Y));
      Lines.CaretPosition := LNewCaretPosition;

      if ASource <> Self then
      begin
        LDropMove := GetKeyState(VK_SHIFT) < 0;
        LDoDrop := True;
        LDropAfter := False;
      end
      else
      begin
        LDropMove := GetKeyState(VK_CONTROL) >= 0;
        Lines.SelEndPosition := SelectionEndPosition;
        LDropAfter := (LNewCaretPosition.Line > Lines.SelEndPosition.Line) or
          ((LNewCaretPosition.Line = Lines.SelEndPosition.Line) and
          ((LNewCaretPosition.Char > Lines.SelEndPosition.Char) or
          ((not LDropMove) and (LNewCaretPosition.Char = Lines.SelEndPosition.Char))));
        LDoDrop := LDropAfter or (LNewCaretPosition.Line < Lines.SelBeginPosition.Line) or
          ((LNewCaretPosition.Line = Lines.SelBeginPosition.Line) and
          ((LNewCaretPosition.Char < Lines.SelBeginPosition.Char) or
          ((not LDropMove) and (LNewCaretPosition.Char = Lines.SelBeginPosition.Char))));
      end;
      if LDoDrop then
      begin
        Lines.BeginUpdate();
        try
          LDragDropText := TCustomBCEditor(ASource).SelText;

          if LDropMove then
          begin
            if ASource <> Self then
              TCustomBCEditor(ASource).SelText := ''
            else
            begin
              SelText := '';

              if LDropAfter and (LNewCaretPosition.Line = Lines.SelEndPosition.Line) then
                Dec(LNewCaretPosition.Char, Lines.SelEndPosition.Char - Lines.SelBeginPosition.Char);
              if LDropAfter and (Lines.SelEndPosition.Line > Lines.SelBeginPosition.Line) then
                Dec(LNewCaretPosition.Line, Lines.SelEndPosition.Line - Lines.SelBeginPosition.Line);
            end;
          end;

          LChangeScrollPastEndOfLine := not (soPastEndOfLine in FScroll.Options);
          try
            if LChangeScrollPastEndOfLine then
              FScroll.SetOption(soPastEndOfLine, True);
            Lines.InsertText(LNewCaretPosition, LDragDropText);
          finally
            if LChangeScrollPastEndOfLine then
              FScroll.SetOption(soPastEndOfLine, False);
          end;

          CommandProcessor(ecSelectionGotoXY, BCEDITOR_NONE_CHAR, @LNewCaretPosition);
        finally
          Lines.EndUpdate();
        end;
      end;
    finally
      Lines.EndUpdate();
    end;
    EndUpdate();

    Exclude(FState, esDragging);
  end;
end;

procedure TCustomBCEditor.DragOver(ASource: TObject; X, Y: Integer; AState: TDragState; var AAccept: Boolean);
var
  LColumn: Integer;
  LDisplayPosition: TBCEditorDisplayPosition;
  LOldTextCaretPosition: TBCEditorTextPosition;
begin
  inherited;

  if (ASource is TCustomBCEditor) and not ReadOnly then
  begin
    AAccept := True;

    if Dragging then
    begin
      if AState = dsDragLeave then
        Lines.CaretPosition := TextPosition(ClientToText(FMouseDownX, FMouseDownY))
      else
      begin
        LOldTextCaretPosition := Lines.CaretPosition;
        LDisplayPosition := ClientToDisplay(X, Y);
        LColumn := HorzTextPos div CharWidth;
        LDisplayPosition.Row := MinMax(LDisplayPosition.Row, TopRow, TopRow + VisibleRows - 1);
        LDisplayPosition.Column := MinMax(LDisplayPosition.Column, LColumn, LColumn + GetVisibleChars(LDisplayPosition.Row) - 1);
        Lines.CaretPosition := DisplayToText(LDisplayPosition);
        ComputeScroll(Point(X, Y));
        if (LOldTextCaretPosition <> Lines.CaretPosition) then
          Invalidate;
      end;
    end
    else
      Lines.CaretPosition := TextPosition(ClientToText(X, Y));
  end;
end;

procedure TCustomBCEditor.DrawCaret;
var
  LDisplayPosition: TBCEditorDisplayPosition;
  LIndex: Integer;
begin
  if (not SelectionAvailable) then
    if Assigned(FMultiCarets) and (FMultiCarets.Count > 0) then
      for LIndex := 0 to FMultiCarets.Count - 1 do
      begin
        LDisplayPosition := FMultiCarets[LIndex];
        if ((TopRow <= LDisplayPosition.Row) and (LDisplayPosition.Row <= TopRow + VisibleRows)) then
          PaintCaretBlock(LDisplayPosition);
      end
    else
      PaintCaretBlock(DisplayCaretPosition);
end;

procedure TCustomBCEditor.EndUndoBlock;
begin
  Lines.EndUpdate();
end;

procedure TCustomBCEditor.EndUpdate();
begin
  Dec(FUpdateCount);
  if (FUpdateCount = 0) then SetUpdateState(False);
end;

procedure TCustomBCEditor.ExpandCodeFoldingLevel(const AFirstLevel: Integer; const ALastLevel: Integer);
var
  LFirstLine: Integer;
  LLastLine: Integer;
  LLevel: Integer;
  LLine: Integer;
  LRange: TBCEditorCodeFolding.TRanges.TRange;
  LRangeLevel: Integer;
begin
  if (SelectionAvailable) then
  begin
    LFirstLine := Lines.SelBeginPosition.Line;
    LLastLine := Lines.SelEndPosition.Line;
  end
  else
  begin
    LFirstLine := 0;
    LLastLine := Lines.Count - 1;
  end;

  BeginUpdate();

  LLevel := -1;
  for LLine := LFirstLine to LLastLine do
  begin
    LRange := FCodeFoldingRangeFromLine[LLine];
    if (Assigned(LRange)) then
    begin
      if LLevel = -1 then
        LLevel := LRange.FoldRangeLevel;
      LRangeLevel := LRange.FoldRangeLevel - LLevel;
      if ((AFirstLevel <= LRangeLevel) and (LRangeLevel <= ALastLevel)
        and LRange.Collapsed) then
        ExpandCodeFoldingRange(LRange);
    end;
  end;

  EndUpdate();
end;

function TCustomBCEditor.ExpandCodeFoldingLines(const AFirstLine: Integer = -1; const ALastLine: Integer = -1): Integer;
var
  LFirstLine: Integer;
  LLastLine: Integer;
  LLine: Integer;
  LRange: TBCEditorCodeFolding.TRanges.TRange;
begin
  if (AFirstLine >= 0) then
    LFirstLine := AFirstLine
  else
    LFirstLine := 0;
  if (ALastLine >= -1) then
    LLastLine := ALastLine
  else if (AFirstLine >= 0) then
    LLastLine := AFirstLine
  else
    LLastLine := Lines.Count - 1;

  Include(FState, esRowsUpdating);
  try
    Result := 0;
    for LLine := LFirstLine to LLastLine do
    begin
      LRange := FCodeFoldingRangeFromLine[LLine];
      if (Assigned(LRange) and LRange.Collapsed) then
      begin
        ExpandCodeFoldingRange(LRange);
        Inc(Result);
      end;
    end;
  finally
    Exclude(FState, esRowsUpdating);
  end;
end;

procedure TCustomBCEditor.ExpandCodeFoldingRange(const ARange: TBCEditorCodeFolding.TRanges.TRange);
var
  LLine: Integer;
begin
  if (ARange.Collapsed) then
  begin
    ARange.Collapsed := False;
    ARange.SetParentCollapsedOfSubCodeFoldingRanges(False, ARange.FoldRangeLevel);

    for LLine := ARange.FirstLine + 1 to ARange.LastLine do
      InsertLineIntoRows(LLine, False);
  end;
end;

function TCustomBCEditor.ExecuteAction(Action: TBasicAction): Boolean;
begin
  Result := True;

  if (Action is TEditCut) then
    ExecuteCommand(ecCut, #0, nil)
  else if (Action is TEditCopy) then
    ExecuteCommand(ecCopy, #0, nil)
  else if (Action is TEditPaste) then
    ExecuteCommand(ecPaste, #0, nil)
  else if (Action is TEditDelete) then
    ExecuteCommand(ecBackspace, #0, nil)
  else if (Action is TEditSelectAll) then
    ExecuteCommand(ecSelectAll, #0, nil)
  else if (Action is TEditUndo) then
    ExecuteCommand(ecUndo, #0, nil)
  else if (Action is TSearchFindFirst) then
    DoSearchFind(True, TSearchFindFirst(Action))
  else if (Action is TSearchFind) then
    DoSearchFind(Search.Pattern = '', TSearchFind(Action))
  else if (Action is TSearchReplace) then
    DoSearchReplace(TSearchReplace(Action))
  else if (Action is TSearchFindNext) then
    ExecuteCommand(ecSearchNext, #0, nil)
  else
    Result := inherited;
end;

procedure TCustomBCEditor.ExecuteCommand(ACommand: TBCEditorCommand; AChar: Char; AData: Pointer);
begin
  case ACommand of
    ecLeft, ecSelectionLeft:
      if not FSyncEdit.Active or FSyncEdit.Active and (Lines.CaretPosition.Char > FSyncEdit.EditBeginPosition.Char) then
        MoveCaretHorizontally(-1, ACommand = ecSelectionLeft);
    ecRight, ecSelectionRight:
      if not FSyncEdit.Active or FSyncEdit.Active and (Lines.CaretPosition.Char < FSyncEdit.EditEndPosition.Char) then
        MoveCaretHorizontally(1, ACommand = ecSelectionRight);
    ecPageLeft, ecSelectionPageLeft:
      DoPageLeftOrRight(ACommand);
    ecLineBegin, ecSelectionLineBegin:
      DoHomeKey(ACommand = ecSelectionLineBegin);
    ecLineEnd, ecSelectionLineEnd:
      DoEndKey(ACommand = ecSelectionLineEnd);
    ecUp, ecSelectionUp:
      MoveCaretVertically(-1, ACommand = ecSelectionUp);
    ecDown, ecSelectionDown:
      MoveCaretVertically(1, ACommand = ecSelectionDown);
    ecPageUp, ecSelectionPageUp, ecPageDown, ecSelectionPageDown:
      DoPageUpOrDown(ACommand);
    ecPageTop, ecSelectionPageTop, ecPageBottom, ecSelectionPageBottom:
      DoPageTopOrBottom(ACommand);
    ecEditorTop, ecSelectionEditorTop:
      DoEditorTop(ACommand);
    ecEditorBottom, ecSelectionEditorBottom:
      DoEditorBottom(ACommand);
    ecGotoXY, ecSelectionGotoXY:
      if Assigned(AData) then
        MoveCaretAndSelection(Lines.CaretPosition, TBCEditorTextPosition(AData^), ACommand = ecSelectionGotoXY);
    ecToggleBookmark:
      DoToggleBookmark;
    ecGotoNextBookmark:
      GotoNextBookmark;
    ecGotoPreviousBookmark:
      GotoPreviousBookmark;
    ecGotoBookmark1 .. ecGotoBookmark9:
      if LeftMargin.Bookmarks.ShortCuts then
        GotoBookmark(ACommand - ecGotoBookmark1);
    ecSetBookmark1 .. ecSetBookmark9:
      if LeftMargin.Bookmarks.ShortCuts then
        DoSetBookmark(ACommand, AData);
    ecWordLeft, ecSelectionWordLeft:
      DoWordLeft(ACommand);
    ecWordRight, ecSelectionWordRight:
      DoWordRight(ACommand);
    ecSelectionWord:
      SetSelectedWord;
    ecSelectAll:
      SelectAll;
    ecBackspace:
      if not ReadOnly then
        DoBackspace;
    ecDeleteChar:
      if not ReadOnly then
        DeleteChar;
    ecDeleteWord, ecDeleteEndOfLine:
      if not ReadOnly then
        DeleteWordOrEndOfLine(ACommand);
    ecDeleteLastWord, ecDeleteBeginningOfLine:
      if not ReadOnly then
        DeleteLastWordOrBeginningOfLine(ACommand);
    ecDeleteLine:
      if not ReadOnly then
        DeleteLine;
    ecMoveLineUp:
      MoveLineUp;
    ecMoveLineDown:
      MoveLineDown;
    ecMoveCharLeft:
      MoveCharLeft;
    ecMoveCharRight:
      MoveCharRight;
    ecSearchFindFirst:
      DoSearchFind(True, nil);
    ecSearchFind:
      DoSearchFind(Search.Pattern = '', nil);
    ecSearchReplace:
      DoSearchReplace(nil);
    ecSearchNext:
      FindNext;
    ecSearchPrevious:
      FindPrevious;
    ecClear:
      if not ReadOnly then
        Clear;
    ecInsertLine:
      if not ReadOnly then
        InsertLine;
    ecLineBreak:
      if not ReadOnly then
        DoLineBreak;
    ecTab:
      if not ReadOnly then
        DoTabKey;
    ecShiftTab:
      if not ReadOnly then
        DoShiftTabKey;
    ecChar:
      if not ReadOnly and (AChar >= BCEDITOR_SPACE_CHAR) and (AChar <> BCEDITOR_CTRL_BACKSPACE) then
        DoChar(AChar);
    ecUpperCase, ecLowerCase, ecAlternatingCase, ecSentenceCase, ecTitleCase, ecUpperCaseBlock, ecLowerCaseBlock,
      ecAlternatingCaseBlock:
      if not ReadOnly then
        DoToggleSelectedCase(ACommand);
    ecUndo:
      if not ReadOnly then
        Undo();
    ecRedo:
      if not ReadOnly then
        Redo();
    ecCut:
      if (not ReadOnly and SelectionAvailable) then
        DoCutToClipboard;
    ecCopy:
      CopyToClipboard;
    ecPaste:
      if not ReadOnly then
        DoPasteFromClipboard();
    ecScrollUp, ecScrollDown:
      DoScroll(ACommand);
    ecScrollLeft:
      begin
        HorzTextPos := HorzTextPos - 1;
        Update;
      end;
    ecScrollRight:
      begin
        HorzTextPos := HorzTextPos + 1;
        Update;
      end;
    ecInsertMode:
      SetTextEntryMode(temInsert);
    ecOverwriteMode:
      SetTextEntryMode(temOverwrite);
    ecToggleMode:
      if FTextEntryMode = temInsert then
        SetTextEntryMode(temOverwrite)
      else
        SetTextEntryMode(temInsert);
    ecBlockIndent,
    ecBlockUnindent:
      if not ReadOnly then
        DoBlockIndent(ACommand);
    ecNormalSelect:
      Lines.SelMode := smNormal;
    ecColumnSelect:
      Lines.SelMode := smColumn;
    ecContextHelp:
      if Assigned(FOnContextHelp) then
        FOnContextHelp(Self, WordAt[CaretPos]);
    ecBlockComment:
      if not ReadOnly then
        DoBlockComment;
    ecLineComment:
      if not ReadOnly then
        DoLineComment;
    ecImeStr:
      if not ReadOnly then
        DoImeStr(AData);
    ecCompletionProposal:
      DoCompletionProposal();
  end;
end;

procedure TCustomBCEditor.ExportToHTML(const AFileName: string; const ACharSet: string = '';
  AEncoding: TEncoding = nil);
var
  LFileStream: TFileStream;
begin
  LFileStream := TFileStream.Create(AFileName, fmCreate);
  try
    ExportToHTML(LFileStream, ACharSet, AEncoding);
  finally
    LFileStream.Free;
  end;
end;

procedure TCustomBCEditor.ExportToHTML(AStream: TStream; const ACharSet: string = '';
  AEncoding: TEncoding = nil);
begin
  with TBCEditorExportHTML.Create(Lines, FHighlighter, Font, ACharSet) do
  try
    SaveToStream(AStream, AEncoding);
  finally
    Free;
  end;
end;

procedure TCustomBCEditor.FillRect(const ARect: TRect);
begin
  ExtTextOut(Canvas.Handle, 0, 0, ETO_OPAQUE, ARect, '', 0, nil);
end;

procedure TCustomBCEditor.FindAll;
var
  LIndex: Integer;
begin
  if (FCaret.MultiEdit.Enabled) then
  begin
    for LIndex := 0 to FSearchResults.Count - 1 do
      AddCaret(TextToDisplay(FSearchResults[LIndex].EndPosition));
    SetFocus();
  end;
end;

function TCustomBCEditor.FindFirst(): Boolean;
var
  LBeginPosition: TBCEditorTextPosition;
  LEndPosition: TBCEditorTextPosition;
  LSearchResult: TSearchResult;
begin
  if (SelectionAvailable and (FSearch.InSelection.Active)) then
  begin
    LBeginPosition := Lines.SelBeginPosition;
    LEndPosition:= Lines.SelEndPosition;
  end
  else
  begin
    LBeginPosition := Lines.BOFPosition;
    LEndPosition := Lines.EOFPosition;
  end;

  Include(FState, esFind);
  try
    Result := DoSearch(LBeginPosition, LEndPosition);
    if (Result) then
    begin
      if (soEntireScope in FSearch.Options) then
        if (soBackwards in FSearch.Options) then
          DoSearchPrevious(Lines.EOFPosition, LSearchResult)
        else
          DoSearchNext(Lines.BOFPosition, LSearchResult)
      else
        if (soBackwards in FSearch.Options) then
          DoSearchPrevious(Lines.CaretPosition, LSearchResult, soWrapAround in Search.Options)
        else
          DoSearchNext(Lines.CaretPosition, LSearchResult, soWrapAround in Search.Options);

      if (soBackwards in Search.Options) then
        SetCaretAndSelection(LSearchResult.BeginPosition, LSearchResult.BeginPosition, LSearchResult.EndPosition)
      else      
        SetCaretAndSelection(LSearchResult.EndPosition, LSearchResult.BeginPosition, LSearchResult.EndPosition);
    end;
  finally
    Exclude(FState, esFind);
  end;
end;

function TCustomBCEditor.FindHookedCommandEvent(const AHookedCommandEvent: TBCEditorHookedCommandEvent): Integer;
var
  LHookedCommandHandler: TBCEditorHookedCommandHandler;
begin
  Result := GetHookedCommandHandlersCount - 1;
  while Result >= 0 do
  begin
    LHookedCommandHandler := TBCEditorHookedCommandHandler(FHookedCommandHandlers[Result]);
    if LHookedCommandHandler.Equals(AHookedCommandEvent) then
      Break;
    Dec(Result);
  end;
end;

function TCustomBCEditor.FindNext(const AHandleNotFound: Boolean = True): Boolean;
var
  LSearchResult: TSearchResult;
begin
  if (FSearchResults.Count = 0) then
    Result := FindFirst()
  else
  begin
    Include(FState, esFind);
    BeginUpdate();
    try
      if (soBackwards in Search.Options) then
        Result := DoSearchPrevious(Lines.CaretPosition, LSearchResult, soWrapAround in FSearch.Options)
      else      
        Result := DoSearchNext(Lines.CaretPosition, LSearchResult, soWrapAround in FSearch.Options);
        
      if (Result) then
      begin
        if (LSearchResult.BeginPosition.Line >= TopRow + VisibleRows - 1) then
          GotoLineAndCenter(LSearchResult.EndPosition.Line, LSearchResult.EndPosition.Char);

        if (soBackwards in Search.Options) then
          SetCaretAndSelection(LSearchResult.BeginPosition, LSearchResult.BeginPosition, LSearchResult.EndPosition)
        else      
          SetCaretAndSelection(LSearchResult.EndPosition, LSearchResult.BeginPosition, LSearchResult.EndPosition);
      end
      else if (AHandleNotFound and (Search.Pattern <> '')) then
        DoSearchStringNotFoundDialog();
    finally
      EndUpdate();
      Exclude(FState, esFind);
    end;
  end;
end;

function TCustomBCEditor.FindPrevious(const AHandleNotFound: Boolean = True): Boolean;
var
  LSearchResult: TSearchResult;
begin
  if (FSearchResults.Count = 0) then
    Result := FindFirst()
  else
  begin
    Include(FState, esFind);
    BeginUpdate();
    try
      if (soBackwards in Search.Options) then
        Result := DoSearchNext(Lines.CaretPosition, LSearchResult, soWrapAround in FSearch.Options)
      else
        Result := DoSearchPrevious(Lines.CaretPosition, LSearchResult, soWrapAround in FSearch.Options);

      if (Result) then
      begin
        if (LSearchResult.BeginPosition.Line >= TopRow + VisibleRows - 1) then
          GotoLineAndCenter(LSearchResult.EndPosition.Line, LSearchResult.EndPosition.Char);

        if (soBackwards in Search.Options) then
          SetCaretAndSelection(LSearchResult.BeginPosition, LSearchResult.BeginPosition, LSearchResult.EndPosition)
        else
          SetCaretAndSelection(LSearchResult.EndPosition, LSearchResult.BeginPosition, LSearchResult.EndPosition);
      end
      else if (AHandleNotFound and (Search.Pattern <> '')) then
        DoSearchStringNotFoundDialog();
    finally
      Exclude(FState, esFind);
    end;
  end;
end;

procedure TCustomBCEditor.FindWords(const AWord: string; AList: TList; ACaseSensitive: Boolean; AWholeWordsOnly: Boolean);

  function AreCharsSame(APChar1, APChar2: PChar): Boolean;
  begin
    if ACaseSensitive then
      Result := APChar1^ = APChar2^
    else
      Result := CaseUpper(APChar1^) = CaseUpper(APChar2^)
  end;

  function IsWholeWord(FirstChar, LastChar: PChar): Boolean;
  begin
    Result := IsWordBreakChar(FirstChar^) and IsWordBreakChar(LastChar^);
  end;

var
  LEndPosWord: PChar;
  LFirstChar: Integer;
  LFirstLine: Integer;
  LLastChar: Integer;
  LLastLine: Integer;
  LLine: Integer;
  LLineBeginPos: PChar;
  LLineEndPos: PChar;
  LLinePos: PChar;
  LPBookmarkText: PChar;
  LPosWord: PChar;
  LPTextPosition: PBCEditorTextPosition;
begin
  if FSearch.InSelection.Active then
  begin
    LFirstLine := FSearch.InSelection.SelectionBeginPosition.Line;
    LFirstChar := FSearch.InSelection.SelectionBeginPosition.Char - 1;
    LLastLine := FSearch.InSelection.SelectionEndPosition.Line;
    LLastChar := FSearch.InSelection.SelectionEndPosition.Char;
  end
  else
  begin
    LFirstLine := 0;
    LFirstChar := -1;
    LLastLine := Lines.Count - 1;
    LLastChar := -1;
  end;

  for LLine := LFirstLine to LLastLine do
  begin
    if (Lines.Lines[LLine].Text <> '') then
    begin
      LLinePos := @Lines.Lines[LLine].Text[1];
      LLineBeginPos := LLinePos;
      LLineEndPos := @Lines.Lines[LLine].Text[Length(Lines.Lines[LLine].Text)];
      if (LLine = LFirstLine) and (LFirstChar >= 0) then
        Inc(LLinePos, LFirstChar);
      while (LLinePos <= LLineEndPos) do
      begin
        if (AreCharsSame(LLinePos, PChar(AWord))) then { If the first character is a match }
        begin
          LPosWord := @AWord[1];
          LEndPosWord := @AWord[Length(AWord)];
          LPBookmarkText := LLinePos;
          { Check if the keyword found }
          while ((LLinePos <= LLineEndPos) and (LPosWord^ <= LEndPosWord) and AreCharsSame(LLinePos, LPosWord)) do
          begin
            Inc(LLinePos);
            Inc(LPosWord);
          end;
          if ((LLinePos > LEndPosWord)
            and (not AWholeWordsOnly or AWholeWordsOnly and IsWholeWord(LPBookmarkText - 1, LLinePos))) then
          begin
            Dec(LLinePos);
            New(LPTextPosition);
            LPTextPosition^.Char := LPBookmarkText - LLineBeginPos;
            LPTextPosition^.Line := LLine;
            AList.Add(LPTextPosition)
          end
          else
            LLinePos := LPBookmarkText; { Not found, return pointer back }
        end;

        Inc(LLinePos);

        if ((LLine = LLastLine) and (LLastChar >= 0)) then
          if (LLineBeginPos - LLinePos > LLastChar + 1) then
            Break;
      end;
    end;
  end;
end;

procedure TCustomBCEditor.FontChanged(ASender: TObject);
var
  LSize: TSize;
begin
  FLineHeight := FPaintHelper.CharHeight + FLineSpacing;
  FPaintHelper.SetStyle([]);
  if (not GetTextExtentPoint32(FPaintHelper.StockBitmap.Canvas.Handle, #187, 1, LSize)) then
    // Sometimes GetTextExtentPoint32 fails. But why?
    // Obsolete Canvas.Handle?
    // Lack of GDI resources?
    FTabSignWidth := CharWidth
  else
    FTabSignWidth := LSize.cx;
  if (not GetTextExtentPoint32(FPaintHelper.StockBitmap.Canvas.Handle, #182, 1, LSize)) then
    // Sometimes GetTextExtentPoint32 fails. But why?
    // Obsolete Canvas.Handle?
    // Lack of GDI resources?
    FLineBreakSignWidth := CharWidth
  else
    FLineBreakSignWidth := LSize.cx;

  if (HandleAllocated) then
    with FWordWrapIndicator do
    begin
      Handle := CreateCompatibleBitmap(Self.Canvas.Handle, 2 * FLeftMarginCharWidth, LineHeight);
      Canvas.Brush.Color := LeftMargin.Colors.Background;
      Canvas.Pen.Color := LeftMargin.Font.Color;
      Canvas.FillRect(Rect(0, 0, FWordWrapIndicator.Width, FWordWrapIndicator.Height));
      Canvas.MoveTo(6, 4);
      Canvas.LineTo(13, 4);
      Canvas.MoveTo(13, 5);
      Canvas.LineTo(13, 9);
      Canvas.MoveTo(12, 9);
      Canvas.LineTo(7, 9);
      Canvas.MoveTo(10, 7);
      Canvas.LineTo(10, 12);
      Canvas.MoveTo(9, 8);
      Canvas.LineTo(9, 11);
      Canvas.MoveTo(2, 6);
      Canvas.LineTo(7, 6);
      Canvas.MoveTo(2, 8);
      Canvas.LineTo(5, 8);
      Canvas.MoveTo(2, 10);
      Canvas.LineTo(5, 10);
      Canvas.MoveTo(2, 12);
      Canvas.LineTo(7, 12);
    end;

  SizeOrFontChanged(True);
end;

procedure TCustomBCEditor.FreeHintForm(var AForm: TBCEditorCodeFoldingHintForm);
begin
  if Assigned(AForm) then
  begin
    AForm.Hide;
    AForm.ItemList.Clear;
    AForm.Free;
    AForm := nil;
  end;
  FCodeFolding.MouseOverHint := False;
  UpdateMouseCursor;
end;

procedure TCustomBCEditor.FreeMultiCarets;
begin
  if Assigned(FMultiCarets) then
  begin
    FMultiCaretTimer.Enabled := False;
    FMultiCaretTimer.Free;
    FMultiCaretTimer := nil;
    FMultiCarets.Free();
    FMultiCarets := nil;
  end;
end;

procedure TCustomBCEditor.FreeTokenInfoPopupWindow;
var
  LTokenInfoPopupWindow: TBCEditorTokenInfoPopupWindow;
begin
  if Assigned(FTokenInfoPopupWindow) then
  begin
    LTokenInfoPopupWindow := FTokenInfoPopupWindow;
    FTokenInfoPopupWindow := nil; { Prevent WMKillFocus to free it again }
    LTokenInfoPopupWindow.Hide();
    LTokenInfoPopupWindow.Free();
    FTokenInfoTokenRect.Empty();
  end;
end;

function TCustomBCEditor.GetBookmark(const AIndex: Integer; var ATextPosition: TBCEditorTextPosition): Boolean;
var
  LBookmark: TBCEditorMark;
begin
  Result := False;
  LBookmark := FBookmarkList.Find(AIndex);
  if Assigned(LBookmark) then
  begin
    ATextPosition.Char := LBookmark.Char;
    ATextPosition.Line := LBookmark.Line;
    Result := True;
  end;
end;

function TCustomBCEditor.GetCanPaste: Boolean;
begin
  Result := not ReadOnly and (IsClipboardFormatAvailable(CF_TEXT) or IsClipboardFormatAvailable(CF_UNICODETEXT));
end;

function TCustomBCEditor.GetCanRedo: Boolean;
begin
  Result := not ReadOnly and Lines.CanRedo;
end;

function TCustomBCEditor.GetCanUndo: Boolean;
begin
  Result := not ReadOnly and Lines.CanUndo;
end;

function TCustomBCEditor.GetCaretPos(): TPoint;
begin
  Result := Point(Lines.CaretPosition);
end;

function TCustomBCEditor.GetCharAt(APos: TPoint): Char;
begin
  Result := Lines.Char[TextPosition(APos)];
end;

function TCustomBCEditor.GetCharWidth(): Integer;
begin
  Result := FPaintHelper.CharWidth;
end;

function TCustomBCEditor.GetColorsFileName(const AFileName: string): string;
begin
  Result := Trim(ExtractFilePath(AFileName));
  if Trim(ExtractFilePath(Result)) = '' then
{$WARN SYMBOL_PLATFORM OFF}
    Result := IncludeTrailingBackslash(ExtractFilePath(Application.ExeName)) + Result;
  Result := IncludeTrailingBackslash(Result) + ExtractFileName(AFileName);
{$WARN SYMBOL_PLATFORM ON}
end;

function TCustomBCEditor.GetCommentAtTextPosition(const ATextPosition: TBCEditorTextPosition): string;
var
  LBeginPosition: TBCEditorTextPosition;
  LEndPosition: TBCEditorTextPosition;
begin
  if ((Lines.CaretPosition.Line >= Lines.Count)
    or (Lines.CaretPosition > Lines.EOLPosition[Lines.CaretPosition.Line])
    or not IsCommentChar(Lines.Char[Lines.CaretPosition])) then
    Result := ''
  else
  begin
    LBeginPosition := Lines.CaretPosition;
    while ((LBeginPosition.Char > 0) and IsCommentChar(Lines.Lines[LBeginPosition.Line].Text[1 + LBeginPosition.Char - 1])) do
      Dec(LBeginPosition.Char);
    LEndPosition := Lines.CaretPosition;
    while ((LEndPosition.Char < Length(Lines.Lines[LEndPosition.Line].Text)) and IsCommentChar(Lines.Lines[LEndPosition.Line].Text[1 + LEndPosition.Char + 1])) do
      Inc(LEndPosition.Char);
    Result := Lines.TextBetween[LBeginPosition, LEndPosition];
  end;
end;

function TCustomBCEditor.GetDisplayCaretPosition(): TBCEditorDisplayPosition;
begin
  Result := TextToDisplay(Lines.CaretPosition);
end;

function TCustomBCEditor.GetHighlighterAttributeAtRowColumn(const ATextPosition: TBCEditorTextPosition;
  var AToken: string; var ATokenType: TBCEditorRangeType; var AColumn: Integer;
  var AHighlighterAttribute: TBCEditorHighlighter.TAttribute): Boolean;
begin
  if (Assigned(FHighlighter)
    and (0 <= ATextPosition.Line) and (ATextPosition.Line < Lines.Count)
    and (Lines.BOLPosition[ATextPosition.Line] <= ATextPosition) and (ATextPosition <= Lines.EOLPosition[ATextPosition.Line])) then
  begin
    if (ATextPosition.Line = 0) then
      FHighlighter.ResetCurrentRange()
    else
      FHighlighter.SetCurrentRange(Lines.Lines[ATextPosition.Line - 1].Range);
    FHighlighter.SetCurrentLine(Lines.Lines[ATextPosition.Line].Text);
    while (not FHighlighter.GetEndOfLine()) do
    begin
      AColumn := FHighlighter.GetTokenIndex + 1;
      FHighlighter.GetTokenText(AToken);
      if ((AColumn < ATextPosition.Char) and (ATextPosition.Char < AColumn - 1 + Length(AToken))) then
      begin
        AHighlighterAttribute := FHighlighter.GetTokenAttribute;
        ATokenType := FHighlighter.GetTokenKind;
        Exit(True);
      end;
      FHighlighter.Next;
    end;
  end;
  AToken := '';
  AHighlighterAttribute := nil;
  Result := False;
end;

function TCustomBCEditor.GetHighlighterFileName(const AFileName: string): string;
begin
  Result := Trim(ExtractFilePath(AFileName));
  if Trim(ExtractFilePath(Result)) = '' then
{$WARN SYMBOL_PLATFORM OFF}
    Result := IncludeTrailingBackslash(ExtractFilePath(Application.ExeName)) + Result;
  Result := IncludeTrailingBackslash(Result) + ExtractFileName(AFileName);
{$WARN SYMBOL_PLATFORM ON}
end;

function TCustomBCEditor.GetHookedCommandHandlersCount: Integer;
begin
  if Assigned(FHookedCommandHandlers) then
    Result := FHookedCommandHandlers.Count
  else
    Result := 0;
end;

function TCustomBCEditor.GetLeadingExpandedLength(const AStr: string; const ABorder: Integer = 0): Integer;
var
  LChar: PChar;
  LLength: Integer;
begin
  Result := 0;
  LChar := PChar(AStr);
  if ABorder > 0 then
    LLength := Min(PInteger(LChar - 2)^, ABorder)
  else
    LLength := PInteger(LChar - 2)^;
  while LLength > 0 do
  begin
    if LChar^ = BCEDITOR_TAB_CHAR then
      Inc(Result, FTabs.Width - (Result mod FTabs.Width))
    else
    if (CharInSet(LChar^, [BCEDITOR_NONE_CHAR, BCEDITOR_SPACE_CHAR])) then
      Inc(Result)
    else
      Exit;
    Inc(LChar);
    Dec(LLength);
  end;
end;

function TCustomBCEditor.GetLeftMarginWidth: Integer;
begin
  Result := LeftMargin.Width + FCodeFolding.GetWidth;
  if FSearch.Map.Align = saLeft then
    Inc(Result, FSearch.Map.GetWidth);
end;

function TCustomBCEditor.GetLineIndentLevel(const ALine: Integer): Integer;
var
  LLineEndPos: PChar;
  LLinePos: PChar;
begin
  Assert((0 <= ALine) and (ALine < Lines.Count));

  Result := 0;
  if (Lines.Lines[ALine].Text <> '') then
  begin
    LLinePos := @Lines.Lines[ALine].Text[1];
    LLineEndPos := @Lines.Lines[ALine].Text[Length(Lines.Lines[ALine].Text)];
    while ((LLinePos <= LLineEndPos) and CharInSet(LLinePos^, [BCEDITOR_NONE_CHAR, BCEDITOR_TAB_CHAR, BCEDITOR_SPACE_CHAR])) do
    begin
      if (LLinePos^ <> BCEDITOR_TAB_CHAR) then
        Inc(Result)
      else if (toColumns in Tabs.Options) then
        Inc(Result, FTabs.Width - Result mod FTabs.Width)
      else
        Inc(Result, FTabs.Width);
      Inc(LLinePos);
    end;
  end;
end;

function TCustomBCEditor.GetMarkBackgroundColor(const ALine: Integer): TColor;
var
  LIndex: Integer;
  LMark: TBCEditorMark;
begin
  Result := clNone;
  { Bookmarks }
  if LeftMargin.Colors.BookmarkBackground <> clNone then
  for LIndex := 0 to FBookmarkList.Count - 1 do
  begin
    LMark := FBookmarkList.Items[LIndex];
    if LMark.Line + 1 = ALine then
    begin
      Result := LeftMargin.Colors.BookmarkBackground;
      Break;
    end;
  end;
  { Other marks }
  for LIndex := 0 to FMarkList.Count - 1 do
  begin
    LMark := FMarkList.Items[LIndex];
    if (LMark.Line + 1 = ALine) and (LMark.Background <> clNone) then
    begin
      Result := LMark.Background;
      Break;
    end;
  end;
end;

function TCustomBCEditor.GetMatchingToken(const ATextCaretPosition: TBCEditorTextPosition;
  var AMatchingPairMatch: TBCEditorHighlighter.TMatchingPairMatch): TMatchingPairTokenResult;
var
  LDeltaLevel: Integer;
  LLevel: Integer;
  LMatchingPair: Integer;
  LMachtingPairsCount: Integer;
  LMatchStackIndex: Integer;
  LOriginalTokenText: string;
  LTextCaretPosition: TBCEditorTextPosition;

  function IsCommentOrString(const AElement: string): Boolean; inline;
  begin
    Result := (AElement = BCEDITOR_ATTRIBUTE_ELEMENT_COMMENT) or (AElement = BCEDITOR_ATTRIBUTE_ELEMENT_STRING);
  end;

  function IsOpenToken(const AToken: string): Boolean;
  var
    LIndex: Integer;
  begin
    Result := False;
    if (not IsCommentOrString(FHighlighter.GetCurrentRangeAttribute().Element)) then
      for LIndex := 0 to LMachtingPairsCount - 1 do
        if (AToken = FHighlighter.MatchingPairs[LIndex].OpenToken) then
          Result := True;
  end;

  function IsCloseToken(const AToken: string): Boolean;
  var
    LIndex: Integer;
  begin
    Result := False;
    if (not IsCommentOrString(FHighlighter.GetCurrentRangeAttribute().Element)) then
      for LIndex := 0 to LMachtingPairsCount - 1 do
        if (AToken = FHighlighter.MatchingPairs[LIndex].CloseToken) then
          Result := True;
  end;

  function CheckTokenForwards(): Boolean;
  var
    LToken: string;
  begin
    FHighlighter.GetTokenText(LToken);
    LToken := LowerCase(LToken);
    if (IsCloseToken(LToken)) then
      Dec(LLevel)
    else if (IsOpenToken(LToken)) then
      Inc(LLevel);
    Result := LLevel = 0;
    if (Result) then
    begin
      GetMatchingToken := trOpenAndCloseTokenFound;
      FHighlighter.GetTokenText(AMatchingPairMatch.CloseText);
      AMatchingPairMatch.ClosePosition := TextPosition(FHighlighter.GetTokenIndex(), LTextCaretPosition.Line);
    end
    else
      FHighlighter.Next();
  end;

  procedure CheckTokenBackwards();
  var
    LToken: string;
  begin
    FHighlighter.GetTokenText(LToken);
    LToken := LowerCase(LToken);
    if (IsCloseToken(LToken)) then
    begin
      Dec(LLevel);
      if (LMatchStackIndex >= 0) then
        Dec(LMatchStackIndex);
    end
    else if (IsOpenToken(LToken)) then
    begin
      Inc(LLevel);
      Inc(LMatchStackIndex);
      if (LMatchStackIndex >= Length(FMatchingPairMatchStack)) then
        SetLength(FMatchingPairMatchStack, Length(FMatchingPairMatchStack) + 32);
      FHighlighter.GetTokenText(FMatchingPairMatchStack[LMatchStackIndex].Token);
      FMatchingPairMatchStack[LMatchStackIndex].Position := TextPosition(FHighlighter.GetTokenIndex(), LTextCaretPosition.Line);
    end;
    FHighlighter.Next();
  end;

var
  LTokenText: string;
begin
  Result := trNotFound;

  if (Assigned(FHighlighter)) then
  begin
    LTextCaretPosition := ATextCaretPosition;

    if (LTextCaretPosition.Line = 0) then
      FHighlighter.ResetCurrentRange()
    else
      FHighlighter.SetCurrentRange(Lines.Lines[LTextCaretPosition.Line - 1].Range);
    FHighlighter.SetCurrentLine(Lines.Lines[LTextCaretPosition.Line].Text);

    while (not FHighlighter.GetEndOfLine()
      and (ATextCaretPosition.Char >= FHighlighter.GetTokenIndex() + FHighlighter.GetTokenLength())) do
      FHighlighter.Next();

    if (not FHighlighter.GetEndOfLine()
      and not IsCommentOrString(FHighlighter.GetCurrentRangeAttribute().Element)) then
    begin
      LMachtingPairsCount := FHighlighter.MatchingPairs.Count;

      FHighlighter.GetTokenText(LOriginalTokenText);
      LTokenText := Trim(LowerCase(LOriginalTokenText));

      Result := trNotFound;
      for LMatchingPair := 0 to LMachtingPairsCount - 1 do
        if (FHighlighter.MatchingPairs[LMatchingPair].OpenToken = LTokenText) then
        begin
          Result := trOpenTokenFound;
          AMatchingPairMatch.OpenText := LOriginalTokenText;
          AMatchingPairMatch.OpenPosition := TextPosition(FHighlighter.GetTokenIndex(), LTextCaretPosition.Line);
          Break;
        end
        else if (FHighlighter.MatchingPairs[LMatchingPair].CloseToken = LTokenText) then
        begin
          Result := trCloseTokenFound;
          AMatchingPairMatch.CloseText := LOriginalTokenText;
          AMatchingPairMatch.ClosePosition := TextPosition(FHighlighter.GetTokenIndex(), LTextCaretPosition.Line);
          Break;
        end;

      if (Result <> trNotFound) then
      begin
        AMatchingPairMatch.Attribute := FHighlighter.GetTokenAttribute();

        if (Result = trOpenTokenFound) then
        begin
          LLevel := 1;
          FHighlighter.Next();
          while (True) do
          begin
            while (not FHighlighter.GetEndOfLine()) do
              if (CheckTokenForwards()) then
                Exit;

            Inc(LTextCaretPosition.Line);
            if (LTextCaretPosition.Line >= Lines.Count) then
              Break;

            if (LTextCaretPosition.Line = 0) then
              FHighlighter.ResetCurrentRange()
            else
              FHighlighter.SetCurrentRange(Lines.Lines[LTextCaretPosition.Line - 1].Range);
            FHighlighter.SetCurrentLine(Lines.Lines[LTextCaretPosition.Line].Text);
          end;
        end
        else
        begin
          if (Length(FMatchingPairMatchStack) < 32) then
            SetLength(FMatchingPairMatchStack, 32);
          LMatchStackIndex := -1;
          LLevel := -1;

          if (LTextCaretPosition.Line = 0) then
            FHighlighter.ResetCurrentRange()
          else
            FHighlighter.SetCurrentRange(Lines.Lines[LTextCaretPosition.Line - 1].Range);
          FHighlighter.SetCurrentLine(Lines.Lines[LTextCaretPosition.Line].Text);

          while (not FHighlighter.GetEndOfLine() and (FHighlighter.GetTokenIndex() < AMatchingPairMatch.ClosePosition.Char)) do
            CheckTokenBackwards();
          if (LMatchStackIndex > -1) then
          begin
            Result := trCloseAndOpenTokenFound;
            AMatchingPairMatch.OpenText := FMatchingPairMatchStack[LMatchStackIndex].Token;
            AMatchingPairMatch.OpenPosition := FMatchingPairMatchStack[LMatchStackIndex].Position;
          end
          else
            while (LTextCaretPosition.Line > 0) do
            begin
              LDeltaLevel := -LLevel - 1;
              Dec(LTextCaretPosition.Line);

              if (LTextCaretPosition.Line = 0) then
                FHighlighter.ResetCurrentRange()
              else
                FHighlighter.SetCurrentRange(Lines.Lines[LTextCaretPosition.Line - 1].Range);
              FHighlighter.SetCurrentLine(Lines.Lines[LTextCaretPosition.Line].Text);

              LMatchStackIndex := -1;
              while (not FHighlighter.GetEndOfLine()) do
                CheckTokenBackwards();
              if (LDeltaLevel <= LMatchStackIndex) then
              begin
                Result := trCloseAndOpenTokenFound;
                AMatchingPairMatch.OpenText := FMatchingPairMatchStack[LMatchStackIndex - LDeltaLevel].Token;
                AMatchingPairMatch.OpenPosition := FMatchingPairMatchStack[LMatchStackIndex - LDeltaLevel].Position;
                Exit;
              end;
            end;
        end;
      end;
    end;
  end;
end;

function TCustomBCEditor.GetModified(): Boolean;
begin
  Result := Lines.Modified;
end;

function TCustomBCEditor.GetMouseMoveScrollCursorIndex: Integer;
var
  LBottomY: Integer;
  LCursorPoint: TPoint;
  LLeftX: Integer;
  LRightX: Integer;
  LTopY: Integer;
begin
  Result := scNone;

  GetCursorPos(LCursorPoint);
  LCursorPoint := ScreenToClient(LCursorPoint);

  LLeftX := FMouseMoveScrollingPoint.X - FScroll.Indicator.Width;
  LRightX := FMouseMoveScrollingPoint.X + 4;
  LTopY := FMouseMoveScrollingPoint.Y - FScroll.Indicator.Height;
  LBottomY := FMouseMoveScrollingPoint.Y + 4;

  if LCursorPoint.Y < LTopY then
  begin
    if LCursorPoint.X < LLeftX then
      Exit(scNorthWest)
    else
    if (LCursorPoint.X >= LLeftX) and (LCursorPoint.X <= LRightX) then
      Exit(scNorth)
    else
      Exit(scNorthEast)
  end;

  if LCursorPoint.Y > LBottomY then
  begin
    if LCursorPoint.X < LLeftX then
      Exit(scSouthWest)
    else
    if (LCursorPoint.X >= LLeftX) and (LCursorPoint.X <= LRightX) then
      Exit(scSouth)
    else
      Exit(scSouthEast)
  end;

  if LCursorPoint.X < LLeftX then
    Exit(scWest);

  if LCursorPoint.X > LRightX then
    Exit(scEast);
end;

function TCustomBCEditor.GetMouseMoveScrollCursors(const AIndex: Integer): HCursor;
begin
  Result := 0;
  if (AIndex >= Low(FMouseMoveScrollCursors)) and (AIndex <= High(FMouseMoveScrollCursors)) then
    Result := FMouseMoveScrollCursors[AIndex];
end;

function TCustomBCEditor.GetReadOnly: Boolean;
begin
  Result := Lines.ReadOnly;
end;

function TCustomBCEditor.GetRows(): TRows;
const
  RowToInsert = -2;
var
  LCodeFolding: Integer;
  LLine: Integer;
  LRange: TBCEditorCodeFolding.TRanges.TRange;
  LRow: Integer;
begin
  if (FRows.Count = 0) then
    if (WordWrap.Enabled and (WordWrap.Width = wwwPage) and not HandleAllocated) then
      HandleNeeded()
    else
    begin
      Include(FState, esRowsUpdating);
      try
        for LLine := 0 to Lines.Count - 1 do
          Lines.SetFirstRow(LLine, RowToInsert);

        for LCodeFolding := 0 to FAllCodeFoldingRanges.AllCount - 1 do
        begin
          LRange := FAllCodeFoldingRanges[LCodeFolding];
          if (Assigned(LRange) and LRange.Collapsed) then
            for LLine := LRange.FirstLine + 1 to LRange.LastLine do
              Lines.SetFirstRow(LLine, -1);
        end;

        LRow := 0;
        for LLine := 0 to Lines.Count - 1 do
          if (Lines.Lines[LLine].FirstRow = RowToInsert) then
          begin
            Lines.SetFirstRow(LLine, LRow);
            Inc(LRow, InsertLineIntoRows(LLine, LRow));
          end;
      finally
        Exclude(FState, esRowsUpdating);

        if (UpdateCount = 0) then
          UpdateScrollBars(False);
      end;
    end;

  Result := FRows;
end;

function TCustomBCEditor.GetSearchResultCount: Integer;
begin
  Result := FSearchResults.Count;
end;

function TCustomBCEditor.GetSelectionAvailable(): Boolean;
begin
  Result := Lines.SelBeginPosition <> Lines.SelEndPosition;
end;

function TCustomBCEditor.GetSelectionBeginPosition: TBCEditorTextPosition;
begin
  Result := Lines.SelBeginPosition;
end;

function TCustomBCEditor.GetSelectionEndPosition: TBCEditorTextPosition;
begin
  Result := Lines.SelEndPosition;
end;

function TCustomBCEditor.GetSelectionMode(): TBCEditorSelectionMode;
begin
  Result := Lines.SelMode;
end;

function TCustomBCEditor.GetSelLength(): Integer;
begin
  if (Lines.SelBeginPosition = Lines.SelEndPosition) then
    Result := 0
  else
    Result := Lines.PositionToCharIndex(Max(Lines.SelBeginPosition, Lines.SelEndPosition))
      - Lines.PositionToCharIndex(Min(Lines.SelBeginPosition, Lines.SelEndPosition));
end;

function TCustomBCEditor.GetSelStart(): Integer;
begin
  Result := Lines.PositionToCharIndex(Min(Lines.SelBeginPosition, Lines.SelEndPosition));
end;

function TCustomBCEditor.GetSelText(): string;
begin
  if (not SelectionAvailable) then
    Result := ''
  else if (Lines.SelMode = smNormal) then
    Result := Lines.TextBetween[Min(Lines.SelBeginPosition, Lines.SelEndPosition), Max(Lines.SelBeginPosition, Lines.SelEndPosition)]
  else
    Result := Lines.TextBetweenColumn[Lines.SelBeginPosition, Lines.SelEndPosition];
end;

function TCustomBCEditor.GetText(): string;
begin
  Result := Lines.Text;
end;

function TCustomBCEditor.GetTextBetween(ATextBeginPosition, ATextEndPosition: TBCEditorTextPosition): string;
begin
  if (Lines.SelMode = smNormal) then
    Result := Lines.TextBetween[ATextBeginPosition, ATextEndPosition]
  else
    Result := Lines.TextBetweenColumn[ATextBeginPosition, ATextEndPosition];
end;

function TCustomBCEditor.GetTextPositionOfMouse(out ATextPosition: TBCEditorTextPosition): Boolean;
var
  LCursorPoint: TPoint;
begin
  Result := False;

  GetCursorPos(LCursorPoint);
  LCursorPoint := ScreenToClient(LCursorPoint);
  if (LCursorPoint.X < 0) or (LCursorPoint.Y < 0) or (LCursorPoint.X > Self.Width) or (LCursorPoint.Y > Self.Height) then
    Exit;
  ATextPosition := TextPosition(ClientToText(LCursorPoint.X, LCursorPoint.Y));

  if (ATextPosition.Line = Lines.Count - 1) and (ATextPosition.Char >= Length(Lines.Lines[Lines.Count - 1].Text)) then
    Exit;

  Result := True;
end;

function TCustomBCEditor.GetUndoOptions(): TBCEditorUndoOptions;
begin
  Result := [];
  if (loUndoGrouped in Lines.Options) then
    Result := Result + [uoGroupUndo];
  if (loUndoAfterLoad in Lines.Options) then
    Result := Result + [uoUndoAfterLoad];
  if (loUndoAfterSave in Lines.Options) then
    Result := Result + [uoUndoAfterSave];
end;

function TCustomBCEditor.GetVisibleChars(const ARow: Integer; const ALineText: string = ''): Integer;
var
  LRect: TRect;
begin
  LRect := ClientRect;

  Result := ClientAndRowToDisplayPosition(LRect.Right, ARow, ALineText).Column;

  if (WordWrap.Enabled and (FWordWrap.Width = wwwRightMargin)) then
    Result := FRightMargin.Position;
end;

function TCustomBCEditor.GetWordAt(ATextPos: TPoint): string;
begin
  Result := GetWordAtTextPosition(TextPosition(ATextPos));
end;

function TCustomBCEditor.GetWordAtPixels(const X, Y: Integer): string;
begin
  Result := GetWordAtTextPosition(TextPosition(ClientToText(X, Y)));
end;

function TCustomBCEditor.GetWordAtTextPosition(const ATextPosition: TBCEditorTextPosition): string;
var
  LBeginPosition: TBCEditorTextPosition;
  LEndPosition: TBCEditorTextPosition;
begin
  if ((ATextPosition.Line >= Lines.Count)
    or (ATextPosition.Char >= Length(Lines.Lines[ATextPosition.Line].Text))) then
    Result := ''
  else
  begin
    LEndPosition := Min(ATextPosition, Lines.EOLPosition[ATextPosition.Line]);
    if ((LEndPosition.Char > 0)
      and not IsWordBreakChar(Lines.Char[LEndPosition])
      and IsWordBreakChar(Lines.Char[LEndPosition])) then
      Dec(LEndPosition.Char);
    if (IsWordBreakChar(Lines.Char[LEndPosition])) then
      Result := ''
    else
    begin
      LBeginPosition := WordBegin(LEndPosition);
      LEndPosition := WordEnd(LEndPosition);
      Result := Copy(Lines.Lines[LBeginPosition.Line].Text, 1 + LBeginPosition.Char, LEndPosition.Char - LBeginPosition.Char + 1);
    end;
  end;
end;

procedure TCustomBCEditor.GotoBookmark(const AIndex: Integer);
var
  LBookmark: TBCEditorMark;
  LTextPosition: TBCEditorTextPosition;
begin
  LBookmark := FBookmarkList.Find(AIndex);
  if Assigned(LBookmark) then
  begin
    LTextPosition.Char := LBookmark.Char - 1;
    LTextPosition.Line := LBookmark.Line;

    GotoLineAndCenter(LTextPosition.Line, LTextPosition.Char);
  end;
end;

procedure TCustomBCEditor.GotoLineAndCenter(const ALine: Integer; const AChar: Integer = 1);
var
  LIndex: Integer;
  LRange: TBCEditorCodeFolding.TRanges.TRange;
begin
  if (FCodeFolding.Visible) then
    for LIndex := 0 to FAllCodeFoldingRanges.AllCount - 1 do
    begin
      LRange := FAllCodeFoldingRanges[LIndex];
      if LRange.FirstLine >= ALine then
        Break
      else if LRange.Collapsed then
        ExpandCodeFoldingRange(LRange);
    end;

  Lines.CaretPosition := TextPosition(AChar, ALine);
  TopRow := Max(0, DisplayCaretPosition.Row - VisibleRows div 2);
end;

procedure TCustomBCEditor.GotoNextBookmark;
var
  LIndex: Integer;
  LMark: TBCEditorMark;
begin
  for LIndex := 0 to FBookmarkList.Count - 1 do
  begin
    LMark := FBookmarkList.Items[LIndex];
    if (LMark.Line > Lines.CaretPosition.Line) or
      (LMark.Line = Lines.CaretPosition.Line) and (LMark.Char - 1 > Lines.CaretPosition.Char) then
    begin
      GotoBookmark(LMark.Index);
      Exit;
    end;
  end;
  if FBookmarkList.Count > 0 then
    GotoBookmark(FBookmarkList.Items[0].Index);
end;

procedure TCustomBCEditor.GotoPreviousBookmark;
var
  LIndex: Integer;
  LMark: TBCEditorMark;
begin
  for LIndex := FBookmarkList.Count - 1 downto 0 do
  begin
    LMark := FBookmarkList.Items[LIndex];
    if (LMark.Line < Lines.CaretPosition.Line) or
      (LMark.Line = Lines.CaretPosition.Line) and (LMark.Char - 1 < Lines.CaretPosition.Char) then
    begin
      GotoBookmark(LMark.Index);
      Exit;
    end;
  end;
  if FBookmarkList.Count > 0 then
    GotoBookmark(FBookmarkList.Items[FBookmarkList.Count - 1].Index);
end;

procedure TCustomBCEditor.HideCaret;
begin
  if esCaretVisible in FState then
    if Windows.HideCaret(Handle) then
      Exclude(FState, esCaretVisible);
end;

procedure TCustomBCEditor.HookEditorLines(ALines: TBCEditorLines; AUndo, ARedo: TBCEditorLines.TUndoList);
var
  LOldWrap: Boolean;
begin
  Assert(not Assigned(FChainedEditor));
  Assert(Lines = FOriginalLines);

  LOldWrap := WordWrap.Enabled;
  UpdateWordWrap(False);

  if Assigned(FChainedEditor) then
    RemoveChainedEditor
  else
  if Lines <> FOriginalLines then
    UnhookEditorLines;

  with ALines do
  begin
    FOnChainLinesCleared := OnCleared; OnCleared := ChainLinesCleared;
    FOnChainLinesDeleted := OnDeleted; OnDeleted := ChainLinesDeleted;
    FOnChainLinesInserted := OnInserted; OnInserted := ChainLinesInserted;
    FOnChainLinesUpdated := OnUpdated; OnUpdated := ChainLinesUpdated;
  end;

  FLines := ALines;
  LinesHookChanged;

  UpdateWordWrap(LOldWrap);
end;

procedure TCustomBCEditor.InitCodeFolding;
begin
  ClearCodeFolding;
  if FCodeFolding.Visible then
  begin
    ScanCodeFoldingRanges;
    CodeFoldingResetCaches;
  end;
end;

procedure TCustomBCEditor.InsertLine();
begin
  if (SelectionAvailable) then
    SelText := Lines.LineBreak
  else
    Lines.InsertText(Lines.CaretPosition, Lines.LineBreak);
end;

procedure TCustomBCEditor.InsertLineIntoRows(const ALine: Integer; const ANewLine: Boolean);
var
  LCodeFolding: Integer;
  LInsertedRows: Integer;
  LLeftRow: Integer;
  LRange: TBCEditorCodeFolding.TRanges.TRange;
  LRightRow: Integer;
  LRow: Integer;
begin
  if (FRows.Count > 0) then
  begin
    for LCodeFolding := 0 to FAllCodeFoldingRanges.AllCount - 1 do
    begin
      LRange := FAllCodeFoldingRanges[LCodeFolding];
      if (Assigned(LRange)
        and LRange.Collapsed
        and (LRange.FirstLine < ALine) and (ALine <= LRange.LastLine)) then
        Exit;
    end;

    LRow := 0;
    LLeftRow := 0;
    LRightRow := FRows.Count - 1;
    while (LLeftRow <= LRightRow) do
    begin
      LRow := (LLeftRow + LRightRow) div 2;
      case (Sign(FRows[LRow].Line - ALine)) of
        -1: begin LLeftRow := LRow + 1; Inc(LRow); end;
        0: break;
        1: begin LRightRow := LRow - 1; Dec(LRow); end;
      end;
    end;

    while ((LRow < FRows.Count) and not (rfFirstRowOfLine in FRows[LRow].Flags)) do
      Inc(LRow);

    LInsertedRows := InsertLineIntoRows(ALine, LRow);

    if (ANewLine) then
      for LRow := LRow + LInsertedRows to FRows.Count - 1 do
        FRows.Line[LRow] := FRows.Line[LRow] + 1;
  end;
end;

function TCustomBCEditor.InsertLineIntoRows(const ALine: Integer; const ARow: Integer): Integer;
var
  LColumnIndex: Integer;
  LFlags: TRow.TFlags;
  LHighlighterAttribute: TBCEditorHighlighter.TAttribute;
  LLine: Integer;
  LLineIndex: Integer;
  LMaxRowWidth: Integer;
  LRow: Integer;
  LRowLength: Integer;
  LRowWidth: Integer;
  LTokenBeginPos: PChar;
  LTokenEndPos: PChar;
  LTokenPos: PChar;
  LTokenPrevPos: PChar;
  LTokenRowBeginPos: PChar;
  LTokenRowWidth: Integer;
  LTokenText: string;
  LTokenWidth: Integer;
begin
  ClearMatchingPair();

  if (not WordWrap.Enabled) then
  begin
    LRowWidth := ComputeTokenWidth(Lines.Lines[ALine].Text, Length(Lines.Lines[ALine].Text), 0);
    FRows.Insert(ARow, [rfFirstRowOfLine, rfLastRowOfLine], ALine, 0, Length(Lines.Lines[ALine].Text), LRowWidth);
    Result := 1;
  end
  else
  begin
    LRow := ARow;
    LFlags := [rfFirstRowOfLine];
    LMaxRowWidth := WordWrapWidth();
    if ALine = 0 then
      FHighlighter.ResetCurrentRange
    else
      FHighlighter.SetCurrentRange(Lines.Lines[ALine - 1].Range);
    FHighlighter.SetCurrentLine(Lines.Lines[ALine].Text);

    LRowWidth := 0;
    LRowLength := 0;
    LColumnIndex := 0;
    LLineIndex := 0;
    while (not FHighlighter.GetEndOfLine()) do
    begin
      FHighlighter.GetTokenText(LTokenText);
      LHighlighterAttribute := FHighlighter.GetTokenAttribute();
      if (Assigned(LHighlighterAttribute)) then
        FPaintHelper.SetStyle(LHighlighterAttribute.FontStyles);

      LTokenWidth := ComputeTokenWidth(LTokenText, Length(LTokenText), LColumnIndex);

      if (LRowWidth + LTokenWidth <= LMaxRowWidth) then
      begin
        { no row break in token }
        Inc(LRowLength, Length(LTokenText));
        Inc(LRowWidth, LTokenWidth);
        Inc(LColumnIndex, ComputeTextColumns(LTokenText, LColumnIndex));
      end
      else if (LRowLength > 0) then
      begin
        { row break before token }
        FRows.Insert(LRow, LFlags, ALine, LLineIndex, LRowLength, LRowWidth);
        Exclude(LFlags, rfFirstRowOfLine);
        Inc(LLineIndex, LRowLength);
        Inc(LRow);

        LRowLength := Length(LTokenText);
        LRowWidth := LTokenWidth;
        LColumnIndex := ComputeTextColumns(LTokenText, LColumnIndex);
      end
      else
      begin
        { row break inside token }

        LTokenBeginPos := @LTokenText[1];
        LTokenPos := LTokenBeginPos;
        LTokenEndPos := @LTokenText[Length(LTokenText)];

        repeat
          LTokenRowBeginPos := LTokenPos;

          Inc(LTokenPos);

          repeat
            LTokenPrevPos := LTokenPos;

            LTokenRowWidth := ComputeTokenWidth(LTokenText, LTokenPos - LTokenRowBeginPos, LColumnIndex);

            if (LTokenRowWidth < LMaxRowWidth) then
              repeat
                Inc(LTokenPos);
              until ((LTokenPos > LTokenEndPos)
                or (Char((LTokenPos - 1)^).GetUnicodeCategory() <> TUnicodeCategory.ucNonSpacingMark) or IsCombiningDiacriticalMark((LTokenPos - 1)^)
                  and not (Char(LTokenPos^).GetUnicodeCategory in [TUnicodeCategory.ucCombiningMark, TUnicodeCategory.ucNonSpacingMark]));
          until ((LTokenPos > LTokenEndPos) or (LTokenRowWidth >= LMaxRowWidth));

          if (LTokenRowWidth >= LMaxRowWidth) then
          begin
            LTokenPos := LTokenPrevPos;

            LRowLength := LTokenPos - LTokenRowBeginPos;
            FRows.Insert(LRow, LFlags, ALine, LLineIndex, LRowLength, LTokenRowWidth);
            Exclude(LFlags, rfFirstRowOfLine);
            Inc(LLineIndex, LRowLength);
            Inc(LRow);

            LRowLength := 0;
            LRowWidth := 0;
            LColumnIndex := 0;
          end
          else
          begin
            LRowLength := LTokenPos - LTokenRowBeginPos;
            LRowWidth := LTokenRowWidth;
            LColumnIndex := ComputeTextColumns(Copy(LTokenText,1 + LTokenRowBeginPos - LTokenBeginPos, LRowLength), LColumnIndex);
          end;
        until ((LTokenPos > LTokenEndPos) or (LTokenRowWidth < LMaxRowWidth));
      end;

      FHighlighter.Next();
    end;

    if ((LRowLength > 0) or (Lines.Lines[ALine].Text = '')) then
    begin
      FRows.Insert(LRow, LFlags + [rfLastRowOfLine], ALine, LLineIndex, LRowLength, LRowWidth);
      Inc(LRow);
    end;

    Result := LRow - ARow;
  end;

  Lines.SetFirstRow(ALine, ARow);
  for LLine := ALine + 1 to Lines.Count - 1 do
    if (Lines.Lines[LLine].FirstRow >= ARow) then
      Lines.SetFirstRow(LLine, Lines.Lines[LLine].FirstRow + Result);

  if (FMultiCaretPosition.Row >= ARow) then
    Inc(FMultiCaretPosition.Row, Result);

  if (UpdateCount > 0) then
    Include(FState, esRowsChanged)
  else
  begin
    UpdateScrollBars();
    Invalidate();
  end;
end;

function TCustomBCEditor.IsCommentAtCaretPosition(): Boolean;
var
  LCommentAtCaret: string;

  function CheckComment(AComment: string): Boolean;
  begin
    Result := (Length(LCommentAtCaret) >= Length(AComment))
      and (StrLIComp(PChar(AComment), PChar(LCommentAtCaret), Length(AComment)) = 0);
  end;

var
  LIndex: Integer;
  LTextPosition: TBCEditorTextPosition;
begin
  Result := False;

  if (FCodeFolding.Visible
    and Assigned(FHighlighter)
    and ((Length(FHighlighter.Comments.BlockComments) > 0) or (Length(FHighlighter.Comments.LineComments) > 0))) then
  begin
    LTextPosition := Lines.CaretPosition;

    Dec(LTextPosition.Char);
    LCommentAtCaret := GetCommentAtTextPosition(LTextPosition);

    if LCommentAtCaret <> '' then
    begin
      LIndex := 0;
      while (LIndex < Length(FHighlighter.Comments.BlockComments)) do
      begin
        if (CheckComment(FHighlighter.Comments.BlockComments[LIndex])) then
          Exit(True);
        if (CheckComment(FHighlighter.Comments.BlockComments[LIndex + 1])) then
          Exit(True);
        Inc(LIndex, 2);
      end;
      for LIndex := 0 to Length(FHighlighter.Comments.LineComments) - 1 do
        if (CheckComment(FHighlighter.Comments.LineComments[LIndex])) then
          Exit(True);
    end;
  end;
end;

function TCustomBCEditor.IsCommentChar(const AChar: Char): Boolean;
begin
  Result := Assigned(FHighlighter) and CharInSet(AChar, FHighlighter.Comments.Chars);
end;

function TCustomBCEditor.IsEmptyChar(const AChar: Char): Boolean;
begin
  Result := CharInSet(AChar, BCEDITOR_EMPTY_CHARACTERS);
end;

function TCustomBCEditor.IsKeywordAtPosition(const APosition: TBCEditorTextPosition;
  const APOpenKeyWord: PBoolean = nil; const AHighlightAfterToken: Boolean = True): Boolean;
var
  LLineEndPos: PChar;
  LLinePos: PChar;

  function CheckToken(const AKeyword: string; const ABeginWithBreakChar: Boolean): Boolean;
  var
    LWordAtCaret: PChar;
  begin
    LWordAtCaret := LLinePos;
    if ABeginWithBreakChar then
      Dec(LWordAtCaret);

    Result := (LLineEndPos + 1 - LWordAtCaret >= Length(AKeyword))
      and (StrLIComp(PChar(AKeyword), LWordAtCaret, Length(AKeyword)) = 0);

    if (Assigned(APOpenKeyWord)) then
      APOpenKeyWord^ := Result;
  end;

var
  LFoldRegion: TBCEditorCodeFolding.TRegion;
  LFoldRegionItem: TBCEditorCodeFoldingRegionItem;
  LIndex1: Integer;
  LIndex2: Integer;
  LLineBeginPos: PChar;
begin
  Result := False;

  if (FCodeFolding.Visible
    and Assigned(FHighlighter)
    and (Length(FHighlighter.CodeFoldingRegions) > 0)
    and (Lines.CaretPosition.Line < Lines.Count)
    and (Lines.Lines[Lines.CaretPosition.Line].Text <> '')
    and (Lines.CaretPosition.Char > 0)) then
  begin
    LLineBeginPos := @Lines.Lines[Lines.CaretPosition.Line].Text[1];
    LLinePos := @Lines.Lines[Lines.CaretPosition.Line].Text[Lines.CaretPosition.Char];
    LLineEndPos := @Lines.Lines[Lines.CaretPosition.Line].Text[Length(Lines.Lines[Lines.CaretPosition.Line].Text)];

    if (not IsWordBreakChar(LLinePos^)) then
    begin
      while ((LLinePos >= LLineBeginPos) and not IsWordBreakChar(LLinePos^)) do
        Dec(LLinePos);
      Inc(LLinePos);
    end;

    for LIndex1 := 0 to Length(FHighlighter.CodeFoldingRegions) - 1 do
    begin
      LFoldRegion := FHighlighter.CodeFoldingRegions[LIndex1];

      for LIndex2 := 0 to LFoldRegion.Count - 1 do
      begin
        LFoldRegionItem := LFoldRegion.Items[LIndex2];
        if CheckToken(LFoldRegionItem.OpenToken, LFoldRegionItem.BeginWithBreakChar) then
          Exit(True);

        if LFoldRegionItem.OpenTokenCanBeFollowedBy <> '' then
          if CheckToken(LFoldRegionItem.OpenTokenCanBeFollowedBy, LFoldRegionItem.BeginWithBreakChar) then
            Exit(True);

        if CheckToken(LFoldRegionItem.CloseToken, LFoldRegionItem.BeginWithBreakChar) then
          Exit(True);
      end;
    end;
  end;
end;

function TCustomBCEditor.IsKeywordAtPositionOrAfter(const APosition: TBCEditorTextPosition): Boolean;

  function IsValidChar(const ACharacter: Char): Boolean; inline;
  begin
    Result := ACharacter.IsUpper or ACharacter.IsNumber;
  end;

  function IsWholeWord(const AFirstChar, ALastChar: Char): Boolean; inline;
  begin
    Result := not IsValidChar(AFirstChar) and not IsValidChar(ALastChar);
  end;

var
  LCaretPosition: TBCEditorTextPosition;
  LFoldRegion: TBCEditorCodeFolding.TRegion;
  LFoldRegionItem: TBCEditorCodeFoldingRegionItem;
  LIndex1: Integer;
  LIndex2: Integer;
  LLineBeginPos: PChar;
  LLineEndPos: PChar;
  LLinePos: PChar;
  LPBookmarkText: PChar;
  LPos: PChar;
  LTokenEndPos: PChar;
  LTokenPos: PChar;
begin
  Result := False;

  if (FCodeFolding.Visible
    and Assigned(FHighlighter)
    and (Length(FHighlighter.CodeFoldingRegions) > 0)
    and (APosition.Char > 0)
    and (Lines.Lines[APosition.Line].Text <> '')) then
  begin
    LLineBeginPos := @Lines.Lines[APosition.Line].Text[1];
    LLinePos := @Lines.Lines[APosition.Line].Text[APosition.Char];
    LLineEndPos := @Lines.Lines[APosition.Line].Text[Length(Lines.Lines[APosition.Line].Text)];

    LCaretPosition := APosition;

    if (not IsWordBreakChar(LLinePos^)) then
    begin
      while ((LLinePos >= LLineBeginPos) and not IsWordBreakChar(LLinePos^)) do
        Dec(LLinePos);
      Inc(LLinePos);
    end;

    if (LLinePos <= LLineEndPos) then
      for LIndex1 := 0 to Length(FHighlighter.CodeFoldingRegions) - 1 do
      begin
        LFoldRegion := FHighlighter.CodeFoldingRegions[LIndex1];
        for LIndex2 := 0 to LFoldRegion.Count - 1 do
        begin
          LFoldRegionItem := LFoldRegion.Items[LIndex2];
          LPos := LLinePos;
          if (LFoldRegionItem.BeginWithBreakChar) then
            Dec(LPos);
          while (LPos <= LLineEndPos) do
          begin
            while ((LPos <= LLineEndPos) and (LPos^ < BCEDITOR_EXCLAMATION_MARK)) do
              Inc(LPos);

            LPBookmarkText := LPos;

            { Check if the open keyword found }
            if (LFoldRegionItem.OpenToken <> '') then
            begin
              LTokenPos := @LFoldRegionItem.OpenToken[1];
              LTokenEndPos := @LFoldRegionItem.OpenToken[Length(LFoldRegionItem.OpenToken)];
              while ((LPos >= LLineEndPos) and (LTokenPos >= LTokenEndPos))
                and (CaseUpper(LPos^) = LTokenPos^) do
              begin
                Inc(LPos);
                Inc(LTokenPos);
              end;
              if (LTokenPos > LTokenEndPos) then { If found, pop skip region from the stack }
              begin
                if (IsWholeWord((LPBookmarkText - 1)^, LPos^)) then { Not interested in partial hits }
                  Exit(True)
                else
                  LPos := LPBookmarkText;
                  { Skip region close not found, return pointer back }
              end
              else
                LPos := LPBookmarkText;
                { Skip region close not found, return pointer back }
            end;

            { Check if the close keyword found }
            if (LFoldRegionItem.CloseToken <> '') then
            begin
              LTokenPos := @LFoldRegionItem.CloseToken[1];
              LTokenEndPos := @LFoldRegionItem.CloseToken[Length(LFoldRegionItem.CloseToken)];

              while ((LPos <= LLineEndPos) and (LTokenPos <= LTokenEndPos)
                and (CaseUpper(LPos^) = LTokenPos^)) do
              begin
                Inc(LPos);
                Inc(LTokenPos);
              end;
              if (LTokenPos > LTokenEndPos) then { If found, pop skip region from the stack }
              begin
                if (IsWholeWord((LPBookmarkText - 1)^, LPos^)) then { Not interested in partial hits }
                  Exit(True)
                else
                  LPos := LPBookmarkText;
                { Skip region close not found, return pointer back }
              end
              else
                LPos := LPBookmarkText;
              { Skip region close not found, return pointer back }

              Inc(LPos);
              { Skip until next word }
              while ((LPos >= LLineEndPos) and IsValidChar((LPos - 1)^)) do
                Inc(LPos);
            end;
          end;
        end;
      end;
  end;
end;

function TCustomBCEditor.IsMultiEditCaretFound(const ALine: Integer): Boolean;
var
  LIndex: Integer;
begin
  Result := False;
  if Assigned(FMultiCarets) and (FMultiCarets.Count > 0) then
    if meoShowActiveLine in FCaret.MultiEdit.Options then
      for LIndex := 0 to FMultiCarets.Count - 1 do
        if Rows[FMultiCarets[LIndex].Row].Line = ALine then
          Exit(True);
end;

function TCustomBCEditor.IsTextPositionInSearchBlock(const ATextPosition: TBCEditorTextPosition): Boolean;
var
  LSelectionBeginPosition: TBCEditorTextPosition;
  LSelectionEndPosition: TBCEditorTextPosition;
begin
  Result := False;

  LSelectionBeginPosition := FSearch.InSelection.SelectionBeginPosition;
  LSelectionEndPosition := FSearch.InSelection.SelectionEndPosition;

  if Lines.SelMode = smNormal then
    Result :=
      ((ATextPosition.Line > LSelectionBeginPosition.Line) or
       (ATextPosition.Line = LSelectionBeginPosition.Line) and (ATextPosition.Char >= LSelectionBeginPosition.Char))
      and
      ((ATextPosition.Line < LSelectionEndPosition.Line) or
       (ATextPosition.Line = LSelectionEndPosition.Line) and (ATextPosition.Char <= LSelectionEndPosition.Char))
  else
  if Lines.SelMode = smColumn then
    Result :=
      ((ATextPosition.Line >= LSelectionBeginPosition.Line) and (ATextPosition.Char >= LSelectionBeginPosition.Char))
      and
      ((ATextPosition.Line <= LSelectionEndPosition.Line) and (ATextPosition.Char <= LSelectionEndPosition.Char));
end;

function TCustomBCEditor.IsWordBreakChar(const AChar: Char): Boolean;
begin
  Result := Lines.IsWordBreakChar(AChar);
end;

function TCustomBCEditor.IsWordSelected(): Boolean;
begin
  Result := SelectionAvailable and (SelText = GetWordAtTextPosition(Lines.SelBeginPosition));
end;

procedure TCustomBCEditor.KeyDown(var AKey: Word; AShift: TShiftState);
var
  LChar: Char;
  LCursorPoint: TPoint;
  LData: Pointer;
  LEditorCommand: TBCEditorCommand;
  LHighlighterAttribute: TBCEditorHighlighter.TAttribute;
  LRangeType: TBCEditorRangeType;
  LSecondaryShortCutKey: Word;
  LSecondaryShortCutShift: TShiftState;
  LShortCutKey: Word;
  LShortCutShift: TShiftState;
  LStart: Integer;
  LTextPosition: TBCEditorTextPosition;
  LToken: string;
begin
  inherited;

  if AKey = 0 then
  begin
    Include(FState, esIgnoreNextChar);
    Exit;
  end;

  if FCaret.MultiEdit.Enabled and Assigned(FMultiCarets) and (FMultiCarets.Count > 0) then
    if (AKey = BCEDITOR_CARRIAGE_RETURN_KEY) or (AKey = BCEDITOR_ESCAPE_KEY) then
    begin
      FreeMultiCarets;
      Invalidate;
      Exit;
    end;

  if FSyncEdit.Enabled then
  begin
    if FSyncEdit.Active then
      if (AKey = BCEDITOR_CARRIAGE_RETURN_KEY) or (AKey = BCEDITOR_ESCAPE_KEY) then
      begin
        FSyncEdit.Active := False;
        AKey := 0;
        Exit;
      end;

    ShortCutToKey(FSyncEdit.ShortCut, LShortCutKey, LShortCutShift);
    if (AShift = LShortCutShift) and (AKey = LShortCutKey) then
    begin
      FSyncEdit.Active := not FSyncEdit.Active;
      AKey := 0;
      Exit;
    end;
  end;

  FKeyboardHandler.ExecuteKeyDown(Self, AKey, AShift);

  { URI mouse over }
  if (ssCtrl in AShift) and URIOpener then
  begin
    GetCursorPos(LCursorPoint);
    LCursorPoint := ScreenToClient(LCursorPoint);
    LTextPosition := TextPosition(ClientToText(LCursorPoint.X, LCursorPoint.Y));
    GetHighlighterAttributeAtRowColumn(LTextPosition, LToken, LRangeType, LStart, LHighlighterAttribute);
    FMouseOverURI := LRangeType in [ttWebLink, ttMailtoLink];
  end;

  LData := nil;
  LChar := BCEDITOR_NONE_CHAR;
  try
    LEditorCommand := TranslateKeyCode(AKey, AShift, LData);

    if not ReadOnly and FCompletionProposal.Enabled and not Assigned(FCompletionProposalPopupWindow) then
    begin
      ShortCutToKey(FCompletionProposal.ShortCut, LShortCutKey, LShortCutShift);
      ShortCutToKey(FCompletionProposal.SecondaryShortCut, LSecondaryShortCutKey, LSecondaryShortCutShift);

      if ((AKey = LShortCutKey) and (AShift = LShortCutShift)
        or (AKey = LSecondaryShortCutKey) and (AShift = LSecondaryShortCutShift)
        or (AKey <> LShortCutKey) and not (ssAlt in AShift) and not (ssCtrl in AShift) and (cpoAutoInvoke in FCompletionProposal.Options) and Chr(AKey).IsLetter) then
      begin
        LEditorCommand := ecCompletionProposal;
        if not (cpoAutoInvoke in FCompletionProposal.Options) then
        begin
          AKey := 0;
          Include(FState, esIgnoreNextChar);
        end;
      end;
    end;

    if FSyncEdit.Active then
    begin
      case LEditorCommand of
        ecChar, ecBackspace, ecCopy, ecCut, ecLeft, ecSelectionLeft, ecRight, ecSelectionRight:
          ;
        ecLineBreak:
          FSyncEdit.Active := False;
      else
        LEditorCommand := ecNone;
      end;
    end;

    if LEditorCommand <> ecNone then
    begin
      AKey := 0;
      Include(FState, esIgnoreNextChar);
      CommandProcessor(LEditorCommand, LChar, LData);
    end
    else
      Exclude(FState, esIgnoreNextChar);
  finally
    if Assigned(LData) then
      FreeMem(LData);
  end;

  if FCodeFolding.Visible then
  begin
    FCodeFoldingDelayTimer.Enabled := False;
    if FCodeFoldingDelayTimer.Interval <> FCodeFolding.DelayInterval then
      FCodeFoldingDelayTimer.Interval := FCodeFolding.DelayInterval;
    FCodeFoldingDelayTimer.Enabled := True;
  end;
end;

procedure TCustomBCEditor.KeyPressW(var AKey: Char);
begin
  if not (esIgnoreNextChar in FState) then
  begin
    FKeyboardHandler.ExecuteKeyPress(Self, AKey);
    CommandProcessor(ecChar, AKey, nil);
  end
  else
    Exclude(FState, esIgnoreNextChar);
end;

procedure TCustomBCEditor.KeyUp(var AKey: Word; AShift: TShiftState);
begin
  inherited;

  if FMouseOverURI then
    FMouseOverURI := False;

  if FCodeFolding.Visible then
    CheckIfAtMatchingKeywords;

  FKeyboardHandler.ExecuteKeyUp(Self, AKey, AShift);

  if (FMultiCaretPosition.Row >= 0) then
  begin
    FMultiCaretPosition.Row := -1;
    Invalidate;
  end;
end;

procedure TCustomBCEditor.LeftMarginChanged(ASender: TObject);
begin
  DoLeftMarginAutoSize();
end;

function TCustomBCEditor.LeftSpaceCount(const AText: string; AWantTabs: Boolean = False): Integer;
var
  LTextEndPos: PChar;
  LTextPos: PChar;
begin
  if ((AText = '') or not (eoAutoIndent in FOptions)) then
    Result := 0
  else
  begin
    LTextPos := @AText[1];
    LTextEndPos := @AText[Length(AText)];
    Result := 0;
    while ((LTextPos <= LTextEndPos) and (LTextPos^ <= BCEDITOR_SPACE_CHAR)) do
    begin
      if ((LTextPos^ = BCEDITOR_TAB_CHAR) and AWantTabs) then
        if toColumns in FTabs.Options then
          Inc(Result, FTabs.Width - Result mod FTabs.Width)
        else
          Inc(Result, FTabs.Width)
      else
        Inc(Result);
      Inc(LTextPos);
    end;
  end;
end;

function TCustomBCEditor.LeftTrimLength(const AText: string): Integer;
begin
  Result := 0;
  while ((Result < Length(AText)) and (AText[1 + Result] <= BCEDITOR_SPACE_CHAR)) do
    Inc(Result);
end;

procedure TCustomBCEditor.CaretMoved(ASender: TObject);
begin
  if (FUpdateCount > 0) then
    Include(FState, esCaretMoved)
  else
  begin
    UpdateCaret();
    ScanMatchingPair();
    ScrollToCaret();
  end;
end;

procedure TCustomBCEditor.LineDeleted(ASender: TObject; const ALine: Integer);
var
  LIndex: Integer;

  procedure UpdateMarks(AMarkList: TBCEditorMarkList);
  var
    LMark: TBCEditorMark;
    LMarkIndex: Integer;
  begin
    for LMarkIndex := 0 to AMarkList.Count - 1 do
    begin
      LMark := AMarkList[LMarkIndex];
      if LMark.Line >= LIndex then
        LMark.Line := LMark.Line - 1;
    end;
  end;

begin
  UpdateMarks(FBookmarkList);
  UpdateMarks(FMarkList);

  if (FCodeFolding.Visible) then
    CodeFoldingLinesDeleted(LIndex + 1);

  if (Assigned(FHighlighter) and (LIndex < Lines.Count)) then
  begin
    LIndex := Max(LIndex, 1);
    if (LIndex < Lines.Count) then
      RescanHighlighterRangesFrom(LIndex);
  end;

  CodeFoldingResetCaches;

  DeleteLineFromRows(ALine);

  Modified := True;

  if (UpdateCount > 0) then
    Include(FState, esLinesDeleted)
  else
  begin
    ScanMatchingPair();

    if (LeftMargin.LineNumbers.Visible and LeftMargin.Autosize) then
      LeftMargin.AutosizeDigitCount(Lines.Count);
    if (HandleAllocated) then
      UpdateScrollBars();
    Invalidate();

    if (Assigned(OnChange)) then
      OnChange(Self);
  end;
end;

procedure TCustomBCEditor.LineInserted(ASender: TObject; const ALine: Integer);

  procedure UpdateMarks(AMarkList: TBCEditorMarkList);
  var
    LIndex: Integer;
    LMark: TBCEditorMark;
  begin
    for LIndex := 0 to AMarkList.Count - 1 do
    begin
      LMark := AMarkList[LIndex];
      if LMark.Line >= ALine then
        LMark.Line := LMark.Line + 1;
    end;
  end;

begin
  UpdateMarks(FBookmarkList);
  UpdateMarks(FMarkList);

  if FCodeFolding.Visible then
    UpdateFoldRanges(ALine + 1, 1);

  if (Assigned(FHighlighter)) then
    RescanHighlighterRangesFrom(ALine);

  InsertLineIntoRows(ALine, True);
  CodeFoldingResetCaches;

  Modified := True;

  if (UpdateCount > 0) then
    Include(FState, esLinesInserted)
  else
  begin
    ScanMatchingPair();

    if (LeftMargin.LineNumbers.Visible and LeftMargin.Autosize) then
      LeftMargin.AutosizeDigitCount(Lines.Count);
    if (HandleAllocated) then
      UpdateScrollBars();
    Invalidate();

    if (Assigned(OnChange)) then
      OnChange(Self);
  end;
end;

procedure TCustomBCEditor.LineUpdated(ASender: TObject; const ALine: Integer);
begin
  UpdateRows(ALine);

  if (Assigned(FHighlighter)) then
    RescanHighlighterRangesFrom(ALine);

  if FCodeFolding.Visible then
    UpdateFoldRanges(ALine + 1, 1);

  Modified := True;

  if (UpdateCount > 0) then
    Include(FState, esLinesUpdated)
  else
  begin
    ScanMatchingPair();

    Invalidate();

    if (Assigned(OnChange)) then
      OnChange(Self);
  end;
end;

procedure TCustomBCEditor.LinesCleared(ASender: TObject);
begin
  ClearCodeFolding;
  ClearMatchingPair;
  ClearBookmarks;
  FMarkList.Clear;
  FRows.Clear();
  FMultiCaretPosition.Row := -1;

  Modified := True;

  if (UpdateCount > 0) then
    Include(FState, esLinesCleared)
  else
  begin
    InitCodeFolding();
    
    if (LeftMargin.LineNumbers.Visible and LeftMargin.Autosize) then
      LeftMargin.AutosizeDigitCount(Lines.Count);
    if (HandleAllocated) then
      UpdateScrollBars();
    Invalidate();

    if (Assigned(OnChange)) then
      OnChange(Self);
  end;
end;

procedure TCustomBCEditor.LinesHookChanged;
begin
  UpdateScrollBars;
  Invalidate;
end;

procedure TCustomBCEditor.LoadFromFile(const AFileName: string; AEncoding: TEncoding = nil);
begin
  Lines.LoadFromFile(AFileName, AEncoding);
end;

procedure TCustomBCEditor.LoadFromStream(AStream: TStream; AEncoding: TEncoding = nil);
begin
  Lines.LoadFromStream(AStream, AEncoding);
end;

procedure TCustomBCEditor.MarkListChange(ASender: TObject);
begin
  Invalidate;
end;

procedure TCustomBCEditor.MouseDown(AButton: TMouseButton; AShift: TShiftState; X, Y: Integer);
var
  LDisplayPosition: TBCEditorDisplayPosition;
  LRow: Integer;
  LRowCount: Integer;
  LSelectedRow: Integer;
  LSelectionAvailable: Boolean;
  LTextCaretPosition: TBCEditorTextPosition;
begin
  Lines.UndoGroupBreak();

  LSelectionAvailable := SelectionAvailable;
  LSelectedRow := ClientToDisplayRow(X, Y);

  if AButton = mbLeft then
  begin
    FMouseDownX := X;
    FMouseDownY := Y;
    FMouseDownTextPosition := TextPosition(ClientToText(X, Y));

    if FCaret.MultiEdit.Enabled and not FMouseOverURI then
    begin
      if ssCtrl in AShift then
      begin
        LDisplayPosition := ClientToDisplay(X, Y);
        if ssShift in AShift then
          AddMultipleCarets(LDisplayPosition)
        else
          AddCaret(LDisplayPosition);
        Invalidate;
        Exit;
      end
      else
        FreeMultiCarets;
    end;
  end;

  if FSearch.Map.Visible then
    if (FSearch.Map.Align = saRight) and (X > ClientRect.Width - FSearch.Map.GetWidth) or (FSearch.Map.Align = saLeft)
      and (X <= FSearch.Map.GetWidth) then
    begin
      DoOnSearchMapClick(AButton, X, Y);
      Exit;
    end;

  if FSyncEdit.Enabled and FSyncEdit.Activator.Visible and not FSyncEdit.Active and LSelectionAvailable then
  begin
    LDisplayPosition := TextToDisplay(SelectionEndPosition);

    if X < LeftMargin.MarksPanel.Width then
    begin
      LRowCount := Y div LineHeight;
      LRow := LDisplayPosition.Row - TopRow;
      if (LRowCount <= LRow) and (LRowCount > LRow - 1) then
      begin
        FSyncEdit.Active := True;
        Exit;
      end;
    end;
  end;

  if FSyncEdit.Enabled and FSyncEdit.BlockSelected then
    if not FSyncEdit.IsTextPositionInBlock(TextPosition(ClientToText(X, Y))) then
      FSyncEdit.Active := False;

  if FSyncEdit.Enabled and FSyncEdit.Active then
  begin
    if not FSyncEdit.IsTextPositionInEdit(TextPosition(ClientToText(X, Y))) then
      FSyncEdit.Active := False
    else
    begin
      Lines.CaretPosition := TextPosition(ClientToText(X, Y));
      Exit;
    end;
  end;

  inherited;

  if (rmoMouseMove in FRightMargin.Options) and FRightMargin.Visible then
    if (AButton = mbLeft) and (Abs(FRightMargin.Position * CharWidth + LeftMarginWidth - X - HorzTextPos) < 3) then
    begin
      FRightMargin.Moving := True;
      FRightMarginMovePosition := FRightMargin.Position * CharWidth + LeftMarginWidth;
      Exit;
    end;

  if (AButton = mbLeft) and FCodeFolding.Visible and FCodeFolding.Hint.Indicator.Visible and
    (cfoUncollapseByHintClick in FCodeFolding.Options) then
    if DoOnCodeFoldingHintClick(Point(X, Y)) then
    begin
      Include(FState, esCodeFoldingInfoClicked);
      FCodeFolding.MouseOverHint := False;
      UpdateMouseCursor;
      Exit;
    end;

  FKeyboardHandler.ExecuteMouseDown(Self, AButton, AShift, X, Y);

  if (AButton = mbLeft) and (ssDouble in AShift) and (X > LeftMarginWidth) then
  begin
    FLastDblClick := GetTickCount;
    FLastRow := LSelectedRow;
    Exit;
  end
  else
  if (soTripleClickRowSelect in FSelection.Options) and (AShift = [ssLeft]) and (FLastDblClick > 0) then
  begin
    if (GetTickCount - FLastDblClick < FDoubleClickTime) and (FLastRow = LSelectedRow) then
    begin
      DoTripleClick;
      Invalidate;
      Exit;
    end;
    FLastDblClick := 0;
  end;

  if ((X + 4 > LeftMarginWidth) and ((AButton = mbLeft) or (AButton = mbRight))) then
  begin
    LTextCaretPosition := TextPosition(ClientToText(X, Y));
    if (AButton = mbLeft) then
    begin
      Lines.CaretPosition := LTextCaretPosition;

      MouseCapture := True;

      Exclude(FState, esWaitForDragging);
      if LSelectionAvailable and (eoDragDropEditing in FOptions) and (X > LeftMarginWidth) and
        (Lines.SelMode = smNormal) and Lines.IsPositionInSelection(LTextCaretPosition) then
        Include(FState, esWaitForDragging);
    end
    else if (AButton = mbRight) then
    begin
      if (coRightMouseClickMove in FCaret.Options) and
        (not LSelectionAvailable or not Lines.IsPositionInSelection(LTextCaretPosition)) then
        Lines.CaretPosition := LTextCaretPosition
      else
        Exit;
    end
  end;

  if soWheelClickMove in FScroll.Options then
  begin
    if (AButton = mbMiddle) and not FMouseMoveScrolling then
    begin
      FMouseMoveScrolling := True;
      FMouseMoveScrollingPoint := Point(X, Y);
      Invalidate;
      Exit;
    end
    else
    if FMouseMoveScrolling then
    begin
      FMouseMoveScrolling := False;
      Invalidate;
      Exit;
    end;
  end;

  if not (esWaitForDragging in FState) then
    if not (esDblClicked in FState) then
    begin
      if ssShift in AShift then
        Lines.SelEndPosition := Lines.CaretPosition
      else
      begin
        if soALTSetsColumnMode in FSelection.Options then
        begin
          if (ssAlt in AShift) and not FAltEnabled then
          begin
            FSaveSelectionMode := Lines.SelMode;
            Lines.SelMode := smColumn;
            FAltEnabled := True;
          end
          else
          if not (ssAlt in AShift) and FAltEnabled then
          begin
            Lines.SelMode := FSaveSelectionMode;
            FAltEnabled := False;
          end;
        end;
        Lines.SelBeginPosition := Lines.CaretPosition;
      end;
    end;

  if X + 4 < LeftMarginWidth then
    DoOnLeftMarginClick(AButton, AShift, X, Y);
end;

procedure TCustomBCEditor.MouseMove(AShift: TShiftState; X, Y: Integer);
var
  LDisplayPosition: TBCEditorDisplayPosition;
  LFoldRange: TBCEditorCodeFolding.TRanges.TRange;
  LHintWindow: THintWindow;
  LIndex: Integer;
  LLine: Integer;
  LMultiCaretPosition: TBCEditorDisplayPosition;
  LPoint: TPoint;
  LPositionText: string;
  LRect: TRect;
  LRow: Integer;
begin
  if FCaret.MultiEdit.Enabled and Focused then
  begin
    if (AShift = [ssCtrl, ssShift]) or (AShift = [ssCtrl]) then
      if (not ShortCutPressed and (meoShowGhost in FCaret.MultiEdit.Options)) then
      begin
        LMultiCaretPosition := ClientToDisplay(X, Y);

        if (FMultiCaretPosition <> LMultiCaretPosition) then
        begin
          FMultiCaretPosition := LMultiCaretPosition;
          Invalidate;
        end;
      end;

    if Assigned(FMultiCarets) and (FMultiCarets.Count > 0) then
      Exit;
  end;

  if FTokenInfo.Enabled then
    DoTokenInfo;

  if FMouseMoveScrolling then
  begin
    ComputeScroll(Point(X, Y));
    Exit;
  end;

  if FSearch.Map.Visible then
    if (FSearch.Map.Align = saRight) and (X > ClientRect.Width - FSearch.Map.GetWidth) or (FSearch.Map.Align = saLeft)
      and (X <= FSearch.Map.GetWidth) then
      Exit;

  inherited MouseMove(AShift, X, Y);

  if FMouseOverURI and not (ssCtrl in AShift) then
    FMouseOverURI := False;

  if (rmoMouseMove in FRightMargin.Options) and FRightMargin.Visible then
  begin
    FRightMargin.MouseOver := Abs(FRightMargin.Position * CharWidth + LeftMarginWidth - X - HorzTextPos) < 3;

    if FRightMargin.Moving then
    begin
      if X > LeftMarginWidth then
        FRightMarginMovePosition := X;
      if rmoShowMovingHint in FRightMargin.Options then
      begin
        LHintWindow := GetRightMarginHint;

        LPositionText := Format(SBCEditorRightMarginPosition,
          [(FRightMarginMovePosition - LeftMarginWidth + HorzTextPos) div CharWidth]);

        LRect := LHintWindow.CalcHintRect(200, LPositionText, nil);
        LPoint := ClientToScreen(Point(ClientWidth - LRect.Right - 4, 4));

        OffsetRect(LRect, LPoint.X, LPoint.Y);
        LHintWindow.ActivateHint(LRect, LPositionText);
        LHintWindow.Invalidate;
      end;
      Invalidate;
      Exit;
    end;
  end;

  if FCodeFolding.Visible and FCodeFolding.Hint.Indicator.Visible and FCodeFolding.Hint.Visible then
  begin
    LRow := ClientToDisplayRow(X, Y);

    if (LRow < Rows.Count) then
    begin
      LLine := Rows[LRow].Line;

      LFoldRange := CodeFoldingCollapsableFoldRangeForLine(LLine);

      if Assigned(LFoldRange) and LFoldRange.Collapsed and not LFoldRange.ParentCollapsed then
      begin
        LPoint := Point(X, Y);
        LRect := LFoldRange.CollapseMarkRect;
        OffsetRect(LRect, -LeftMarginWidth, 0);

        if LRect.Right > LeftMarginWidth then
        begin
          FCodeFolding.MouseOverHint := False;
          if PtInRect(LRect, LPoint) then
          begin
            FCodeFolding.MouseOverHint := True;

            if not Assigned(FCodeFoldingHintForm) then
            begin
              FCodeFoldingHintForm := TBCEditorCodeFoldingHintForm.Create(Self);
              with FCodeFoldingHintForm do
              begin
                BackgroundColor := FCodeFolding.Hint.Colors.Background;
                BorderColor := FCodeFolding.Hint.Colors.Border;
                Font := FCodeFolding.Hint.Font;
              end;

              LLine := LFoldRange.LastLine - LFoldRange.FirstLine;
              if LLine > FCodeFolding.Hint.RowCount then
                LLine := FCodeFolding.Hint.RowCount;
              for LIndex := LFoldRange.FirstLine to LFoldRange.FirstLine + LLine - 1 do
                FCodeFoldingHintForm.ItemList.Add(Lines.ExpandedStrings[LIndex]);
              if LLine = FCodeFolding.Hint.RowCount then
                FCodeFoldingHintForm.ItemList.Add('...');

              LPoint.X := LeftMarginWidth;
              LPoint.Y := LRect.Bottom + 2;
              LPoint := ClientToScreen(LPoint);

              FCodeFoldingHintForm.Execute('', LPoint.X, LPoint.Y);
            end;
          end
          else
            FreeHintForm(FCodeFoldingHintForm);
        end
        else
          FreeHintForm(FCodeFoldingHintForm);
      end
      else
        FreeHintForm(FCodeFoldingHintForm);
    end;
  end;

  { Drag & Drop }
  if MouseCapture and (esWaitForDragging in FState) then
  begin
    if (Abs(FMouseDownX - X) >= GetSystemMetrics(SM_CXDRAG)) or (Abs(FMouseDownY - Y) >= GetSystemMetrics(SM_CYDRAG))
    then
    begin
      Exclude(FState, esWaitForDragging);
      BeginDrag(False);
      Include(FState, esDragging);
      FDragBeginTextCaretPosition := Lines.CaretPosition;
    end;
  end
  else
  if (ssLeft in AShift) and MouseCapture and ((X <> FOldMouseMovePoint.X) or (Y <> FOldMouseMovePoint.Y)) then
  begin
    FOldMouseMovePoint.X := X;
    FOldMouseMovePoint.Y := Y;
    ComputeScroll(FOldMouseMovePoint);
    LDisplayPosition := ClientToDisplay(X, Y);
    if (not (soPastEndOfFile in Scroll.Options)) then
      LDisplayPosition.Row := Min(LDisplayPosition.Row, Rows.Count - 1);
    if FScrollDeltaX <> 0 then
      LDisplayPosition.Column := DisplayCaretPosition.Column;
    if FScrollDeltaY <> 0 then
      LDisplayPosition.Row := DisplayCaretPosition.Row;
    if not (esCodeFoldingInfoClicked in FState) then { No selection when info clicked }
      MoveCaretAndSelection(FMouseDownTextPosition, DisplayToText(LDisplayPosition), True);
    FLastSortOrder := soDesc;
    Include(FState, esInSelection);
    Exclude(FState, esCodeFoldingInfoClicked);
  end;
end;

procedure TCustomBCEditor.MouseMoveScrollTimerHandler(ASender: TObject);
var
  LCursorPoint: TPoint;
begin
  BeginUpdate();

  GetCursorPos(LCursorPoint);
  LCursorPoint := ScreenToClient(LCursorPoint);
  if FScrollDeltaX <> 0 then
  begin
    if GetKeyState(VK_SHIFT) < 0 then
      HorzTextPos := HorzTextPos + TextWidth
    else
      HorzTextPos := HorzTextPos + FScrollDeltaX;
  end;
  if FScrollDeltaY <> 0 then
  begin
    if GetKeyState(VK_SHIFT) < 0 then
      TopRow := TopRow + FScrollDeltaY * VisibleRows
    else
      TopRow := TopRow + FScrollDeltaY;
  end;

  EndUpdate();
  ComputeScroll(LCursorPoint);
end;

procedure TCustomBCEditor.MouseUp(AButton: TMouseButton; AShift: TShiftState; X, Y: Integer);
var
  LCursorPoint: TPoint;
  LHighlighterAttribute: TBCEditorHighlighter.TAttribute;
  LRangeType: TBCEditorRangeType;
  LStart: Integer;
  LTextPosition: TBCEditorTextPosition;
  LToken: string;
begin
  Exclude(FState, esInSelection);

  inherited MouseUp(AButton, AShift, X, Y);

  FKeyboardHandler.ExecuteMouseUp(Self, AButton, AShift, X, Y);

  if FCodeFolding.Visible then
    CheckIfAtMatchingKeywords;

  if FMouseOverURI and (AButton = mbLeft) and (X > LeftMarginWidth) then
  begin
    GetCursorPos(LCursorPoint);
    LCursorPoint := ScreenToClient(LCursorPoint);
    LTextPosition := TextPosition(ClientToText(LCursorPoint.X, LCursorPoint.Y));
    GetHighlighterAttributeAtRowColumn(LTextPosition, LToken, LRangeType, LStart, LHighlighterAttribute);
    OpenLink(LToken, LRangeType);
    Exit;
  end;

  if (rmoMouseMove in FRightMargin.Options) and FRightMargin.Visible then
    if FRightMargin.Moving then
    begin
      FRightMargin.Moving := False;
      if rmoShowMovingHint in FRightMargin.Options then
        ShowWindow(GetRightMarginHint.Handle, SW_HIDE);
      FRightMargin.Position := (FRightMarginMovePosition - LeftMarginWidth + HorzTextPos)
        div CharWidth;
      if Assigned(FOnRightMarginMouseUp) then
        FOnRightMarginMouseUp(Self);
      Invalidate;
      Exit;
    end;

  FMouseMoveScrollTimer.Enabled := False;

  FScrollTimer.Enabled := False;
  if (AButton = mbRight) and (AShift = [ssRight]) and Assigned(PopupMenu) then
    Exit;
  MouseCapture := False;

  if FState * [esDblClicked, esWaitForDragging] = [esWaitForDragging] then
  begin
    Lines.CaretPosition := TextPosition(ClientToText(X, Y));

    if not (ssShift in AShift) then
      Lines.SelBeginPosition := Lines.CaretPosition;
    Lines.SelEndPosition := Lines.CaretPosition;

    Exclude(FState, esWaitForDragging);
  end;
  Exclude(FState, esDblClicked);
end;

procedure TCustomBCEditor.MoveCaretAndSelection(ABeforeTextPosition, AAfterTextPosition: TBCEditorTextPosition;
  const ASelectionCommand: Boolean);
begin
  if (not ASelectionCommand) then
    Lines.CaretPosition := AAfterTextPosition
  else
    SetCaretAndSelection(AAfterTextPosition, Lines.SelBeginPosition, AAfterTextPosition);
end;

procedure TCustomBCEditor.MoveCaretHorizontally(const Cols: Integer;
  const SelectionCommand: Boolean);
var
  LLineEndPos: PChar;
  LLinePos: PChar;
  LLineTextLength: Integer;
  LNewCaretPosition: TBCEditorTextPosition;
begin
  if ((Lines.CaretPosition.Char > 0) or (Cols > 0)) then
    if (Lines.CaretPosition.Line < Lines.Count) then
    begin
      LLineTextLength := Length(Lines.Lines[Lines.CaretPosition.Line].Text);

      LNewCaretPosition := TextPosition(Max(0, Lines.CaretPosition.Char + Cols), Lines.CaretPosition.Line);
      if (not (soPastEndOfLine in FScroll.Options) or WordWrap.Enabled) then
        LNewCaretPosition.Char := Min(LNewCaretPosition.Char, LLineTextLength);

      { Skip combined and non-spacing marks }
      if ((0 < LLineTextLength) and (LNewCaretPosition.Char < LLineTextLength)) then
      begin
        LLinePos := @Lines.Lines[Lines.CaretPosition.Line].Text[1 + LNewCaretPosition.Char];
        LLineEndPos := @Lines.Lines[Lines.CaretPosition.Line].Text[Length(Lines.Lines[Lines.CaretPosition.Line].Text)];
        while ((LLinePos <= LLineEndPos)
          and ((LLinePos^.GetUnicodeCategory in [TUnicodeCategory.ucCombiningMark, TUnicodeCategory.ucNonSpacingMark])
            or ((LLinePos - 1)^ <> BCEDITOR_NONE_CHAR)
              and ((LLinePos - 1)^.GetUnicodeCategory = TUnicodeCategory.ucNonSpacingMark)
              and not IsCombiningDiacriticalMark((LLinePos - 1)^))) do
        begin
          Dec(LLinePos);
          Dec(LNewCaretPosition.Char);
        end;
      end;

      MoveCaretAndSelection(Lines.SelBeginPosition, LNewCaretPosition, SelectionCommand);
    end
    else if ((soPastEndOfLine in FScroll.Options) and not WordWrap.Enabled) then
      MoveCaretAndSelection(Lines.SelBeginPosition, TextPosition(Lines.CaretPosition.Char + Cols, Lines.CaretPosition.Line), SelectionCommand);
end;

procedure TCustomBCEditor.MoveCaretVertically(const ARows: Integer; const SelectionCommand: Boolean);
var
  LDisplayCaretPosition: TBCEditorDisplayPosition;
begin
  LDisplayCaretPosition := DisplayCaretPosition;
  if ((ARows < 0) or (soPastEndOfFile in Scroll.Options)) then
    LDisplayCaretPosition.Row := Max(0, LDisplayCaretPosition.Row + ARows)
  else
    LDisplayCaretPosition.Row := Min(Rows.Count - 1, LDisplayCaretPosition.Row + ARows);
  if ((LDisplayCaretPosition.Row >= Rows.Count)
    and (not (soPastEndOfLine in FScroll.Options) or WordWrap.Enabled)) then
    LDisplayCaretPosition.Column := 0;

  if ((not (soPastEndOfLine in FScroll.Options) or WordWrap.Enabled) and (LDisplayCaretPosition.Row < Rows.Count)) then
    if (not (rfLastRowOfLine in Rows[LDisplayCaretPosition.Row].Flags)) then
      LDisplayCaretPosition.Column := Min(LDisplayCaretPosition.Column, Rows[LDisplayCaretPosition.Row].Length - 1)
    else
      LDisplayCaretPosition.Column := Min(LDisplayCaretPosition.Column, Rows[LDisplayCaretPosition.Row].Length);

  MoveCaretAndSelection(Lines.CaretPosition, DisplayToText(LDisplayCaretPosition), SelectionCommand);
end;

procedure TCustomBCEditor.MoveCharLeft;
var
  LPoint: TPoint;
  LTextPosition: TBCEditorTextPosition;
begin
  FCommandDrop := True;
  try
    LTextPosition := TextPosition(Min(Lines.SelBeginPosition.Char, Lines.SelEndPosition.Char) - 1,
      Min(Lines.SelBeginPosition.Line, Lines.SelEndPosition.Line));
    LPoint := DisplayToClient(TextToDisplay(LTextPosition));
    DragDrop(Self, LPoint.X, LPoint.Y);
  finally
    FCommandDrop := False;
  end;
end;

procedure TCustomBCEditor.MoveCharRight;
var
  LPoint: TPoint;
  LTextPosition: TBCEditorTextPosition;
begin
  FCommandDrop := True;
  try
    LTextPosition := TextPosition(Min(Lines.SelBeginPosition.Char, Lines.SelEndPosition.Char) + 1,
      Min(Lines.SelBeginPosition.Line, Lines.SelEndPosition.Line));
    LPoint := DisplayToClient(TextToDisplay(LTextPosition));
    DragDrop(Self, LPoint.X, LPoint.Y);
  finally
    FCommandDrop := False;
  end;
end;

procedure TCustomBCEditor.MoveLineDown;
var
  LPoint: TPoint;
  LTextPosition: TBCEditorTextPosition;
begin
  FCommandDrop := True;
  try
    LTextPosition := TextPosition(Min(Lines.SelBeginPosition.Char, Lines.SelEndPosition.Char),
      Max(Lines.SelBeginPosition.Line, Lines.SelEndPosition.Line));
    LPoint := DisplayToClient(TextToDisplay(LTextPosition));
    Inc(LPoint.Y, LineHeight);
    DragDrop(Self, LPoint.X, LPoint.Y);
  finally
    FCommandDrop := False;
  end;
end;

procedure TCustomBCEditor.MoveLineUp;
var
  LPoint: TPoint;
  LTextPosition: TBCEditorTextPosition;
begin
  FCommandDrop := True;
  try
    LTextPosition := TextPosition(Min(Lines.SelBeginPosition.Char, Lines.SelEndPosition.Char),
      Min(Lines.SelBeginPosition.Line, Lines.SelEndPosition.Line));
    LPoint := DisplayToClient(TextToDisplay(LTextPosition));
    Dec(LPoint.Y, LineHeight);
    DragDrop(Self, LPoint.X, LPoint.Y);
  finally
    FCommandDrop := False;
  end;
end;

procedure TCustomBCEditor.MultiCaretTimerHandler(ASender: TObject);
begin
  FDrawMultiCarets := not FDrawMultiCarets;
  Invalidate;
end;

function TCustomBCEditor.NextWordPosition(const ATextPosition: TBCEditorTextPosition): TBCEditorTextPosition;
begin
  if (ATextPosition.Line >= Lines.Count) then
    Result := Lines.EOFPosition
  else
  begin
    Result := Min(ATextPosition, Lines.EOLPosition[ATextPosition.Line]);
    if (Result.Char < Length(Lines.Lines[Result.Line].Text)) then
      while ((Result.Char < Length(Lines.Lines[Result.Line].Text)) and IsWordBreakChar(Lines.Char[Result])) do
        Inc(Result.Char)
    else if (Result.Line < Lines.Count - 1) then
    begin
      Result := Lines.BOLPosition[Result.Line + 1];
      while ((Result.Char + 1 < Length(Lines.Lines[Result.Line].Text)) and IsWordBreakChar(Lines.Lines[Result.Line].Text[Result.Char + 1])) do
        Inc(Result.Char);
    end
  end;
end;

procedure TCustomBCEditor.Notification(AComponent: TComponent; AOperation: TOperation);
begin
  inherited Notification(AComponent, AOperation);

  if AOperation = opRemove then
  begin
    if AComponent = FChainedEditor then
      RemoveChainedEditor;

    if Assigned(LeftMargin) and Assigned(LeftMargin.Bookmarks) and Assigned(LeftMargin.Bookmarks.Images) then
      if (AComponent = LeftMargin.Bookmarks.Images) then
      begin
        LeftMargin.Bookmarks.Images := nil;
        Invalidate;
      end;
  end;
end;

procedure TCustomBCEditor.NotifyHookedCommandHandlers(AAfterProcessing: Boolean; var ACommand: TBCEditorCommand;
  var AChar: Char; AData: Pointer);
var
  LHandled: Boolean;
  LHookedCommandHandler: TBCEditorHookedCommandHandler;
  LIndex: Integer;
begin
  LHandled := False;
  for LIndex := 0 to GetHookedCommandHandlersCount - 1 do
  begin
    LHookedCommandHandler := TBCEditorHookedCommandHandler(FHookedCommandHandlers[LIndex]);
    LHookedCommandHandler.Event(Self, AAfterProcessing, LHandled, ACommand, AChar, AData, LHookedCommandHandler.Data);
  end;
  if LHandled then
    ACommand := ecNone;
end;

procedure TCustomBCEditor.OnCodeFoldingDelayTimer(ASender: TObject);
begin
  FCodeFoldingDelayTimer.Enabled := False;

  if (FRescanCodeFolding and FCodeFolding.Visible) then
    RescanCodeFoldingRanges;
end;

procedure TCustomBCEditor.OnTokenInfoTimer(ASender: TObject);
var
  LControl: TWinControl;
  LPoint: TPoint;
  LPreviousTextPosition: TBCEditorTextPosition;
  LShowInfo: Boolean;
  LSize: TSize;
  LTextPosition: TBCEditorTextPosition;
  LToken: string;
begin
  FTokenInfoTimer.Enabled := False;

  if GetTextPositionOfMouse(LTextPosition) then
  begin
    LPreviousTextPosition := PreviousWordPosition(LTextPosition);
    if LPreviousTextPosition.Line = LTextPosition.Line then
      LTextPosition := LPreviousTextPosition
    else
      LTextPosition.Char := 0;
    LToken := GetWordAtTextPosition(LTextPosition);
    if LToken <> '' then
    begin
      FTokenInfoPopupWindow := TBCEditorTokenInfoPopupWindow.Create(Self);
      with FTokenInfoPopupWindow do
      begin
        LControl := Self;
        while Assigned(LControl) and not (LControl is TCustomForm) do
          LControl := LControl.Parent;
        if LControl is TCustomForm then
          PopupParent := TCustomForm(LControl);
        Assign(FTokenInfo);

        LShowInfo := False;
        if Assigned(FOnBeforeTokenInfoExecute) then
          FOnBeforeTokenInfoExecute(Self, LTextPosition, LToken, Content, TitleContent, LShowInfo);

        if LShowInfo then
        begin
          LPoint := Self.ClientToScreen(DisplayToClient(TextToDisplay(LTextPosition)));
          FTokenInfoTokenRect.Left := LPoint.X;
          FTokenInfoTokenRect.Top := LPoint.Y;
          Inc(LPoint.Y, LineHeight);
          FTokenInfoTokenRect.Bottom := LPoint.Y;
          GetTextExtentPoint32(FPaintHelper.StockBitmap.Canvas.Handle, LToken, Length(LToken), LSize);
          FTokenInfoTokenRect.Right := FTokenInfoTokenRect.Left + LSize.cx;
          Execute(LPoint);
        end;
      end;
    end;
  end
end;

procedure TCustomBCEditor.OpenLink(const AURI: string; ARangeType: TBCEditorRangeType);
var
  LURI: string;
begin
  case ARangeType of
    ttMailtoLink:
      if Pos(BCEDITOR_MAILTO, AURI) <> 1 then
        LURI := BCEDITOR_MAILTO + AURI;
    ttWebLink:
      LURI := BCEDITOR_HTTP + AURI;
  end;

  ShellExecute(0, nil, PChar(LURI), nil, nil, SW_SHOWNORMAL);
end;

procedure TCustomBCEditor.Paint;
var
  LClipRect: TRect;
  LDrawRect: TRect;
  LFirstRow: Integer;
  LLastRow: Integer;
  LLastTextRow: Integer;
  LTemp: Integer;
begin
  LClipRect := ClientRect;

  LFirstRow := TopRow + LClipRect.Top div LineHeight;
  LTemp := (LClipRect.Bottom + LineHeight - 1) div LineHeight;
  LLastTextRow := MinMax(TopRow + LTemp - 1, -1, Rows.Count - 1);
  LLastRow := TopRow + LTemp;

  HideCaret;

  try
    Canvas.Brush.Color := FBackgroundColor;

    FPaintHelper.BeginDrawing(Canvas.Handle);
    try
      FPaintHelper.SetBaseFont(Font);

      { Text lines }
      LDrawRect.Top := 0;
      LDrawRect.Left := LeftMarginWidth - HorzTextPos;
      LDrawRect.Right := ClientRect.Width;
      LDrawRect.Bottom := LClipRect.Height;

      PaintTextLines(LDrawRect, LFirstRow, LLastTextRow);

      PaintRightMargin(LDrawRect);

      if (FCodeFolding.Visible and (cfoShowIndentGuides in CodeFolding.Options)) then
        PaintGuides(TopRow, Min(TopRow + VisibleRows, Rows.Count) - 1);

      if FSyncEdit.Enabled and FSyncEdit.Active then
        PaintSyncItems;

      if FCaret.NonBlinking.Enabled or Assigned(FMultiCarets) and (FMultiCarets.Count > 0) and FDrawMultiCarets then
        DrawCaret;

      if (not Assigned(FCompletionProposalPopupWindow)
        and FCaret.MultiEdit.Enabled
        and (FMultiCaretPosition.Row >= 0)) then
        PaintCaretBlock(FMultiCaretPosition);

      if FRightMargin.Moving then
        PaintRightMarginMove;

      if FMouseMoveScrolling then
        PaintMouseMoveScrollPoint;

      { Left margin and code folding }
      LDrawRect := LClipRect;
      LDrawRect.Left := 0;
      if FSearch.Map.Align = saLeft then
        Inc(LDrawRect.Left, FSearch.Map.GetWidth);

      if LeftMargin.Visible then
      begin
        LDrawRect.Right := LDrawRect.Left + LeftMargin.Width;
        PaintLeftMargin(LDrawRect, LFirstRow, LLastTextRow, LLastRow);
      end;

      if FCodeFolding.Visible then
      begin
        Inc(LDrawRect.Left, LeftMargin.Width);
        LDrawRect.Right := LDrawRect.Left + FCodeFolding.GetWidth;
        PaintCodeFolding(LDrawRect, LFirstRow, LLastTextRow);
      end;

      { Search map }
      if FSearch.Map.Visible then
      begin
        LDrawRect := LClipRect;
        if FSearch.Map.Align = saRight then
          LDrawRect.Left := ClientRect.Width - FSearch.Map.GetWidth
        else
        begin
          LDrawRect.Left := 0;
          LDrawRect.Right := FSearch.Map.GetWidth;
        end;
        PaintSearchMap(LDrawRect);
      end;
    finally
      FPaintHelper.EndDrawing;
    end;

    DoOnPaint;
  finally
    FLastTopLine := TopRow;
    FLastLineNumberCount := Rows.Count;
    if not FCaret.NonBlinking.Enabled and not Assigned(FMultiCarets) then
      UpdateCaret;
  end;
end;

procedure TCustomBCEditor.PaintCaretBlock(ADisplayCaretPosition: TBCEditorDisplayPosition);
var
  LBackgroundColor: TColor;
  LCaretHeight: Integer;
  LCaretStyle: TBCEditorCaretStyle;
  LCaretWidth: Integer;
  LForegroundColor: TColor;
  LPoint: TPoint;
  LTempBitmap: Graphics.TBitmap;
  LTextPosition: TBCEditorTextPosition;
  X: Integer;
  Y: Integer;
begin
  if (HandleAllocated) then
  begin
    LPoint := DisplayToClient(ADisplayCaretPosition);
    Y := 0;
    X := 0;
    LCaretHeight := 1;
    LCaretWidth := CharWidth;

    if Assigned(FMultiCarets) and (FMultiCarets.Count > 0) or (FMultiCaretPosition.Row >= 0) then
    begin
      LBackgroundColor := FCaret.MultiEdit.Colors.Background;
      LForegroundColor := FCaret.MultiEdit.Colors.Foreground;
      LCaretStyle := FCaret.MultiEdit.Style
    end
    else
    begin
      LBackgroundColor := FCaret.NonBlinking.Colors.Background;
      LForegroundColor := FCaret.NonBlinking.Colors.Foreground;
      if FTextEntryMode = temInsert then
        LCaretStyle := FCaret.Styles.Insert
      else
        LCaretStyle := FCaret.Styles.Overwrite;
    end;

    case LCaretStyle of
      csHorizontalLine, csThinHorizontalLine:
        begin
          if LCaretStyle = csHorizontalLine then
            LCaretHeight := 2;
          Y := LineHeight - LCaretHeight;
          Inc(LPoint.Y, Y);
          Inc(LPoint.X);
        end;
      csHalfBlock:
        begin
          LCaretHeight := LineHeight div 2;
          Y := LineHeight div 2;
          Inc(LPoint.Y, Y);
          Inc(LPoint.X);
        end;
      csBlock:
        begin
          LCaretHeight := LineHeight;
          Inc(LPoint.X);
        end;
      csVerticalLine, csThinVerticalLine:
        begin
          LCaretWidth := 1;
          if LCaretStyle = csVerticalLine then
            LCaretWidth := 2;
          LCaretHeight := LineHeight;
          X := 1;
        end;
    end;
    LTempBitmap := Graphics.TBitmap.Create;
    try
      { Background }
      LTempBitmap.Canvas.Pen.Color := LBackgroundColor;
      LTempBitmap.Canvas.Brush.Color := LBackgroundColor;
      { Size }
      LTempBitmap.Width := CharWidth;
      LTempBitmap.Height := LineHeight;
      { Character }
      LTempBitmap.Canvas.Brush.Style := bsClear;

      LTextPosition := DisplayToText(ADisplayCaretPosition);
      if ((LTextPosition.Line < Lines.Count)
        and (LTextPosition.Char < Length(Lines.Lines[LTextPosition.Line].Text))) then
      begin
        LTempBitmap.Canvas.Font.Name := Font.Name;
        LTempBitmap.Canvas.Font.Color := LForegroundColor;
        LTempBitmap.Canvas.Font.Style := Font.Style;
        LTempBitmap.Canvas.Font.Height := Font.Height;
        LTempBitmap.Canvas.Font.Size := Font.Size;
        LTempBitmap.Canvas.TextOut(X, 0, Lines.Char[LTextPosition]);
      end;

      Canvas.CopyRect(Rect(LPoint.X + FCaret.Offsets.Left, LPoint.Y + FCaret.Offsets.Top,
        LPoint.X + FCaret.Offsets.Left + LCaretWidth, LPoint.Y + FCaret.Offsets.Top + LCaretHeight), LTempBitmap.Canvas,
        Rect(0, Y, LCaretWidth, Y + LCaretHeight));
    finally
      LTempBitmap.Free
    end;
  end;
end;

procedure TCustomBCEditor.PaintCodeFolding(AClipRect: TRect; AFirstRow, ALastRow: Integer);
var
  LBackground: TColor;
  LLine: Integer;
  LOldBrushColor: TColor;
  LOldPenColor: TColor;
  LRange: TBCEditorCodeFolding.TRanges.TRange;
  LRow: Integer;
begin
  LOldBrushColor := Canvas.Brush.Color;
  LOldPenColor := Canvas.Pen.Color;

  Canvas.Brush.Color := FCodeFolding.Colors.Background;
  FillRect(AClipRect);
  Canvas.Pen.Style := psSolid;
  Canvas.Brush.Color := FCodeFolding.Colors.FoldingLine;

  LRange := nil;
  if (cfoHighlightFoldingLine in FCodeFolding.Options) then
  begin
    LLine := Max(DisplayToText(DisplayCaretPosition).Line, Length(FCodeFoldingRangeFromLine) - 1);
    while ((LLine > 0) and not Assigned(FCodeFoldingRangeFromLine[LLine])) do
      Dec(LLine);
    if (Assigned(FCodeFoldingRangeFromLine[LLine])) then
      LRange := FCodeFoldingRangeFromLine[LLine]
  end;

  for LRow := AFirstRow to ALastRow do
  begin
    LLine := Rows[LRow].Line;

    AClipRect.Top := (LRow - TopRow) * LineHeight;
    AClipRect.Bottom := AClipRect.Top + LineHeight;
    LBackground := GetMarkBackgroundColor(LRow);
    if LBackground <> clNone then
    begin
      Canvas.Brush.Color := LBackground;
      FillRect(AClipRect);
    end;
    if Assigned(LRange) and (LLine >= LRange.FirstLine) and (LLine <= LRange.LastLine) then
    begin
      Canvas.Brush.Color := CodeFolding.Colors.FoldingLineHighlight;
      Canvas.Pen.Color := CodeFolding.Colors.FoldingLineHighlight;
    end
    else
    begin
      Canvas.Brush.Color := CodeFolding.Colors.FoldingLine;
      Canvas.Pen.Color := CodeFolding.Colors.FoldingLine;
    end;
    PaintCodeFoldingLine(AClipRect, LLine);
  end;
  Canvas.Brush.Color := LOldBrushColor;
  Canvas.Pen.Color := LOldPenColor;
end;

procedure TCustomBCEditor.PaintCodeFoldingCollapsedLine(AFoldRange: TBCEditorCodeFolding.TRanges.TRange; const ALineRect: TRect);
var
  LOldPenColor: TColor;
begin
  if FCodeFolding.Visible and (cfoShowCollapsedLine in CodeFolding.Options) and Assigned(AFoldRange) and
    AFoldRange.Collapsed and not AFoldRange.ParentCollapsed then
  begin
    LOldPenColor := Canvas.Pen.Color;
    Canvas.Pen.Color := CodeFolding.Colors.CollapsedLine;
    Canvas.MoveTo(ALineRect.Left, ALineRect.Bottom - 1);
    Canvas.LineTo(Width, ALineRect.Bottom - 1);
    Canvas.Pen.Color := LOldPenColor;
  end;
end;

procedure TCustomBCEditor.PaintCodeFoldingCollapseMark(AFoldRange: TBCEditorCodeFolding.TRanges.TRange;
  const ATokenPosition, ATokenLength, ALine: Integer; ALineRect: TRect);
var
  LBrush: TBrush;
  LCollapseMarkRect: TRect;
  LDisplayPosition: TBCEditorDisplayPosition;
  LDotSpace: Integer;
  LIndex: Integer;
  LOldBrushColor: TColor;
  LOldPenColor: TColor;
  LPoints: array [0..2] of TPoint;
  X: Integer;
  Y: Integer;
begin
  LOldPenColor := Canvas.Pen.Color;
  LOldBrushColor  := Canvas.Brush.Color;
  if FCodeFolding.Visible and FCodeFolding.Hint.Indicator.Visible and Assigned(AFoldRange) and
    AFoldRange.Collapsed and not AFoldRange.ParentCollapsed then
  begin
    LDisplayPosition.Row := Lines.Lines[ALine].FirstRow;
    LDisplayPosition.Column := ATokenPosition + ATokenLength + 1;
    if SpecialChars.Visible and (ALine < Lines.Count) then
      Inc(LDisplayPosition.Column);
    LCollapseMarkRect.Left := DisplayToClient(LDisplayPosition).X -
      FCodeFolding.Hint.Indicator.Padding.Left;
    LCollapseMarkRect.Right := FCodeFolding.Hint.Indicator.Padding.Right + LCollapseMarkRect.Left +
      FCodeFolding.Hint.Indicator.Width;
    LCollapseMarkRect.Top := FCodeFolding.Hint.Indicator.Padding.Top + ALineRect.Top;
    LCollapseMarkRect.Bottom := ALineRect.Bottom - FCodeFolding.Hint.Indicator.Padding.Bottom;

    if LCollapseMarkRect.Right > LeftMarginWidth then
    begin
      if FCodeFolding.Hint.Indicator.Glyph.Visible then
        FCodeFolding.Hint.Indicator.Glyph.Draw(Canvas, LCollapseMarkRect.Left, ALineRect.Top, ALineRect.Height)
      else
      begin
        if BackgroundColor <> FCodeFolding.Hint.Indicator.Colors.Background then
        begin
          Canvas.Brush.Color := FCodeFolding.Hint.Indicator.Colors.Background;
          FillRect(LCollapseMarkRect);
        end;

        if hioShowBorder in FCodeFolding.Hint.Indicator.Options then
        begin
          LBrush := TBrush.Create;
          try
            LBrush.Color := FCodeFolding.Hint.Indicator.Colors.Border;
            FrameRect(Canvas.Handle, LCollapseMarkRect, LBrush.Handle);
          finally
            LBrush.Free;
          end;
        end;

        if hioShowMark in FCodeFolding.Hint.Indicator.Options then
        begin
          Canvas.Pen.Color := FCodeFolding.Hint.Indicator.Colors.Mark;
          Canvas.Brush.Color := FCodeFolding.Hint.Indicator.Colors.Mark;
          case FCodeFolding.Hint.Indicator.MarkStyle of
            imsThreeDots:
              begin
                { [...] }
                LDotSpace := (LCollapseMarkRect.Width - 8) div 4;
                Y := LCollapseMarkRect.Top + (LCollapseMarkRect.Bottom - LCollapseMarkRect.Top) div 2;
                X := LCollapseMarkRect.Left + LDotSpace + (LCollapseMarkRect.Width - LDotSpace * 4 - 6) div 2;
                for LIndex := 1 to 3 do
                begin
                  Canvas.Rectangle(X, Y, X + 2, Y + 2);
                  X := X + LDotSpace + 2;
                end;
              end;
            imsTriangle:
              begin
                LPoints[0] := Point(LCollapseMarkRect.Left + (LCollapseMarkRect.Width - LCollapseMarkRect.Height) div 2 + 2, LCollapseMarkRect.Top + 2);
                LPoints[1] := Point(LCollapseMarkRect.Right - (LCollapseMarkRect.Width - LCollapseMarkRect.Height) div 2 - 3 - (LCollapseMarkRect.Width + 1) mod 2, LCollapseMarkRect.Top + 2);
                LPoints[2] := Point(LCollapseMarkRect.Left + LCollapseMarkRect.Width div 2 - (LCollapseMarkRect.Width + 1) mod 2, LCollapseMarkRect.Bottom - 3);
                Canvas.Polygon(LPoints);
              end;
          end;
        end;
      end;
    end;
    Inc(LCollapseMarkRect.Left, LeftMarginWidth);
    LCollapseMarkRect.Right := LCollapseMarkRect.Left + FCodeFolding.Hint.Indicator.Width;
    AFoldRange.CollapseMarkRect := LCollapseMarkRect;
  end;
  Canvas.Pen.Color := LOldPenColor;
  Canvas.Brush.Color := LOldBrushColor;
end;

procedure TCustomBCEditor.PaintCodeFoldingLine(AClipRect: TRect; ALine: Integer);
var
  LFoldRange: TBCEditorCodeFolding.TRanges.TRange;
  LHeight: Integer;
  LPoints: array [0..2] of TPoint;
  LTemp: Integer;
  X: Integer;
  Y: Integer;
begin
  if CodeFolding.Padding > 0 then
    InflateRect(AClipRect, -CodeFolding.Padding, 0);

  LFoldRange := CodeFoldingCollapsableFoldRangeForLine(ALine);

  if not Assigned(LFoldRange) then
  begin
    if cfoShowTreeLine in FCodeFolding.Options then
    begin
      if CodeFoldingTreeLineForLine(ALine) then
      begin
        X := AClipRect.Left + ((AClipRect.Right - AClipRect.Left) div 2) - 1;
        Canvas.MoveTo(X, AClipRect.Top);
        Canvas.LineTo(X, AClipRect.Bottom);
      end;
      if CodeFoldingTreeEndForLine(ALine) then
      begin
        X := AClipRect.Left + ((AClipRect.Right - AClipRect.Left) div 2) - 1;
        Canvas.MoveTo(X, AClipRect.Top);
        Y := AClipRect.Top + ((AClipRect.Bottom - AClipRect.Top) - 4);
        Canvas.LineTo(X, Y);
        Canvas.LineTo(AClipRect.Right - 1, Y);
      end
    end;
  end
  else
  if LFoldRange.Collapsable then
  begin
    LHeight := AClipRect.Right - AClipRect.Left;
    AClipRect.Top := AClipRect.Top + ((LineHeight - LHeight) div 2) + 1;
    AClipRect.Bottom := AClipRect.Top + LHeight - 1;
    AClipRect.Right := AClipRect.Right - 1;

    if CodeFolding.MarkStyle = msTriangle then
    begin
      if LFoldRange.Collapsed then
      begin
        LPoints[0] := Point(AClipRect.Left, AClipRect.Top);
        LPoints[1] := Point(AClipRect.Left, AClipRect.Bottom - 1);
        LPoints[2] := Point(AClipRect.Right - (FCodeFolding.Width + 1) mod 2, AClipRect.Top + AClipRect.Height div 2);
        Canvas.Polygon(LPoints);
      end
      else
      begin
        LPoints[0] := Point(AClipRect.Left, AClipRect.Top + 1);
        LPoints[1] := Point(AClipRect.Right - (FCodeFolding.Width + 1) mod 2, AClipRect.Top + 1);
        LPoints[2] := Point(AClipRect.Left + AClipRect.Width div 2, AClipRect.Bottom - 1);
        Canvas.Polygon(LPoints);
      end;
    end
    else
    begin
      if CodeFolding.MarkStyle = msSquare then
        Canvas.FrameRect(AClipRect)
      else
      if CodeFolding.MarkStyle = msCircle then
      begin
        Canvas.Brush.Color := FCodeFolding.Colors.Background;
        Canvas.Ellipse(AClipRect);
      end;

      { - }
      LTemp := AClipRect.Top + ((AClipRect.Bottom - AClipRect.Top) div 2);
      Canvas.MoveTo(AClipRect.Left + AClipRect.Width div 4, LTemp);
      Canvas.LineTo(AClipRect.Right - AClipRect.Width div 4, LTemp);

      if LFoldRange.Collapsed then
      begin
        { + }
        LTemp := (AClipRect.Right - AClipRect.Left) div 2;
        Canvas.MoveTo(AClipRect.Left + LTemp, AClipRect.Top + AClipRect.Width div 4);
        Canvas.LineTo(AClipRect.Left + LTemp, AClipRect.Bottom - AClipRect.Width div 4);
      end;
    end;
  end;
end;

procedure TCustomBCEditor.PaintGuides(const AFirstRow, ALastRow: Integer);
var
  LCodeFoldingRange: TBCEditorCodeFolding.TRanges.TRange;
  LCodeFoldingRanges: array of TBCEditorCodeFolding.TRanges.TRange;
  LCodeFoldingRangeTo: TBCEditorCodeFolding.TRanges.TRange;
  LCurrentLine: Integer;
  LDeepestLevel: Integer;
  LEndLine: Integer;
  LFirstLine: Integer;
  LIncY: Boolean;
  LIndex: Integer;
  LLine: Integer;
  LOldColor: TColor;
  LRangeIndex: Integer;
  LRow: Integer;
  X: Integer;
  Y: Integer;
  Z: Integer;

  function GetDeepestLevel: Integer;
  var
    LTempLine: Integer;
  begin
    Result := 0;
    LTempLine := LCurrentLine;
    if LTempLine < Length(FCodeFoldingRangeFromLine) then
    begin
      while LTempLine > 0 do
      begin
        LCodeFoldingRange := FCodeFoldingRangeFromLine[LTempLine];
        LCodeFoldingRangeTo := FCodeFoldingRangeToLine[LTempLine];
        if not Assigned(LCodeFoldingRange) and not Assigned(LCodeFoldingRangeTo) then
          Dec(LTempLine)
        else
        if Assigned(LCodeFoldingRange) and (LCurrentLine >= LCodeFoldingRange.FirstLine) and
          (LCurrentLine <= LCodeFoldingRange.LastLine) then
          Break
        else
        if Assigned(LCodeFoldingRangeTo) and (LCurrentLine >= LCodeFoldingRangeTo.FirstLine) and
          (LCurrentLine <= LCodeFoldingRangeTo.LastLine) then
        begin
          LCodeFoldingRange := LCodeFoldingRangeTo;
          Break
        end
        else
          Dec(LTempLine)
      end;
      if Assigned(LCodeFoldingRange) then
        Result := LCodeFoldingRange.IndentLevel;
    end;
  end;

var
  LDisplayCaretPosition: TBCEditorDisplayPosition;
begin
  if (ALastRow < Rows.Count) then
  begin
    LOldColor := Canvas.Pen.Color;

    Y := 0;
    LDisplayCaretPosition := DisplayCaretPosition;
    if (LDisplayCaretPosition.Row < Rows.Count) then
      LCurrentLine := Rows[DisplayCaretPosition.Row].Line
    else
      LCurrentLine := -1;
    LCodeFoldingRange := nil;
    LDeepestLevel := GetDeepestLevel;
    if (AFirstRow < Rows.Count) then
      LFirstLine := Rows[AFirstRow].Line
    else
      LFirstLine := -1;
    if (ALastRow < Rows.Count - 1) then
      LEndLine := Rows[ALastRow].Line
    else
      LEndLine := -1;

    SetLength(LCodeFoldingRanges, FAllCodeFoldingRanges.AllCount);
    LRangeIndex := 0;
    for LIndex := 0 to FAllCodeFoldingRanges.AllCount - 1 do
    begin
      LCodeFoldingRange := FAllCodeFoldingRanges[LIndex];
      if Assigned(LCodeFoldingRange) then
        for LRow := AFirstRow to ALastRow do
        begin
          LLine := Rows[LRow].Line;
          if (LCodeFoldingRange.LastLine < LFirstLine) or (LCodeFoldingRange.FirstLine > LEndLine) then
            Break
          else
          if not LCodeFoldingRange.Collapsed and not LCodeFoldingRange.ParentCollapsed and
            (LCodeFoldingRange.FirstLine < LLine) and (LCodeFoldingRange.LastLine > LLine) then
          begin
            LCodeFoldingRanges[LRangeIndex] := LCodeFoldingRange;
            Inc(LRangeIndex);
            Break;
          end
        end;
    end;

    for LRow := AFirstRow to ALastRow do
    begin
      LLine := Rows[LRow].Line;
      LIncY := Odd(LineHeight) and not Odd(LRow);
      for LIndex := 0 to LRangeIndex - 1 do
      begin
        LCodeFoldingRange := LCodeFoldingRanges[LIndex];
        if Assigned(LCodeFoldingRange) then
          if not LCodeFoldingRange.Collapsed and not LCodeFoldingRange.ParentCollapsed and
            (LCodeFoldingRange.FirstLine < LLine) and (LCodeFoldingRange.LastLine > LLine) then
          begin
            if not LCodeFoldingRange.RegionItem.ShowGuideLine then
              Continue;

            X := LeftMarginWidth + GetLineIndentLevel(LCodeFoldingRange.LastLine) * CharWidth - HorzTextPos;

            if (X - LeftMarginWidth > 0) then
            begin
              if (LDeepestLevel = LCodeFoldingRange.IndentLevel) and (LCurrentLine >= LCodeFoldingRange.FirstLine) and
                (LCurrentLine <= LCodeFoldingRange.LastLine) and (cfoHighlightIndentGuides in FCodeFolding.Options) then
              begin
                Canvas.Pen.Color := FCodeFolding.Colors.IndentHighlight;
                Canvas.MoveTo(X, Y);
                Canvas.LineTo(X, Y + LineHeight);
              end
              else
              begin
                Canvas.Pen.Color := FCodeFolding.Colors.Indent;

                Z := Y;
                if LIncY then
                  Inc(Z);

                while Z < Y + LineHeight do
                begin
                  Canvas.MoveTo(X, Z);
                  Inc(Z);
                  Canvas.LineTo(X, Z);
                  Inc(Z);
                end;
              end;
            end;
          end;
      end;
      Inc(Y, LineHeight);
    end;
    SetLength(LCodeFoldingRanges, 0);
    Canvas.Pen.Color := LOldColor;
  end;
end;

procedure TCustomBCEditor.PaintLeftMargin(const AClipRect: TRect; const AFirstRow, ALastTextRow, ALastRow: Integer);
var
  LLine: Integer;
  LLineHeight: Integer;
  LLineRect: TRect;

  procedure DrawBookmark(ABookmark: TBCEditorMark; var AOverlappingOffset: Integer; AMarkRow: Integer);
  begin
    if not Assigned(FInternalBookmarkImage) then
      FInternalBookmarkImage := TBCEditorInternalImage.Create(HInstance, BCEDITOR_BOOKMARK_IMAGES,
        BCEDITOR_BOOKMARK_IMAGE_COUNT);
    FInternalBookmarkImage.Draw(Canvas, ABookmark.ImageIndex, AClipRect.Left + LeftMargin.Bookmarks.LeftMargin,
      (AMarkRow - TopRow) * LLineHeight, LLineHeight, clFuchsia);
    Inc(AOverlappingOffset, LeftMargin.Marks.OverlappingOffset);
  end;

  procedure DrawMark(AMark: TBCEditorMark; const AOverlappingOffset: Integer; AMarkRow: Integer);
  var
    Y: Integer;
  begin
    if Assigned(LeftMargin.Marks.Images) then
      if AMark.ImageIndex <= LeftMargin.Marks.Images.Count then
      begin
        if LLineHeight > LeftMargin.Marks.Images.Height then
          Y := LLineHeight shr 1 - LeftMargin.Marks.Images.Height shr 1
        else
          Y := 0;
        LeftMargin.Marks.Images.Draw(Canvas, AClipRect.Left + LeftMargin.Marks.LeftMargin + AOverlappingOffset,
          (AMarkRow - TopRow) * LLineHeight + Y, AMark.ImageIndex);
      end;
  end;

  procedure PaintLineNumbers();
  var
    LBackground: TColor;
    LRow: Integer;
    LLastRow: Integer;
    LLeftMarginWidth: Integer;
    LLineNumber: string;
    LOldColor: TColor;
    LTextSize: TSize;
    LTop: Integer;
  begin
    FPaintHelper.SetBaseFont(LeftMargin.Font);
    try
      FPaintHelper.SetForegroundColor(LeftMargin.Font.Color);

      LLineRect := AClipRect;

      if (lnoAfterLastLine in LeftMargin.LineNumbers.Options) then
        LLastRow := ALastRow
      else
        LLastRow := ALastTextRow;

      for LRow := AFirstRow to LLastRow + 1 do
      begin
        LLineRect.Top := (LRow - TopRow) * LLineHeight;
        LLineRect.Bottom := LLineRect.Top + LLineHeight;

        if (LeftMargin.LineNumbers.Visible
          and ((LRow = 0)
            or (LRow < Rows.Count))) then
        begin
          if (LRow < Rows.Count) then
            LLine := Rows[LRow].Line
          else
            LLine := LRow - Rows.Count;

          FPaintHelper.SetBackgroundColor(LeftMargin.Colors.Background);

          if (not Assigned(FMultiCarets) and (LLine = Lines.CaretPosition.Line)) then
          begin
            FPaintHelper.SetBackgroundColor(LeftMargin.Colors.Background);
            Canvas.Brush.Color := LeftMargin.Colors.Background;
            if Assigned(FMultiCarets) then
              FillRect(LLineRect);
          end
          else
          begin
            LBackground := GetMarkBackgroundColor(LRow);
            if LBackground <> clNone then
            begin
              FPaintHelper.SetBackgroundColor(LBackground);
              Canvas.Brush.Color := LBackground;
              FillRect(LLineRect);
            end
          end;

          if (((Rows.Count = 0) or (rfFirstRowOfLine in Rows[LRow].Flags))
            and ((LLine = 0)
              or (LLine = Lines.CaretPosition.Line)
              or ((LLine + 1) mod 10 = 0)
              or not (lnoIntens in LeftMargin.LineNumbers.Options))) then
          begin
            LLineNumber := LeftMargin.FormatLineNumber(LLine + 1);
            GetTextExtentPoint32(Canvas.Handle, PChar(LLineNumber), Length(LLineNumber), LTextSize);
            ExtTextOut(Canvas.Handle,
              LLineRect.Left + (LeftMargin.Width - LeftMargin.LineState.Width - 2) - LTextSize.cx,
              LLineRect.Top + ((LLineHeight - Integer(LTextSize.cy)) div 2),
              ETO_OPAQUE, @LLineRect, PChar(LLineNumber), Length(LLineNumber), nil);
          end
          else if (rfFirstRowOfLine in Rows[LRow].Flags) then
          begin
            LLeftMarginWidth := LLineRect.Left + LeftMargin.Width - LeftMargin.LineState.Width - 1;
            LOldColor := Canvas.Pen.Color;
            Canvas.Pen.Color := LeftMargin.Font.Color;
            LTop := LLineRect.Top + ((LLineHeight - 1) div 2);
            if (LLine + 1) mod 5 = 0 then
              Canvas.MoveTo(LLeftMarginWidth - FLeftMarginCharWidth + ((FLeftMarginCharWidth - 9) div 2), LTop)
            else
              Canvas.MoveTo(LLeftMarginWidth - FLeftMarginCharWidth + ((FLeftMarginCharWidth - 2) div 2), LTop);
            Canvas.LineTo(LLeftMarginWidth - ((FLeftMarginCharWidth - 1) div 2), LTop);
            Canvas.Pen.Color := LOldColor;
          end
          else if (WordWrap.Enabled and WordWrap.Indicator.Visible) then
          begin
            BitBlt(Canvas.Handle,
              LeftMargin.Width - LeftMargin.LineState.Width - 2 - FWordWrapIndicator.Width,
              LLineRect.Top,
              FWordWrapIndicator.Width, FWordWrapIndicator.Height,
              FWordWrapIndicator.Canvas.Handle, 0, 0, SRCCOPY);
          end;
        end;
      end;

      FPaintHelper.SetBackgroundColor(LeftMargin.Colors.Background);
      { Erase the remaining area }
      if (AClipRect.Bottom > LLineRect.Bottom) then
      begin
        LLineRect.Top := LLineRect.Bottom;
        LLineRect.Bottom := AClipRect.Bottom;
        FillRect(LLineRect);
      end;
    finally
      FPaintHelper.SetBaseFont(Font);
    end;
  end;

  procedure PaintBookmarkPanel;
  var
    LBackground: TColor;
    LRow: Integer;
    LOldColor: TColor;
    LPanelActiveLineRect: TRect;
    LPanelRect: TRect;

    procedure SetPanelActiveLineRect;
    begin
      LPanelActiveLineRect := System.Types.Rect(AClipRect.Left, (LRow - TopRow) * LLineHeight,
        AClipRect.Left + LeftMargin.MarksPanel.Width, (LRow - TopRow + 1) * LLineHeight);
    end;

  begin
    LOldColor := Canvas.Brush.Color;
    if LeftMargin.MarksPanel.Visible then
    begin
      LPanelRect := System.Types.Rect(AClipRect.Left, 0, AClipRect.Left + LeftMargin.MarksPanel.Width,
        ClientHeight);
      if LeftMargin.Colors.BookmarkPanelBackground <> clNone then
      begin
        Canvas.Brush.Color := LeftMargin.Colors.BookmarkPanelBackground;
        FillRect(LPanelRect);
      end;

      for LRow := AFirstRow to ALastTextRow do
      begin
        if (LRow < Rows.Count) then
          LLine := Rows[LRow].Line
        else
          LLine := LRow - Rows.Count;

        if (Assigned(FMultiCarets) and IsMultiEditCaretFound(LLine)) then
        begin
          SetPanelActiveLineRect;
          Canvas.Brush.Color := LeftMargin.Colors.Background;
          FillRect(LPanelActiveLineRect);
        end
        else
        begin
          LBackground := GetMarkBackgroundColor(LRow);
          if LBackground <> clNone then
          begin
            SetPanelActiveLineRect;
            Canvas.Brush.Color := LBackground;
            FillRect(LPanelActiveLineRect);
          end
        end;
      end;
      if Assigned(FOnBeforeMarkPanelPaint) then
        FOnBeforeMarkPanelPaint(Self, Canvas, LPanelRect, AFirstRow, ALastRow);
    end;
    Canvas.Brush.Color := LOldColor;
  end;

  procedure PaintBorder;
  var
    LRightPosition: Integer;
  begin
    LRightPosition := AClipRect.Left + LeftMargin.Width;
    if (LeftMargin.Border.Style <> mbsNone) and (AClipRect.Right >= LRightPosition - 2) then
      with Canvas do
      begin
        Pen.Color := LeftMargin.Colors.Border;
        Pen.Width := 1;
        if LeftMargin.Border.Style = mbsMiddle then
        begin
          MoveTo(LRightPosition - 2, AClipRect.Top);
          LineTo(LRightPosition - 2, AClipRect.Bottom);
          Pen.Color := LeftMargin.Colors.Background;
        end;
        MoveTo(LRightPosition - 1, AClipRect.Top);
        LineTo(LRightPosition - 1, AClipRect.Bottom);
      end;
  end;

  procedure PaintMarks;
  var
    LIndex: Integer;
    LLine: Integer;
    LMark: TBCEditorMark;
    LOverlappingOffsets: PIntegerArray;
    LRow: Integer;
  begin
    if LeftMargin.Bookmarks.Visible and LeftMargin.Bookmarks.Visible and
      ((FBookmarkList.Count > 0) or (FMarkList.Count > 0)) and (ALastRow >= AFirstRow) then
    begin
      LOverlappingOffsets := AllocMem((ALastRow - AFirstRow + 1) * SizeOf(Integer));
      try
        for LRow := AFirstRow to ALastTextRow do
          if (rfFirstRowOfLine in Rows[LRow].Flags) then
          begin
            LLine := Rows[LRow].Line;
            { Bookmarks }
            for LIndex := FBookmarkList.Count - 1 downto 0 do
            begin
              LMark := FBookmarkList[LIndex];
              if LMark.Line = LLine then
                if LMark.Visible then
                  DrawBookmark(LMark, LOverlappingOffsets[ALastRow - LRow], LRow);
            end;
            { Other marks }
            for LIndex := FMarkList.Count - 1 downto 0 do
            begin
              LMark := FMarkList[LIndex];
              if LMark.Line = LLine then
                if LMark.Visible then
                  DrawMark(LMark, LOverlappingOffsets[ALastRow - LRow], LRow);
            end;
          end;
      finally
        FreeMem(LOverlappingOffsets);
      end;
    end;
  end;

  procedure PaintActiveLineIndicator;
  begin
    if FActiveLine.Visible and FActiveLine.Indicator.Visible then
      FActiveLine.Indicator.Draw(Canvas, AClipRect.Left + FActiveLine.Indicator.Left, (DisplayCaretPosition.Row - TopRow) * LLineHeight,
        LLineHeight);
  end;

  procedure PaintSyncEditIndicator;
  var
    LDisplayPosition: TBCEditorDisplayPosition;
  begin
    if FSyncEdit.Enabled and not FSyncEdit.Active and FSyncEdit.Activator.Visible and SelectionAvailable then
      if (Lines.SelBeginPosition.Line <> Lines.SelEndPosition.Line) or FSyncEdit.BlockSelected then
      begin
        LDisplayPosition := TextToDisplay(SelectionEndPosition);
        FSyncEdit.Activator.Draw(Canvas, AClipRect.Left + FActiveLine.Indicator.Left,
          (LDisplayPosition.Row - TopRow) * LLineHeight, LLineHeight);
      end;
  end;

  procedure PaintLineState;
  var
    LLine: Integer;
    LLineStateRect: TRect;
    LOldColor: TColor;
    LRow: Integer;
  begin
    if (LeftMargin.LineState.Enabled) then
    begin
      LOldColor := Canvas.Brush.Color;
      LLineStateRect.Left := AClipRect.Left + LeftMargin.Width - LeftMargin.LineState.Width - 1;
      LLineStateRect.Right := LLineStateRect.Left + LeftMargin.LineState.Width;
      for LRow := AFirstRow to ALastTextRow do
      begin
        LLine := Rows[LRow].Line;

        if (Lines.Lines[LLine].State <> lsLoaded) then
        begin
          LLineStateRect.Top := (LRow - TopRow) * LLineHeight;
          LLineStateRect.Bottom := LLineStateRect.Top + LLineHeight;
          if (Lines.Lines[LLine].State = lsSaved) then
            Canvas.Brush.Color := LeftMargin.Colors.LineStateNormal
          else
            Canvas.Brush.Color := LeftMargin.Colors.LineStateModified;
          FillRect(LLineStateRect);
        end;
      end;
      Canvas.Brush.Color := LOldColor;
    end;
  end;

  procedure PaintBookmarkPanelLine;
  var
    LLine: Integer;
    LPanelRect: TRect;
    LRow: Integer;
  begin
    if LeftMargin.MarksPanel.Visible then
    begin
      if Assigned(FOnMarkPanelLinePaint) then
      begin
        LPanelRect.Left := AClipRect.Left;
        LPanelRect.Top := 0;
        LPanelRect.Right := LeftMargin.MarksPanel.Width;
        LPanelRect.Bottom := AClipRect.Bottom;
        for LRow := AFirstRow to ALastTextRow do
        begin
          LLine := Rows[LRow].Line;
          LLineRect.Left := LPanelRect.Left;
          LLineRect.Right := LPanelRect.Right;
          LLineRect.Top := (LRow - TopRow) * LLineHeight;
          LLineRect.Bottom := LLineRect.Top + LLineHeight;
          FOnMarkPanelLinePaint(Self, Canvas, LLineRect, LLine);
        end;
      end;
      if Assigned(FOnAfterMarkPanelPaint) then
        FOnAfterMarkPanelPaint(Self, Canvas, LPanelRect, AFirstRow, ALastRow);
    end;
  end;

begin
  FPaintHelper.SetBackgroundColor(LeftMargin.Colors.Background);
  Canvas.Brush.Color := LeftMargin.Colors.Background;
  FillRect(AClipRect);
  LLineHeight := LineHeight;
  PaintLineNumbers;
  PaintBookmarkPanel;
  PaintBorder;
  PaintMarks;
  PaintActiveLineIndicator;
  PaintSyncEditIndicator;
  PaintLineState;
  PaintBookmarkPanelLine;
end;

procedure TCustomBCEditor.PaintMouseMoveScrollPoint;
var
  LHalfWidth: Integer;
begin
  LHalfWidth := FScroll.Indicator.Width div 2;
  FScroll.Indicator.Draw(Canvas, FMouseMoveScrollingPoint.X - LHalfWidth, FMouseMoveScrollingPoint.Y - LHalfWidth);
end;

procedure TCustomBCEditor.PaintRightMargin(AClipRect: TRect);
var
  LRightMarginPosition: Integer;
begin
  if FRightMargin.Visible then
  begin
    LRightMarginPosition := LeftMarginWidth + FRightMargin.Position * CharWidth - HorzTextPos;
    if (LRightMarginPosition >= AClipRect.Left) and (LRightMarginPosition <= AClipRect.Right) then
    begin
      Canvas.Pen.Color := FRightMargin.Colors.Edge;
      Canvas.MoveTo(LRightMarginPosition, 0);
      Canvas.LineTo(LRightMarginPosition, Height);
    end;
  end;
end;

procedure TCustomBCEditor.PaintRightMarginMove;
var
  LOldPenStyle: TPenStyle;
  LOldStyle: TBrushStyle;
begin
  with Canvas do
  begin
    Pen.Width := 1;
    LOldPenStyle := Pen.Style;
    Pen.Style := psDot;
    Pen.Color := FRightMargin.Colors.MovingEdge;
    LOldStyle := Brush.Style;
    Brush.Style := bsClear;
    MoveTo(FRightMarginMovePosition, 0);
    LineTo(FRightMarginMovePosition, ClientHeight);
    Brush.Style := LOldStyle;
    Pen.Style := LOldPenStyle;
  end;
end;

procedure TCustomBCEditor.PaintSearchMap(AClipRect: TRect);
var
  LHeight: Double;
  LIndex: Integer;
  LLine: Integer;
begin
  if (FSearchResults.Count > 0) then
  begin
    { Background }
    if FSearch.Map.Colors.Background <> clNone then
      Canvas.Brush.Color := FSearch.Map.Colors.Background
    else
      Canvas.Brush.Color := FBackgroundColor;
    FillRect(AClipRect);
    { Lines in window }
    LHeight := ClientRect.Height / Max(Lines.Count, 1);
    AClipRect.Top := Round((TopRow - 1) * LHeight);
    AClipRect.Bottom := Max(Round((TopRow - 1 + VisibleRows) * LHeight), AClipRect.Top + 1);
    Canvas.Brush.Color := FBackgroundColor;
    FillRect(AClipRect);
    { Draw lines }
    if FSearch.Map.Colors.Foreground <> clNone then
      Canvas.Pen.Color := FSearch.Map.Colors.Foreground
    else
      Canvas.Pen.Color := clHighlight;
    Canvas.Pen.Width := 1;
    Canvas.Pen.Style := psSolid;
    for LIndex := 0 to FSearchResults.Count - 1 do
    begin
      LLine := Round(FSearchResults[LIndex].BeginPosition.Line * LHeight);
      Canvas.MoveTo(AClipRect.Left, LLine);
      Canvas.LineTo(AClipRect.Right, LLine);
      Canvas.MoveTo(AClipRect.Left, LLine + 1);
      Canvas.LineTo(AClipRect.Right, LLine + 1);
    end;
    { Draw active line }
    if moShowActiveLine in FSearch.Map.Options then
    begin
      if FSearch.Map.Colors.ActiveLine <> clNone then
        Canvas.Pen.Color := FSearch.Map.Colors.ActiveLine
      else
        Canvas.Pen.Color := FActiveLine.Color;
      LLine := Round(DisplayCaretPosition.Row * LHeight);
      Canvas.MoveTo(AClipRect.Left, LLine);
      Canvas.LineTo(AClipRect.Right, LLine);
      Canvas.MoveTo(AClipRect.Left, LLine + 1);
      Canvas.LineTo(AClipRect.Right, LLine + 1);
    end;
  end;
end;

procedure TCustomBCEditor.PaintSyncItems;
var
  LIndex: Integer;
  LLength: Integer;
  LOldBrushStyle: TBrushStyle;
  LOldPenColor: TColor;
  LTextPosition: TBCEditorTextPosition;

  procedure DrawRectangle(ATextPosition: TBCEditorTextPosition);
  var
    LDisplayPosition: TBCEditorDisplayPosition;
    LRect: TRect;
  begin
    LRect.Top := (ATextPosition.Line - TopRow + 1) * LineHeight;
    LRect.Bottom := LRect.Top + LineHeight;
    LDisplayPosition := TextToDisplay(ATextPosition);
    LRect.Left := DisplayToClient(LDisplayPosition).X;
    Inc(LDisplayPosition.Column, LLength);
    LRect.Right := DisplayToClient(LDisplayPosition).X;
    Canvas.Rectangle(LRect);
  end;

begin
  if not Assigned(FSyncEdit.SyncItems) then
    Exit;

  LLength := FSyncEdit.EditEndPosition.Char - FSyncEdit.EditBeginPosition.Char;

  LOldPenColor := Canvas.Pen.Color;
  LOldBrushStyle := Canvas.Brush.Style;
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := FSyncEdit.Colors.EditBorder;
  DrawRectangle(FSyncEdit.EditBeginPosition);

  for LIndex := 0 to FSyncEdit.SyncItems.Count - 1 do
  begin
    LTextPosition := PBCEditorTextPosition(FSyncEdit.SyncItems.Items[LIndex])^;

    if TextToDisplay(LTextPosition).Row > TopRow + VisibleRows then
      Exit
    else
    if TextToDisplay(LTextPosition).Row + 1 >= TopRow then
    begin
      Canvas.Pen.Color := FSyncEdit.Colors.WordBorder;
      DrawRectangle(LTextPosition);
    end;
  end;
  Canvas.Pen.Color := LOldPenColor;
  Canvas.Brush.Style := LOldBrushStyle;
end;

procedure TCustomBCEditor.PaintTextLines(AClipRect: TRect; const AFirstRow, ALastRow: Integer);
var
  LAddWrappedCount: Boolean;
  LBackgroundColor: TColor;
  LBookmarkOnCurrentLine: Boolean;
  LBorderColor: TColor;
  LCurrentLine: Integer;
  LCurrentRowText: string;
  LCurrentRowTextLength: Integer;
  LCurrentSearchIndex: Integer;
  LCustomBackgroundColor: TColor;
  LCustomForegroundColor: TColor;
  LCustomLineColors: Boolean;
  LExpandedCharsBefore: Integer;
  LForegroundColor: TColor;
  LIsCurrentLine: Boolean;
  LIsLineSelected: Boolean;
  LIsSearchInSelectionBlock: Boolean;
  LSelectionInRow: Boolean;
  LIsSyncEditBlock: Boolean;
  LLineEndRect: TRect;
  LSelectionEndColumn: Integer;
  LSelectionStartColumn: Integer;
  LMarkColor: TColor;
  LPaintedColumn: Integer;
  LPaintedWidth: Integer;
  LRGBColor: Cardinal;
  LRowRect: TRect;
  LSelectionBeginPosition: TBCEditorTextPosition;
  LSelectionEndPosition: TBCEditorTextPosition;
  LTextPosition: TBCEditorTextPosition;
  LTokenHelper: TBCEditorTokenHelper;
  LTokenRect: TRect;

  function IsBookmarkOnCurrentLine: Boolean;
  var
    LIndex: Integer;
    LMark: TBCEditorMark;
  begin
    Result := True;
    for LIndex := 0 to FBookmarkList.Count - 1 do
    begin
      LMark := FBookmarkList.Items[LIndex];
      if LMark.Line = LCurrentLine then
        Exit;
    end;
    Result := False;
  end;

  function GetBackgroundColor: TColor;
  var
    LHighlighterAttribute: TBCEditorHighlighter.TAttribute;
  begin
    if LIsCurrentLine and FActiveLine.Visible and (FActiveLine.Color <> clNone) then
      Result := FActiveLine.Color
    else
    if LMarkColor <> clNone then
      Result := LMarkColor
    else
    if LIsSyncEditBlock then
      Result := FSyncEdit.Colors.Background
    else
    if LIsSearchInSelectionBlock then
      Result := FSearch.InSelection.Background
    else
    begin
      Result := FBackgroundColor;
      if Assigned(FHighlighter) then
      begin
        LHighlighterAttribute := FHighlighter.GetCurrentRangeAttribute;
        if Assigned(LHighlighterAttribute) and (LHighlighterAttribute.Background <> clNone) then
          Result := LHighlighterAttribute.Background;
      end;
    end;
  end;

  procedure SetDrawingColors(const ASelected: Boolean);
  var
    LColor: TColor;
  begin
    { Selection colors }
    if (ASelected and (not HideSelection or Focused())) then
    begin
      if FSelection.Colors.Foreground <> clNone then
        FPaintHelper.SetForegroundColor(FSelection.Colors.Foreground)
      else
        FPaintHelper.SetForegroundColor(LForegroundColor);
      LColor := FSelection.Colors.Background;
    end
    { Normal colors }
    else
    begin
      FPaintHelper.SetForegroundColor(LForegroundColor);
      LColor := LBackgroundColor;
    end;
    FPaintHelper.SetBackgroundColor(LColor); { Text }
    Canvas.Brush.Color := LColor; { Rest of the line }
    LRGBColor := RGB(LColor and $FF, (LColor shr 8) and $FF, (LColor shr 16) and $FF);
  end;

  procedure PaintSearchResults(const AText: string; const ATextRect: TRect);
  var
    LBeginTextPosition: TBCEditorTextPosition;
    LCharCount: Integer;
    LIsTextPositionInSelection: Boolean;
    LOldBackgroundColor: TColor;
    LOldColor: TColor;
    LSearchItem: TSearchResult;
    LSearchRect: TRect;
    LSearchTextLength: Integer;
    LToken: string;

    function GetSearchTextLength: Integer;
    begin
      if (LCurrentLine = LSearchItem.BeginPosition.Line) and (LSearchItem.BeginPosition.Line = LSearchItem.EndPosition.Line) then
        Result := LSearchItem.EndPosition.Char - LSearchItem.BeginPosition.Char
      else
      if (LCurrentLine > LSearchItem.BeginPosition.Line) and (LCurrentLine < LSearchItem.EndPosition.Line) then
        Result := LCurrentRowTextLength
      else
      if (LCurrentLine = LSearchItem.BeginPosition.Line) and (LCurrentLine < LSearchItem.EndPosition.Line) then
        Result := LCurrentRowTextLength - LSearchItem.BeginPosition.Char + 2
      else
      if (LCurrentLine > LSearchItem.BeginPosition.Line) and (LCurrentLine = LSearchItem.EndPosition.Line) then
        Result := LSearchItem.EndPosition.Char
      else
        Result := 0;
    end;

    function NextItem: Boolean;
    begin
      Result := True;
      Inc(LCurrentSearchIndex);
      if LCurrentSearchIndex < FSearchResults.Count then
        LSearchItem := FSearchResults[LCurrentSearchIndex]
      else
      begin
        LCurrentSearchIndex := -1;
        Result := False;
      end;
    end;

  begin
    if soHighlightResults in FSearch.Options then
      if LCurrentSearchIndex <> -1 then
      begin
        LSearchItem := FSearchResults[LCurrentSearchIndex];

        while (LCurrentSearchIndex < FSearchResults.Count) and (LSearchItem.EndPosition.Line < LCurrentLine) do
        begin
          Inc(LCurrentSearchIndex);
          if LCurrentSearchIndex < FSearchResults.Count then
            LSearchItem := FSearchResults[LCurrentSearchIndex];
        end;
        if LCurrentSearchIndex = FSearchResults.Count then
        begin
          LCurrentSearchIndex := -1;
          Exit;
        end;

        if LCurrentLine < LSearchItem.BeginPosition.Line then
          Exit;

        LOldColor := FPaintHelper.Color;
        LOldBackgroundColor := FPaintHelper.BackgroundColor;

        if FSearch.Highlighter.Colors.Foreground <> clNone then
          FPaintHelper.SetForegroundColor(FSearch.Highlighter.Colors.Foreground);
        FPaintHelper.SetBackgroundColor(FSearch.Highlighter.Colors.Background);

        while True do
        begin
          LSearchTextLength := GetSearchTextLength;
          if LSearchTextLength = 0 then
            Break;

          if FSearch.InSelection.Active then
          begin
            LIsTextPositionInSelection := IsTextPositionInSearchBlock(LSearchItem.BeginPosition);
            if LIsTextPositionInSelection then
              LIsTextPositionInSelection := not Lines.IsPositionInSelection(LSearchItem.BeginPosition);
          end
          else
            LIsTextPositionInSelection := Lines.IsPositionInSelection(LSearchItem.BeginPosition) and
              Lines.IsPositionInSelection(LSearchItem.EndPosition);

          if not FSearch.InSelection.Active and LIsTextPositionInSelection or
            FSearch.InSelection.Active and not LIsTextPositionInSelection then
          begin
            if not NextItem then
              Break;
            Continue;
          end;

          LToken := AText;
          LSearchRect := ATextRect;

          if LSearchItem.BeginPosition.Line < LCurrentLine then
            LBeginTextPosition := TextPosition(0, 0)
          else
            LBeginTextPosition := LSearchItem.BeginPosition;

          LCharCount := LBeginTextPosition.Char - LTokenHelper.CharsBefore;

          if LCharCount > 0 then
          begin
            LToken := Copy(AText, 1, LCharCount);
            Inc(LSearchRect.Left, ComputeTokenWidth(LToken, LCharCount, LPaintedColumn));
            LToken := Copy(AText, LCharCount + 1, Length(AText));
          end
          else
            LCharCount := LTokenHelper.Length - Length(AText);

          LToken := LeftStr(LToken, Min(LSearchTextLength, LBeginTextPosition.Char + LSearchTextLength - LTokenHelper.CharsBefore - LCharCount));
          LSearchRect.Right := LSearchRect.Left + ComputeTokenWidth(LToken, Length(LToken), LPaintedColumn);
          if SameText(AText, LToken) then
            Inc(LSearchRect.Right, FItalicOffset);

          if LToken <> '' then
            ExtTextOut(Canvas.Handle, LSearchRect.Left, LSearchRect.Top, ETO_CLIPPED or ETO_OPAQUE,
              @LSearchRect, PChar(LToken), Length(LToken), nil);

          if LBeginTextPosition.Char + LSearchTextLength > LCurrentRowTextLength then
            Break
          else
          if LBeginTextPosition.Char + LSearchTextLength > LTokenHelper.CharsBefore + Length(LToken) + LCharCount + 1 then
            Break
          else
          if LBeginTextPosition.Char + LSearchTextLength - 1 <= LCurrentRowTextLength then
          begin
            if not NextItem then
              Break;
          end
          else
            Break;
        end;

        FPaintHelper.SetForegroundColor(LOldColor);
        FPaintHelper.SetBackgroundColor(LOldBackgroundColor);
      end;
  end;

  procedure PaintToken(const AToken: string; const ATokenLength: Integer);
  var
    LBottom: Integer;
    LLastChar: Char;
    LLastColumn: Integer;
    LLeft: Integer;
    LMaxX: Integer;
    LOldPenColor: TColor;
    LStep: Integer;
    LText: string;
    LTokenLength: Integer;
    LTop: Integer;
  begin
    LLastColumn := LTokenHelper.CharsBefore + Length(LTokenHelper.Text) + 1;

    if (LTokenRect.Right > LeftMarginWidth) then
    begin
      if (SpecialChars.Visible and (LTokenHelper.EmptySpace <> esNone)) then
      begin
        if (Canvas.Brush.Color <> FSelection.Colors.Background) then
          FPaintHelper.SetForegroundColor(SpecialChars.Color)
        else if (FSelection.Colors.Foreground <> clNone) then
          FPaintHelper.SetForegroundColor(FSelection.Colors.Foreground)
        else
          FPaintHelper.SetForegroundColor(LForegroundColor);

        case (LTokenHelper.EmptySpace) of
          esNoneChar,
          esSpace:
            begin
              if (ATokenLength > Length(FSpecialCharsText)) then
                FSpecialCharsText := StringOfChar(Char(#183), ATokenLength);
              FPaintHelper.SetStyle([fsBold]);
              ExtTextOut(Canvas.Handle, LTokenRect.Left, LTokenRect.Top,
                ETO_CLIPPED or ETO_OPAQUE, @LTokenRect, PChar(FSpecialCharsText), ATokenLength, nil);
            end;
          esTab:
            begin
              FPaintHelper.SetStyle([]);
              ExtTextOut(Canvas.Handle,
                LTokenRect.Left + (LTokenRect.Width - FTabSignWidth) div 2, LTokenRect.Top,
                ETO_CLIPPED or ETO_OPAQUE, @LTokenRect, #187, 1, nil);
            end;
          else raise ERangeError.Create('EmptySpace: ' + IntToStr(Ord(LTokenHelper.EmptySpace)));
        end;
      end
      else
      begin
        if (LTokenHelper.EmptySpace = esTab) then
        begin
          LTokenLength := ATokenLength * FTabs.Width;
          LText := StringOfChar(BCEDITOR_SPACE_CHAR, LTokenLength);
        end
        else
        begin
          LTokenLength := ATokenLength;
          LText := AToken;
        end;

        ExtTextOut(Canvas.Handle, LTokenRect.Left, LTokenRect.Top,
          ETO_CLIPPED or ETO_OPAQUE, @LTokenRect, PChar(LText), LTokenLength, nil);

        if LTokenHelper.IsItalic and (LText[1] <> BCEDITOR_SPACE_CHAR) and (ATokenLength = Length(AToken)) then
        begin
          LLastChar := AToken[ATokenLength];

          if ((Word(LLastChar) < 256) and (FItalicOffsetCache[AnsiChar(LLastChar)] <> 0)) then
            FItalicOffset := FItalicOffsetCache[AnsiChar(LLastChar)]
          else
          begin
            FItalicOffset := 0;

            LBottom := Min(LTokenRect.Bottom, Canvas.ClipRect.Bottom);

            LMaxX := LTokenRect.Right + 1;
            for LTop := LTokenRect.Top to LBottom - 1 do
              for LLeft := LMaxX to LTokenRect.Right - 1 do
                if GetPixel(Canvas.Handle, LLeft, LTop) <> LRGBColor then
                  if LLeft > LMaxX then
                    LMaxX := LLeft;
            FItalicOffset := Max(LMaxX - LTokenRect.Right + 1, 0);

            if (Word(LLastChar) < 256) then
              FItalicOffsetCache[AnsiChar(LLastChar)] := FItalicOffset;
          end;

//          if LLastColumn = LCurrentRowTextLength + 1 then
//            Inc(LTokenRect.Right, FItalicOffset);

          if LAddWrappedCount then
            Inc(LTokenRect.Right, FItalicOffset);
        end;
      end;

      if LTokenHelper.Border <> clNone then
      begin
        LOldPenColor := Canvas.Pen.Color;
        Canvas.Pen.Color := LTokenHelper.Border;
        Canvas.MoveTo(LTokenRect.Left, LTokenRect.Bottom - 1);
        Canvas.LineTo(LTokenRect.Right + FItalicOffset - 1, LTokenRect.Bottom - 1);
        Canvas.LineTo(LTokenRect.Right + FItalicOffset - 1, LTokenRect.Top);
        Canvas.LineTo(LTokenRect.Left, LTokenRect.Top);
        Canvas.LineTo(LTokenRect.Left, LTokenRect.Bottom - 1);
        Canvas.Pen.Color := LOldPenColor;
      end;

      if LTokenHelper.TokenAddon <> taNone then
      begin
        LOldPenColor := Canvas.Pen.Color;
        Canvas.Pen.Color := LTokenHelper.TokenAddonColor;
        case LTokenHelper.TokenAddon of
          taDoubleUnderline, taUnderline:
            begin
              if LTokenHelper.TokenAddon = taDoubleUnderline then
              begin
                Canvas.MoveTo(LTokenRect.Left, LTokenRect.Bottom - 3);
                Canvas.LineTo(LTokenRect.Right, LTokenRect.Bottom - 3);
              end;
              Canvas.MoveTo(LTokenRect.Left, LTokenRect.Bottom - 1);
              Canvas.LineTo(LTokenRect.Right, LTokenRect.Bottom - 1);
            end;
          taWaveLine:
            begin
              LStep := 0;
              while LStep < LTokenRect.Right - 4 do
              begin
                Canvas.MoveTo(LTokenRect.Left + LStep, LTokenRect.Bottom - 3);
                Canvas.LineTo(LTokenRect.Left + LStep + 2, LTokenRect.Bottom - 1);
                Canvas.LineTo(LTokenRect.Left + LStep + 4, LTokenRect.Bottom - 3);
                Inc(LStep, 4);
              end;
            end;
        end;
        Canvas.Pen.Color := LOldPenColor;
      end;
    end;

    LTokenRect.Left := LTokenRect.Right;

    if (SpecialChars.Visible and (LLastColumn >= LCurrentRowTextLength)) then
      LLineEndRect := LTokenRect;
  end;

  procedure PaintHighlightToken(const ARow: Integer; const AFillToEndOfLine: Boolean);
  var
    LFirstColumn: Integer;
    LFirstUnselectedPartOfToken: Boolean;
    LIsPartOfTokenSelected: Boolean;
    LLastColumn: Integer;
    LSearchTokenRect: TRect;
    LSecondUnselectedPartOfToken: Boolean;
    LSelected: Boolean;
    LSelectedRect: TRect;
    LSelectedText: string;
    LSelectedTokenLength: Integer;
    LTempRect: TRect;
    LText: string;
    LTokenLength: Integer;
  begin
    LFirstColumn := LTokenHelper.CharsBefore + 1;
    LLastColumn := LFirstColumn + LTokenHelper.Length;

    LFirstUnselectedPartOfToken := False;
    LSecondUnselectedPartOfToken := False;
    LIsPartOfTokenSelected := False;

    if LSelectionInRow then
    begin
      LSelected := (LFirstColumn >= LSelectionStartColumn) and (LFirstColumn < LSelectionEndColumn) or
        (LLastColumn > LSelectionStartColumn) and (LLastColumn <= LSelectionEndColumn) or
        (LSelectionStartColumn > LFirstColumn) and (LSelectionEndColumn < LLastColumn);
      if LSelected then
      begin
        LFirstUnselectedPartOfToken := LFirstColumn < LSelectionStartColumn;
        LSecondUnselectedPartOfToken := LLastColumn > LSelectionEndColumn;
        LIsPartOfTokenSelected := LFirstUnselectedPartOfToken or LSecondUnselectedPartOfToken;
      end;
    end
    else
      LSelected := LIsLineSelected;

    LBackgroundColor := LTokenHelper.Background;
    LForegroundColor := LTokenHelper.Foreground;

    FPaintHelper.SetStyle(LTokenHelper.FontStyle);

    if LCustomLineColors and (LCustomForegroundColor <> clNone) then
      LForegroundColor := LCustomForegroundColor;
    if LCustomLineColors and (LCustomBackgroundColor <> clNone) then
      LBackgroundColor := LCustomBackgroundColor;

    LText := LTokenHelper.Text;
    LTokenLength := 0;
    LSelectedTokenLength := 0;
    LSearchTokenRect := LTokenRect;

    if LIsPartOfTokenSelected then
    begin
      if LFirstUnselectedPartOfToken then
      begin
        SetDrawingColors(False);
        LTokenLength := LSelectionStartColumn - LFirstColumn;
        LTokenRect.Right := LTokenRect.Left + ComputeTokenWidth(LText, LTokenLength, LTokenHelper.ExpandedCharsBefore);
        PaintToken(LText, LTokenLength);
        Delete(LText, 1, LTokenLength);
      end;
      { Selected part of the token }
      LTokenLength := Min(LSelectionEndColumn, LLastColumn) - LFirstColumn - LTokenLength;
      LTokenRect.Right := LTokenRect.Left + ComputeTokenWidth(LText, LTokenLength, LTokenHelper.ExpandedCharsBefore);
      LSelectedRect := LTokenRect;
      LSelectedTokenLength := LTokenLength;
      LSelectedText := LText;
      LTokenRect.Left := LTokenRect.Right;
      if LSecondUnselectedPartOfToken then
      begin
        Delete(LText, 1, LTokenLength);
        SetDrawingColors(False);
        LTokenRect.Right := LTokenRect.Left + ComputeTokenWidth(LText, Length(LText), LTokenHelper.ExpandedCharsBefore);
        PaintToken(LText, Length(LText));
      end;
    end
    else
    if LText <> '' then
    begin
      SetDrawingColors(LSelected);
      LTokenLength := Length(LText);
      LTokenRect.Right := LTokenRect.Left + ComputeTokenWidth(LText, LTokenLength, LTokenHelper.ExpandedCharsBefore);
      PaintToken(LText, LTokenLength)
    end;

    if (not LSelected or LIsPartOfTokenSelected) then
    begin
      LSearchTokenRect.Right := LTokenRect.Right;
      PaintSearchResults(LTokenHelper.Text, LSearchTokenRect);
    end;

    if LIsPartOfTokenSelected then
    begin
      SetDrawingColors(True);
      LTempRect := LTokenRect;
      LTokenRect := LSelectedRect;
      PaintToken(LSelectedText, LSelectedTokenLength);
      LTokenRect := LTempRect;
    end;

    if AFillToEndOfLine and (LTokenRect.Left < LRowRect.Right) then
    begin
      LBackgroundColor := GetBackgroundColor;

      if LCustomLineColors and (LCustomForegroundColor <> clNone) then
        LForegroundColor := LCustomForegroundColor;
      if LCustomLineColors and (LCustomBackgroundColor <> clNone) then
        LBackgroundColor := LCustomBackgroundColor;

      if Lines.SelMode = smNormal then
      begin
        SetDrawingColors(not (soToEndOfLine in FSelection.Options) and (LIsLineSelected or LSelected and (LSelectionEndColumn > LLastColumn)));
        LTokenRect.Right := LRowRect.Right;
        FillRect(LTokenRect);
      end
      else
      begin
        if LSelectionStartColumn > LLastColumn then
        begin
          SetDrawingColors(False);
          LTokenRect.Right := Min(LTokenRect.Left + (LSelectionStartColumn - LLastColumn) * CharWidth, LRowRect.Right);
          FillRect(LTokenRect);
        end;

        if (LTokenRect.Right < LRowRect.Right) and (LSelectionEndColumn > LLastColumn) then
        begin
          SetDrawingColors(True);
          LTokenRect.Left := LTokenRect.Right;
          if LSelectionStartColumn > LLastColumn then
            LTokenLength := LSelectionEndColumn - LSelectionStartColumn
          else
            LTokenLength := LSelectionEndColumn - LLastColumn;
          LTokenRect.Right := Min(LTokenRect.Left + LTokenLength * CharWidth, LRowRect.Right);
          FillRect(LTokenRect);
        end;

        if LTokenRect.Right < LRowRect.Right then
        begin
          SetDrawingColors(False);
          LTokenRect.Left := LTokenRect.Right;
          LTokenRect.Right := LRowRect.Right;
          FillRect(LTokenRect);
        end;

        if LTokenRect.Right = LRowRect.Right then
        begin
          SetDrawingColors(False);
          FillRect(LTokenRect);
        end;
      end;
    end;
  end;

  procedure PrepareTokenHelper(const ARow: Integer; const AToken: string; const ACharsBefore, ATokenLength: Integer;
    const AForeground, ABackground: TColor; const ABorder: TColor; const AFontStyle: TFontStyles;
    const ATokenAddon: TBCEditorTokenAddon;
    const ATokenAddonColor: TColor;
    const ACustomBackgroundColor: Boolean);
  var
    LAppendAnsiChars: Boolean;
    LAppendTabs: Boolean;
    LAppendUnicode: Boolean;
    LBackground: TColor;
    LCanAppend: Boolean;
    LEmptySpace: TBCEditorEmptySpace;
    LForeground: TColor;
    LPToken: PChar;
  begin
    LForeground := AForeground;
    LBackground := ABackground;
    if (LBackground = clNone) or ((FActiveLine.Color <> clNone) and LIsCurrentLine and not ACustomBackgroundColor) then
      LBackground := GetBackgroundColor;
    if AForeground = clNone then
      LForeground := FForegroundColor;

    LCanAppend := False;

    LPToken := PChar(AToken);

    case (LPToken^) of
      BCEDITOR_NONE_CHAR:
        LEmptySpace := esNoneChar;
      BCEDITOR_SPACE_CHAR:
        LEmptySpace := esSpace;
      BCEDITOR_TAB_CHAR:
        LEmptySpace := esTab;
      else
        LEmptySpace := esNone;
    end;

    if (LEmptySpace <> esNone) and SpecialChars.Visible then
      LForeground := SpecialChars.Color;

    if LTokenHelper.Length > 0 then
    begin
      LCanAppend := (LTokenHelper.Length < BCEDITOR_TOKEN_MAX_LENGTH) and
        (LTokenHelper.Background = LBackground) and (LTokenHelper.Foreground = LForeground);
      LAppendAnsiChars := (LTokenHelper.Length > 0) and (Ord(LTokenHelper.Text[1]) < 256) and (Ord(LPToken^) < 256);
      LAppendUnicode := LPToken^.GetUnicodeCategory in [TUnicodeCategory.ucCombiningMark, TUnicodeCategory.ucNonSpacingMark];
      LAppendTabs := not (toColumns in FTabs.Options) or (toColumns in FTabs.Options) and (LEmptySpace <> esTab);

      LCanAppend := LCanAppend and
        ((LTokenHelper.FontStyle = AFontStyle) or ((LEmptySpace <> esNone) and not (fsUnderline in AFontStyle) and
        not (fsUnderline in LTokenHelper.FontStyle))) and (LTokenHelper.TokenAddon = ATokenAddon) and
        (LEmptySpace = LTokenHelper.EmptySpace) and (LAppendAnsiChars or LAppendUnicode) and LAppendTabs;

      if not LCanAppend then
      begin
        PaintHighlightToken(ARow, False);
        LTokenHelper.EmptySpace := esNone;
      end;
    end;

    LTokenHelper.EmptySpace := LEmptySpace;

    if LCanAppend then
    begin
      Insert(AToken, LTokenHelper.Text, LTokenHelper.Length + 1);
      Inc(LTokenHelper.Length, ATokenLength);
    end
    else
    begin
      LTokenHelper.Length := ATokenLength;
      LTokenHelper.Text := AToken;
      LTokenHelper.CharsBefore := ACharsBefore;
      LTokenHelper.ExpandedCharsBefore := LExpandedCharsBefore;
      LTokenHelper.Foreground := LForeground;
      LTokenHelper.Background := LBackground;
      LTokenHelper.Border := ABorder;
      LTokenHelper.FontStyle := AFontStyle;
      LTokenHelper.IsItalic := fsItalic in AFontStyle;
      LTokenHelper.TokenAddon := ATokenAddon;
      LTokenHelper.TokenAddonColor := ATokenAddonColor;
    end;

    LPToken := PChar(AToken);

    if LPToken^ = BCEDITOR_TAB_CHAR then
    begin
      if toColumns in FTabs.Options then
        Inc(LExpandedCharsBefore, FTabs.Width - LExpandedCharsBefore mod FTabs.Width)
      else
        Inc(LExpandedCharsBefore, FTabs.Width);
    end
    else
      Inc(LExpandedCharsBefore, ATokenLength);
  end;

  procedure PaintLines;
  var
    LFontStyles: TFontStyles;
    LHighlighterAttribute: TBCEditorHighlighter.TAttribute;
    LIsCustomBackgroundColor: Boolean;
    LLastColumn: Integer;
    LSelectedText: string;
    LTokenAddon: TBCEditorTokenAddon;
    LTokenAddonColor: TColor;
    LTokenLength: Integer;
    LTokenPosition: Integer;
    LTokenText: string;
    LWordAtSelection: string;

    function GetWordAtSelection(var ASelectedText: string): string;
    var
      LBeginPosition: TBCEditorTextPosition;
      LEndPosition: TBCEditorTextPosition;
    begin
      LBeginPosition := TextPosition(Min(Lines.SelBeginPosition.Char, Lines.SelEndPosition.Char), Lines.SelBeginPosition.Line);
      LEndPosition := TextPosition(Max(Lines.SelBeginPosition.Char, Lines.SelEndPosition.Char), Lines.SelBeginPosition.Line);
      if (LBeginPosition.Line < Lines.Count) then
      begin
        LEndPosition.Char := Min(LEndPosition.Char, Length(Lines.Lines[LEndPosition.Line].Text));
        ASelectedText := Lines.TextBetween[LBeginPosition, LEndPosition]
      end
      else
        ASelectedText := '';
      if (LEndPosition < Lines.EOFPosition) then
        Result := WordAt[Point(LEndPosition)]
      else
        Result := '';
    end;

    procedure PrepareToken(const ARow: Integer);
    begin
      LBorderColor := clNone;
      LHighlighterAttribute := FHighlighter.GetTokenAttribute;
      if not (csDesigning in ComponentState) and Assigned(LHighlighterAttribute) then
      begin
        LForegroundColor := LHighlighterAttribute.Foreground;
        LBackgroundColor := LHighlighterAttribute.Background;
        LFontStyles := LHighlighterAttribute.FontStyles;

        LIsCustomBackgroundColor := False;
        LTokenAddon := taNone;
        LTokenAddonColor := clNone;

        if Assigned(FOnCustomTokenAttribute) then
          FOnCustomTokenAttribute(Self, LTokenText, LCurrentLine, LTokenPosition, LForegroundColor,
            LBackgroundColor, LFontStyles, LTokenAddon, LTokenAddonColor);

        if FMatchingPair.Enabled and not FSyncEdit.Active and (FCurrentMatchingPair <> trNotFound) then
          if (LCurrentLine = FCurrentMatchingPairMatch.OpenPosition.Line) and
            (LTokenPosition = FCurrentMatchingPairMatch.OpenPosition.Char) or
            (LCurrentLine = FCurrentMatchingPairMatch.ClosePosition.Line) and
            (LTokenPosition = FCurrentMatchingPairMatch.ClosePosition.Char) then
          begin
            if (FCurrentMatchingPair = trOpenAndCloseTokenFound) or (FCurrentMatchingPair = trCloseAndOpenTokenFound) then
            begin
              LIsCustomBackgroundColor := mpoUseMatchedColor in FMatchingPair.Options;
              if LIsCustomBackgroundColor then
              begin
                if LForegroundColor = FMatchingPair.Colors.Matched then
                  LForegroundColor := FBackgroundColor;
                LBackgroundColor := FMatchingPair.Colors.Matched;
              end;
              if mpoUnderline in FMatchingPair.Options then
              begin
                LTokenAddon := taUnderline;
                LTokenAddonColor := FMatchingPair.Colors.Underline;
              end;
            end
            else
            if mpoHighlightUnmatched in FMatchingPair.Options then
            begin
              LIsCustomBackgroundColor := mpoUseMatchedColor in FMatchingPair.Options;
              if LIsCustomBackgroundColor then
              begin
                if LForegroundColor = FMatchingPair.Colors.Unmatched then
                  LForegroundColor := FBackgroundColor;
                LBackgroundColor := FMatchingPair.Colors.Unmatched;
              end;
              if mpoUnderline in FMatchingPair.Options then
              begin
                LTokenAddon := taUnderline;
                LTokenAddonColor := FMatchingPair.Colors.Underline;
              end;
            end;
          end;

        if FSyncEdit.BlockSelected and LIsSyncEditBlock then
          LBackgroundColor := FSyncEdit.Colors.Background;

        if FSearch.InSelection.Active and LIsSearchInSelectionBlock then
          LBackgroundColor := FSearch.InSelection.Background;

        if (LMarkColor <> clNone) and not (LIsCurrentLine and FActiveLine.Visible and (FActiveLine.Color <> clNone)) then
        begin
          LIsCustomBackgroundColor := True;
          LBackgroundColor := LMarkColor;
        end;

        PrepareTokenHelper(ARow, LTokenText, LTokenPosition, LTokenLength, LForegroundColor, LBackgroundColor, LBorderColor,
          LFontStyles, LTokenAddon, LTokenAddonColor, LIsCustomBackgroundColor)
      end
      else
        PrepareTokenHelper(ARow, LTokenText, LTokenPosition, LTokenLength, LForegroundColor, LBackgroundColor, LBorderColor,
          Font.Style, taNone, clNone, False);
    end;

    procedure SetLineSelectionVariables();
    begin
      LSelectionInRow := False;

      if ((LSelectionBeginPosition.Line <= LCurrentLine) and (LCurrentLine <= LSelectionEndPosition.Line)) then
      begin
        LSelectionStartColumn := 1;
        LSelectionEndColumn := LLastColumn + 1;
        if ((Lines.SelMode = smColumn)
          or (Lines.SelMode = smNormal) and (LCurrentLine = LSelectionBeginPosition.Line)) then
          if LSelectionBeginPosition.Char > LLastColumn - 1 then
          begin
            LSelectionStartColumn := 0;
            LSelectionEndColumn := 0;
          end
          else if LSelectionBeginPosition.Char > LTokenPosition - 1 then
          begin
            LSelectionStartColumn := LSelectionBeginPosition.Char + 1;
            LSelectionInRow := True;
          end;

        if (Lines.SelMode = smColumn) or
          ((Lines.SelMode = smNormal) and (LCurrentLine = LSelectionEndPosition.Line)) then
          if LSelectionEndPosition.Char < 0 then
          begin
            LSelectionStartColumn := 0;
            LSelectionEndColumn := 0;
          end
          else if LSelectionEndPosition.Char < LLastColumn - 1 then
          begin
            LSelectionEndColumn := LSelectionEndPosition.Char + 1;
            LSelectionInRow := True;
          end;
      end
      else
      begin
        LSelectionStartColumn := 0;
        LSelectionEndColumn := 0;
      end;

      LIsLineSelected := not LSelectionInRow and (LSelectionStartColumn > 0);
    end;

  var
    LElement: string;
    LFirstColumn: Integer;
    LFoldRange: TBCEditorCodeFolding.TRanges.TRange;
    LBeginLineText: string;
    LNextTokenText: string;
    LOpenTokenEndLen: Integer;
    LOpenTokenEndPos: Integer;
    LRow: Integer;
    LTextCaretY: Integer;
    LTextPosition: TBCEditorTextPosition;
    LEndLineText: string;
    LWordWrapTokenPosition: Integer;
  begin
    LRowRect := AClipRect;
    LRowRect.Bottom := LineHeight;
    LFirstColumn := HorzTextPos div CharWidth;

    LWordAtSelection := GetWordAtSelection(LSelectedText);

    if (SelectionAvailable) then
    begin
      LSelectionBeginPosition := Min(Lines.SelBeginPosition, Lines.SelEndPosition);
      LSelectionEndPosition := Max(Lines.SelBeginPosition, Lines.SelEndPosition);

      if Lines.SelMode = smColumn then
        if LSelectionBeginPosition.Char > LSelectionEndPosition.Char then
          SwapInt(LSelectionBeginPosition.Char, LSelectionEndPosition.Char);
    end;

    LBookmarkOnCurrentLine := False;

    for LRow := AFirstRow to ALastRow do
    begin
      LCurrentLine := Rows[LRow].Line;

      LMarkColor := GetMarkBackgroundColor(LCurrentLine);

      LPaintedColumn := 1;

      LIsCurrentLine := False;

      LTokenPosition := 0;
      LTokenLength := 0;
      LNextTokenText := '';
      LExpandedCharsBefore := 0;
      LTextCaretY := Lines.CaretPosition.Line;

      LCurrentRowText := Rows.Text[LRow];
      LCurrentRowTextLength := Length(LCurrentRowText);
      if (not WordWrap.Enabled) then
        LLastColumn := LFirstColumn + GetVisibleChars(LRow, LCurrentRowText)
      else
        LLastColumn := Rows[LRow].Length;

      SetLineSelectionVariables;

      LFoldRange := nil;
      if FCodeFolding.Visible then
      begin
        LFoldRange := CodeFoldingCollapsableFoldRangeForLine(LCurrentLine + 1);
        if Assigned(LFoldRange) and LFoldRange.Collapsed then
        begin
          LOpenTokenEndLen := 0;
          LBeginLineText := Lines.Lines[LFoldRange.FirstLine].Text;
          LEndLineText := Lines.Lines[LFoldRange.LastLine].Text;

          LOpenTokenEndPos := Pos(LFoldRange.RegionItem.OpenTokenEnd, AnsiUpperCase(LBeginLineText));

          if LOpenTokenEndPos > 0 then
          begin
            if LCurrentLine = 0 then
              FHighlighter.ResetCurrentRange
            else
              FHighlighter.SetCurrentRange(Lines.Lines[LCurrentLine - 1].Range);
            FHighlighter.SetCurrentLine(LBeginLineText);
            repeat
              while not FHighlighter.GetEndOfLine and
                (LOpenTokenEndPos > FHighlighter.GetTokenIndex + FHighlighter.GetTokenLength) do
                FHighlighter.Next;
              LElement := FHighlighter.GetCurrentRangeAttribute.Element;
              if (LElement <> BCEDITOR_ATTRIBUTE_ELEMENT_COMMENT) and (LElement <> BCEDITOR_ATTRIBUTE_ELEMENT_STRING) then
                Break;
              LOpenTokenEndPos := Pos(LFoldRange.RegionItem.OpenTokenEnd, AnsiUpperCase(LBeginLineText),
                LOpenTokenEndPos + 1);
            until LOpenTokenEndPos = 0;
          end;

          if (LFoldRange.RegionItem.OpenTokenEnd <> '') and (LOpenTokenEndPos > 0) then
          begin
            LOpenTokenEndLen := Length(LFoldRange.RegionItem.OpenTokenEnd);
            LCurrentRowText := Copy(LBeginLineText, 1, LOpenTokenEndPos + LOpenTokenEndLen - 1);
          end
          else
            LCurrentRowText := Copy(LBeginLineText, 1, Length(LFoldRange.RegionItem.OpenToken) +
              Pos(LFoldRange.RegionItem.OpenToken, AnsiUpperCase(LBeginLineText)) - 1);

          if LFoldRange.RegionItem.CloseToken <> '' then
            if Pos(LFoldRange.RegionItem.CloseToken, AnsiUpperCase(LEndLineText)) <> 0 then
            begin
              LCurrentRowText := LCurrentRowText + '..' + TrimLeft(LEndLineText);
              if LSelectionInRow then
                LSelectionEndColumn := Length(LCurrentRowText);
            end;

          if LCurrentLine = FCurrentMatchingPairMatch.OpenPosition.Line then
          begin
            if (LFoldRange.RegionItem.OpenTokenEnd <> '') and (LOpenTokenEndPos > 0) then
              FCurrentMatchingPairMatch.ClosePosition.Char := LOpenTokenEndPos + LOpenTokenEndLen + 2 { +2 = '..' } - 1
            else
              FCurrentMatchingPairMatch.ClosePosition.Char := FCurrentMatchingPairMatch.OpenPosition.Char +
                Length(FCurrentMatchingPairMatch.OpenText) + 2 { +2 = '..' };
            FCurrentMatchingPairMatch.ClosePosition.Line := FCurrentMatchingPairMatch.OpenPosition.Line;
          end;
        end;
      end;

      if LCurrentLine = 0 then
        FHighlighter.ResetCurrentRange
      else
        FHighlighter.SetCurrentRange(Lines.Lines[LCurrentLine - 1].Range);

      FHighlighter.SetCurrentLine(LCurrentRowText);
      LWordWrapTokenPosition := 0;

      LPaintedWidth := 0;
      FItalicOffset := 0;

      if Assigned(FMultiCarets) then
        LIsCurrentLine := IsMultiEditCaretFound(LCurrentLine + 1)
      else
        LIsCurrentLine := LTextCaretY = LCurrentLine;

      LForegroundColor := FForegroundColor;
      LBackgroundColor := GetBackgroundColor;

      LCustomLineColors := False;
      if Assigned(FOnCustomLineColors) then
        FOnCustomLineColors(Self, LCurrentLine, LCustomLineColors, LCustomForegroundColor, LCustomBackgroundColor);

      LTokenRect := LRowRect;
      LLineEndRect := LRowRect;
      LLineEndRect.Left := -100;
      LTokenHelper.Length := 0;
      LTokenHelper.EmptySpace := esNone;
      LAddWrappedCount := False;

      while (not FHighlighter.GetEndOfLine) do
      begin
        LTokenPosition := FHighlighter.GetTokenIndex;

        if LNextTokenText = '' then
        begin
          FHighlighter.GetTokenText(LTokenText);
          LWordWrapTokenPosition := 0;
        end
        else
        begin
          LTokenText := LNextTokenText;
          Inc(LTokenPosition, LWordWrapTokenPosition);
        end;
        LNextTokenText := '';
        LTokenLength := Length(LTokenText);

        begin
          LIsSyncEditBlock := False;
          if FSyncEdit.BlockSelected then
          begin
            LTextPosition := TextPosition(LTokenPosition, LCurrentLine);
            if FSyncEdit.IsTextPositionInBlock(LTextPosition) then
              LIsSyncEditBlock := True;
          end;

          LIsSearchInSelectionBlock := False;
          if FSearch.InSelection.Active then
          begin
            LTextPosition := TextPosition(LTokenPosition, LCurrentLine);
            if IsTextPositionInSearchBlock(LTextPosition) then
              LIsSearchInSelectionBlock := True;
          end;

          PrepareToken(LRow);
        end;

        if (LTokenPosition + LTokenLength > LLastColumn) then
          break;

        FHighlighter.Next;
      end;

      PaintHighlightToken(LRow, True);

      if (SpecialChars.Visible
        and (rfLastRowOfLine in Rows[LRow].Flags)
        and (Rows[LRow].Length < Lines.Count - 1)) then
      begin
        if (Canvas.Brush.Color <> FSelection.Colors.Background) then
          FPaintHelper.SetForegroundColor(SpecialChars.Color)
        else if (FSelection.Colors.Foreground <> clNone) then
          FPaintHelper.SetForegroundColor(FSelection.Colors.Foreground)
        else
          FPaintHelper.SetForegroundColor(LForegroundColor);
        FPaintHelper.SetStyle([]);
        ExtTextOut(Canvas.Handle, LTokenRect.Left, LTokenRect.Top,
          ETO_CLIPPED or ETO_OPAQUE, @LTokenRect, #182, 1, nil);
        Inc(LTokenRect.Left, FLineBreakSignWidth);
      end;

      PaintCodeFoldingCollapseMark(LFoldRange, LTokenPosition, LTokenLength, LCurrentLine, LRowRect);
      PaintCodeFoldingCollapsedLine(LFoldRange, LRowRect);

      if Assigned(FOnAfterLinePaint) then
        FOnAfterLinePaint(Self, Canvas, LRowRect, LCurrentLine);

      LRowRect.Top := LRowRect.Bottom;
      Inc(LRowRect.Bottom, LineHeight);
    end;
    LIsCurrentLine := False;
  end;

begin
  LCurrentSearchIndex := -1;

  if (FSearchResults.Count > 0) then
  begin
    LCurrentSearchIndex := 0;
    while LCurrentSearchIndex < FSearchResults.Count do
    begin
      LTextPosition := FSearchResults[LCurrentSearchIndex].EndPosition;
      if LTextPosition.Line + 1 >= TopRow then
        Break
      else
        Inc(LCurrentSearchIndex);
    end;
    if LCurrentSearchIndex = FSearchResults.Count then
      LCurrentSearchIndex := -1;
  end;

  PaintLines;

  LBookmarkOnCurrentLine := False;

  { Fill below the last line }
  LTokenRect := AClipRect;
  LTokenRect.Top := (ALastRow - TopRow + 1) * LineHeight;

  if LTokenRect.Top < LTokenRect.Bottom then
  begin
    LBackgroundColor := FBackgroundColor;
    SetDrawingColors(False);
    FillRect(LTokenRect);
  end;
end;

procedure TCustomBCEditor.PasteFromClipboard();
begin
  CommandProcessor(ecPaste, BCEDITOR_NONE_CHAR, nil);
end;

function TCustomBCEditor.PixelsToTextPosition(const X, Y: Integer): TBCEditorTextPosition;
begin
  Result := TextPosition(ClientToText(X, Y));
end;

function TCustomBCEditor.PreviousWordPosition(const ATextPosition: TBCEditorTextPosition): TBCEditorTextPosition;
begin
  if (ATextPosition.Line < Lines.Count) then
    Result := Min(ATextPosition, Lines.EOLPosition[ATextPosition.Line])
  else
    Result := Lines.EOFPosition;

  if (Result.Char > 0) then
    while ((Result.Char > 0) and IsWordBreakChar(Lines.Lines[Result.Line].Text[1 + Result.Char - 1])) do
      Dec(Result.Char)
  else if (Result.Line > 0) then
    Result := Lines.EOLPosition[Result.Line - 1]
  else
    Result := Lines.BOFPosition;
end;

procedure TCustomBCEditor.ReadState(Reader: TReader);
begin
  inherited;

  if (eoTrimTrailingLines in Options) then
    Lines.Options := Lines.Options + [loTrimTrailingLines]
  else
    Lines.Options := Lines.Options - [loTrimTrailingLines];
  if (eoTrimTrailingSpaces in Options) then
    Lines.Options := Lines.Options + [loTrimTrailingSpaces]
  else
    Lines.Options := Lines.Options - [loTrimTrailingSpaces];
  if (toColumns in Tabs.Options) then
    Lines.Options := Lines.Options + [loColumnTabs]
  else
    Lines.Options := Lines.Options - [loColumnTabs];
end;

procedure TCustomBCEditor.Redo();
begin
  Lines.Redo();
end;

procedure TCustomBCEditor.RegisterCommandHandler(const AHookedCommandEvent: TBCEditorHookedCommandEvent;
  AHandlerData: Pointer);
begin
  if not Assigned(AHookedCommandEvent) then
    Exit;
  if not Assigned(FHookedCommandHandlers) then
    FHookedCommandHandlers := TObjectList.Create;
  if FindHookedCommandEvent(AHookedCommandEvent) = -1 then
    FHookedCommandHandlers.Add(TBCEditorHookedCommandHandler.Create(AHookedCommandEvent, AHandlerData))
end;

procedure TCustomBCEditor.RemoveChainedEditor;
begin
  if Assigned(FChainedEditor) then
    RemoveFreeNotification(FChainedEditor);
  FChainedEditor := nil;

  UnhookEditorLines;
end;

procedure TCustomBCEditor.RemoveDuplicateMultiCarets;
var
  LIndex1: Integer;
  LIndex2: Integer;
begin
  if Assigned(FMultiCarets) then
    for LIndex1 := 0 to FMultiCarets.Count - 1 do
      for LIndex2 := FMultiCarets.Count - 1 downto LIndex1 + 1 do
        if (FMultiCarets[LIndex1] = FMultiCarets[LIndex2]) then
          FMultiCarets.Delete(LIndex2);
end;

procedure TCustomBCEditor.RemoveKeyDownHandler(AHandler: TKeyEvent);
begin
  FKeyboardHandler.RemoveKeyDownHandler(AHandler);
end;

procedure TCustomBCEditor.RemoveKeyPressHandler(AHandler: TBCEditorKeyPressWEvent);
begin
  FKeyboardHandler.RemoveKeyPressHandler(AHandler);
end;

procedure TCustomBCEditor.RemoveKeyUpHandler(AHandler: TKeyEvent);
begin
  FKeyboardHandler.RemoveKeyUpHandler(AHandler);
end;

procedure TCustomBCEditor.RemoveMouseCursorHandler(AHandler: TBCEditorMouseCursorEvent);
begin
  FKeyboardHandler.RemoveMouseCursorHandler(AHandler);
end;

procedure TCustomBCEditor.RemoveMouseDownHandler(AHandler: TMouseEvent);
begin
  FKeyboardHandler.RemoveMouseDownHandler(AHandler);
end;

procedure TCustomBCEditor.RemoveMouseUpHandler(AHandler: TMouseEvent);
begin
  FKeyboardHandler.RemoveMouseUpHandler(AHandler);
end;

procedure TCustomBCEditor.ReplaceChanged(AEvent: TBCEditorReplaceChanges);
begin
  case AEvent of
    rcEngineUpdate:
      begin
        Lines.CaretPosition := Lines.BOFPosition;
        FSearch.Engine := FReplace.Engine;
      end;
  end;
end;

function TCustomBCEditor.ReplaceText(): Integer;
begin
  if (SelectionAvailable and (roSelectedOnly in Replace.Options)) then
  begin
    Replace.BeginPosition := Lines.SelBeginPosition;
    Replace.EndPosition := Lines.SelEndPosition;
  end
  else if (roEntireScope in FReplace.Options) then
  begin
    Replace.BeginPosition := Lines.BOFPosition;
    Replace.EndPosition := Lines.EOFPosition;
  end
  else if (roBackwards in FReplace.Options) then
  begin
    Replace.BeginPosition := Lines.BOFPosition;
    Replace.EndPosition := Lines.CaretPosition;
  end
  else
  begin
    Replace.BeginPosition := Lines.CaretPosition;
    Replace.EndPosition := Lines.EOFPosition;
  end;

  Result := DoReplaceText();
end;

procedure TCustomBCEditor.RescanCodeFoldingRanges;
var
  LCodeFoldingRange: TBCEditorCodeFolding.TRanges.TRange;
  LIndex: Integer;
begin
  FRescanCodeFolding := False;

  { Delete all uncollapsed folds }
  for LIndex := FAllCodeFoldingRanges.AllCount - 1 downto 0 do
  begin
    LCodeFoldingRange := FAllCodeFoldingRanges[LIndex];
    if Assigned(LCodeFoldingRange) then
    begin
      if not LCodeFoldingRange.Collapsed and not LCodeFoldingRange.ParentCollapsed then
      begin
        FCodeFoldingRangeFromLine[LCodeFoldingRange.FirstLine] := nil;
        FCodeFoldingRangeToLine[LCodeFoldingRange.LastLine] := nil;
        FreeAndNil(LCodeFoldingRange);
        FAllCodeFoldingRanges.List.Delete(LIndex);
      end
    end;
  end;

  ScanCodeFoldingRanges;

  CodeFoldingResetCaches;
  Invalidate;
end;

function TCustomBCEditor.RescanHighlighterRangesFrom(const ALine: Integer): Integer;
var
  LRange: TBCEditorHighlighter.TRange;
begin
  Assert(ALine < Lines.Count);

  if (ALine = 0) then
    FHighlighter.ResetCurrentRange()
  else
    FHighlighter.SetCurrentRange(Lines.Lines[ALine - 1].Range);

  Result := ALine;
  repeat
    FHighlighter.SetCurrentLine(Lines.Lines[Result].Text);
    FHighlighter.NextToEndOfLine();
    LRange := FHighlighter.GetCurrentRange();
    if (Lines.Lines[Result].Range = LRange) then
      exit;
    Lines.SetRange(Result, LRange);
    Inc(Result);
  until (Result = Lines.Count);

  Dec(Result);
end;

procedure TCustomBCEditor.ResetCaret;
var
  LCaretStyle: TBCEditorCaretStyle;
  LHeight: Integer;
  LWidth: Integer;
begin
  if FTextEntryMode = temInsert then
    LCaretStyle := FCaret.Styles.Insert
  else
    LCaretStyle := FCaret.Styles.Overwrite;
  LHeight := 1;
  LWidth := 1;
  FCaretOffset := Point(FCaret.Offsets.Left, FCaret.Offsets.Top);
  case LCaretStyle of
    csHorizontalLine, csThinHorizontalLine:
      begin
        LWidth := CharWidth;
        if LCaretStyle = csHorizontalLine then
          LHeight := 2;
        FCaretOffset.Y := FCaretOffset.Y + LineHeight;
      end;
    csHalfBlock:
      begin
        LWidth := CharWidth;
        LHeight := LineHeight div 2;
        FCaretOffset.Y := FCaretOffset.Y + LHeight;
      end;
    csBlock:
      begin
        LWidth := CharWidth;
        LHeight := LineHeight;
      end;
    csVerticalLine, csThinVerticalLine:
      begin
        if LCaretStyle = csVerticalLine then
          LWidth := 2;
        LHeight := LineHeight;
      end;
  end;
  Exclude(FState, esCaretVisible);

  if (HandleAllocated) then
  begin
    CreateCaret(Handle, 0, LWidth, LHeight);
    UpdateCaret();
  end;
end;

procedure TCustomBCEditor.Resize();
begin
  SizeOrFontChanged(False);

  inherited;
end;

procedure TCustomBCEditor.RightMarginChanged(ASender: TObject);
begin
  if (WordWrap.Enabled and (FWordWrap.Width = wwwRightMargin)) then
  begin
    FRows.Clear();
    FMultiCaretPosition.Row := -1;
  end;

  Invalidate();
end;

procedure TCustomBCEditor.SaveToFile(const AFileName: string; AEncoding: TEncoding = nil);
var
  LFileStream: TFileStream;
begin
  LFileStream := TFileStream.Create(AFileName, fmCreate);
  try
    SaveToStream(LFileStream, AEncoding);
  finally
    LFileStream.Free;
  end;
end;

procedure TCustomBCEditor.SaveToStream(AStream: TStream; AEncoding: TEncoding = nil);
begin
  Lines.SaveToStream(AStream, AEncoding);
  SetModified(False);
end;

procedure TCustomBCEditor.ScanCodeFoldingRanges;
const
  DEFAULT_CODE_FOLDING_RANGE_INDEX = 0;
var
  LBeginningOfLine: Boolean;
  LCodeFoldingRangeIndexList: TList;
  LCurrentCodeFoldingRegion: TBCEditorCodeFolding.TRegion;
  LFoldCount: Integer;
  LFoldRanges: TBCEditorCodeFolding.TRanges;
  LLastFoldRange: TBCEditorCodeFolding.TRanges.TRange;
  LLine: Integer;
  LLineEndPos: PChar;
  LLinePos: PChar;
  LOpenTokenFoldRangeList: TList;
  LOpenTokenSkipFoldRangeList: TList;
  LPBookmarkText: PChar;
  LPBookmarkText2: PChar;

  function IsValidChar(Character: PChar): Boolean;
  begin
    Result := Character^.IsLower or Character^.IsUpper or Character^.IsNumber or
      CharInSet(Character^, BCEDITOR_CODE_FOLDING_VALID_CHARACTERS);
  end;

  function IsWholeWord(FirstChar, LastChar: PChar): Boolean;
  begin
    Result := not IsValidChar(FirstChar) and not IsValidChar(LastChar);
  end;

  function SkipEmptySpace(): Boolean;
  begin
    while ((LLinePos <= LLineEndPos) and (LLinePos^ < BCEDITOR_EXCLAMATION_MARK)) do
      Inc(LLinePos);
    Result := LLinePos > LLineEndPos;
  end;

  function CountCharsBefore(APText: PChar; const Character: Char): Integer;
  var
    LPText: PChar;
  begin
    Result := 0;
    LPText := APText - 1;
    while LPText^ = Character do
    begin
      Inc(Result);
      Dec(LPText);
    end;
  end;

  function OddCountOfStringEscapeChars(APText: PChar): Boolean;
  begin
    Result := False;
    if LCurrentCodeFoldingRegion.StringEscapeChar <> BCEDITOR_NONE_CHAR then
      Result := Odd(CountCharsBefore(APText, LCurrentCodeFoldingRegion.StringEscapeChar));
  end;

  function EscapeChar(APText: PChar): Boolean;
  begin
    Result := False;
    if LCurrentCodeFoldingRegion.EscapeChar <> BCEDITOR_NONE_CHAR then
      Result := APText^ = LCurrentCodeFoldingRegion.EscapeChar;
  end;

  function IsNextSkipChar(APText: PChar; ASkipRegionItem: TBCEditorCodeFolding.TSkipRegions.TItem): Boolean;
  begin
    Result := False;
    if ASkipRegionItem.SkipIfNextCharIsNot <> BCEDITOR_NONE_CHAR then
      Result := APText^ = ASkipRegionItem.SkipIfNextCharIsNot;
  end;

  function SkipRegionsClose: Boolean;
  var
    LSkipRegionItem: TBCEditorCodeFolding.TSkipRegions.TItem;
    LTokenEndPos: PChar;
    LTokenPos: PChar;
    LTokenText: string;
  begin
    Result := False;
    { Note! Check Close before Open because close and open keys might be same. }
    if ((LOpenTokenSkipFoldRangeList.Count > 0)
      and CharInSet(LLinePos^, FHighlighter.SkipCloseKeyChars)
      and not OddCountOfStringEscapeChars(LLinePos)) then
    begin
      LSkipRegionItem := LOpenTokenSkipFoldRangeList.Last;
      if (LSkipRegionItem.CloseToken <> LSkipRegionItem.CloseToken) then
      begin
        LTokenText := LSkipRegionItem.CloseToken;
        LTokenPos := @LTokenText[1];
        LTokenEndPos := @LTokenText[Length(LTokenText)];
        LPBookmarkText := LLinePos;
        { Check if the close keyword found }
        while ((LLinePos <= LLineEndPos) and (LTokenPos <= LTokenEndPos)
          and ((LLinePos^ = LTokenPos^) or (LSkipRegionItem.SkipEmptyChars and (LLinePos^ < BCEDITOR_EXCLAMATION_MARK)))) do
        begin
          if (not CharInSet(LLinePos^, [BCEDITOR_NONE_CHAR, BCEDITOR_SPACE_CHAR, BCEDITOR_TAB_CHAR])) then
            Inc(LTokenPos);
          Inc(LLinePos);
        end;
        if (LTokenPos >= LTokenEndPos) then { If found, pop skip region from the stack }
        begin
          LOpenTokenSkipFoldRangeList.Delete(LOpenTokenSkipFoldRangeList.Count - 1);
          Result := True;
        end
        else
          LLinePos := LPBookmarkText; { Skip region close not found, return pointer back }
      end;
    end;
  end;

  function SkipRegionsOpen: Boolean;
  var
    LCount: Integer;
    LIndex: Integer;
    LSkipRegionItem: TBCEditorCodeFolding.TSkipRegions.TItem;
    LTokenEndPos: PChar;
    LTokenPos: PChar;
    LTokenText: string;
  begin
    Result := False;

    if CharInSet(LLinePos^, FHighlighter.SkipOpenKeyChars) then
      if LOpenTokenSkipFoldRangeList.Count = 0 then
      begin
        LCount := LCurrentCodeFoldingRegion.SkipRegions.Count - 1;
        for LIndex := 0 to LCount do
        begin
          LSkipRegionItem := LCurrentCodeFoldingRegion.SkipRegions[LIndex];
          if ((LLinePos^ = LSkipRegionItem.OpenToken[1])
            and not OddCountOfStringEscapeChars(LLinePos)
            and not IsNextSkipChar(LLinePos + Length(LSkipRegionItem.OpenToken), LSkipRegionItem)) then
          begin
            LTokenText := LSkipRegionItem.OpenToken;
            if (LTokenText <> '') then
            begin
              LTokenPos := @LTokenText[1];
              LTokenEndPos := @LTokenText[Length(LTokenText)];
              LPBookmarkText := LLinePos;
              { Check, if the open keyword found }
              while ((LLinePos <= LLineEndPos) and (LTokenPos <= LTokenEndPos)
                and ((LLinePos^ = LTokenPos^) or (LSkipRegionItem.SkipEmptyChars and (LLinePos^ < BCEDITOR_EXCLAMATION_MARK)))) do
              begin
                if (not LSkipRegionItem.SkipEmptyChars
                  or LSkipRegionItem.SkipEmptyChars and not CharInSet(LLinePos^, [BCEDITOR_NONE_CHAR, BCEDITOR_SPACE_CHAR, BCEDITOR_TAB_CHAR])) then
                  Inc(LTokenPos);
                Inc(LLinePos);
              end;

              if (LTokenPos > LTokenEndPos) then { If found, skip single line comment or push skip region into stack }
              begin
                if LSkipRegionItem.RegionType = ritSingleLineString then
                begin
                  LTokenText := LSkipRegionItem.CloseToken;
                  if (LTokenText <> '') then
                  begin
                    LTokenPos := @LTokenText[1];
                    LTokenEndPos := @LTokenText[Length(LTokenText)];
                    while ((LLinePos <= LLineEndPos) and (LTokenPos <= LTokenEndPos)
                      and ((LLinePos^ <> LTokenPos^) or OddCountOfStringEscapeChars(LLinePos))) do
                      Inc(LLinePos);
                    Inc(LLinePos);
                  end;
                end
                else if LSkipRegionItem.RegionType = ritSingleLineComment then
                  { Single line comment skip until next line }
                  Exit(True)
                else
                  LOpenTokenSkipFoldRangeList.Add(LSkipRegionItem);
                Dec(LLinePos); { The end of the while loop will increase }
                Break;
              end
              else
                LLinePos := LPBookmarkText; { Skip region open not found, return pointer back }
            end;
          end;
        end;
      end;
  end;

  procedure RegionItemsClose;

    procedure SetCodeFoldingRangeToLine(ACodeFoldingRange: TBCEditorCodeFolding.TRanges.TRange);
    var
      LIndex: Integer;
    begin
      if ACodeFoldingRange.RegionItem.TokenEndIsPreviousLine then
      begin
        LIndex := LLine;
        while (LIndex > 0) and (Lines.Lines[LIndex - 1].Text = '') do
          Dec(LIndex);
        ACodeFoldingRange.LastLine := LIndex
      end
      else
        ACodeFoldingRange.LastLine := LLine;
    end;

  var
    LCodeFoldingRange: TBCEditorCodeFolding.TRanges.TRange;
    LCodeFoldingRangeLast: TBCEditorCodeFolding.TRanges.TRange;
    LIndex: Integer;
    LIndexDecrease: Integer;
    LItemIndex: Integer;
    LTokenEndPos: PChar;
    LTokenPos: PChar;
    LTokenText: string;
  begin
    if ((LOpenTokenSkipFoldRangeList.Count = 0) 
      and (LOpenTokenFoldRangeList.Count > 0)
      and CharInSet(CaseUpper(LLinePos^), FHighlighter.FoldCloseKeyChars)) then
    begin
      LIndexDecrease := 1;
      {$if defined(VER250)}
      LCodeFoldingRange := nil;
      {$endif}
      repeat
        LIndex := LOpenTokenFoldRangeList.Count - LIndexDecrease;
        if LIndex < 0 then
          Break;
        LCodeFoldingRange := LOpenTokenFoldRangeList.Items[LIndex];

        if LCodeFoldingRange.RegionItem.CloseTokenBeginningOfLine and not LBeginningOfLine then
          Exit;
        LTokenText := LCodeFoldingRange.RegionItem.CloseToken;
        if (LTokenText <> '') then
        begin
          LTokenPos := @LTokenText[1];
          LTokenEndPos := @LTokenText[Length(LTokenText)];
          LPBookmarkText := LLinePos;
          { Check if the close keyword found }
          while ((LLinePos <= LLineEndPos) and (LTokenPos <= LTokenEndPos)
            and (CaseUpper(LLinePos^) = LTokenPos^)) do
          begin
            Inc(LLinePos);
            Inc(LTokenPos);
          end;

          if (LTokenPos > LTokenEndPos) then { If found, pop skip region from the stack }
          begin
            if not LCodeFoldingRange.RegionItem.BreakCharFollows or
              LCodeFoldingRange.RegionItem.BreakCharFollows and IsWholeWord(LPBookmarkText - 1, LLinePos) then
            begin
              LOpenTokenFoldRangeList.Remove(LCodeFoldingRange);
              Dec(LFoldCount);

              if ((LCodeFoldingRange.RegionItem.BreakIfNotFoundBeforeNextRegion <> '')
                and not LCodeFoldingRange.IsExtraTokenFound) then
              begin
                LLinePos := LPBookmarkText;
                Exit;
              end;
              SetCodeFoldingRangeToLine(LCodeFoldingRange);
              { Check if the code folding ranges have shared close }
              if LOpenTokenFoldRangeList.Count > 0 then
                for LItemIndex := LOpenTokenFoldRangeList.Count - 1 downto 0 do
                begin
                  LCodeFoldingRangeLast := LOpenTokenFoldRangeList.Items[LItemIndex];
                  if Assigned(LCodeFoldingRangeLast.RegionItem) and LCodeFoldingRangeLast.RegionItem.SharedClose then
                  begin
                    LTokenText := LCodeFoldingRangeLast.RegionItem.CloseToken;
                    LTokenPos := @LTokenText[1];
                    LTokenEndPos := @LTokenText[Length(LTokenText)];
                    LLinePos := LPBookmarkText;
                    while ((LLinePos <= LLineEndPos) and (LTokenPos <= LTokenEndPos)
                      and (CaseUpper(LLinePos^) = LTokenPos^)) do
                    begin
                      Inc(LLinePos);
                      Inc(LTokenPos);
                    end;
                    if (LTokenPos > LTokenEndPos) then
                    begin
                      SetCodeFoldingRangeToLine(LCodeFoldingRangeLast);
                      LOpenTokenFoldRangeList.Remove(LCodeFoldingRangeLast);
                      Dec(LFoldCount);
                    end;
                  end;
                end;
              LLinePos := LPBookmarkText; { Go back where we were }
            end
            else
              LLinePos := LPBookmarkText; { Region close not found, return pointer back }
          end
          else
            LLinePos := LPBookmarkText; { Region close not found, return pointer back }
        end;

        Inc(LIndexDecrease);
      until Assigned(LCodeFoldingRange) and ((LCodeFoldingRange.RegionItem.BreakIfNotFoundBeforeNextRegion = '') or
        (LOpenTokenFoldRangeList.Count - LIndexDecrease < 0));
    end;
  end;

  function RegionItemsOpen: Boolean;
  var
    LArrayIndex: Integer;
    LCodeFoldingRange: TBCEditorCodeFolding.TRanges.TRange;
    LIndex: Integer;
    LLineTempPos: PChar;
    LRegionItem: TBCEditorCodeFoldingRegionItem;
    LSkipIfFoundAfterOpenToken: Boolean;
    LTokenEndPos: PChar;
    LTokenFollowEndPos: PChar;
    LTokenFollowPos: PChar;
    LTokenFollowText: string;
    LTokenPos: PChar;
    LTokenText: string;
  begin
    Result := False;

    if LOpenTokenSkipFoldRangeList.Count <> 0 then
      Exit;
    if CharInSet(CaseUpper(LLinePos^), FHighlighter.FoldOpenKeyChars) then
    begin
      LCodeFoldingRange := nil;
      if LOpenTokenFoldRangeList.Count > 0 then
        LCodeFoldingRange := LOpenTokenFoldRangeList.Last;
      if Assigned(LCodeFoldingRange) and LCodeFoldingRange.RegionItem.NoSubs then
        Exit;

      for LIndex := 0 to LCurrentCodeFoldingRegion.Count - 1 do
      begin
        LRegionItem := LCurrentCodeFoldingRegion[LIndex];
        if (LRegionItem.OpenTokenBeginningOfLine and LBeginningOfLine) or (not LRegionItem.OpenTokenBeginningOfLine) then
        begin
          { Check if extra token found }
          if Assigned(LCodeFoldingRange) then
          begin
            if LCodeFoldingRange.RegionItem.BreakIfNotFoundBeforeNextRegion <> '' then
              if (LLinePos^ = LCodeFoldingRange.RegionItem.BreakIfNotFoundBeforeNextRegion[1]) then { If first character match }
              begin
                LTokenText := LCodeFoldingRange.RegionItem.BreakIfNotFoundBeforeNextRegion;
                if (LTokenText <> '') then
                begin
                  LTokenPos := @LTokenText[1];
                  LTokenEndPos := @LTokenText[Length(LTokenText)];
                  LPBookmarkText := LLinePos;
                  { Check if open keyword found }
                  while ((LLinePos <= LLineEndPos) and (LTokenPos <= LTokenEndPos)
                    and ((CaseUpper(LLinePos^) = LTokenPos^)
                      or CharInSet(LLinePos^, [BCEDITOR_NONE_CHAR, BCEDITOR_SPACE_CHAR, BCEDITOR_TAB_CHAR]))) do
                  begin
                    if (CharInSet(LTokenPos^, [BCEDITOR_NONE_CHAR, BCEDITOR_SPACE_CHAR, BCEDITOR_TAB_CHAR])
                      or not CharInSet(LLinePos^, [BCEDITOR_NONE_CHAR, BCEDITOR_SPACE_CHAR, BCEDITOR_TAB_CHAR])) then
                      Inc(LTokenPos);
                    Inc(LLinePos);
                  end;
                  if (LTokenPos > LTokenEndPos) then
                  begin
                    LCodeFoldingRange.IsExtraTokenFound := True;
                    Continue;
                  end
                  else
                    LLinePos := LPBookmarkText; { Region not found, return pointer back }
                end;
              end;
          end;
          { First word after newline }
          if (CaseUpper(LLinePos^) = LRegionItem.OpenToken[1]) then { If first character match }
          begin
            LTokenText := LRegionItem.OpenToken;
            if (LTokenText <> '') then
            begin
              LTokenPos := @LTokenText[1];
              LTokenEndPos := @LTokenText[Length(LTokenText)];
              LPBookmarkText := LLinePos;
              { Check if open keyword found }
              while ((LLinePos <= LLineEndPos) and (LTokenPos <= LTokenEndPos)
                and (CaseUpper(LLinePos^) = LTokenPos^)) do
              begin
                Inc(LLinePos);
                Inc(LTokenPos);
              end;

              if ((LRegionItem.OpenTokenCanBeFollowedBy <> '')
                and (CaseUpper(LLinePos^) = LRegionItem.OpenTokenCanBeFollowedBy[1])) then
              begin
                LLineTempPos := LLinePos;
                LTokenFollowText := LRegionItem.OpenTokenCanBeFollowedBy;
                LTokenFollowPos := @LTokenFollowText[1];
                LTokenFollowEndPos := @LTokenFollowText[Length(LTokenFollowText)];
                while (LLineTempPos <= LLineEndPos) and (LTokenFollowPos <= LTokenFollowEndPos)
                  and (CaseUpper(LLineTempPos^) = LTokenFollowPos^) do
                begin
                  Inc(LLineTempPos);
                  Inc(LTokenFollowPos);
                end;
                if (LTokenFollowPos > LTokenFollowEndPos) then
                  LLinePos := LLineTempPos;
              end;

              if (LTokenPos > LTokenEndPos) then
              begin
                if ((not LRegionItem.BreakCharFollows or LRegionItem.BreakCharFollows and IsWholeWord(LPBookmarkText - 1, LLinePos))
                  and not EscapeChar(LPBookmarkText - 1)) then { Not interested in partial hits }
                begin
                  { Check if special rule found }
                  LSkipIfFoundAfterOpenToken := False;
                  if (LRegionItem.SkipIfFoundAfterOpenTokenArrayCount > 0) then
                    while (LLinePos <= LLineEndPos) do
                    begin
                      for LArrayIndex := 0 to LRegionItem.SkipIfFoundAfterOpenTokenArrayCount - 1 do
                      begin
                        LTokenText := LRegionItem.SkipIfFoundAfterOpenTokenArray[LArrayIndex];
                        LTokenPos := @LTokenText[1];
                        LTokenEndPos := @LTokenText[Length(LTokenText)];
                        LPBookmarkText2 := LLinePos;
                        if (CaseUpper(LLinePos^) = LTokenPos^) then { If first character match }
                        begin
                          while ((LLinePos <= LLineEndPos) and (LTokenPos <= LTokenEndPos)
                            and (CaseUpper(LLinePos^) = LTokenPos^)) do
                          begin
                            Inc(LLinePos);
                            Inc(LTokenPos);
                          end;
                          if (LTokenPos > LTokenEndPos) then
                          begin
                            LSkipIfFoundAfterOpenToken := True;
                            Break; { for }
                          end
                          else
                            LLinePos := LPBookmarkText2; { Region not found, return pointer back }
                        end;
                      end;
                      if LSkipIfFoundAfterOpenToken then
                        Break; { while }
                      Inc(LLinePos);
                    end;
                  if LSkipIfFoundAfterOpenToken then
                  begin
                    LLinePos := LPBookmarkText; { Skip found, return pointer back }
                    Continue;
                  end;

                  if Assigned(LCodeFoldingRange) and (LCodeFoldingRange.RegionItem.BreakIfNotFoundBeforeNextRegion <> '')
                    and not LCodeFoldingRange.IsExtraTokenFound then
                  begin
                    LOpenTokenFoldRangeList.Remove(LCodeFoldingRange);
                    Dec(LFoldCount);
                  end;

                  if LOpenTokenFoldRangeList.Count > 0 then
                    LFoldRanges := TBCEditorCodeFolding.TRanges.TRange(LOpenTokenFoldRangeList.Last).SubCodeFoldingRanges
                  else
                    LFoldRanges := FAllCodeFoldingRanges;

                  LCodeFoldingRange := LFoldRanges.Add(FAllCodeFoldingRanges, LLine, GetLineIndentLevel(LLine),
                    LFoldCount, LRegionItem, LLine);
                  { Open keyword found }
                  LOpenTokenFoldRangeList.Add(LCodeFoldingRange);
                  Inc(LFoldCount);
                  Dec(LLinePos); { The end of the while loop will increase }
                  Result := LRegionItem.OpenTokenBreaksLine;
                  Break;
                end
                else
                  LLinePos := LPBookmarkText; { Region not found, return pointer back }
              end
              else
                LLinePos := LPBookmarkText; { Region not found, return pointer back }
            end;
          end;
        end;
      end;
    end;
  end;

  function MultiHighlighterOpen: Boolean;
  var
    LChar: Char;
    LCodeFoldingRegion: TBCEditorCodeFolding.TRegion;
    LIndex: Integer;
    LTokenEndPos: PChar;
    LTokenPos: PChar;
    LTokenText: string;
  begin
    Result := False;
    if LOpenTokenSkipFoldRangeList.Count <> 0 then
      Exit;
    LChar := CaseUpper(LLinePos^);
    LPBookmarkText := LLinePos;
    for LIndex := 1 to Highlighter.CodeFoldingRangeCount - 1 do { First (0) is the default range }
    begin
      LCodeFoldingRegion := Highlighter.CodeFoldingRegions[LIndex];

      if (LChar = LCodeFoldingRegion.OpenToken[1]) then { If first character match }
      begin
        LTokenText := LCodeFoldingRegion.OpenToken;
        if (LTokenText <> '') then
        begin
          LTokenPos := @LTokenText[1];
          LTokenEndPos := @LTokenText[Length(LTokenText)];
          { Check if open keyword found }
          while ((LLinePos <= LLineEndPos) and (LTokenPos <= LTokenEndPos)
            and (CaseUpper(LLinePos^) = LTokenPos^)) do
          begin
            Inc(LLinePos);
            Inc(LTokenPos);
          end;
          LLinePos := LPBookmarkText; { Return pointer always back }
          if (LTokenPos > LTokenEndPos) then
          begin
            LCodeFoldingRangeIndexList.Add(Pointer(LIndex));
            LCurrentCodeFoldingRegion := Highlighter.CodeFoldingRegions[LIndex];
            Exit(True)
          end;
        end;
      end;
    end;
  end;

  procedure MultiHighlighterClose;
  var
    LChar: Char;
    LCodeFoldingRegion: TBCEditorCodeFolding.TRegion;
    LIndex: Integer;
    LTokenEndPos: PChar;
    LTokenPos: PChar;
    LTokenText: string;
  begin
    if (LOpenTokenSkipFoldRangeList.Count = 0) then
    begin
      LChar := CaseUpper(LLinePos^);
      LPBookmarkText := LLinePos;
      for LIndex := 1 to Highlighter.CodeFoldingRangeCount - 1 do { First (0) is the default range }
      begin
        LCodeFoldingRegion := Highlighter.CodeFoldingRegions[LIndex];

        if (LChar = LCodeFoldingRegion.CloseToken[1]) then { If first character match }
        begin
          LTokenText := LCodeFoldingRegion.CloseToken;
          if (LTokenText <> '') then
          begin
            LTokenPos := @LTokenText[1];
            LTokenEndPos := @LTokenText[Length(LTokenText)];
            { Check if close keyword found }
            while ((LLinePos <= LLineEndPos) and (LTokenPos <= LTokenEndPos)
              and (CaseUpper(LLinePos^) = LTokenEndPos^)) do
            begin
              Inc(LLinePos);
              Inc(LTokenPos);
            end;
            LLinePos := LPBookmarkText; { Return pointer always back }
            if (LTokenPos > LTokenEndPos) then
            begin
              if LCodeFoldingRangeIndexList.Count > 0 then
                LCodeFoldingRangeIndexList.Delete(LCodeFoldingRangeIndexList.Count - 1);
              if LCodeFoldingRangeIndexList.Count > 0 then
                LCurrentCodeFoldingRegion := Highlighter.CodeFoldingRegions[Integer(LCodeFoldingRangeIndexList.Last)]
              else
                LCurrentCodeFoldingRegion := Highlighter.CodeFoldingRegions[DEFAULT_CODE_FOLDING_RANGE_INDEX];
              Exit;
            end
          end;
        end;
      end;
    end;
  end;

  function TagFolds: Boolean;
  var
    LCodeFoldingRegion: TBCEditorCodeFolding.TRegion;
    LIndex: Integer;
  begin
    Result := False;
    for LIndex := 0 to Highlighter.CodeFoldingRangeCount - 1 do
    begin
      LCodeFoldingRegion := Highlighter.CodeFoldingRegions[LIndex];
      if LCodeFoldingRegion.FoldTags then
        Exit(True);
    end;
  end;

  procedure AddTagFolds;
  var
    LAdded: Boolean;
    LCloseToken: string;
    LOpenToken: string;
    LText: string;
    LTextBeginPos: PChar;
    LTextEndPos: PChar;
    LTextPos: PChar;
    LRegionItem: TBCEditorCodeFoldingRegionItem;
    LTokenAttributes: string;
    LTokenAttributesBeginPos: PChar;
    LTokenName: string;
    LRegion: BCEditor.Editor.CodeFolding.TBCEditorCodeFolding.TRegion;
  begin
    LText := Lines.Text;
    LTextBeginPos := @LText[1];
    LTextEndPos := @LText[Length(LText)];
    LTextPos := LTextBeginPos;
    LAdded := False;
    while (LTextPos <= LTextEndPos) do
    begin
      if (LTextPos^ = '<') then
      begin
        Inc(LTextPos);
        if not CharInSet(LTextPos^, ['?', '!', '/']) then
        begin
          LTokenName := '';
          while ((LTextPos <= LTextEndPos) and not CharInSet(LTextPos^, [' ', '>'])) do
          begin
            LTokenName := LTokenName + CaseUpper(LTextPos^);
            Inc(LTextPos);
          end;
          if (LTextPos^ <> ' ') then
            LTokenAttributes := ''
          else
          begin
            LTokenAttributesBeginPos := LTextPos;
            while ((LTextPos <= LTextEndPos) and not CharInSet(LTextPos^, ['/', '>'])) do
            begin
              Inc(LTextPos);
              if (CharInSet(LTextPos^, ['"', ''''])) then
              begin
                Inc(LTextPos);
                while ((LTextPos <= LTextEndPos) and not CharInSet(LTextPos^, ['"', ''''])) do
                  Inc(LTextPos);
              end;
            end;
            LTokenAttributes := UpperCase(Copy(LText, 1 + LTokenAttributesBeginPos - LTextBeginPos, LTextPos - LTokenAttributesBeginPos));
          end;

          LOpenToken := '<' + LTokenName + LTokenAttributes + LTextPos^;
          LCloseToken := '</' + LTokenName + '>';

          if (LTextPos^ = '>') and (LTextPos^ <> '/') then
          begin
            LRegion := FHighlighter.CodeFoldingRegions[0];
            if not LRegion.Contains(LOpenToken, LCloseToken) then { First (0) is the default range }
            begin
              LRegionItem := LRegion.Add(LOpenToken, LCloseToken);
              LRegionItem.BreakCharFollows := False;
              LAdded := True;
            end;
          end;
        end;
      end;
      Inc(LTextPos);
    end;
    if (LAdded) then
    begin
      FHighlighter.AddKeyChar(ctFoldOpen, '<');
      FHighlighter.AddKeyChar(ctFoldClose, '<');
    end;
  end;

var
  LCodeFoldingRange: TBCEditorCodeFolding.TRanges.TRange;
  LRow: Integer;
  LPreviousLine: Integer;
begin
  LFoldCount := 0;
  LOpenTokenSkipFoldRangeList := TList.Create;
  LOpenTokenFoldRangeList := TList.Create;
  LCodeFoldingRangeIndexList := TList.Create;
  try
    if TagFolds then
      AddTagFolds;

    { Go through the text line by line, character by character }
    LPreviousLine := -1;

    LCodeFoldingRangeIndexList.Add(Pointer(DEFAULT_CODE_FOLDING_RANGE_INDEX));

    if Highlighter.CodeFoldingRangeCount > 0 then
      LCurrentCodeFoldingRegion := Highlighter.CodeFoldingRegions[DEFAULT_CODE_FOLDING_RANGE_INDEX];

    for LRow := 0 to Rows.Count - 1 do
    begin
      LLine := Rows[LRow].Line;
      if (LLine >= Length(FCodeFoldingRangeFromLine)) then
        LCodeFoldingRange := nil
      else
        LCodeFoldingRange := FCodeFoldingRangeFromLine[LLine];
      if Assigned(LCodeFoldingRange) and LCodeFoldingRange.Collapsed then
      begin
        LPreviousLine := LLine;
        Continue;
      end;

      if ((LPreviousLine <> LLine) and (Lines.Lines[LLine].Text <> '')) then
      begin
        LLinePos := @Lines.Lines[LLine].Text[1];
        LLineEndPos := @Lines.Lines[LLine].Text[Length(Lines.Lines[LLine].Text)];
        LBeginningOfLine := True;
        while (LLinePos <= LLineEndPos) do
          if (not SkipEmptySpace()) then
          begin
            if Highlighter.MultiHighlighter then
              if not MultiHighlighterOpen then
                MultiHighlighterClose;

            if SkipRegionsClose then
              Continue; { while LTextPos <= LTextEndPos do }
            if SkipRegionsOpen then
              Break; { Line comment breaks }

            if SkipEmptySpace then
              Break;

            if LOpenTokenSkipFoldRangeList.Count = 0 then
            begin
              RegionItemsClose;
              if RegionItemsOpen then
                Break; { OpenTokenBreaksLine region item option breaks }
            end;

            if (LLinePos <= LLineEndPos) then
              Inc(LLinePos);

            { Skip rest of the word }
            while ((LLinePos <= LLineEndPos)
              and (LLinePos^.IsLower or LLinePos^.IsUpper or LLinePos^.IsNumber)) do
              Inc(LLinePos);

            LBeginningOfLine := False; { Not in the beginning of the line anymore }
          end;
      end;
      LPreviousLine := LLine;
    end;
    { Check the last not empty line }
    LLine := Lines.Count - 1;
    while (LLine >= 0) and (Trim(Lines.Lines[LLine].Text) = '') do
      Dec(LLine);
    if ((LLine >= 0) and (Lines.Lines[LLine].Text <> '')) then
    begin
      LLinePos := @Lines.Lines[LLine].Text[1];
      LLineEndPos := @Lines.Lines[LLine].Text[Length(Lines.Lines[LLine].Text)];
      while LOpenTokenFoldRangeList.Count > 0 do
      begin
        LLastFoldRange := LOpenTokenFoldRangeList.Last;
        if Assigned(LLastFoldRange) then
        begin
          Inc(LLine);
          LLine := Min(LLine, Lines.Count - 1);
          if LLastFoldRange.RegionItem.OpenIsClose then
            LLastFoldRange.LastLine := LLine;
          LOpenTokenFoldRangeList.Remove(LLastFoldRange);
          Dec(LFoldCount);
          RegionItemsClose;
        end;
      end;
    end;
  finally
    LCodeFoldingRangeIndexList.Free;
    LOpenTokenSkipFoldRangeList.Free;
    LOpenTokenFoldRangeList.Free;
  end;
end;

procedure TCustomBCEditor.ScanMatchingPair();
var
  LFoldRange: TBCEditorCodeFolding.TRanges.TRange;
  LLine: Integer;
  LLineText: string;
  LOpenLineText: string;
  LTempPosition: Integer;
begin
  if (FMatchingPair.Enabled and FHighlighter.MatchingPairHighlight
    and not FSyncEdit.Active) then
  begin
    if (Lines.CaretPosition.Line >= Lines.Count) then
      ClearMatchingPair()
    else
    begin
      FCurrentMatchingPair := GetMatchingToken(Lines.CaretPosition, FCurrentMatchingPairMatch);
      if ((FCurrentMatchingPair = trNotFound)
        and (Lines.CaretPosition.Char > 0)
        and (mpoHighlightAfterToken in FMatchingPair.Options)) then
        FCurrentMatchingPair := GetMatchingToken(TextPosition(Lines.CaretPosition.Char - 1, Lines.CaretPosition.Line), FCurrentMatchingPairMatch);

      if (FCurrentMatchingPair = trNotFound) and FHighlighter.MatchingPairHighlight and (cfoHighlightMatchingPair in FCodeFolding.Options) then
      begin
        LFoldRange := CodeFoldingCollapsableFoldRangeForLine(Lines.CaretPosition.Line);
        if not Assigned(LFoldRange) then
          LFoldRange := CodeFoldingFoldRangeForLineTo(Lines.CaretPosition.Line);
        if Assigned(LFoldRange) then
        begin
          if IsKeywordAtPosition(Lines.CaretPosition, nil, mpoHighlightAfterToken in FMatchingPair.Options) then
          begin
            FCurrentMatchingPair := trOpenAndCloseTokenFound;

            LLineText := Lines.ExpandedStrings[LFoldRange.FirstLine];

            LOpenLineText := AnsiUpperCase(LLineText);
            LTempPosition := Pos(LFoldRange.RegionItem.OpenToken, LOpenLineText);

            FCurrentMatchingPairMatch.OpenText := System.Copy(LLineText, LTempPosition,
              Length(LFoldRange.RegionItem.OpenToken + LFoldRange.RegionItem.OpenTokenCanBeFollowedBy));
            FCurrentMatchingPairMatch.OpenPosition := TextPosition(LTempPosition, LFoldRange.FirstLine);

            LLine := LFoldRange.LastLine;
            LLineText := Lines.ExpandedStrings[LLine - 1];
            LTempPosition := Pos(LFoldRange.RegionItem.CloseToken, AnsiUpperCase(LLineText));
            FCurrentMatchingPairMatch.CloseText := System.Copy(LLineText, LTempPosition,
              Length(LFoldRange.RegionItem.CloseToken));
            if not LFoldRange.Collapsed then
              FCurrentMatchingPairMatch.ClosePosition := TextPosition(LTempPosition, LLine - 1)
            else
              FCurrentMatchingPairMatch.ClosePosition :=
                TextPosition(FCurrentMatchingPairMatch.OpenPosition.Char + Length(FCurrentMatchingPairMatch.OpenText) +
                2 { +2 = '..' }, LFoldRange.FirstLine);
          end;
        end;
      end;
    end;
  end;
end;

procedure TCustomBCEditor.ScrollChanged(ASender: TObject);
begin
  UpdateScrollBars;
  Invalidate;
end;

procedure TCustomBCEditor.ScrollTimerHandler(ASender: TObject);
var
  LCursorPoint: TPoint;
  LDisplayPosition: TBCEditorDisplayPosition;
  LRow: Integer;
  LTextCaretPosition: TBCEditorTextPosition;
begin
  BeginUpdate();

  GetCursorPos(LCursorPoint);
  LCursorPoint := ScreenToClient(LCursorPoint);
  LDisplayPosition := ClientToDisplay(LCursorPoint.X, LCursorPoint.Y);
  if FScrollDeltaX <> 0 then
    if GetKeyState(VK_SHIFT) < 0 then
      HorzTextPos := Max(0, HorzTextPos + Sign(FScrollDeltaX) * TextWidth)
    else
      HorzTextPos := Max(0, HorzTextPos + FScrollDeltaX);
  if FScrollDeltaY <> 0 then
  begin
    if GetKeyState(VK_SHIFT) < 0 then
      TopRow := TopRow + FScrollDeltaY * VisibleRows
    else
      TopRow := TopRow + FScrollDeltaY;
    LRow := TopRow;
    if FScrollDeltaY > 0 then
      Inc(LRow, VisibleRows - 1);
    LDisplayPosition.Row := MinMax(LRow, 0, Rows.Count - 1);
  end;

  if not FMouseMoveScrolling then
  begin
    LTextCaretPosition := DisplayToText(LDisplayPosition);
    if (Lines.CaretPosition <> LTextCaretPosition) then
      MoveCaretAndSelection(Lines.SelBeginPosition, LTextCaretPosition, MouseCapture);
  end;

  EndUpdate();
  ComputeScroll(LCursorPoint);
end;

procedure TCustomBCEditor.ScrollToCaret(ACenterVertical: Boolean = False; AScrollAlways: Boolean = False);
var
  LClient: TPoint;
  LDisplayCaretPosition: TBCEditorDisplayPosition;
begin
  LDisplayCaretPosition := DisplayCaretPosition;

  LClient := DisplayToClient(LDisplayCaretPosition);
  if (LClient.X - LeftMarginWidth < 0) then
    HorzTextPos := LClient.X - LeftMarginWidth + HorzTextPos
  else if ((LClient.X - LeftMarginWidth + CharWidth > TextWidth) or AScrollAlways) then
    HorzTextPos := LClient.X - LeftMarginWidth + HorzTextPos - TextWidth + CharWidth + 1;

  if (not ACenterVertical) then
  begin
    if (LDisplayCaretPosition.Row < TopRow) then
      TopRow := LDisplayCaretPosition.Row
    else if ((LDisplayCaretPosition.Row >= TopRow + VisibleRows) or AScrollAlways) then
      TopRow := LDisplayCaretPosition.Row - VisibleRows + 1;
  end
  else
  begin
    if (LDisplayCaretPosition.Row < TopRow) then
      TopRow := Max(0, LDisplayCaretPosition.Row - VisibleRows div 2)
    else if ((LDisplayCaretPosition.Row >= TopRow + VisibleRows div 2) or AScrollAlways) then
      TopRow := LDisplayCaretPosition.Row - VisibleRows div 2 + 1;
  end;
end;

procedure TCustomBCEditor.SearchChanged(AEvent: TBCEditorSearchEvent);
begin
  if (FSearchResults.Count > 0) then
    case (AEvent) of
      seChange:
        FindFirst();
    end;
  FLeftMarginWidth := GetLeftMarginWidth();
  Invalidate;
end;

function TCustomBCEditor.SearchStatus: string;
begin
  Result := FSearchStatus;
end;

procedure TCustomBCEditor.SelectAll;
begin
  Lines.SelBeginPosition := Lines.BOFPosition;
  if (Lines.SelMode = smNormal) then
    Lines.SelEndPosition := Lines.EOFPosition
  else
    Lines.SelEndPosition := TextPosition(Lines.MaxLength, Lines.Count - 1);
  FLastSortOrder := soDesc;
end;

function TCustomBCEditor.SelectedText(): string;
begin
  Result := SelText;
end;

procedure TCustomBCEditor.SelectionChanged(ASender: TObject);
begin
  Invalidate;

  if (Assigned(OnSelectionChanged)) then
    OnSelectionChanged(Self);
end;

procedure TCustomBCEditor.SetActiveLine(const AValue: TBCEditorActiveLine);
begin
  FActiveLine.Assign(AValue);
end;

procedure TCustomBCEditor.SetAlwaysShowCaret(const AValue: Boolean);
begin
  if FAlwaysShowCaret <> AValue then
  begin
    FAlwaysShowCaret := AValue;
    if not (csDestroying in ComponentState) and not Focused then
    begin
      if AValue then
        ResetCaret
      else
      begin
        HideCaret;
        DestroyCaret;
      end;
    end;
  end;
end;

procedure TCustomBCEditor.SetBackgroundColor(const AValue: TColor);
begin
  if FBackgroundColor <> AValue then
  begin
    FBackgroundColor := AValue;
    Color := AValue;
    Invalidate;
  end;
end;

procedure TCustomBCEditor.SetBookmark(const AIndex: Integer; const ATextPosition: TBCEditorTextPosition);
var
  LBookmark: TBCEditorMark;
begin
  if (ATextPosition.Line >= 0) and (ATextPosition.Line <= Max(0, Lines.Count - 1)) then
  begin
    LBookmark := FBookmarkList.Find(AIndex);
    if Assigned(LBookmark) then
      DeleteBookmark(LBookmark);

    LBookmark := TBCEditorMark.Create(Self);
    with LBookmark do
    begin
      Line := ATextPosition.Line;
      Char := ATextPosition.Char + 1;
      ImageIndex := Min(AIndex, 9);
      Index := AIndex;
      Visible := True;
    end;
    FBookmarkList.Add(LBookmark);
    FBookmarkList.Sort(CompareLines);
    if Assigned(FOnAfterBookmarkPlaced) then
      FOnAfterBookmarkPlaced(Self);
  end;
end;

procedure TCustomBCEditor.SetBorderStyle(const AValue: TBorderStyle);
begin
  if FBorderStyle <> AValue then
  begin
    FBorderStyle := AValue;
    RecreateWnd;
  end;
end;

procedure TCustomBCEditor.SetCaretAndSelection(ACaretPosition,
  ASelBeginPosition, ASelEndPosition: TBCEditorTextPosition);
begin
  Lines.BeginUpdate();
  try
    Lines.CaretPosition := ACaretPosition;
    Lines.SelBeginPosition := ASelBeginPosition;
    Lines.SelEndPosition := ASelEndPosition;
  finally
    Lines.EndUpdate();
  end;
end;

procedure TCustomBCEditor.SetCaretPos(AValue: TPoint);
begin
  Lines.CaretPosition := TextPosition(AValue);
end;

procedure TCustomBCEditor.SetCodeFolding(const AValue: TBCEditorCodeFolding);
begin
  FCodeFolding.Assign(AValue);
  if AValue.Visible then
    InitCodeFolding;
end;

procedure TCustomBCEditor.SetDefaultKeyCommands;
begin
  FKeyCommands.ResetDefaults;
end;

procedure TCustomBCEditor.SetDisplayCaretPosition(const ADisplayCaretPosition: TBCEditorDisplayPosition);
begin
  Lines.CaretPosition := DisplayToText(ADisplayCaretPosition);
end;

procedure TCustomBCEditor.SetForegroundColor(const AValue: TColor);
begin
  if FForegroundColor <> AValue then
  begin
    FForegroundColor := AValue;
    Font.Color := AValue;
    Invalidate;
  end;
end;

procedure TCustomBCEditor.SetHideScrollBars(AValue: Boolean);
begin
  if (AValue <> FHideScrollBars) then
  begin
    FHideScrollBars := AValue;
    UpdateScrollBars();
  end;
end;

procedure TCustomBCEditor.SetHideSelection(AValue: Boolean);
begin
  if (AValue <> FHideSelection) then
  begin
    FHideSelection := AValue;
    if (not Focused() and SelectionAvailable) then
      Invalidate();
  end;
end;

procedure TCustomBCEditor.SetKeyCommands(const AValue: TBCEditorKeyCommands);
begin
  if not Assigned(AValue) then
    FKeyCommands.Clear
  else
    FKeyCommands.Assign(AValue);
end;

procedure TCustomBCEditor.SetLeftMargin(const AValue: TBCEditorLeftMargin);
begin
  LeftMargin.Assign(AValue);
end;

procedure TCustomBCEditor.SetHorzTextPos(AValue: Integer);
begin
  if (AValue <> FHorzTextPos) then
  begin
    FHorzTextPos := AValue;

    if (UpdateCount > 0) then
      Include(FState, esScrolled)
    else
    begin
      UpdateScrollBars();
      Invalidate();
    end;
  end;
end;

procedure TCustomBCEditor.SetLineColor(const ALine: Integer; const AForegroundColor, ABackgroundColor: TColor);
begin
  if (ALine >= 0) and (ALine < Lines.Count) then
  begin
    Lines.SetForeground(ALine, AForegroundColor);
    Lines.SetBackground(ALine, ABackgroundColor);
    Invalidate;
  end;
end;

procedure TCustomBCEditor.SetLineColorToDefault(const ALine: Integer);
begin
  if (ALine >= 0) and (ALine < Lines.Count) then
    Invalidate;
end;

procedure TCustomBCEditor.SetMark(const AIndex: Integer; const ATextPosition: TBCEditorTextPosition;
  const AImageIndex: Integer; const AColor: TColor = clNone);
var
  LMark: TBCEditorMark;
begin
  if (ATextPosition.Line >= 0) and (ATextPosition.Line <= Max(0, Lines.Count - 1)) then
  begin
    LMark := FMarkList.Find(AIndex);
    if Assigned(LMark) then
      DeleteMark(LMark);

    LMark := TBCEditorMark.Create(Self);
    with LMark do
    begin
      Line := ATextPosition.Line;
      Char := ATextPosition.Char + 1;
      if AColor <> clNone then
        Background := AColor
      else
        Background := LeftMargin.Colors.MarkDefaultBackground;
      ImageIndex := AImageIndex;
      Index := AIndex;
      Visible := True;
    end;
    if Assigned(FOnBeforeMarkPlaced) then
      FOnBeforeMarkPlaced(Self, LMark);
    FMarkList.Add(LMark);
    FMarkList.Sort(CompareLines);
    if Assigned(FOnAfterMarkPlaced) then
      FOnAfterMarkPlaced(Self);
  end;
end;

procedure TCustomBCEditor.SetModified(const AValue: Boolean);
begin
  Lines.Modified := AValue;
end;

procedure TCustomBCEditor.SetMouseMoveScrollCursors(const AIndex: Integer; const AValue: HCursor);
begin
  if (AIndex >= Low(FMouseMoveScrollCursors)) and (AIndex <= High(FMouseMoveScrollCursors)) then
    FMouseMoveScrollCursors[AIndex] := AValue;
end;

procedure TCustomBCEditor.SetName(const AValue: TComponentName);
var
  LTextToName: Boolean;
begin
  LTextToName := (ComponentState * [csDesigning, csLoading] = [csDesigning]) and (TrimRight(Text) = Name);
  inherited SetName(AValue);
  if LTextToName then
    Text := AValue;
end;

procedure TCustomBCEditor.SetOption(const AOption: TBCEditorOption; const AEnabled: Boolean);
begin
  if AEnabled then
    Include(FOptions, AOption)
  else
    Exclude(FOptions, AOption);
end;

procedure TCustomBCEditor.SetOptions(const AValue: TBCEditorOptions);
begin
  if (AValue <> FOptions) then
  begin
    FOptions := AValue;

    if (eoTrimTrailingLines in Options) then
      Lines.Options := Lines.Options + [loTrimTrailingLines]
    else
      Lines.Options := Lines.Options - [loTrimTrailingLines];
    if (eoTrimTrailingSpaces in Options) then
      Lines.Options := Lines.Options + [loTrimTrailingSpaces]
    else
      Lines.Options := Lines.Options - [loTrimTrailingSpaces];

    if (eoDropFiles in FOptions) <> (eoDropFiles in AValue) and not (csDesigning in ComponentState) and HandleAllocated then
      DragAcceptFiles(Handle, eoDropFiles in FOptions);

    Invalidate;
  end;
end;

procedure TCustomBCEditor.SetReadOnly(const AValue: Boolean);
begin
  Lines.ReadOnly := AValue;
end;

procedure TCustomBCEditor.SetRightMargin(const AValue: TBCEditorRightMargin);
begin
  FRightMargin.Assign(AValue);
end;

procedure TCustomBCEditor.SetScroll(const AValue: TBCEditorScroll);
begin
  FScroll.Assign(AValue);
end;

procedure TCustomBCEditor.SetSearch(const AValue: TBCEditorSearch);
begin
  FSearch.Assign(AValue);
end;

procedure TCustomBCEditor.SetSelectedWord();
begin
  SetWordBlock(Lines.CaretPosition);
end;

procedure TCustomBCEditor.SetSelection(const AValue: TBCEditorSelection);
begin
  FSelection.Assign(AValue);
end;

procedure TCustomBCEditor.SetSelectionBeginPosition(const AValue: TBCEditorTextPosition);
begin
  Lines.SelBeginPosition := AValue;
end;

procedure TCustomBCEditor.SetSelectionEndPosition(const AValue: TBCEditorTextPosition);
begin
  Lines.SelEndPosition := AValue;
end;

procedure TCustomBCEditor.SetSelectionMode(const AValue: TBCEditorSelectionMode);
begin
  Lines.SelMode := AValue;
end;

procedure TCustomBCEditor.SetSelLength(const AValue: Integer);
begin
  Lines.SelEndPosition := Lines.CharIndexToPosition(AValue, Min(Lines.SelBeginPosition, Lines.SelEndPosition));
end;

procedure TCustomBCEditor.SetSelStart(const AValue: Integer);
begin
  Lines.CaretPosition := Lines.CharIndexToPosition(AValue);
end;

procedure TCustomBCEditor.SetSelText(const AValue: string);
var
  LBeginPosition: TBCEditorTextPosition;
  LEndPosition: TBCEditorTextPosition;
begin
  ClearCodeFolding();

  Lines.BeginUpdate();

  LBeginPosition := Min(Lines.SelBeginPosition, Lines.SelEndPosition);

  if (Lines.SelMode = smColumn) then
  begin
    LEndPosition := Lines.SelEndPosition;

    Lines.DeleteText(LBeginPosition, Lines.SelEndPosition);
    Lines.InsertText(LBeginPosition, Lines.SelEndPosition, AValue);
  end
  else if (AValue = '') then
    Lines.DeleteText(LBeginPosition, Max(Lines.SelBeginPosition, Lines.SelEndPosition))
  else
    Lines.ReplaceText(LBeginPosition, Max(Lines.SelBeginPosition, Lines.SelEndPosition), AValue);

  Lines.EndUpdate();

  InitCodeFolding();
end;

procedure TCustomBCEditor.SetSpecialChars(const AValue: TBCEditorSpecialChars);
begin
  SpecialChars.Assign(AValue);
end;

procedure TCustomBCEditor.SetSyncEdit(const AValue: TBCEditorSyncEdit);
begin
  FSyncEdit.Assign(AValue);
end;

procedure TCustomBCEditor.SetTabs(const AValue: TBCEditorTabs);
begin
  FTabs.Assign(AValue);
end;

procedure TCustomBCEditor.SetText(const AValue: string);
begin
  Lines.Text := AValue;
end;

procedure TCustomBCEditor.SetTextEntryMode(const AValue: TBCEditorTextEntryMode);
begin
  if FTextEntryMode <> AValue then
  begin
    FTextEntryMode := AValue;
    if not (csDesigning in ComponentState) then
    begin
      ResetCaret;
      Invalidate();
    end;
  end;
end;

procedure TCustomBCEditor.SetTokenInfo(const AValue: TBCEditorTokenInfo);
begin
  FTokenInfo.Assign(AValue);
end;

procedure TCustomBCEditor.SetTopRow(const AValue: Integer);
var
  LValue: Integer;
begin
  LValue := AValue;
  if (not (soPastEndOfLine in FScroll.Options)) then
    LValue := Min(AValue, Rows.Count - VisibleRows + 1);
  LValue := Max(0, LValue);

  if (LValue <> FTopRow) then
  begin
    FTopRow := LValue;

    if Assigned(OnScroll) then
      OnScroll(Self, sbVertical);

    if (UpdateCount > 0) then
      Include(FState, esScrolled)
    else
    begin
      UpdateScrollBars();
      Invalidate();
    end;
  end;
end;

procedure TCustomBCEditor.SetUndoOption(const AOption: TBCEditorUndoOption; const AEnabled: Boolean);
begin
  case (AOption) of
    uoGroupUndo:
      if (AEnabled) then
        Lines.Options := Lines.Options + [loUndoGrouped]
      else
        Lines.Options := Lines.Options - [loUndoGrouped];
    uoUndoAfterLoad:
      if (AEnabled) then
        Lines.Options := Lines.Options + [loUndoAfterLoad]
      else
        Lines.Options := Lines.Options - [loUndoAfterLoad];
    uoUndoAfterSave:
      if (AEnabled) then
        Lines.Options := Lines.Options + [loUndoAfterSave]
      else
        Lines.Options := Lines.Options - [loUndoAfterSave];
  end;
end;

procedure TCustomBCEditor.SetUndoOptions(AOptions: TBCEditorUndoOptions);
var
  LLinesOptions: TBCEditorLines.TOptions;
begin
  LLinesOptions := Lines.Options;
  LLinesOptions := LLinesOptions - [loUndoGrouped, loUndoAfterLoad, loUndoAfterSave];
  if (uoGroupUndo in AOptions) then
    LLinesOptions := LLinesOptions + [loUndoGrouped];
  if (uoUndoAfterLoad in AOptions) then
    LLinesOptions := LLinesOptions + [loUndoAfterLoad];
  if (uoUndoAfterSave in AOptions) then
    LLinesOptions := LLinesOptions + [loUndoAfterSave];
  Lines.Options := LLinesOptions;
end;

procedure TCustomBCEditor.SetUpdateState(AUpdating: Boolean);
begin
  if (AUpdating) then
  begin
    if (HandleAllocated and Visible) then
      SendMessage(Handle, WM_SETREDRAW, WPARAM(FALSE), 0);
  end
  else
  begin
    {$IFDEF Debug}
    Assert(Lines.UndoList.UpdateCount = 0);
    {$ENDIF}

    if ((State * [esLinesCleared, esLinesDeleted, esLinesInserted] <> [])
      and LeftMargin.LineNumbers.Visible and LeftMargin.Autosize) then
      LeftMargin.AutosizeDigitCount(Lines.Count);

    if (State * [esLinesCleared] <> []) then
      InitCodeFolding();

    if (State * [esCaretMoved, esRowsChanged, esLinesCleared, esLinesDeleted, esLinesInserted, esLinesUpdated] <> []) then
    begin
      if (State * [esFind, esReplace] = []) then
        FSearchResults.Clear();
      ScanMatchingPair();
    end;

    if (State * [esCaretMoved, esRowsChanged, esLinesCleared, esLinesUpdated] <> []) then
      ScrollToCaret();

    if (HandleAllocated) then
    begin
      if (State * [esCaretMoved] <> []) then
        UpdateCaret();
      if ((State * [esRowsChanged, esLinesCleared, esLinesUpdated, esScrolled] <> [])
        or (State * [esCaretMoved] <> []) and ((Lines.CaretPosition.Line >= Lines.Count) or (Lines.CaretPosition.Char > Rows.MaxLength))) then
        UpdateScrollBars();
      if (Visible) then
      begin
        SendMessage(Handle, WM_SETREDRAW, WPARAM(TRUE), 0);
        Invalidate();
      end;
    end;

    if (Assigned(OnChange)
      and (State * [esLinesCleared, esLinesDeleted, esLinesInserted, esLinesUpdated] <> [])
      and not (csReading in ComponentState)
      and (not (lsLoading in Lines.State) or (loUndoAfterLoad in Lines.Options))) then
      OnChange(Self);

    FState := FState - [esCaretMoved, esLinesCleared, esLinesDeleted, esLinesInserted, esLinesUpdated];
  end;
end;

procedure TCustomBCEditor.SetWantReturns(const AValue: Boolean);
begin
  FWantReturns := AValue;
end;

procedure TCustomBCEditor.SetWordBlock(const ATextPosition: TBCEditorTextPosition);
var
  LBeginPosition: TBCEditorTextPosition;
  LEndPosition: TBCEditorTextPosition;
  LLineTextLength: Integer;
begin
  if (ATextPosition.Line < Lines.Count) then
  begin
    LLineTextLength := Length(Lines.Lines[ATextPosition.Line].Text);

    LBeginPosition := TextPosition(Min(ATextPosition.Char, LLineTextLength), ATextPosition.Line);
    while ((LBeginPosition.Char > 0)
      and IsWordBreakChar(Lines.Lines[ATextPosition.Line].Text[1 + LBeginPosition.Char - 1])) do
      Dec(LBeginPosition.Char);
    while ((LBeginPosition.Char > 0)
      and not IsWordBreakChar(Lines.Lines[ATextPosition.Line].Text[1 + LBeginPosition.Char - 1])) do
      Dec(LBeginPosition.Char);
    if ((soExpandRealNumbers in FSelection.Options) and Lines.Lines[ATextPosition.Line].Text[1 + LBeginPosition.Char - 1].IsNumber) then
      while ((LBeginPosition.Char > 0)
        and (Lines.Lines[ATextPosition.Line].Text[1 + LBeginPosition.Char].IsNumber or CharInSet(Lines.Lines[ATextPosition.Line].Text[1 + LBeginPosition.Char - 1], BCEDITOR_REAL_NUMBER_CHARS))) do
        Dec(LBeginPosition.Char);

    LEndPosition := LBeginPosition;
    while ((LEndPosition.Char < LLineTextLength)
      and not IsWordBreakChar(Lines.Lines[ATextPosition.Line].Text[1 + LEndPosition.Char])) do
      Inc(LEndPosition.Char);
    if ((soExpandRealNumbers in FSelection.Options) and Lines.Lines[ATextPosition.Line].Text[1 + LBeginPosition.Char + 1].IsNumber) then
      while ((LEndPosition.Char + 1 < LLineTextLength)
        and (Lines.Lines[ATextPosition.Line].Text[1 + LEndPosition.Char + 1].IsNumber or CharInSet(Lines.Lines[ATextPosition.Line].Text[1 + LEndPosition.Char + 1], BCEDITOR_REAL_NUMBER_CHARS))) do
        Inc(LEndPosition.Char);

    SetCaretAndSelection(LEndPosition, LBeginPosition, LEndPosition);
  end;
end;

procedure TCustomBCEditor.SetWordWrap(const AValue: TBCEditorWordWrap);
begin
  FWordWrap.Assign(AValue);
end;

function TCustomBCEditor.ShortCutPressed: Boolean;
var
  LIndex: Integer;
  LKeyCommand: TBCEditorKeyCommand;
begin
  Result := False;

  for LIndex := 0 to FKeyCommands.Count - 1 do
  begin
    LKeyCommand := FKeyCommands[LIndex];
    if (LKeyCommand.ShiftState = [ssCtrl, ssShift]) or (LKeyCommand.ShiftState = [ssCtrl]) then
      if GetKeyState(LKeyCommand.Key) < 0 then
        Exit(True);
  end;
end;

procedure TCustomBCEditor.ShowCaret;
begin
  if not FCaret.NonBlinking.Enabled and not (esCaretVisible in FState) then
    if Windows.ShowCaret(Handle) then
      Include(FState, esCaretVisible);
end;

procedure TCustomBCEditor.SizeOrFontChanged(const AFontChanged: Boolean);
var
  LTextWidth: Integer;
  LVisibleRows: Integer;
  LWidthChanged: Boolean;
begin
  if (HandleAllocated and (CharWidth <> 0) and (LineHeight > 0)) then
  begin
    BeginUpdate();
    try
      FPaintHelper.SetBaseFont(Font);

      if AFontChanged then
      begin
        if LeftMargin.LineNumbers.Visible then
          LeftMarginChanged(Self);
        ResetCaret;
      end;

      LTextWidth := ClientWidth - LeftMarginWidth;
      LVisibleRows := Max(1, ClientHeight div LineHeight);
      LWidthChanged := LTextWidth <> FTextWidth;

      FillChar(FItalicOffsetCache, SizeOf(FItalicOffsetCache), 0);

      if (LWidthChanged or (LVisibleRows <> VisibleRows)) then
      begin
        FTextWidth := LTextWidth;
        FVisibleRows := LVisibleRows;

        if (WordWrap.Enabled and LWidthChanged) then
        begin
          FRows.Clear();
          FMultiCaretPosition.Row := -1;
        end;

        if cfoAutoWidth in FCodeFolding.Options then
        begin
          FCodeFolding.Width := FPaintHelper.CharHeight;
          if Odd(FCodeFolding.Width) then
            FCodeFolding.Width := FCodeFolding.Width - 1;
        end;
        if cfoAutoPadding in FCodeFolding.Options then
          FCodeFolding.Padding := MulDiv(2, Screen.PixelsPerInch, 96);
      end;

      Include(FState, esScrolled);
    finally
      EndUpdate();
      Invalidate();
    end;
  end;
end;

procedure TCustomBCEditor.Sort(const ASortOrder: TBCEditorSortOrder = soAsc; const ACaseSensitive: Boolean = False);
var
  LBeginLine: Integer;
  LEndLine: Integer;
  LSelectionBeginPosition: TBCEditorTextPosition;
  LSelectionEndPosition: TBCEditorTextPosition;
begin
  if (SelectionAvailable) then
  begin
    LSelectionBeginPosition := SelectionEndPosition;
    LSelectionEndPosition := SelectionEndPosition;

    LBeginLine := LSelectionBeginPosition.Line;
    LEndLine := LSelectionEndPosition.Line;
    if ((LSelectionEndPosition.Char = 0) and (LSelectionEndPosition.Line > LSelectionBeginPosition.Line)) then
      Dec(LEndLine);
  end
  else
  begin
    LBeginLine := 0;
    LEndLine := Lines.Count - 1;
  end;

  Lines.CaseSensitive := ACaseSensitive;
  Lines.SortOrder := ASortOrder;
  Lines.Sort(LBeginLine, LEndLine);

  if (FCodeFolding.Visible) then
    RescanCodeFoldingRanges;
end;

procedure TCustomBCEditor.SpecialCharsChanged(ASender: TObject);
begin
  UpdateScrollBars();
  Invalidate();
end;

function TCustomBCEditor.SplitTextIntoWords(AStringList: TStrings; const ACaseSensitive: Boolean): string;
var
  LSkipCloseKeyChars: TBCEditorCharSet;
  LSkipOpenKeyChars: TBCEditorCharSet;
  LSkipRegionItem: TBCEditorCodeFolding.TSkipRegions.TItem;

  procedure AddKeyChars();
  var
    LIndex: Integer;
    LTokenEndPos: PChar;
    LTokenPos: PChar;
    LTokenText: string;
  begin
    LSkipOpenKeyChars := [];
    LSkipCloseKeyChars := [];

    for LIndex := 0 to FHighlighter.CompletionProposalSkipRegions.Count - 1 do
    begin
      LSkipRegionItem := FHighlighter.CompletionProposalSkipRegions[LIndex];

      LTokenText := LSkipRegionItem.OpenToken;
      if (LTokenText <> '') then
      begin
        LTokenPos := @LTokenText[1];
        LTokenEndPos := @LTokenText[Length(LTokenText)];
        while (LTokenPos <= LTokenEndPos) do
          LSkipOpenKeyChars := LSkipOpenKeyChars + [LTokenPos^];

        LTokenText := LSkipRegionItem.CloseToken;
        LTokenPos := @LTokenText[1];
        LTokenEndPos := @LTokenText[Length(LTokenText)];
        while (LTokenPos <= LTokenEndPos) do
          LSkipCloseKeyChars := LSkipCloseKeyChars + [LTokenPos^];
      end;
    end;
  end;

var
  LIndex: Integer;
  LLine: Integer;
  LLineEndPos: PChar;
  LLinePos: PChar;
  LOpenTokenSkipFoldRangeList: TList;
  LPBookmarkText: PChar;
  LStringList: TStringList;
  LTokenEndPos: PChar;
  LTokenPos: PChar;
  LTokenText: string;
  LWord: string;
  LWordList: string;
begin
  Result := '';
  AddKeyChars;
  AStringList.Clear;
  LOpenTokenSkipFoldRangeList := TList.Create;
  try
    for LLine := 0 to Lines.Count - 1 do
      if (Lines.Lines[LLine].Text <> '') then
      begin
        { Add document words }
        LLinePos := @Lines.Lines[LLine].Text[1];
        LLineEndPos := @Lines.Lines[LLine].Text[Length(Lines.Lines[LLine].Text)];
        LWord := '';
        while (LLinePos <= LLineEndPos) do
        begin
          { Skip regions - Close }
          if (LOpenTokenSkipFoldRangeList.Count > 0) and CharInSet(LLinePos^, LSkipCloseKeyChars) then
          begin
            LTokenText := TBCEditorCodeFolding.TSkipRegions.TItem(LOpenTokenSkipFoldRangeList.Last).CloseToken;
            if (LTokenText <> '') then
            begin
              LTokenPos := @LTokenText[1];
              LTokenEndPos := @LTokenText[Length(LTokenText)];
              LPBookmarkText := LLinePos;
              { Check if the close keyword found }
              while ((LLinePos <= LLineEndPos) and (LTokenPos <= LTokenEndPos)
                and (LLinePos^ = LTokenPos^)) do
              begin
                Inc(LLinePos);
                Inc(LTokenPos);
              end;
              if (LTokenPos > LTokenEndPos) then { If found, pop skip region from the list }
              begin
                LOpenTokenSkipFoldRangeList.Delete(LOpenTokenSkipFoldRangeList.Count - 1);
                Continue;
              end
              else
                LLinePos := LPBookmarkText;
                { Skip region close not found, return pointer back }
            end;
          end;

          { Skip regions - Open }
          if (CharInSet(LLinePos^, LSkipOpenKeyChars)) then
          begin
            for LIndex := 0 to FHighlighter.CompletionProposalSkipRegions.Count - 1 do
            begin
              LSkipRegionItem := FHighlighter.CompletionProposalSkipRegions[LIndex];
              LTokenText := LSkipRegionItem.OpenToken;
              if ((LTokenText <> '') and (LLinePos^ = LTokenText[1])) then { If the first character is a match }
              begin
                LTokenPos := @LTokenText[1];
                LTokenEndPos := @LTokenText[Length(LTokenText)];
                LPBookmarkText := LLinePos;
                { Check if the open keyword found }
                while ((LLinePos <= LLineEndPos) and (LTokenPos <= LTokenEndPos)
                  and (LLinePos^ = LTokenPos^)) do
                begin
                  Inc(LLinePos);
                  Inc(LTokenPos);
                end;
                if (LTokenPos > LTokenEndPos) then { If found, skip single line comment or push skip region into stack }
                begin
                  if LSkipRegionItem.RegionType = ritSingleLineComment then
                    { Single line comment skip until next line }
                    LLinePos := LLineEndPos
                  else
                    LOpenTokenSkipFoldRangeList.Add(LSkipRegionItem);
                  Dec(LLinePos); { The end of the while loop will increase }
                  Break;
                end
                else
                  LLinePos := LPBookmarkText;
                { Skip region open not found, return pointer back }
              end;
            end;
          end;

          if LOpenTokenSkipFoldRangeList.Count = 0 then
          begin
            if ((LWord = '') and (LLinePos^.IsLower or LLinePos^.IsUpper or (LLinePos^ = BCEDITOR_UNDERSCORE))
              or (LWord <> '') and (LLinePos^.IsLower or LLinePos^.IsUpper or LLinePos^.IsNumber or (LLinePos^ = BCEDITOR_UNDERSCORE))) then
              LWord := LWord + LLinePos^
            else
            begin
              if (LWord <> '') and (Length(LWord) > 1) then
                if Pos(LWord + Lines.LineBreak, LWordList) = 0 then { No duplicates }
                  LWordList := LWordList + LWord + Lines.LineBreak;
              LWord := ''
            end;
          end;
          LLinePos := LLineEndPos;
        end;
        if (Length(LWord) > 1) then
          if Pos(LWord + Lines.LineBreak, LWordList) = 0 then { No duplicates }
            LWordList := LWordList + LWord + Lines.LineBreak;
      end;
    LStringList := TStringList.Create();
    LStringList.LineBreak := Lines.LineBreak;
    LStringList.Text := LWordList;
    LStringList.Sort();
    AStringList.Assign(LStringList);
    LStringList.Free();
  finally
    LOpenTokenSkipFoldRangeList.Free;
  end;
end;

procedure TCustomBCEditor.SwapInt(var ALeft: Integer; var ARight: Integer);
var
  LTemp: Integer;
begin
  LTemp := ARight;
  ARight := ALeft;
  ALeft := LTemp;
end;

procedure TCustomBCEditor.SyncEditChanged(ASender: TObject);
var
  LIndex: Integer;
  LIsWordSelected: Boolean;
  LSelectionAvailable: Boolean;
  LTextPosition: TBCEditorTextPosition;
begin
  FSyncEdit.ClearSyncItems;
  if FSyncEdit.Active then
  begin
    WordWrap.Enabled := False;
    LSelectionAvailable := SelectionAvailable;
    LIsWordSelected := IsWordSelected;
    if LSelectionAvailable and LIsWordSelected then
    begin
      Lines.BeginUpdate();
      try
        FSyncEdit.InEditor := True;
        FSyncEdit.EditBeginPosition := Lines.SelBeginPosition;
        FSyncEdit.EditEndPosition := Lines.SelEndPosition;
        FSyncEdit.EditWidth := FSyncEdit.EditEndPosition.Char - FSyncEdit.EditBeginPosition.Char;
        FindWords(SelText, FSyncEdit.SyncItems, seCaseSensitive in FSyncEdit.Options, True);
        LIndex := 0;
        while LIndex < FSyncEdit.SyncItems.Count do
        begin
          LTextPosition := PBCEditorTextPosition(FSyncEdit.SyncItems.Items[LIndex])^;
          if (LTextPosition.Line = FSyncEdit.EditBeginPosition.Line) and
            (LTextPosition.Char = FSyncEdit.EditBeginPosition.Char) or FSyncEdit.BlockSelected and
            not FSyncEdit.IsTextPositionInBlock(LTextPosition) then
          begin
            Dispose(PBCEditorTextPosition(FSyncEdit.SyncItems.Items[LIndex]));
            FSyncEdit.SyncItems.Delete(LIndex);
          end
          else
            Inc(LIndex);
        end;
      finally
        Lines.EndUpdate();
      end;
    end
    else
    if LSelectionAvailable and not LIsWordSelected then
    begin
      FSyncEdit.BlockSelected := True;
      FSyncEdit.BlockBeginPosition := Lines.SelBeginPosition;
      FSyncEdit.BlockEndPosition := Lines.SelEndPosition;
      FSyncEdit.Abort;
      Lines.SelBeginPosition := Lines.CaretPosition;
    end
    else
      FSyncEdit.Abort;
  end
  else
  begin
    FSyncEdit.BlockSelected := False;
    if FSyncEdit.InEditor then
    begin
      FSyncEdit.InEditor := False;
      Lines.EndUpdate;
    end;
  end;
  Invalidate;
end;

procedure TCustomBCEditor.TabsChanged(ASender: TObject);
begin
  Lines.TabWidth := Tabs.Width;
  if (toColumns in Tabs.Options) then
    Lines.Options := Lines.Options + [loColumnTabs]
  else
    Lines.Options := Lines.Options - [loColumnTabs];
  if (WordWrap.Enabled) then
  begin
    FRows.Clear();
    FMultiCaretPosition.Row := -1;
  end;
  Invalidate;
end;

function TCustomBCEditor.TextCaretPosition(): TBCEditorTextPosition;
begin
  Result := Lines.CaretPosition;
end;

function TCustomBCEditor.TextToDisplay(const ATextPosition: TBCEditorTextPosition): TBCEditorDisplayPosition;
var
  LChar: Integer;
  LIsWrapped: Boolean;
  LLineEndPos: PChar;
  LLinePos: PChar;
  LRowsCount: Integer; // Debug 2017-04-24
begin
  if (Lines.Count = 0) then
    Result := DisplayPosition(ATextPosition.Char, ATextPosition.Line)
  else if (ATextPosition.Line >= Lines.Count) then
    Result := DisplayPosition(ATextPosition.Char, Rows.Count + ATextPosition.Line - Rows[Rows.Count - 1].Line - 1)
  else if ((Rows.Count >= 0) and (Lines.Lines[ATextPosition.Line].FirstRow < 0)) then
    // Rows.Count >= 0 is not needed - but GetRows must be called to initialize Lines.FirstRow
  begin
    LRowsCount := Rows.Count;
    FRows.Clear();
    raise ERangeError.Create(SBCEditorLineIsNotVisible + #13#10
      + 'Lines.Count: ' + IntToStr(Lines.Count) + #13#10
      + 'Rows.Count: ' + IntToStr(Rows.Count) + #13#10
      + 'LRowCount: ' + IntToStr(LRowsCount) + #13#10
      + 'WordWrap: ' + BoolToStr(WordWrap.Enabled, True))
  end
  else
  begin
    Result := DisplayPosition(ATextPosition.Char, Lines.Lines[ATextPosition.Line].FirstRow);

    LIsWrapped := False;

    if WordWrap.Enabled then
    begin
      LChar := 1;

      if ((Lines.Lines[ATextPosition.Line].Text <> '') and (Result.Column < Length(Lines.Lines[ATextPosition.Line].Text))) then
      begin
        LLinePos := @Lines.Lines[ATextPosition.Line].Text[1];
        LLineEndPos := @Lines.Lines[ATextPosition.Line].Text[Length(Lines.Lines[ATextPosition.Line].Text)];
        while ((LLinePos <= LLineEndPos) and (LChar <= Result.Column)) do
        begin
          if (LLinePos^ = BCEDITOR_TAB_CHAR) then
            Inc(Result.Column, FTabs.Width - 1);
          Inc(LChar);
          Inc(LLinePos);
        end;
      end;

      while ((Result.Row < Rows.Count)
        and ((Result.Column > Rows[Result.Row].Length)
          or not (rfLastRowOfLine in Rows[Result.Row].Flags) and (Result.Column = Rows[Result.Row].Length))) do
      begin
        LIsWrapped := True;
        Dec(Result.Column, Rows[Result.Row].Length);
        Inc(Result.Row);
      end;
    end;

    if (not LIsWrapped and (ATextPosition.Line < Lines.Count)) then
      if (Lines.Lines[ATextPosition.Line].Text = '') then
        Result.Column := ATextPosition.Char
      else
      begin
        LLinePos := @Lines.Lines[ATextPosition.Line].Text[1];
        LLineEndPos := @Lines.Lines[ATextPosition.Line].Text[Length(Lines.Lines[ATextPosition.Line].Text)];
        Result.Column := 0;
        LChar := 0;
        while (LChar < ATextPosition.Char) do
        begin
          if (LLinePos <= LLineEndPos) then
          begin
            if (LLinePos^ <> BCEDITOR_TAB_CHAR) then
              Inc(Result.Column)
            else if (toColumns in FTabs.Options) then
              Inc(Result.Column, FTabs.Width - Result.Column mod FTabs.Width)
            else
              Inc(Result.Column, FTabs.Width);
            Inc(LLinePos);
          end
          else
            Inc(Result.Column);
          Inc(LChar);
        end;
      end;
  end;
end;

procedure TCustomBCEditor.ToggleBookmark(const AIndex: Integer = -1);
begin
  if (AIndex = -1) then
    DoToggleBookmark
  else if (not DeleteBookmark(Lines.CaretPosition.Line, AIndex)) then
    SetBookmark(AIndex, Lines.CaretPosition);
end;

procedure TCustomBCEditor.ToggleSelectedCase(const ACase: TBCEditorCase = cNone);
var
  LCommand: TBCEditorCommand;
  LSelEndPosition: TBCEditorTextPosition;
  LSelBeginPosition: TBCEditorTextPosition;
begin
  if AnsiUpperCase(SelText) <> AnsiUpperCase(FSelectedCaseText) then
  begin
    FSelectedCaseCycle := cUpper;
    FSelectedCaseText := SelText;
  end;
  if ACase <> cNone then
    FSelectedCaseCycle := ACase;

  BeginUpdate();

  LSelBeginPosition := Lines.SelBeginPosition;
  LSelEndPosition := Lines.SelEndPosition;
  LCommand := ecNone;
  case FSelectedCaseCycle of
    cUpper: { UPPERCASE }
      if Lines.SelMode = smColumn then
        LCommand := ecUpperCaseBlock
      else
        LCommand := ecUpperCase;
    cLower: { lowercase }
      if Lines.SelMode = smColumn then
        LCommand := ecLowerCaseBlock
      else
        LCommand := ecLowerCase;
    cAlternating: { aLtErNaTiNg cAsE }
      if Lines.SelMode = smColumn then
        LCommand := ecAlternatingCaseBlock
      else
        LCommand := ecAlternatingCase;
    cSentence: { Sentence case }
      LCommand := ecSentenceCase;
    cTitle: { Title Case }
      LCommand := ecTitleCase;
    cOriginal: { Original text }
      SelText := FSelectedCaseText;
  end;
  if FSelectedCaseCycle <> cOriginal then
    CommandProcessor(LCommand, BCEDITOR_NONE_CHAR, nil);
  Lines.SelBeginPosition := LSelBeginPosition;
  Lines.SelEndPosition := LSelEndPosition;

  EndUpdate();

  Inc(FSelectedCaseCycle);
  if FSelectedCaseCycle > cOriginal then
    FSelectedCaseCycle := cUpper;
end;

function TCustomBCEditor.TranslateKeyCode(const ACode: Word; const AShift: TShiftState; var AData: Pointer): TBCEditorCommand;
var
  LIndex: Integer;
begin
  LIndex := KeyCommands.FindKeycodes(FLastKey, FLastShiftState, ACode, AShift);
  if LIndex >= 0 then
    Result := KeyCommands[LIndex].Command
  else
  begin
    LIndex := KeyCommands.FindKeycode(ACode, AShift);
    if LIndex >= 0 then
      Result := KeyCommands[LIndex].Command
    else
      Result := ecNone;
  end;
  if (Result = ecNone) and (ACode >= VK_ACCEPT) and (ACode <= VK_SCROLL) then
  begin
    FLastKey := ACode;
    FLastShiftState := AShift;
  end
  else
  begin
    FLastKey := 0;
    FLastShiftState := [];
  end;
end;

procedure TCustomBCEditor.UMFreeCompletionProposalPopupWindow(var AMessage: TMessage);
begin
  if (Assigned(FCompletionProposalPopupWindow)) then
  begin
    FCompletionProposalPopupWindow.Free;
    FCompletionProposalPopupWindow := nil;
    AlwaysShowCaret := FAlwaysShowCaretBeforePopup;
  end;
end;

procedure TCustomBCEditor.Undo();
begin
  Lines.Undo();
end;

procedure TCustomBCEditor.UnhookEditorLines;
var
  LOldWrap: Boolean;
begin
  Assert(not Assigned(FChainedEditor));
  if Lines = FOriginalLines then
    Exit;

  LOldWrap := WordWrap.Enabled;
  UpdateWordWrap(False);

  with Lines do
  begin
    OnCleared := FOnChainLinesCleared;
    OnDeleted := FOnChainLinesDeleted;
    OnInserted := FOnChainLinesInserted;
    OnUpdated := FOnChainLinesUpdated;
  end;

  FOnChainLinesCleared := nil;
  FOnChainLinesDeleted := nil;
  FOnChainLinesInserted := nil;
  FOnChainLinesUpdated := nil;

  FLines := FOriginalLines;
  LinesHookChanged;

  UpdateWordWrap(LOldWrap);
end;

procedure TCustomBCEditor.UnregisterCommandHandler(AHookedCommandEvent: TBCEditorHookedCommandEvent);
var
  LIndex: Integer;
begin
  if not Assigned(AHookedCommandEvent) then
    Exit;
  LIndex := FindHookedCommandEvent(AHookedCommandEvent);
  if LIndex > -1 then
    FHookedCommandHandlers.Delete(LIndex)
end;

function TCustomBCEditor.UpdateAction(Action: TBasicAction): Boolean;
begin
  Result := Focused;

  if (Result) then
    if Action is TEditCut then
      TEditCut(Action).Enabled := not ReadOnly and SelectionAvailable
    else if Action is TEditCopy then
      TEditCopy(Action).Enabled := SelectionAvailable
    else if Action is TEditPaste then
      TEditPaste(Action).Enabled := CanPaste
    else if Action is TEditDelete then
      TEditDelete(Action).Enabled := not ReadOnly and SelectionAvailable
    else if Action is TEditSelectAll then
      TEditSelectAll(Action).Enabled := (Lines.Count > 0)
    else if Action is TEditUndo then
      TEditUndo(Action).Enabled := not ReadOnly and Lines.CanUndo
    else if Action is TSearchFindNext then
      // must be before TSearchFind, since TSearchFindNext is TSearchFind too
      TSearchFindNext(Action).Enabled := Search.Pattern <> ''
    else if Action is TSearchReplace then
      // must be before TSearchFind, since TSearchReplace is TSearchFind too
      TSearchReplace(Action).Enabled := (Lines.Count > 0)
    else if Action is TSearchFind then
      TSearchFind(Action).Enabled := (Lines.Count > 0)
    else
      Result := inherited;
end;

procedure TCustomBCEditor.UpdateCaret();
var
  LCaretPoint: TPoint;
  LCaretStyle: TBCEditorCaretStyle;
  LCompositionForm: TCompositionForm;
  LRect: TRect;
begin
  if (FUpdateCount = 0) then
  begin
    if FTextEntryMode = temInsert then
      LCaretStyle := FCaret.Styles.Insert
    else
      LCaretStyle := FCaret.Styles.Overwrite;

    LCaretPoint := DisplayToClient(DisplayCaretPosition);
    LCaretPoint.Offset(FCaretOffset);
    if (LCaretStyle in [csHorizontalLine, csThinHorizontalLine, csHalfBlock, csBlock]) then
      Inc(LCaretPoint.X);

    LRect := ClientRect;
    Inc(LRect.Left, LeftMargin.Width + FCodeFolding.GetWidth);

    Windows.SetCaretPos(LCaretPoint.X, LCaretPoint.Y);
    if (LRect.Contains(LCaretPoint) and (Focused() or AlwaysShowCaret)) then
      ShowCaret
    else
      HideCaret;

    LCompositionForm.dwStyle := CFS_POINT;
    LCompositionForm.ptCurrentPos := LCaretPoint;
    ImmSetCompositionWindow(ImmGetContext(Handle), @LCompositionForm);

    if Assigned(FOnCaretChanged) then
      FOnCaretChanged(Self, Lines.CaretPosition.Char + 1, Lines.CaretPosition.Line + LeftMargin.LineNumbers.StartFrom);
  end;
end;

procedure TCustomBCEditor.UpdateFoldRanges(const ACurrentLine: Integer; const ALineCount: Integer);
var
  LCodeFoldingRange: TBCEditorCodeFolding.TRanges.TRange;
  LIndex: Integer;
begin
  for LIndex := 0 to FAllCodeFoldingRanges.AllCount - 1 do
  begin
    LCodeFoldingRange := FAllCodeFoldingRanges[LIndex];
    if not LCodeFoldingRange.ParentCollapsed then
    begin
      if LCodeFoldingRange.FirstLine > ACurrentLine then
      begin
        LCodeFoldingRange.MoveBy(ALineCount);

        if LCodeFoldingRange.Collapsed then
          UpdateFoldRanges(LCodeFoldingRange.SubCodeFoldingRanges, ALineCount);

        Continue;
      end
      else
      if LCodeFoldingRange.FirstLine = ACurrentLine then
      begin
        LCodeFoldingRange.MoveBy(ALineCount);
        Continue;
      end;

      if not LCodeFoldingRange.Collapsed then
        if LCodeFoldingRange.LastLine >= ACurrentLine then
          LCodeFoldingRange.Widen(ALineCount)
    end;
  end;
end;

procedure TCustomBCEditor.UpdateFoldRanges(AFoldRanges: TBCEditorCodeFolding.TRanges; const ALineCount: Integer);
var
  LCodeFoldingRange: TBCEditorCodeFolding.TRanges.TRange;
  LIndex: Integer;
begin
  if Assigned(AFoldRanges) then
  for LIndex := 0 to AFoldRanges.Count - 1 do
  begin
    LCodeFoldingRange := AFoldRanges[LIndex];
    UpdateFoldRanges(LCodeFoldingRange.SubCodeFoldingRanges, ALineCount);
    LCodeFoldingRange.MoveBy(ALineCount);
  end;
end;

procedure TCustomBCEditor.UpdateMouseCursor;
var
  LCursorIndex: Integer;
  LCursorPoint: TPoint;
  LNewCursor: TCursor;
  LSelectionAvailable: Boolean;
  LTextPosition: TBCEditorTextPosition;
  LWidth: Integer;
begin
  GetCursorPos(LCursorPoint);
  LCursorPoint := ScreenToClient(LCursorPoint);

  Inc(LCursorPoint.X, 4);

  LWidth := 0;
  if FSearch.Map.Align = saLeft then
    Inc(LWidth, FSearch.Map.GetWidth);

  if FMouseMoveScrolling then
  begin
    LCursorIndex := GetMouseMoveScrollCursorIndex;
    if LCursorIndex <> -1 then
      SetCursor(FMouseMoveScrollCursors[LCursorIndex])
    else
      SetCursor(0)
  end
  else
  if (LCursorPoint.X > LWidth) and (LCursorPoint.X < LWidth + LeftMargin.Width + FCodeFolding.GetWidth) then
    SetCursor(Screen.Cursors[LeftMargin.Cursor])
  else
  if FSearch.Map.Visible and ((FSearch.Map.Align = saRight) and
    (LCursorPoint.X > ClientRect.Width - FSearch.Map.GetWidth) or (FSearch.Map.Align = saLeft) and
    (LCursorPoint.X <= FSearch.Map.GetWidth)) then
    SetCursor(Screen.Cursors[FSearch.Map.Cursor])
  else
  begin
    LSelectionAvailable := SelectionAvailable;
    if LSelectionAvailable then
      LTextPosition := TextPosition(ClientToText(LCursorPoint.X, LCursorPoint.Y));
    if (eoDragDropEditing in FOptions) and not MouseCapture and LSelectionAvailable and
      Lines.IsPositionInSelection(LTextPosition) then
      LNewCursor := crArrow
    else
    if FRightMargin.Moving or FRightMargin.MouseOver then
      LNewCursor := FRightMargin.Cursor
    else
    if FMouseOverURI then
      LNewCursor := crHandPoint
    else
    if FCodeFolding.MouseOverHint then
      LNewCursor := FCodeFolding.Hint.Cursor
    else
      LNewCursor := Cursor;
    FKeyboardHandler.ExecuteMouseCursor(Self, LTextPosition, LNewCursor);
    SetCursor(Screen.Cursors[LNewCursor]);
  end;
end;

procedure TCustomBCEditor.UpdateRows(const ALine: Integer);
var
  LDeletedRows: Integer;
  LLine: Integer;
  LRow: Integer;
begin
  if (FRows.Count > 0) then
  begin
    LRow := Lines.Lines[ALine].FirstRow;

    if (LRow >= 0) then
    begin
      LDeletedRows := 0;
      while ((LRow < FRows.Count) and (FRows[LRow].Line = ALine)) do
      begin
        FRows.Delete(LRow);
        Inc(LDeletedRows);
      end;

      if (LDeletedRows > 0) then
        for LLine := ALine + 1 to Lines.Count - 1 do
          Lines.SetFirstRow(LLine, Lines.Lines[LLine].FirstRow - LDeletedRows);

      InsertLineIntoRows(ALine, LRow);
    end;
  end;
end;

procedure TCustomBCEditor.UpdateScrollBars(const AUpdateRows: Boolean = True);
var
  LDisplayCaretPosition: TBCEditorDisplayPosition;
  LHorzScrollInfo: TScrollInfo;
  LVertScrollInfo: TScrollInfo;
begin
  if (HandleAllocated
    and (FUpdateCount = 0)
    and not (esRowsUpdating in State)) then
  begin
    if (AUpdateRows) then
      Rows; // Make sure, Rows is updated

    LDisplayCaretPosition := DisplayCaretPosition;

    LVertScrollInfo.cbSize := SizeOf(ScrollInfo);
    LVertScrollInfo.fMask := SIF_PAGE or SIF_POS or SIF_RANGE;
    LVertScrollInfo.nMin := 0;
    LVertScrollInfo.nMax := Max(LDisplayCaretPosition.Row, FRows.Count - 1);
    LVertScrollInfo.nPage := VisibleRows;
    LVertScrollInfo.nPos := TopRow;
    LVertScrollInfo.nTrackPos := 0;
    SetScrollInfo(Handle, SB_VERT, LVertScrollInfo, TRUE);

    LHorzScrollInfo.cbSize := SizeOf(ScrollInfo);
    LHorzScrollInfo.fMask := SIF_PAGE or SIF_POS or SIF_RANGE;
    LHorzScrollInfo.nMin := 0;
    LHorzScrollInfo.nMax := FRows.MaxWidth - 1;
    if (SpecialChars.Visible) then
      Inc(LHorzScrollInfo.nMax, FLineBreakSignWidth);
    if ((LDisplayCaretPosition.Row >= FRows.Count)
      or (LDisplayCaretPosition.Column > FRows[LDisplayCaretPosition.Row].Length)) then
      if (AUpdateRows or (LDisplayCaretPosition.Row < FRows.Count)) then
      LHorzScrollInfo.nMax := Max(DisplayToClient(LDisplayCaretPosition).X - LeftMarginWidth, LHorzScrollInfo.nMax)
    else
      LHorzScrollInfo.nMax := LeftMarginWidth + LDisplayCaretPosition.Column * CharWidth;
    LHorzScrollInfo.nPage := TextWidth;
    LHorzScrollInfo.nPos := HorzTextPos;
    LHorzScrollInfo.nTrackPos := 0;
    SetScrollInfo(Handle, SB_HORZ, LHorzScrollInfo, TRUE);

    ShowScrollBar(Handle, SB_VERT, not HideScrollBars or (LVertScrollInfo.nMax > INT(LVertScrollInfo.nPage)));
    ShowScrollBar(Handle, SB_HORZ, not HideScrollBars or (LHorzScrollInfo.nMax > INT(LHorzScrollInfo.nPage)));
  end;
end;

procedure TCustomBCEditor.UpdateWordWrap(const AValue: Boolean);
var
  LOldTopRow: Integer;
  LShowCaret: Boolean;
begin
  if (AValue <> WordWrap.Enabled) then
  begin
    Invalidate;
    LShowCaret := CaretInView;
    LOldTopRow := TopRow;
    if AValue then
    begin
      HorzTextPos := 0;
      if FWordWrap.Width = wwwRightMargin then
        FRightMargin.Visible := True;
    end;
    TopRow := LOldTopRow;
    UpdateScrollBars;

    if LShowCaret then
      ScrollToCaret;
  end;
end;

procedure TCustomBCEditor.WMCaptureChanged(var AMessage: TMessage);
begin
  FScrollTimer.Enabled := False;
  inherited;
end;

procedure TCustomBCEditor.WMChar(var AMessage: TWMChar);
begin
  DoKeyPressW(AMessage);
end;

procedure TCustomBCEditor.WMClear(var AMessage: TMessage);
begin
  if not ReadOnly then
    SelText := '';
end;

procedure TCustomBCEditor.WMCopy(var AMessage: TMessage);
begin
  CopyToClipboard;
  AMessage.Result := Ord(True);
end;

procedure TCustomBCEditor.WMCut(var AMessage: TMessage);
begin
  if not ReadOnly then
    CutToClipboard;
  AMessage.Result := Ord(True);
end;

procedure TCustomBCEditor.WMDropFiles(var AMessage: TMessage);
var
  LFileName: array [0 .. MAX_PATH - 1] of Char;
  LFilesList: TStringList;
  LIndex: Integer;
  LNumberDropped: Integer;
  LPoint: TPoint;
begin
  try
    if Assigned(FOnDropFiles) then
    begin
      LFilesList := TStringList.Create;
      try
        LNumberDropped := DragQueryFile(THandle(AMessage.wParam), Cardinal(-1), nil, 0);
        DragQueryPoint(THandle(AMessage.wParam), LPoint);
        for LIndex := 0 to LNumberDropped - 1 do
        begin
          DragQueryFileW(THandle(AMessage.wParam), LIndex, LFileName, SizeOf(LFileName) div 2);
          LFilesList.Add(LFileName)
        end;
        FOnDropFiles(Self, LPoint, LFilesList);
      finally
        LFilesList.Free;
      end;
    end;
  finally
    AMessage.Result := 0;
    DragFinish(THandle(AMessage.wParam));
  end;
end;

procedure TCustomBCEditor.WMEraseBkgnd(var AMessage: TMessage);
begin
  AMessage.Result := 1;
end;

procedure TCustomBCEditor.WMGetDlgCode(var AMessage: TWMGetDlgCode);
begin
  inherited;
  AMessage.Result := AMessage.Result or DLGC_WANTARROWS or DLGC_WANTCHARS;
  if FTabs.WantTabs then
    AMessage.Result := AMessage.Result or DLGC_WANTTAB;
  if FWantReturns then
    AMessage.Result := AMessage.Result or DLGC_WANTALLKEYS;
end;

procedure TCustomBCEditor.WMGetText(var AMessage: TWMGetText);
begin
  StrLCopy(PChar(AMessage.Text), PChar(Text), AMessage.TextMax - 1);
  AMessage.Result := StrLen(PChar(AMessage.Text));
end;

procedure TCustomBCEditor.WMGetTextLength(var AMessage: TWMGetTextLength);
begin
  if (csDocking in ControlState) or (csDestroying in ComponentState) then
    AMessage.Result := 0
  else
    AMessage.Result := Lines.GetTextLength();
end;

procedure TCustomBCEditor.WMHScroll(var AMessage: TWMScroll);
begin
  AMessage.Result := 0;

  FreeTokenInfoPopupWindow;

  inherited;

  case AMessage.ScrollCode of
    SB_LEFT:
      HorzTextPos := 0;
    SB_RIGHT:
      HorzTextPos := Max(0, Rows.MaxWidth - TextWidth);
    SB_LINELEFT:
      HorzTextPos := HorzTextPos - CharWidth;
    SB_LINERIGHT:
      HorzTextPos := HorzTextPos + CharWidth;
    SB_PAGELEFT:
      HorzTextPos := HorzTextPos - TextWidth;
    SB_PAGERIGHT:
      HorzTextPos := HorzTextPos + TextWidth;
    SB_THUMBPOSITION, SB_THUMBTRACK:
      begin
        FIsScrolling := True;
        HorzTextPos := AMessage.Pos;
      end;
    SB_ENDSCROLL:
      FIsScrolling := False;
  end;
  Update;
  if Assigned(OnScroll) then
    OnScroll(Self, sbHorizontal);
end;

procedure TCustomBCEditor.WMIMEChar(var AMessage: TMessage);
begin
  { Do nothing here, the IME string is retrieved in WMIMEComposition
    Handling the WM_IME_CHAR message stops Windows from sending WM_CHAR messages while using the IME }
end;

procedure TCustomBCEditor.WMIMEComposition(var AMessage: TMessage);
var
  LImc: HIMC;
  LImeCount: Integer;
  LPBuffer: PChar;
begin
  if (AMessage.LParam and GCS_RESULTSTR) <> 0 then
  begin
    LImc := ImmGetContext(Handle);
    try
      LImeCount := ImmGetCompositionStringW(LImc, GCS_RESULTSTR, nil, 0);
      { ImeCount is always the size in bytes, also for Unicode }
      GetMem(LPBuffer, LImeCount + SizeOf(Char));
      try
        ImmGetCompositionStringW(LImc, GCS_RESULTSTR, LPBuffer, LImeCount);
        LPBuffer[LImeCount div SizeOf(Char)] := BCEDITOR_NONE_CHAR;
        CommandProcessor(ecImeStr, BCEDITOR_NONE_CHAR, LPBuffer);
      finally
        FreeMem(LPBuffer);
      end;
    finally
      ImmReleaseContext(Handle, LImc);
    end;
  end;
  inherited;
end;

procedure TCustomBCEditor.WMIMENotify(var AMessage: TMessage);
var
  LImc: HIMC;
  LLogFontW: TLogFontW;
begin
  with AMessage do
  begin
    case wParam of
      IMN_SETOPENSTATUS:
        begin
          LImc := ImmGetContext(Handle);
          if LImc <> 0 then
          begin
            GetObjectW(Font.Handle, SizeOf(TLogFontW), @LLogFontW);
            ImmSetCompositionFontW(LImc, @LLogFontW);
            ImmReleaseContext(Handle, LImc);
          end;
        end;
    end;
  end;
  inherited;
end;

procedure TCustomBCEditor.WMMouseHWheel(var AMessage: TWMMouseWheel);
var
  IsNeg: Boolean;
begin
  Inc(FHWheelAccumulator, AMessage.WheelDelta);
  while Abs(FHWheelAccumulator) >= WHEEL_DELTA do
  begin
    IsNeg := FHWheelAccumulator < 0;
    FHWheelAccumulator := Abs(FHWheelAccumulator) - WHEEL_DELTA;
    if IsNeg then
    begin
      if FHWheelAccumulator <> 0 then FHWheelAccumulator := -FHWheelAccumulator;
      HorzTextPos := HorzTextPos - CharWidth;
    end
    else
      HorzTextPos := HorzTextPos + CharWidth;
  end;
end;

procedure TCustomBCEditor.WMNCPaint(var AMessage: TMessage);
var
  LBorderHeight: Integer;
  LBorderWidth: Integer;
  LExStyle: Integer;
  LRect: TRect;
  LTempRgn: HRGN;
begin
  if StyleServices.Enabled then
  begin
    LExStyle := GetWindowLong(Handle, GWL_EXSTYLE);
    if (LExStyle and WS_EX_CLIENTEDGE) <> 0 then
    begin
      GetWindowRect(Handle, LRect);
      LBorderWidth := GetSystemMetrics(SM_CXEDGE);
      LBorderHeight := GetSystemMetrics(SM_CYEDGE);
      InflateRect(LRect, -LBorderWidth, -LBorderHeight);
      LTempRgn := CreateRectRgnIndirect(LRect);
      DefWindowProc(Handle, AMessage.Msg, wParam(LTempRgn), 0);
      DeleteObject(LTempRgn);
    end
    else
      DefaultHandler(AMessage);
  end
  else
    DefaultHandler(AMessage);

  if StyleServices.Enabled then
    StyleServices.PaintBorder(Self, False);
end;

procedure TCustomBCEditor.WMKillFocus(var AMessage: TWMKillFocus);
begin
  inherited;

  if (not AlwaysShowCaret) then
    UpdateCaret();

  if (HideSelection and SelectionAvailable) then
    Invalidate();
end;

procedure TCustomBCEditor.WMPaint(var AMessage: TWMPaint);
var
  LCompatibleBitmap: HBITMAP;
  LCompatibleDC: HDC;
  LDC: HDC;
  LOldBitmap: HBITMAP;
  LPaintStruct: TPaintStruct;
begin
  if AMessage.DC <> 0 then
  begin
    if not (csCustomPaint in ControlState) and (ControlCount = 0) then
      inherited
    else
      PaintHandler(AMessage);
  end
  else
  begin
    LDC := GetDC(0);
    LCompatibleBitmap := CreateCompatibleBitmap(LDC, ClientWidth, ClientHeight);
    ReleaseDC(0, LDC);
    LCompatibleDC := CreateCompatibleDC(0);
    LOldBitmap := SelectObject(LCompatibleDC, LCompatibleBitmap);
    try
      LDC := BeginPaint(Handle, LPaintStruct);
      AMessage.DC := LCompatibleDC;
      WMPaint(AMessage);
      BitBlt(LDC, 0, 0, ClientRect.Right, ClientRect.Bottom, LCompatibleDC, 0, 0, SRCCOPY);
      EndPaint(Handle, LPaintStruct);
    finally
      SelectObject(LCompatibleDC, LOldBitmap);
      DeleteObject(LCompatibleBitmap);
      DeleteDC(LCompatibleDC);
    end;
  end;
end;

procedure TCustomBCEditor.WMPaste(var AMessage: TMessage);
begin
  if (not ReadOnly) then
    PasteFromClipboard();
  AMessage.Result := LRESULT(TRUE);
end;

procedure TCustomBCEditor.WMSetCursor(var AMessage: TWMSetCursor);
begin
  if (AMessage.HitTest = HTCLIENT) and (AMessage.CursorWnd = Handle) and not (csDesigning in ComponentState) then
    UpdateMouseCursor
  else
    inherited;
end;

procedure TCustomBCEditor.WMSetFocus(var AMessage: TWMSetFocus);
begin
  inherited;

  if (Assigned(FCompletionProposalPopupWindow)) then
    PostMessage(Handle, UM_FREE_COMPLETIONPROPOSAL_POPUPWINDOW, 0, 0);

  if (not AlwaysShowCaret) then
  begin
    ResetCaret();
    UpdateCaret();
  end;

  if (HideSelection and SelectionAvailable) then
    Invalidate;
end;

procedure TCustomBCEditor.WMSetText(var AMessage: TWMSetText);
begin
  AMessage.Result := 1;
  try
    if HandleAllocated and IsWindowUnicode(Handle) then
      Text := PChar(AMessage.Text)
    else
      Text := string(PAnsiChar(AMessage.Text));
  except
    AMessage.Result := 0;
    raise
  end
end;

procedure TCustomBCEditor.WMSettingChange(var AMessage: TWMSettingChange);
begin
  inherited;

  if (AMessage.Flag = SPI_SETWHEELSCROLLLINES) then
    if (not SystemParametersInfo(SPI_GETWHEELSCROLLLINES, 0, @FWheelScrollLines, 0)) then
      FWheelScrollLines := 3;
end;

procedure TCustomBCEditor.WMUndo(var AMessage: TMessage);
begin
  Undo();
end;

procedure TCustomBCEditor.WMVScroll(var AMessage: TWMScroll);
var
  LScrollButtonHeight: Integer;
  LScrollHint: string;
  LScrollHintPoint: TPoint;
  LScrollHintRect: TRect;
  LScrollHintWindow: THintWindow;
  LScrollInfo: TScrollInfo;
begin
  Invalidate;
  AMessage.Result := 0;

  FreeTokenInfoPopupWindow;

  case AMessage.ScrollCode of
    SB_TOP:
      TopRow := 1;
    SB_BOTTOM:
      TopRow := Rows.Count;
    SB_LINEDOWN:
      TopRow := TopRow + 1;
    SB_LINEUP:
      TopRow := TopRow - 1;
    SB_PAGEDOWN:
      TopRow := TopRow + VisibleRows;
    SB_PAGEUP:
      TopRow := TopRow - VisibleRows;
    SB_THUMBPOSITION, SB_THUMBTRACK:
      begin
        FIsScrolling := True;
        if Rows.Count > BCEDITOR_MAX_SCROLL_RANGE then
          TopRow := MulDiv(VisibleRows + Rows.Count - 1, AMessage.Pos, BCEDITOR_MAX_SCROLL_RANGE)
        else
          TopRow := AMessage.Pos;

        if soShowVerticalScrollHint in FScroll.Options then
        begin
          LScrollHintWindow := GetScrollHint;
          if FScroll.Hint.Format = shFTopLineOnly then
            LScrollHint := Format(SBCEditorScrollInfoTopLine, [TopRow])
          else
            LScrollHint := Format(SBCEditorScrollInfo,
              [TopRow, TopRow + Min(VisibleRows, Rows.Count - TopRow)]);

          LScrollHintRect := LScrollHintWindow.CalcHintRect(200, LScrollHint, nil);

          if soHintFollows in FScroll.Options then
          begin
            LScrollButtonHeight := GetSystemMetrics(SM_CYVSCROLL);

            FillChar(LScrollInfo, SizeOf(LScrollInfo), 0);
            LScrollInfo.cbSize := SizeOf(LScrollInfo);
            LScrollInfo.fMask := SIF_ALL;
            GetScrollInfo(Handle, SB_VERT, LScrollInfo);

            LScrollHintPoint := ClientToScreen(Point(ClientWidth - LScrollHintRect.Right - 4,
              ((LScrollHintRect.Bottom - LScrollHintRect.Top) shr 1) + Round((LScrollInfo.nTrackPos / LScrollInfo.nMax)
              * (ClientHeight - LScrollButtonHeight * 2)) - 2));
          end
          else
            LScrollHintPoint := ClientToScreen(Point(ClientWidth - LScrollHintRect.Right - 4, 4));

          OffsetRect(LScrollHintRect, LScrollHintPoint.X, LScrollHintPoint.Y);
          LScrollHintWindow.ActivateHint(LScrollHintRect, LScrollHint);
          LScrollHintWindow.Update;
        end;
      end;
    SB_ENDSCROLL:
      begin
        FIsScrolling := False;
        if soShowVerticalScrollHint in FScroll.Options then
          ShowWindow(GetScrollHint.Handle, SW_HIDE);
      end;
  end;
  Update;
  if Assigned(OnScroll) then
    OnScroll(Self, sbVertical);
end;

procedure TCustomBCEditor.WndProc(var AMessage: TMessage);
begin
  case (AMessage.Msg) of
    WM_LBUTTONDOWN, WM_LBUTTONDBLCLK:
      if (not (csDesigning in ComponentState) and not Focused()) then
      begin
        Windows.SetFocus(Handle);
        if (not Focused) then Exit;
      end;
    WM_SYSCHAR:
      { Prevent Alt+Backspace from beeping }
      if ((AMessage.wParam = VK_BACK) and (AMessage.lParam and (1 shl 29) <> 0)) then
        AMessage.Msg := 0;
    WM_SETTEXT,
    WM_GETTEXT,
    WM_GETTEXTLENGTH:
      { Handle direct WndProc calls that could happen through VCL-methods like Perform }
      if (HandleAllocated and IsWindowUnicode(Handle)) then
        if (FWindowProducedMessage) then
          FWindowProducedMessage := False
        else
        begin
          FWindowProducedMessage := True;
          with AMessage do
            Result := SendMessageA(Handle, Msg, wParam, LParam);
          Exit;
        end;
  end;

  inherited;
end;

function TCustomBCEditor.WordAtCursor(): string;
begin
  Result := GetWordAt(CaretPos);
end;

function TCustomBCEditor.WordAtMouse(): string;
var
  LTextPosition: TBCEditorTextPosition;
begin
  Result := '';
  if GetTextPositionOfMouse(LTextPosition) then
    Result := GetWordAtTextPosition(LTextPosition);
end;

function TCustomBCEditor.WordBegin(const ATextPosition: TBCEditorTextPosition): TBCEditorTextPosition;
begin
  Result := ATextPosition;
  while ((Result.Char - 1 >= 0) and not IsWordBreakChar(Lines.Lines[Result.Line].Text[1 + Result.Char - 1])) do
    Dec(Result.Char);
end;

function TCustomBCEditor.WordEnd(): TBCEditorTextPosition;
begin
  Result := WordEnd(Lines.CaretPosition);
end;

function TCustomBCEditor.WordEnd(const ATextPosition: TBCEditorTextPosition): TBCEditorTextPosition;
begin
  Result := ATextPosition;
  while ((Result.Char + 1 < Length(Lines.Lines[Result.Line].Text)) and not IsWordBreakChar(Lines.Lines[Result.Line].Text[1 + Result.Char + 1])) do
    Inc(Result.Char);
end;

procedure TCustomBCEditor.WordWrapChanged(ASender: TObject);
begin
  FRows.Clear();
  FMultiCaretPosition.Row := -1;

  Invalidate();
end;

function TCustomBCEditor.WordWrapWidth: Integer;
begin
  case (FWordWrap.Width) of
    wwwPage:
      Result := TextWidth;
    wwwRightMargin:
      Result := FRightMargin.Position * CharWidth;
    else raise ERangeError.Create('Width: ' + IntToStr(Ord(FWordWrap.Width)));
  end;
end;

end.

