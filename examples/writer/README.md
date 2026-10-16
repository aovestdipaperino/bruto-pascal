# Bruto Writer

A small word processor written in Free Vision and compiled by Bruto
Pascal. It is meant as a tour: the user interface is Free Vision's
Turbo Pascal `object` types (an application, menus, an editor, dialogs
and the file dialog), and the document logic behind it uses the parts of
FPC's Object Pascal that Bruto Pascal compiles as FPC does.

```
 File  Edit  Document  Window  Help
╔═[■]════════════════════ lighthouse (lighthouse.wri) ═════════════════════[↕]═╗
║# The Lig╔═[■]══════════════ Document properties ═══════════════════╗         ▲
║         ║                                                          ║         ▓
║The keepe║  Title        The Lighthouse                             ║ne       ▓
║hundred a║                                                          ║p.       ▓
║         ║  Author       A. Keeper                                  ║         ▓
║## The St║                                                          ║         ▓
║         ║               Genre             Tags                     ║         ▓
║Rain came║               ( ) Novel         [ ] Draft                ║         ▓
║tower sho║               ( ) Essay         [X] Reviewed             ║         ▓
║         ║               ( ) Poem          [ ] Final                ║         ▓
║## Mornin║               (*) Letter        [ ] Private              ║         ▓
║         ║               ( ) Notes         [X] Favourite            ║         ▓
║At dawn t║                                                          ║g:       ▓
║"The ligh║  Rate/word    0.125                                      ║         ▓
║         ║                                                          ║         ▓
║         ║  Rating       4                                          ║         ▓
║         ║                                                          ║         ▓
║         ║                   OK    ▄      Cancel  ▄                 ║         ▓
║         ║               ▀▀▀▀▀▀▀▀▀▀▀    ▀▀▀▀▀▀▀▀▀▀▀                 ║         ▓
║         ╚══════════════════════════════════════════════════════════╝         ▓
║                                                                              ▼
╚═══════ 1:1 ═════◄▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓►─┘
 F2 Save  F3 Open  F7 Stats  F8 Outline  F9 Properties  Alt-X Exit
```

## What it shows

The editor window holds the text; lines starting with `#` are headings.
The **Document** menu works on the front document:

- **Statistics** (F7) counts words, sentences and paragraphs, works out a
  Flesch readability score with the Math unit (`Mean`, `StdDev`,
  `MaxValue`, `Ceil`), and lists the most frequent words with fgl's
  generic `TFPGMap`. Words are found with sets of characters, and the
  reading time comes from an enumeration with explicit values
  (`rsAverage = 230`). A generic routine (`Clamp<T>`) keeps the score in
  range.
- **Outline** (F8) collects the headings into a `TCollection` of
  `THeading` items, iterated with `for ... in`.
- **Properties** (F9) edits the document's properties: a `TDocInfo`
  component with published properties of many kinds: strings, an
  enumeration, a set of tags (4 bytes, as FPC lays it out), a
  `Currency` rate, a `Variant` rating (a number of stars, a word, or
  Null) and the headings collection. Saving the document (F2) also saves
  them beside it, as `Name.meta`, with `TStream.WriteComponent`;
  opening it reads them back with `ReadComponent`.
- **Inspect** walks the properties through run-time type information
  (`GetPropList`, `GetPropValue`, `GetVariantProp`, `GetEnumName`) and
  shows the component's stream in FPC's text form
  (`ObjectBinaryToText`).
- **Invoice** prices the text per word in `Currency`, which is exact to
  four decimals and multiplies as FPC does, and formats it with
  `WriteStr`.
- **Export** writes plain text, HTML or Markdown through an `IExporter`
  interface: three reference-counted classes, chosen in a dialog that
  lists their own names.
