# flua — Lua-subset to Forth transpiler

Transpiles a simple Lua subset to Gforth-compatible Forth source.
**Реализация — только Forth (Gforth), без Python и внешних зависимостей.**

## Supported Lua subset

- **Function definitions**: `function name(a, b, ...) return expr end`
- **Integer literals**: decimal and `0x` hex
- **String literals**: `"..."` и `'...'` (эскейпы `\n`, `\t`, `\\`, `\"`, `\'`)
- **Binary operators**: `+ - * /` (целочисленные)
- **String concatenation**: `..` (транспилируется в `s+`)
- **Unary minus**: `-expr` → `negate`
- **Вызовы слов**: `name(a, b)` и ссылки на параметры `name`
- **Комментарии**: `--` до конца строки

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

## Installation

```bash
export FLUA_HOME="$HOME/flua"
export PATH="$FLUA_HOME/bin:$PATH"   # одна строка PATH на инструмент (конвенция VitaSound)
```

## Usage

```bash
flua file.lua     # компиляция файла → Forth на stdout
flua              # чтение Lua из stdin
flua --stack f    # режим --stack (короткий флаг: -s) — стековая эмиссия
flua help         # справка
flua version      # версия
```

## Режим `--stack`

По умолчанию параметры становятся gforth-locals (`: add { a b } …`).
Режим `--stack` генерирует чисто стековый вариант: шапка — только
стековая нотация `( a b -- r )`, тело — `roll` / `pick` / `dup`
по позициям параметров:

```bash
flua --stack file.lua          # или flua -s file.lua
FLUA_MODE=stack flua file.lua  # режим также задаётся окружением
```

```lua
function add(a, b) return a + b end
```

```forth
\ ( a b -- r )
: add
1 roll 1 roll +
;
```

Как расставляется подъём:

- параметр используется впервые — `d pick` (копия с глубины d) или `dup`
  с вершины;
- последнее использование параметра — `d roll` (перенос на вершину);
- порядок использования вычисляется лексическим сканом тела функции
  (`fl-scan-end` / `fl-count`), позиции живут в структурах параметров
  (fenum `ulist`);
- модель стека сверяется на каждом шаге: нехватка слотов →
  `flua: stack model desync …`, итоговая глубина должна быть ≥ 1.

Ограничения режима (типов в подмножестве нет):

- неиспользуемый параметр — ошибка: `parameter 'a' is unused (stack mode)`;
- `..` с операндом-целым (параметром) — ошибка десинка: строка занимает
  2 слота, `s+` ждёт 4 — конкатенировать можно строки без параметров-целых.

## Architecture (чистый Forth)

| Слой | Слова |
|------|-------|
| Лексер | `src-set` `src-at` `src-peek` `src-next` — побайтовый курсор; `src-trivia` (пробелы + `--`-комментарии); `src-ident`, `fl-parse-number`, `fl-parse-string` |
| Парсер | рекурсивный спуск: `fl-parse-concat(..)` → `fl-parse-additive(+-)` → `fl-parse-term(*/)` → `fl-parse-unary(-)` → `fl-parse-primary` |
| Эмит | `emit-ch`/`emit-st` — постфиксная запись в выходной буфер; `defer fl-parse-expr` связан с `fl-parse-concat` |
| Стековая модель (`--stack`) | `m-model/m-len` — слоты текущего стека; `m-find`/`m-move-to-top`/`m-push-tmp`/`m-popn` (guard-проверка); `fl-count`/`fl-scan-end`/`fl-skip-string` — подсчёт использований; `fl-stack-leaf` — `pick`/`roll`/`dup` |
| CLI | `bin/flua` → gforth + `flua.4th`; диспетчер по `FLUA_CMD` (`FLUA_ARG` — файл, иначе stdin); режим — `FLUA_MODE=stack` (`--stack`/`-s`) |

## Project structure

```
/home/sea/flua/
├── package.4th             — манифест VitaSound (name flua, COPL, deps fmix/flint/fcov/ttester)
├── bin/flua                — CLI-лаунчер (конвенция: одна строка PATH на тул)
├── flua.4th                — вся реализация: лексер + парсер + CLI
├── tests/
│   ├── flua_test.4th       — юнит-тесты на ttester
│   ├── golden_test.4th     — golden-тесты (исходник ↔ эталон, байт-в-байт)
│   └── golden/             — пары <name>.lua ↔ <name>.4th (locals) и
│                             <name>.stack.4th (режим --stack)
│       ├── add.lua / add.4th / add.stack.4th
│       ├── priority.lua / priority.4th / priority.stack.4th
│       ├── unary_hex.lua / unary_hex.4th / unary_hex.stack.4th
│       ├── strings.lua / strings.4th          (locals-only, см. ограничения)
│       ├── comments.lua / comments.4th / comments.stack.4th
│       ├── calls.lua / calls.4th / calls.stack.4th
│       └── concat.lua / concat.4th / concat.stack.4th
├── .gitignore
└── README.md
```

## Tests

```bash
fmix test                        # весь набор (flua_test + golden_test)
gforth tests/flua_test.4th       # юнит-тесты отдельно
gforth tests/golden_test.4th     # golden-тесты отдельно
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
