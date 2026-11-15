fpath path+ ../fjson/fjson
require ../fenum/fenum.4th
require ../fjson/fjson.4th
\ path join via fjson.str-concat (-- @fpath / -- @require).
\ Generate into flua repo root (paths are relative to the .4th file):
\   flua examples/path_join.lua > path_join.out.4th
\   gforth -e 'include path_join.out.4th s" a" s" b" fsoc_join type cr bye'
\ @fpath ../fjson/fjson
\ @require ../fenum/fenum.4th
\ @require ../fjson/fjson.4th
\ @forth fjson.str-concat ( a1 u1 a2 u2 -- a3 u3 )
\ @forth fjson.str-free ( a u -- )
\ ( a1 u1 a2 u2 -- r1 r2 )
: fsoc_join { a1 u1 a2 u2 | sa su mid_a mid_u out_a out_u }
  s\" /" to su to sa 
  a1 u1 sa su fjson.str-concat to mid_u to mid_a 
  mid_a mid_u a2 u2 fjson.str-concat to out_u to out_a 
  mid_a mid_u fjson.str-free 
  out_a out_u 
;
