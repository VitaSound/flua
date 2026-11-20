\ tests/dispatch_cli_test.4th — wordlist CLI dispatch smoke

require ../../ttester/ttester.4th
require ../../ttester/ttester-ext.4th

: expect-system-ok ( c-addr u -- )
    system $? 0= expect-true ;

\ help / version must exit 0
s" FLUA_HOME=. FLUA_CMD=version gforth flua.4th" expect-system-ok
s" FLUA_HOME=. FLUA_CMD=help gforth flua.4th" expect-system-ok

\ compile with empty stdin (default path)
s" FLUA_HOME=. FLUA_CMD=compile gforth flua.4th </dev/null" expect-system-ok

\ unknown CMD still compiles (legacy fallthrough), must not crash
s" FLUA_HOME=. FLUA_CMD=nosuch gforth flua.4th </dev/null" expect-system-ok

cr ." dispatch_cli_test ok" cr
