{ Bruto Writer's document logic, without the user interface: the same
  output from Bruto Pascal and from FPC. }
program WriterCheck;

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Variants, WriterCore;

var
  Lines: TStringList;
  Info, Copy: TDocInfo;
  I: Integer;
  Written: string;
begin
  RandSeed := 42;
  Lines := TStringList.Create;
  Lines.LoadFromFile('lighthouse.wri');
  Info := TDocInfo.Create(nil);
  Info.Name := 'Lighthouse';
  Info.Title := 'The Lighthouse';
  Info.Author := 'A. Keeper';
  Info.Genre := gnLetter;
  Info.Tags := [tgReviewed, tgFavourite];
  Info.Rate := 0.125;
  FindHeadings(Lines, Info);
  Write(StatisticsReport(Info, Lines));
  WriteLn;
  Write(InvoiceReport(Info, Lines, 21));
  WriteLn;
  Write(OutlineReport(Info));
  WriteLn;
  Info.Rating := 4;
  Write(PropertiesReport(Info));
  WriteLn;
  Write(ExportersReport);
  for I := 0 to ExporterCount - 1 do
  begin
    Written := ExportDocument(Exporter(I), Info, Lines, 'lighthouse.wri');
    WriteLn(ExtractFileName(Written), ' written');
  end;
  SaveInfo(Info, 'lighthouse.wri');
  Copy := TDocInfo.Create(nil);
  Copy.Rating := 'unread';
  WriteLn('loaded ', LoadInfo(Copy, 'lighthouse.wri'), ': ', Copy.Title, ' by ', Copy.Author,
    ', ', Copy.Headings.Count, ' headings, rate ', CurrToStr(Copy.Rate), ', rating ',
    VarToStr(Copy.Rating));
  Info.Rate := 0;
  try
    InvoiceReport(Info, Lines, 21);
  except
    on E: EWriterError do WriteLn('caught ', E.ClassName, ': ', E.Message);
  end;
  WriteLn(Inspiration);
  WriteLn(Inspiration);
  Copy.Free;
  Info.Free;
  Lines.Free;
end.
