\ остаток от деления: % → mod (остаток со знаком делителя)
\ ( a b -- r )
: modulo { a b }
  a b mod 
;
\ ( a b c -- r )
: mixed { a b c }
  a b * c mod a + 
;
