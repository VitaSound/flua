\ tests/flua_test.4th — тесты транспилятора flua (чистый Forth, без Python)
\ Запуск из корня проекта:  gforth tests/flua_test.4th
\ Принцип: ожидаемый текст задаётся литералами s" (без слэшей и кавычек в
\ содержимом); всё, что содержит s"-литералы, проверяется выполнением.

require ../../ttester/ttester.4th
require ../../ttester/ttester-ext.4th
require ../flua.4th

0 #ERRORS !

\ ( lua-a lua-u expected-a expected-u -- f ) скомпилировать и сравнить вывод
: transpiles? ( lua-a lua-u expected-a expected-u -- f )
    2>r fl-compile emit-result 2r> compare 0= ;

\ ( lua-a lua-u needle-a needle-u -- f ) есть ли фрагмент в выводе
: has-output? ( lua-a lua-u needle-a needle-u -- f )
    2>r fl-compile emit-result 2r> search >r 2drop r> ;

\ ( lua-a lua-u -- ) скомпилировать и подключить слова в gforth
: run-generated ( lua-a lua-u -- ) fl-compile emit-result evaluate ;

\ ( lua-a lua-u needle-a needle-u -- f ) фрагмента НЕТ в выводе
: lacks-output? ( lua-a lua-u needle-a needle-u -- f )
    2>r fl-compile emit-result 2r> search >r 2drop r> 0= ;

