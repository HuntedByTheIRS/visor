// Creating, refcounting and comparing subtrees, split out of subtree.c.

#include "./subtree.h"

void ts_subtree_compress(
  MutableSubtree self,
  unsigned count,
  const TSLanguage *language,
  MutableSubtreeArray *stack
) {
  unsigned initial_stack_size = stack->size;

  MutableSubtree tree = self;
  TSSymbol symbol = tree.ptr->symbol;
  for (unsigned i = 0; i < count; i++) {
    if (tree.ptr->ref_count > 1 || tree.ptr->child_count < 2) break;

    MutableSubtree child = ts_subtree_to_mut_unsafe(ts_subtree_children(tree)[0]);
    if (
      child.data.is_inline ||
      child.ptr->child_count < 2 ||
      child.ptr->ref_count > 1 ||
      child.ptr->symbol != symbol
    ) break;

    MutableSubtree grandchild = ts_subtree_to_mut_unsafe(ts_subtree_children(child)[0]);
    if (
      grandchild.data.is_inline ||
      grandchild.ptr->child_count < 2 ||
      grandchild.ptr->ref_count > 1 ||
      grandchild.ptr->symbol != symbol
    ) break;

    ts_subtree_children(tree)[0] = ts_subtree_from_mut(grandchild);
    ts_subtree_children(child)[0] = ts_subtree_children(grandchild)[grandchild.ptr->child_count - 1];
    ts_subtree_children(grandchild)[grandchild.ptr->child_count - 1] = ts_subtree_from_mut(child);
    array_push(stack, tree);
    tree = grandchild;
  }

  while (stack->size > initial_stack_size) {
    tree = array_pop(stack);
    MutableSubtree child = ts_subtree_to_mut_unsafe(ts_subtree_children(tree)[0]);
    MutableSubtree grandchild = ts_subtree_to_mut_unsafe(ts_subtree_children(child)[child.ptr->child_count - 1]);
    ts_subtree_summarize_children(grandchild, language);
    ts_subtree_summarize_children(child, language);
    ts_subtree_summarize_children(tree, language);
  }
}

