-- Parse JSON via fjson (host include), put fields into a Lua/fenum map.
--
--   flua examples/parse_json.lua > /tmp/parse_json.4th
--   gforth examples/json_bridge.4th /tmp/parse_json.4th -e bye
--
-- json_bridge.4th: require fjson + aliases fjson-node-str / fjson-node-num.
-- fjson.parse → дерево нод (не hashmap); поля кладём в {} сами.

-- @forth fjson.parse ( a u -- node )
-- @forth fjson.object-get ( ka ku obj -- node )
-- @forth fjson-node-str ( node -- a u )
-- @forth fjson-node-num ( node -- u )
-- @forth fjson.node-free ( node -- )
-- @forth TM-STR ( -- t )
-- @forth TM-INT ( -- t )
-- @forth hashmap-set ( kt k1 k2 vt v1 v2 m -- )
-- @forth type ( c-addr u -- )
-- @forth cr ( -- )

function demo()
  local root = fjson_parse("{\"name\":\"flua\",\"n\":42}")
  if root == 0 then abort("parse") end

  local ns = fjson_object_get("name", root)
  local na, nu = fjson_node_str(ns)
  local nn = fjson_object_get("n", root)
  local n = fjson_node_num(nn)

  local m = {}
  local ts = TM_STR()
  local ti = TM_INT()
  hashmap_set(ts, "name", ts, na, nu, m)
  hashmap_set(ts, "n", ti, n, 0, m)

  local vt, v1, v2, ok = m.name
  type(v1, v2)
  cr()
  local wt, w1, w2, ok2 = m.n
  print(w1)

  fjson_node_free(root)
end

demo()
