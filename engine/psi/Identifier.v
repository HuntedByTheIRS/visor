// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct Identifier {
	PsiElementImpl
}

// value returns the text the identifier is written with.
pub fn (i Identifier) value() string {
	return i.get_text()
}

// name returns the identifier's text, which is the name it stands for.
pub fn (i Identifier) name() string {
	return i.get_text()
}

// qualifier returns the expression the identifier is selected from, or none when the
// identifier is not the right side of a selector.
pub fn (i Identifier) qualifier() ?PsiElement {
	parent := i.parent()?
	if parent is SelectorExpression {
		left := parent.left()?
		if left.is_equal(i) {
			return none
		}
		return left
	}
	return none
}

// reference returns the reference that resolves the identifier.
pub fn (i Identifier) reference() PsiReference {
	file := i.containing_file()
	return new_reference(file, i, false)
}

// resolve returns the declaration the identifier names. A declaration's own name
// resolves to the declaration; every other identifier goes through its reference.
pub fn (i Identifier) resolve() ?PsiElement {
	if parent := i.parent() {
		if parent is PsiNamedElement {
			if ident := parent.identifier() {
				if ident.is_equal(i) {
					return parent as PsiElement
				}
			}
		}
	}
	return i.reference().resolve()
}
