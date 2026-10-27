\ if-оператор с else: условие — целое (0 = ложь, ≠0 = истина)
\ @stack
\ ( n -- r )
: abs 
  dup 0 < if 
    dup 1 negate * nip exit 
  else 
    exit 
  then 
;
\ @stack
\ ( v -- r )
: clamp 
  dup 10 > if 
    10 nip exit 
  else 
    exit 
  then 
;
