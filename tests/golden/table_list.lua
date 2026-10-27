function demo()
  local xs = { 10, 20, 30 }
  local t0, a, z0 = xs[0]
  local t1, b, z1 = xs[1]
  xs[2] = 99
  local t2, c, z2 = xs[2]
  return a, b, c
end
