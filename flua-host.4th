\ flua-host.4th — абстракция хоста выполнения (REPL).
\ По умолчанию — тот же процесс gforth. Позже: адаптер fsys (fsoc).

[IFDEF] host-eval [ELSE]

defer host-eval                          \ ( a u -- ) выполнить Forth-текст
defer host-stack-print                   \ ( -- ) показать стек при depth>0

\ Обрезать data stack до сохранённой глубины (после catch у evaluate
\ стек может быть «кривым»: a/u восстанавливаются не всегда).
: host-trim-depth ( n -- )
    >r begin depth r@ > while drop repeat rdrop ;

: host-eval-gforth ( a u -- )
    warnings @ >r warnings off           \ VALUE b и т.п. не орут «redefined»
    depth 2 - >r                         \ глубина до (a u)
    ['] evaluate catch
    if                                   \ 0 | throw# — if съедает
        cr ." flua: host error" cr
        r@ host-trim-depth
    then
    rdrop
    r> warnings ! ;

: host-stack-print-gforth ( -- )
    depth 0> if .s cr then ;

' host-eval-gforth is host-eval
' host-stack-print-gforth is host-stack-print

[THEN]
