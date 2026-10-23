\ унарный минус и hex-литерал
\ ( v -- r )
: negate_it { v }
v negate 
;
\ ( n -- r )
: offset { n }
n $10 + 
;
\ ( n -- r )
: shift { n }
n $FF * 
;
