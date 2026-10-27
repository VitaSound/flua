\ flua-ast.4th — вывод AST (фаза 2 конвейера flua: токены → дерево).
\
\ Узел — запись из 7 ячеек (allocate), поля — смещения в ячейках:
\   an-type — ANT-NUM | ANT-STR | ANT-ID | ANT-BIN | ANT-UN | ANT-CALL | ANT-FN
\             | ANT-TABLE | ANT-INDEX | ANT-FIELD | …
\   an-pa / an-pu — позиция и длина текста узла в исходнике (src)
\   an-op — ANT-BIN: ASCII-код оператора; OP-CONCAT (256) — «..»
\           ANT-UN: [char] - или OP-NOT (261)
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
\ Грамматика подмножества (как у основного конвейера / AGENTS.md):
\   program  := ( function | assign | expr | print )* EOF
\   function := [pragmas] 'function' ID '(' params ')' stmts 'end'
\   stmts    := ( local | assign | return | if | while | repeat | call )*
\   if       := 'if' expr 'then' stmts
\               ( 'elseif' expr 'then' stmts )* [ 'else' stmts ] 'end'
\   while    := 'while' expr 'do' stmts 'end'
\   repeat   := 'repeat' stmts 'until' expr
\   expr     := or < and < relational < concat < additive < term < unary < primary

require ./flua-tokens.4th

[IFDEF] an-node [ELSE]

0 constant ANT-NUM
1 constant ANT-STR
2 constant ANT-ID
3 constant ANT-BIN
4 constant ANT-UN
5 constant ANT-CALL
6 constant ANT-FN
7 constant ANT-IF
8 constant ANT-BR
9 constant ANT-ASSIGN                   \ ID '=' expr (имя pa/pu, expr an-l)
10 constant ANT-LOCAL                   \ local ID '=' expr
11 constant ANT-RET                     \ return [expr (, expr)*]; aux = ulist exprs
12 constant ANT-WHILE                   \ while: cond an-l, body an-aux
13 constant ANT-REPEAT                  \ repeat: body an-aux, cond an-l
14 constant ANT-FOR                     \ for i=lo,hi: pa/pu=i, an-l=lo, an-r=hi, an-aux=body
15 constant ANT-TABLE                   \ {…}: an-op=0 map / 1 list; an-aux=fields
16 constant ANT-INDEX                   \ t[k] / t.a: an-l=container, an-r=key
17 constant ANT-FIELD                   \ map-поле: pa/pu=ключ-id, an-l=value

0 constant TABLE-MAP
1 constant TABLE-LIST

256 constant OP-CONCAT                   \ «..» — не ASCII-символ
257 constant OP-LE                       \ «<=»
258 constant OP-GE                       \ «>=»
259 constant OP-EQ                       \ «==» (печать «=»)
260 constant OP-NE                       \ «~=" (печать «<>»)

261 constant OP-NOT                      \ «not» — унарный (антипод '-')
262 constant OP-AND                      \ «and» — бинарный, шорт-кircuit
263 constant OP-OR                       \ «or» — бинарный, шорт-кircuit

\ смещения полей узла (в ячейках) и размер записи
0 constant an-type
1 constant an-pa
2 constant an-pu
3 constant an-op
4 constant an-l
5 constant an-r
6 constant an-aux
7 constant an-flags                     \ ANT-FN: биты прагм (@stack/@proc)
8 constant an-cells

1 constant FN-STACK                     \ -- @stack
2 constant FN-PROC                      \ -- @proc

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
    tok-p fl-syntax-error ;

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

\ серия комментариев непосредственно перед значимым токеном: без копирования
\ в cm-buf — диапазон токенов (fl-hdr-i0, fl-hdr-i1) сохраняется в узле
\ функции (an-op/an-r), копия в cm-buf — в fl-gen-fn кодогенератора
variable fl-hdr-i0                      \ первый токен серии (включая CM)
variable fl-hdr-i1                      \ токен-граница: значимый после серии

\ разобрать тело CM «@forth name ( a b -- c d )» → fl-forth-add
\ клетки = число идентификаторов по обе стороны от «--»
variable ff-a variable ff-u variable ff-i
variable ff-na variable ff-nu
variable ff-in variable ff-out variable ff-side
variable ff-wa variable ff-wu

: ff-skip-bl ( -- )
    begin
        ff-i @ ff-u @ >= if exit then
        ff-a @ ff-i @ + c@ bl <=
    while 1 ff-i +! repeat ;

