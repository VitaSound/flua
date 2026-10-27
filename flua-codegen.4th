\ flua-codegen.4th — кодогенерация из AST (конвейер: токены → дерево → код).
\
\ Один парсер (flua-tokens → flua-ast) строит дерево; отсюда же бесплатно
\ получается вывод --ast (fl-ast-run). Это слово — второй потребитель того
\ же дерева: обход эмитит Forth-код. Режим выбирается stack-mode? как
\ раньше: locals — шапка { a b } и постфиксная эмиссия имён; --stack —
\ стековая модель m-*/fl-arrange (выбор dup/over/pick/roll).
\
\ Подсчёт использований параметров (--stack) — обход дерева (fl-count-tree).
\ Шапки-комментарии: fl-hdr-cm-fill наполняет cm-buf серией TK-CM-токенов
\ перед function; cm-flush эмитит её перед шапкой функции.
\
\ Подключается из flua.4th после flua-ast.4th: нужны emit-*, src-*, cm-*,
\ m-*, fl-arrange, fl-stack-leaf, param-*, fl-params-ul, fl-emit-names,
\ fl-fname-*, переменные кодогена fl-karg/fl-cbase/fl-cn/fl-nna/fl-nnu/fl-if-n.

require ./flua-ast.4th

[IFDEF] fl-gen-fn [ELSE]

\ ---- оператор → постфиксная строка ("+ ", "s+ ", "<= " ...) ----
\ одиночные ASCII-операторы — символ + пробел (кроме % → mod);
\ сравнения — готовые слова
: fl-op-emit ( op -- )
    dup OP-CONCAT = if drop s" s+ " emit-st exit then
    dup OP-EQ    = if drop s" = "  emit-st exit then
    dup OP-NE    = if drop s" <> " emit-st exit then
    dup OP-LE    = if drop s" <= " emit-st exit then
    dup OP-GE    = if drop s" >= " emit-st exit then
    dup [char] % = if drop s" mod " emit-st exit then
    emit-ch emit-bl ;

\ ---- выражение: узел → постфиксный эмит ----
defer fl-eval                          \ рекурсивное слово; тело — fl-eval-1

\ число: 0x... → $hex, десятичное — как есть
: fl-eval-num ( m -- )
    { m }
    m an-text { a u }
    u 1 > a c@ [char] 0 = and
    a 1+ c@ [char] x = a 1+ c@ [char] X = or and if
        [char] $ emit-ch
        a 2 + u 2 -                       \ hex-часть — на стеке для bounds
        bounds ?do i c@ emit-ch loop
        emit-bl
    else
        a u emit-st emit-bl
    then
    1 m-push-res ;

