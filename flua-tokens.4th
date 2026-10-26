\ flua-tokens.4th — ттокенизатор исходника Lua-подмножества flua.
\
\ Проходит по src-курсору (flua.4th) и заполняет массив токенов:
\   [ type  pos  len ]   — три ячейки на токен
\   type: TK-ID / TK-NUM / TK-STR / TK-OP / TK-CM / TK-EOF
\   pos — позиция в исходнике (для ошибок и codegen-цитат);
\   len — длина в байтах:
\     TK-STR — от открывающей до закрывающей кавычки включительно;
\     TK-CM  — текст комментария после «--» до конца строки;
\     TK-ID  — длина идентификатора; TK-NUM — длина числа;
\     TK-OP  — 1 символ или 2 («..»).
\
\ Подключается из flua-ast.4th (тот в свою очередь — из flua.4th перед CLI),
\ после символьных предикатов, src-курсора и CM-буфера.

[IFDEF] tok-buf [ELSE]

0 constant TK-EOF
1 constant TK-ID
2 constant TK-NUM
3 constant TK-STR
4 constant TK-OP
5 constant TK-CM

4 constant tok-cells
4096 constant tok-max
create tok-buf tok-max tok-cells * cells allot
variable tok-n                          \ сколько токенов
variable tok-i                          \ курсор чтения (парсер)

: tok-rec ( i -- addr ) tok-cells cells * tok-buf + ;

\ type pos len --     записать токен в конец
: tok-push ( type pos len -- )
    tok-n @ tok-max >= abort" flua: token buffer overflow"
    tok-n @ tok-rec >r
    r@ 2 cells + !                      \ len (верхушка стека)
    r@ cell+ !                          \ pos
    r> !                                \ type
    1 tok-n +! ;

\ i -- type pos len
: tok-at ( i -- type pos len )
    tok-rec dup @ swap cell+ dup @ swap cell+ @ ;

: tok-reset ( -- ) 0 tok-n ! 0 tok-i ! ;
: tok-more? ( -- f ) tok-i @ tok-n @ < ;
: tok-cur ( -- type pos len ) tok-i @ tok-at ;
: tok-next ( -- ) 1 tok-i +! ;

\ type pos --          длина = src-pos - pos (курсор уже за токеном)
: tok-span ( type pos -- )
    { type pos }
    type pos src-pos @ pos - tok-push ;

\ ------------------- сканеры токенов -------------------

\ курсор на открывающей кавычке: пропустить строку до закрывающей
\ (эскейп \x съедает два символа); курсор — за закрывающей
: tok-skip-string ( -- )
    src-next strq !
    begin
        src-eof? abort" flua: unterminated string"
        src-next
        dup strq @ = if drop exit then
        [char] \ = if src-next drop then
    again ;

: tok-string ( -- )                    \ курсор на открывающей кавычке
    src-pos @ >r tok-skip-string TK-STR r> tok-span ;

: tok-comment ( -- )                   \ курсор на «--»
    src-next drop src-next drop         \ съесть «--»: pos = начало текста
    src-pos @ >r
    begin
        src-peek -1 = src-peek 10 = or
        if true else src-next drop false then
    until
    TK-CM r> tok-span ;

: tok-number ( -- )                    \ курсор на первой цифре
    src-pos @ >r
    0 src-at [char] 0 = if
        1 src-at [char] x = 1 src-at [char] X = or if
            src-next drop src-next drop \ 0x → код hex-цифр остаётся текстом
            begin src-peek fl-hexd? while src-next drop repeat
            TK-NUM r> tok-span exit
        then
    then
    begin src-peek fl-digit? while src-next drop repeat
    TK-NUM r> tok-span ;

: tok-ident ( -- )                     \ курсор на букве/подчёркивании
    src-pos @ >r src-ident 2drop TK-ID r> tok-span ;

: tok-dot2 ( -- )                      \ «..» — конкатенация
    src-pos @ >r src-next drop src-next drop TK-OP r> tok-span ;

: tok-op1 ( -- )                       \ одиночный операторный символ
    src-pos @ >r src-next drop TK-OP r> tok-span ;

\ текущая пара символов — один из «<=», «>=», «==», «~="?
: tok-pair2? ( -- f )
    src-peek [char] < =
    src-peek [char] > = or
    src-peek [char] = = or
    src-peek [char] ~ = or
    if 1 src-at [char] = = else false then ;

\ «..», «<=», «>=», «==», «~=" — два символа; иначе один
: tok-op2 ( -- )
    src-peek [char] . = 1 src-at [char] . = and if tok-dot2 exit then
    tok-pair2? if
        src-pos @ >r src-next drop src-next drop TK-OP r> tok-span exit
    then
    tok-op1 ;

\ ------------------- основной проход -------------------

: fl-tokenize ( -- )
    tok-reset
    begin
        src-skip-ws                       \ только пробелы: комменты должны
                                          \ попасть в токены TK-CM (trivia
                                          \ их съедает без следа)
        src-eof? if TK-EOF src-pos @ 0 tok-push exit then
        0 src-at [char] " = 0 src-at [char] ' = or if tok-string else
        0 src-at fl-digit? if tok-number else
        0 src-at fl-alpha? if tok-ident else
        src-comment? if tok-comment else
            tok-op2
        then then then then
    again ;

[THEN]