: ff-take-word ( -- a u | 0 0 )
    ff-skip-bl
    ff-i @ ff-u @ >= if 0 0 exit then
    ff-a @ ff-i @ + ff-wa !
    0 ff-wu !
    begin
        ff-i @ ff-u @ >= if ff-wa @ ff-wu @ exit then
        ff-a @ ff-i @ + c@ dup bl <= if
            drop ff-wa @ ff-wu @ exit
        then
        [char] ( = if ff-wa @ ff-wu @ exit then
        1 ff-i +! 1 ff-wu +!
    again ;

: ff-cell-tok? ( a u -- f )               \ не «--», не «)»
    2dup s" --" compare 0= if 2drop false exit then
    2dup s" )" compare 0= if 2drop false exit then
    nip 0<> ;

: ff-trim ( a u -- a u )                  \ локальный trim (fl-trim ниже по файлу)
    begin dup while over c@ bl <= while 1 /string repeat then
    begin dup while 2dup + 1- c@ bl <= while 1- repeat then ;

: fl-forth-parse-cm ( a u -- )
    ff-trim { a u }
    u 6 < if exit then                    \ «@forth» = 6
    a 6 s" @forth" compare 0= 0= if exit then
    a u 6 /string ff-trim                 \ снять префикс
    dup 0= if 2drop
        cr ." flua: @forth: missing word name" cr -1 throw
    then
    ff-u ! ff-a ! 0 ff-i !
    ff-take-word dup 0= if 2drop
        cr ." flua: @forth: missing word name" cr -1 throw
    then
    ff-nu ! ff-na !
    ff-skip-bl
    ff-i @ ff-u @ >= if
        cr ." flua: @forth: expected ( ... )" cr -1 throw
    then
    ff-a @ ff-i @ + c@ [char] ( <> if
        cr ." flua: @forth: expected ( ... )" cr -1 throw
    then
    1 ff-i +!                            \ съесть '('
    0 ff-in ! 0 ff-out ! 0 ff-side !     \ 0=in, 1=out
    begin
        ff-take-word dup 0= if 2drop
            cr ." flua: @forth: unclosed )" cr -1 throw
        then
        2dup s" --" compare 0= if
            2drop 1 ff-side ! false
        else 2dup s" )" compare 0= if
            2drop true
        else
            ff-cell-tok? 0= if
                cr ." flua: @forth: bad stack comment" cr -1 throw
            then
            ff-side @ if 1 ff-out +! else 1 ff-in +! then
            false
        then
        then
    until
    ff-na @ ff-nu @ ff-in @ ff-out @ fl-forth-add ;

\ -- @require path  /  -- @fpath dir  (тело CM после «--»)
: fl-require-parse-cm ( a u -- f )        \ true = обработано
    ff-trim { a u }
    u 8 < if false exit then
    a 8 s" @require" compare 0= 0= if false exit then
    a u 8 /string ff-trim
    dup 0= if 2drop
        cr ." flua: @require: missing path" cr -1 throw
    then
    fl-require-add true ;

: fl-fpath-parse-cm ( a u -- f )
    ff-trim { a u }
    u 6 < if false exit then
    a 6 s" @fpath" compare 0= 0= if false exit then
    a u 6 /string ff-trim
    dup 0= if 2drop
        cr ." flua: @fpath: missing path" cr -1 throw
    then
    fl-fpath-add true ;

: fl-pragma-parse-cm ( a u -- )
    2dup fl-require-parse-cm if 2drop exit then
    2dup fl-fpath-parse-cm   if 2drop exit then
    fl-forth-parse-cm ;

: fl-p-hdr-cm ( -- )
    tok-i @ fl-hdr-i0 !                 \ до серии CM (или пусто: i0 = i1)
    begin tok-t TK-CM = while
        tok-text fl-pragma-parse-cm
        tok-next
    repeat
    tok-i @ fl-hdr-i1 ! ;

\ ================= узлы =================

variable an-nodes                        \ реестр узлов текущего разбора
variable an-root                         \ функции верхнего уровня
addrlist-new an-nodes !
addrlist-new an-root !

: an@ ( m off -- n ) cells + @ ;
: an! ( n m off -- ) cells + ! ;

\ освободить узел: контейнер aux (аргументы/параметры) и сама запись
: an-free-one ( m -- )
    dup an-aux an@ ?dup if addrlist-dispose then
    dup an-type an@ ANT-FN = if
        dup an-l an@ ?dup if addrlist-dispose then
    then
    free throw ;

\ освободить всё, что построено предыдущим разбором
: an-reset ( -- )
    ['] an-free-one an-nodes @ addrlist-each
    an-nodes @ addrlist-clear
    an-root @ addrlist-clear ;

\ type -- m: обнулённый узел, зарегистрированный в an-nodes
: an-node ( type -- m )
    an-cells cells allocate throw         \ ( type addr )
    >r r@ an-cells cells erase r@ !       \ type → поле [0]
    r@ an-nodes @ addrlist-add
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

: an-un ( op x -- m )                    \ унарный: '-' или OP-NOT
    { op x }
    ANT-UN an-node { m }
    op m an-op an!
    x m an-l an!
    m ;

: an-call ( pa pu args -- m )
    { pa pu args }
    ANT-CALL an-node { m }
    pa m an-pa an!
    pu m an-pu an!
    args m an-aux an!
    m ;

: an-fn ( pa pu params stmts -- m )
    { pa pu params stmts }
    ANT-FN an-node { m }
    pa m an-pa an!
    pu m an-pu an!
    params m an-aux an!
    stmts m an-l an!                     \ тело: ulist stmt'ов
    0 m an-flags an!
    m ;

\ assign/local: pa/pu = первое имя; an-aux = ulist всех имён (an-id); an-l = expr
: an-assign ( names expr -- m )
    { names expr }
    ANT-ASSIGN an-node { m }
    0 names addrlist-nth-addr { id0 }
    id0 an-pa an@ m an-pa an!
    id0 an-pu an@ m an-pu an!
    names m an-aux an!
    expr m an-l an! m ;

: an-local ( names expr -- m )
    { names expr }
    ANT-LOCAL an-node { m }
    0 names addrlist-nth-addr { id0 }
    id0 an-pa an@ m an-pa an!
    id0 an-pu an@ m an-pu an!
    names m an-aux an!
    expr m an-l an! m ;

: an-ret ( exprs -- m )                  \ ulist выражений (0 = пустой return)
    { exprs }
    ANT-RET an-node { m }
    exprs m an-aux an! m ;

: an-while ( cond body -- m )
    { cond body }
    ANT-WHILE an-node { m }
    cond m an-l an! body m an-aux an! m ;

: an-repeat ( body cond -- m )
    { body cond }
    ANT-REPEAT an-node { m }
    body m an-aux an! cond m an-l an! m ;

: an-for ( pa pu lo hi body -- m )
    { pa pu lo hi body }
    ANT-FOR an-node { m }
    pa m an-pa an! pu m an-pu an!
    lo m an-l an! hi m an-r an!
    body m an-aux an! m ;

: an-table ( kind fields -- m )
    { kind fields }
    ANT-TABLE an-node { m }
    kind m an-op an!
    fields m an-aux an!
    m ;

: an-index ( container key -- m )
    { container key }
    ANT-INDEX an-node { m }
    container m an-l an!
    key m an-r an!
    m ;

: an-field ( pa pu val -- m )
    { pa pu val }
    ANT-FIELD an-node { m }
    pa m an-pa an!
    pu m an-pu an!
    val m an-l an!
    m ;

\ assign с LHS = индекс (an-aux=0, an-r=ANT-INDEX, an-l=expr)
: an-idx-assign ( idx expr -- m )
    { idx expr }
    ANT-ASSIGN an-node { m }
    0 m an-aux an!
    idx m an-r an!
    expr m an-l an!
    idx an-l an@ { c }
    c an-pa an@ m an-pa an!
    c an-pu an@ m an-pu an!
    m ;

\ trim пробелов по краям (a u -- a' u')
: fl-trim-lead ( a u -- a u )
    begin dup while over c@ bl <= while 1 /string repeat then ;
: fl-trim-trail ( a u -- a u )
    begin dup while 2dup + 1- c@ bl <= while 1- repeat then ;
: fl-trim ( a u -- a u ) fl-trim-lead fl-trim-trail ;

\ тело TK-CM (после «--») — ровно needle (с trim)?
: fl-cm-is ( a u needle-a needle-u -- f )
    2swap fl-trim 2swap compare 0= ;

variable fl-pragma-acc

\ просканировать hdr CM-диапазон fn → биты FN-STACK / FN-PROC в an-flags
: fl-fn-scan-pragmas ( fn -- )
    { fn }
    0 fl-pragma-acc !
    tok-i @ >r
    fn an-op an@ tok-i !
    begin tok-i @ fn an-r an@ < while
        tok-t TK-CM = if
            tok-text
            2dup s" @stack" fl-cm-is if FN-STACK fl-pragma-acc @ or fl-pragma-acc ! then
            2dup s" @proc"  fl-cm-is if FN-PROC  fl-pragma-acc @ or fl-pragma-acc ! then
            2drop
        then
        tok-next
    repeat
    r> tok-i !
    fl-pragma-acc @ fn an-flags an! ;

\ ветка if: cond — условие (0 — для else), stmts — ulist операторов ветки
: an-br ( cond stmts -- m )
    { cond stmts }
    ANT-BR an-node { m }
    cond m an-l an!
    stmts m an-aux an!
    m ;

\ if: aux — ulist веток ANT-BR (первая, затем elseif…, затем else)
: an-if ( branches -- m )
    { branches }
    ANT-IF an-node { m }
    branches m an-aux an!
    m ;

\ ================= парсер =================
\ Приоритет (снизу вверх): or < and < сравнения < .. < + - < * / %
\                          < унарный (- not) < primary

defer fl-p-expr                          \ верхний уровень выражения
defer fl-p-unary                         \ рекурсивное слово

\ курсор на «(» после имени: ( pa pu -- m )
: fl-p-call ( pa pu -- m )
    { pa pu }
    addrlist-new { args }
    tok-next                             \ съесть «(»
    [char] ) tok-op? if
        tok-next                         \ пустой список аргументов
    else
        begin
            fl-p-expr                    \ ( node )
            args addrlist-add               \ prepend → reverse ниже
            [char] , tok-op? if
                tok-next false
            else
                [char] ) tok-op? 0= if fl-p-error then
                true
            then
        until
        tok-next                         \ съесть «)»
    then
    args addrlist-reverse                   \ порядок чтения аргументов
    pa pu args an-call ;

\ курсор на значимом TK-ID: имя прочитано → идентификатор или вызов
: fl-p-name ( -- m )
    tok-p tok-l { pa pu }
    tok-next
    pa pu                             \ аргументы обоих исходов до ветвления
    [char] ( tok-op? if fl-p-call else an-id then ;

\ postfix [expr] / .ID → ANT-INDEX (ключ-строка для .ID = ANT-STR по тексту id)
: fl-p-postfix ( m -- m )
    begin
        tok-skip-cm
        [char] [ tok-op? if
            tok-next fl-p-expr
            [char] ] tok-op? 0= if fl-p-error then
            tok-next an-index
            false
        else
            [char] . tok-op? if
                tok-next
                tok-skip-cm
                tok-t TK-ID = 0= if fl-p-error then
                tok-p tok-l an-str { key }
                tok-next
                key an-index
                false
            else
                true
            then
        then
    until ;

\ id '=' на текущей позиции? (lookahead, курсор не двигаем)
: fl-p-map-entry? ( -- f )
    tok-skip-cm
    tok-t TK-ID = 0= if false exit then
    tok-i @ >r
    tok-next
    [char] = tok-op?
    r> tok-i ! ;

: fl-p-table ( -- m )
    tok-next                             \ съесть «{»
    addrlist-new { fields }
    tok-skip-cm
    [char] } tok-op? if                  \ {} → пустой map
        tok-next
        TABLE-MAP fields an-table exit
    then
    fl-p-map-entry? { is-map }
    begin
        tok-skip-cm
        [char] } tok-op? if
            tok-next true
        else
            is-map if
                fl-p-map-entry? 0= if
                    cr ." flua: mixed table literal" cr fl-p-error
                then
                tok-t TK-ID = 0= if fl-p-error then
                tok-p tok-l { kpa kpu }
                tok-next
                [char] = tok-op? 0= if fl-p-error then
                tok-next
                kpa kpu fl-p-expr an-field fields addrlist-add
            else
                fl-p-map-entry? if
                    cr ." flua: mixed table literal" cr fl-p-error
                then
                fl-p-expr fields addrlist-add
            then
            [char] , tok-op? if
                tok-next
                tok-skip-cm
                [char] } tok-op? if tok-next true else false then
            else
                [char] } tok-op? 0= if fl-p-error then
                tok-next true
            then
        then
    until
    fields addrlist-reverse
    is-map if TABLE-MAP else TABLE-LIST then
    fields an-table ;