\ строка: Lua-текст → forth s\" с escape
: fl-eval-str ( m -- )
    { m }
    [char] s emit-ch [char] \ emit-ch [char] " emit-ch emit-bl
    m an-text { a u }
    u 2 >= a c@ [char] " = a c@ [char] ' = or and if
        a 1 + to a  u 2 - to u         \ снять краевые кавычки (" или ')
    then
    begin u 0 > while
        a c@ [char] \ = u 1 > and if      \ «\X» → «\X» (n/t/\/" — как есть)
            [char] \ emit-ch a 1+ c@ emit-ch
            a 2 + to a  u 2 - to u
        else
            a c@ [char] " = if            \ " внутри '...' → \"
                [char] \ emit-ch [char] " emit-ch
            else
                a c@ emit-ch
            then
            a 1 + to a  u 1 - to u
        then
    repeat
    [char] " emit-ch emit-bl
    2 m-push-res ;

\ цикл for: имя переменной → эмит Forth «i»
variable fl-for-va
variable fl-for-vu
0 fl-for-va ! 0 fl-for-vu !

\ идентификатор: параметр — подъём/копия (stack) либо просто имя (locals);
\ не-параметр в --stack — ошибка (проверка — в fl-stack-leaf)
: fl-eval-id ( m -- )
    { m }
    fl-for-vu @ if
        m an-text fl-for-va @ fl-for-vu @ compare 0= if
            s" i " emit-st exit
        then
    then
    stack-mode? @ if
        m an-text fl-stack-leaf
    else
        m an-text emit-st emit-bl
    then ;

\ and/or со шорт-кircuit: правый операнд эмитится только внутри ветки —
\ он не должен выполняться, когда левый решает исход (Lua-семантика).
\ Формы: and (locals) — «A dup if drop B then»; and (--stack) —
\ «A dup if drop B else nip then»: в skip-пути (a=0) под a лежит слот
\ правого операнда — nip убирает его, и обе ветки стыкуются одной
\ ячейкой (иначе лишняя подложка на then-стыке); or — одна форма для
\ обоих режимов: «A dup if else drop B then».
\ Модель (--stack): A выравнивается наверх, «dup if drop» съедает его
\ значение → m-pop (как «if» в fl-gen-if); B строится на пустом верхе
\ в then-ветке; после «then» модель = результат B (без лишних push)
: fl-eval-bool ( m -- )
    { m }
    m an-l an@ fl-eval
    stack-mode? @ if
        fl-vs @ m-find fl-vsz @ 0 fl-o!
        1 fl-on !
        fl-arrange
    then
    m an-op an@ OP-AND = if
        s" dup if drop " emit-st
        stack-mode? @ if m-pop then
        m an-r an@ fl-eval
        stack-mode? @ if s" else nip " emit-st then
        s" then " emit-st
    else
        s" dup if else drop " emit-st
        stack-mode? @ if m-pop then
        m an-r an@ fl-eval
        s" then " emit-st
    then ;

\ тип выражения: 0 неизвестен (параметр/вызов), 1 целое, 2 строка
: fl-expr-ncells ( m -- n )
    dup an-type an@ ANT-STR = if drop 2 exit then
    dup an-type an@ ANT-NUM = if drop 1 exit then
    dup an-type an@ ANT-TABLE = if drop 1 exit then
    dup an-type an@ ANT-BIN = if
        an-op an@ OP-CONCAT = if 2 else 1 then exit
    then
    dup an-type an@ ANT-UN = if drop 1 exit then
    dup an-type an@ ANT-ID = if
        an-text fl-glob-find-rec dup if 2 cells + @ else drop 0 then exit
    then
    drop 0 ;

\ a u → s\" …" (идентификаторы / голый текст без кавычек в src)
: fl-emit-bare-str ( a u -- )
    [char] s emit-ch [char] \ emit-ch [char] " emit-ch emit-bl
    bounds ?do
        i c@ dup [char] " = over [char] \ = or if
            [char] \ emit-ch
        then emit-ch
    loop
    [char] " emit-ch emit-bl ;

\ значение → терм TM-* + клетки на стеке (для set/add)
: fl-emit-term-val ( m -- )
    { m }
    m an-type an@ ANT-TABLE = if
        m an-op an@ TABLE-MAP = if s" TM-MAP " else s" TM-LST " then emit-st
        m fl-eval
        s" 0 " emit-st
        exit
    then
    m fl-expr-ncells
    dup 2 = if drop s" TM-STR " emit-st m fl-eval exit then
    dup 1 = if drop s" TM-INT " emit-st m fl-eval s" 0 " emit-st exit then
    drop
    cr ." flua: table value type unknown" cr -1 throw ;

: fl-eval-table ( m -- )
    { m }
    m an-op an@ TABLE-MAP = if
        s" hashmap-new >r " emit-st
        m an-aux an@ { fs }
        fs addrlist-len 0 ?do
            emit-nl emit-ind
            i fs addrlist-nth-addr { f }
            s" TM-STR " emit-st
            f an-text fl-emit-bare-str
            f an-l an@ fl-emit-term-val
            s" r@ hashmap-set " emit-st
        loop
        emit-nl emit-ind s" r> " emit-st
    else
        s" ulist-new >r " emit-st
        m an-aux an@ { fs }
        fs addrlist-len 0 ?do
            emit-nl emit-ind
            fs addrlist-len 1- i - fs addrlist-nth-addr fl-emit-term-val
            s" r@ ulist-add " emit-st
        loop
        emit-nl emit-ind s" r> " emit-st
    then
    1 m-push-res ;

\ t[k] / t.a → hashmap-get (4) или ulist-nth-term (3)
\ k — выражение: str (2 cells) → map, int (1) → list.
\ m[a] ≠ m["a"]: нужен типизированный a (VALUE/local), иначе ошибка.
: fl-eval-index ( m -- )
    { m }
    m an-r an@ { key }
    m an-l an@ { cont }
    key fl-expr-ncells { kn }
    kn 2 = if
        s" TM-STR " emit-st
        key fl-eval
        cont fl-eval
        s" hashmap-get " emit-st
        3 m-popn
        4 0 ?do 1 m-push-res loop
    else
        kn 1 = if
            key fl-eval
            cont fl-eval
            s" ulist-nth-term " emit-st
            2 m-popn
            3 0 ?do 1 m-push-res loop
        else
            cr ." flua: index key needs typed value (m.a / string literal / int var)" cr
            -1 throw
        then
    then ;

: fl-gen-idx-assign ( m -- )
    { m }
    stack-mode? @ if
        cr ." flua: locals/assign not supported in -- @stack function" cr
        -1 throw
    then
    m an-r an@ { idx }
    m an-l an@ { val }
    idx an-r an@ { key }
    idx an-l an@ { cont }
    emit-ind
    key fl-expr-ncells { kn }
    kn 2 = if
        s" TM-STR " emit-st
        key fl-eval
        val fl-emit-term-val
        cont fl-eval
        s" hashmap-set " emit-st
        val fl-expr-ncells 2 + 1 + m-popn
    else
        kn 1 = if
            key fl-eval
            val fl-emit-term-val
            cont fl-eval
            s" ulist-set-term " emit-st
            val fl-expr-ncells 1 + 1 + m-popn
        else
            cr ." flua: index key needs typed value (m.a / string literal / int var)" cr
            -1 throw
        then
    then
    emit-nl ;

: fl-arg-is-str? ( m -- f ) fl-expr-ncells 2 = ;

\ .. — нельзя с известным целым; арифметика/сравнения — нельзя с известной строкой
: fl-bin-check-types ( m -- )
    { m }
    m an-op an@ OP-CONCAT = if
        m an-l an@ fl-expr-ncells 1 =
        m an-r an@ fl-expr-ncells 1 = or if
            cr ." flua: .. expects strings" cr -1 throw
        then exit
    then
    m an-l an@ fl-expr-ncells 2 =
    m an-r an@ fl-expr-ncells 2 = or if
        cr ." flua: type mismatch in expression" cr -1 throw
    then ;

: fl-eval-bin ( m -- )
    { m }
    m fl-bin-check-types
    m an-op an@ dup OP-AND = over OP-OR = or if
        drop m fl-eval-bool exit              \ шорт-кircuit — своя эмиссия
    then
    drop                                      \ не and/or: op больше не нужен
    m an-l an@ fl-eval
    stack-mode? @ if fl-vs @ fl-vsz @ 2>r then
    m an-r an@ fl-eval
    stack-mode? @ if
        fl-vs @ m-find fl-vsz @ 1 fl-o! \ правый операнд → №1
        2r> swap m-find swap 0 fl-o!      \ левый (тэг из R) → №0
        2 fl-on !
        fl-arrange
    then
    m an-op an@ fl-op-emit
    \ «..»: результат — строка (2 ячейки), съедает 4 (2+2)
    m an-op an@ OP-CONCAT = if
        4 m-popn 2 m-push-res
    else
        2 m-popn 1 m-push-res
    then ;

: fl-eval-un ( m -- )
    { m }
    m an-l an@ fl-expr-ncells 2 = if
        cr ." flua: type mismatch in expression" cr -1 throw
    then
    m an-l an@ fl-eval
    stack-mode? @ if
        fl-vs @ m-find fl-vsz @ 0 fl-o!
        1 fl-on !
        fl-arrange
    then
    m an-op an@ [char] - = if s" negate " else s" 0= " then emit-st
    m-pop 1 m-push-res ;

\ builtin print(...): аргументы слева направо, «. »/«type », space, cr; 0 results
: fl-eval-print ( m -- )
    { m }
    m an-aux an@ { args }
    args addrlist-len 0 ?do
        i args addrlist-nth-addr { arg }
        arg fl-eval
        stack-mode? @ if
            fl-vs @ m-find fl-vsz @ 0 fl-o!
            1 fl-on ! fl-arrange
        then
        stack-mode? @ if fl-vsz @ 2 = else arg fl-arg-is-str? then if
            s" type " emit-st
        else
            s" 0 .r " emit-st            \ без хвостового пробела (в отличие от .)
        then
        stack-mode? @ if fl-vsz @ m-popn else 1 m-popn then
        i 1+ args addrlist-len < if s" space " emit-st then
    loop
    s" cr " emit-st ;

\ builtin abort("msg") → true abort" msg"
: fl-eval-abort ( m -- )
    { m }
    m an-aux an@ { args }
    args addrlist-len 1 <> if
        cr ." flua: abort expects one string argument" cr -1 throw
    then
    0 args addrlist-nth-addr { arg }
    arg an-type an@ ANT-STR <> if
        cr ." flua: abort expects a string literal" cr -1 throw
    then
    s" true abort" emit-st [char] " emit-ch emit-bl
    arg an-text { a u }
    u 2 >= if a 1+ to a u 2 - to u then
    a u emit-st
    [char] " emit-ch emit-bl ;

\ bare lua_name → forth-имя: '_' → '-' (точки/«?» только через -- @forth)
create fl-emit-name-buf 128 allot
: fl-lua-to-forth-name ( a u -- a u )
    dup 128 > if cr ." flua: name too long" cr -1 throw then
    tuck fl-emit-name-buf swap move
    fl-emit-name-buf swap
    2dup bounds ?do
        i c@ [char] _ = if [char] - i c! then
    loop ;

\ outs вызова: @forth | fl-expect-outs | 1
: fl-call-resolve-out ( m -- n )
    { m }
    m an-text fl-forth-find ?dup if fi-out@ exit then
    fl-expect-outs @ dup 0< 0= if exit then
    drop 1 ;

\ ncells аргумента для @forth: 0 (неизвестно) → 1
: fl-expr-incells ( m -- n )
    fl-expr-ncells ?dup 0= if 1 then ;

: fl-args-incells ( args -- n )
    { args }
    0
    args addrlist-len 0 ?do
        i args addrlist-nth-addr fl-expr-incells +
    loop ;

: fl-call-check-in ( m fi -- )
    { m fi }
    m an-aux an@ fl-args-incells fi fi-in@ <> if
        cr ." flua: @forth arity mismatch for " m an-text type
        ." : expected " fi fi-in@ . ." cells" cr -1 throw
    then ;

\ вызов: аргументы → имя; outs из @forth / expect / 1
: fl-eval-call ( m -- )
    { m }
    m an-text s" print" compare 0= if m fl-eval-print exit then
    m an-text s" abort" compare 0= if m fl-eval-abort exit then
    m an-text fl-forth-find { fi }
    fi if m fi fl-call-check-in then
    m fl-call-resolve-out { outs }
    fi if
        fl-expect-outs @ dup 0< 0= if
            outs <> if
                cr ." flua: @forth out-arity mismatch for " m an-text type cr
                -1 throw
            then
        else drop then
    then
    0 fl-karg !
    fl-cdepth @ 8 * fl-cbase ! 1 fl-cdepth +!
    m an-aux an@ { args }
    args fl-args-incells { incells }
    args addrlist-len 0 ?do
        i args addrlist-nth-addr fl-eval
        stack-mode? @ if
            fl-vs @ fl-vsz @ fl-cbase @ fl-karg @ + fl-as!
        then
        1 fl-karg +!
    loop
    stack-mode? @ if
        fl-karg @ 0 ?do
            fl-cbase @ i + fl-as@ swap m-find swap i fl-o!
        loop
        fl-karg @ fl-on !
        fl-arrange
    then
    -1 fl-cdepth +!
    fi if
        fi fi-forth emit-st emit-bl
    else
        m an-text fl-lua-to-forth-name emit-st emit-bl
    then
    incells m-popn
    outs 0 ?do 1 m-push-res loop ;

: fl-eval-1 ( m -- )
    { m }
    m an-type an@ case
        ANT-NUM   of m fl-eval-num   endof
        ANT-STR   of m fl-eval-str   endof
        ANT-ID    of m fl-eval-id    endof
        ANT-BIN   of m fl-eval-bin   endof
        ANT-UN    of m fl-eval-un    endof
        ANT-CALL  of m fl-eval-call  endof
        ANT-TABLE of m fl-eval-table endof
        ANT-INDEX of m fl-eval-index endof
        true abort" flua: internal codegen error: not an expression"
    endcase ;

: fl-eval-set ( -- ) ['] fl-eval-1 is fl-eval ; fl-eval-set

\ ---- return (ANT-RET) ----
\ early? true → exit после значений
: fl-gen-ret ( m early? -- )
    { m early? }
    m an-aux an@ { exprs }
    exprs addrlist-len 0= if                 \ пустой return
        proc-mode? @ 0= if
            cr ." flua: empty return only allowed in -- @proc" cr -1 throw
        then
        early? if emit-ind s" exit " emit-st emit-nl then exit
    then
    emit-ind
    exprs addrlist-len 0 ?do
        i exprs addrlist-nth-addr fl-eval
        stack-mode? @ if
            fl-vs @ m-find fl-vsz @ i fl-o!
        then
    loop
    stack-mode? @ if
        exprs addrlist-len fl-on !
        fl-arrange
        early? if
            m-len @ exprs addrlist-len - 0 max 0 ?do s" nip " emit-st loop
        then
    then
    early? if s" exit " emit-st then
    emit-nl ;

\ ---- assign / local → expr to name[s] (стек: last name на TOS) ----
: fl-assign-index-check ( m n -- )        \ single ← index-get запрещён
    { m n }
    n 1 = m an-l an@ an-type an@ ANT-INDEX = and if
        cr ." flua: index get needs multi-assign" cr -1 throw
    then ;

: fl-gen-to ( m -- )                      \ ANT-ASSIGN или ANT-LOCAL
    { m }
    m an-type an@ ANT-ASSIGN = m an-aux an@ 0= and if
        m fl-gen-idx-assign exit
    then
    stack-mode? @ if
        cr ." flua: locals/assign not supported in -- @stack function" cr
        -1 throw
    then
    m an-aux an@ { ns }
    ns addrlist-len { n }
    m n fl-assign-index-check
    fl-expect-outs @ >r
    n fl-expect-outs !
    emit-ind
    m an-l an@ fl-eval
    r> fl-expect-outs !
    \ to в обратном порядке: TOS → последнее имя
    n 0 ?do
        n 1- i - ns addrlist-nth-addr an-text
        s" to " emit-st emit-st emit-bl
    loop
    emit-nl
    stack-mode? @ 0= if n m-popn then ;

\ ---- if (ветки = ulist stmt в an-aux) ----
defer fl-gen-stmt

: fl-gen-stmts ( lst -- )
    { lst }
    lst addrlist-len 0 ?do
        i lst addrlist-nth-addr fl-gen-stmt
    loop ;

: fl-gen-branch ( br bi -- )
    { br bi }
    bi 0> if
        br an-l an@ if                    \ elseif → else … if
            stack-mode? @ if m-pop then
            1 fl-if-n +!
            fl-indent-
            emit-ind s" else " emit-st emit-nl
            fl-indent+
            emit-ind
            br an-l an@ fl-eval
            stack-mode? @ if
                fl-vs @ m-find fl-vsz @ 0 fl-o!
                1 fl-on ! fl-arrange m-pop
            then
            s" if " emit-st emit-nl
            fl-indent+
        else                              \ else
            stack-mode? @ if m-pop then
            fl-indent-
            emit-ind s" else " emit-st emit-nl
            fl-indent+
        then
    then
    br an-aux an@ fl-gen-stmts ;

: fl-gen-if ( m -- )
    { m }
    m an-aux an@ { branches }
    emit-ind
    0 branches addrlist-nth-addr an-l an@ fl-eval
    stack-mode? @ if
        fl-vs @ m-find fl-vsz @ 0 fl-o!
        1 fl-on ! fl-arrange
    then
    s" if " emit-st emit-nl
    stack-mode? @ if m-pop then
    fl-indent+
    1 fl-if-n !
    branches addrlist-len 0 ?do
        i branches addrlist-nth-addr i fl-gen-branch
    loop
    fl-if-n @ 0 ?do
        fl-indent-
        emit-ind s" then " emit-st emit-nl
    loop ;

: fl-gen-while ( m -- )
    { m }
    emit-ind s" begin " emit-st
    m an-l an@ fl-eval
    stack-mode? @ if
        fl-vs @ m-find fl-vsz @ 0 fl-o!
        1 fl-on ! fl-arrange m-pop
    then
    s" while " emit-st emit-nl
    fl-indent+
    m an-aux an@ fl-gen-stmts
    fl-indent-
    emit-ind s" repeat " emit-st emit-nl ;

: fl-gen-repeat ( m -- )
    { m }
    emit-ind s" begin " emit-st emit-nl
    fl-indent+
    m an-aux an@ fl-gen-stmts
    fl-indent-
    emit-ind
    m an-l an@ fl-eval
    stack-mode? @ if
        fl-vs @ m-find fl-vsz @ 0 fl-o!
        1 fl-on ! fl-arrange m-pop
    then
    s" until " emit-st emit-nl ;

\ for i=lo,hi → hi 1+ lo ?do … loop ; имя цикла → слово i
: fl-gen-for ( m -- )
    { m }
    stack-mode? @ if
        cr ." flua: for not supported in -- @stack" cr -1 throw
    then
    fl-for-va @ fl-for-vu @ 2>r
    m an-text fl-for-vu ! fl-for-va !
    emit-ind
    m an-r an@ fl-eval                   \ hi
    s" 1+ " emit-st
    m an-l an@ fl-eval                   \ lo
    s" ?do " emit-st emit-nl
    fl-indent+
    m an-aux an@ fl-gen-stmts
    fl-indent-
    emit-ind s" loop " emit-st emit-nl
    2r> fl-for-vu ! fl-for-va ! ;

: fl-gen-stmt-1 ( m -- )
    { m }
    m an-type an@ case
        ANT-IF     of m fl-gen-if endof
        ANT-WHILE  of m fl-gen-while endof
        ANT-REPEAT of m fl-gen-repeat endof
        ANT-FOR    of m fl-gen-for endof
        ANT-RET    of m true fl-gen-ret endof   \ early exit by default in stmt
        ANT-ASSIGN of m fl-gen-to endof
        ANT-LOCAL  of m fl-gen-to endof
        ANT-CALL   of
            fl-expect-outs @ >r
            0 fl-expect-outs !            \ call-stmt → 0 outs по умолчанию
            emit-ind m fl-eval emit-nl
            r> fl-expect-outs !
        endof
        \ legacy: bare expr as return (не должно встречаться после нового парсера)
        m false fl-gen-ret
    endcase ;
' fl-gen-stmt-1 is fl-gen-stmt

\ ---- подсчёт использований параметров: обход дерева (--stack) ----
\ fl-count-tree считает AN-ID-листы с именем fl-nna/fl-nnu (имя-вызова
\ живёт в AN-CALL, не в AN-ID). xt для addrlist-each параметров — fl-count-one-tree.
variable fl-gen-cur                     \ генерируемая функция (корень обхода)
defer fl-count-tree                     \ рекурсия: узел → счёт по fl-cn

: fl-count-tree-lst ( lst -- )          \ ulist узлов: каждый — fl-count-tree
    { lst }
    lst addrlist-len 0 ?do
        i lst addrlist-nth-addr fl-count-tree
    loop ;

: fl-count-tree-1 ( m -- )
    { m }
    m an-type an@ case
        ANT-ID of
            m an-text fl-nna @ fl-nnu @ compare 0= if
                1 fl-cn +!
            then
        endof
        ANT-BIN  of m an-l an@ fl-count-tree m an-r an@ fl-count-tree endof
        ANT-UN   of m an-l an@ fl-count-tree endof
        ANT-CALL of m an-aux an@ fl-count-tree-lst endof
        ANT-IF   of m an-aux an@ fl-count-tree-lst endof
        ANT-FOR  of
            m an-l an@ fl-count-tree m an-r an@ fl-count-tree
            m an-aux an@ fl-count-tree-lst
        endof
        ANT-BR   of
            m an-l an@ ?dup if fl-count-tree then
            m an-aux an@ fl-count-tree-lst
        endof
        ANT-RET of m an-aux an@ fl-count-tree-lst endof
        ANT-ASSIGN of
            m an-aux an@ 0= if
                m an-r an@ fl-count-tree
            then
            m an-l an@ fl-count-tree
        endof
        ANT-LOCAL  of m an-l an@ fl-count-tree endof
        ANT-WHILE  of m an-l an@ fl-count-tree m an-aux an@ fl-count-tree-lst endof
        ANT-REPEAT of m an-aux an@ fl-count-tree-lst m an-l an@ fl-count-tree endof
        ANT-TABLE of m an-aux an@ fl-count-tree-lst endof
        ANT-INDEX of m an-l an@ fl-count-tree m an-r an@ fl-count-tree endof
        ANT-FIELD of m an-l an@ fl-count-tree endof
        ANT-NUM of endof
        ANT-STR of endof
        ANT-FN  of m an-l an@ fl-count-tree-lst endof
    endcase ;

: fl-count-tree-set ( -- ) ['] fl-count-tree-1 is fl-count-tree ; fl-count-tree-set

\ xt для addrlist-each: сколько раз параметр — лист в дереве (0 → ошибка)
: fl-count-one-tree ( p -- )
    dup param-name fl-nnu ! fl-nna !
    0 fl-cn !
    fl-gen-cur @ fl-count-tree
    dup fl-cn @ swap                   \ ( p p n ) → swap → ( p n p )
    param-count!
    dup param-count@ 0= if
        cr ." flua: parameter '" param-name type
        ." ' is unused (stack mode)" cr
        -1 throw
    then drop ;

\ ---- функция: шапка, слово, тело, «;» ----

\ серия CM-токенов функции (an-op .. an-r) → cm-buf; курсор tok-i сохраняется
: fl-hdr-cm-fill ( fn -- )
    { fn }
    cm-reset
    tok-i @ >r
    fn an-op an@ tok-i !
    begin tok-i @ fn an-r an@ < while
        tok-t TK-CM = if tok-text cm-add then
        tok-next
    repeat
    r> tok-i ! ;

\ собрать ANT-LOCAL имена тела в ulist (тексты как an-id узлов — копируем an-text)
variable fl-locals-ul

defer fl-collect-locals-stmt
: fl-collect-locals-stmt-1 ( m -- )
    { m }
    m an-type an@ ANT-LOCAL = if
        m an-aux an@ { ns }
        ns addrlist-len 0 ?do
            i ns addrlist-nth-addr { id }
            id an-pa an@ id an-pu an@ an-id fl-locals-ul @ addrlist-add
        loop
        exit
    then
    m an-type an@ ANT-IF = if
        m an-aux an@ { brs }
        brs addrlist-len 0 ?do
            i brs addrlist-nth-addr an-aux an@ ?dup if
                { st }
                st addrlist-len 0 ?do
                    i st addrlist-nth-addr fl-collect-locals-stmt
                loop
            then
        loop
    then
    m an-type an@ ANT-WHILE = if
        m an-aux an@ { st }
        st addrlist-len 0 ?do i st addrlist-nth-addr fl-collect-locals-stmt loop
    then
    m an-type an@ ANT-REPEAT = if
        m an-aux an@ { st }
        st addrlist-len 0 ?do i st addrlist-nth-addr fl-collect-locals-stmt loop
    then
    m an-type an@ ANT-FOR = if
        m an-aux an@ { st }
        st addrlist-len 0 ?do i st addrlist-nth-addr fl-collect-locals-stmt loop
    then ;
' fl-collect-locals-stmt-1 is fl-collect-locals-stmt

: fl-emit-local-names ( -- )
    fl-locals-ul @ addrlist-len 0 ?do
        i fl-locals-ul @ addrlist-nth-addr an-text emit-st emit-bl
    loop ;

\ вывести «-- » / «-- r » / «-- r1 r2 »
: fl-emit-out-sig ( -- )
    fl-out-arity @ 0= if s" -- )" emit-st exit then
    fl-out-arity @ 1 = if s" -- r )" emit-st exit then
    s" -- " emit-st
    fl-out-arity @ 0 ?do
        s" r" emit-st i 1+ emit-uint emit-bl
    loop
    s" )" emit-st ;

\ сканировать stmt-список → обновить fl-out-arity (все return с одним N)
defer fl-scan-arity-stmt
: fl-scan-arity-ret ( m -- )
    { m }
    m an-aux an@ addrlist-len { n }
    fl-out-arity @ 0< if
        n fl-out-arity !
    else
        fl-out-arity @ n <> if
            cr ." flua: stack signature mismatch between returns" cr
            -1 throw
        then
    then
    proc-mode? @ if
        n 0<> if
            cr ." flua: -- @proc cannot return values" cr -1 throw
        then
    else
        n 0= if
            cr ." flua: empty return only allowed in -- @proc" cr -1 throw
        then
    then ;

: fl-scan-arity-stmt-1 ( m -- )
    { m }
    m an-type an@ ANT-RET = if m fl-scan-arity-ret exit then
    m an-type an@ ANT-IF = if
        m an-aux an@ { brs }
        brs addrlist-len 0 ?do
            i brs addrlist-nth-addr an-aux an@ { st }
            st addrlist-len 0 ?do i st addrlist-nth-addr fl-scan-arity-stmt loop
        loop
    then
    m an-type an@ ANT-WHILE = if
        m an-aux an@ { st }
        st addrlist-len 0 ?do i st addrlist-nth-addr fl-scan-arity-stmt loop
    then
    m an-type an@ ANT-REPEAT = if
        m an-aux an@ { st }
        st addrlist-len 0 ?do i st addrlist-nth-addr fl-scan-arity-stmt loop
    then
    m an-type an@ ANT-FOR = if
        m an-aux an@ { st }
        st addrlist-len 0 ?do i st addrlist-nth-addr fl-scan-arity-stmt loop
    then ;
' fl-scan-arity-stmt-1 is fl-scan-arity-stmt

: fl-gen-fn ( fn -- )
    { fn }
    stack-mode? @ proc-mode? @ 2>r
    fn an-flags an@ FN-STACK and 0<> stack-mode? !
    fn an-flags an@ FN-PROC  and 0<> proc-mode?  !
    proc-mode? @ if 0 else -1 then fl-out-arity !   \ -1 = ещё не видели return
    addrlist-new fl-params-ul !
    fn an-aux an@ { params }
    params addrlist-len 0 ?do
        i params addrlist-nth-addr an-text param-new
        fl-params-ul @ addrlist-add
    loop
    fl-params-ul @ addrlist-reverse
    fn an-text fl-fname-u ! fl-fname-a !
    \ locals из тела
    addrlist-new fl-locals-ul !
    fn an-l an@ { stmts0 }
    stmts0 addrlist-len 0 ?do
        i stmts0 addrlist-nth-addr fl-collect-locals-stmt
    loop
    fl-locals-ul @ addrlist-reverse
    \ out-arity из всех return
    stmts0 addrlist-len 0 ?do
        i stmts0 addrlist-nth-addr fl-scan-arity-stmt
    loop
    fl-out-arity @ 0< if                \ не было return
        proc-mode? @ if 0 else 1 then fl-out-arity !
    then
    m-reset
    fl-params-ul @ addrlist-len 0 ?do i m-append loop
    stack-mode? @ if
        fn fl-gen-cur !
        ['] fl-count-one-tree fl-params-ul @ addrlist-each
    then
    fn fl-hdr-cm-fill
    cm-flush
    s" \ ( " emit-st
    fl-emit-names
    fl-emit-out-sig emit-nl
    s" : " emit-st fl-fname-a @ fl-fname-u @ emit-st emit-bl
    stack-mode? @ 0= if
        fl-params-ul @ addrlist-len fl-locals-ul @ addrlist-len or if
            s" { " emit-st fl-emit-names
            fl-locals-ul @ addrlist-len if
                s" | " emit-st fl-emit-local-names
            then
            s" }" emit-st
        then
    then
    emit-nl
    fl-indent+                            \ тело функции
    fn an-l an@ { stmts }
    stmts addrlist-len 0 ?do
        i stmts addrlist-nth-addr { st }
        st an-type an@ ANT-RET = if
            \ последний return — без exit (; закроет слово); иначе early exit
            st  i stmts addrlist-len 1- <>  fl-gen-ret
        else
            st fl-gen-stmt
        then
    loop
    fl-indent-
    s" ;" emit-st emit-nl
    stack-mode? @ proc-mode? @ 0= and if
        m-len @ fl-out-arity @ < if
            cr ." flua: stack mode: empty result (final depth " m-len @ . ." )" cr
            -1 throw
        then
    then
    fl-params-ul @ addrlist-dispose
    fl-locals-ul @ addrlist-dispose
    2r> proc-mode? ! stack-mode? ! ;

\ kind глобала по RHS: TABLE → map/list, иначе scalar
: fl-rhs-glob-kind ( expr -- k )
    dup an-type an@ ANT-TABLE = if
        an-op an@ TABLE-MAP = if FG-MAP else FG-LIST then exit
    then
    drop FG-SCALAR ;

\ гарантировать 1-cell VALUE для имени (multi-assign / to)
: fl-glob-ensure-1 ( a u -- )
    2dup fl-glob-find if 2drop exit then
    2dup 1 FG-SCALAR fl-glob-add        \ add съедает копию; a u для emit
    s" 0 VALUE " emit-st emit-st emit-bl ;

\ top-level assign/local → VALUE/2VALUE / TO (в т.ч. multi)
: fl-gen-toplevel-assign ( m -- )
    { m }
    m an-aux an@ { ns }
    ns 0= if
        cr ." flua: internal: top-level assign without names" cr -1 throw
    then
    ns addrlist-len { n }
    m n fl-assign-index-check
    n 1 = if
        \ одно имя: int/str/table как раньше
        m an-l an@ fl-expr-ncells { nc }
        m an-l an@ fl-rhs-glob-kind { gk }
        m an-l an@ fl-eval
        0 ns addrlist-nth-addr an-text
        2dup fl-glob-find if
            \ nc=0 (вызов/неизвестно) → считаем 1 cell; 2VALUE не трогаем
            2dup fl-glob-cells { gc }
            nc if nc else 1 then
            gc <> if
                2drop
                cr ." flua: global type mismatch (int vs string)" cr -1 throw
            then
            fl-glob-find-rec 3 cells + gk swap !
            s" to " emit-st 0 ns addrlist-nth-addr an-text emit-st
        else
            \ новый глобал: неизвестный RHS → VALUE (1 cell)
            nc 0= if 1 to nc then
            nc gk fl-glob-add
            nc 2 = if s" 2VALUE " else s" VALUE " then emit-st
            0 ns addrlist-nth-addr an-text emit-st
        then
        emit-bl emit-nl exit
    then
    \ multi: все имена — 1-cell VALUE, затем to в обратном порядке
    n 0 ?do
        i ns addrlist-nth-addr an-text fl-glob-ensure-1
    loop
    fl-expect-outs @ >r
    n fl-expect-outs !
    m an-l an@ fl-eval
    r> fl-expect-outs !
    n 0 ?do
        n 1- i - ns addrlist-nth-addr an-text
        s" to " emit-st emit-st emit-bl
    loop
    emit-nl ;

: fl-gen-toplevel-stmt ( m -- )           \ LOCAL / ASSIGN / idx-assign
    dup an-type an@ ANT-ASSIGN =
    over an-aux an@ 0= and if
        fl-gen-idx-assign exit
    then
    fl-gen-toplevel-assign ;

\ REPL-метка результата top-level expr ( m -- )
: fl-repl-tag-expr ( m -- )
    { m }
    m an-type an@ ANT-INDEX = if
        m an-r an@ fl-expr-ncells 2 = if 4 else 3 then
        fl-repl-out-cells ! exit
    then
    m an-type an@ ANT-TABLE = if
        m an-op an@ TABLE-MAP = if -1 else -2 then
        fl-repl-out-cells ! exit
    then
    m an-type an@ ANT-ID = if
        m an-text fl-glob-kind
        dup FG-MAP = if drop -1 fl-repl-out-cells ! exit then
        dup FG-LIST = if drop -2 fl-repl-out-cells ! exit then
        drop
    then
    m fl-expr-ncells fl-repl-out-cells ! ;

: fl-gen-item ( m -- )
    { m }
    m an-type an@ ANT-FN = if
        0 fl-repl-out-cells ! m fl-gen-fn exit
    then
    m an-type an@ ANT-ASSIGN =
    m an-type an@ ANT-LOCAL = or if
        0 fl-repl-out-cells ! m fl-gen-toplevel-stmt exit
    then
    \ top-level expression — запомнить тип результата для REPL-печати
    false stack-mode? !
    m fl-repl-tag-expr
    m fl-eval emit-nl ;

: fl-codegen ( -- )
    ['] fl-gen-item an-root @ addrlist-each ;

[THEN]
