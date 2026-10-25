\ flua-ast.4th — вывод AST (фаза 2 конвейера flua: токены → дерево).
\
\ Узел — запись из 7 ячеек (allocate), поля — смещения в ячейках:
\   an-type — ANT-NUM | ANT-STR | ANT-ID | ANT-BIN | ANT-UN | ANT-CALL | ANT-FN
\   an-pa / an-pu — позиция и длина текста узла в исходнике (src)
\   an-op — ANT-BIN: ASCII-код оператора; OP-CONCAT (256) — «..»
\   an-l   — ANT-BIN: левый операнд; ANT-UN: операнд; ANT-FN: тело
\   an-r   — ANT-BIN: правый операнд
\   an-aux — ANT-CALL: аргументы, ANT-FN: параметры (ulist узлов); 0 иначе
\
\ Текст узла задаётся парой (pa, pu): печать цитирует src напрямую, без
\ копий. Все узлы регистрируются в an-nodes; an-reset освобождает их
\ вместе с контейнерами aux — повторный разбор без утечек.
\
\ Подключается из flua.4th (перед CLI): нужны emit-*, src-*, ulist.
\ Вход — токены flua-tokens.4th; комментарии TK-CM — trivia.
\ Грамматика подмножества (как у основного конвейера):
\   program  := ( function )* EOF
\   function := 'function' ID '(' params ')' 'return' expr 'end'
\   expr     := concat; concat < additive < term < unary < primary

require ./flua-tokens.4th

[IFDEF] an-node [ELSE]

0 constant ANT-NUM
1 constant ANT-STR
2 constant ANT-ID
3 constant ANT-BIN
4 constant ANT-UN
5 constant ANT-CALL
6 constant ANT-FN

256 constant OP-CONCAT                   \ «..» — не ASCII-символ

\ смещения полей узла (в ячейках) и размер записи
0 constant an-type
1 constant an-pa
2 constant an-pu
3 constant an-op
4 constant an-l
5 constant an-r
6 constant an-aux
7 constant an-cells

\ ================= токен-доступ (поверх flua-tokens) =================

: tok-end? ( -- f ) tok-i @ tok-n @ >= ;

\ за концом потока — TK-EOF и конец src: ошибка печатает позицию
: tok-t ( -- n ) tok-end? if TK-EOF else tok-i @ tok-rec @ then ;
: tok-p ( -- n ) tok-end? if src-len @ else tok-i @ tok-rec cell+ @ then ;
: tok-l ( -- n ) tok-end? if 0 else tok-i @ tok-rec 2 cells + @ then ;
: tok-text ( -- a u ) src-a @ tok-p + tok-l ;

\ пропустить комментарии — trivia токен-потока
: tok-skip-cm ( -- )
    begin tok-more? while
        tok-t TK-CM <> if exit then
        tok-next
    repeat ;

: fl-p-error ( -- )
    ." flua: syntax error at offset " tok-p . cr -1 throw ;

\ текущий значимый токен — ключевое слово a u?
: tok-kw? ( a u -- f )
    { a u }
    tok-skip-cm
    tok-t TK-ID = 0= if false exit then
    tok-text a u compare 0= ;

\ текущий значимый токен — одиночный оператор c?
: tok-op? ( c -- f )
    { c }
    tok-skip-cm
    tok-t TK-OP = 0= if false exit then
    tok-l 1 <> if false exit then
    src-a @ tok-p + c@ c = ;

\ код текущего одиночного оператора; 0 — не одиночный оператор
: tok-opc ( -- c )
    tok-skip-cm
    tok-t TK-OP = 0= if 0 exit then
    tok-l 1 <> if 0 exit then
    src-a @ tok-p + c@ ;

\ текущий значимый токен — «..»?
: tok-dot2? ( -- f )
    tok-skip-cm
    tok-t TK-OP = 0= if false exit then
    tok-l 2 <> if false exit then
    src-a @ tok-p + dup c@ [char] . =
    if 1+ c@ [char] . = else drop false then ;

\ ================= узлы =================

variable an-nodes                        \ реестр узлов текущего разбора
variable an-root                         \ функции верхнего уровня
ulist-new an-nodes !
ulist-new an-root !

: an@ ( m off -- n ) cells + @ ;
: an! ( n m off -- ) cells + ! ;

\ освободить узел: контейнер aux (аргументы/параметры) и сама запись
: an-free-one ( m -- )
    dup an-aux an@ ?dup if ulist-dispose then
    free throw ;

