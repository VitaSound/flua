\ @proc
\ ( n -- )
: countdown { n }
  begin n 0 > while 
    n 1 - to n 
  repeat 
;
