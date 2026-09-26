// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct AttributeExpression {
	PsiElementImpl
}

// value returns the text of the attribute expression, which for a bare attribute
// is the name it is indexed under.
pub fn (n &AttributeExpression) value() string {
	if stub := n.get_stub() {
		if first_child := stub.first_child() {
			return first_child.text()
		}
		return ''
	}

	if first_child := n.first_child() {
		if first_child is ValueAttribute {
			return first_child.value()
		}
	}

	return ''
}

fn (_ &AttributeExpression) stub() {}