\ освободить всё, что построено предыдущим разбором
: an-reset ( -- )
    ['] an-free-one an-nodes @ ulist-each
    an-nodes @ ulist-clear
    an-root @ ulist-clear ;

\ type -- m: обнулённый узел, зарегистрированный в an-nodes
: an-node ( type -- m )
    an-cells cells allocate throw         \ ( type addr )
    >r r@ an-cells cells erase r@ !       \ type → поле [0]
    r@ an-nodes @ ulist-add
    r> ;

\ ---------------- конструкторы ----------------

: an-num ( pa pu -- m )
    { pa pu }
    ANT-NUM an-node { m }
    pa m an-pa an!
    pu m an-pu an!
    m ;

: an-str ( pa pu -- m )
    { pa pu }
    ANT-STR an-node { m }
    pa m an-pa an!
    pu m an-pu an!
    m ;

: an-id ( pa pu -- m )
    { pa pu }
    ANT-ID an-node { m }
    pa m an-pa an!
    pu m an-pu an!
    m ;

: an-bin ( op l r -- m )
    { op l r }
    ANT-BIN an-node { m }
    op m an-op an!
    l m an-l an!
    r m an-r an!
    m ;

: an-un ( x -- m )
    { x }
    ANT-UN an-node { m }
    x m an-l an!
    m ;

: an-call ( pa pu args -- m )
    { pa pu args }
    ANT-CALL an-node { m }
    pa m an-pa an!
    pu m an-pu an!
    args m an-aux an!
    m ;

: an-fn ( pa pu params body -- m )
    { pa pu params body }
    ANT-FN an-node { m }
    pa m an-pa an!
    pu m an-pu an!
    params m an-aux an!
    body m an-l an!
    m ;

\ ================= парсер =================
\ Приоритет (снизу вверх): .. < + - < * / < унарный - < primary

defer fl-p-expr                          \ верхний уровень выражения
defer fl-p-unary                         \ рекурсивное слово

\ курсор на «(» после имени: ( pa pu -- m )
: fl-p-call ( pa pu -- m )
    { pa pu }
    ulist-new { args }
    tok-next                             \ съесть «(»
    [char] ) tok-op? if
        tok-next                         \ пустой список аргументов
    else
        begin
            fl-p-expr                    \ ( node )
            args ulist-add               \ prepend → reverse ниже
            [char] , tok-op? if
                tok-next false
            else
                [char] ) tok-op? 0= if fl-p-error then
                true
            then
        until
        tok-next                         \ съесть «)»
    then
    args ulist-reverse                   \ порядок чтения аргументов
    pa pu args an-call ;

\ курсор на значимом TK-ID: имя прочитано → идентификатор или вызов
: fl-p-name ( -- m )
    tok-p tok-l { pa pu }
    tok-next
    pa pu                             \ аргументы обоих исходов до ветвления
    [char] ( tok-op? if fl-p-call else an-id then ;

: fl-p-primary ( -- m )
    tok-skip-cm
    tok-t TK-NUM = if tok-p tok-l an-num tok-next exit then
    tok-t TK-STR = if tok-p tok-l an-str tok-next exit then
    tok-t TK-ID  = if fl-p-name exit then
    [char] ( tok-op? if                 \ группировка ( expr ): прозрачна
        tok-next fl-p-expr
        [char] ) tok-op? 0= if fl-p-error then
        tok-next exit
    then
    fl-p-error ;

: fl-p-unary-1 ( -- m )
    [char] - tok-op? if
        tok-next fl-p-unary
        an-un
    else
        fl-p-primary
    then ;

' fl-p-unary-1 is fl-p-unary

\ уровень * /: ( op l r ) собирается через r-stack — общего состояния
\ нет, вложенные вызовы (аргументы) не затирают оператор
: fl-p-term ( -- m )
    fl-p-unary
    begin
        tok-opc dup [char] * = over [char] / = or if
            \ ( l c )
            tok-next fl-p-unary            \ ( l c r )
            >r swap r>                    \ ( c l r )
            an-bin
            false
        else
            drop true
        then
    until ;

: fl-p-additive ( -- m )
    fl-p-term
    begin
        tok-opc dup [char] + = over [char] - = or if
            tok-next fl-p-term
            >r swap r> an-bin
            false
        else
            drop true
        then
    until ;

: fl-p-concat ( -- m )
    fl-p-additive
    begin
        tok-dot2? if
            tok-next fl-p-additive        \ ( l r )
            OP-CONCAT -rot                \ ( op l r )
            an-bin
            false
        else
            true
        then
    until ;

' fl-p-concat is fl-p-expr

\ ---------------- функция ----------------

variable fl-p-na variable fl-p-nu         \ имя текущей функции
variable fl-p-params                      \ параметры текущей функции (ulist)

: fl-p-function ( -- m )
    tok-next                             \ съесть «function»
    tok-skip-cm
    tok-t TK-ID = 0= if fl-p-error then
    tok-p fl-p-na ! tok-l fl-p-nu !
    tok-next
    [char] ( tok-op? 0= if fl-p-error then
    tok-next                             \ съесть «(»
    ulist-new fl-p-params !
    [char] ) tok-op? if
        tok-next                         \ () — параметров нет
    else
        begin
            tok-skip-cm
            tok-t TK-ID = 0= if fl-p-error then
            tok-p tok-l an-id fl-p-params @ ulist-add
            tok-next
            [char] , tok-op? if
                tok-next false
            else
                [char] ) tok-op? 0= if fl-p-error then
                true
            then
        until
        tok-next                         \ съесть «)»
    then
    fl-p-params @ ulist-reverse          \ ulist-add в голову → порядок чтения
    s" return" tok-kw? 0= if fl-p-error then
    tok-next
    fl-p-expr                            \ ( body )
    s" end" tok-kw? 0= if fl-p-error then
    tok-next
    >r                                   \ r: body
    fl-p-na @ fl-p-nu @ fl-p-params @ r>
    an-fn ;

