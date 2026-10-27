\ tests/golden_test.4th — golden-тесты: исходный .lua ↔ эталонный .4th
\
\ Один проход на пару: режим функции задаётся прагмой -- @stack в .lua.
\   tests/golden/<name>.lua ↔ tests/golden/<name>.4th
\
\ Для каждой пары:
\   1. читаем исходник, компилируем fl-compile (fail-loud при ошибке парсера)
\   2. сравниваем сгенерированный вывод с эталоном байт-в-байт (compare)
\   3. выполняем сгенерированный Forth (evaluate) — он должен быть валиден
\
\ Новая пара = файл .lua + эталон + строка в списке ниже.
\ Обновление эталона:
\   flua tests/golden/<name>.lua > tests/golden/<name>.4th
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

: slurp-src ( a u -- ) slurp-file gd-src-u ! gd-src-a ! ;
: slurp-exp ( a u -- ) slurp-file gd-exp-u ! gd-exp-a ! ;

\ ( name ext -- path ) путь tests/golden/<name>.<ext>
variable gp-na  variable gp-nu  variable gp-ea  variable gp-eu
: gpath ( a u a u -- a u )
    gp-eu ! gp-ea ! gp-nu ! gp-na !
    s" tests/golden/" gp-na @ gp-nu @ s+
    gp-ea @ gp-eu @ s+ ;

: golden-one ( name-a name-u -- )
    gd-name 2!
    gd-name 2@ s" .lua" gpath slurp-src
    gd-name 2@ s" .4th" gpath slurp-exp
    false stack-mode? ! false proc-mode? !
    gd-src-a @ gd-src-u @ fl-compile
    emit-result
    gd-exp-a @ gd-exp-u @ compare if
        cr ." GOLDEN MISMATCH: " gd-name 2@ type cr
        1 #ERRORS +!
    then
    depth >r
    \ evaluate эталона (тот же текст, что emit, если compare=0); не emit-buf —
    \ s\" / evaluate из того же буфера, куда пишет кодоген, даёт -9 на части кейсов
    gd-exp-a @ gd-exp-u @ ['] evaluate catch
    dup if
        cr ." GOLDEN EVAL FAILED: " gd-name 2@ type cr
        1 #ERRORS +!
    then drop
    \ top-level expr / VALUE могут оставить ячейки — не травим следующий кейс
    begin depth r@ > while drop repeat rdrop
    ." ok " gd-name 2@ type cr ;

s" add"          golden-one
s" priority"     golden-one
s" unary_hex"    golden-one
s" strings"      golden-one
s" comments"     golden-one
s" calls"        golden-one
s" concat"       golden-one
s" reorder"      golden-one
s" if_else"      golden-one
s" elseif"       golden-one
s" modulo"       golden-one
s" add_stack"    golden-one
s" priority_stack" golden-one
s" unary_hex_stack" golden-one
s" comments_stack" golden-one
s" calls_stack"  golden-one
s" concat_stack" golden-one
s" reorder_stack" golden-one
s" if_else_stack" golden-one
s" elseif_stack" golden-one
s" modulo_stack" golden-one
s" toplevel"    golden-one
s" print"       golden-one
s" print_stack" golden-one
s" globals_str" golden-one

cr
#ERRORS @ 0= [IF]
    ." ALL GOLDEN TESTS PASSED" cr
[ELSE]
    ." GOLDEN TESTS FAILED: " #ERRORS @ . cr
[THEN]
bye
