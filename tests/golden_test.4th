\ tests/golden_test.4th — golden-тесты: исходный .lua ↔ эталонный .4th
\
\ Для каждой пары tests/golden/<name>.lua + tests/golden/<name>.4th:
\   1. читаем исходник, компилируем fl-compile (fail-loud при ошибке парсера)
\   2. сравниваем сгенерированный вывод с эталоном байт-в-байт (compare)
\   3. выполняем сгенерированный Forth (evaluate) — он должен быть валиден
\
\ Новая пара = файл .lua + эталон .4th + строка в golden-cases.
\ Обновление эталона (осознанно, при изменении формата вывода):
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
variable gd-name-a  variable gd-name-u

: slurp-src ( a u -- ) slurp-file gd-src-u ! gd-src-a ! ;
: slurp-exp ( a u -- ) slurp-file gd-exp-u ! gd-exp-a ! ;

\ ( name ext -- path ) путь tests/golden/<name>.<ext>
: gpath ( a u a u -- a u )
    2>r s" tests/golden/" 2swap s+ 2r> s+ ;

\ одна golden-пара
: golden-one ( name-a name-u -- )
    2dup gd-name-u ! gd-name-a !
    2dup s" .lua" gpath slurp-src
    s" .4th" gpath slurp-exp
    \ 1. компиляция исходника (fail-loud: throw обрывает прогон с позицией)
    gd-src-a @ gd-src-u @ fl-compile
    \ 2. байт-в-байт сравнение с эталоном
    emit-result
    gd-exp-a @ gd-exp-u @ compare if
        cr ." GOLDEN MISMATCH: " gd-name-a @ gd-name-u @ type cr
        1 #ERRORS +!
    then
    \ 3. сгенерированный Forth должен выполняться
    emit-result ['] evaluate catch
    dup if
        cr ." GOLDEN EVAL FAILED: " gd-name-a @ gd-name-u @ type cr
        1 #ERRORS +!
    then drop
    ." ok " gd-name-a @ gd-name-u @ type cr ;

\ ---------- список golden-пар ----------
s" add"        golden-one
s" priority"   golden-one
s" unary_hex"  golden-one
s" strings"    golden-one
s" comments"   golden-one
s" calls"      golden-one

cr
#ERRORS @ 0= [IF]
    ." ALL GOLDEN TESTS PASSED" cr
[ELSE]
    ." GOLDEN TESTS FAILED: " #ERRORS @ . cr
[THEN]
bye
