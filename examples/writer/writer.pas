{ Bruto Writer: a small word processor in Free Vision, compiled by Bruto
  Pascal. The editor, menus, dialogs and file dialogs are Free Vision's
  (Turbo Pascal `object` types); the document logic is WriterCore's
  (classes, interfaces, generics, Variants, Currency, RTTI and component
  streaming). See README.md. }
program Writer;

{$mode objfpc}{$H+}

uses
  {$ifdef UNIX}cwstring,{$endif}
  SysUtils, Classes, Variants,
  Objects, FVConsts, Drivers, Views, Menus, Dialogs, App, Editors, MsgBox, StdDlg,
  WriterCore;

const
  cmStatistics = 1001;
  cmOutline = 1002;
  cmProperties = 1003;
  cmInspect = 1004;
  cmInvoice = 1005;
  cmExport = 1006;
  cmInspire = 1007;
  cmAbout = 1008;
  { Broadcast: the topmost document window answers. }
  cmFindDocument = 1100;

type
  PDocWindow = ^TDocWindow;

  { A document: Free Vision's editor window, with its properties (a
    TDocInfo component, saved beside the file as Name.meta). }
  TDocWindow = object(TEditWindow)
    Info: TDocInfo;
    constructor Init(var Bounds: TRect; AFileName: FNameStr);
    destructor Done; virtual;
    function GetTitle(MaxSize: Sw_Integer): TTitleStr; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    { The text, as lines. The caller frees them. }
    function Lines: Classes.TStringList;
  end;

  PReportWindow = ^TReportWindow;

  { A report: an editor window holding text the program wrote. }
  TReportWindow = object(TEditWindow)
    Caption: string;
    function GetTitle(MaxSize: Sw_Integer): TTitleStr; virtual;
  end;

  TWriterApp = object(TApplication)
    constructor Init;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure InitMenuBar; virtual;
    procedure InitStatusLine; virtual;
  end;

var
  WriterApp: TWriterApp;

const
  Welcome =
    '# Welcome to Bruto Writer' + LineEnding + LineEnding +
    'Write here. Lines starting with # are headings; the Document menu' + LineEnding +
    'counts your words, outlines the headings, works out an invoice and' + LineEnding +
    'exports the text as HTML or Markdown. Save the document (F2) and its' + LineEnding +
    'properties are saved too, as a component stream beside it.' + LineEnding + LineEnding +
    'Stuck? Try Document > Inspire me.' + LineEnding;

{ ── Helpers ─────────────────────────────────────────────────── }

{ Views at (AX, AY)-(BX, BY): their constructors take the bounds as a
  var parameter. }
function NewDialog(BX, BY: Sw_Integer; const Title: string): PDialog;
var
  R: TRect;
begin
  R.Assign(0, 0, BX, BY);
  Result := New(PDialog, Init(R, Title));
  Result^.Options := Result^.Options or ofCentered;
end;

function NewLabel(AX, AY, BX: Sw_Integer; const Text: string; Link: PView): PLabel;
var
  R: TRect;
begin
  R.Assign(AX, AY, BX, AY + 1);
  Result := New(PLabel, Init(R, Text, Link));
end;

function NewButton(AX, AY: Sw_Integer; const Title: string; Command: Word;
  Flags: Byte): PButton;
var
  R: TRect;
begin
  R.Assign(AX, AY, AX + 12, AY + 2);
  Result := New(PButton, Init(R, Title, Command, Flags));
end;

function NewRadio(AX, AY, BX, BY: Sw_Integer; Items: PSItem): PRadioButtons;
var
  R: TRect;
begin
  R.Assign(AX, AY, BX, BY);
  Result := New(PRadioButtons, Init(R, Items));
end;

function NewChecks(AX, AY, BX, BY: Sw_Integer; Items: PSItem): PCheckBoxes;
var
  R: TRect;
begin
  R.Assign(AX, AY, BX, BY);
  Result := New(PCheckBoxes, Init(R, Items));
end;

function NewText(AX, AY, BX: Sw_Integer; const Text: string): PStaticText;
var
  R: TRect;
begin
  R.Assign(AX, AY, BX, AY + 1);
  Result := New(PStaticText, Init(R, Text));
end;

{ Text for an editor: its lines ended by CR LF. }
function EditorText(const S: string): string;
var
  L: Classes.TStringList;
  I: Integer;
