-- Read a file via Gforth words (@forth).
-- String arg to open-file counts as 2 cells (cell arity).
-- Run from repo root:
--   flua examples/read_file.lua > /tmp/read_file.4th
--   gforth -e 'include /tmp/read_file.4th bye'

-- @forth r/o ( -- fam )
-- @forth open-file ( c-addr u fam -- fileid ior )
-- @forth close-file ( fileid -- ior )
-- @forth read-file ( c-addr u1 fileid -- u2 ior )
-- @forth allocate ( u -- addr ior )
-- @forth free ( addr -- ior )
-- @forth type ( c-addr u -- )
-- @forth cr ( -- )

function demo(n)
  local fam = r_o()
  local fid, ior = open_file("examples/data.txt", fam)
  if ior ~= 0 then abort("open") end
  local buf, ai = allocate(n)
  if ai ~= 0 then abort("alloc") end
  local got, ri = read_file(buf, n, fid)
  if ri ~= 0 then abort("read") end
  local ci = close_file(fid)
  if ci ~= 0 then abort("close") end
  type(buf, got)
  cr()
  ior = free(buf)
end

demo(256)
