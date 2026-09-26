// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

pub struct AttributeExpression {
	PsiElementImpl
}

// value returns the name a bare `@[name]` attribute carries, and an empty string
// for the forms that hold no such name: key/value, literal and if.
pub fn (n &AttributeExpression) value() string {
	if stub := n.get_stub() {
		// The stub and the tree have to answer the same way, so this asks for
		// the value attribute by type rather than taking whatever child is
		// first. Only value attributes are stubbed, but the tree branch below
		// names the type, and a reader comparing the two should see that.
		for value_attribute in stub.get_children_by_type(.value_attribute) {
			return value_attribute.text()
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
