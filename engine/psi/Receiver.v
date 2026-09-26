// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.psi.types

pub struct Receiver {
	PsiElementImpl
}

// is_public always returns true because a receiver never carries a visibility modifier of its own.
pub fn (r &Receiver) is_public() bool {
	return true
}

fn (r &Receiver) identifier_text_range() TextRange {
	if stub := r.get_stub() {
		return stub.identifier_text_range
	}

	identifier := r.identifier() or { return TextRange{} }
	return identifier.text_range()
}

fn (r &Receiver) identifier() ?PsiElement {
	return r.find_child_by_type(.identifier)
}

// name returns the receiver's name, taken from the stub when one is attached.
pub fn (r &Receiver) name() string {
	if stub := r.get_stub() {
		return stub.name
	}

	identifier := r.identifier() or { return '' }
	return identifier.get_text()
}

// type_element returns the node holding the receiver's type, or none when it has no explicit type.
pub fn (r &Receiver) type_element() ?PsiElement {
	if stub := r.get_stub() {
		if receiver_stub := stub.get_child_by_type(.plain_type) {
			// The local cannot be called `psi`: V 0.5.2 rejects a name that
			// repeats a module name in the project.
			element := receiver_stub.get_psi()?
			if element is PlainType {
				return element
			}
		}
		return none
	}

	return r.find_child_by_type(.plain_type)
}

// get_type returns the receiver's type as resolved by type inference.
pub fn (r &Receiver) get_type() types.Type {
	return infer_type(PsiElement(r))
}

// mutability_modifiers returns the receiver's mutability modifiers, or none when it has none.
pub fn (r &Receiver) mutability_modifiers() ?&MutabilityModifiers {
	modifiers := r.find_child_by_type_or_stub(.mutability_modifiers)?
	if modifiers is MutabilityModifiers {
		return modifiers
	}
	return none
}

// is_mutable reports whether the receiver is declared mutable.
pub fn (r &Receiver) is_mutable() bool {
	mods := r.mutability_modifiers() or { return false }
	return mods.is_mutable()
}

fn (_ &Receiver) stub() {}
