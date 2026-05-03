// Main program. Imports Shapes directly; pulls in MathUtils
// transitively (Shapes itself `uses MathUtils`).
//
// Test from the command line:
//      brutop -r Demo.pas        -- compile and run
//      brutop Demo.pas           -- compile only; run with ./Demo
//
// Or in the IDE (`brutop` with no arguments): open Demo.pas, F9 to
// build, F5 to debug. Set a breakpoint on the for-loop body and
// double-click the watch row for `s2` — the active variant fields
// should be visible and the inactive ones hidden. Variables of an
// enum type display by name rather than ordinal.

program Demo;

uses Shapes;

var
  stats: TStat;
  s1, s2, s3: TShape;
  i: integer;

begin
  StatReset(stats);

  s1 := MakeSquare(1, 5);
  s2 := MakeRectangle(2, 4, 6);
  s3 := MakeTriangle(3, 8, 3);

  StatAdd(stats, ShapeArea(s1));
  StatAdd(stats, ShapeArea(s2));
  StatAdd(stats, ShapeArea(s3));

  writeln('--- shape areas ---');
  writeln('square(5)        area=', ShapeArea(s1));
  writeln('rectangle(4x6)   area=', ShapeArea(s2));
  writeln('triangle(8x3)    area=', ShapeArea(s3));

  writeln('--- stats ---');
  writeln('count=', stats.count, ' total=', stats.total, ' peak=', stats.peak);

  writeln('--- ad-hoc ---');
  for i := 1 to 4 do
    writeln('cube(', i, ')=', Cube(i))
end.
