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
    u 2 >= if                          \ снять краевые кавычки (" или ')
        a 1 + to a  u 2 - to u
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

\ идентификатор: параметр — подъём/копия (stack) либо просто имя (locals);
\ не-параметр в --stack — ошибка (проверка — в fl-stack-leaf)
: fl-eval-id ( m -- )
    { m }
    stack-mode? @ if
        m an-text fl-stack-leaf
    else
        m an-text emit-st emit-bl
    then ;

: fl-eval-bin ( m -- )
    { m }
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
    m an-l an@ fl-eval
    stack-mode? @ if
        fl-vs @ m-find fl-vsz @ 0 fl-o!
        1 fl-on !
        fl-arrange
    then
    s" negate " emit-st
    m-pop 1 m-push-res ;

\ вызов: аргументы → буфер уровня → выравнивание → имя в постфиксной позиции
: fl-eval-call ( m -- )
    { m }
    0 fl-karg !
    fl-cdepth @ 8 * fl-cbase ! 1 fl-cdepth +!
    m an-aux an@ { args }
    args ulist-len 0 ?do
        i args ulist-nth-addr fl-eval
        stack-mode? @ if              \ тэг аргумента — в буфер уровня
            fl-vs @ fl-vsz @ fl-cbase @ fl-karg @ + fl-as!
        then
        1 fl-karg +!
    loop
    stack-mode? @ if                  \ тэги → актуальные слоты → выравнивание
        fl-karg @ 0 ?do
            fl-cbase @ i + fl-as@ swap m-find swap i fl-o!
        loop
        fl-karg @ fl-on !
        fl-arrange
    then
    -1 fl-cdepth +!
    m an-text emit-st emit-bl         \ имя в постфиксной позиции
    fl-karg @ m-popn
    1 m-push-res ;

: fl-eval-1 ( m -- )
    { m }
    m an-type an@ case
        ANT-NUM  of m fl-eval-num  endof
        ANT-STR  of m fl-eval-str  endof
        ANT-ID   of m fl-eval-id   endof
        ANT-BIN  of m fl-eval-bin  endof
        ANT-UN   of m fl-eval-un   endof
        ANT-CALL of m fl-eval-call endof
        true abort" flua: internal codegen error: not an expression"
    endcase ;

: fl-eval-set ( -- ) ['] fl-eval-1 is fl-eval ; fl-eval-set

\ ---- return ----
\ в ветке if: результат на месте, чистка под ним (nip — только в --stack),
\ exit — выход из слова внутри ветки
: fl-ret-stmt ( m -- )
    fl-eval
    stack-mode? @ if
        fl-vs @ m-find fl-vsz @ 0 fl-o!
        1 fl-on !
        fl-arrange
        m-len @ 1- 0 ?do s" nip " emit-st loop
    then
    s" exit " emit-st emit-nl ;

\ на верхнем уровне тела: без exit (слово завершит «;» после тела)
: fl-ret-top ( m -- )
    fl-eval
    stack-mode? @ if
        fl-vs @ m-find fl-vsz @ 0 fl-o!
        1 fl-on !
        fl-arrange
    then
    emit-nl ;

\ ---- if ----
\ одна ветка (br, i): i=0 — первая после «if»; elseif несёт условие,
\ else (cond=0) — только значение; хвост ветки — return с exit
: fl-gen-branch ( br i -- )
    { br i }
    i 0> if
        br an-l an@ if                    \ elseif: условие ≠ 0
            stack-mode? @ if m-pop then   \ результат then-ветки израсходован if'ом
            1 fl-if-n +!
            s" else " emit-st emit-nl
            br an-l an@ fl-eval
            stack-mode? @ if
                fl-vs @ m-find fl-vsz @ 0 fl-o!
                1 fl-on !
                fl-arrange
                m-pop                     \ условие elseif съедается if'ом
            then
            s" if " emit-st emit-nl
        else                              \ else: условия нет
            stack-mode? @ if m-pop then
            s" else " emit-st emit-nl
        then
    then
    br an-r an@ fl-ret-stmt ;

\ весь if: условие → «if», ветки → return-эмиссии, хвост — N × "then "
: fl-gen-if ( m -- )
    { m }
    m an-aux an@ { branches }
    0 branches ulist-nth-addr an-l an@ fl-eval   \ условие первой ветки
    stack-mode? @ if
        fl-vs @ m-find fl-vsz @ 0 fl-o!
        1 fl-on !
        fl-arrange
    then
    s" if " emit-st emit-nl
    stack-mode? @ if m-pop then           \ условие съедается run-time if
    1 fl-if-n !
    branches ulist-len 0 ?do
        i branches ulist-nth-addr i fl-gen-branch
    loop
    fl-if-n @ 0 ?do s" then " emit-st loop
    emit-nl ;

\ ---- stmt и функция ----
: fl-gen-stmt ( m -- )
    dup an-type an@ ANT-IF = if fl-gen-if else fl-ret-top then ;

\ ---- подсчёт использований параметров: обход дерева (--stack) ----
\ fl-count-tree считает AN-ID-листы с именем fl-nna/fl-nnu (имя-вызова
\ живёт в AN-CALL, не в AN-ID). xt для ulist-each параметров — fl-count-one-tree.
variable fl-gen-cur                     \ генерируемая функция (корень обхода)
defer fl-count-tree                     \ рекурсия: узел → счёт по fl-cn

: fl-count-tree-lst ( lst -- )          \ ulist узлов: каждый — fl-count-tree
    { lst }
    lst ulist-len 0 ?do
        i lst ulist-nth-addr fl-count-tree
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
        ANT-BR   of
            m an-l an@ ?dup if fl-count-tree then   \ условие (0 у else)
            m an-r an@ fl-count-tree                \ значение ветки
        endof
        ANT-NUM of endof
        ANT-STR of endof
        ANT-FN  of m an-l an@ fl-count-tree-lst endof \ тело: ulist stmt'ов
                                                       \ (an-aux — параметры,
                                                       \  их не считаем)
    endcase ;

: fl-count-tree-set ( -- ) ['] fl-count-tree-1 is fl-count-tree ; fl-count-tree-set

\ xt для ulist-each: сколько раз параметр — лист в дереве (0 → ошибка)
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

: fl-gen-fn ( fn -- )
    { fn }
    \ параметры: AN-ID-узлы → param-структуры (имена, подсчёт, emit)
    ulist-new fl-params-ul !
    fn an-aux an@ { params }
    params ulist-len 0 ?do
        i params ulist-nth-addr an-text param-new
        fl-params-ul @ ulist-add
    loop
    fl-params-ul @ ulist-reverse         \ ulist-add в голову → порядок чтения
    fn an-text fl-fname-u ! fl-fname-a !
    \ модель стека: слоты 0..n-1 = параметры по порядку объявления
    m-reset
    fl-params-ul @ ulist-len 0 ?do i m-append loop
    stack-mode? @ if
        fn fl-gen-cur !
        ['] fl-count-one-tree fl-params-ul @ ulist-each
    then
    \ шапка: комментарии перед function (диапазон токенов от fl-p-program) + нотация
    fn fl-hdr-cm-fill
    cm-flush
    s" \ ( " emit-st
    fl-emit-names
    s" -- r )" emit-st emit-nl
    \ определение слова
    s" : " emit-st fl-fname-a @ fl-fname-u @ emit-st emit-bl
    fl-params-ul @ ulist-len 0> stack-mode? @ 0= and if
        s" { " emit-st fl-emit-names s" }" emit-st
    then
    emit-nl
    \ тело: stmt'* end (end-токены уже проверены парсером)
    fn an-l an@ { stmts }
    stmts ulist-len 0 ?do
        i stmts ulist-nth-addr fl-gen-stmt
    loop
    s" ;" emit-st emit-nl
    stack-mode? @ if
        m-len @ 1 < if
            cr ." flua: stack mode: empty result (final depth " m-len @ . ." )" cr
            -1 throw
        then
    then
    fl-params-ul @ ulist-dispose ;

\ ---- программа ----
: fl-codegen ( -- )                    \ дерево функций → emit-buf
    ['] fl-gen-fn an-root @ ulist-each ;

[THEN]
