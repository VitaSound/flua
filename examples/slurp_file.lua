-- Whole-file read via Gforth slurp-file.
--   flua examples/slurp_file.lua > /tmp/slurp.4th
--   gforth -e 'include /tmp/slurp.4th bye'

-- @forth slurp-file ( c-addr u -- addr u )
-- @forth type ( c-addr u -- )
-- @forth cr ( -- )

function demo()
  local a, u = slurp_file("examples/data.txt")
  type(a, u)
  cr()
end

demo()