// Assign all of the node's properties that depend on its children.
void ts_subtree_summarize_children(
  MutableSubtree self,
  const TSLanguage *language
) {
  ts_assert(!self.data.is_inline);

  self.ptr->named_child_count = 0;
  self.ptr->visible_child_count = 0;
  self.ptr->error_cost = 0;
  self.ptr->repeat_depth = 0;
  self.ptr->visible_descendant_count = 0;
  self.ptr->has_external_tokens = false;
  self.ptr->depends_on_column = false;
  self.ptr->has_external_scanner_state_change = false;
  self.ptr->dynamic_precedence = 0;

  uint32_t structural_index = 0;
  const TSSymbol *alias_sequence = ts_language_alias_sequence(language, self.ptr->production_id);
  uint32_t lookahead_end_byte = 0;

  const Subtree *children = ts_subtree_children(self);
  for (uint32_t i = 0; i < self.ptr->child_count; i++) {
    Subtree child = children[i];

    if (
      self.ptr->size.extent.row == 0 &&
      ts_subtree_depends_on_column(child)
    ) {
      self.ptr->depends_on_column = true;
    }

    if (ts_subtree_has_external_scanner_state_change(child)) {
      self.ptr->has_external_scanner_state_change = true;
    }

    if (i == 0) {
      self.ptr->padding = ts_subtree_padding(child);
      self.ptr->size = ts_subtree_size(child);
    } else {
      self.ptr->size = length_add(self.ptr->size, ts_subtree_total_size(child));
    }

    uint32_t child_lookahead_end_byte =
      self.ptr->padding.bytes +
      self.ptr->size.bytes +
      ts_subtree_lookahead_bytes(child);
    if (child_lookahead_end_byte > lookahead_end_byte) {
      lookahead_end_byte = child_lookahead_end_byte;
    }

    if (ts_subtree_symbol(child) != ts_builtin_sym_error_repeat) {
      self.ptr->error_cost += ts_subtree_error_cost(child);
    }

    uint32_t grandchild_count = ts_subtree_child_count(child);
    if (
      self.ptr->symbol == ts_builtin_sym_error ||
      self.ptr->symbol == ts_builtin_sym_error_repeat
    ) {
      if (!ts_subtree_extra(child) && !(ts_subtree_is_error(child) && grandchild_count == 0)) {
        if (ts_subtree_visible(child)) {
          self.ptr->error_cost += ERROR_COST_PER_SKIPPED_TREE;
        } else if (grandchild_count > 0) {
          self.ptr->error_cost += ERROR_COST_PER_SKIPPED_TREE * child.ptr->visible_child_count;
        }
      }
    }

    self.ptr->dynamic_precedence += ts_subtree_dynamic_precedence(child);
    self.ptr->visible_descendant_count += ts_subtree_visible_descendant_count(child);

    if (
      !ts_subtree_extra(child) &&
      ts_subtree_symbol(child) != 0 &&
      alias_sequence &&
      alias_sequence[structural_index] != 0
    ) {
      self.ptr->visible_descendant_count++;
      self.ptr->visible_child_count++;
      if (ts_language_symbol_metadata(language, alias_sequence[structural_index]).named) {
        self.ptr->named_child_count++;
      }
    } else if (ts_subtree_visible(child)) {
      self.ptr->visible_descendant_count++;
      self.ptr->visible_child_count++;
      if (ts_subtree_named(child)) self.ptr->named_child_count++;
    } else if (grandchild_count > 0) {
      self.ptr->visible_child_count += child.ptr->visible_child_count;
      self.ptr->named_child_count += child.ptr->named_child_count;
    }

    if (ts_subtree_has_external_tokens(child)) self.ptr->has_external_tokens = true;

    if (ts_subtree_is_error(child)) {
      self.ptr->fragile_left = self.ptr->fragile_right = true;
      self.ptr->parse_state = TS_TREE_STATE_NONE;
    }

    if (!ts_subtree_extra(child)) structural_index++;
  }

  self.ptr->lookahead_bytes = lookahead_end_byte - self.ptr->size.bytes - self.ptr->padding.bytes;

  if (
    self.ptr->symbol == ts_builtin_sym_error ||
    self.ptr->symbol == ts_builtin_sym_error_repeat
  ) {
    self.ptr->error_cost +=
      ERROR_COST_PER_RECOVERY +
      ERROR_COST_PER_SKIPPED_CHAR * self.ptr->size.bytes +
      ERROR_COST_PER_SKIPPED_LINE * self.ptr->size.extent.row;
  }

  if (self.ptr->child_count > 0) {
    Subtree first_child = children[0];
    Subtree last_child = children[self.ptr->child_count - 1];

    self.ptr->first_leaf.symbol = ts_subtree_leaf_symbol(first_child);
    self.ptr->first_leaf.parse_state = ts_subtree_leaf_parse_state(first_child);

    if (ts_subtree_fragile_left(first_child)) self.ptr->fragile_left = true;
    if (ts_subtree_fragile_right(last_child)) self.ptr->fragile_right = true;

    if (
      self.ptr->child_count >= 2 &&
      !self.ptr->visible &&
      !self.ptr->named &&
      ts_subtree_symbol(first_child) == self.ptr->symbol
    ) {
      if (ts_subtree_repeat_depth(first_child) > ts_subtree_repeat_depth(last_child)) {
        self.ptr->repeat_depth = ts_subtree_repeat_depth(first_child) + 1;
      } else {
        self.ptr->repeat_depth = ts_subtree_repeat_depth(last_child) + 1;
      }
    }
  }
}

// Create a new parent node with the given children.
//
// This takes ownership of the children array.
MutableSubtree ts_subtree_new_node(
  TSSymbol symbol,
  SubtreeArray *children,
  unsigned production_id,
  const TSLanguage *language
) {
  TSSymbolMetadata metadata = ts_language_symbol_metadata(language, symbol);
  bool fragile = symbol == ts_builtin_sym_error || symbol == ts_builtin_sym_error_repeat;

  // Allocate the node's data at the end of the array of children.
  size_t new_byte_size = ts_subtree_alloc_size(children->size);
  if (children->capacity * sizeof(Subtree) < new_byte_size) {
    children->contents = ts_realloc(children->contents, new_byte_size);
    children->capacity = (uint32_t)(new_byte_size / sizeof(Subtree));
  }
  SubtreeHeapData *data = (SubtreeHeapData *)&children->contents[children->size];

  *data = (SubtreeHeapData) {
    .ref_count = 1,
    .symbol = symbol,
    .child_count = children->size,
    .visible = metadata.visible,
    .named = metadata.named,
    .has_changes = false,
    .has_external_scanner_state_change = false,
    .fragile_left = fragile,
    .fragile_right = fragile,
    .is_keyword = false,
    {{
      .visible_descendant_count = 0,
      .production_id = production_id,
      .first_leaf = {.symbol = 0, .parse_state = 0},
    }}
  };
  MutableSubtree result = {.ptr = data};
  ts_subtree_summarize_children(result, language);
  return result;
}

