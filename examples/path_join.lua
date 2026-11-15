-- path join via fjson.str-concat (-- @fpath / -- @require).
-- Generate into flua repo root (paths are relative to the .4th file):
--   flua examples/path_join.lua > path_join.out.4th
--   gforth -e 'include path_join.out.4th s" a" s" b" fsoc_join type cr bye'

-- @fpath ../fjson/fjson
-- @require ../fenum/fenum.4th
-- @require ../fjson/fjson.4th

-- @forth fjson.str-concat ( a1 u1 a2 u2 -- a3 u3 )
-- @forth fjson.str-free ( a u -- )

function fsoc_join(a1, u1, a2, u2)
  local sa, su = "/"
  local mid_a, mid_u = fjson_str_concat(a1, u1, sa, su)
  local out_a, out_u = fjson_str_concat(mid_a, mid_u, a2, u2)
  fjson_str_free(mid_a, mid_u)
  return out_a, out_u
end
