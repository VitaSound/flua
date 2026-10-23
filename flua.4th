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
            drop [char] " emit-ch emit-bl exit
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
            emit-bl exit
        then
    then
    begin src-peek fl-digit? while src-next emit-ch repeat
    emit-bl ;

\ ============================== парсер выражений (постфиксный вывод) ==============================
\ Приоритет (снизу вверх): .. < + - < * / < унарный - < primary

defer fl-parse-expr                       \ связан с fl-parse-concat ниже

: fl-parse-call ( a u -- )                \ имя прочитано, курсор на '('
    2>r src-next drop                     \ съесть '('
    src-trivia
    0 src-at [char] ) = if
        src-next drop                     \ пустой список аргументов
    else
        begin
            fl-parse-expr
            src-trivia
            0 src-at [char] , = if
                src-next drop src-trivia false
            else true then
        until
        0 src-at [char] ) <> abort" flua: expected ')'"
        src-next drop
    then
    2r> emit-st emit-bl ;                 \ имя в постфиксной позиции

: fl-parse-ident-expr ( a u -- )
    src-trivia
    0 src-at [char] ( = if fl-parse-call
    else emit-st emit-bl then ;           \ ссылка на параметр

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
        s" negate " emit-st
    else fl-parse-primary then ;

' fl-parse-unary-1 is fl-parse-unary  \ связка рекурсии на верхнем уровне

: fl-parse-term ( -- )
    fl-parse-unary
    begin
        src-trivia
        0 src-at [char] * = if
            src-next drop fl-parse-unary s" * " emit-st false
        else
            0 src-at [char] / = if
                src-next drop fl-parse-unary s" / " emit-st false
            else true then
        then
    until ;

: fl-parse-additive ( -- )
    fl-parse-term
    begin
        src-trivia
        0 src-at [char] + = if
            src-next drop fl-parse-term s" + " emit-st false
        else
            0 src-at [char] - = if
                src-next drop fl-parse-term s" - " emit-st false
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
            s" s+ " emit-st false
        else true then
    until ;

' fl-parse-concat is fl-parse-expr        \ связка defer (только на верхнем уровне)

\ ============================== определение функции ==============================

variable fl-fname-a
variable fl-fname-u
variable fl-param-count
variable plen
create plist 512 allot

: plist-reset ( -- ) 0 plen ! ;

: plist-add ( a u -- )
    dup >r
    plist plen @ + swap cmove
    r@ plen +!
    bl plist plen @ + c!
    1 plen +!
    rdrop ;

: fl-parse-function ( -- )
    src-trivia src-ident                  \ имя функции
    fl-fname-u ! fl-fname-a !
    src-trivia
    0 src-at [char] ( <> if fl-syntax-error then
    src-next drop                         \ съесть '('
    plist-reset 0 fl-param-count !
    src-trivia
    0 src-at [char] ) = if                \ () — параметров нет
        src-next drop
    else
        begin
            src-trivia
            src-ident dup 0= if 2drop fl-syntax-error then
            plist-add 1 fl-param-count +!
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
    \ шапка: стековая нотация из входных параметров
    s" \ ( " emit-st
    plist plen @ emit-st
    s" -- r )" emit-st emit-nl
    \ определение слова
    s" : " emit-st fl-fname-a @ fl-fname-u @ emit-st emit-bl
    fl-param-count @ 0> if
        s" { " emit-st plist plen @ emit-st s" }" emit-st
    then
    emit-nl
    \ тело: return expr
    src-trivia
    src-ident 2dup s" return" compare 0<> if 2drop fl-syntax-error then 2drop
    fl-parse-expr emit-nl
    \ конец: end
    src-trivia
    src-ident 2dup s" end" compare 0<> if 2drop fl-syntax-error then 2drop
    s" ;" emit-st emit-nl ;

\ ============================== компилятор ==============================

: fl-compile ( a u -- )
    src-set emit-reset plist-reset
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

: flua.dispatch ( -- )
    s" FLUA_CMD" getenv
    2dup s" help" compare 0= if 2drop flua.help bye then
    2dup s" version" compare 0= if 2drop flua.version bye then
    2drop
    flua.compile-cli bye ;

\ CLI-диспетчер запускается только при наличии FLUA_CMD (bin/flua);
\ require из тестов его не触发ает.
s" FLUA_CMD" getenv nip [IF] flua.dispatch [THEN]
