# flua — инструкция для ИИ-ассистента

Транспилятор простого подмножества Lua в Forth (Gforth), реализация —
чистый Forth в одном файле `flua.4th`.

## Главный принцип

**Не пиши Forth руками.** Пиши код на Lua во flua-подмножестве (Lua —
язык, на котором ИИ пишет уверенно), транспилируй `flua`, а корректность
Forth проверяй инструментами ниже. Руками пишется только Forth в
тестах-ожиданиях (golden) и в проверочных командах `gforth -e`.

## Рабочий цикл

```bash
export FLUA_HOME="$HOME/flua"
export PATH="$FLUA_HOME/bin:$PATH"

# 1. написать исходник, например calc.lua
# 2. проверить транспиляцию + компиляцию Forth (режимы — прагмы в .lua):
flua-verify calc.lua
#    OK   calc.lua

# 3. проверить ВЫПОЛНЕНИЕ — что функции дают ожидаемое:
flua calc.lua > /tmp/calc.4th
gforth -e 'include /tmp/calc.4th 2 3 calc . cr bye'   # → результат

# 4. перед коммитом — полный набор тестов
fmix test
fmix check --stage pre-commit
```

`flua-verify` возвращает 0 если файл транспилируется и gforth компилирует
генерат (ловит в т.ч. `Undefined word`). Стековый codegen — прагма
`-- @stack` перед `function`, не флаг CLI.

## Подмножество Lua (шпаргалка)

Полные списки — в `README.md`: «Supported Lua subset» и «Чего нет».

Можно:

```lua
x = 10                                     -- глобал → VALUE / TO
s = "hi"                                   -- строковый глобал → 2VALUE / TO
1 + 2                                      -- top-level expr → на data stack
function add(a, b) return a + b end
function f(x)
  local t = x * 2                          -- { x | t } + to
  return t, x                              -- multi-return
end
-- @stack
function add_s(a, b) return a + b end      -- стек без locals
-- @proc
function clear(x)                          -- 0 out; пустой return → exit
  if x < 0 then return end
  x = 0
end
```

- top-level: `function` | `local`/`name = expr` (→ VALUE) | expr | `print(...)`;
- в функции: `local`/`assign`/`return`/`if`/`while`/`repeat`/`print(...)`
  (и др. call-stmt; stmt-списки в ветках);
- `print(a, b)` → `0 .r` / `type` + `space` + `cr` (0 results);
- `return a, b` — out-arity N на всех путях; `-- @proc` → N=0;
- сравнения/логика как раньше (флаг 0/−1); `while`→BEGIN WHILE REPEAT,
  `repeat`/`until`→BEGIN UNTIL;
- прагмы перед `function`: `-- @stack`, `-- @proc` (можно вместе);
- комментарии перед `function` → `\ …` в выводе.

Дополнительно:

```lua
-- @forth open-file ( c-addr u fam -- fileid ior )
-- @forth r/o ( -- fam )                  -- '/' → '_' → r_o()
local fid, ior = open_file(path, r_o())   -- path-строка = 2 клетки + fam
-- @forth fjson.str-concat ( a1 u1 a2 u2 -- a3 u3 )
local a, u = fjson_str_concat(a1, u1, a2, u2)  -- '.'/'?'/'/' → '_'
abort("open")
for i = 1, n do s = s + i end             -- → ?do / loop, индекс = i
local m = { a = 1 }                       -- hashmap
local xs = { 10, 20 }                     -- ulist
local vt, v1, v2, ok = m.a                -- hashmap-get (не x = m.a)
xs[0] = 99                                -- ulist-set-term
```

### Host Forth (`-- @forth`, пакеты)

- Билтины только `print` / `abort("…")`. Всё остальное (файлы, `type`,
  `cr`, fjson, …) — слова host’а через `-- @forth name ( in -- out )`.
- Arity **клеточная**: сумма `ncells` аргументов; строка = 2; `0`→1.
- Имена: `-./?/` → `_`. Символ **`@` не мапится** → алиас в `.4th`.
- `-- @forth` **не** делает `include`. Прагмы `-- @require` нет.
  Пакет грузить host preamble’ом **перед** генератом:
  `gforth examples/json_bridge.4th /tmp/out.4th -e bye`.