\ ( lua-a lua-u -- f ) ожидаем синтаксической ошибки
: expect-error ( lua-a lua-u -- f )
    ['] fl-compile catch if 2drop true else false then ;
: expect-stack-error ( lua-a lua-u -- f )
    ['] fl-compile catch if 2drop true else false then ;

\ ---------- режим -- @stack (прагма перед function) ----------
: transpiles-stack? ( lua-a lua-u expected-a expected-u -- f )
    2>r fl-compile emit-result 2r> compare 0= ;
: run-stack ( lua-a lua-u -- ) fl-compile emit-result evaluate ;

\ ---------- точные сравнения ----------
T{ s\" function add(a,b) return a+b end"
   s\" \\ ( a b -- r )
: add { a b }
  a b + 
;
"
   transpiles? -> true }T

T{ s\" function compute(x, y, z) return (x + y) * z end"
   s\" \\ ( x y z -- r )
: compute { x y z }
  x y + z * 
;
"
   transpiles? -> true }T

T{ s\" -- header comment
function n(a) return -a + 0x10 end"
   s\" \\ header comment
\\ ( a -- r )
: n { a }
  a negate $10 + 
;
"
   transpiles? -> true }T

\ ---------- комментарий перед функцией ----------
\ внутренний комментарий (после return) в вывод не попадает
T{ s\" function f(a) return a -- внутр
 end"
   s" -- внутр" lacks-output? -> true }T

\ комментарий в конце файла — уже не перед функцией, не эмитится
T{ s\" function g(a) return a end
-- последний"
   s" последний" lacks-output? -> true }T

\ серия комментариев между функциями относится к следующей
T{ s\" function p(a) return a end
-- про p
function q(a) return a end"
   s\" \\ про p
\\ ( a -- r )
: q { a }" has-output? -> true }T

\ ---------- фрагменты вывода (ключевые конструкции) ----------
T{ s\" function greet() return \"hi\" end"   s" hi"   has-output? -> true }T
T{ s\" function cat(a) return a .. \"!\" end"  s" s+"   has-output? -> true }T
T{ s\" function p(a, b) return a + b end"   s" { a b }" has-output? -> true }T
T{ s\" function noargs() return 7 end"      s" \ ( -- r )" has-output? -> true }T
T{ s\" function w(a) return a * -2 end"     s" negate"  has-output? -> true }T
T{ s" print(1, 2)"  s" 0 .r" has-output? -> true }T
T{ s\" print(\"hi\")" s" type" has-output? -> true }T
T{ s\" function f(x) print(x) return x end" s" 0 .r" has-output? -> true }T

\ ---------- генерированный Forth реально выполняется ----------
T{ s\" function add(a,b) return a+b end" run-generated 2 3 add -> 5 }T
T{ s\" function compute(x,y,z) return (x+y)*z end" run-generated 1 2 3 compute -> 9 }T
T{ s\" function dbl(n) return n+n end" run-generated 21 dbl -> 42 }T
T{ s\" function hex(n) return n + 0xff end" run-generated 1 hex -> 256 }T
T{ s\" function neg(v) return -v end" run-generated 7 neg -> -7 }T
T{ s\" function m(a) return a * -2 end" run-generated 5 m -> -10 }T

\ вызов другого слова внутри выражения
T{ s\" function twice(n) return n * 2 end
function four(n) return twice(n) + twice(n) end"
   run-generated 5 four -> 20 }T

\ строковый результат: evaluate, потом сравнить строку
: greet-returns-hi? ( -- f )
    s\" function greet() return \"hi\" end" run-generated
    s" greet" evaluate s" hi" compare 0= ;
T{ greet-returns-hi? -> true }T

\ конкатенация строк выполняется: "ab"
: cat-runs? ( -- f )
    s\" function cat(a) return a .. \"!\" end" run-generated
    s" a" s" cat" evaluate s" a!" compare 0= ;
T{ cat-runs? -> true }T

\ ---------- режим --stack: стековая эмиссия без { } ----------
T{ s\" -- @stack
function add(a,b) return a+b end"
   s\" \\ @stack
\\ ( a b -- r )
: add 
  + 
;
"
   transpiles-stack? -> true }T

T{ s\" -- @stack
function neg(v) return -v end"
   s\" \\ @stack
\\ ( v -- r )
: neg 
  negate 
;
"
   transpiles-stack? -> true }T

T{ s\" -- @stack
function noargs() return 7 end"
   s\" \\ @stack
\\ ( -- r )
: noargs 
  7 
;
"
   transpiles-stack? -> true }T

\ обратный порядок операндов → swap (для d=1 эмитится swap, не 1 roll)
T{ s\" -- @stack
function rb(a,b) return b + a end"
   s\" \\ @stack
\\ ( a b -- r )
: rb 
  swap + 
;
"
   transpiles-stack? -> true }T

\ выполнение стекового генерата: два roll = swap, дважды = ид
T{ s\" -- @stack
function add(a,b) return a+b end" run-stack 2 3 add -> 5 }T
T{ s\" -- @stack
function neg(v) return -v end" run-stack 7 neg -> -7 }T
T{ s\" -- @stack
function rb(a,b) return b + a end" run-stack 2 3 rb -> 5 }T

\ ---------- if / сравнения ----------
T{ s\" function f(a,b) if a then return b else return a end end" s\" if " has-output? -> true }T
T{ s\" function f(a,b) if a then return b else return a end end" s\" exit" has-output? -> true }T
T{ s\" function f(a,b) if a then return b else return a end end" s\" then" has-output? -> true }T
T{ s\" function f() return 1 < 2 end" s\" < " has-output? -> true }T
T{ s\" function f() return 1 <= 2 end" s\" <= " has-output? -> true }T
T{ s\" function f() return 1 >= 2 end" s\" >= " has-output? -> true }T
T{ s\" function f() return 1 ~= 2 end" s\" <> " has-output? -> true }T
T{ s\" function f() return 1 == 2 end" s\" = " has-output? -> true }T

\ выполнение if-оператора (locals): n<0 → n*-1, иначе n
T{ s\" function abs(n) if n < 0 then return n * -1 else return n end end"
   run-generated -3 abs -> 3 }T
T{ s\" function abs(n) if n < 0 then return n * -1 else return n end end"
   run-generated 5 abs -> 5 }T

\ истинное сравнение → then-ветка, ложное → else-ветка
T{ s\" function t() if 1 < 2 then return 11 else return 22 end end"
   run-generated t -> 11 }T
T{ s\" function t() if 1 > 2 then return 11 else return 22 end end"
   run-generated t -> 22 }T

\ elseif-цепочка (locals)
T{ s\" function s3(n) if n > 0 then return 1 elseif n < 0 then return -1 else return 0 end end"
   run-generated 5 s3 -> 1 }T
T{ s\" function s3(n) if n > 0 then return 1 elseif n < 0 then return -1 else return 0 end end"
   run-generated -5 s3 -> -1 }T
T{ s\" function s3(n) if n > 0 then return 1 elseif n < 0 then return -1 else return 0 end end"
   run-generated 0 s3 -> 0 }T

\ выполнение if в режиме --stack
T{ s\" -- @stack
function abs(n) if n < 0 then return n * -1 else return n end end"
   run-stack -4 abs -> 4 }T
T{ s\" -- @stack
function abs(n) if n < 0 then return n * -1 else return n end end"
   run-stack 7 abs -> 7 }T
T{ s\" -- @stack
function t() if 1 > 2 then return 11 else return 22 end end"
   run-stack t -> 22 }T

\ elseif в режиме --stack
T{ s\" -- @stack
function s3(n) if n > 0 then return 1 elseif n < 0 then return -1 else return 0 end end"
   run-stack -5 s3 -> -1 }T

\ if без else (опционален): при истинном условии → then-ветка
T{ s\" function t() if 1 < 2 then return 42 end end"
   run-generated t -> 42 }T

\ ограничения --stack: неиспользуемый параметр и конкатенация с целым
T{ s\" -- @stack
function u(a) return 7 end" expect-stack-error -> true }T
T{ s\" -- @stack
function cat(a) return a .. \"!\" end" expect-stack-error -> true }T

\ ---------- остаток от деления: % → mod ----------
\ точный вывод (locals)
T{ s\" function modulo(a,b) return a % b end"
   s\" \\ ( a b -- r )
: modulo { a b }
  a b mod 
;
"
   transpiles? -> true }T
\ приоритет: % на уровне * /, левоассоциативно: a * b % c + a
T{ s\" function mixed(a,b,c) return a * b % c + a end"
   s\" \\ ( a b c -- r )
: mixed { a b c }
  a b * c mod a + 
;
"
   transpiles? -> true }T
\ выполняется: остаток со знаком делителя (как в Lua): 5%3=2, -5%3=1
T{ s\" function modulo(a,b) return a % b end" run-generated 5 3 modulo -> 2 }T
T{ s\" function modulo(a,b) return a % b end" run-generated -5 3 modulo -> 1 }T
\ режим --stack: точный вывод и выполнение
T{ s\" -- @stack
function modulo(a,b) return a % b end"
   s\" \\ @stack
\\ ( a b -- r )
: modulo 
  mod 
;
"
   transpiles-stack? -> true }T
T{ s\" -- @stack
function modulo(a,b) return a % b end" run-stack -5 3 modulo -> 1 }T
T{ s\" -- @stack
function mixed(a,b,c) return a * b % c + a end" run-stack 2 3 4 mixed -> 4 }T

\ ---------- лексер: одиночный оператор ----------
\ ( lua-a lua-u i -- type len ) токенизировать источник и взять type/len
\ токена № i (позиция в исходнике не нужна)
: tok-of ( lua-a lua-u i -- type len )
    >r src-set fl-tokenize r> tok-at >r drop r> ;
\ tok-op1 не проверяет символы: одиночный "%" — TK-OP длиной 1,
\ соседние токены не слипаются с ним
T{ s\" function m(a,b) return a % b end" 9 tok-of -> TK-OP 1 }T

\ ---------- логические операторы: not, and, or ----------
\ not → 0= : флаг gforth −1 (истина) / 0 (ложь), как у сравнений
T{ s\" function fnot(a) return not a end"
   s\" \\ ( a -- r )
: fnot { a }
  a 0= 
;
"
   transpiles? -> true }T
\ and: правый операнд эмитится только внутри ветки (шорт-кircuit)
T{ s\" function fband(a,b) return a and b end"
   s\" \\ ( a b -- r )
: fband { a b }
  a dup if drop b then 
;
"
   transpiles? -> true }T
\ or: левый решает исход — правый не выполняется
T{ s\" function fbor(a,b) return a or b end"
   s\" \\ ( a b -- r )
: fbor { a b }
  a dup if else drop b then 
;
"
   transpiles? -> true }T
\ режим --stack: та же эмиссия с выравниванием операндов
T{ s\" -- @stack
function fband(a,b) return a and b end"
   s\" \\ @stack
\\ ( a b -- r )
: fband 
  swap dup if drop else nip then 
;
"
   transpiles-stack? -> true }T
T{ s\" -- @stack
function fnot(a) return not a end"
   s\" \\ @stack
\\ ( a -- r )
: fnot 
  0= 
;
"
   transpiles-stack? -> true }T
\ семантика (locals): and → b при a≠0, or → a при a≠0
T{ s\" function fband(a,b) return a and b end" run-generated 10 3 fband -> 3 }T
T{ s\" function fband(a,b) return a and b end" run-generated 0 3 fband -> 0 }T
T{ s\" function fbor(a,b) return a or b end" run-generated 7 0 fbor -> 7 }T
T{ s\" function fbor(a,b) return a or b end" run-generated 0 5 fbor -> 5 }T
\ флаг not: 0 → −1, 5 → 0
T{ s\" function fnot(a) return not a end" run-generated 0 fnot -> -1 }T
T{ s\" function fnot(a) return not a end" run-generated 5 fnot -> 0 }T
\ приоритет: and ближе к выражению, чем or — a and b or c = (a and b) or c
T{ s\" function fchain(a,b,c) return a and b or c end" run-generated 1 2 3 fchain -> 2 }T
T{ s\" function fchain(a,b,c) return a and b or c end" run-generated 0 0 5 fchain -> 5 }T
\ not + or в одном выражении: not a or a
T{ s\" function fneg(a) return not a or a end" run-generated 0 fneg -> -1 }T
T{ s\" function fneg(a) return not a or a end" run-generated 5 fneg -> 5 }T
\ та же семантика в --stack
T{ s\" -- @stack
function fband(a,b) return a and b end" run-stack 10 3 fband -> 3 }T
T{ s\" -- @stack
function fband(a,b) return a and b end" run-stack 0 3 fband -> 0 }T
T{ s\" -- @stack
function fnot(a) return not a end" run-stack 0 fnot -> -1 }T
\ шорт-кircuit на выполнении: fprobe бросает исключение, если вызван —
\ a=0 возвращает 0 молча (правый операнд не выполнялся),
\ a=5 доходит до fprobe (выполнялся) — ловим throw через catch
: fprobe ( n -- n ) drop -1 throw ;
T{ s\" function fsc(a) return a and fprobe(7) end" run-generated 0 fsc -> 0 }T
\ вызов с a≠0 внутри слова (catch только в колонном определении):
\ fprobe выполнится и бросит — catch возвращает код ≠ 0
: fsc5 ( -- n ) 5 fsc ;
T{ ' fsc5 catch 0<> -> true }T

\ ---------- позиция ошибки: строка/столбец ----------
\ src-line-col: байт → (line col); границы строк — одиночный \n (10)
T{ s\" line one
line two" src-set 0 src-line-col -> 1 1 }T
T{ s\" line one
line two" src-set 9 src-line-col -> 2 1 }T
T{ s\" line one
line two" src-set 13 src-line-col -> 2 5 }T
\ сообщение об ошибке — чистая функция, байт-в-байт
T{ s\" line one
line two" src-set 10 fl-syntax-msg s" 2:2 (offset 10)" compare -> 0 }T

\ ---------- ошибки парсинга ----------
T{ s\" function (a) return a end" expect-error -> true }T
T{ s\" function broken( return end" expect-error -> true }T
\ if без then / if без end / return вне ветки if
T{ s\" function f() if 1 return 2 end" expect-error -> true }T
T{ s\" function f() if 1 then return 2" expect-error -> true }T
T{ s\" function f() if 1 then 2 end end" expect-error -> true }T

\ ---------- ошибки токенизатора (с позицией) ----------
\ незакрытая строка: позиция — открывающая кавычка
T{ s\" function f() return \"abc end" expect-error -> true }T
\ переполнение буфера токенов: 4100 токенов «x» > tok-max (4096)
create many-src 9000 allot
: fill-many ( -- )                       \ «x x x …» — 8200 байт
    many-src 8200 0 ?do
        dup i + i 2 mod 0= if [char] x else bl then swap c!
    loop drop ;
T{ fill-many many-src 8200 expect-error -> true }T

\ ---------- local / multi-return / while / repeat / @proc ----------
T{ s\" function f(x)
  local t = x * 2
  return t, x
end" run-generated 3 f -> 6 3 }T
T{ s\" -- @proc
function countdown(n)
  while n > 0 do
    n = n - 1
  end
end" run-generated 3 countdown -> }T
T{ s\" function until_zero(n)
  repeat
    n = n - 1
  until n == 0
  return n
end" run-generated 4 until_zero -> 0 }T
T{ s\" -- @proc
function clear(x)
  if x < 0 then return end
  x = 0
end" run-generated -1 clear -> }T
T{ s\" -- @proc
function clear(x)
  if x < 0 then return end
  x = 0
end" run-generated 5 clear -> }T

\ ---------- @forth / multi-assign / for / abort ----------
T{ s\" -- @forth twice ( n -- n2 )
function f(x)
  local y = twice(x)
  return y
end"
   s\" twice" has-output? -> true }T
\ клеточная arity: строковый литерал = 2 клетки; r/o → r_o
T{ s\" -- @forth open-file ( c-addr u fam -- fileid ior )
-- @forth r/o ( -- fam )
function load()
  local fam = r_o()
  local fid, ior = open_file(\"x.txt\", fam)
  return fid, ior
end"
   s\" open-file" has-output? -> true }T
T{ s\" -- @forth open-file ( c-addr u fam -- fileid ior )
-- @forth r/o ( -- fam )
function load()
  local fam = r_o()
  local fid, ior = open_file(\"x.txt\", fam)
  return fid, ior
end"
   s\" r/o" has-output? -> true }T
\ раздельные a,u по-прежнему ок (1+1+1)
T{ s\" -- @forth open-file ( c-addr u fam -- fileid ior )
function load(a, u, fam)
  local fid, ior = open_file(a, u, fam)
  return fid
end"
   s\" open-file" has-output? -> true }T
\ 1-cell + 1-cell к 3-cell open-file → mismatch
T{ s\" -- @forth open-file ( c-addr u fam -- fileid ior )
function bad(n, fam)
  local fid, ior = open_file(n, fam)
  return fid
end" expect-error -> true }T
\ неизвестный ID на @forth → untyped arg (не тихий 0→1)
T{ s\" -- @forth type ( c-addr u -- )
function bad()
  type(unknown_buf)
end" expect-error -> true }T
T{ s\" function sum_to(n)
  local s = 0
  for i = 1, n do
    s = s + i
  end
  return s
end" run-generated 4 sum_to -> 10 }T
T{ s\" -- @proc
function boom()
  abort(\"x\")
end"
   s\" abort\" x\"" has-output? -> true }T
\ single-assign от index-get запрещён
T{ s\" function f()
  local m = { a = 1 }
  local x = m.a
  return x
end" expect-error -> true }T

\ ---------- table literals / index ----------
T{ s\" local m = { a = 1 }" s" VALUE m" has-output? -> true }T
T{ s\" local m = { a = 1 }" s" local " lacks-output? -> true }T
T{ s\" function f() local m = { a = 1 } return m end"
   s" hashmap-new" has-output? -> true }T
T{ s\" function f() local xs = { 10, 20 } return xs end"
   s" ulist-new" has-output? -> true }T
T{ s\" function f()
  local m = { a = 1 }
  local vt, v1, v2, fl = m.a
  return v1
end" run-generated f -> 1 }T
T{ s\" function f()
  local xs = { 10, 20, 30 }
  local t, a, z = xs[0]
  return a
end" run-generated f -> 10 }T
T{ s\" function f() local bad = { 1, a = 2 } return bad end"
   expect-error -> true }T
T{ s\" function f()
  local m = {}
  m.k = 4
  local vt, v, x, fl = m.k
  return v
end" run-generated f -> 4 }T
\ top-level multi-assign (REPL): emit содержит to …
T{ s\" function wrap()
  local m = { a = 1 }
  local vt, v1, v2, fl = m.a
  return vt, v1, fl
end" run-generated wrap -> 1 1 -1 }T

\ ---------- @ → _at / @require / @fpath ----------
T{ s" fjson.node-str@" fl-forth-to-lua s" fjson_node_str_at" compare -> 0 }T
T{ s\" -- @fpath ../fjson/fjson
-- @require ../fenum/fenum.4th
-- @forth cr ( -- )
function f()
  cr()
end"
   s" fpath path+ ../fjson/fjson" has-output? -> true }T
T{ s\" -- @require ../fenum/fenum.4th
-- @require ../fjson/fjson.4th
function f() return 1 end"
   s" require ../fenum/fenum.4th" has-output? -> true }T
\ порядок объявления (не LIFO): a.4th раньше b.4th в выводе
: require-order-ok? ( -- f )
    s\" -- @require a.4th
-- @require b.4th
function f() return 1 end" fl-compile
    emit-result { a u }
    a u s" require a.4th" search 0= if 2drop false exit then
    { a1 u1 }                       \ a1 — после совпадения a.4th
    a1 u1 s" require b.4th" search nip nip ;
T{ require-order-ok? -> true }T

\ ---------- local ncells / m.n = local_int ----------
T{ s\" function f(x)
  local y = x + 1
  local m = {}
  m.n = y
  return y
end" s" TM-INT y" has-output? -> true }T
T{ s\" function f(x)
  local y = x + 1
  local m = {}
  m.n = y
  local vt, v, z, ok = m.n
  return v
end" run-generated 3 f -> 4 }T

\ ---------- Lua-function out-arity registry ----------
T{ s\" function pair(a, b)
  return a, b
end
function use()
  local x = pair(1, 2)
  return x
end" expect-error -> true }T
T{ s\" function pair(a, b)
  return a, b
end
function use()
  local x, y = pair(1, 2)
  return x + y
end" run-generated use -> 3 }T

\ ---------- host-eval smoke (flua-host) ----------
T{ s" 40 2 +" host-eval -> 42 }T
\ ошибка evaluate → host-trim-depth; стек до вызова не портится
: host-err-ok? ( -- f )
    depth { d0 }
    s" -1 throw" host-eval
    depth d0 = ;
T{ host-err-ok? -> true }T
\ host-stack-print (иначе 0% на defer target)
T{ 7 8 host-stack-print -> 7 8 }T
\ REPL chunk без TTY: compile → host-eval → показать out-cells
: repl-smoke-ok? ( -- f )
    s" 1+2" fl-compile-repl
    emit-result host-eval
    fl-repl-out-cells @ 1 <> if drop false exit then
    depth 1 < if false exit then
    3 = ;
T{ repl-smoke-ok? -> true }T

\ ---------- CLI: файл не найден ----------
\ flua.src при заданном FLUA_ARG с несуществующим файлом:
\ file-status → сообщение + тихий -1 throw (без трассы gforth)
: cli-no-file? ( -- f )
    s" FLUA_ARG" s" /tmp/flua-no-such-file.lua" 1 setenv drop
    ['] flua.src catch if true else 2drop false then
    s" FLUA_ARG" unsetenv drop ;
T{ cli-no-file? -> true }T

\ ---------- итог ----------
#ERRORS @ 0= [IF]
    ." ALL TESTS PASSED" cr
[ELSE]
    ." TESTS FAILED: " #ERRORS @ . cr
[THEN]
bye
