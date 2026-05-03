// Reusable math helpers + a stat accumulator record.
// Exposes constants, functions, a procedure and a record type
// through the interface section. Demonstrates an initialization
// block that runs before the main program's body.

unit MathUtils;

interface

const
  MaxStat = 100;

type
  TStat = record
    count: integer;
    total: integer;
    peak:  integer;
  end;

function Square(x: integer): integer;
function Cube(x: integer): integer;
function Max(a, b: integer): integer;
procedure StatReset(var s: TStat);
procedure StatAdd(var s: TStat; v: integer);

implementation

// Implementation-only constant: not visible to anything that
// `uses MathUtils`.
const
  Banner = '[MathUtils ready]';

function Square(x: integer): integer;
begin
  Square := x * x
end;

function Cube(x: integer): integer;
begin
  Cube := x * x * x
end;

function Max(a, b: integer): integer;
begin
  if a > b then
    Max := a
  else
    Max := b
end;

procedure StatReset(var s: TStat);
begin
  s.count := 0;
  s.total := 0;
  s.peak  := 0
end;

procedure StatAdd(var s: TStat; v: integer);
begin
  s.count := s.count + 1;
  s.total := s.total + v;
  s.peak  := Max(s.peak, v)
end;

// Initialization block — runs once, before the main program's
// begin..end. body.
begin
  writeln(Banner)
end.
