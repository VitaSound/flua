\ строковые литералы и конкатенация
\ ( -- r )
: greet 
s\" hi" 
;
\ ( -- r )
: shout 
s\" loud" 
;
\ ( s -- r )
: bang { s }
s s\" !" s+ 
;