: fl-p-primary ( -- m )
    tok-skip-cm
    tok-t TK-NUM = if tok-p tok-l an-num tok-next fl-p-postfix exit then
    tok-t TK-STR = if tok-p tok-l an-str tok-next fl-p-postfix exit then
    tok-t TK-ID  = if fl-p-name fl-p-postfix exit then
    [char] { tok-op? if fl-p-table fl-p-postfix exit then
    [char] ( tok-op? if                 \ группировка ( expr ): прозрачна
        tok-next fl-p-expr
        [char] ) tok-op? 0= if fl-p-error then
        tok-next fl-p-postfix exit
    then
    fl-p-error ;

: fl-p-unary-1 ( -- m )
    [char] - tok-op? if
        [char] - tok-next fl-p-unary an-un
    else
        s" not" tok-kw? if
            OP-NOT tok-next fl-p-unary an-un
        else
            fl-p-primary
        then
    then ;

' fl-p-unary-1 is fl-p-unary

\ уровень * / %: ( op l r ) собирается через r-stack — общего состояния
\ нет, вложенные вызовы (аргументы) не затирают оператор
: fl-p-term ( -- m )
    fl-p-unary
    begin
        tok-opc dup [char] * = over [char] / = or over [char] % = or if
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

\ текущий значимый токен — оператор сравнения? → опкод, 0 — не сравнение
\ (двухсимвольные <= >= == ~= распознаёт токенизатор как один TK-OP)
: fl-p-relop ( -- op )
    tok-skip-cm
    tok-t TK-OP = 0= if 0 exit then
    tok-text
    2dup s" <=" compare 0= if 2drop OP-LE exit then
    2dup s" >=" compare 0= if 2drop OP-GE exit then
    2dup s" ==" compare 0= if 2drop OP-EQ exit then
    2dup s" ~=" compare 0= if 2drop OP-NE exit then
    2dup s" <"  compare 0= if 2drop [char] < exit then
    2dup s" >"  compare 0= if 2drop [char] > exit then
    2drop 0 ;

\ уровень сравнений — левоассоциативный, как concat
: fl-p-relational ( -- m )
    fl-p-concat
    begin
        fl-p-relop                       \ ( m op ), op = 0 — не сравнение
        dup 0= if
            drop true                    \ сравнений больше нет → выход
        else
            tok-next fl-p-concat         \ ( m op r )
            >r swap r>                   \ ( op m r )
            an-bin
            false
        then
    until ;

\ уровень «and» (ближе к выражению, чем «or»): ключевое слово, не символ
: fl-p-and ( -- m )
    fl-p-relational
    begin
        s" and" tok-kw? if
            OP-AND tok-next fl-p-relational
            >r swap r> an-bin
            false
        else
            true
        then
    until ;

\ уровень «or» — верхний: левоассоциативно, как все уровни ниже
: fl-p-or ( -- m )
    fl-p-and
    begin
        s" or" tok-kw? if
            OP-OR tok-next fl-p-and
            >r swap r> an-bin
            false
        else
            true
        then
    until ;

' fl-p-or is fl-p-expr

\ ---------------- операторы ----------------

defer fl-p-stmt                          \ один stmt
defer fl-p-if
defer fl-p-while
defer fl-p-repeat
defer fl-p-for

\ return [expr (, expr)*]
: fl-p-return ( -- m )
    tok-next                             \ съесть return
    addrlist-new { exprs }
    \ пустой return: следующий токен — конец stmt (end/elseif/else/function/…)
    s" end" tok-kw? s" elseif" tok-kw? or s" else" tok-kw? or
    s" until" tok-kw? or s" function" tok-kw? or tok-t TK-EOF = or if
        exprs an-ret exit
    then
    fl-p-expr exprs addrlist-add
    begin
        [char] , tok-op? if
            tok-next fl-p-expr exprs addrlist-add false
        else true then
    until
    exprs addrlist-reverse exprs an-ret ;

\ ID (, ID)* — список имён (для local / multi-assign)
: fl-p-name-list ( -- names )
    addrlist-new { names }
    begin
        tok-skip-cm
        tok-t TK-ID = 0= if fl-p-error then
        tok-p tok-l an-id names addrlist-add
        tok-next
        [char] , tok-op? if tok-next false else true then
    until
    names addrlist-reverse names ;

\ local name [, name]* = expr
: fl-p-local ( -- m )
    tok-next                             \ local
    fl-p-name-list
    [char] = tok-op? 0= if fl-p-error then
    tok-next
    fl-p-expr
    an-local ;

\ name [, name]* = expr (курсор на первом ID)
: fl-p-assign ( -- m )
    fl-p-name-list
    [char] = tok-op? 0= if fl-p-error then
    tok-next
    fl-p-expr
    an-assign ;

\ ID (, ID)* '=' ? lookahead
: fl-p-id-assign? ( -- f )
    tok-skip-cm
    tok-t TK-ID = 0= if false exit then
    tok-i @ >r
    begin
        tok-next
        [char] , tok-op? if tok-next false else true then
    until
    [char] = tok-op?
    r> tok-i ! ;

\ пропустить [ … ] на уровне токенов (для lookahead assign)
: fl-p-skip-brackets ( -- f )
    1 { depth }
    begin
        tok-t TK-EOF = if false exit then
        [char] [ tok-op? if tok-next depth 1+ to depth false
        else [char] ] tok-op? if
            tok-next
            depth 1- dup to depth
            0= if true exit then
            false
        else tok-next false then then
    until ;

\ ID (.ID | […])+ '=' ? — индексный assign
: fl-p-index-assign? ( -- f )
    tok-skip-cm
    tok-t TK-ID = 0= if false exit then
    tok-i @ >r
    tok-next
    false { saw }
    begin
        [char] . tok-op? if
            tok-next
            tok-skip-cm
            tok-t TK-ID = 0= if r> tok-i ! false exit then
            tok-next true to saw false
        else [char] [ tok-op? if
            tok-next
            fl-p-skip-brackets 0= if r> tok-i ! false exit then
            true to saw false
        else true then then
    until
    saw [char] = tok-op? and
    r> tok-i ! ;

: fl-p-index-assign ( -- m )
    fl-p-name fl-p-postfix { idx }
    idx an-type an@ ANT-INDEX <> if fl-p-error then
    [char] = tok-op? 0= if fl-p-error then
    tok-next
    fl-p-expr
    idx swap an-idx-assign ;

\ ID '(' ? — вызов как statement (print и др.)
: fl-p-id-call? ( -- f )
    tok-skip-cm
    tok-t TK-ID = 0= if false exit then
    tok-i @ >r
    tok-next
    [char] ( tok-op?
    r> tok-i ! ;

: fl-p-stmt-1 ( -- m )
    s" function" tok-kw? if
        cr ." flua: nested functions not allowed" cr fl-p-error
    then
    s" return" tok-kw? if fl-p-return exit then
    s" local" tok-kw? if fl-p-local exit then
    s" if" tok-kw? if fl-p-if exit then
    s" while" tok-kw? if fl-p-while exit then
    s" repeat" tok-kw? if fl-p-repeat exit then
    s" for" tok-kw? if fl-p-for exit then
    fl-p-id-assign? if fl-p-assign exit then
    fl-p-index-assign? if fl-p-index-assign exit then
    fl-p-id-call? if fl-p-expr exit then
    fl-p-error ;

' fl-p-stmt-1 is fl-p-stmt

\ список stmt до тех пор, пока end-check ( -- f ) ложь; end-check не должен
\ сдвигать курсор на true (ключевое слово остаётся)
: fl-p-stmts-until ( xt -- stmts )
    { endxt }
    addrlist-new { stmts }
    begin
        endxt execute if
            stmts addrlist-reverse stmts exit
        then
        fl-p-stmt stmts addrlist-add
        false
    until ;

: fl-p-end-if-branch? ( -- f )
    s" elseif" tok-kw? s" else" tok-kw? or s" end" tok-kw? or ;

: fl-p-end-body? ( -- f ) s" end" tok-kw? ;
: fl-p-end-while? ( -- f ) s" end" tok-kw? ;
: fl-p-end-repeat? ( -- f ) s" until" tok-kw? ;

\ курсор на «if»
: fl-p-if-1 ( -- m )
    tok-next
    addrlist-new { branches }
    fl-p-expr
    s" then" tok-kw? 0= if fl-p-error then
    tok-next
    ['] fl-p-end-if-branch? fl-p-stmts-until
    an-br branches addrlist-add
    begin
        s" elseif" tok-kw? if
            tok-next fl-p-expr
            s" then" tok-kw? 0= if fl-p-error then
            tok-next
            ['] fl-p-end-if-branch? fl-p-stmts-until
            an-br branches addrlist-add
            false
        else
            s" else" tok-kw? if
                tok-next
                ['] fl-p-end-if-branch? fl-p-stmts-until
                0 swap an-br branches addrlist-add
                s" end" tok-kw? 0= if fl-p-error then
                tok-next
                true
            else
                s" end" tok-kw? 0= if fl-p-error then
                tok-next
                true
            then
        then
    until
    branches addrlist-reverse branches an-if ;
' fl-p-if-1 is fl-p-if

: fl-p-while-1 ( -- m )
    tok-next
    fl-p-expr
    s" do" tok-kw? 0= if fl-p-error then
    tok-next
    ['] fl-p-end-while? fl-p-stmts-until
    s" end" tok-kw? 0= if fl-p-error then
    tok-next
    an-while ;
' fl-p-while-1 is fl-p-while

: fl-p-repeat-1 ( -- m )
    tok-next
    ['] fl-p-end-repeat? fl-p-stmts-until
    s" until" tok-kw? 0= if fl-p-error then
    tok-next
    fl-p-expr
    an-repeat ;
' fl-p-repeat-1 is fl-p-repeat

\ for i = lo, hi do stmts end  → ANT-FOR (numeric only; step=1)
: fl-p-end-for? ( -- f ) s" end" tok-kw? ;
: fl-p-for-1 ( -- m )
    tok-next                             \ for
    tok-skip-cm
    tok-t TK-ID = 0= if fl-p-error then
    tok-p tok-l { pa pu }
    tok-next
    [char] = tok-op? 0= if fl-p-error then
    tok-next
    fl-p-expr { lo }
    [char] , tok-op? 0= if fl-p-error then
    tok-next
    fl-p-expr { hi }
    s" do" tok-kw? 0= if fl-p-error then
    tok-next
    ['] fl-p-end-for? fl-p-stmts-until { body }
    s" end" tok-kw? 0= if fl-p-error then
    tok-next
    pa pu lo hi body an-for ;
' fl-p-for-1 is fl-p-for

: fl-p-body ( -- stmts )
    ['] fl-p-end-body? fl-p-stmts-until ;

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
    addrlist-new fl-p-params !
    [char] ) tok-op? if
        tok-next                         \ () — параметров нет
    else
        begin
            tok-skip-cm
            tok-t TK-ID = 0= if fl-p-error then
            tok-p tok-l an-id fl-p-params @ addrlist-add
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
    fl-p-params @ addrlist-reverse          \ addrlist-add в голову → порядок чтения
    fl-p-body                            \ ( body ): return-expr или if
    s" end" tok-kw? 0= if fl-p-error then
    tok-next
    >r                                   \ r: body
    fl-p-na @ fl-p-nu @ fl-p-params @ r>
    an-fn                               \ ( fn )
    fl-hdr-i1 @ over an-r an!            \ граница серии CM (токен после неё)
    fl-hdr-i0 @ over an-op an!           \ первый токен серии
    dup fl-fn-scan-pragmas
    ;

\ ---------------- файл ----------------

\ top-level item: function | local | assign | index-assign | expr
\ (local на top-level → тот же узел ANT-LOCAL; codegen: VALUE, как assign)
: fl-p-toplevel ( -- m )
    s" function" tok-kw? if fl-p-function exit then
    s" local" tok-kw? if fl-p-local exit then
    fl-p-id-assign? if fl-p-assign exit then
    fl-p-index-assign? if fl-p-index-assign exit then
    fl-p-expr ;

: fl-p-program ( -- )
    an-reset
    fl-tokenize
    begin
        fl-p-hdr-cm
        tok-t TK-EOF = if
            an-root @ addrlist-reverse exit
        then
        fl-p-toplevel an-root @ addrlist-add
        false
    until ;

\ ================= печать AST в emit-buf =================

variable an-d                            \ текущий уровень отступа
defer an-print                           \ рекурсия; тело — an-print-1 ниже

\ текст узла — цитата из исходника
: an-text ( m -- a u )
    { m } src-a @ m an-pa an@ + m an-pu an@ ;

: an-indent ( -- ) an-d @ 0 ?do emit-bl emit-bl loop ;

\ параметры (id-узлы): «a, b»
: an-params ( lst -- )
    { lst }
    lst addrlist-len 0 ?do
        i 0> if s" , " emit-st then
        i lst addrlist-nth-addr an-text emit-st
    loop ;

: an-op-emit ( op -- )
    dup OP-CONCAT = if drop s" .." emit-st exit then
    dup OP-LE    = if drop s" <=" emit-st exit then
    dup OP-GE    = if drop s" >=" emit-st exit then
    dup OP-EQ    = if drop s" ="  emit-st exit then
    dup OP-NE    = if drop s" <>" emit-st exit then
    dup OP-AND   = if drop s" and" emit-st exit then
    dup OP-OR    = if drop s" or"  emit-st exit then
    emit-ch ;

\ одна ветка if (br, bi): bi = 0 — первая (после «if»), иначе elseif/else
: an-branch-print ( br bi -- )
    { br bi }
    bi 0= if
        1 an-d +!
        br an-l an@ an-print              \ условие
        -1 an-d +!
        an-indent s" then" emit-st emit-nl
    else
        br an-l an@ if                    \ elseif — условие ≠ 0
            an-indent s" elseif" emit-st emit-nl
            1 an-d +!
            br an-l an@ an-print
            -1 an-d +!
            an-indent s" then" emit-st emit-nl
        else                              \ else — условия нет
            an-indent s" else" emit-st emit-nl
        then
    then
    1 an-d +!
    br an-aux an@ addrlist-len 0 ?do
        i br an-aux an@ addrlist-nth-addr an-print
    loop
    -1 an-d +! ;

\ весь if: «if», ветки, «end» (отступ строки узла уже напечатал an-print-1)
: an-if-print ( m -- )
    { m }
    s" if" emit-st emit-nl
    m an-aux an@ { lst }
    lst addrlist-len 0 ?do
        i lst addrlist-nth-addr i an-branch-print
    loop ;

\ узел → emit-buf: строка узла, затем дочерние на уровень глубже
: an-print-1 ( m -- )
    { m }
    an-indent
    m an-type an@ case
        ANT-NUM of s" num " emit-st m an-text emit-st emit-nl endof
        ANT-STR of s" str " emit-st m an-text emit-st emit-nl endof
        ANT-ID  of s" id "  emit-st m an-text emit-st emit-nl endof
        ANT-BIN of
            s" bin " emit-st m an-op an@ an-op-emit emit-nl
            1 an-d +!
            m an-l an@ an-print
            m an-r an@ an-print
            -1 an-d +!
        endof
        ANT-UN of
            s" un " emit-st
            m an-op an@ [char] - = if s" -" else s" not" then emit-st
            emit-nl
            1 an-d +!
            m an-l an@ an-print
            -1 an-d +!
        endof
        ANT-CALL of
            s" call " emit-st m an-text emit-st emit-nl
            1 an-d +!
            m an-aux an@ addrlist-len 0 ?do
                i m an-aux an@ addrlist-nth-addr an-print
            loop
            -1 an-d +!
        endof
        ANT-FN of
            s" fn " emit-st m an-text emit-st
            [char] ( emit-ch
            m an-aux an@ an-params
            [char] ) emit-ch emit-nl
            1 an-d +!
            m an-l an@ addrlist-len 0 ?do   \ тело: ulist stmt'ов
                i m an-l an@ addrlist-nth-addr an-print
            loop
            -1 an-d +!
        endof
        ANT-IF of
            m an-if-print
            an-indent s" end" emit-st emit-nl
        endof
        ANT-RET of
            m an-aux an@ addrlist-len 1 = if
                \ одна expr — печатаем её на месте (откат ложного отступа строки ret)
                an-d @ 2* negate emit-pos +!
                0 m an-aux an@ addrlist-nth-addr an-print
            else
                s" ret" emit-st emit-nl
                1 an-d +!
                m an-aux an@ addrlist-len 0 ?do
                    i m an-aux an@ addrlist-nth-addr an-print
                loop
                -1 an-d +!
            then
        endof
        ANT-ASSIGN of
            m an-aux an@ 0= if
                s" idx-assign" emit-st emit-nl
                1 an-d +!
                m an-r an@ an-print
                m an-l an@ an-print
                -1 an-d +!
            else
                s" assign " emit-st m an-text emit-st emit-nl
                1 an-d +! m an-l an@ an-print -1 an-d +!
            then
        endof
        ANT-LOCAL of
            s" local " emit-st m an-text emit-st emit-nl
            1 an-d +! m an-l an@ an-print -1 an-d +!
        endof
        ANT-WHILE of
            s" while" emit-st emit-nl
            1 an-d +!
            m an-l an@ an-print
            m an-aux an@ addrlist-len 0 ?do
                i m an-aux an@ addrlist-nth-addr an-print
            loop
            -1 an-d +!
        endof
        ANT-REPEAT of
            s" repeat" emit-st emit-nl
            1 an-d +!
            m an-aux an@ addrlist-len 0 ?do
                i m an-aux an@ addrlist-nth-addr an-print
            loop
            m an-l an@ an-print
            -1 an-d +!
        endof
        ANT-FOR of
            s" for " emit-st m an-text emit-st emit-nl
            1 an-d +!
            m an-l an@ an-print
            m an-r an@ an-print
            m an-aux an@ addrlist-len 0 ?do
                i m an-aux an@ addrlist-nth-addr an-print
            loop
            -1 an-d +!
        endof
        ANT-TABLE of
            s" table " emit-st
            m an-op an@ TABLE-MAP = if s" map" else s" list" then emit-st
            emit-nl
            1 an-d +!
            m an-aux an@ addrlist-len 0 ?do
                i m an-aux an@ addrlist-nth-addr an-print
            loop
            -1 an-d +!
        endof
        ANT-INDEX of
            s" index" emit-st emit-nl
            1 an-d +!
            m an-l an@ an-print
            m an-r an@ an-print
            -1 an-d +!
        endof
        ANT-FIELD of
            s" field " emit-st m an-text emit-st emit-nl
            1 an-d +!
            m an-l an@ an-print
            -1 an-d +!
        endof
        true abort" flua: internal AST error: bad node type"
    endcase ;

: an-print-set ( -- ) ['] an-print-1 is an-print ; an-print-set

\ ================= разбор и вывод файла =================

\ ( a u -- ) разобрать исходник, построить AST и напечатать его в emit-buf
: fl-ast-run ( a u -- )
    src-set emit-reset
    fl-p-program
    0 an-d !
    ['] an-print an-root @ addrlist-each ;

[THEN]
