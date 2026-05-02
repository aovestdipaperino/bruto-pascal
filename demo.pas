program Demo;
{ Small demo for running / debugging in the Bruto IDE.
  Try setting a breakpoint inside the loop on the line that
  reads `square := i * i;` and pressing F5 to inspect i, square, total. }

var
  i, square, total, doubled: integer;

function Double(n: integer): integer;
begin
  writeln('  Double called with n = ', n);
  Double := n * 2
end;

begin
  writeln('Demo starting.');
  total := 0;
  for i := 1 to 5 do
  begin
    square := i * i;
    total := total + square;
    writeln('i = ', i, '  square = ', square, '  total = ', total)
  end;
  writeln('Sum of squares 1..5 = ', total);
  doubled := Double(7);
  writeln('Double(7) = ', doubled);
  writeln('Demo done.')
end.
