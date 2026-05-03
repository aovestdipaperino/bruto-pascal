program LongDemo;
{ Long-form bruto-pascal demo. Designed to take a few seconds to
  compile so the IDE's progress dialog goes through the Compiling /
  Linking / Generating-debug-info phases. Built around patterns
  proven to work in SAMPLE.PAS — many small procedures, lots of
  arithmetic, no exotic features that the parser hasn't seen. }

const
  Pi  = 3.14159265358979;
  E   = 2.71828182845904;
  Phi = 1.61803398874989;

type
  Color   = (Red, Green, Blue, Yellow, Cyan, Magenta);
  Day     = (Mon, Tue, Wed, Thu, Fri, Sat, Sun);
  Percent = 0..100;
  IntArr  = array[1..10] of integer;
  RealArr = array[1..10] of real;
  Matrix  = array[1..3, 1..3] of integer;
  Point   = record
    x, y: real;
  end;
  IntSet  = set of integer;
  IntPtr  = ^integer;

var
  i, j, k, n, total: integer;
  acc: real;
  arr: IntArr;
  rarr: RealArr;
  mat: Matrix;
  pt: Point;
  ip: IntPtr;
  c1, c2: Color;
  d1: Day;
  pct: Percent;
  setA, setB, setC: IntSet;
  s, t: string;
  ok: boolean;

{ ── small builders & helpers (~30 procedures) ── }

procedure Header(name: string);
begin
  writeln;
  writeln('=== ', name, ' ===')
end;

procedure ReportInt(name: string; v: integer);
begin
  writeln('  ', name, ' = ', v)
end;

procedure ReportReal(name: string; v: real);
begin
  writeln('  ', name, ' = ', v)
end;

procedure ReportBool(name: string; v: boolean);
begin
  writeln('  ', name, ' = ', v)
end;

procedure ReportString(name: string; v: string);
begin
  writeln('  ', name, ' = ', v)
end;

function IntMin(a, b: integer): integer;
begin
  if a < b then IntMin := a else IntMin := b
end;

function IntMax(a, b: integer): integer;
begin
  if a > b then IntMax := a else IntMax := b
end;

function IntAbs(n: integer): integer;
begin
  if n < 0 then IntAbs := -n else IntAbs := n
end;

function IntSign(n: integer): integer;
begin
  if n > 0 then IntSign := 1
  else if n < 0 then IntSign := -1
  else IntSign := 0
end;

function Square(n: integer): integer;
begin
  Square := n * n
end;

function Cube(n: integer): integer;
begin
  Cube := n * n * n
end;

function Quad(n: integer): integer;
begin
  Quad := n * n * n * n
end;

function Sum1ToN(n: integer): integer;
var k, s: integer;
begin
  s := 0;
  for k := 1 to n do s := s + k;
  Sum1ToN := s
end;

function SumSq(n: integer): integer;
var k, s: integer;
begin
  s := 0;
  for k := 1 to n do s := s + k * k;
  SumSq := s
end;

function SumCube(n: integer): integer;
var k, s: integer;
begin
  s := 0;
  for k := 1 to n do s := s + k * k * k;
  SumCube := s
end;

function Factorial(n: integer): integer;
begin
  if n <= 1 then Factorial := 1
  else Factorial := n * Factorial(n - 1)
end;

function Fibonacci(n: integer): integer;
begin
  if n < 2 then Fibonacci := n
  else Fibonacci := Fibonacci(n - 1) + Fibonacci(n - 2)
end;

function GCD(a, b: integer): integer;
begin
  if b = 0 then GCD := a
  else GCD := GCD(b, a mod b)
end;

function LCM(a, b: integer): integer;
begin
  LCM := (a * b) div GCD(a, b)
end;

function PowerInt(base, exp: integer): integer;
var k, r: integer;
begin
  r := 1;
  for k := 1 to exp do r := r * base;
  PowerInt := r
end;

function PowerReal(base: real; exp: integer): real;
var k: integer; r: real;
begin
  r := 1.0;
  for k := 1 to exp do r := r * base;
  PowerReal := r
end;

function IsPrime(n: integer): boolean;
var k: integer; result: boolean;
begin
  if n < 2 then result := false
  else if n = 2 then result := true
  else if (n mod 2) = 0 then result := false
  else
  begin
    result := true;
    k := 3;
    while (k * k <= n) and result do
    begin
      if (n mod k) = 0 then result := false;
      k := k + 2
    end
  end;
  IsPrime := result
end;

function IsEven(n: integer): boolean;
begin
  IsEven := (n mod 2) = 0
end;

function IsOdd(n: integer): boolean;
begin
  IsOdd := (n mod 2) <> 0
end;

function CountPrimes(lo, hi: integer): integer;
var k, c: integer;
begin
  c := 0;
  for k := lo to hi do
    if IsPrime(k) then c := c + 1;
  CountPrimes := c
end;

function CountDivisors(n: integer): integer;
var k, c: integer;
begin
  c := 0;
  for k := 1 to n do
    if (n mod k) = 0 then c := c + 1;
  CountDivisors := c
end;

function MaxDivisor(n: integer): integer;
var k, m: integer;
begin
  m := 1;
  for k := 2 to n - 1 do
    if (n mod k) = 0 then m := k;
  MaxDivisor := m
end;

function DigitSum(n: integer): integer;
var s: integer;
begin
  s := 0;
  while n > 0 do
  begin
    s := s + (n mod 10);
    n := n div 10
  end;
  DigitSum := s
end;

function DigitCount(n: integer): integer;
var c: integer;
begin
  c := 0;
  if n = 0 then DigitCount := 1
  else
  begin
    while n > 0 do
    begin
      c := c + 1;
      n := n div 10
    end;
    DigitCount := c
  end
end;

function ReverseDigits(n: integer): integer;
var r: integer;
begin
  r := 0;
  while n > 0 do
  begin
    r := r * 10 + (n mod 10);
    n := n div 10
  end;
  ReverseDigits := r
end;

function IsPalindrome(n: integer): boolean;
begin
  IsPalindrome := n = ReverseDigits(n)
end;

function CollatzSteps(n: integer): integer;
var c: integer;
begin
  c := 0;
  while n > 1 do
  begin
    if (n mod 2) = 0 then n := n div 2
    else n := 3 * n + 1;
    c := c + 1
  end;
  CollatzSteps := c
end;

function PowerOfTwo(p: integer): integer;
var k, r: integer;
begin
  r := 1;
  for k := 1 to p do r := r * 2;
  PowerOfTwo := r
end;

function CountBits(n: integer): integer;
var c: integer;
begin
  c := 0;
  while n > 0 do
  begin
    if (n mod 2) = 1 then c := c + 1;
    n := n div 2
  end;
  CountBits := c
end;

function HighestBit(n: integer): integer;
var c: integer;
begin
  c := 0;
  while n > 0 do
  begin
    c := c + 1;
    n := n div 2
  end;
  HighestBit := c
end;

function NthFib(n: integer): integer;
var k, a, b, t: integer;
begin
  a := 0; b := 1;
  for k := 1 to n do
  begin
    t := a + b;
    a := b;
    b := t
  end;
  NthFib := a
end;

function NthTriangle(n: integer): integer;
begin
  NthTriangle := (n * (n + 1)) div 2
end;

function NthPentagonal(n: integer): integer;
begin
  NthPentagonal := (n * (3 * n - 1)) div 2
end;

function NthHexagonal(n: integer): integer;
begin
  NthHexagonal := n * (2 * n - 1)
end;

function FloatToInt(r: real): integer;
begin
  FloatToInt := trunc(r)
end;

function RealMin(a, b: real): real;
begin
  if a < b then RealMin := a else RealMin := b
end;

function RealMax(a, b: real): real;
begin
  if a > b then RealMax := a else RealMax := b
end;

function RealAbs(r: real): real;
begin
  if r < 0.0 then RealAbs := 0.0 - r else RealAbs := r
end;

function HypotenuseSq(a, b: real): real;
begin
  HypotenuseSq := a * a + b * b
end;

function Hypotenuse(a, b: real): real;
begin
  Hypotenuse := sqrt(a * a + b * b)
end;

function CircleArea(r: real): real;
begin
  CircleArea := 3.14159265358979 * r * r
end;

function CircleCircum(r: real): real;
begin
  CircleCircum := 2.0 * 3.14159265358979 * r
end;

function SphereVolume(r: real): real;
begin
  SphereVolume := (4.0 / 3.0) * 3.14159265358979 * r * r * r
end;

function SphereSurface(r: real): real;
begin
  SphereSurface := 4.0 * 3.14159265358979 * r * r
end;

function CylinderVolume(r, h: real): real;
begin
  CylinderVolume := 3.14159265358979 * r * r * h
end;

function CylinderSurface(r, h: real): real;
begin
  CylinderSurface := 2.0 * 3.14159265358979 * r * (r + h)
end;

function ConeVolume(r, h: real): real;
begin
  ConeVolume := (1.0 / 3.0) * 3.14159265358979 * r * r * h
end;

function TriangleArea(b, h: real): real;
begin
  TriangleArea := 0.5 * b * h
end;

function HeronArea(a, b, c: real): real;
var s: real;
begin
  s := (a + b + c) / 2.0;
  HeronArea := sqrt(s * (s - a) * (s - b) * (s - c))
end;

function CelsiusToF(c: real): real;
begin
  CelsiusToF := c * 9.0 / 5.0 + 32.0
end;

function FtoCelsius(f: real): real;
begin
  FtoCelsius := (f - 32.0) * 5.0 / 9.0
end;

function MphToKmh(m: real): real;
begin
  MphToKmh := m * 1.609344
end;

function KmhToMph(k: real): real;
begin
  KmhToMph := k / 1.609344
end;

procedure FillSeq(var arr: IntArr);
var k: integer;
begin
  for k := 1 to 10 do arr[k] := k
end;

procedure FillSquares(var arr: IntArr);
var k: integer;
begin
  for k := 1 to 10 do arr[k] := Square(k)
end;

procedure FillCubes(var arr: IntArr);
var k: integer;
begin
  for k := 1 to 10 do arr[k] := Cube(k)
end;

procedure FillReverse(var arr: IntArr);
var k: integer;
begin
  for k := 1 to 10 do arr[k] := 11 - k
end;

procedure FillRand(var arr: IntArr);
begin
  arr[1] := 7;  arr[2] := 3; arr[3] := 9; arr[4] := 1; arr[5] := 8;
  arr[6] := 5;  arr[7] := 2; arr[8] := 6; arr[9] := 4; arr[10] := 0
end;

procedure FillFib(var arr: IntArr);
var k: integer;
begin
  for k := 1 to 10 do arr[k] := NthFib(k)
end;

procedure FillTriangles(var arr: IntArr);
var k: integer;
begin
  for k := 1 to 10 do arr[k] := NthTriangle(k)
end;

procedure FillPrimesUpTo(var arr: IntArr);
var k, idx: integer;
begin
  idx := 0;
  k := 2;
  while idx < 10 do
  begin
    if IsPrime(k) then
    begin
      idx := idx + 1;
      arr[idx] := k
    end;
    k := k + 1
  end
end;

function ArrSum(var arr: IntArr): integer;
var k, s: integer;
begin
  s := 0;
  for k := 1 to 10 do s := s + arr[k];
  ArrSum := s
end;

function ArrMin(var arr: IntArr): integer;
var k, m: integer;
begin
  m := arr[1];
  for k := 2 to 10 do if arr[k] < m then m := arr[k];
  ArrMin := m
end;

function ArrMax(var arr: IntArr): integer;
var k, m: integer;
begin
  m := arr[1];
  for k := 2 to 10 do if arr[k] > m then m := arr[k];
  ArrMax := m
end;

function ArrProd(var arr: IntArr): integer;
var k, p: integer;
begin
  p := 1;
  for k := 1 to 10 do p := p * arr[k];
  ArrProd := p
end;

function ArrCountPositive(var arr: IntArr): integer;
var k, c: integer;
begin
  c := 0;
  for k := 1 to 10 do if arr[k] > 0 then c := c + 1;
  ArrCountPositive := c
end;

function ArrCountEven(var arr: IntArr): integer;
var k, c: integer;
begin
  c := 0;
  for k := 1 to 10 do if IsEven(arr[k]) then c := c + 1;
  ArrCountEven := c
end;

procedure ArrPrint(var arr: IntArr);
var k: integer;
begin
  write('  [');
  for k := 1 to 10 do
  begin
    write(arr[k]);
    if k < 10 then write(', ')
  end;
  writeln(']')
end;

procedure ArrCopy(var src, dst: IntArr);
var k: integer;
begin
  for k := 1 to 10 do dst[k] := src[k]
end;

procedure ArrZero(var arr: IntArr);
var k: integer;
begin
  for k := 1 to 10 do arr[k] := 0
end;

procedure ArrIncBy(var arr: IntArr; delta: integer);
var k: integer;
begin
  for k := 1 to 10 do arr[k] := arr[k] + delta
end;

procedure ArrScale(var arr: IntArr; factor: integer);
var k: integer;
begin
  for k := 1 to 10 do arr[k] := arr[k] * factor
end;

procedure ArrSquare(var arr: IntArr);
var k: integer;
begin
  for k := 1 to 10 do arr[k] := arr[k] * arr[k]
end;

procedure ArrReverse(var arr: IntArr);
var k, m, tmp: integer;
begin
  for k := 1 to 5 do
  begin
    m := 11 - k;
    tmp := arr[k];
    arr[k] := arr[m];
    arr[m] := tmp
  end
end;

procedure BubbleSort(var arr: IntArr);
var i, j, tmp: integer;
begin
  for i := 1 to 9 do
    for j := 1 to 10 - i do
      if arr[j] > arr[j + 1] then
      begin
        tmp := arr[j];
        arr[j] := arr[j + 1];
        arr[j + 1] := tmp
      end
end;

procedure InsertionSort(var arr: IntArr);
var i, j, key: integer;
begin
  for i := 2 to 10 do
  begin
    key := arr[i];
    j := i - 1;
    while (j >= 1) and (arr[j] > key) do
    begin
      arr[j + 1] := arr[j];
      j := j - 1
    end;
    arr[j + 1] := key
  end
end;

procedure SelectionSort(var arr: IntArr);
var i, j, m, tmp: integer;
begin
  for i := 1 to 9 do
  begin
    m := i;
    for j := i + 1 to 10 do
      if arr[j] < arr[m] then m := j;
    if m <> i then
    begin
      tmp := arr[i];
      arr[i] := arr[m];
      arr[m] := tmp
    end
  end
end;

function LinSearch(var arr: IntArr; target: integer): integer;
var k, found: integer;
begin
  found := 0;
  k := 1;
  while (k <= 10) and (found = 0) do
  begin
    if arr[k] = target then found := k;
    k := k + 1
  end;
  LinSearch := found
end;

function BinSearch(var arr: IntArr; target: integer): integer;
var lo, hi, mid, found: integer;
begin
  found := 0;
  lo := 1; hi := 10;
  while (lo <= hi) and (found = 0) do
  begin
    mid := (lo + hi) div 2;
    if arr[mid] = target then found := mid
    else if arr[mid] < target then lo := mid + 1
    else hi := mid - 1
  end;
  BinSearch := found
end;

procedure MatIdent(var m: Matrix);
var i, j: integer;
begin
  for i := 1 to 3 do
    for j := 1 to 3 do
      if i = j then m[i, j] := 1 else m[i, j] := 0
end;

procedure MatSeq(var m: Matrix);
var i, j, c: integer;
begin
  c := 1;
  for i := 1 to 3 do
    for j := 1 to 3 do
    begin
      m[i, j] := c;
      c := c + 1
    end
end;

procedure MatScale(var m: Matrix; k: integer);
var i, j: integer;
begin
  for i := 1 to 3 do
    for j := 1 to 3 do
      m[i, j] := m[i, j] * k
end;

procedure MatAdd(var a, b, c: Matrix);
var i, j: integer;
begin
  for i := 1 to 3 do
    for j := 1 to 3 do
      c[i, j] := a[i, j] + b[i, j]
end;

procedure MatMul(var a, b, c: Matrix);
var i, j, k, s: integer;
begin
  for i := 1 to 3 do
    for j := 1 to 3 do
    begin
      s := 0;
      for k := 1 to 3 do s := s + a[i, k] * b[k, j];
      c[i, j] := s
    end
end;

procedure MatTranspose(var src, dst: Matrix);
var i, j: integer;
begin
  for i := 1 to 3 do
    for j := 1 to 3 do
      dst[j, i] := src[i, j]
end;

function MatTrace(var m: Matrix): integer;
var i, s: integer;
begin
  s := 0;
  for i := 1 to 3 do s := s + m[i, i];
  MatTrace := s
end;

procedure MatPrint(var m: Matrix);
var i, j: integer;
begin
  for i := 1 to 3 do
  begin
    write('  [');
    for j := 1 to 3 do
    begin
      write(m[i, j]:6);
      if j < 3 then write(' ')
    end;
    writeln(']')
  end
end;

function AltSign(k: integer): real;
begin
  if (k mod 2) = 0 then AltSign := 1.0
  else AltSign := 0.0 - 1.0
end;

procedure HarmonicSeries(n: integer);
var k: integer; s: real;
begin
  s := 0.0;
  for k := 1 to n do s := s + 1.0 / (k * 1.0);
  ReportReal('Harmonic', s)
end;

procedure GeometricSeries(r: real; n: integer);
var k: integer; s: real;
begin
  s := 0.0;
  for k := 0 to n do s := s + PowerReal(r, k);
  ReportReal('Geometric', s)
end;

procedure ETaylor(n: integer);
var k: integer; s: real;
begin
  s := 0.0;
  for k := 0 to n do s := s + 1.0 / Factorial(k);
  ReportReal('e via Taylor', s)
end;

procedure PiLeibniz(n: integer);
var k: integer; s: real;
begin
  s := 0.0;
  for k := 0 to n do s := s + AltSign(k) / (2.0 * k + 1.0);
  ReportReal('pi/4 via Leibniz', s);
  ReportReal('pi via Leibniz',  s * 4.0)
end;

procedure SinTaylor(x: real; n: integer);
var k: integer; s, term: real;
begin
  s := 0.0;
  for k := 0 to n do
  begin
    term := AltSign(k) * PowerReal(x, 2 * k + 1) / (Factorial(2 * k + 1) * 1.0);
    s := s + term
  end;
  ReportReal('sin(Taylor)', s)
end;

procedure CosTaylor(x: real; n: integer);
var k: integer; s, term: real;
begin
  s := 0.0;
  for k := 0 to n do
  begin
    term := AltSign(k) * PowerReal(x, 2 * k) / (Factorial(2 * k) * 1.0);
    s := s + term
  end;
  ReportReal('cos(Taylor)', s)
end;

procedure ExpTaylor(x: real; n: integer);
var k: integer; s: real;
begin
  s := 0.0;
  for k := 0 to n do
    s := s + PowerReal(x, k) / (Factorial(k) * 1.0);
  ReportReal('exp(Taylor)', s)
end;

procedure DescribeSet(name: string; s: IntSet);
var k: integer; first: boolean;
begin
  write('  ', name, ' = [');
  first := true;
  for k := 0 to 31 do
    if k in s then
    begin
      if not first then write(', ');
      write(k);
      first := false
    end;
  writeln(']')
end;

function SetSize(s: IntSet): integer;
var k, c: integer;
begin
  c := 0;
  for k := 0 to 31 do
    if k in s then c := c + 1;
  SetSize := c
end;

{ ── main ── }

begin
  writeln('====================================');
  writeln('  bruto-pascal long-form demo');
  writeln('====================================');

  Header('Constants');
  ReportReal('Pi',   Pi);
  ReportReal('E',    E);
  ReportReal('Phi',  Phi);

  Header('Arithmetic builtins');
  ReportInt('abs(-7)',     abs(-7));
  ReportInt('sqr(6)',      sqr(6));
  ReportReal('sqrt(144)',  sqrt(144.0));
  ReportInt('trunc(3.9)',  trunc(3.9));
  ReportInt('round(3.5)',  round(3.5));
  ReportInt('round(-3.5)', round(0.0 - 3.5));
  ReportBool('odd(7)',     odd(7));
  ReportBool('odd(8)',     odd(8));
  ReportReal('sin(0)',     sin(0.0));
  ReportReal('cos(0)',     cos(0.0));
  ReportReal('exp(0)',     exp(0.0));
  ReportReal('ln(1)',      ln(1.0));
  ReportReal('arctan(0)',  arctan(0.0));
  ReportInt('IntMin(5,3)', IntMin(5, 3));
  ReportInt('IntMax(5,3)', IntMax(5, 3));
  ReportInt('IntAbs(-9)',  IntAbs(-9));
  ReportInt('IntSign(-7)', IntSign(-7));
  ReportInt('IntSign(0)',  IntSign(0));
  ReportInt('IntSign(7)',  IntSign(7));
  ReportInt('Square(11)',  Square(11));
  ReportInt('Cube(4)',     Cube(4));
  ReportInt('Quad(3)',     Quad(3));

  Header('Series sums');
  ReportInt('Sum1ToN(50)', Sum1ToN(50));
  ReportInt('SumSq(10)',   SumSq(10));
  ReportInt('SumCube(8)',  SumCube(8));

  Header('Number theory');
  for n := 1 to 10 do writeln('  ', n, '! = ', Factorial(n));
  for n := 0 to 14 do write(Fibonacci(n), ' ');
  writeln;
  ReportInt('NthFib(20)',     NthFib(20));
  ReportInt('NthTriangle(8)', NthTriangle(8));
  ReportInt('Pentagonal(5)',  NthPentagonal(5));
  ReportInt('Hexagonal(7)',   NthHexagonal(7));
  ReportInt('GCD(48,18)',     GCD(48, 18));
  ReportInt('LCM(4,6)',       LCM(4, 6));
  ReportInt('PowerInt(2,10)', PowerInt(2, 10));
  ReportInt('PowerOfTwo(8)',  PowerOfTwo(8));
  ReportInt('CountPrimes(0,30)', CountPrimes(0, 30));
  ReportInt('CountPrimes(0,100)', CountPrimes(0, 100));
  ReportInt('CountDivisors(72)', CountDivisors(72));
  ReportInt('MaxDivisor(72)',    MaxDivisor(72));
  ReportInt('DigitSum(12345)',   DigitSum(12345));
  ReportInt('DigitCount(0)',     DigitCount(0));
  ReportInt('DigitCount(99)',    DigitCount(99));
  ReportInt('DigitCount(99999)', DigitCount(99999));
  ReportInt('Reverse(1234)',     ReverseDigits(1234));
  ReportBool('Palindrome(121)',  IsPalindrome(121));
  ReportBool('Palindrome(123)',  IsPalindrome(123));
  ReportInt('Collatz(7)',        CollatzSteps(7));
  ReportInt('Collatz(27)',       CollatzSteps(27));
  ReportInt('CountBits(0)',      CountBits(0));
  ReportInt('CountBits(7)',      CountBits(7));
  ReportInt('HighestBit(255)',   HighestBit(255));

  Header('Real arithmetic');
  ReportReal('CelsiusToF(100)', CelsiusToF(100.0));
  ReportReal('FtoCelsius(32)',  FtoCelsius(32.0));
  ReportReal('FtoCelsius(212)', FtoCelsius(212.0));
  ReportReal('MphToKmh(60)',    MphToKmh(60.0));
  ReportReal('KmhToMph(100)',   KmhToMph(100.0));
  ReportReal('CircleArea(10)',  CircleArea(10.0));
  ReportReal('CircleCirc(10)',  CircleCircum(10.0));
  ReportReal('SphereVol(5)',    SphereVolume(5.0));
  ReportReal('SphereSurf(5)',   SphereSurface(5.0));
  ReportReal('CylVol(3,7)',     CylinderVolume(3.0, 7.0));
  ReportReal('CylSurf(3,7)',    CylinderSurface(3.0, 7.0));
  ReportReal('ConeVol(3,7)',    ConeVolume(3.0, 7.0));
  ReportReal('TriArea(3,4)',    TriangleArea(3.0, 4.0));
  ReportReal('Heron(3,4,5)',    HeronArea(3.0, 4.0, 5.0));
  ReportReal('HypotSq(3,4)',    HypotenuseSq(3.0, 4.0));
  ReportReal('Hypot(3,4)',      Hypotenuse(3.0, 4.0));
  ReportReal('RealMin(3.5,2.7)', RealMin(3.5, 2.7));
  ReportReal('RealMax(3.5,2.7)', RealMax(3.5, 2.7));
  ReportReal('RealAbs(-9.5)',    RealAbs(0.0 - 9.5));

  Header('Series');
  HarmonicSeries(50);
  HarmonicSeries(200);
  GeometricSeries(0.5, 20);
  ETaylor(15);
  PiLeibniz(20);
  SinTaylor(Pi / 6.0, 8);
  SinTaylor(Pi / 4.0, 8);
  SinTaylor(Pi / 2.0, 8);
  CosTaylor(0.0, 8);
  CosTaylor(Pi / 4.0, 8);
  CosTaylor(Pi / 2.0, 8);
  ExpTaylor(0.0, 12);
  ExpTaylor(1.0, 12);
  ExpTaylor(2.0, 12);

  Header('Arrays');
  FillSeq(arr);
  ArrPrint(arr);
  ReportInt('sum',     ArrSum(arr));
  ReportInt('min',     ArrMin(arr));
  ReportInt('max',     ArrMax(arr));
  ReportInt('product', ArrProd(arr));
  ReportInt('positive count', ArrCountPositive(arr));
  ReportInt('even count',     ArrCountEven(arr));
  FillSquares(arr);
  ArrPrint(arr);
  FillCubes(arr);
  ArrPrint(arr);
  FillFib(arr);
  ArrPrint(arr);
  FillTriangles(arr);
  ArrPrint(arr);
  FillPrimesUpTo(arr);
  ArrPrint(arr);
  FillReverse(arr);
  ArrPrint(arr);
  ArrReverse(arr);
  writeln('  after reverse:');
  ArrPrint(arr);
  ArrIncBy(arr, 100);
  writeln('  after +100:');
  ArrPrint(arr);
  ArrScale(arr, 2);
  writeln('  after *2:');
  ArrPrint(arr);
  ArrZero(arr);
  writeln('  after zero:');
  ArrPrint(arr);

  Header('Sorting');
  FillRand(arr);
  writeln('  bubble before:');
  ArrPrint(arr);
  BubbleSort(arr);
  writeln('  after:');
  ArrPrint(arr);
  FillReverse(arr);
  writeln('  insertion before:');
  ArrPrint(arr);
  InsertionSort(arr);
  writeln('  after:');
  ArrPrint(arr);
  FillRand(arr);
  writeln('  selection before:');
  ArrPrint(arr);
  SelectionSort(arr);
  writeln('  after:');
  ArrPrint(arr);

  Header('Searching');
  for i := 1 to 10 do arr[i] := i * 3;
  ArrPrint(arr);
  for i := 0 to 30 do
    if (i mod 5) = 0 then
      writeln('  linear(', i, ') -> ', LinSearch(arr, i));
  for i := 3 to 27 do
    if (i mod 6) = 0 then
      writeln('  binary(', i, ') -> ', BinSearch(arr, i));

  Header('Matrix ops');
  MatSeq(mat);
  writeln('  seq:');
  MatPrint(mat);
  MatIdent(mat);
  writeln('  identity:');
  MatPrint(mat);
  MatSeq(mat);
  MatScale(mat, 3);
  writeln('  seq * 3:');
  MatPrint(mat);
  MatSeq(mat);
  ReportInt('trace', MatTrace(mat));

  Header('Records / with');
  pt.x := 1.0;
  pt.y := 2.0;
  writeln('  pt = (', pt.x, ', ', pt.y, ')');
  with pt do
  begin
    x := x * 10.0;
    y := y * 10.0
  end;
  writeln('  after with*10: (', pt.x, ', ', pt.y, ')');

  Header('Pointers');
  new(ip);
  ip^ := 42;
  writeln('  ip^ = ', ip^);
  ip^ := ip^ * 2;
  writeln('  doubled = ', ip^);
  dispose(ip);

  Header('Enums and subranges');
  c1 := Red;
  c2 := Magenta;
  ReportInt('ord(Red)',     ord(c1));
  ReportInt('ord(Magenta)', ord(c2));
  ReportInt('succ(Green)',  ord(succ(Green)));
  d1 := Wed;
  ReportInt('ord(Wed)',     ord(d1));
  pct := 75;
  ReportInt('pct',          pct);

  Header('Sets');
  setA := [1, 3, 5, 7, 9, 11, 13];
  setB := [2..6];
  setC := setA + setB;
  DescribeSet('A',     setA);
  DescribeSet('B',     setB);
  DescribeSet('A+B',   setC);
  setC := setA - setB;
  DescribeSet('A-B',   setC);
  setC := setA * setB;
  DescribeSet('A*B',   setC);
  ReportInt('size(A)', SetSize(setA));
  ReportInt('size(B)', SetSize(setB));
  setA := [];
  for i := 0 to 16 do
    if (i mod 3) = 0 then include(setA, i);
  DescribeSet('mult of 3', setA);
  setB := [];
  for i := 0 to 16 do
    if (i mod 4) = 0 then include(setB, i);
  DescribeSet('mult of 4', setB);
  setC := setA * setB;
  DescribeSet('A*B (mult 12)', setC);

  Header('Case statement');
  for n := 0 to 8 do
  begin
    write('  ', n, ' -> ');
    case n of
      0:    writeln('zero');
      1, 2: writeln('one or two');
      3..5: writeln('three to five');
      6, 7: writeln('six or seven')
    else
      writeln('other')
    end
  end;

  Header('Boolean');
  ok := (3 > 2) and (5 < 10);
  ReportBool('and', ok);
  ok := not false;
  ReportBool('not', ok);
  ok := (1 = 1) or (2 = 3);
  ReportBool('or',  ok);
  ok := (3 > 5) and (10 = 10);
  ReportBool('false-and', ok);
  ok := (3 < 5) or (10 = 11);
  ReportBool('true-or',   ok);

  Header('String operations');
  s := 'Hello' + ' ' + 'Pascal!';
  ReportString('s', s);
  ReportInt('length', length(s));
  t := copy(s, 7, 6);
  ReportString('copy', t);
  ReportInt('pos(Pascal)', pos('Pascal', s));
  writeln('  upcase(a) = ', upcase('a'));
  t := concat('one', 'two', 'three');
  ReportString('concat', t);
  str(2026, t);
  ReportString('str(2026)', t);
  s := 'abcdef';
  delete(s, 3, 2);
  ReportString('delete', s);
  s := 'Hello';
  insert(' World', s, 6);
  ReportString('insert', s);

  Header('Stress');
  total := 0;
  for i := 1 to 30 do
    for j := 1 to 30 do
      for k := 1 to 30 do
        if (i + j + k) = 50 then total := total + 1;
  ReportInt('triples summing 50', total);
  total := 0;
  for n := 1 to 200 do
    if IsPrime(n) then total := total + 1;
  ReportInt('primes up to 200', total);
  total := 0;
  for n := 0 to 30 do
    total := total + Fibonacci(IntMin(n, 20));
  ReportInt('fibs total', total);

  Header('Times tables');
  for i := 1 to 12 do
  begin
    write('  ');
    for j := 1 to 12 do write((i * j):5);
    writeln
  end;

  Header('Triangle of squares');
  for i := 1 to 15 do
  begin
    write('  ');
    for j := 1 to i do write(Square(j):5);
    writeln
  end;

  Header('Fibonacci tableau');
  for i := 0 to 19 do
    writeln('  fib(', i:2, ') = ', NthFib(i));

  Header('Factorial tableau');
  for i := 0 to 12 do
    writeln('  ', i:2, '! = ', Factorial(i));

  Header('Prime sieve up to 100');
  for i := 2 to 100 do
    if IsPrime(i) then write(i, ' ');
  writeln;

  Header('Harmonic sums');
  for i := 1 to 10 do
  begin
    acc := 0.0;
    for j := 1 to i * 10 do acc := acc + 1.0 / (j * 1.0);
    writeln('  H(', (i * 10):3, ') = ', acc)
  end;

  Header('Geometric sums');
  for i := 1 to 10 do
  begin
    acc := 0.0;
    for j := 0 to i * 5 do acc := acc + PowerReal(0.7, j);
    writeln('  G(', (i * 5):3, ') = ', acc)
  end;

  Header('Approx pi');
  for i := 1 to 6 do
  begin
    acc := 0.0;
    for j := 0 to i * 50 do
      acc := acc + AltSign(j) / (2.0 * j + 1.0);
    writeln('  Leibniz(', (i * 50):4, ') -> ', acc * 4.0)
  end;

  Header('Approx e');
  for i := 1 to 6 do
  begin
    acc := 0.0;
    for j := 0 to i * 2 do
      acc := acc + 1.0 / (Factorial(j) * 1.0);
    writeln('  Taylor(', (i * 2):3, ') -> ', acc)
  end;

  Header('Sin/cos table');
  for i := 0 to 12 do
  begin
    acc := i * (3.14159265358979 / 6.0);
    writeln('  ', acc, '   sin = ', sin(acc), '   cos = ', cos(acc))
  end;

  Header('Triangular numbers');
  for i := 1 to 15 do
    writeln('  T(', i:3, ') = ', NthTriangle(i));

  Header('Pentagonal numbers');
  for i := 1 to 15 do
    writeln('  P(', i:3, ') = ', NthPentagonal(i));

  Header('Hexagonal numbers');
  for i := 1 to 15 do
    writeln('  H(', i:3, ') = ', NthHexagonal(i));

  Header('Powers of 2 / 3 / 5');
  for i := 0 to 14 do
    writeln('  2^', i:2, ' = ', PowerInt(2, i),
            '   3^', i:2, ' = ', PowerInt(3, i),
            '   5^', i:2, ' = ', PowerInt(5, IntMin(i, 8)));

  Header('Collatz convergence');
  for i := 1 to 30 do
    writeln('  Collatz(', i:3, ') -> ', CollatzSteps(i), ' steps');

  Header('Divisor counts');
  for i := 1 to 30 do
    writeln('  d(', i:3, ') = ', CountDivisors(i),
            '   maxDiv = ', MaxDivisor(i));

  Header('GCD pairs');
  for i := 1 to 12 do
    for j := 1 to 12 do
      writeln('  GCD(', i:3, ', ', j:3, ') = ', GCD(i, j));

  Header('LCM pairs');
  for i := 1 to 8 do
    for j := 1 to 8 do
      writeln('  LCM(', i:3, ', ', j:3, ') = ', LCM(i, j));

  Header('Hypotenuses');
  for i := 1 to 8 do
    for j := 1 to 8 do
      writeln('  hypot(', i:2, ', ', j:2, ') = ', Hypotenuse(i * 1.0, j * 1.0));

  Header('Surface and volume tables');
  for i := 1 to 8 do
  begin
    acc := i * 1.0;
    writeln('  r=', acc:0:1,
            '   sphereVol=', SphereVolume(acc):0:4,
            '   sphereSurf=', SphereSurface(acc):0:4,
            '   circleArea=', CircleArea(acc):0:4)
  end;

  Header('Conversions');
  for i := 0 to 100 do
    if (i mod 10) = 0 then
      writeln('  ', i:4, ' C = ', CelsiusToF(i * 1.0):0:2, ' F');
  for i := 0 to 100 do
    if (i mod 10) = 0 then
      writeln('  ', i:4, ' mph = ', MphToKmh(i * 1.0):0:2, ' km/h');

  Header('Digit-twiddle table');
  for i := 1 to 30 do
    writeln('  n=', i:4,
            '   sum=', DigitSum(i):4,
            '   count=', DigitCount(i):4,
            '   reverse=', ReverseDigits(i):4,
            '   palindrome=', IsPalindrome(i));

  Header('Bit tests');
  for i := 0 to 31 do
    writeln('  ', i:4,
            '   bits=', CountBits(i):4,
            '   highBit=', HighestBit(i):4);

  writeln;
  writeln('=== End of long demo ===')
end.
