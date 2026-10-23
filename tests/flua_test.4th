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

\ ( lua-a lua-u -- f ) ожидаем синтаксической ошибки
: expect-error ( lua-a lua-u -- f )
    ['] fl-compile catch if 2drop true else 2drop false then ;

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
   s\" \\ ( a -- r )
: n { a }
a negate $10 + 
;
"
   transpiles? -> true }T

\ ---------- фрагменты вывода (ключевые конструкции) ----------
T{ s\" function greet() return \"hi\" end"   s" hi"   has-output? -> true }T
T{ s\" function cat(a) return a .. \"!\" end"  s" s+"   has-output? -> true }T
T{ s\" function p(a, b) return a + b end"   s" { a b }" has-output? -> true }T
T{ s\" function noargs() return 7 end"      s" \ ( -- r )" has-output? -> true }T
T{ s\" function w(a) return a * -2 end"     s" negate"  has-output? -> true }T

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

\ ---------- ошибки парсинга ----------
T{ s\" naf return x end" expect-error -> true }T
T{ s\" function broken( return end" expect-error -> true }T

\ ---------- итог ----------
#ERRORS @ 0= [IF]
    ." ALL TESTS PASSED" cr
[ELSE]
    ." TESTS FAILED: " #ERRORS @ . cr
[THEN]
bye