begin
  L := Classes.TStringList.Create;
  try
    L.Text := S;
    Result := '';
    for I := 0 to L.Count - 1 do
      Result := Result + L[I] + #13#10;
  finally
    L.Free;
  end;
end;

{ An editor window whose text the program just wrote: cursor at the top,
  nothing to save. }
procedure Unmodified(W: PEditWindow);
begin
  { Cleared first: moving the cursor updates the indicator. }
  W^.Editor^.Modified := False;
  W^.Editor^.SetCurPtr(1, 0);
  W^.Editor^.SetCurPtr(0, 0);
  W^.Editor^.TrackCursor(False);
end;

procedure ShowReport(const Caption, Text: string);
var
  R: TRect;
  W: PReportWindow;
  S: string;
begin
  Desktop^.GetExtent(R);
  R.A.X := R.B.X div 4;
  W := New(PReportWindow, Init(R, '', wnNoNumber));
  W^.Caption := Caption;
  S := EditorText(Text);
  if S <> '' then
    W^.Editor^.InsertText(@S[1], Length(S), False);
  Unmodified(W);
  Application^.InsertWindow(W);
end;

procedure ShowError(const What: string; E: Exception);
begin
  MessageBox(What + ': ' + E.Message, nil, mfError + mfOkButton);
end;

{ The topmost document window, or nil. }
function CurrentDocument: PDocWindow;
begin
  Result := PDocWindow(Message(Desktop, evBroadcast, cmFindDocument, nil));
end;

function OpenDocument(const FileName: string): PDocWindow;
var
  R: TRect;
begin
  Desktop^.GetExtent(R);
  Result := New(PDocWindow, Init(R, FileName));
  Application^.InsertWindow(Result);
end;

{ ── Documents ───────────────────────────────────────────────── }

constructor TDocWindow.Init(var Bounds: TRect; AFileName: FNameStr);
begin
  inherited Init(Bounds, AFileName, wnNoNumber);
  Info := TDocInfo.Create(nil);
  Info.Name := 'Document';
  if AFileName <> '' then
  begin
    try
      LoadInfo(Info, AFileName);
    except
      on E: Exception do
        ShowError('Properties not read', E);
    end;
    if Info.Title = '' then
      Info.Title := ChangeFileExt(SysUtils.ExtractFileName(AFileName), '');
  end
  else
    Info.Title := 'Untitled';
end;

destructor TDocWindow.Done;
begin
  Info.Free;
  inherited Done;
end;

function TDocWindow.GetTitle(MaxSize: Sw_Integer): TTitleStr;
begin
  if Editor^.FileName = '' then
    Result := Info.Title
  else
    Result := Info.Title + ' (' + SysUtils.ExtractFileName(Editor^.FileName) + ')';
end;

procedure TDocWindow.HandleEvent(var Event: TEvent);
var
  Saving: Boolean;
begin
  if (Event.What = evBroadcast) and (Event.Command = cmFindDocument) then
  begin
    ClearEvent(Event);
    Exit;
  end;
  Saving := (Event.What = evCommand) and ((Event.Command = cmSave) or (Event.Command = cmSaveAs));
  inherited HandleEvent(Event);
  if Saving and (Editor^.FileName <> '') and not Editor^.Modified then
  begin
    try
      FindHeadings(Lines, Info);
      SaveInfo(Info, Editor^.FileName);
    except
      on E: Exception do
        ShowError('Properties not saved', E);
    end;
    Frame^.DrawView;
  end;
end;

function TDocWindow.Lines: Classes.TStringList;
var
  I: Sw_Word;
  S: string;
begin
  SetLength(S, Editor^.BufLen);
  if Editor^.BufLen > 0 then
    for I := 0 to Editor^.BufLen - 1 do
      S[I + 1] := Editor^.BufChar(I);
  Result := Classes.TStringList.Create;
  Result.Text := S;
end;

function TReportWindow.GetTitle(MaxSize: Sw_Integer): TTitleStr;
begin
  Result := Caption;
end;

{ ── Dialogs ─────────────────────────────────────────────────── }

function NewInput(D: PDialog; Y: Sw_Integer; const LabelText: string; MaxLen: Sw_Integer;
  const Value: string): PInputLine;
var
  R: TRect;
  S: ShortString;
begin
  R.Assign(15, Y, 56, Y + 1);
  Result := New(PInputLine, Init(R, MaxLen));
  D^.Insert(Result);
  D^.Insert(NewLabel(2, Y, 14, LabelText, Result));
  S := Value;
  Result^.SetData(S);
