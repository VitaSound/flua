-- DisasmGenerator pilot (flua). Full emit: fsoc/futils/disasm_gen.4th.
-- Regen: flua-verify fsoc/flua/disasm_gen.lua
--         flua fsoc/flua/disasm_gen.lua > fsoc/flua/disasm_gen.4th

-- Nibble 0..15 → ASCII hex digit code (parity with Python %02X).
function hexdigit(n)
  if n < 10 then
    return 48 + n
  end
  return 65 + (n - 10)
end

function hex2hi(u)
  return hexdigit(u / 16)
end

function hex2lo(u)
  local hi = u / 16
  return hexdigit(u - hi * 16)
end
