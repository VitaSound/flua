\ унарный минус и hex-литерал
\ @stack
\ ( v -- r )
: negate_it 
  negate 
;
\ @stack
\ ( n -- r )
: offset 
  $10 + 
;
\ @stack
\ ( n -- r )
: shift 
  $FF * 
;
