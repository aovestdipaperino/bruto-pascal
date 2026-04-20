program FeatureShowcase;
{ Demonstrates every implemented Mini-Pascal feature }

label 99;

const
  MaxItems = 5;
  Pi = 3.14159265;
  Greeting = 'Hello';

type
  Color = (Red, Green, Blue);
  Percent = 0..100;
  IntArray = array[1..5] of integer;
  Matrix = array[1..3, 1..3] of integer;
  Point = record
    x, y: real;
  end;
  IntPtr = ^integer;
  Shape = record
    name: string;
    case kind: integer of
      1: (radius: integer);
      2: (width, height: integer);
  end;
  CharSet = set of integer;
  Table = record
    rows: array[1..3] of Point;
  end;

var
  nums: IntArray;
  mat: Matrix;
  pt: Point;
  tbl: Table;
  p1, p2: ^integer;
  circle, rect: Shape;
  palette: CharSet;
  c: Color;
  pct: Percent;
  i, j, total: integer;
  avg, r: real;
  s, t: string;
  ch: char;
  ok: boolean;
  code: integer;

{ Forward declaration for mutual recursion }
procedure Odd(n: integer); forward;

procedure Even(n: integer);
begin
  if n = 0 then
    writeln('  even(0) -> true')
  else
    Odd(n - 1)
end;

procedure Odd(n: integer);
begin
  if n = 0 then
    writeln('  odd(0) -> false')
  else
    Even(n - 1)
end;

{ Procedure with var parameter }
procedure Swap(var a, b: integer);
var tmp: integer;
begin
  tmp := a;
  a := b;
  b := tmp
end;

{ Function returning a value }
function Factorial(n: integer): integer;
begin
  if n <= 1 then
    Factorial := 1
  else
    Factorial := n * Factorial(n - 1)
end;

{ Procedure filling an array }
procedure FillSquares(var arr: IntArray; count: integer);
var i: integer;
begin
  for i := 1 to count do
    arr[i] := sqr(i)
end;

{ Function computing array sum }
function ArraySum(var arr: IntArray; count: integer): integer;
var i, s: integer;
begin
  s := 0;
  for i := 1 to count do
    s := s + arr[i];
  ArraySum := s
end;

