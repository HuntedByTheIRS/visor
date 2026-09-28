// imports.v reads the modules a file imports.
//
// The walk goes over the parse rather than the lines, so a module named in a
// comment or a string is not an import. What comes back is the path as written,
// which is what a standard library directory is named after: `os` for
// `import os`, and `x.json2` for `import x.json2`.
module engine

import engine.psi

// imported_modules lists the modules a parsed file imports, in the order the
// source names them and without repeats.
pub fn imported_modules(file &psi.PsiFile) []string {
	mut modules := []string{}
	collect_imports(file.root, mut modules)
	return modules
}

// collect_imports adds one element's import, when it is one, and then looks
// through everything under it.
//
// An import declaration is not descended into: its own children carry the parts
// of the path, and reading them again would add the last segment a second time.
fn collect_imports(element psi.PsiElement, mut modules []string) {
	if element is psi.ImportDeclaration {
		if spec := element.spec() {
			name := spec.qualified_name()
			if name != '' && name !in modules {
				modules << name
			}
		}
		return
	}
	for child in element.children() {
		collect_imports(child, mut modules)
	}
}
