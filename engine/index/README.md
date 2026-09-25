# index

The project index: what every file under a root declares, kept without the
function bodies so a whole module root fits in memory.

| Entry point | What it does |
| --- | --- |
| `IndexingRoot.index` | walks the root and indexes each file |
| `IndexingRoot.index_file` | indexes one file |
| `IndexingRoot.load_index`, `save_index` | reads and writes the on-disk form |
| `FileIndex`, `PerFileIndex` | what one file declares |
| `StubTree` | the declaration-only view of a file |

`IndexSerializer` and `IndexDeserializer` own the on-disk format, which
`binary.v` implements. `docs/architecture.md` has the module map.
