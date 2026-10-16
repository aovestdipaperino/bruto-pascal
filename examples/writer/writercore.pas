{ Bruto Writer: the document logic behind the Free Vision editor.

  Plain Object Pascal ({$mode objfpc}), kept apart from the Free Vision
  program so it can use FPC's classes (Free Vision's Objects unit has a
  TObject of its own). It shows the language features Bruto Pascal
  compiles as FPC does:

  - classes, properties, published RTTI and component streaming
    (TDocInfo, ObjectBinaryToText, WriteComponent/ReadComponent);
  - a TCollection of headings, streamed with the component;
  - an enumeration with explicit values, sets of characters and of tags;
  - Currency arithmetic for the invoice, Variants for the rating;
  - interfaces (IExporter) with reference counting, a generic routine
    and generic containers (fgl's TFPGMap);
  - exceptions, the Math unit, Random, WriteStr and Format. }
unit WriterCore;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes, TypInfo, Variants, Math, fgl;

type
  TGenre = (gnNovel, gnEssay, gnPoem, gnLetter, gnNotes);
  { Words per minute: an enumeration with explicit values. }
  TReadingSpeed = (rsSlow = 180, rsAverage = 230, rsFast = 300);
  TTag = (tgDraft, tgReviewed, tgFinal, tgPrivate, tgFavourite);
  TTags = set of TTag;

  { A heading of the document (a line starting with '#'). }
  THeading = class(TCollectionItem)
  private
    FTitle: string;
    FLine: Integer;
    FLevel: Integer;
  published
    property Title: string read FTitle write FTitle;
    property Line: Integer read FLine write FLine;
    property Level: Integer read FLevel write FLevel default 1;
  end;

  THeadings = class(TOwnedCollection)
  private
    function GetHeading(Index: Integer): THeading;
  public
    function AddHeading(const ATitle: string; ALine, ALevel: Integer): THeading;
    property Headings[Index: Integer]: THeading read GetHeading; default;
  end;

  { The document's properties, saved beside it as a component stream. }
  TDocInfo = class(TComponent)
  private
    FTitle: string;
    FAuthor: string;
    FGenre: TGenre;
    FTags: TTags;
    FRate: Currency;
    FRating: Variant;
    FWords: Integer;
    FHeadings: THeadings;
    procedure SetHeadings(Value: THeadings);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Title: string read FTitle write FTitle;
    property Author: string read FAuthor write FAuthor;
    property Genre: TGenre read FGenre write FGenre default gnNovel;
    property Tags: TTags read FTags write FTags;
    property Rate: Currency read FRate write FRate;
    property Rating: Variant read FRating write FRating;
    property Words: Integer read FWords write FWords;
    property Headings: THeadings read FHeadings write SetHeadings;
  end;

  TStats = record
    Chars, Letters, Words, Sentences, Paragraphs, Lines, Syllables: Integer;
    LongestWord: string;
    SentenceLengths: array of Double;
  end;

  { A way to save the document in another format. }
  IExporter = interface
    ['{6B0E2C1A-4D5F-4E8B-9A71-3C2D1E0F5A6B}']
    function Name: string;
    function Extension: string;
    function Render(Info: TDocInfo; Lines: TStrings): string;
  end;

  EWriterError = class(Exception);

  TWordCounts = specialize TFPGMap<string, Integer>;

const
  WordChars = ['A'..'Z', 'a'..'z', '0'..'9', '''', #128..#255];
  SentenceEnds = ['.', '!', '?'];

{ A genre's name. }
function GenreName(G: TGenre): string;
{ Counts of the text in Lines. }
function Analyse(Lines: TStrings): TStats;
{ Flesch reading ease (higher is easier), clamped to 0..100. }
function Readability(const S: TStats): Double;
{ The Count most frequent words of three letters or more. }
function TopWords(Lines: TStrings; Count: Integer): string;
{ The headings ('#' lines) of Lines, into Info.Headings. }
procedure FindHeadings(Lines: TStrings; Info: TDocInfo);

function StatisticsReport(Info: TDocInfo; Lines: TStrings): string;
function InvoiceReport(Info: TDocInfo; Lines: TStrings; TaxPercent: Currency): string;
function PropertiesReport(Info: TDocInfo): string;
function OutlineReport(Info: TDocInfo): string;
function ExportersReport: string;

{ The exporters, by number (0, 1, 2). }
function Exporter(Index: Integer): IExporter;
function ExporterCount: Integer;
{ Write the document with exporter E beside FileName; the file written. }
function ExportDocument(E: IExporter; Info: TDocInfo; Lines: TStrings;
  const FileName: string): string;

{ The properties file of a document: Name.meta. }
function InfoFileName(const FileName: string): string;
procedure SaveInfo(Info: TDocInfo; const FileName: string);
{ Read Info back; False when there is no properties file. }
function LoadInfo(Info: TDocInfo; const FileName: string): Boolean;

{ A writing prompt, picked at random. }
function Inspiration: string;

{ Lower..Upper, for any ordered type. }
generic function Clamp<T>(Value, Lower, Upper: T): T;

implementation

{ ── Headings ────────────────────────────────────────────────── }

function THeadings.GetHeading(Index: Integer): THeading;
begin
  Result := THeading(Items[Index]);
end;

function THeadings.AddHeading(const ATitle: string; ALine, ALevel: Integer): THeading;
begin
  Result := THeading(Add);
  Result.Title := ATitle;
  Result.Line := ALine;
  Result.Level := ALevel;
end;

{ ── Document properties ─────────────────────────────────────── }

constructor TDocInfo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FGenre := gnNovel;
  FTags := [tgDraft];
  FRate := 0.08;
  FRating := Null;
  FHeadings := THeadings.Create(Self, THeading);
end;

destructor TDocInfo.Destroy;
begin
  FHeadings.Free;
  inherited Destroy;
end;

procedure TDocInfo.SetHeadings(Value: THeadings);
begin
  FHeadings.Assign(Value);
end;

function GenreName(G: TGenre): string;
begin
  case G of
    gnNovel: Result := 'novel';
    gnEssay: Result := 'essay';
    gnPoem: Result := 'poem';
    gnLetter: Result := 'letter';
  else
    Result := 'notes';
  end;
end;

{ ── Analysis ────────────────────────────────────────────────── }

generic function Clamp<T>(Value, Lower, Upper: T): T;
begin
  if Value < Lower then
    Result := Lower
  else if Value > Upper then
    Result := Upper
  else
    Result := Value;
end;

{ Vowel groups, a rough syllable count. }
function Syllables(const W: string): Integer;
const
  Vowels = ['a', 'e', 'i', 'o', 'u', 'y', 'A', 'E', 'I', 'O', 'U', 'Y'];
var
  I: Integer;
  InGroup: Boolean;
begin
  Result := 0;
  InGroup := False;
  for I := 1 to Length(W) do
    if W[I] in Vowels then
    begin
      if not InGroup then
        Inc(Result);
      InGroup := True;
    end
    else
      InGroup := False;
  if (Length(W) > 2) and (LowerCase(W[Length(W)]) = 'e') and (Result > 1) then
    Dec(Result);
  if Result = 0 then
    Result := 1;
end;

function Analyse(Lines: TStrings): TStats;
var
  L, I, InSentence: Integer;
  S, W: string;
  Blank: Boolean;
begin
  Result.Chars := 0;
  Result.Letters := 0;
  Result.Words := 0;
  Result.Sentences := 0;
  Result.Paragraphs := 0;
  Result.Lines := Lines.Count;
  Result.Syllables := 0;
  Result.LongestWord := '';
  SetLength(Result.SentenceLengths, 0);
  InSentence := 0;
  Blank := True;
  for L := 0 to Lines.Count - 1 do
  begin
    S := Lines[L];
    Inc(Result.Chars, Length(S));
    if Trim(S) = '' then
    begin
      Blank := True;
      Continue;
    end;
    if Blank then
      Inc(Result.Paragraphs);
    Blank := False;
    W := '';
    for I := 1 to Length(S) + 1 do
    begin
      if (I <= Length(S)) and (S[I] in WordChars) then
      begin
        W := W + S[I];
        if S[I] in ['A'..'Z', 'a'..'z'] then
          Inc(Result.Letters);
        Continue;
      end;
      if W <> '' then
      begin
        Inc(Result.Words);
        Inc(InSentence);
        Inc(Result.Syllables, Syllables(W));
        if Length(W) > Length(Result.LongestWord) then
          Result.LongestWord := W;
        W := '';
      end;
      if (I <= Length(S)) and (S[I] in SentenceEnds) and (InSentence > 0) then
      begin
        Inc(Result.Sentences);
        SetLength(Result.SentenceLengths, Length(Result.SentenceLengths) + 1);
        Result.SentenceLengths[High(Result.SentenceLengths)] := InSentence;
        InSentence := 0;
      end;
    end;
  end;
  if InSentence > 0 then
  begin
    Inc(Result.Sentences);
    SetLength(Result.SentenceLengths, Length(Result.SentenceLengths) + 1);
    Result.SentenceLengths[High(Result.SentenceLengths)] := InSentence;
  end;
end;

function Readability(const S: TStats): Double;
begin
  if (S.Words = 0) or (S.Sentences = 0) then
    Exit(0);
  Result := 206.835 - 1.015 * (S.Words / S.Sentences) - 84.6 * (S.Syllables / S.Words);
  Result := specialize Clamp<Double>(Result, 0, 100);
end;

function TopWords(Lines: TStrings; Count: Integer): string;
var
  Counts: TWordCounts;
  L, I, N, Best, Index: Integer;
  S, W: string;
begin
  Counts := TWordCounts.Create;
  try
    for L := 0 to Lines.Count - 1 do
    begin
      S := Lines[L] + ' ';
      W := '';
      for I := 1 to Length(S) do
        if S[I] in WordChars then
          W := W + S[I]
        else if W <> '' then
        begin
          if Length(W) >= 3 then
          begin
            W := LowerCase(W);
            Index := Counts.IndexOf(W);
            if Index < 0 then
              Counts.Add(W, 1)
            else
              Counts.Data[Index] := Counts.Data[Index] + 1;
          end;
          W := '';
        end;
    end;
    Result := '';
    for N := 1 to Count do
    begin
      Best := -1;
      for I := 0 to Counts.Count - 1 do
        if (Counts.Data[I] > 0) and ((Best < 0) or (Counts.Data[I] > Counts.Data[Best])
          or ((Counts.Data[I] = Counts.Data[Best]) and (Counts.Keys[I] < Counts.Keys[Best]))) then
          Best := I;
      if Best < 0 then
        Break;
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + Format('%s (%d)', [Counts.Keys[Best], Counts.Data[Best]]);
      Counts.Data[Best] := 0;
    end;
  finally
    Counts.Free;
  end;
end;

procedure FindHeadings(Lines: TStrings; Info: TDocInfo);
var
  L, Level: Integer;
  S: string;
begin
  Info.Headings.Clear;
  for L := 0 to Lines.Count - 1 do
  begin
    S := Lines[L];
    if (S <> '') and (S[1] = '#') then
    begin
      Level := 0;
      while (Level < Length(S)) and (S[Level + 1] = '#') do
        Inc(Level);
      Info.Headings.AddHeading(Trim(Copy(S, Level + 1, MaxInt)), L + 1, Level);
    end;
  end;
end;

{ ── Reports ─────────────────────────────────────────────────── }

function Rule(const Title: string): string;
begin
  Result := Title + LineEnding + StringOfChar('=', Length(Title)) + LineEnding;
end;

function StatisticsReport(Info: TDocInfo; Lines: TStrings): string;
var
  S: TStats;
  Ease: Double;
  Level, Spread: string;
begin
  S := Analyse(Lines);
  Info.Words := S.Words;
  Ease := Readability(S);
  case Round(Ease) of
    0..29: Level := 'very hard';
    30..49: Level := 'hard';
    50..69: Level := 'plain';
    70..89: Level := 'easy';
  else
    Level := 'very easy';
  end;
  if Length(S.SentenceLengths) > 1 then
    Spread := Format('%.1f words on average (spread %.1f, longest %d)',
      [Mean(S.SentenceLengths), StdDev(S.SentenceLengths), Round(MaxValue(S.SentenceLengths))])
  else
    Spread := 'not enough sentences';
  Result := Rule('Statistics: ' + Info.Title)
    + Format('Words        %d' + LineEnding, [S.Words])
    + Format('Characters   %d (%d letters)' + LineEnding, [S.Chars, S.Letters])
    + Format('Sentences    %d, %s' + LineEnding, [S.Sentences, Spread])
    + Format('Paragraphs   %d in %d lines' + LineEnding, [S.Paragraphs, S.Lines])
    + Format('Longest word %s' + LineEnding, [S.LongestWord])
    + Format('Reading time %d min (%d at a slow pace)' + LineEnding,
      [Ceil(S.Words / Ord(rsAverage)), Ceil(S.Words / Ord(rsSlow))])
    + Format('Readability  %.0f / 100 (%s)' + LineEnding, [Ease, Level])
    + 'Top words    ' + TopWords(Lines, 5) + LineEnding;
end;

function InvoiceReport(Info: TDocInfo; Lines: TStrings; TaxPercent: Currency): string;
var
  Words: Integer;
  Net, Tax, Total: Currency;
  Line: string;
begin
  Words := Analyse(Lines).Words;
  if Info.Rate <= 0 then
    raise EWriterError.Create('Set a rate per word first');
  { Currency arithmetic: exact to four decimals, as FPC computes it. }
  Net := Info.Rate * Words;
  Tax := Net * TaxPercent / 100;
  Total := Net + Tax;
  Result := Rule('Invoice: ' + Info.Title);
  WriteStr(Line, 'Words      ', Words:12);
  Result := Result + Line + LineEnding;
  WriteStr(Line, 'Rate/word  ', Info.Rate:12:4);
  Result := Result + Line + LineEnding;
  WriteStr(Line, 'Net        ', Net:12:2);
  Result := Result + Line + LineEnding;
  WriteStr(Line, 'Tax ', TaxPercent:4:1, '%   ', Tax:12:2);
  Result := Result + Line + LineEnding;
  WriteStr(Line, 'Total      ', Total:12:2);
  Result := Result + Line + LineEnding + LineEnding
    + 'Total as text: ' + CurrToStr(Total) + LineEnding;
end;

function RatingText(const Rating: Variant): string;
begin
  if VarIsNull(Rating) or VarIsEmpty(Rating) then
    Result := 'not rated'
  else if VarIsNumeric(Rating) then
    Result := StringOfChar('*', Rating) + Format(' (%s, %s)',
      [VarToStr(Rating), VarTypeAsText(VarType(Rating))])
  else
    Result := VarToStr(Rating) + ' (' + VarTypeAsText(VarType(Rating)) + ')';
end;

function PropertiesReport(Info: TDocInfo): string;
var
  Props: PPropList;
  Count, I: Integer;
  Stream: TMemoryStream;
  Text: TStringStream;
  Value: string;
begin
  Result := Rule('Properties: ' + Info.Title);
  { Run-time type information: every published property, by name. }
  Count := GetPropList(Info, Props);
  try
    for I := 0 to Count - 1 do
    begin
      case Props^[I]^.PropType^.Kind of
        tkClass: Value := '(' + GetObjectProp(Info, Props^[I]).ClassName + ')';
        tkVariant: Value := RatingText(GetVariantProp(Info, Props^[I]));
      else
        Value := VarToStr(GetPropValue(Info, Props^[I]^.Name));
      end;
      Result := Result + Format('%-9s %-9s %s',
        [Props^[I]^.Name, GetEnumName(TypeInfo(TTypeKind), Ord(Props^[I]^.PropType^.Kind)),
         Value]) + LineEnding;
    end;
  finally
    FreeMem(Props);
  end;
  Result := Result + Format('Genre %s (ordinal %d); tags are a set of %d bytes',
    [GenreName(Info.Genre), Ord(Info.Genre), SizeOf(TTags)]) + LineEnding;
  { The component as FPC streams it, in its text form. }
  Stream := TMemoryStream.Create;
  Text := TStringStream.Create('');
  try
    Stream.WriteComponent(Info);
    Stream.Position := 0;
    ObjectBinaryToText(Stream, Text);
    Result := Result + LineEnding + Format('Stream (%d bytes):', [Stream.Size]) + LineEnding
      + Text.DataString;
  finally
    Stream.Free;
    Text.Free;
  end;
end;

function OutlineReport(Info: TDocInfo): string;
var
  H: TCollectionItem;
begin
  Result := Rule('Outline: ' + Info.Title);
  if Info.Headings.Count = 0 then
    Exit(Result + 'No headings: start a line with # to add one.' + LineEnding);
  for H in Info.Headings do
    with THeading(H) do
      Result := Result + Format('%4d  %s%s', [Line, StringOfChar(' ', (Level - 1) * 2), Title])
        + LineEnding;
end;

{ ── Exporters ───────────────────────────────────────────────── }

type
  TPlainExporter = class(TInterfacedObject, IExporter)
    function Name: string; virtual;
    function Extension: string; virtual;
    function Render(Info: TDocInfo; Lines: TStrings): string; virtual;
  end;

  THtmlExporter = class(TPlainExporter)
    function Name: string; override;
    function Extension: string; override;
    function Render(Info: TDocInfo; Lines: TStrings): string; override;
  end;

  TMarkdownExporter = class(TPlainExporter)
    function Name: string; override;
    function Extension: string; override;
    function Render(Info: TDocInfo; Lines: TStrings): string; override;
  end;

function TPlainExporter.Name: string;
begin
  Result := 'Plain text';
end;

function TPlainExporter.Extension: string;
begin
  Result := '.txt';
end;

function TPlainExporter.Render(Info: TDocInfo; Lines: TStrings): string;
begin
  Result := Info.Title + LineEnding + 'by ' + Info.Author + LineEnding + LineEnding + Lines.Text;
end;

function THtmlExporter.Name: string;
begin
  Result := 'HTML';
end;

function THtmlExporter.Extension: string;
begin
  Result := '.html';
end;

function Escape(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    case S[I] of
      '<': Result := Result + '&lt;';
      '>': Result := Result + '&gt;';
      '&': Result := Result + '&amp;';
    else
      Result := Result + S[I];
    end;
end;

function THtmlExporter.Render(Info: TDocInfo; Lines: TStrings): string;
var
  L, Level: Integer;
  S: string;
  InPara: Boolean;
begin
  Result := '<!doctype html>' + LineEnding + '<meta charset="utf-8">' + LineEnding
    + '<title>' + Escape(Info.Title) + '</title>' + LineEnding
    + '<h1>' + Escape(Info.Title) + '</h1>' + LineEnding
    + '<p><em>by ' + Escape(Info.Author) + '</em></p>' + LineEnding;
  InPara := False;
  for L := 0 to Lines.Count - 1 do
  begin
    S := Lines[L];
    if (S <> '') and (S[1] = '#') then
    begin
      if InPara then
        Result := Result + '</p>' + LineEnding;
      InPara := False;
      Level := 1;
      while (Level < Length(S)) and (S[Level + 1] = '#') do
        Inc(Level);
      Result := Result + Format('<h%d>%s</h%d>', [Level + 1,
        Escape(Trim(Copy(S, Level + 1, MaxInt))), Level + 1]) + LineEnding;
    end
    else if Trim(S) = '' then
    begin
      if InPara then
        Result := Result + '</p>' + LineEnding;
      InPara := False;
    end
    else
    begin
      if not InPara then
        Result := Result + '<p>';
      InPara := True;
      Result := Result + Escape(S) + LineEnding;
    end;
  end;
  if InPara then
    Result := Result + '</p>' + LineEnding;
end;

function TMarkdownExporter.Name: string;
begin
  Result := 'Markdown';
end;

function TMarkdownExporter.Extension: string;
begin
  Result := '.md';
end;

function TMarkdownExporter.Render(Info: TDocInfo; Lines: TStrings): string;
begin
  Result := '# ' + Info.Title + LineEnding + LineEnding + '*by ' + Info.Author + '*'
    + LineEnding + LineEnding + Lines.Text;
end;

function Exporter(Index: Integer): IExporter;
begin
  case Index of
    0: Result := TPlainExporter.Create;
    1: Result := THtmlExporter.Create;
    2: Result := TMarkdownExporter.Create;
  else
    raise EWriterError.CreateFmt('No exporter %d', [Index]);
  end;
end;

function ExporterCount: Integer;
begin
  Result := 3;
end;

function ExportersReport: string;
var
  I: Integer;
  E: IExporter;
begin
  Result := '';
  for I := 0 to ExporterCount - 1 do
  begin
    E := Exporter(I);
    Result := Result + Format('%d %s (%s)', [I + 1, E.Name, E.Extension]) + LineEnding;
  end;
end;

function ExportDocument(E: IExporter; Info: TDocInfo; Lines: TStrings;
  const FileName: string): string;
var
  Output: TStringList;
begin
  if FileName = '' then
    raise EWriterError.Create('Save the document first');
  Result := ChangeFileExt(FileName, E.Extension);
  if Result = FileName then
    Result := FileName + E.Extension;
  Output := TStringList.Create;
  try
    Output.Text := E.Render(Info, Lines);
    Output.SaveToFile(Result);
  finally
    Output.Free;
  end;
end;

{ ── Saving the properties ───────────────────────────────────── }

function InfoFileName(const FileName: string): string;
begin
  Result := ChangeFileExt(FileName, '.meta');
end;

procedure SaveInfo(Info: TDocInfo; const FileName: string);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(InfoFileName(FileName), fmCreate);
  try
    Stream.WriteComponent(Info);
  finally
    Stream.Free;
  end;
end;

function LoadInfo(Info: TDocInfo; const FileName: string): Boolean;
var
  Stream: TFileStream;
begin
  Result := FileExists(InfoFileName(FileName));
  if not Result then
    Exit;
  Stream := TFileStream.Create(InfoFileName(FileName), fmOpenRead);
  try
    Stream.ReadComponent(Info);
  finally
    Stream.Free;
  end;
end;

function Inspiration: string;
const
  Openings: array[0..4] of string = ('A letter arrives', 'The lights go out',
    'Someone knocks twice', 'The last train leaves', 'A map is found');
  Twists: array[0..4] of string = ('forty years too late', 'in the wrong city',
    'and nobody is surprised', 'just before midnight', 'with a name crossed out');
begin
  Result := Openings[Random(Length(Openings))] + ' ' + Twists[Random(Length(Twists))] + '.';
end;

initialization
  RegisterClasses([TDocInfo, THeading]);
end.
