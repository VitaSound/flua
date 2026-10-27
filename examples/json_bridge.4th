\ Host preamble: fenum + fjson + Lua-friendly aliases (без '@' в имени).
\ Пути относительно этого файла (examples/) — gforth include меняет каталог.
\
\ Запуск из корня flua:
\   flua examples/parse_json.lua > /tmp/parse_json.4th
\   gforth examples/json_bridge.4th /tmp/parse_json.4th -e bye

include ../../fenum/fenum.4th
fpath path+ ../../fjson/fjson
include ../../fjson/fjson.4th

\ '@' не мапится в Lua-идентификатор — тонкие обёртки
: fjson-node-str ( node -- a u ) fjson.node-str@ ;
: fjson-node-num ( node -- u )   fjson.node-num@ ;
