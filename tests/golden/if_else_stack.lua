-- if-оператор с else: условие — целое (0 = ложь, ≠0 = истина)
-- @stack
function abs(n)
  if n < 0 then return n * -1
  else return n
  end
end
-- @stack
function clamp(v)
  if v > 10 then return 10
  else return v
  end
end