end;

function InputText(Line: PInputLine): string;
var
  S: ShortString;
begin
  Line^.GetData(S);
  Result := Trim(S);
end;

{ OK and Cancel. (The dialog's focus goes to the last control inserted:
  callers then select the first, so Enter means OK.) }
procedure AddButtons(D: PDialog; Y: Sw_Integer);
begin
  D^.Insert(NewButton(15, Y, 'O~K~', cmOK, bfDefault));
  D^.Insert(NewButton(30, Y, 'Cancel', cmCancel, bfNormal));
end;

procedure EditProperties(Doc: PDocWindow);
var
  D: PDialog;
  TitleLine, AuthorLine, RateLine, RatingLine: PInputLine;
  Genre: PRadioButtons;
  Tags: PCheckBoxes;
  T: TTag;
  Bits: LongInt;
  Rating: string;
  N: Integer;
begin
  D := NewDialog(60, 20, 'Document properties');
  TitleLine := NewInput(D, 2, '~T~itle', 60, Doc^.Info.Title);
  AuthorLine := NewInput(D, 4, '~A~uthor', 60, Doc^.Info.Author);
  Genre := NewRadio(15, 7, 30, 12,
    NewSItem('~N~ovel', NewSItem('~E~ssay', NewSItem('~P~oem',
    NewSItem('~L~etter', NewSItem('N~o~tes', nil))))));
  D^.Insert(Genre);
  D^.Insert(NewLabel(15, 6, 30, '~G~enre', Genre));
  Tags := NewChecks(33, 7, 56, 12,
    NewSItem('~D~raft', NewSItem('~R~eviewed', NewSItem('~F~inal',
    NewSItem('Pr~i~vate', NewSItem('Fa~v~ourite', nil))))));
  D^.Insert(Tags);
  D^.Insert(NewLabel(33, 6, 56, 'Ta~g~s', Tags));
  RateLine := NewInput(D, 13, 'Rate/~w~ord', 14, CurrToStr(Doc^.Info.Rate));
  if VarIsNull(Doc^.Info.Rating) or VarIsEmpty(Doc^.Info.Rating) then
    Rating := ''
  else
    Rating := VarToStr(Doc^.Info.Rating);
  RatingLine := NewInput(D, 15, 'Rati~n~g', 20, Rating);
  AddButtons(D, 17);
  Genre^.Value := Ord(Doc^.Info.Genre);
  Bits := 0;
  for T := Low(TTag) to High(TTag) do
    if T in Doc^.Info.Tags then
      Bits := Bits or (LongInt(1) shl Ord(T));
  Tags^.Value := Bits;
  D^.SelectNext(False);
  if Desktop^.ExecView(D) = cmOK then
  begin
    Doc^.Info.Title := InputText(TitleLine);
    Doc^.Info.Author := InputText(AuthorLine);
    Doc^.Info.Genre := TGenre(Genre^.Value);
    Doc^.Info.Tags := [];
    for T := Low(TTag) to High(TTag) do
      if (Tags^.Value and (LongInt(1) shl Ord(T))) <> 0 then
        Doc^.Info.Tags := Doc^.Info.Tags + [T];
    try
      Doc^.Info.Rate := StrToCurr(InputText(RateLine));
    except
      on E: EConvertError do
        ShowError('Rate unchanged', E);
    end;
    { A Variant: a number of stars, a word, or nothing. }
    Rating := InputText(RatingLine);
    if Rating = '' then
      Doc^.Info.Rating := Null
    else if TryStrToInt(Rating, N) then
      Doc^.Info.Rating := N
    else
      Doc^.Info.Rating := Rating;
    Doc^.Frame^.DrawView;
  end;
  Dispose(D, Done);
end;

procedure Invoice(Doc: PDocWindow);
var
  D: PDialog;
  TaxLine: PInputLine;
  Text: Classes.TStringList;
  Tax: Currency;
