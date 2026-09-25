# smoke fixture

Two modules and one symbol, small enough that a failure here is about the
feature under test rather than about the fixture.

| File | What it is |
| --- | --- |
| `app.v` | calls `greeter.greeting` |
| `greeter/greeter.v` | the symbol itself, exported and doc-commented |
| `client-capabilities.json` | the capabilities the smoke run claims to support |
| `capabilities.golden.json` | the initialize response for that client |

`greeter.greeting` is the symbol to hover, complete and go to definition on: it
is exported, it has a doc comment, and `app.v` calls it. Change one of the two
JSON files without the other and `tools/lsp_smoke.vsh` fails on the comparison.
