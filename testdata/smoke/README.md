# smoke fixture

Two modules and one symbol, small enough that a failure in a feature lane is
about the feature and not about the fixture.

`greeter.greeting` is the symbol to hover, complete and go to definition on: it
is exported, it has a doc comment, and `app.v` calls it. `client-capabilities.json`
is what the smoke run claims to support, and `capabilities.golden.json` is the
initialize response for that client. Change one without the other and
`tools/lsp_smoke.vsh` fails on the comparison.