- Примеры: `examples/read_file.lua`, `slurp_file.lua`, `parse_json.lua` +
  `json_bridge.4th`. Полный текст — [README § Host Forth](README.md#host-forth).

Нельзя:

- `break`, `goto`, `nil`/`true`/`false` как литералы;
- вложенные `function`; методы, varargs, `--[[ ]]`;
- `local`/assign/`for` внутри `-- @stack` функции;
- RTTI / скрытая типизация строк (держите `a, u` явно);
- смешанный литерал `{ 1, a = 2 }`;
- `include`/`require` из `.lua` (только preamble);
- single-assign от index-get: `x = m.a` → ошибка, нужен multi-assign.

## Контейнеры → fenum

| Lua | Forth (fenum) |
|-----|----------------|
| `{ a = 1, b = "x" }` / `{}` | `hashmap-new` + `TM-STR … hashmap-set` |
| `{ 10, 20, 30 }` | `ulist-new` + `TM-INT … ulist-add` (add reverse — prepend) |
| `{ 10, name = "x" }` | **ошибка** — смесь array+hash |
| `t.a` / `t["k"]` | `hashmap-get` / `hashmap-set` |
| `t[i]` | `ulist-nth-term` / `ulist-set-term` |

- Чтение → multi-assign: `local vt, v1, v2, ok = m.a` (терм + flag).
- Не угадывать тип значения на чтении.
- Host: fenum 0.1.3+; dispose — явно.
- Не плодить flua-алиасы над одним словом (урок пилота `json_has`).

Подробные примеры эмита — [ROADMAP.md](ROADMAP.md).

## Частые ловушки ИИ

1. **Пишу «настоящий» Lua** вне подмножества — `flua: syntax error`.
2. **CLI `--stack` удалён** — пишите `-- @stack` перед нужной `function`.
3. **Руками `roll`/`pick`** не надо — в `@stack` это делает `fl-arrange`.
4. **`..` с целым-параметром** в `@stack` — desync (строка = 2 ячейки).
5. **Unused param** в `@stack` — ошибка.
6. **Проверяю только компиляцию** — всегда гоняйте `gforth -e 'include …'`.
7. **Смешанный `{1, a=2}`** — ошибка; int `t[i]` = ulist, не hashmap.
8. **`-- @forth` без `include` пакета** — Undefined word; нужен preamble.
9. **Строковый `path` как Lua-param** + `@forth` на 3 клетки — arity miss;
   литерал/`2VALUE` на call-site или явные `a, u`.
10. **`print(addr, u)`** ≠ текст; для буфера — `@forth type`.
11. **Слово с `@` в имени** — не импортируется в Lua; алиас в preamble.

## Как добавить тест под новую фичу

1. `tests/golden/<name>.lua` — исходник на Lua.
2. Сгенерировать эталоны:
   ```bash
   flua tests/golden/<name>.lua                > tests/golden/<name>.4th
   flua --stack tests/golden/<name>.lua        > tests/golden/<name>.stack.4th
   ```
3. Добавить строки в `tests/golden_test.4th`:
   `s" <name>" golden-one` и, если кейс валиден в `--stack`,
   `s" <name>" golden-stack-one`.
4. При изменении формата вывода — перегенерировать **все** эталоны и
   обновить точные ожидания в `tests/flua_test.4th`.
5. Убедиться: `fmix test` → `ALL TESTS PASSED` / `ALL GOLDEN TESTS PASSED`.

## Гейты перед коммитом

```bash
fmix test                        # юнит + golden (оба режима)
fmix check --stage pre-commit    # тесты + flint (0 дублей в проекте)
fcov run fmix test && fcov report   # Cov; при смене % — badge в README
```

Не коммитить с незелёными гейтами. `tests/golden/` и `examples/` —
`flint-exclude` / `fcov-exclude` в `package.4th` (фикстуры, не исходники).

## Карта проекта

- `flua.4th` — инфраструктура: emit-буфер, курсор src, стековая модель,
  выравнивание, параметры, шапки-комментарии, CLI (`fl-compile` →
  `fl-p-program` + `fl-codegen`);
- `flua-tokens.4th` — токенизатор (фаза 1 AST-конвейера);
- `flua-ast.4th` — AST: парсер поверх токенов + печать дерева (`flua --ast`);
- `flua-codegen.4th` — кодогенерация: обход дерева → Forth-код;
- `bin/flua` — лаунчер (`--stack`/`-s`, `--ast`/`-a`, `help`, `version`);
- `bin/flua-verify` — проверка файла в обоих режимах;
- `tests/flua_test.4th` — юнит-тесты (ttester), включая точные
  ожидания вывода и кейсы ошибок;
- `tests/ast_test.4th` — тесты вывода AST (байт-в-байт + ошибки);
- `tests/golden_test.4th` + `tests/golden/` — пары `.lua` ↔ эталоны,
  сравнение байт-в-байт + `evaluate`;
- `README.md` — полное описание подмножества и режимов;
- `ROADMAP.md` — статус, fsys, next (map/list → fenum);
- `flua-host.4th` — `host-eval` / REPL (gforth).
