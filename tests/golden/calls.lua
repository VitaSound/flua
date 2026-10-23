-- вызовы других слов в выражениях
function twice(n) return n * 2 end
function four(n) return twice(n) + twice(n) end
function zero() return 0 end
