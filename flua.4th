\ flua.4th — транспилятор простого подмножества Lua в Forth (Gforth).
\ Только Forth, без Python. Часть экосистемы VitaSound Forth tooling.
\
\ Поддерживаемое подмножество:
\   -- line comments
\   function name(a, b) return expr end
\   целые (десятичные, 0x hex), унарный минус
\   строки "..." и '...' (эскейпы \n \t \\ \" \')
\   бинарные + - * /, конкатенация ..  → s+
\   вызовы слов name(a, b) и ссылки на параметры name

s" 0.1.0" 2constant flua-version

\ ============================== fenum (контейнеры для структур) ==============================
\ Параметры функции хранятся как структуры в ulist fenum:
\   [0] name-a  [1] name-u  [2] count  [3] used
\ Кандидаты: forth-packages (после fmix packages.get) либо sibling-клон
\ рядом с flua (~/fenum). Путь отсчитывается от файла flua.4th.
: fl-load-fenum ( -- )
    s" forth-packages/fenum/0.1.2/fenum.4th"
    2dup file-status nip 0= if required exit then
    2drop s" ../fenum/fenum.4th" required ;

fl-load-fenum

\ ============================== режим генерации ==============================
\ false (по умолчанию) — locals: : name { a b } ...
\ true (--stack)      — чистый стековый вид: : name ... ; с pick/roll
variable stack-mode? false stack-mode? !

\ ============================== буфер эмита ==============================

65536 constant emit-capacity
create emit-buf emit-capacity allot
variable emit-pos

: emit-reset ( -- ) 0 emit-pos ! ;
: emit-ch ( c -- )
    emit-pos @ emit-capacity >= abort" flua: emit buffer overflow"
    emit-buf emit-pos @ + c!
    1 emit-pos +! ;
: emit-st ( a u -- ) dup 0= if 2drop exit then bounds ?do i c@ emit-ch loop ;
: emit-nl ( -- ) 10 emit-ch ;
: emit-bl  ( -- ) 32 emit-ch ;
: emit-result ( -- a u ) emit-buf emit-pos @ ;

\ ============================== классификация символов ==============================

: fl-ws? ( c -- f )
    dup 32 = over 9 = or over 13 = or swap 10 = or ;
: fl-alpha? ( c -- f )
    dup [char] a [char] z 1+ within
    over [char] A [char] Z 1+ within or
    swap [char] _ = or ;
: fl-digit? ( c -- f ) [char] 0 [char] 9 1+ within ;
: fl-hexd? ( c -- f )
    dup fl-digit? if drop true exit then
    dup [char] a [char] f 1+ within if drop true exit then
    dup [char] A [char] F 1+ within if drop true exit then
    drop false ;
: fl-alnum? ( c -- f ) dup fl-alpha? swap fl-digit? or ;

\ ============================== стековая модель (--stack) ==============================
\ Модель отражает физический стек: один слот = одна ячейка стека.
\ Тэги: 0..N-1 — слот параметра; 128 — временное (вычисленное) значение.
\ Нужна только для режима --stack (выбор pick/roll и проверки чистоты),
\ но ведётся всегда — обновления дёшевы и единообразны.

create m-model 512 allot
variable m-len
: m-reset ( -- ) 0 m-len ! ;
: m-append ( c -- ) m-len @ m-model + c! 1 m-len +! ;
: m-push-tmp ( -- ) 128 m-append ;
: m-popn ( k -- )
    stack-mode? @ if                        \ проверка — только в режиме --stack
        dup m-len @ > if
            cr ." flua: stack model desync: need " dup . ." slot(s), have " m-len @ . cr
            -1 throw
        then
    then
    negate m-len +! ;
: m-pop ( -- ) -1 m-len +! ;

\ позиция слота параметра n (тэг = индекс), -1 если не найден
: m-find ( n -- p )
    m-len @ 0 ?do
        dup m-model i + c@ = if drop i unloop exit then
    loop
    drop -1 ;

\ переставить слот с позиции p на вершину (физически: roll)
: m-move-to-top ( p -- )
    dup m-model + c@ >r                      \ r: тэг
    dup m-model +                           \ ( p to )
    dup 1+ swap                             \ ( p from to )   from = to+1
    m-len @ 1- 3 pick -                     \ ( p from to count )
    cmove drop                              \ ( )
    r> m-len @ 1- m-model + c! ;            \ тэг в последний слот: ( tag addr -> c! )

\ ============================== курсор по исходнику ==============================

variable src-a
variable src-len
variable src-pos

: src-set ( a u -- ) src-len ! src-a ! 0 src-pos ! ;
: src-eof? ( -- f ) src-pos @ src-len @ >= ;
: src-at ( u -- c )                       \ символ на смещении pos+u, -1 за концом
    dup src-pos @ + src-len @ >= if drop -1 exit then
    src-a @ src-pos @ + + c@ ;
: src-peek ( -- c ) 0 src-at ;
: src-next ( -- c )                       \ текущий символ и сдвиг курсора
    src-eof? if -1 exit then
    src-a @ src-pos @ + c@
    src-pos @ 1+ src-pos ! ;

\ ============================== пробелы и комментарии ==============================

: src-comment? ( -- f )                   \ курсор стоит на "--"?
    src-peek [char] - = if
        src-pos @ 1+ src-len @ < if
            src-a @ src-pos @ 1+ + c@ [char] - =
        else false then
    else false then ;

: src-skip-ws ( -- )
    begin src-peek fl-ws? while src-next drop repeat ;

: src-skip-comment ( -- )                 \ курсор на "--": до конца строки
    src-next drop src-next drop
    begin
        src-peek -1 = if exit then
        src-peek 10 = if exit then
        src-next drop
    again ;

: src-trivia ( -- )                       \ пробелы и комментарии, пока есть
    begin
        src-skip-ws
        src-comment? if src-skip-comment false else true then
    until ;

\ ============================== синтаксическая ошибка ==============================

: fl-syntax-error ( -- )
    ." flua: syntax error at offset " src-pos @ . cr
    -1 throw ;

\ ============================== лексеры ==============================

: src-ident ( -- a u )                    \ [A-Za-z_][A-Za-z0-9_]*
    src-eof? if 0 0 exit then
    0 src-at fl-alpha? 0= if 0 0 exit then
    src-a @ src-pos @ +
    begin src-peek fl-alnum? while src-next drop repeat
    src-a @ src-pos @ + over - ;

variable strq                             \ закрывающая кавычка текущей строки

: fl-parse-string ( -- )                  \ курсор на открывающей кавычке
    src-next strq !
    [char] s emit-ch [char] \ emit-ch [char] " emit-ch emit-bl   \ s"<пробел>
    begin
        src-eof? abort" flua: unterminated string"
        src-next
        dup strq @ = if                   \ закрывающая кавычка
            drop [char] " emit-ch emit-bl m-push-tmp m-push-tmp exit
        then
        dup [char] \ = if                 \ escape из Lua → escape в s\"
            drop src-next
            [char] \ emit-ch
            dup [char] n = if drop [char] n emit-ch else
            dup [char] t = if drop [char] t emit-ch else
            dup [char] \ = if drop [char] \ emit-ch else
            dup [char] " = if drop [char] " emit-ch else
            emit-ch
            then then then then
        else
            dup [char] " = if             \ " внутри '...' → \"
                drop [char] \ emit-ch [char] " emit-ch
            else emit-ch then
        then
    again ;

: fl-parse-number ( -- )
    0 src-at [char] 0 = if                \ 0x / 0X → $hex в Forth
        1 src-at [char] x = 1 src-at [char] X = or if
            [char] $ emit-ch
            src-next drop src-next drop
            begin src-peek fl-hexd? while src-next emit-ch repeat
            emit-bl m-push-tmp exit
        then
    then
    begin src-peek fl-digit? while src-next emit-ch repeat
    emit-bl m-push-tmp ;

\ ============================== параметры как структуры (fenum ulist) ==============================
\ Структура параметра (param%):
\   [0] name-a  [1] name-u  [2] count  [3] used
\ Список адресов — ulist fenum: динамический (нет предела «64»),
\ адреса структур хранятся в контейнере (паттерн из README fenum).

4 cells constant param-size
variable fl-params-ul                     \ ulist адресов параметров текущей функции

: param-new ( a u -- p )
    param-size allocate throw >r           \ ( a u ) r: p
    r@ cell+ ! r@ !                       \ name-u в [1], name-a в [0]
    r@ 2 cells + 0 swap !                 \ count = 0
    r@ 3 cells + 0 swap ! r> ;            \ used = 0

: param-name ( p -- a u ) dup @ swap cell+ @ ;
: param-count@ ( p -- n ) 2 cells + @ ;
: param-used@  ( p -- n ) 3 cells + @ ;
: param-count+! ( p -- ) 2 cells + dup @ 1+ swap ! ;
: param-used+!  ( p -- ) 3 cells + dup @ 1+ swap ! ;

\ эмит имён подряд с пробелами: "a b " (как давал старый plist)
: fl-emit-one-name ( p -- ) param-name emit-st emit-bl ;
: fl-emit-names ( -- ) ['] fl-emit-one-name fl-params-ul @ ulist-each ;

\ ---- подсчёт использований параметров (лексический скан тела) ----
variable fl-body-lo  variable fl-body-hi
variable fl-sv                               \ сохранённая позиция курсора
variable fl-cn                              \ счётчик вхождений
variable fl-nna variable fl-nnu             \ needle: имя параметра (для сканера --stack)

\ пропуск строкового литерала (курс на открывающей кавычке)
: fl-skip-string ( -- )
    src-next strq !
    begin
        src-eof? if exit then
        src-next                       \ ( ch )
        dup strq @ = if drop exit then \ закрывающая кавычка
        [char] 92 = if src-next drop then \ escape: пропустить следующий символ
    again ;

\ найти начало токена `end` (мимо строк/комментариев), позицию восстановить
: fl-scan-end ( -- pos )
    src-pos @ fl-sv !
    begin
        src-trivia
        src-eof? if fl-sv @ src-pos ! 0 exit then
        0 src-at [char] " = 0 src-at [char] ' = or if
            fl-skip-string
        else 0 src-at fl-alpha? if
                src-ident
                2dup s" end" compare 0= if
                    swap src-a @ - nip              \ ( позиция начала идента )
                    fl-sv @ src-pos !
                    exit
                else 2drop then
            else
                src-next drop
            then
        then
    again ;

\ сколько раз needle (fl-nna/fl-nnu) встречается как лист в [fl-body-lo, fl-body-hi)
: fl-count ( -- n )
    fl-body-lo @ src-pos !
    0 fl-cn !
    begin
        src-pos @ fl-body-hi @ < while
            src-trivia
            src-pos @ fl-body-hi @ >= if
                fl-body-lo @ src-pos ! fl-cn @ exit
            then
            0 src-at [char] " = 0 src-at [char] ' = or if
                fl-skip-string
            else 0 src-at fl-alpha? if
                    src-ident
                    2dup fl-nna @ fl-nnu @ compare 0= if
                        2drop
                        src-trivia 0 src-at [char] ( <> if 1 fl-cn +! then
                    else 2drop then
                else 0 src-at fl-digit? if
                        begin src-peek fl-digit? while src-next drop repeat
                    else src-next drop then
                then
            then
    repeat
    fl-body-lo @ src-pos !
    fl-cn @ ;

\ индекс параметра по имени в ulist-структуре ( -1 если нет )
variable pi-na  variable pi-nu  variable pi-idx  variable pi-hit

: fl-pi-one ( p -- )
    pi-hit @ 0= if
        dup param-name pi-na @ pi-nu @ compare 0= if
            1 pi-hit !
        else
            1 pi-idx +!
        then
    then drop ;

: fl-param-idx ( a u -- i | -1 )
    pi-nu ! pi-na !                       \ сначала верхний (u) в pi-nu
    0 pi-idx ! 0 pi-hit !
    ['] fl-pi-one fl-params-ul @ ulist-each
    pi-hit @ if pi-idx @ else -1 then ;

\ ============================== парсер выражений (постфиксный вывод) ==============================
\ Приоритет (снизу вверх): .. < + - < * / < унарный - < primary

defer fl-parse-expr                       \ связан с fl-parse-concat ниже

variable fl-karg                           \ аргументов в текущем вызове

: fl-parse-call ( a u -- )                \ имя прочитано, курсор на '('
    2>r src-next drop 0 fl-karg !         \ съесть '('
    src-trivia
    0 src-at [char] ) = if
        src-next drop                     \ пустой список аргументов
    else
        begin
            fl-parse-expr 1 fl-karg +!
            src-trivia
            0 src-at [char] , = if
                src-next drop src-trivia false
            else true then
        until
        0 src-at [char] ) <> abort" flua: expected ')'"
        src-next drop
    then
    2r> emit-st emit-bl                   \ имя в постфиксной позиции
    fl-karg @ m-popn m-push-tmp ;         \ аргументы съедены → один результат

\ ==== режим --stack: подсчёт использований и лист-параметр ====

: emit-uint ( n -- ) s>d <# #s #> emit-st ;

: param-count! ( n p -- ) 2 cells + ! ;

\ xt для ulist-each: сколько раз параметр — лист в теле (0 → ошибка)
: fl-count-one ( p -- )
    dup param-name fl-nnu ! fl-nna !
    dup fl-count swap param-count!
    dup param-count@ 0= if
        cr ." flua: parameter '" param-name type
        ." ' is unused (stack mode)" cr
        -1 throw
    then drop ;

\ Лист-параметр в stack-режиме: поднять значение к месту использования.
\ Последнее использование параметра — extract (d roll), иначе — duplicate.
\ ( d = m-len-1-позиция : 0 = уже на вершине, ничего не эмитим )
: fl-stack-leaf ( a u -- )
    fl-param-idx dup 0< if 2drop fl-syntax-error then
    dup fl-params-ul @ ulist-nth-addr param-used+!
    dup fl-params-ul @ ulist-nth-addr param-count@
    over fl-params-ul @ ulist-nth-addr param-used@ = if
        dup m-find m-len @ 1- over -                         \ ( i slot d )
        dup 0= if 2drop drop else
            dup emit-uint emit-bl s" roll " emit-st
            over m-move-to-top 2drop drop
        then
    else
       
        dup m-find m-len @ 1- over -
        dup 0= if 2drop drop s" dup " emit-st else
            emit-uint emit-bl s" pick " emit-st 2drop
        then
        m-push-tmp
    then ;

: fl-parse-ident-expr ( a u -- )
    src-trivia
    0 src-at [char] ( = if fl-parse-call
    else stack-mode? @ if fl-stack-leaf else emit-st emit-bl then then ;

: fl-parse-primary ( -- )
    src-trivia
    src-eof? if fl-syntax-error then
    0 src-at [char] " = if fl-parse-string exit then
    0 src-at [char] ' = if fl-parse-string exit then
    0 src-at fl-digit? if fl-parse-number exit then
    0 src-at [char] ( = if                \ группировка ( expr )
        src-next drop src-trivia fl-parse-expr src-trivia
        0 src-at [char] ) <> if fl-syntax-error then
        src-next drop exit
    then
    0 src-at fl-alpha? if src-ident fl-parse-ident-expr exit then
    fl-syntax-error ;

defer fl-parse-unary                   \ рекурсивное слово; связано ниже

: fl-parse-unary-1 ( -- )
    src-trivia
    0 src-at [char] - = if
        src-next drop fl-parse-unary
        s" negate " emit-st m-pop m-push-tmp
    else fl-parse-primary then ;

' fl-parse-unary-1 is fl-parse-unary  \ связка рекурсии на верхнем уровне

: fl-parse-term ( -- )
    fl-parse-unary
    begin
        src-trivia
        0 src-at [char] * = if
            src-next drop fl-parse-unary s" * " emit-st 2 m-popn m-push-tmp false
        else
            0 src-at [char] / = if
                src-next drop fl-parse-unary s" / " emit-st 2 m-popn m-push-tmp false
            else true then
        then
    until ;

: fl-parse-additive ( -- )
    fl-parse-term
    begin
        src-trivia
        0 src-at [char] + = if
            src-next drop fl-parse-term s" + " emit-st 2 m-popn m-push-tmp false
        else
            0 src-at [char] - = if
                src-next drop fl-parse-term s" - " emit-st 2 m-popn m-push-tmp false
            else true then
        then
    until ;

: fl-parse-concat ( -- )
    fl-parse-additive
    begin
        src-trivia
        0 src-at [char] . = 1 src-at [char] . = and if
            src-next drop src-next drop
            src-trivia fl-parse-additive
            s" s+ " emit-st 4 m-popn m-push-tmp m-push-tmp false
        else true then
    until ;

' fl-parse-concat is fl-parse-expr        \ связка defer (только на верхнем уровне)

\ ============================== определение функции ==============================

variable fl-fname-a
variable fl-fname-u
variable fl-param-count
: fl-parse-function ( -- )
    src-trivia src-ident                  \ имя функции
    fl-fname-u ! fl-fname-a !
    src-trivia
    0 src-at [char] ( <> if fl-syntax-error then
    src-next drop                         \ съесть '('
    ulist-new fl-params-ul !
    src-trivia
    0 src-at [char] ) = if                \ () — параметров нет
        src-next drop
    else
        begin
            src-trivia
            src-ident dup 0= if 2drop fl-syntax-error then
            param-new fl-params-ul @ ulist-add
            src-trivia
            0 src-at [char] , = if
                src-next drop false
            else
                0 src-at [char] ) = if
                    src-next drop true
                else fl-syntax-error then
            then
        until
    then
    fl-params-ul @ ulist-reverse            \ ulist-add кладёт в голову: вернуть порядок
    \ модель стека: слоты 0..n-1 = параметры по порядку объявления
    m-reset
    fl-params-ul @ ulist-len 0 ?do i m-append loop
    stack-mode? @ if
        src-pos @ fl-body-lo !
        fl-scan-end fl-body-hi !
        ['] fl-count-one fl-params-ul @ ulist-each
    then
    \ шапка: стековая нотация из входных параметров
    s" \ ( " emit-st
    fl-emit-names
    s" -- r )" emit-st emit-nl
    \ определение слова
    s" : " emit-st fl-fname-a @ fl-fname-u @ emit-st emit-bl
    fl-params-ul @ ulist-len 0> stack-mode? @ 0= and if
        s" { " emit-st fl-emit-names s" }" emit-st
    then
    emit-nl
    \ тело: return expr
    src-trivia
    src-ident 2dup s" return" compare 0<> if 2drop fl-syntax-error then 2drop
    fl-parse-expr emit-nl
    \ конец: end
    src-trivia
    src-ident 2dup s" end" compare 0<> if 2drop fl-syntax-error then 2drop
    s" ;" emit-st emit-nl
    stack-mode? @ if
        m-len @ 1 < if
            cr ." flua: stack mode: empty result (final depth " m-len @ . ." )" cr
            -1 throw
        then
    then
    fl-params-ul @ ulist-dispose ;

\ ============================== компилятор ==============================

: fl-compile ( a u -- )
    src-set emit-reset
    begin
        src-trivia
        src-eof? if exit then
        src-ident 2dup s" function" compare 0<> if 2drop fl-syntax-error then 2drop
        fl-parse-function
    again ;

\ ============================== CLI ==============================

: flua.help ( -- )
    cr
    ." flua v" flua-version type cr
    ." Транспилятор простого подмножества Lua в Forth (VitaSound)." cr cr
    ." Usage:" cr
    ."   flua [file.lua]    компиляция файла, Forth на stdout" cr
    ."   flua               чтение Lua из stdin" cr
    ."   flua --stack f     стековая эмиссия: без { }, pick/roll (флаг: -s)" cr
    ."   flua help          эта справка" cr
    ."   flua version       версия" cr cr
    ." Подмножество Lua: function name(a, b) return expr end," cr
    ." целые (0x hex), строки, + - * /, .. (s+), вызовы слов." cr ;

: flua.version ( -- ) ." flua v" flua-version type cr ;

: flua.compile-cli ( -- )
    s" FLUA_ARG" getenv
    dup 0= if 2drop stdin slurp-fid        \ аргумента нет → stdin
    else slurp-file then                   \ имя файла → содержимое
    fl-compile
    emit-result type cr ;

: flua.read-mode ( -- )
    s" FLUA_MODE" getenv dup 0= if 2drop exit then
    s" stack" compare 0= if true stack-mode? ! then ;

: flua.dispatch ( -- )
    flua.read-mode
    s" FLUA_CMD" getenv
    2dup s" help" compare 0= if 2drop flua.help bye then
    2dup s" version" compare 0= if 2drop flua.version bye then
    2drop
    flua.compile-cli bye ;

\ CLI-диспетчер запускается только при наличии FLUA_CMD (bin/flua);
\ require из тестов его не触发ает.
s" FLUA_CMD" getenv nip [IF] flua.dispatch [THEN]
