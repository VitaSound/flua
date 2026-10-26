\ flua.4th — транспилятор простого подмножества Lua в Forth (Gforth).
\ Только Forth, без Python. Часть экосистемы VitaSound Forth tooling.
\
\ Поддерживаемое подмножество:
\   -- line comments
\   function name(a, b) return expr end
\   целые (десятичные, 0x hex), унарный минус
\   строки "..." и '...' (эскейпы \n \t \\ \" \')
\   бинарные + - * / % (остаток → mod), конкатенация ..  → s+
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
    2drop s" ../fenum/fenum-ulist-bs.4th" required ;

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
variable fl-vs     \ тэг значения последнего подвыражения
variable fl-vsz    \ размер этого значения в ячейках (1 — целое, 2 — строка)
variable fl-mtag   \ следующий уникальный тэг временного значения (128..255)
: m-reset ( -- ) 0 m-len ! 128 fl-mtag ! ;
: m-append ( c -- ) m-len @ m-model + c! 1 m-len +! ;
: m-push-tmp ( -- )                     \ темп с УНИКАЛЬНЫМ тэгом: слот всегда пересчитывается
    fl-mtag @ 255 > if
        cr ." flua: too many temporary values" cr -1 throw
    then
    fl-mtag @ dup 1+ fl-mtag ! m-append ;
: m-push-res ( sz -- )                  \ результат из sz ячеек: фиксирует fl-vs/fl-vsz
    dup fl-vsz !
    dup 0 ?do m-push-tmp loop
    drop
    fl-mtag @ fl-vsz @ - fl-vs ! ;
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

: emit-uint ( n -- ) s>d <# #s #> emit-st ;

\ ==================== выравнивание операндов (режим --stack) ====================
\ Перед токеном потребителя (оператор / вызов / return) операнды должны лежать
\ верхним блоком в порядке чтения: первый операнд — ниже, последний — на вершине.
\ Слоты живут в fl-oslot/fl-osz; при набивке тэги превращаются в слоты через
\ m-find — поэтому сохранённый тэг левого операнда не протухает при подъёмах.
create fl-oslot 8 cells allot
create fl-osz   8 cells allot
variable fl-on                           \ число операндов текущего потребителя
variable fl-obase                        \ база блока операндов в модели
create fl-aslot 64 cells allot           \ буфер аргументов вызовов (8 уровней x 8)
create fl-asz   64 cells allot
variable fl-cdepth                       \ глубина вложенности вызовов

: fl-o! ( slot size n -- )
    >r fl-osz r@ cells + ! fl-oslot r@ cells + ! r> drop ;
: fl-o@ ( n -- slot size )
    >r fl-oslot r@ cells + @ fl-osz r@ cells + @ r> drop ;
: fl-as! ( tag size n -- )
    >r fl-asz r@ cells + ! fl-aslot r@ cells + ! r> drop ;
: fl-as@ ( n -- tag size )
    >r fl-aslot r@ cells + @ fl-asz r@ cells + @ r> drop ;

: fl-ototal ( -- sz ) 0 fl-on @ 0 ?do i fl-o@ nip + loop ;
: fl-ooff ( n -- off ) 0 swap 0 ?do i fl-o@ nip + loop ;

: fl-ocheck ( -- f )                     \ блок операндов уже лежит на своих местах?
    fl-ototal negate m-len @ + fl-obase !
    true
    fl-on @ 0 ?do
        i fl-o@ drop i fl-ooff fl-obase @ + = and
    loop ;

\ поднять ячейку из слота from наверх: эмит (swap при d=1, иначе d roll),
\ перенос байта в модели и поправка слотов остальных операндов
: fl-oroll-cell ( from -- )
    dup m-len @ 1- over -                 \ ( from d )
    dup 0 > if
        dup 1 = if
            drop s" swap " emit-st
        else
            emit-uint emit-bl s" roll " emit-st
        then
    else drop then
    m-move-to-top
    fl-on @ 0 ?do
        i fl-o@ drop                      \ ( from slot )
        2dup = if drop m-len @ 1-
        else 2dup < if 1- then then
        fl-oslot i cells + !
    loop
    drop ;

variable fl-or-n variable fl-or-z variable fl-or-s
\ поднять операнда №n наверх (строка из 2 ячеек катится глубокой первой)
: fl-oroll-op ( n -- )
    fl-or-n !
    fl-or-n @ fl-o@ nip fl-or-z !
    fl-or-z @ 0 ?do
        fl-oslot fl-or-n @ cells + @ fl-or-s !
        fl-or-s @ fl-oroll-cell
        i 0= fl-or-z @ 1 > and if
            fl-or-s @                    \ многоячеечный: партнёр встал в этот слот
        else
            m-len @ fl-or-z @ -          \ последняя ячейка наверху: глубина = L-sz
        then
        fl-oslot fl-or-n @ cells + !
    loop ;

\ Главное правило оптимизации: поднимаем только то, что ниже своей цели.
\ Если блок уже на месте (add, priority) — подъёмов нет вовсе.
: fl-arrange ( -- )
    stack-mode? @ 0= if exit then
    fl-on @ 0= if exit then
    fl-ocheck if exit then                \ случай add/priority: подъёмов нет
    fl-on @ 0 ?do
        i fl-o@ drop i fl-ooff fl-obase @ + < if
            i fl-oroll-op                \ слот ниже цели → поднять
        then
    loop
    fl-ocheck 0= if
        cr ." flua: stack arrange failed: base=" fl-obase @ . ." len=" m-len @ . cr
        fl-on @ 0 ?do
            i fl-o@ ."   os[" i . ." ]=slot " swap . ." size " . cr
        loop
        -1 throw
    then ;

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

\ ---------- комментарий перед функцией ----------
\ Комментарии из Lua не копируются как есть: "--" в Forth — это не
\ комментарий, а несуществующее слово. Переносим только комментарий,
\ стоящий непосредственно перед строкой function (включая серию
\ подряд идущих -- строк между функциями): он становится шапкой
\ "\ ..." непосредственно перед стек-комментарием. Всё остальное
\ (внутри тела, в конце файла) отбрасывается: токенизатор хранит их как
\ TK-CM, серию перед function в шапку переносит fl-hdr-cm-fill (codegen).

create cm-buf 4096 allot                 \ выходные строки комментариев
variable cm-u                            \ сколько занято

: cm-reset ( -- ) 0 cm-u ! ;
: cm-put ( c -- ) cm-buf cm-u @ + c! 1 cm-u +! ;

\ текст комментария → буфер строкой "\ текст<LF>"
: cm-add ( a u -- )
    dup 0= if 2drop exit then             \ пустой "--" — пропустить
    2dup + 1- c@ 13 = if 1- then          \ CRLF: убрать \r
    dup 0= if 2drop exit then
    over c@ bl = if 1 /string then      \ один ведущий пробел после "--"
    cm-u @ 3 + over + 4096 > if 2drop exit then \ не влезает — не ломаем
    [char] \ cm-put bl cm-put
    bounds ?do i c@ cm-put loop
    10 cm-put ;

\ эмит накопленного в выходной буфер и сброс (перед шапкой функции)
: cm-flush ( -- )
    cm-u @ 0= if exit then
    cm-buf cm-u @ emit-st cm-reset ;

\ ============================== синтаксическая ошибка ==============================

: fl-syntax-error ( -- )
    ." flua: syntax error at offset " src-pos @ . cr
    -1 throw ;

\ ============================== идентификатор (токенизатор) ==============================

: src-ident ( -- a u )                    \ [A-Za-z_][A-Za-z0-9_]*
    src-eof? if 0 0 exit then
    0 src-at fl-alpha? 0= if 0 0 exit then
    src-a @ src-pos @ +
    begin src-peek fl-alnum? while src-next drop repeat
    src-a @ src-pos @ + over - ;

variable strq                             \ закрывающая кавычка строки (flua-tokens)

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
: param-used+!  ( p -- ) 3 cells + dup @ 1+ swap ! ;

\ эмит имён подряд с пробелами: "a b " (как давал старый plist)
: fl-emit-one-name ( p -- ) param-name emit-st emit-bl ;
: fl-emit-names ( -- ) ['] fl-emit-one-name fl-params-ul @ ulist-each ;

\ ---- подсчёт использований параметров: обход дерева (flua-codegen) ----
variable fl-cn                              \ счётчик вхождений
variable fl-nna variable fl-nnu             \ needle: имя параметра
variable fl-if-n                            \ вложенность if..end (число then в кодогене)

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

\ ============================== переменные кодогена ==============================
\ Состояние обхода AST (flua-codegen): аргументы текущего вызова.
variable fl-karg                           \ аргументов в текущем вызове
variable fl-cbase                          \ базовый индекс уровня в буфере аргументов

\ ==== режим --stack: лист-параметр ====

: param-count! ( n p -- ) 2 cells + ! ;   \ счётчик вхождений (fl-count-tree в codegen)

\ Лист-параметр в режиме --stack:
\  - первое использование: копия наверх сразу (dup / over / d pick) — значение
\    нужно ещё раз, оригинал остаётся на своём слоте;
\  - последнее использование: подъём здесь НЕ эмитим — в fl-vs кладём ТЭГ,
\    подъём выполнит потребитель (fl-arrange) перед своим токеном.
variable fl-li
: fl-stack-leaf ( a u -- )
    fl-param-idx dup 0< if 2drop fl-syntax-error then
    fl-li !
    fl-li @ fl-params-ul @ ulist-nth-addr param-used+!
    fl-li @ fl-params-ul @ ulist-nth-addr param-count@
    fl-li @ fl-params-ul @ ulist-nth-addr param-used@ = if
        fl-li @ fl-vs ! 1 fl-vsz !       \ последнее использование: подъём отложен
    else
        fl-li @ m-find                   \ ( slot )
        dup m-len @ 1- over -            \ ( slot d )
        dup 0= if
            drop s" dup " emit-st
        else
            dup 1 = if
                drop s" over " emit-st   \ d=1 → over (это 1 pick)
            else
                emit-uint emit-bl s" pick " emit-st
            then
        then
        2drop                            \ снять обе ячейки (slot d-контекст): после веток остаётся (slot slot)
        1 m-push-res                     \ копия = новый темп
    then ;

\ ============================== имя генерируемой функции (кодоген) ==============================
variable fl-fname-a
variable fl-fname-u

\ ============================== конвейер: парсер AST + кодогенератор ========
\ Токены → дерево (flua-ast) → из дерева: код (flua-codegen) и --ast (бесплатно).
require ./flua-ast.4th
require ./flua-codegen.4th

\ ============================== компилятор ==============================
\ Единый путь: fl-p-program строит дерево (и буферы шапок-комментариев),
\ fl-codegen обходит его и эмитит Forth в emit-buf.

: fl-compile ( a u -- )
    src-set emit-reset 0 fl-cdepth !
    fl-p-program                        \ токены → дерево функций
    fl-codegen ;                        \ дерево → код в emit-buf

\ ============================== CLI ==============================

: flua.help ( -- )
    cr
    ." flua v" flua-version type cr
    ." Транспилятор простого подмножества Lua в Forth (VitaSound)." cr cr
    ." Usage:" cr
    ."   flua [file.lua]    компиляция файла, Forth на stdout" cr
    ."   flua               чтение Lua из stdin" cr
    ."   flua --stack f     стековая эмиссия: без { }, pick/roll (флаг: -s)" cr
    ."   flua --ast f       вывод AST (дерево разбора) вместо кода (флаг: -a)" cr
    ."   flua help          эта справка" cr
    ."   flua version       версия" cr cr
    ." Подмножество Lua: function name(a, b) return expr end," cr
    ." целые (0x hex), строки, + - * / %, .. (s+), вызовы слов." cr ;

: flua.version ( -- ) ." flua v" flua-version type cr ;

\ содержимое файла FLUA_ARG (нет аргумента → stdin);
\ файла нет или не читается → понятная ошибка вместо исключения gforth
: flua.src ( -- a u )
    s" FLUA_ARG" getenv
    dup 0= if 2drop stdin slurp-fid exit then
    2dup file-status nip if
        ." flua: file not found: " type cr -1 throw
    then
    slurp-file ;

: flua.compile-cli ( -- )
    flua.src fl-compile emit-result type cr ;

: flua.ast-cli ( -- )
    flua.src fl-ast-run emit-result type cr ;

: flua.read-mode ( -- )
    s" FLUA_MODE" getenv dup 0= if 2drop exit then
    s" stack" compare 0= if true stack-mode? ! then ;

: flua.dispatch ( -- )
    flua.read-mode
    s" FLUA_CMD" getenv
    2dup s" help" compare 0= if 2drop flua.help bye then
    2dup s" version" compare 0= if 2drop flua.version bye then
    2dup s" ast" compare 0= if 2drop flua.ast-cli bye then
    2drop
    flua.compile-cli bye ;

\ CLI-диспетчер запускается только при наличии FLUA_CMD (bin/flua);
\ require из тестов его не触发ает.
s" FLUA_CMD" getenv nip [IF] flua.dispatch [THEN]
