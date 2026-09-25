# psi

The Program Structure Interface: typed elements over the syntax tree, one struct
per V construct, so a feature asks a `StructDeclaration` for its fields rather
than matching tree-sitter node kinds.

| Where | What lives there |
| --- | --- |
| `PsiFile.v` | the root of a file's tree |
| `PsiElement.v`, `walk.v` | the element interface and the traversal over it |
| `search/` | references, implementations, supers |
| `types/` | the type layer the inferer works in |

`docs/architecture.md` has the module map.
