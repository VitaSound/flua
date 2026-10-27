function demo()
  local m = {}
  m.k = 7
  local xs = { 1, 2 }
  xs[0] = 5
  local vt, v, f, ok = m["k"]
  local t, a, z = xs[0]
  return v, ok, a
end
