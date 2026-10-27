\ остаток от деления: % → mod (остаток со знаком делителя)
\ @stack
\ ( a b -- r )
: modulo 
  mod 
;
\ @stack
\ ( a b c -- r )
: mixed 
  2 pick 2 roll * swap mod swap + 
;
