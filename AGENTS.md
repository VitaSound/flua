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
# 2. проверить компиляцию в ОБОИХ режимах (locals и --stack):
flua-verify calc.lua
#    OK   [locals] calc.lua
#    OK   [stack] calc.lua

# 3. проверить ВЫПОЛНЕНИЕ — что функции дают ожидаемое:
flua calc.lua > /tmp/calc.4th
gforth -e 'include /tmp/calc.4th 2 3 calc . cr bye'   # → результат

# 4. перед коммитом — полный набор тестов
fmix test
fmix check --stage pre-commit
```

`flua-verify` (в `bin/`) возвращает 0 только если файл транспилируется
в обоих режимах и сгенерированный Forth компилируется gforth'ом
(это ловит в т.ч. вызов несуществующего слова — `Undefined word`).

## Подмножество Lua (шпаргалка)

Полные списки — в `README.md`: «Supported Lua subset» и «Чего нет».

Можно:

```lua
-- комментарий перед функцией переносится в вывод как \ ...
function add(a, b) return a + b end          -- целые, приоритеты, скобки
function s() return "hi" .. "!" end           -- строки, конкатенация ..
function twice(n) return n * 2 end
function calc(a, b) return twice(a + b) * 0x2 end   -- вызовы, 0x-hex
function neg(x) return -x end                 -- унарный минус
function m(a, b) return if a > b then a else b end end   -- сравнения
function abs(n)                                -- if/elseif/else/end
  if n < 0 then return -n
  elseif n > 0 then return n
  else return 0
  end
end
```

- тело функции — операторы `return <выражение>` и/или `if <условие> then
  return … [elseif <условие> then return …] [else return …] end`;
- сравнения: `== ~= < > <= >=` (результат — целое 0/1, для `if`:
  0 = ложь, ≠0 = истина); логических `and`/`or`/`not` по-прежнему нет;
- `elseif`/`else` — опциональны; каждая ветка должна содержать `return`;
  без `else` при ложном условии в стек ничего не кладётся — для Forth
  это не ошибка (шапка `\ ( … )` в выводе — документация, не контракт),
  но результат у вызывающего будет неопределённым — берите результат
  только если все пути ветвления кладут значение;
- параметры только для чтения, порядок объявления важен для `--stack`;
- комментарии `-- …`: в вывод попадает только серия **непосредственно
  перед строкой `function`**; внутри тела — игнорируются.

Нельзя (парсер знает только `function`, `return`, `if/elseif/else/then/end`):

- циклы `while` / `repeat` / `for`;
- переменные, `local`, присваивания (`x = 1`), `break`, `goto`;
- пустой `return`; логику (`and`, `or`, `not`, `nil`, `true`);
- таблицы `{}`, индексацию `t.k` / `t[1]`, методы `obj:m()`;
- анонимные/вложенные функции, varargs `...`, блоки `--[[ ]]`.

## Частые ловушки ИИ

1. **Пишу «настоящий» Lua** — циклы, переменные, `local`, `x = 1`,
   присваивания: получите `flua: syntax error at offset N`.
   Подмножество маленькое, держите его перед глазами.
2. **`if` пишется оператором с `return` в ветках**: `return if …` (if-выражение)
   невалидно; в однострочнике — два `end`: `function f() if c then return x end end`.
2. **Руками расставляю `roll`/`pick`/`dup`** в теле: не надо — в
   режиме `--stack` это делает компилятор (`fl-arrange`), а избыточные
   подъёмы он минимизирует (`a + b` → просто `+`).
3. **Смешиваю типы в `..`**: `param .. "x"` — в `--stack` ошибка
   (`stack model desync`): строка занимает 2 ячейки, `s+` ждёт 4,
   а параметр — целое. Конкатенируйте строки со строками.
4. **Забываю про `unused`**: в `--stack` каждый параметр должен
   использоваться в теле, иначе `parameter 'a' is unused (stack mode)`.
5. **Вызов незнакомого слова**: `flua` пропустит любое имя, но
   `flua-verify` упадёт на `Undefined word` — генерируемое слово должно
   быть либо определённым Forth (например, из gforth), либо описано
   в этом же файле.
6. **Проверяю только «что компилируется»**: компиляция ≠ результат.
   Всегда прогоняйте вызов через `gforth -e 'include … N M f . cr bye'`
   и сверьте число/строку с ожиданием (примеры в `tests/flua_test.4th`).

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

- `flua.4th` — основной конвейер: лексер, парсер, эмит, модель стека, CLI;
- `flua-tokens.4th` — токенизатор (фаза 1 AST-конвейера);
- `flua-ast.4th` — AST: парсер поверх токенов + печать дерева (`flua --ast`);
- `bin/flua` — лаунчер (`--stack`/`-s`, `--ast`/`-a`, `help`, `version`);
- `bin/flua-verify` — проверка файла в обоих режимах;
- `tests/flua_test.4th` — юнит-тесты (ttester), включая точные
  ожидания вывода и кейсы ошибок;
- `tests/ast_test.4th` — тесты вывода AST (байт-в-байт + ошибки);
- `tests/golden_test.4th` + `tests/golden/` — пары `.lua` ↔ эталоны,
  сравнение байт-в-байт + `evaluate`;
- `README.md` — полное описание подмножества и режимов.
