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
    ['] fl-compile catch if 2drop true else 2drop false then ;

\ ---------- режим --stack ----------
\ ( lua-a lua-u expected-a expected-u -- f ) точное сравнение в режиме --stack
: transpiles-stack? ( lua-a lua-u expected-a expected-u -- f )
    true stack-mode? !
    2>r fl-compile emit-result false stack-mode? !
    2r> compare 0= ;
\ ( lua-a lua-u -- ) скомпилировать в --stack и выполнить
: run-stack ( lua-a lua-u -- )
    true stack-mode? ! fl-compile emit-result false stack-mode? ! evaluate ;
\ ( lua-a lua-u -- f ) ожидаем ошибки в режиме --stack
: expect-stack-error ( lua-a lua-u -- f )
    true stack-mode? !
    ['] fl-compile catch if 2drop true else 2drop false then
    false stack-mode? ! ;

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
T{ s\" function add(a,b) return a+b end"
   s\" \\ ( a b -- r )
: add 
+ 
;
"
   transpiles-stack? -> true }T

T{ s\" function neg(v) return -v end"
   s\" \\ ( v -- r )
: neg 
negate 
;
"
   transpiles-stack? -> true }T

T{ s\" function noargs() return 7 end"
   s\" \\ ( -- r )
: noargs 
7 
;
"
   transpiles-stack? -> true }T

\ обратный порядок операндов → swap (для d=1 эмитится swap, не 1 roll)
T{ s\" function rb(a,b) return b + a end"
   s\" \\ ( a b -- r )
: rb 
swap + 
;
"
   transpiles-stack? -> true }T

\ выполнение стекового генерата: два roll = swap, дважды = ид
T{ s\" function add(a,b) return a+b end" run-stack 2 3 add -> 5 }T
T{ s\" function neg(v) return -v end" run-stack 7 neg -> -7 }T
T{ s\" function rb(a,b) return b + a end" run-stack 2 3 rb -> 5 }T

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
T{ s\" function abs(n) if n < 0 then return n * -1 else return n end end"
   run-stack -4 abs -> 4 }T
T{ s\" function abs(n) if n < 0 then return n * -1 else return n end end"
   run-stack 7 abs -> 7 }T
T{ s\" function t() if 1 > 2 then return 11 else return 22 end end"
   run-stack t -> 22 }T

\ elseif в режиме --stack
T{ s\" function s3(n) if n > 0 then return 1 elseif n < 0 then return -1 else return 0 end end"
   run-stack -5 s3 -> -1 }T

\ if без else (опционален): при истинном условии → then-ветка
T{ s\" function t() if 1 < 2 then return 42 end end"
   run-generated t -> 42 }T

\ ограничения --stack: неиспользуемый параметр и конкатенация с целым
T{ s\" function u(a) return 7 end" expect-stack-error -> true }T
T{ s\" function cat(a) return a .. \"!\" end" expect-stack-error -> true }T

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
T{ s\" function modulo(a,b) return a % b end"
   s\" \\ ( a b -- r )
: modulo 
mod 
;
"
   transpiles-stack? -> true }T
T{ s\" function modulo(a,b) return a % b end" run-stack -5 3 modulo -> 1 }T
T{ s\" function mixed(a,b,c) return a * b % c + a end" run-stack 2 3 4 mixed -> 4 }T

\ ---------- лексер: одиночный оператор ----------
\ ( lua-a lua-u i -- type len ) токенизировать источник и взять type/len
\ токена № i (позиция в исходнике не нужна)
: tok-of ( lua-a lua-u i -- type len )
    >r src-set fl-tokenize r> tok-at >r drop r> ;
\ tok-op1 не проверяет символы: одиночный "%" — TK-OP длиной 1,
\ соседние токены не слипаются с ним
T{ s\" function m(a,b) return a % b end" 9 tok-of -> TK-OP 1 }T

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
T{ s\" naf return x end" expect-error -> true }T
T{ s\" function broken( return end" expect-error -> true }T
\ if без then / if без end / return вне ветки if
T{ s\" function f() if 1 return 2 end" expect-error -> true }T
T{ s\" function f() if 1 then return 2" expect-error -> true }T
T{ s\" function f() if 1 then 2 end end" expect-error -> true }T

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
