-- вызовы других слов в выражениях
-- @stack
function twice(n) return n * 2 end
-- @stack
function four(n) return twice(n) + twice(n) end
-- @stack
function zero() return 0 end
