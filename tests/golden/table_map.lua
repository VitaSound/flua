function demo()
  local m = { a = 1, b = "x" }
  local vt, v1, v2, ok = m.a
  m.c = 3
  local t2, x, y, ok2 = m["c"]
  return v1, ok, x, ok2
end
