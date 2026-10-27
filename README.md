# flua — Lua-subset to Forth transpiler
[![License](https://img.shields.io/badge/License-COPL-red.svg)](https://raw.githubusercontent.com/VitaSound/flua/refs/heads/main/LICENSE)
[![Ver](https://img.shields.io/badge/Ver-0.1.0-green.svg)](https://github.com/VitaSound/flua/releases/tag/0.1.0)
[![Cov](https://img.shields.io/badge/Cov-91%25-brightgreen.svg)](https://github.com/VitaSound/flua)

Transpiles a simple Lua subset to Gforth-compatible Forth source.
**Реализация — только Forth (Gforth), без Python и внешних зависимостей.**

Статус и next (контейнеры → fenum): [ROADMAP.md](ROADMAP.md).
Шпаргалка для агента: [AGENTS.md](AGENTS.md).

## Supported Lua subset

Критерий фичи: эмит — **типичный Gforth**, не Lua-VM.

- **Function definitions**: `function name(a, b, ...) … end`
- **Прагмы** перед `function`: `-- @stack` (стек без locals), `-- @proc`
  (0 возвращаемых значений; пустой `return` → `exit`)
- **Integer literals**: decimal and `0x` hex
- **String literals**: `"..."` и `'...'` (эскейпы `\n`, `\t`, `\\`, `\"`, `\'`)
- **Binary operators**: `+ - * / %` (целочисленные; `%` → `mod`)
- **String concatenation**: `..` → `s+` (на стеке строка = 2 клетки)
- **Unary minus**: `-expr` → `negate`
- **Логика**: `not` → `0=`; `and` / `or` — short-circuit; флаг 0/−1
- **Сравнения**: `== ~= < > <= >=` → `= <> < > <= >=`
- **Ветвление**: `if` / `elseif` / `else` со **списками statements** в ветках
  (не только `return`); ранний `return` → `exit`
- **Циклы**: `while … do … end` → `BEGIN WHILE REPEAT`;
  `repeat … until …` → `BEGIN … UNTIL`
- **`local` / assign** (не в `-- @stack`): `{ a | t }` + `to`
- **Multi-return**: `return a, b` — одинаковая out-arity на всех путях
- **Вызовы слов**: `name(a, b)` (expr или statement)
- **Глобалы**: `name = expr` → `VALUE`/`2VALUE` / `TO`
- **`print(...)`**: builtin → `0 .r` / `type` + `space` + `cr`
- **Top-level**: `function` | assign | expr | `print`
- **Комментарии**: `--` до конца строки; блок перед `function` → `\ …`

- **`-- @forth`**: импорт уже существующего слова Gforth/пакета — см. раздел
  [Host Forth](#host-forth) ниже
- **`for i = lo, hi do … end`**: → `hi 1+ lo ?do … loop` (индекс = Forth `i`)
- **`abort("msg")`**: builtin → `true abort" msg"`
- **Таблицы → fenum**: `{ k = v }` → `hashmap-*`; `{ v1, v2 }` → `ulist-*`;
  `{}` → пустой map; смесь array+hash — ошибка. Доступ: `t.a` / `t["k"]` →
  `hashmap-get`/`hashmap-set` (терм + flag); `t[i]` → `ulist-nth-term` /
  `ulist-set-term`. Чтение — multi-assign (`local vt, v1, v2, ok = m.a`);
  **не** `x = m.a` (ошибка: нужен multi-assign). Host: fenum 0.1.3+.

**Чего нет (сейчас в codegen):** `break`, `goto`, `nil`/`true`/`false` как
литералы; вложенные `function`; varargs; `--[[ ]]`;
`local`/assign/`for` в `-- @stack`; **`-- @require` / `include` из `.lua`**
(библиотеки грузит host preamble — см. ниже). Не Lua-VM / RTTI — генерат
должен читаться как типичный Gforth. Int-ключ в `t[i]` = только ulist.

## Output shape

Параметры становятся gforth-locals, тело — постфиксная нотация со стековой нотацией из входных параметров:

```lua
function add(a, b) return a + b end
```

```forth
\ ( a b -- r )
: add { a b }
  a b + 
;
```

Операторы расставляются по приоритету (`a + b * c` → `a b c * +`),
скобки группируются, `0x10` → `$10`, `-x` → `x negate`.
Тело функции и ветки `if`/`while`/`repeat` эмитятся с отступом
(2 пробела на уровень).

`if` транспилируется в Forth `if/else/then`, каждая ветка завершается
`exit`:

```lua
function abs(n)
  if n < 0 then return -n
  else return n
  end
end
```

```forth
\ ( n -- r )
: abs { n }
  n 0 < if 
    n negate exit 
  else 
    n exit 
  then 
;
```

## Installation

```bash
export FLUA_HOME="$HOME/flua"
export PATH="$FLUA_HOME/bin:$PATH"   # одна строка PATH на инструмент (конвенция VitaSound)
```

## Usage

```bash
flua file.lua     # компиляция файла → Forth на stdout
flua              # чтение Lua из stdin
flua --ast f      # вывод AST (дерево разбора) вместо кода (флаг: -a)
flua repl         # REPL: Lua → Forth → evaluate в gforth
flua help         # справка
flua version      # версия
```

Прагмы перед `function`: `-- @stack` (стековая эмиссия без locals),
`-- @proc` (слово без возвращаемых значений). CLI `--stack` удалён.

## Host Forth

flua — **транспилятор**, не Lua-рантайм. Почти весь I/O и библиотеки —
это обычные слова Gforth (или пакетов вроде fjson/fenum). Их не нужно
«добавлять в язык»: достаточно объявить сигнатуру и вызвать.

### Билтины flua vs импорт

| Имя в Lua | Откуда | Нужен `-- @forth`? |
|-----------|--------|-------------------|
| `print(...)` | codegen → `0 .r` / `type` + `cr` | нет |
| `abort("msg")` | codegen → `true abort" msg"` | нет |
| `open_file`, `type`, `cr`, `allocate`, `r_o`, `fjson_parse`, … | слово host’а | **да** |

Каталога «всех» Forth-слов во flua **нет**: сигнатуры берите из man Gforth /
документации пакета (ANS File-Access, Memory-Allocation, [fjson API](https://github.com/VitaSound/fjson)).

### Прагма `-- @forth`

```lua
-- @forth open-file ( c-addr u fam -- fileid ior )
-- @forth r/o ( -- fam )
local fid, ior = open_file("x.txt", r_o())
```

- Это **не** обычный комментарий: парсер регистрирует импорт.
- В генерате будет вызов Forth-слова `open-file` / `r/o`.
- **Клеточная arity**: сумма клеток аргументов = `in` в `( in -- out )`.
  Строка (литерал или `2VALUE`) = **2** клетки → один Lua-аргумент-строка
  закрывает два слота. Неизвестное (`ncells=0`) считается как 1.
- Lua-имя: `-` `.` `?` `/` → `_` (`open-file`→`open_file`, `r/o`→`r_o`).
  Символ **`@` в имени не мапится** — нельзя написать `fjson_node_str@` в Lua;
  сделайте алиас в Forth (`: fjson-node-str … fjson.node-str@ ;`) и импортируйте его.
- `out` стыкуется multi-assign: `local a, b = word(...)`.
- `-- @forth` **не загружает** файл: только имя + arity. Если слова ещё нет
  в словаре host’а → `Undefined word` при `include` генерата.

### Как подключить пакет (`include` / `require`)

Сейчас из `.lua` **нельзя** эмитить `include`. Паттерн:

1. `.lua` — логика + `-- @forth …`
2. короткий host preamble `.4th` — `include`/`fpath` библиотек (+ алиасы)
3. запуск: preamble **перед** генератом

```bash
flua examples/parse_json.lua > /tmp/parse_json.4th
gforth examples/json_bridge.4th /tmp/parse_json.4th -e bye
```

`json_bridge.4th` подтягивает fenum + fjson и объявляет `fjson-node-str` /
`fjson-node-num`. Пути в preamble — **от каталога этого `.4th`** (gforth
при `include` файла меняет относительную базу).

Для файлов без внешних пакетов preamble не нужен — хватает слов ядра Gforth
(после transpile):

```bash
flua examples/read_file.lua > /tmp/read_file.4th
gforth -e 'include /tmp/read_file.4th bye'   # из корня репо (путь к data.txt)
```

### Примеры

| Файл | Что показывает |
|------|----------------|
| [`examples/read_file.lua`](examples/read_file.lua) | `r/o`, `open-file`, `allocate`, `read-file`, `type`, `cr` |
| [`examples/slurp_file.lua`](examples/slurp_file.lua) | `slurp-file` |
| [`examples/data.txt`](examples/data.txt) | фикстура для чтения |
| [`examples/json_bridge.4th`](examples/json_bridge.4th) | host `include` fjson + алиасы без `@` |
| [`examples/parse_json.lua`](examples/parse_json.lua) | `fjson.parse` → поля → Lua `{}` (fenum hashmap) |

Замечание: `fjson.parse` даёт **дерево нод**, не hashmap. В map кладёте
поля сами (`hashmap-set` / присваивания). Обратное (map→JSON) — `fjson.emit-mmap`.

### Ловушки

- Параметр Lua-функции = **1** клетка locals. Строковый путь как один
  `function f(path)` + внутри `open_file(path, fam)` **не** сработает по
  arity (path локаль неизвестна → 1 клетка). Передавайте литерал/`2VALUE`
  на call-site `@forth` или явные `a, u`.
- `print(buf, got)` для буфера `(addr u)` печатает два целых; для текста —
  `@forth type` / `cr`.
- Имена функций с `_`: define оставляет `_`, вызов эмитит `-` — лучше
  без underscore в имени `function` или зовите из Forth по фактическому имени.

## Режим `-- @stack` (на функцию)

По умолчанию параметры/locals — gforth `{ a b | t }`. Прагма `-- @stack`
перед функцией даёт чисто стековый вариант без `{ }`, с `pick`/`roll`:

```lua
-- @stack
function add(a, b) return a + b end
```

```lua
function add(a, b) return a + b end
```

```forth
\ @stack
\ ( a b -- r )
: add
  + 
;
```

### Последовательность шагов генерации

1. **Модель стека.** На входе в тело модель отражает физический стек:
   слоты `0..n-1` — параметры по порядку объявления (тэги = индексы),
   вычисленные значения — временные слоты с уникальными тэгами 128..255
   (`m-push-tmp`). Каждая ячейка стека = один слот; строка занимает 2.
2. **Лист-параметр, первое использование** (`fl-stack-leaf`): значение
   нужно ещё раз, поэтому сразу эмитится **копия** на вершину:
   `dup` (глубина 0), `over` (глубина 1), иначе `d pick` — оригинал
   остаётся на своём слоте.
3. **Лист-параметр, последнее использование**: подъём здесь **не
   эмитится**. В модель/переменную результата запоминается только тэг
   значения, а слот пересчитывается через `m-find` в момент
   использования — так сохранённый операнд не «протухает», если
   подъёмы правого операнда сдвинули его слот.
4. **Потребитель** (оператор, вызов слова, `return`) вызывает
   `fl-arrange` — выравнивание блока операндов:
   - **быстрая проверка** (`fl-ocheck`): блок уже лежит верхними
     слотами в порядке чтения — подъёмов нет **вообще**;
   - иначе — **прямой проход**: для каждого операнда, чей слот ниже
     своей цели, — подъём наверх (`fl-oroll-op`); операнды, уже
     стоящие на месте или выше цели, не трогаются — их опустят
     подъёмы следующих;
   - после прохода — контрольный чек; расхождение = внутренняя ошибка
     `flua: stack arrange failed`.
5. **Финал функции**: результат через `fl-arrange` поднимается на
   вершину, итоговая глубина модели должна быть ≥ 1.

Подсчёт «где последнее использование» — обход дерева AST
(`fl-count-tree` в `flua-codegen.4th`), счётчики `count/used`
живут в структурах параметров (fenum `ulist`).

### Зачем вообще подъём

Операнды оператора должны лежать **верхним блоком в порядке чтения**:
первый операнд — ниже, последний — на вершине (тогда `+` сложит
именно `a` и `b`). Параметры входят в функцию в порядке объявления,
поэтому:

- если тело читает их в том же порядке (`a + b`) — блок уже собран,
  подъём не нужен;
- если порядок нарушен (`b + a`) — значение нужно перенести через
  `d roll` (перенос с глубины d на вершину) или `swap` при d = 1;
- если значение уже лежит на вершине (d = 0) — подъём не эмитится.

В первой (жадной) реализации подъём эмитился сразу при чтении листа.
Для `add(a, b) return a + b` это давало `1 roll 1 roll +`: первый
roll поднимал `a` над `b`, второй возвращал `b` наверх — пара роллов
взаимно гасилась, и к `+` стек и так приходил в исходном порядке.

### Как это оптимизируется

Отложенная эмиссия (шаг 3) плюс проверка «блок на месте» (шаг 4)
убирают подъём-избыточность целиком:

| выражение | раньше (жадно) | сейчас |
|-----------|----------------|--------|
| `a + b` | `1 roll 1 roll +` | `+` |
| `a + b * c` | `2 roll 2 roll 2 roll * +` | `* +` |
| `(b + a) * (a - b)` | — | `dup 2 pick + 2 roll 2 roll - *` |
| `b + a` (обратный порядок) | `1 roll +` | `swap +` |

Подъёмы остаются только там, где без них стек не собрать:
приоритет `*` над `+` вынуждает поднять `c` над уже накопленным
результатом, вызов с аргументами в обратном порядке — поднять
нужный аргумент. Фактический вывод зафиксирован golden-эталонами.

### Почему вместо `1 roll` не сразу `swap`

`swap` — частный случай `1 roll`: на двух верхних ячейках они
эквивалентны. Общий примитив — `d roll` с произвольной глубиной
(`2 roll` и глубже эквивалента swap не имеют), поэтому эмиттер
строит подъём на этом примитиве, а для d = 1 специализирует вывод
в `swap` (как `1 pick` → `over`). Замена roll → swap сама по себе
не экономит ходы; главный выигрыш — в отсутствии подъёмов вовсе,
когда операнды уже на месте.

### Ограничения режима (типов в подмножестве нет)

- неиспользуемый параметр — ошибка: `parameter 'a' is unused (stack mode)`;
- `..` с операндом-целым (параметром) — ошибка десинка: строка занимает
  2 слота, `s+` ждёт 4 — конкатенировать можно строки без параметров-целых;
- модель сверяется на каждом шаге: нехватка слотов →
  `flua: stack model desync …`; финальная глубина ≥ 1.

## Режим `--ast` (вывод AST)

Тот же конвейер токенов и парсера (`flua-tokens.4th` → `flua-ast.4th`):
дерево разбора печатается вместо Forth-кода; кодоген не задействуется,
режим `--stack` на вывод не влияет.

```bash
flua --ast file.lua    # также: flua ast file.lua, короткий флаг -a
```

```lua
function add(a, b) return a + b end
```

```
fn add(a, b)
  bin +
    id a
    id b
```

Узлы: `fn` (имя с параметрами в скобках, тело — под-дерево), `bin`/`un`
(бинарный/унарный оператор), `call` (вызов, аргументы — под-деревья),
`num`/`str`/`id` — листья, текст цитируется из исходника (`str` — с кавычками
и escape'ами). Скобки группировки прозрачны. Отступ — 2 пробела на уровень;
функции печатаются в порядке чтения. Синтаксическая ошибка — как в
компиляторе: `flua: syntax error at L:C (offset N)` (строка:столбец и
байтовая позиция) и код возврата ≠ 0.

## Architecture (чистый Forth)

| Слой | Слова |
|------|-------|
| Токенизатор | `flua-tokens.4th`: `fl-tokenize` → массив токенов TK-ID/NUM/STR/OP/CM/EOF; `src-set` `src-at` `src-peek` `src-next` — побайтовый курсор, `src-skip-ws`/`src-comment?` — пробелы и `--`-комментарии |
| Парсер (AST) | `flua-ast.4th`, рекурсивный спуск: `fl-p-or(или)` → `fl-p-and(и)` → `fl-p-relational(сравнения)` → `fl-p-concat(..)` → `fl-p-additive(+-)` → `fl-p-term(*/%)` → `fl-p-unary(- not)` → `fl-p-primary`; дерево — узлы-записи `an-node`, реестр `an-nodes`/`an-reset` |
| Кодоген | `flua-codegen.4th`: `fl-codegen` — обход дерева, `emit-ch`/`emit-st` — постфиксная запись в выходной буфер; `fl-op-emit` — оператор → Forth-слово; шапки-комментарии через `cm-buf` |
| Стековая модель (`--stack`) | `m-model/m-len/m-tag` — слоты и уникальные тэги значений; `fl-stack-leaf` — первое использование: `dup`/`over`/`d pick`, последнее: подъём отложен; `fl-arrange`/`fl-ocheck`/`fl-oroll-op` — выравнивание блока операндов (см. «Режим --stack»); `m-find`/`m-move-to-top`/`m-popn` (guard), `fl-count-tree` — подсчёт использований по дереву |
| AST (`--ast`) | печать того же дерева: `flua-ast.4th`, `an-print` (дерево в emit-buf), `fl-ast-run` |
| CLI | `bin/flua` → gforth + `flua.4th`; диспетчер по `FLUA_CMD` (`FLUA_ARG` — файл, иначе stdin); режим — `FLUA_MODE=stack` (`--stack`/`-s`); `FLUA_CMD=ast` — вывод AST (`--ast`/`-a`/подкоманда `ast`) |

## Project structure

```
/home/sea/flua/
├── package.4th             — манифест VitaSound (name flua, COPL, deps fmix/flint/fcov/ttester)
├── bin/flua                — CLI-лаунчер (конвенция: одна строка PATH на тул)
├── flua.4th                — инфраструктура: emit-буфер, курсор src, стековая
│                             модель, выравнивание, параметры, CLI (fl-compile)
├── flua-tokens.4th         — токенизатор (фаза 1 конвейера)
├── flua-ast.4th            — AST: парсер поверх токенов + печать дерева (--ast)
├── flua-codegen.4th        — кодогенерация: обход дерева → Forth-код
├── flua-host.4th           — host-eval / REPL (gforth)
├── examples/               — файлы, fjson bridge (см. Host Forth)
├── ROADMAP.md              — статус, fsys, next (контейнеры → fenum)
├── tests/
│   ├── flua_test.4th       — юнит-тесты на ttester
│   ├── golden_test.4th     — golden-тесты (исходник ↔ эталон, байт-в-байт)
│   ├── ast_test.4th        — тесты вывода AST (байт-в-байт + ошибки)
│   └── golden/             — пары <name>.lua ↔ <name>.4th (locals) и
│                             <name>.stack.4th (режим --stack)
│       ├── add.lua / add.4th / add.stack.4th
│       ├── priority.lua / priority.4th / priority.stack.4th
│       ├── unary_hex.lua / unary_hex.4th / unary_hex.stack.4th
│       ├── strings.lua / strings.4th          (locals-only, см. ограничения)
│       ├── comments.lua / comments.4th / comments.stack.4th
│       ├── calls.lua / calls.4th / calls.stack.4th
│       ├── concat.lua / concat.4th / concat.stack.4th
│       └── reorder.lua / reorder.4th / reorder.stack.4th  (обратный порядок → swap)
├── .gitignore
└── README.md
```

## Tests

```bash
fmix test                        # весь набор (flua_test + golden_test + ast_test)
fcov run fmix test && fcov report   # definition coverage (badge Cov)
gforth tests/flua_test.4th       # юнит-тесты отдельно
gforth tests/golden_test.4th     # golden-тесты отдельно
gforth tests/ast_test.4th        # тесты вывода AST отдельно
```

**Юнит-тесты** (`flua_test.4th`): точное совпадение вывода, наличие ключевых
конструкций, реальное выполнение сгенерированного Forth (`evaluate` +
`T{ ... -> ... }T`), ожидаемые синтаксические ошибки.

**Golden-тесты** (`golden_test.4th`) — два прохода на каждой паре:
locals-режим (`<name>.4th`) и stack-режим (`<name>.stack.4th`).
Для каждой пары: компиляция исходника, байт-в-байт сравнение с эталоном
(`compare`) и выполнение сгенерированного Forth. Пары перечислены явно
(`golden-one` / `golden-stack-one`). Рассинхрон даёт `GOLDEN MISMATCH`
(с пометкой `[stack]`).

**AST-тесты** (`ast_test.4th`): точное сравнение вывода `fl-ast-run`
с ожидаемым деревом (байт-в-байт), негативные кейсы через `catch`
(`ast-error?`), включая работоспособность парсера и реестра узлов
после ошибки. Строки `flua: syntax error at L:C (offset N)` в прогоне —
ожидаемый вывод негативных кейсов.

Добавить golden-пару:
1. `tests/golden/<name>.lua` — исходник на Lua;
2. сгенерировать эталон(ы):
   `flua tests/golden/<name>.lua > tests/golden/<name>.4th` и
   `flua --stack tests/golden/<name>.lua > tests/golden/<name>.stack.4th`
   (при изменении формата вывода — осознанно перегенерировать все);
3. добавить строки `s" <name>" golden-one` и (для валидного в --stack
   кейса) `s" <name>" golden-stack-one` в `tests/golden_test.4th`.

## License

COPL (см. `package.4th`).
