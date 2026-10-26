\ остаток от деления: % → mod (остаток со знаком делителя)
\ ( a b -- r )
: modulo 
mod 
;
\ ( a b c -- r )
: mixed 
2 pick 2 roll * swap mod swap + 
;
