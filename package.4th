\ Follows theforth.net publishing guidelines:
\   https://theforth.net/guidelines
\ Order: mandatory meta keys first, then tool requirements, then dependencies.
forth-package
    key-value name flua
    key-value version 0.1.0
    key-value description Lua-subset to Forth source transpiler (integers, string literals, word definitions)
    key-value license COPL
    key-value main flua.4th
    key-value fmix ~> 0.7
    key-value flint ~> 0.2
    key-value fcov ~> 0.3
    key-list tags transpiler
    key-list tags lua
    key-list tags forth
    key-list tags gforth
    key-list flint-exclude tests/golden/
    key-list dependencies fenum git https://github.com/VitaSound/fenum tag 0.1.3
    key-list dependencies ttester git https://github.com/VitaSound/ttester tag 1.2.1
end-forth-package