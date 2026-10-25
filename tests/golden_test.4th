\ tests/golden_test.4th — golden-тесты: исходный .lua ↔ эталонный .4th
\
\ Два прохода на каждой паре:
\   locals-режим: tests/golden/<name>.lua ↔ tests/golden/<name>.4th
\   stack-режим:  tests/golden/<name>.lua ↔ tests/golden/<name>.stack.4th
\ (stack-пара проверяется только для кейсов, валидных в --stack; см. список)
\
\ Для каждой пары:
\   1. читаем исходник, компилируем fl-compile (fail-loud при ошибке парсера)
\   2. сравниваем сгенерированный вывод с эталоном байт-в-байт (compare)
\   3. выполняем сгенерированный Forth (evaluate) — он должен быть валиден
\
\ Новая пара = файл .lua + эталон(ы) + строка в списке ниже.
\ Обновление эталона (осознанно, при изменении формата вывода):
\   flua tests/golden/<name>.lua > tests/golden/<name>.4th
\   FLUA_MODE=stack flua tests/golden/<name>.lua > tests/golden/<name>.stack.4th
\
\ Запуск из корня проекта:  gforth tests/golden_test.4th

require ../../ttester/ttester.4th
require ../../ttester/ttester-ext.4th
require ../flua.4th

0 #ERRORS !

create gd-src 65536 allot            \ содержимое исходного .lua
create gd-exp 65536 allot            \ эталонный .4th
variable gd-src-a   variable gd-src-u
variable gd-exp-a   variable gd-exp-u
2variable gd-name
variable gd-stack                      \ true = stack-режим прохода
2variable gd-suf                       \ суффикс эталона: ".4th" / ".stack.4th"

: slurp-src ( a u -- ) slurp-file gd-src-u ! gd-src-a ! ;
: slurp-exp ( a u -- ) slurp-file gd-exp-u ! gd-exp-a ! ;

\ ( name ext -- path ) путь tests/golden/<name>.<ext>
variable gp-na  variable gp-nu  variable gp-ea  variable gp-eu
: gpath ( a u a u -- a u )
    gp-eu ! gp-ea ! gp-nu ! gp-na !
    s" tests/golden/" gp-na @ gp-nu @ s+      \ префикс + имя
    gp-ea @ gp-eu @ s+ ;                      \ + расширение (.4th / .stack.4th)

\ одна golden-пара: режим/суффикс берётся из gd-stack / gd-suf
: golden-pair ( name-a name-u -- )
    gd-name 2!                          \ имя — в 2variable, стек чист
    gd-name 2@ s" .lua"  gpath slurp-src
    gd-name 2@ gd-suf 2@ gpath slurp-exp
    gd-stack @ stack-mode? !            \ режим этого прохода
    \ 1. компиляция исходника (fail-loud: throw обрывает прогон с позицией)
    gd-src-a @ gd-src-u @ fl-compile
    \ 2. байт-в-байт сравнение с эталоном
    emit-result
    gd-exp-a @ gd-exp-u @ compare if
        cr ." GOLDEN MISMATCH: " gd-name 2@ type
        gd-stack @ if ." [stack]" then cr
        1 #ERRORS +!
    then
    \ 3. сгенерированный Forth должен выполняться
    emit-result ['] evaluate catch
    dup if
        cr ." GOLDEN EVAL FAILED: " gd-name 2@ type
        gd-stack @ if ." [stack]" then cr
        1 #ERRORS +!
    then drop
    false stack-mode? !                 \ вернуть locals для следующих пар
    ." ok " gd-name 2@ type
    gd-stack @ if ."  [stack]" then cr ;

\ ---------- списки golden-пар ----------
\ locals-режим: все пары
: golden-one ( name-a name-u -- )
    false gd-stack !  s" .4th" gd-suf 2!  golden-pair ;
\ stack-режим: только кейсы, валидные в --stack
\ (конкатенация с параметром-целым — типовое ограничение подмножества)
: golden-stack-one ( name-a name-u -- )
    true gd-stack !  s" .stack.4th" gd-suf 2!  golden-pair ;

s" add"        golden-one
s" priority"   golden-one
s" unary_hex"  golden-one
s" strings"    golden-one
s" comments"   golden-one
s" calls"      golden-one
s" concat"     golden-one
s" reorder"    golden-one
s" if_else"    golden-one
s" elseif"     golden-one

cr
." ---------- stack-режим ----------" cr

s" add"        golden-stack-one
s" priority"   golden-stack-one
s" unary_hex"  golden-stack-one
s" comments"   golden-stack-one
s" calls"      golden-stack-one
s" concat"     golden-stack-one
s" reorder"    golden-stack-one
s" if_else"    golden-stack-one
s" elseif"     golden-stack-one

cr
#ERRORS @ 0= [IF]
    ." ALL GOLDEN TESTS PASSED" cr
[ELSE]
    ." GOLDEN TESTS FAILED: " #ERRORS @ . cr
[THEN]
bye
