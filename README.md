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
flua help         # справка
flua version      # версия
```

## Architecture (чистый Forth)

| Слой | Слова |
|------|-------|
| Лексер | `src-set` `src-at` `src-peek` `src-next` — побайтовый курсор; `src-trivia` (пробелы + `--`-комментарии); `src-ident`, `fl-parse-number`, `fl-parse-string` |
| Парсер | рекурсивный спуск: `fl-parse-concat(..)` → `fl-parse-additive(+-)` → `fl-parse-term(*/)` → `fl-parse-unary(-)` → `fl-parse-primary` |
| Эмит | `emit-ch`/`emit-st` — постфиксная запись в выходной буфер; `defer fl-parse-expr` связан с `fl-parse-concat` |
| CLI | `bin/flua` → gforth + `flua.4th`; диспетчер по `FLUA_CMD` (`FLUA_ARG` — файл, иначе stdin) |

## Project structure

```
/home/sea/flua/
├── package.4th             — манифест VitaSound (name flua, COPL, deps fmix/flint/fcov/ttester)
├── bin/flua                — CLI-лаунчер (конвенция: одна строка PATH на тул)
├── flua.4th                — вся реализация: лексер + парсер + CLI
├── tests/
│   ├── flua_test.4th       — юнит-тесты на ttester
│   ├── golden_test.4th     — golden-тесты (исходник ↔ эталон, байт-в-байт)
│   └── golden/             — пары <name>.lua (исходник) ↔ <name>.4th (эталон)
│       ├── add.lua / add.4th
│       ├── priority.lua / priority.4th
│       ├── unary_hex.lua / unary_hex.4th
│       ├── strings.lua / strings.4th
│       ├── comments.lua / comments.4th
│       └── calls.lua / calls.4th
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

**Golden-тесты** (`golden_test.4th`): для каждой пары `tests/golden/<name>.lua`
↔ `tests/golden/<name>.4th` — компиляция исходника, байт-в-байт сравнение
с эталоном (`compare`) и выполнение сгенерированного Forth. Пары перечислены
явно в `golden-cases` (стиль fhdlgen). Рассинхрон даёт `GOLDEN MISMATCH`.

Добавить golden-пару:
1. `tests/golden/<name>.lua` — исходник на Lua;
2. сгенерировать эталон: `flua tests/golden/<name>.lua > tests/golden/<name>.4th`
   (при изменении формата вывода — осознанно перегенерировать все);
3. добавить строку `s" <name>" golden-one` в `tests/golden_test.4th`.

## License

COPL (см. `package.4th`).
