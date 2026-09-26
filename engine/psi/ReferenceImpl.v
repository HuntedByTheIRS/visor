// Ported from v-analyzer (MIT), commit 925d457.
// Copyright (c) 2023 V Open Source Community Association (VOSCA). See NOTICE.

module psi

import engine.utils

pub struct ReferenceImpl {
	element        ReferenceExpressionBase
	file           ?&PsiFile
	for_types      bool
	for_attributes bool
}

// new_reference creates a reference to element, resolving types when for_types is set.
pub fn new_reference(file ?&PsiFile, element ReferenceExpressionBase, for_types bool) &ReferenceImpl {
	return &ReferenceImpl{
		element:   element
		file:      file
		for_types: for_types
	}
}

// new_attribute_reference creates a reference that resolves an attribute name.
pub fn new_attribute_reference(file ?&PsiFile, element ReferenceExpressionBase) &ReferenceImpl {
	return &ReferenceImpl{
		element:        element
		file:           file
		for_attributes: true
	}
}

fn (r &ReferenceImpl) element() PsiElement {
	return r.element as PsiElement
}

// resolve returns the element the reference names, caching the result for later lookups.
pub fn (r &ReferenceImpl) resolve() ?PsiElement {
	file := r.file or { return none }

	sub := SubResolver{
		containing_file: file
		element:         r.element
		for_types:       r.for_types
		for_attributes:  r.for_attributes
	}
	mut processor := ResolveProcessor{
		containing_file: file
		ref:             r.element
		ref_name:        r.element.name()
	}

	if from_cache := resolve_cache.get(r.element()) {
		return from_cache
	}

	sub.process_resolve_variants(mut processor)
	if processor.result.len == 0 {
		return none
	}

	result := processor.result.first()
	resolve_cache.put(r.element(), result)
	return result
}

// multi_resolve returns every element the reference could name, not just the first.
pub fn (r &ReferenceImpl) multi_resolve() []PsiElement {
	file := r.file or { return [] }

	if res := r.resolve_as_import_spec() {
		return res
	}

	sub := SubResolver{
		containing_file: file
		element:         r.element
		for_types:       r.for_types
		for_attributes:  r.for_attributes
	}
	mut processor := ResolveProcessor{
		containing_file: file
		ref:             r.element
		ref_name:        r.element.name()
		collect_all:     true
	}

	sub.process_resolve_variants(mut processor)

	return processor.result
}

fn (r &ReferenceImpl) resolve_as_import_spec() ?[]PsiElement {
	if r.element is Identifier {
		parent := r.element.parent()?
		if parent !is ImportName {
			return none
		}
		spec := parent.parent()?.parent()?
		if spec is ImportSpec {
			if ident := spec.identifier() {
				if ident.is_equal(parent) {
					return [spec]
				}
			}
		}
	}
	return none
}

pub struct ResolveProcessor {
	containing_file &PsiFile
	ref             ReferenceExpressionBase
	ref_name        string
mut:
	result      []PsiElement
	collect_all bool
}

fn (mut r ResolveProcessor) execute(element PsiElement) bool {
	if element.is_equal(r.ref as PsiElement) {
		r.result << element
		return false
	}
	if element is PsiNamedElement {
		mut name := element.name()
		if name.ends_with('Attribute') {
			name = utils.pascal_case_to_snake_case(name.trim_string_right('Attribute'))
		}
		if name == r.ref_name {
			r.result << element as PsiElement
			if r.collect_all {
				return true
			}
			return false
		}
	}
	return true
}
