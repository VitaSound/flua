# flua — roadmap

Статус продукта и следующий язык. Шпаргалка для агента — [AGENTS.md](AGENTS.md);
подмножество сегодня — [README.md](README.md).

## Сейчас (0.1.x)

- Подмножество Lua → типичный Gforth (не Lua-VM): expr, if/while/repeat/for,
  local, multi-return, print, VALUE/2VALUE, `-- @stack` / `-- @proc` / `-- @forth`,
  abort, таблицы → fenum (`hashmap`/`ulist`, индекс `t.a`/`t["k"]`/`t[i]`),
  REPL на том же gforth (`flua-host.4th` → `evaluate`).
- В feco catalog; пилот в fsoc (`fsoc/flua/`) — см. урок ниже.
- Критерий фичи: эмит читается как ручной Forth; строки = `a u` (две клетки).
- Зависимость: fenum **0.1.3+** (term-ulist, hashmap, `ulist-set-term`, addrlist).

## Gforth vs fsys

Дефолтный codegen эмитит Gforth-locals:

```forth
: add { a b }
  a b +
;
```

На soft-CPU / fsys **`{}` locals нет** — такой генерат там не выполнится.
Для fsys (если когда-либо понадобится) только `-- @stack` (чистый стек).
`VALUE`/`2VALUE` тоже host-зависимы. Заготовка `defer host-eval` в
`flua-host.4th` — не ближайшая задача; блокер — диалект, не «провода».

| Цель | Режим |
|------|--------|
| Host gforth / tooling fsoc | locals (default) |
| fsys / чистый стек | `-- @stack` |


## Контейнеры Lua → fenum (в codegen)

Опора: [fenum](https://github.com/VitaSound/fenum) — термы `[type v1 v2]`
(`TM-INT`, `TM-STR`, `TM-MAP`, `TM-LST`, …), контейнер top:
`hashmap-*`, `ulist-*`. RTTI остаётся в fenum; flua эмитит теги и слова **явно**.

### Два литерала (не смешивать)

| Lua | Куда | Ошибка если |
|-----|------|-------------|
| `{ k = v, ... }` / `{}` | **hashmap** | есть позиционные элементы |
| `{ v1, v2, ... }` | **ulist** | есть `k = v` пары |
| `{ 10, name = "x" }` | — | **смесь запрещена** — ошибка flua |

### Доступ (сахар = get/set)

| Форма | Эмит |
|-------|------|
| `t.a` / `t["k"]` | `hashmap-get` / `hashmap-set` |
| `t[i]` (int) | `ulist-nth-term` / `ulist-set-term` |

Чтение — multi-assign (`local vt, v1, v2, ok = m.a`). Тип значения flua **не**
угадывает. Int-ключ = только ulist.

### Во что соберётся в Forth

#### Словарь → hashmap

```lua
local m = { a = 1, b = "x" }
-- @forth hashmap-get ( kt k1 k2 m -- vt v1 v2 flag )
local vt, v1, v2, ok = hashmap_get(TM_STR, ka, ku, m)
-- @forth hashmap-set ( kt k1 k2 vt v1 v2 m -- )
-- @forth hashmap-has? ( kt k1 k2 m -- flag )
-- @forth hashmap-dispose ( m -- )
```

Идея эмита литерала (типичный Gforth + fenum):

```forth
hashmap-new { m }
TM-STR s" a" TM-INT 1 0 m hashmap-set
TM-STR s" b" TM-STR s" x" m hashmap-set   \ значение-строка: TM-STR + ptr u от s"
```

Bare-ключ `a` в `{ a = 1 }` = строковый ключ `"a"`. Значение-строка =
`TM-STR ptr len`. Вложенный словарь-литерал → отдельный `hashmap-new`,
значение `TM-MAP child 0`. Host должен иметь `fenum` (hashmap).

#### Список → ulist

```lua
local xs = { 10, 20, 30 }
-- @forth ulist-nth-term ( n lst -- vt v1 v2 )
local vt, v1, v2 = ulist_nth_term(0, xs)
-- @forth ulist-add ( vt v1 v2 lst -- )
-- @forth ulist-dispose ( lst -- )
```

Идея эмита:

```forth
ulist-new { xs }
TM-INT 10 0 xs ulist-add
TM-INT 20 0 xs ulist-add
TM-INT 30 0 xs ulist-add
```

(порядок add = prepend в текущем fenum — зафиксировать при реализации
codegen: либо reverse после наполнения, либо add в обратном порядке литерала,
чтобы nth совпадал с ожиданием агента.)

Строковый элемент → `TM-STR`; вложенный list/map → `TM-LST` / `TM-MAP`.