- **Inspire me** picks a writing prompt with `Random` (FPC's Mersenne
  Twister, so a given `RandSeed` gives FPC's sequence).

Errors are exceptions: a rate that isn't a number raises SysUtils'
`EConvertError`, an invoice without a rate the program's own
`EWriterError`, and both end up in a message box.

```
 File  Edit  Document  Window  Help
┌───────────────────╔═[■]════════════════════ Inspect ═════════════════════[↑]═╗
│# The Lighthouse   ║Properties: The Lighthouse                                ▲
│                   ║==========================                                ■
│The keeper climbed ║Name      tkAString Document                              ▒
│hundred and twelve,║Tag       tkInt64   0                                     ▒
│                   ║Title     tkAString The Lighthouse                        ▒
│## The Storm       ║Author    tkAString A. Keeper                             ▒
│                   ║Genre     tkEnumeration gnLetter                          ▒
│Rain came from the ║Tags      tkSet     tgReviewed,tgFavourite                ▒
│tower shook! Would ║Rate      tkFloat   0.125                                 ▒
│                   ║Rating    tkVariant **** (4, Integer)                     ▒
│## Morning         ║Words     tkInteger 0                                     ▒
│                   ║Headings  tkClass   (THeadings)                           ▒
│At dawn the water w║Genre letter (ordinal 3); tags are a set of 4 bytes       ▒
│"The light held." T║                                                          ▒
│                   ║Stream (251 bytes):                                       ▒
│                   ║object Document: TDocInfo                                 ▒
│                   ║  Title = 'The Lighthouse'                                ▒
│                   ║  Author = 'A. Keeper'                                    ▒
│                   ║  Genre = gnLetter                                        ▒
│                   ║  Tags = [tgReviewed, tgFavourite]                        ▒
│                   ║  Rate =  1.2500000000000000E-001                         ▼
└───────────────────╚═══════ 1:1 ═════◄▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓►─┘
 F2 Save  F3 Open  F7 Stats  F8 Outline  F9 Properties  Alt-X Exit
```

## Building it

Free Vision isn't part of Bruto Pascal; it comes from
[FPC's sources](https://gitlab.com/freepascal.org/fpc/source) (the main
branch), which this repository has as an optional submodule in
`third_party/fpc`. A plain or recursive clone leaves it empty; fetch it
(a shallow checkout) when you want to build the demo, then point `-Fu`
at Free Vision and at `objects.pp`:

```sh
git submodule update --init --checkout -- third_party/fpc
brutop -Fu third_party/fpc/packages/fv/src \
       -Fu third_party/fpc/packages/rtl-extra/src/inc \
       -o writer examples/writer/writer.pas
./writer examples/writer/lighthouse.wri
```

`lighthouse.wri` is a sample document. Without an argument the program
opens a new one.

The same program builds with FPC 3.2.2, using the Free Vision units it
ships with (with Homebrew on an ARM Mac they are in
`/opt/homebrew/lib/fpc/3.2.2/units/aarch64-darwin/fv`):

```sh
fpc -Fu/opt/homebrew/lib/fpc/3.2.2/units/aarch64-darwin/fv writer.pas
```

## Checking it against FPC

`writercheck.pas` runs the document logic without the user interface, on
`lighthouse.wri`: statistics, invoice, outline, the properties report
and stream, the three exports, saving and reloading the properties, an
exception and two random prompts. Built with Bruto Pascal and with FPC
3.2.2, it prints the same text, and the files it writes (the text, HTML
and Markdown exports and the 253-byte `.meta` component stream) are
identical byte for byte.

```sh
brutop -r writercheck.pas
```

## A note on names

Free Vision's Objects unit declares its own `TObject` (an `object` type)
and `TStringList`, and StdDlg an `ExtractFileName` that drops the
extension. As in FPC, the last unit in a `uses` clause wins, so
`writer.pas` writes `Classes.TStringList` and `SysUtils.ExtractFileName`,
and keeps its classes in `writercore.pas`, which doesn't use Objects:
there `TObject` is the root class.

## Files

| File | |
|------|--|
| `writer.pas` | The Free Vision program |
| `writercore.pas` | The document logic (classes, RTTI, streaming, interfaces, generics, Variants, Currency) |
| `writercheck.pas` | The same logic run from the command line, to compare with FPC |
| `lighthouse.wri` | A sample document |