begin
  D := NewDialog(60, 10, 'Invoice');
  TaxLine := NewInput(D, 2, '~T~ax %', 8, '21');
  D^.Insert(NewText(15, 4, 58, 'Rate per word: ' + CurrToStr(Doc^.Info.Rate)
    + ' (see Properties)'));
  AddButtons(D, 6);
  D^.SelectNext(False);
  if Desktop^.ExecView(D) = cmOK then
  begin
    Text := Doc^.Lines;
    try
      try
        Tax := StrToCurr(InputText(TaxLine));
        ShowReport('Invoice', InvoiceReport(Doc^.Info, Text, Tax));
      except
        on E: EConvertError do
          ShowError('Not a tax rate', E);
        on E: EWriterError do
          ShowError('No invoice', E);
      end;
    finally
      Text.Free;
    end;
  end;
  Dispose(D, Done);
end;

procedure ExportDialog(Doc: PDocWindow);
var
  D: PDialog;
  Formats: PRadioButtons;
  Text: Classes.TStringList;
  Written: string;
  E: IExporter;
begin
  D := NewDialog(44, 11, 'Export');
  { The choices are the exporters' own names (an interface each). }
  Formats := NewRadio(3, 2, 41, 5,
    NewSItem(Exporter(0).Name + ' (' + Exporter(0).Extension + ')',
    NewSItem(Exporter(1).Name + ' (' + Exporter(1).Extension + ')',
    NewSItem(Exporter(2).Name + ' (' + Exporter(2).Extension + ')', nil))));
  D^.Insert(Formats);
  D^.Insert(NewButton(8, 7, 'O~K~', cmOK, bfDefault));
  D^.Insert(NewButton(23, 7, 'Cancel', cmCancel, bfNormal));
  Formats^.Value := 1;
  D^.SelectNext(False);
  if Desktop^.ExecView(D) = cmOK then
  begin
    Text := Doc^.Lines;
    try
      try
        E := Exporter(Formats^.Value);
        Written := ExportDocument(E, Doc^.Info, Text, Doc^.Editor^.FileName);
        MessageBox(E.Name + ' written to ' + SysUtils.ExtractFileName(Written), nil,
          mfInformation + mfOkButton);
      except
        on Ex: Exception do
          ShowError('Not exported', Ex);
      end;
    finally
      Text.Free;
    end;
  end;
  Dispose(D, Done);
end;

procedure Inspire(Doc: PDocWindow);
var
  Prompt: string;
begin
  Prompt := Inspiration;
  if MessageBox(Prompt + #13#13'Add it to the document?', nil,
    mfConfirmation + mfYesButton + mfNoButton) = cmYes then
  begin
    Prompt := Prompt + #13#10;
    Doc^.Editor^.InsertText(@Prompt[1], Length(Prompt), False);
  end;
end;

{ ── The application ─────────────────────────────────────────── }

constructor TWriterApp.Init;
var
  W: PDocWindow;
  S: string;
begin
  inherited Init;
  EditorDialog := @StdEditorDialog;
  Randomize;
  if ParamCount > 0 then
    OpenDocument(ParamStr(1))
  else
  begin
    W := OpenDocument('');
    S := EditorText(Welcome);
    W^.Editor^.InsertText(@S[1], Length(S), False);
    Unmodified(W);
  end;
end;

procedure TWriterApp.HandleEvent(var Event: TEvent);
var
  Doc: PDocWindow;
  FileName: FNameStr;
  Text: Classes.TStringList;
begin
  inherited HandleEvent(Event);
  if Event.What <> evCommand then
    Exit;
  case Event.Command of
    cmNew:
      OpenDocument('');
    cmOpen:
      begin
        FileName := '*.wri';
        if ExecuteDialog(New(PFileDialog, Init('*.wri', 'Open a document', '~N~ame',
          fdOpenButton, 100)), @FileName) <> cmCancel then
          OpenDocument(FileName);
      end;
    cmAbout:
      MessageBox(#3'Bruto Writer'#13#13#3'Free Vision and Object Pascal,'#13 +
        #3'compiled by Bruto Pascal.', nil, mfInformation + mfOkButton);
    cmStatistics, cmOutline, cmProperties, cmInspect, cmInvoice, cmExport, cmInspire:
      begin
        Doc := CurrentDocument;
        if Doc = nil then
        begin
          MessageBox('Open a document first.', nil, mfWarning + mfOkButton);
          ClearEvent(Event);
          Exit;
        end;
        case Event.Command of
          cmStatistics, cmOutline, cmInspect:
            begin
              Text := Doc^.Lines;
              try
                FindHeadings(Text, Doc^.Info);
                case Event.Command of
                  cmStatistics: ShowReport('Statistics', StatisticsReport(Doc^.Info, Text));
                  cmOutline: ShowReport('Outline', OutlineReport(Doc^.Info));
                else
                  ShowReport('Inspect', PropertiesReport(Doc^.Info));
                end;
              finally
                Text.Free;
              end;
            end;
          cmProperties: EditProperties(Doc);
          cmInvoice: Invoice(Doc);
          cmExport: ExportDialog(Doc);
          cmInspire: Inspire(Doc);
        end;
      end;
  else
    Exit;
  end;
  ClearEvent(Event);
end;

procedure TWriterApp.InitMenuBar;
var
  R: TRect;
begin
  GetExtent(R);
  R.B.Y := R.A.Y + 1;
  MenuBar := New(PMenuBar, Init(R, NewMenu(
    NewSubMenu('~F~ile', hcNoContext, NewMenu(
      NewItem('~N~ew', '', kbNoKey, cmNew, hcNoContext,
      NewItem('~O~pen...', 'F3', kbF3, cmOpen, hcNoContext,
      NewItem('~S~ave', 'F2', kbF2, cmSave, hcNoContext,
      NewItem('Save ~a~s...', '', kbNoKey, cmSaveAs, hcNoContext,
      NewLine(
      NewItem('E~x~it', 'Alt-X', kbAltX, cmQuit, hcNoContext, nil))))))),
    NewSubMenu('~E~dit', hcNoContext, NewMenu(
      NewItem('~U~ndo', '', kbNoKey, cmUndo, hcNoContext,
      NewLine(
      NewItem('Cu~t~', 'Shift-Del', kbShiftDel, cmCut, hcNoContext,
      NewItem('~C~opy', 'Ctrl-Ins', kbCtrlIns, cmCopy, hcNoContext,
      NewItem('~P~aste', 'Shift-Ins', kbShiftIns, cmPaste, hcNoContext,
      NewLine(
      NewItem('~F~ind...', '', kbNoKey, cmFind, hcNoContext,
      NewItem('~R~eplace...', '', kbNoKey, cmReplace, hcNoContext, nil))))))))),
    NewSubMenu('~D~ocument', hcNoContext, NewMenu(
      NewItem('~S~tatistics', 'F7', kbF7, cmStatistics, hcNoContext,
      NewItem('~O~utline', 'F8', kbF8, cmOutline, hcNoContext,
      NewItem('~P~roperties...', 'F9', kbF9, cmProperties, hcNoContext,
      NewItem('~I~nspect (RTTI, stream)', '', kbNoKey, cmInspect, hcNoContext,
      NewLine(
      NewItem('In~v~oice...', '', kbNoKey, cmInvoice, hcNoContext,
      NewItem('~E~xport...', '', kbNoKey, cmExport, hcNoContext,
      NewLine(
      NewItem('Inspire ~m~e', '', kbNoKey, cmInspire, hcNoContext, nil)))))))))),
    NewSubMenu('~W~indow', hcNoContext, NewMenu(
      NewItem('~N~ext', 'F6', kbF6, cmNext, hcNoContext,
      NewItem('~Z~oom', 'F5', kbF5, cmZoom, hcNoContext,
      NewItem('~T~ile', '', kbNoKey, cmTile, hcNoContext,
      NewItem('C~a~scade', '', kbNoKey, cmCascade, hcNoContext,
      NewItem('~C~lose', 'Alt-F3', kbAltF3, cmClose, hcNoContext, nil)))))),
    NewSubMenu('~H~elp', hcNoContext, NewMenu(
      NewItem('~A~bout...', '', kbNoKey, cmAbout, hcNoContext, nil)),
    nil))))))));
end;

procedure TWriterApp.InitStatusLine;
var
  R: TRect;
begin
  GetExtent(R);
  R.A.Y := R.B.Y - 1;
  StatusLine := New(PStatusLine, Init(R,
    NewStatusDef(0, $FFFF,
      NewStatusKey('~F2~ Save', kbF2, cmSave,
      NewStatusKey('~F3~ Open', kbF3, cmOpen,
      NewStatusKey('~F7~ Stats', kbF7, cmStatistics,
      NewStatusKey('~F8~ Outline', kbF8, cmOutline,
      NewStatusKey('~F9~ Properties', kbF9, cmProperties,
      NewStatusKey('~Alt-X~ Exit', kbAltX, cmQuit, nil)))))),
    nil)));
end;

begin
  WriterApp.Init;
  WriterApp.Run;
  WriterApp.Done;
end.
