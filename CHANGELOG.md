# Change Log

All notable changes to flua are documented here.

The format is based on [Keep a Changelog](http://keepachangelog.com/) and
this project adheres to [Semantic Versioning](http://semver.org/).

## [Unreleased]

## [0.1.1] — 2026-11-15

### Added
- **`-- @require path` / `-- @fpath dir`**: эмит `require` / `fpath path+`
  в начале генерата (пакеты без отдельного preamble).
- **`@` → `_at`** в Lua-именах host-слов (`fjson.node-str@` →
  `fjson_node_str_at`); эмит вызова сохраняет Forth-имя с `@`.
- Реестр out-arity пользовательских `function` и клеточный `ncells` для
  locals/`@forth` (строка = 2 клетки).
- Примеры: `examples/path_join.lua` (`fjson.str-concat` / `str-free`),
  `examples/disasm_gen.lua` (чистый Lua hexdigit).
- Golden: `path_join`, `disasm_gen`.

### Changed
- Документация Host Forth: ловушка `flua-verify` + относительные
  `@require`/`@fpath` (генерат во `/tmp`); антипаттерн flua-алиаса над
  одним словом (`json_has`).
- Cov badge: 93%.

### Fixed
- Table set / `@forth` args больше не угадывают arity вслепую.

## [0.1.0] — 2026-10-28

Initial tagged release: Lua-subset → Gforth transpiler with `@stack` /
`@proc` / `@forth`, tables → fenum, REPL, fcov.
