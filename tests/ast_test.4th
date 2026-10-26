\ tests/ast_test.4th — тесты вывода AST (flua --ast / fl-ast-run)
\
\ AST-конвейер независим от компиляции: токены → дерево → emit-buf.
\ Сравнение вывода байт-в-байт (как в golden-тестах), ошибки — через catch.
\ Запуск из корня проекта:  gforth tests/ast_test.4th

require ../../ttester/ttester.4th
require ../../ttester/ttester-ext.4th
require ../flua.4th

0 #ERRORS !

\ ( lua-a lua-u expected-a expected-u -- f ) разбор и точное сравнение
: ast? ( lua-a lua-u expected-a expected-u -- f )
    2>r fl-ast-run emit-result 2r> compare 0= ;

\ ( lua-a lua-u -- f ) ожидаемая синтаксическая ошибка парсера AST
\ при ошибке catch возвращает исходную пару (а u) + код → 2drop
: ast-error? ( lua-a lua-u -- f )
    ['] fl-ast-run catch if 2drop true else false then ;

\ ---------- базовые узлы ----------
T{ s\" function add(a,b) return a+b end"
   s\" fn add(a, b)
  bin +
    id a
    id b
"
   ast? -> true }T

T{ s\" function calc(a,b,c) return a + b * c end"
   s\" fn calc(a, b, c)
  bin +
    id a
    bin *
      id b
      id c
"
   ast? -> true }T

\ унарный минус и hex-число: текст листа — цитата из исходника
T{ s\" function neg() return -0x10 end"
   s\" fn neg()
  un -
    num 0x10
"
   ast? -> true }T

\ строка в исходнике цитируется с кавычками и escape'ами
T{ s\" function s() return \"a\\tb\" end"
   s\" fn s()
  str \"a\\tb\"
"
   ast? -> true }T

\ ---------- вызов, конкатенация ----------
T{ s\" function g(x) return f(x, x .. \"s\") end"
   s\" fn g(x)
  call f
    id x
    bin ..
      id x
      str \"s\"
"
   ast? -> true }T

\ скобки прозрачны для AST
T{ s\" function p(a,b) return (a+b)*b end"
   s\" fn p(a, b)
  bin *
    bin +
      id a
      id b
    id b
"
   ast? -> true }T

\ ---------- ветвление if ----------
T{ s\" function m(a,b) if a > b then return a else return b end end"
   s\" fn m(a, b)
  if
    bin >
      id a
      id b
  then
    id a
  else
    id b
  end
"
   ast? -> true }T

\ else опционален: без него есть только then-ветка
T{ s\" function one(x) if x then return x end end"
   s\" fn one(x)
  if
    id x
  then
    id x
  end
"
   ast? -> true }T

\ elseif-цепочка: каждая ветка — условие (нет у else) + значение
T{ s\" function abs(n)
  if n < 0 then return -n
  elseif n > 0 then return n
  else return 0
  end
end"
   s\" fn abs(n)
  if
    bin <
      id n
      num 0
  then
    un -
      id n
  elseif
    bin >
      id n
      num 0
  then
    id n
  else
    num 0
  end
"
   ast? -> true }T

\ несколько stmt'ов в теле: if-блок и return после него
T{ s\" function two(x) if x then return x end return 0 end"
   s\" fn two(x)
  if
    id x
  then
    id x
  end
  num 0
"
   ast? -> true }T

\ ---------- несколько функций, комментарии ----------
T{ s\" -- head
function one() return 1 end
function two(x) return x end"
   s\" fn one()
  num 1
fn two(x)
  id x
"
   ast? -> true }T

\ пустой исходник → пустой вывод
T{ s\" " s\" " ast? -> true }T

\ ---------- ошибки ----------
T{ s\" function broken(a return a end" ast-error? -> true }T
T{ s\" x = 1" ast-error? -> true }T
T{ s\" function f() return 1 + end" ast-error? -> true }T
\ ветка if без return — синтаксическая ошибка
T{ s\" function bad(x) if x then x end end" ast-error? -> true }T
\ пустой return в ветке
T{ s\" function bad(x) if x then return x else return end" ast-error? -> true }T
\ нет end блока if
T{ s\" function bad(x) if x then return x end" ast-error? -> true }T

\ после ошибки парсер и реестр узлов (an-reset) работоспособны
T{ s\" function ok(x) return x end"
   s\" fn ok(x)
  id x
"
   ast? -> true }T

\ ---------- итог ----------
#ERRORS @ 0= [IF]
    ." ALL AST TESTS PASSED" cr
[ELSE]
    ." AST TESTS FAILED: " #ERRORS @ . cr
[THEN]
bye