begin
  { ── Constants and basic I/O ── }
  writeln('=== Mini-Pascal Feature Showcase ===');
  writeln;
  writeln(Greeting, ', World!');
  writeln('MaxItems = ', MaxItems, ', Pi = ', Pi);

  { ── Arithmetic builtins ── }
  writeln;
  writeln('--- Arithmetic ---');
  writeln('abs(-7) = ', abs(-7));
  writeln('sqr(6) = ', sqr(6));
  writeln('sqrt(144) = ', trunc(sqrt(144.0)));
  writeln('trunc(3.9) = ', trunc(3.9));
  writeln('round(3.5) = ', round(3.5));
  writeln('sin(0) = ', trunc(sin(0.0)), ', cos(0) = ', trunc(cos(0.0)));
  writeln('exp(0) = ', trunc(exp(0.0)), ', ln(1) = ', trunc(ln(1.0)));
  writeln('arctan(0) = ', trunc(arctan(0.0)));

  { ── Ordinal builtins ── }
  writeln;
  writeln('--- Ordinals ---');
  writeln('succ(5) = ', succ(5), ', pred(5) = ', pred(5));
  i := 10;
  inc(i);
  writeln('inc(10) = ', i);
  dec(i, 3);
  writeln('dec(11,3) = ', i);
  writeln('low(nums) = ', low(nums), ', high(nums) = ', high(nums));

  { ── String operations ── }
  writeln;
  writeln('--- Strings ---');
  s := 'Hello' + ' ' + 'Pascal!';
  writeln(s, ' (len=', length(s), ')');
  t := copy(s, 7, 7);
  writeln('copy = ', t);
  writeln('pos = ', pos('Pascal', s));
  writeln('upcase(a) = ', upcase('a'));
  t := concat('abc', 'DEF', 'ghi');
  writeln('concat = ', t);
  str(2026, t);
  writeln('str = ', t);
  val('42', i, code);
  writeln('val = ', i, ' (code=', code, ')');
  s := 'abcdef';
  delete(s, 3, 2);
  writeln('delete = ', s);
  s := 'Hello';
  insert(' World', s, 6);
  writeln('insert = ', s);
  writeln('ord(A) = ', ord('A'), ', chr(90) = ', chr(90));

  { ── Arrays and procedures ── }
  writeln;
  writeln('--- Arrays ---');
  FillSquares(nums, MaxItems);
  total := ArraySum(nums, MaxItems);
  write('Squares: ');
  for i := 1 to MaxItems do
    write(nums[i], ' ');
  writeln;
  writeln('Sum = ', total);
  avg := total / MaxItems;
  writeln('Avg = ', avg);

  { ── Multi-dimensional arrays ── }
  writeln;
  writeln('--- Multi-dim Arrays ---');
  for i := 1 to 3 do
    for j := 1 to 3 do
      mat[i, j] := i * 10 + j;
  writeln('mat[2,3] = ', mat[2, 3]);
  writeln('mat[3,1] = ', mat[3, 1]);

  { ── Records ── }
  writeln;
  writeln('--- Records ---');
  pt.x := avg;
  pt.y := Pi;
  writeln('Point = (', pt.x, ', ', pt.y, ')');

  { ── With statement ── }
  with pt do
  begin
    x := 100.0;
    y := 200.0
  end;
  writeln('with: (', pt.x, ', ', pt.y, ')');

  { ── Chained LValue: record containing array ── }
  writeln;
  writeln('--- Chained LValues ---');
  tbl.rows[2].x := 3.14;
  tbl.rows[2].y := 2.71;
  writeln('tbl.rows[2] = (', tbl.rows[2].x, ', ', tbl.rows[2].y, ')');

  { ── Heap pointers ── }
  writeln;
  writeln('--- Pointers ---');
  new(p1);
  new(p2);
  p1^ := 10;
  p2^ := 20;
  writeln('p1^ = ', p1^, ', p2^ = ', p2^);
  dispose(p2);
  dispose(p1);

  { ── Variant records ── }
  writeln;
  writeln('--- Variant Records ---');
  circle.name := 'Circle';
  circle.kind := 1;
  circle.radius := 10;
  writeln(circle.name, ': radius=', circle.radius);
  rect.name := 'Rect';
  rect.kind := 2;
  rect.width := 5;
  rect.height := 3;
  writeln(rect.name, ': ', rect.width, 'x', rect.height);

  { ── Enumerated types ── }
  writeln;
  writeln('--- Enums ---');
  c := Blue;
  writeln('Blue = ', c);
  writeln('succ(Green) = ', succ(Green));

  { ── Subrange types ── }
  pct := 75;
  writeln('Percent = ', pct);

  { ── Sets ── }
  writeln;
  writeln('--- Sets ---');
  palette := [1, 3, 5..9];
  writeln('5 in palette: ', 5 in palette);
  writeln('4 in palette: ', 4 in palette);
  include(palette, 4);
  writeln('after include(4): ', 4 in palette);
  exclude(palette, 5);
  writeln('after exclude(5): ', 5 in palette);

  { ── Case statement ── }
  writeln;
  writeln('--- Case ---');
  for i := 0 to 3 do
  begin
    case i of
      0: writeln('  ', i, ' -> zero');
      1, 2: writeln('  ', i, ' -> one or two');
    else
      writeln('  ', i, ' -> other')
    end
  end;

  { ── Control flow ── }
  writeln;
  writeln('--- Control Flow ---');

  { While }
  i := 1;
  while i <= 3 do
  begin
    write(i, ' ');
    i := i + 1
  end;
  writeln('(while)');

  { For downto }
  for i := 3 downto 1 do
    write(i, ' ');
  writeln('(downto)');

  { Repeat-until }
  i := 1;
  repeat
    write(i, ' ');
    i := i * 2
  until i > 10;
  writeln('(repeat)');

  { ── Goto/Label ── }
  writeln;
  writeln('--- Goto ---');
  i := 0;
  99: i := i + 1;
  if i < 3 then
    goto 99;
  writeln('goto count = ', i);

  { ── Forward declarations (mutual recursion) ── }
  writeln;
  writeln('--- Forward Decl ---');
  Even(4);
  Odd(3);

  { ── Var parameters ── }
  writeln;
  writeln('--- Var Params ---');
  i := 10;
  j := 20;
  Swap(i, j);
  writeln('After swap: i=', i, ' j=', j);

  { ── Functions ── }
  writeln;
  writeln('--- Functions ---');
  writeln('5! = ', Factorial(5));

  { ── Boolean expressions ── }
  writeln;
  writeln('--- Boolean ---');
  ok := (3 > 2) and (5 < 10);
  writeln('(3>2) and (5<10) = ', ok);
  ok := not false;
  writeln('not false = ', ok);
  ok := (1 = 1) or (2 = 3);
  writeln('(1=1) or (2=3) = ', ok);

  { ── Real arithmetic ── }
  writeln;
  writeln('--- Real ---');
  r := Pi * sqr(10.0);
  writeln('Area(r=10) = ', r);
  writeln('sqrt(2) = ', sqrt(2.0));

  writeln;
  writeln('=== All features OK ===')
end.
