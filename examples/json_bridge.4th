\ Deprecated: use -- @fpath / -- @require in the .lua file instead.
\ Kept as a thin redirect for old docs/commands.
\
\   flua examples/parse_json.lua > /tmp/parse_json.4th
\   gforth /tmp/parse_json.4th -e bye
\
\ Legacy (preamble before generat):
\   gforth examples/json_bridge.4th /tmp/parse_json.4th -e bye

include ../../fenum/fenum.4th
fpath path+ ../../fjson/fjson
include ../../fjson/fjson.4th
