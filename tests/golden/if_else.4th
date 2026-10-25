\ if-оператор с else: условие — целое (0 = ложь, ≠0 = истина)
\ ( n -- r )
: abs { n }
n 0 < if 
n 1 negate * exit 
else 
n exit 
then 
;
\ ( v -- r )
: clamp { v }
v 10 > if 
10 exit 
else 
v exit 
then 
;