\ ---------------- файл ----------------

: fl-p-program ( -- )
    an-reset
    fl-tokenize
    begin
        tok-skip-cm
        tok-t TK-EOF = if
            an-root @ ulist-reverse exit  \ обход ulist-add → порядок чтения
        then
        s" function" tok-kw? 0= if fl-p-error then
        fl-p-function an-root @ ulist-add
        false                             \ gforth: repeat требует while → until
    until ;

\ ================= печать AST в emit-buf =================

variable an-d                            \ текущий уровень отступа

\ текст узла — цитата из исходника
: an-text ( m -- a u )
    { m } src-a @ m an-pa an@ + m an-pu an@ ;

: an-indent ( -- ) an-d @ 0 ?do emit-bl emit-bl loop ;

\ параметры (id-узлы): «a, b»
: an-params ( lst -- )
    { lst }
    lst ulist-len 0 ?do
        i 0> if s" , " emit-st then
        i lst ulist-nth-addr an-text emit-st
    loop ;

: an-op-emit ( op -- )
    dup OP-CONCAT = if drop s" .." emit-st else emit-ch then ;

\ узел → emit-buf: строка узла, затем дочерние на уровень глубже
: an-print ( m -- )
    { m }
    an-indent
    m an-type an@ case
        ANT-NUM of s" num " emit-st m an-text emit-st emit-nl endof
        ANT-STR of s" str " emit-st m an-text emit-st emit-nl endof
        ANT-ID  of s" id "  emit-st m an-text emit-st emit-nl endof
        ANT-BIN of
            s" bin " emit-st m an-op an@ an-op-emit emit-nl
            1 an-d +!
            m an-l an@ recurse
            m an-r an@ recurse
            -1 an-d +!
        endof
        ANT-UN of
            s" un -" emit-st emit-nl
            1 an-d +!
            m an-l an@ recurse
            -1 an-d +!
        endof
        ANT-CALL of
            s" call " emit-st m an-text emit-st emit-nl
            1 an-d +!
            m an-aux an@ ulist-len 0 ?do
                i m an-aux an@ ulist-nth-addr recurse
            loop
            -1 an-d +!
        endof
        ANT-FN of
            s" fn " emit-st m an-text emit-st
            [char] ( emit-ch
            m an-aux an@ an-params
            [char] ) emit-ch emit-nl
            1 an-d +!
            m an-l an@ recurse
            -1 an-d +!
        endof
        true abort" flua: internal AST error: bad node type"
    endcase ;

\ ================= разбор и вывод файла =================

\ ( a u -- ) разобрать исходник, построить AST и напечатать его в emit-buf
: fl-ast-run ( a u -- )
    src-set emit-reset
    fl-p-program
    0 an-d !
    ['] an-print an-root @ ulist-each ;

[THEN]
