-- elseif: цепочка условий, else опционален
-- @stack
function sign(n)
  if n > 0 then return 1
  elseif n < 0 then return -1
  else return 0
  end
end
-- @stack
function grade(s)
  if s >= 90 then return 4
  elseif s >= 75 then return 3
  elseif s >= 60 then return 2
  else return 1
  end
end
