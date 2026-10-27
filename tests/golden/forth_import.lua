-- @forth open-file ( c-addr u fam -- fileid ior )
-- @forth addrlist-add ( addr list -- )

function load(a, u, fam)
  local fid, ior = open_file(a, u, fam)
  if ior ~= 0 then abort("open") end
  return fid
end

-- @proc
function add_ptr(p, list)
  addrlist_add(p, list)
end