// Create a new error node containing the given children.
//
// This node is treated as 'extra'. Its children are prevented from having
// having any effect on the parse state.
Subtree ts_subtree_new_error_node(
  SubtreeArray *children,
  bool extra,
  const TSLanguage *language
) {
  MutableSubtree result = ts_subtree_new_node(
    ts_builtin_sym_error, children, 0, language
  );
  result.ptr->extra = extra;
  return ts_subtree_from_mut(result);
}

// Create a new 'missing leaf' node.
//
// This node is treated as 'extra'. Its children are prevented from having
// having any effect on the parse state.
Subtree ts_subtree_new_missing_leaf(
  SubtreePool *pool,
  TSSymbol symbol,
  Length padding,
  uint32_t lookahead_bytes,
  const TSLanguage *language
) {
  Subtree result = ts_subtree_new_leaf(
    pool, symbol, padding, length_zero(), lookahead_bytes,
    0, false, false, false, language
  );
  if (result.data.is_inline) {
    result.data.is_missing = true;
  } else {
    ((SubtreeHeapData *)result.ptr)->is_missing = true;
  }
  return result;
}

void ts_subtree_retain(Subtree self) {
  if (self.data.is_inline) return;
  ts_assert(self.ptr->ref_count > 0);
  atomic_inc((volatile uint32_t *)&self.ptr->ref_count);
  ts_assert(self.ptr->ref_count != 0);
}

void ts_subtree_release(SubtreePool *pool, Subtree self) {
  if (self.data.is_inline) return;
  array_clear(&pool->tree_stack);

  ts_assert(self.ptr->ref_count > 0);
  if (atomic_dec((volatile uint32_t *)&self.ptr->ref_count) == 0) {
    array_push(&pool->tree_stack, ts_subtree_to_mut_unsafe(self));
  }

  while (pool->tree_stack.size > 0) {
    MutableSubtree tree = array_pop(&pool->tree_stack);
    if (tree.ptr->child_count > 0) {
      Subtree *children = ts_subtree_children(tree);
      for (uint32_t i = 0; i < tree.ptr->child_count; i++) {
        Subtree child = children[i];
        if (child.data.is_inline) continue;
        ts_assert(child.ptr->ref_count > 0);
        if (atomic_dec((volatile uint32_t *)&child.ptr->ref_count) == 0) {
          array_push(&pool->tree_stack, ts_subtree_to_mut_unsafe(child));
        }
      }
      ts_free(children);
    } else {
      if (tree.ptr->has_external_tokens) {
        ts_external_scanner_state_delete(&tree.ptr->external_scanner_state);
      }
      ts_subtree_pool_free(pool, tree.ptr);
    }
  }
}

int ts_subtree_compare(Subtree left, Subtree right, SubtreePool *pool) {
  array_push(&pool->tree_stack, ts_subtree_to_mut_unsafe(left));
  array_push(&pool->tree_stack, ts_subtree_to_mut_unsafe(right));

  while (pool->tree_stack.size > 0) {
    right = ts_subtree_from_mut(array_pop(&pool->tree_stack));
    left = ts_subtree_from_mut(array_pop(&pool->tree_stack));

    int result = 0;
    if (ts_subtree_symbol(left) < ts_subtree_symbol(right)) result = -1;
    else if (ts_subtree_symbol(right) < ts_subtree_symbol(left)) result = 1;
    else if (ts_subtree_child_count(left) < ts_subtree_child_count(right)) result = -1;
    else if (ts_subtree_child_count(right) < ts_subtree_child_count(left)) result = 1;
    if (result != 0) {
      array_clear(&pool->tree_stack);
      return result;
    }

    for (uint32_t i = ts_subtree_child_count(left); i > 0; i--) {
      Subtree left_child = ts_subtree_children(left)[i - 1];
      Subtree right_child = ts_subtree_children(right)[i - 1];
      array_push(&pool->tree_stack, ts_subtree_to_mut_unsafe(left_child));
      array_push(&pool->tree_stack, ts_subtree_to_mut_unsafe(right_child));
    }
  }

  return 0;
}

static inline void ts_subtree_set_has_changes(MutableSubtree *self) {
  if (self->data.is_inline) {
    self->data.has_changes = true;
  } else {
    self->ptr->has_changes = true;
  }
}
