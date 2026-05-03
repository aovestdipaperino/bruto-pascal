// A second unit that itself `uses MathUtils`. The main program will
// end up importing MathUtils transitively — proving that `uses`
// resolves dependency graphs, not just direct edges.
//
// Also showcases an enum and a variant record so the watch window
// can be exercised in the IDE: the debugger should print enum
// values by name and only show the active variant's fields.

unit Shapes;

interface

uses MathUtils;

type
  TKind = (KindSquare, KindRectangle, KindTriangle);
  TShape = record
    color: integer;
    case kind: integer of
      0: (side: integer);
      1: (width, height: integer);
      2: (base, h: integer);
  end;

function ShapeArea(s: TShape): integer;
function MakeSquare(c, side: integer): TShape;
function MakeRectangle(c, w, h: integer): TShape;
function MakeTriangle(c, b, h: integer): TShape;

implementation

function ShapeArea(s: TShape): integer;
begin
  if s.kind = 0 then
    ShapeArea := Square(s.side)
  else if s.kind = 1 then
    ShapeArea := s.width * s.height
  else
    ShapeArea := (s.base * s.h) div 2
end;

function MakeSquare(c, side: integer): TShape;
var t: TShape;
begin
  t.color := c;
  t.kind  := 0;
  t.side  := side;
  MakeSquare := t
end;

function MakeRectangle(c, w, h: integer): TShape;
var t: TShape;
begin
  t.color  := c;
  t.kind   := 1;
  t.width  := w;
  t.height := h;
  MakeRectangle := t
end;

function MakeTriangle(c, b, h: integer): TShape;
var t: TShape;
begin
  t.color := c;
  t.kind  := 2;
  t.base  := b;
  t.h     := h;
  MakeTriangle := t
end;

end.
