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

- top-level: `function` | `name = expr` | expr | `print(...)`;
- в функции: `local`/`assign`/`return`/`if`/`while`/`repeat`/`print(...)`
  (и др. call-stmt; stmt-списки в ветках);
- `print(a, b)` → `0 .r` / `type` + `space` + `cr` (0 results);
- `return a, b` — out-arity N на всех путях; `-- @proc` → N=0;
- сравнения/логика как раньше (флаг 0/−1); `while`→BEGIN WHILE REPEAT,
  `repeat`/`until`→BEGIN UNTIL;
- прагмы перед `function`: `-- @stack`, `-- @proc` (можно вместе);
- комментарии перед `function` → `\ …` в выводе.

Нельзя:

- `for`, `break`, `goto`, `nil`/`true`/`false` как литералы;
- вложенные `function`; таблицы, методы, varargs, `--[[ ]]`;
- `local`/assign внутри `-- @stack` функции.

## Частые ловушки ИИ

1. **Пишу «настоящий» Lua** вне подмножества — `flua: syntax error`.
2. **CLI `--stack` удалён** — пишите `-- @stack` перед нужной `function`.
3. **Руками `roll`/`pick`** не надо — в `@stack` это делает `fl-arrange`.
4. **`..` с целым-параметром** в `@stack` — desync (строка = 2 ячейки).
5. **Unused param** в `@stack` — ошибка.
6. **Проверяю только компиляцию** — всегда гоняйте `gforth -e 'include …'`.

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
```

Не коммитить с незелёными гейтами. Каталог `tests/golden/` исключён
из flint (`flint-exclude` в `package.4th`) — это фикстуры, а не
исходники.

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
- `README.md` — полное описание подмножества и режимов.
