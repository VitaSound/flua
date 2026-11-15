\ DisasmGenerator pilot (flua). Full emit: fsoc/futils/disasm_gen.4th.
\ Regen: flua-verify fsoc/flua/disasm_gen.lua
\         flua fsoc/flua/disasm_gen.lua > fsoc/flua/disasm_gen.4th
\ Nibble 0..15 → ASCII hex digit code (parity with Python %02X).
\ ( n -- r )
: hexdigit { n }
  n 10 < if 
    48 n + exit 
  then 
  65 n 10 - + 
;
\ ( u -- r )
: hex2hi { u }
  u 16 / hexdigit 
;
\ ( u -- r )
: hex2lo { u | hi }
  u 16 / to hi 
  u hi 16 * - hexdigit 
;
