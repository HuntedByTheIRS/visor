// Reading the tree at the cursor, split out of tree_cursor.c.

#include "tree_sitter/api.h"
#include "./tree_cursor.h"
#include "./language.h"
#include "./tree.h"

void ts_tree_cursor_goto_descendant(
  TSTreeCursor *_self,
  uint32_t goal_descendant_index
) {
  TreeCursor *self = (TreeCursor *)_self;

  // Ascend to the lowest ancestor that contains the goal node.
  for (;;) {
    uint32_t i = self->stack.size - 1;
    TreeCursorEntry *entry = array_get(&self->stack, i);
    uint32_t next_descendant_index =
      entry->descendant_index +
      (ts_tree_cursor_is_entry_visible(self, i) ? 1 : 0) +
      ts_subtree_visible_descendant_count(*entry->subtree);
    if (
      (entry->descendant_index <= goal_descendant_index) &&
      (next_descendant_index > goal_descendant_index)
    ) {
      break;
    } else if (self->stack.size <= 1) {
      return;
    } else {
      self->stack.size--;
    }
  }

  // Descend to the goal node.
  bool did_descend = true;
  do {
    did_descend = false;
    bool visible;
    TreeCursorEntry entry;
    CursorChildIterator iterator = ts_tree_cursor_iterate_children(self);
    if (iterator.descendant_index > goal_descendant_index) {
      return;
    }

    while (ts_tree_cursor_child_iterator_next(&iterator, &entry, &visible)) {
      if (iterator.descendant_index > goal_descendant_index) {
        array_push(&self->stack, entry);
        if (visible && entry.descendant_index == goal_descendant_index) {
          return;
        } else {
          did_descend = true;
          break;
        }
      }
    }
  } while (did_descend);
}

uint32_t ts_tree_cursor_current_descendant_index(const TSTreeCursor *_self) {
  const TreeCursor *self = (const TreeCursor *)_self;
  TreeCursorEntry *last_entry = array_back(&self->stack);
  return last_entry->descendant_index;
}

TSNode ts_tree_cursor_current_node(const TSTreeCursor *_self) {
  const TreeCursor *self = (const TreeCursor *)_self;
  TreeCursorEntry *last_entry = array_back(&self->stack);
  bool is_extra = ts_subtree_extra(*last_entry->subtree);
  TSSymbol alias_symbol = is_extra ? 0 : self->root_alias_symbol;
  if (self->stack.size > 1 && !is_extra) {
    TreeCursorEntry *parent_entry = array_get(&self->stack, self->stack.size - 2);
    alias_symbol = ts_language_alias_at(
      self->tree->language,
      parent_entry->subtree->ptr->production_id,
      last_entry->structural_child_index
    );
  }
  return ts_node_new(
    self->tree,
    last_entry->subtree,
    last_entry->position,
    alias_symbol
  );
}

// Private - Get various facts about the current node that are needed
// when executing tree queries.
void ts_tree_cursor_current_status(
  const TSTreeCursor *_self,
  TSFieldId *field_id,
  bool *has_later_siblings,
  bool *has_later_named_siblings,
  bool *can_have_later_siblings_with_this_field,
  TSSymbol *supertypes,
  unsigned *supertype_count
) {
  const TreeCursor *self = (const TreeCursor *)_self;
  unsigned max_supertypes = *supertype_count;
  *field_id = 0;
  *supertype_count = 0;
  *has_later_siblings = false;
  *has_later_named_siblings = false;
  *can_have_later_siblings_with_this_field = false;

  // Walk up the tree, visiting the current node and its invisible ancestors,
  // because fields can refer to nodes through invisible *wrapper* nodes,
  for (unsigned i = self->stack.size - 1; i > 0; i--) {
    TreeCursorEntry *entry = array_get(&self->stack, i);
    TreeCursorEntry *parent_entry = array_get(&self->stack, i - 1);

    const TSSymbol *alias_sequence = ts_language_alias_sequence(
      self->tree->language,
      parent_entry->subtree->ptr->production_id
    );

    #define subtree_symbol(subtree, structural_child_index) \
      ((                                                    \
        !ts_subtree_extra(subtree) &&                       \
        alias_sequence &&                                   \
        alias_sequence[structural_child_index]              \
      ) ?                                                   \
        alias_sequence[structural_child_index] :            \
        ts_subtree_symbol(subtree))

    // Stop walking up when a visible ancestor is found.
    TSSymbol entry_symbol = subtree_symbol(
      *entry->subtree,
      entry->structural_child_index
    );
    TSSymbolMetadata entry_metadata = ts_language_symbol_metadata(
      self->tree->language,
      entry_symbol
    );
    if (i != self->stack.size - 1 && entry_metadata.visible) break;

    // Record any supertypes
    if (entry_metadata.supertype && *supertype_count < max_supertypes) {
      supertypes[*supertype_count] = entry_symbol;
      (*supertype_count)++;
    }

    // Determine if the current node has later siblings.
    if (!*has_later_siblings) {
      unsigned sibling_count = parent_entry->subtree->ptr->child_count;
      unsigned structural_child_index = entry->structural_child_index;
      if (!ts_subtree_extra(*entry->subtree)) structural_child_index++;
      for (unsigned j = entry->child_index + 1; j < sibling_count; j++) {
        Subtree sibling = ts_subtree_children(*parent_entry->subtree)[j];
        TSSymbolMetadata sibling_metadata = ts_language_symbol_metadata(
          self->tree->language,
          subtree_symbol(sibling, structural_child_index)
        );
        if (sibling_metadata.visible) {
          *has_later_siblings = true;
          if (*has_later_named_siblings) break;
          if (sibling_metadata.named) {
            *has_later_named_siblings = true;
            break;
          }
        } else if (ts_subtree_visible_child_count(sibling) > 0) {
          *has_later_siblings = true;
          if (*has_later_named_siblings) break;
          if (sibling.ptr->named_child_count > 0) {
            *has_later_named_siblings = true;
            break;
          }
        }
        if (!ts_subtree_extra(sibling)) structural_child_index++;
      }
    }

    #undef subtree_symbol

    if (!ts_subtree_extra(*entry->subtree)) {
      const TSFieldMapEntry *field_map, *field_map_end;
      ts_language_field_map(
        self->tree->language,
        parent_entry->subtree->ptr->production_id,
        &field_map, &field_map_end
      );

      // Look for a field name associated with the current node.
      if (!*field_id) {
        for (const TSFieldMapEntry *map = field_map; map < field_map_end; map++) {
          if (!map->inherited && map->child_index == entry->structural_child_index) {
            *field_id = map->field_id;
            break;
          }
        }
      }

      // Determine if the current node can have later siblings with the same field name.
      if (*field_id) {
        for (const TSFieldMapEntry *map = field_map; map < field_map_end; map++) {
          if (
            map->field_id == *field_id &&
            map->child_index > entry->structural_child_index
          ) {
            *can_have_later_siblings_with_this_field = true;
            break;
          }
        }
      }
    }
  }
}

uint32_t ts_tree_cursor_current_depth(const TSTreeCursor *_self) {
  const TreeCursor *self = (const TreeCursor *)_self;
  uint32_t depth = 0;
  for (unsigned i = 1; i < self->stack.size; i++) {
    if (ts_tree_cursor_is_entry_visible(self, i)) {
      depth++;
    }
  }
  return depth;
}

TSNode ts_tree_cursor_parent_node(const TSTreeCursor *_self) {
  const TreeCursor *self = (const TreeCursor *)_self;
  for (int i = (int)self->stack.size - 2; i >= 0; i--) {
    TreeCursorEntry *entry = array_get(&self->stack, i);
    bool is_visible = true;
    TSSymbol alias_symbol = 0;
    if (i > 0) {
      TreeCursorEntry *parent_entry = array_get(&self->stack, i - 1);
      alias_symbol = ts_language_alias_at(
        self->tree->language,
        parent_entry->subtree->ptr->production_id,
        entry->structural_child_index
      );
      is_visible = (alias_symbol != 0) || ts_subtree_visible(*entry->subtree);
    }
    if (is_visible) {
      return ts_node_new(
        self->tree,
        entry->subtree,
        entry->position,
        alias_symbol
      );
    }
  }
  return ts_node_new(NULL, NULL, length_zero(), 0);
}

TSFieldId ts_tree_cursor_current_field_id(const TSTreeCursor *_self) {
  const TreeCursor *self = (const TreeCursor *)_self;

  // Walk up the tree, visiting the current node and its invisible ancestors.
  for (unsigned i = self->stack.size - 1; i > 0; i--) {
    TreeCursorEntry *entry = array_get(&self->stack, i);
    TreeCursorEntry *parent_entry = array_get(&self->stack, i - 1);

    // Stop walking up when another visible node is found.
    if (
      i != self->stack.size - 1 &&
      ts_tree_cursor_is_entry_visible(self, i)
    ) break;

    if (ts_subtree_extra(*entry->subtree)) break;

    const TSFieldMapEntry *field_map, *field_map_end;
    ts_language_field_map(
      self->tree->language,
      parent_entry->subtree->ptr->production_id,
      &field_map, &field_map_end
    );
    for (const TSFieldMapEntry *map = field_map; map < field_map_end; map++) {
      if (!map->inherited && map->child_index == entry->structural_child_index) {
        return map->field_id;
      }
    }
  }
  return 0;
}

const char *ts_tree_cursor_current_field_name(const TSTreeCursor *_self) {
  TSFieldId id = ts_tree_cursor_current_field_id(_self);
  if (id) {
    const TreeCursor *self = (const TreeCursor *)_self;
    return self->tree->language->field_names[id];
  } else {
    return NULL;
  }
}

TSTreeCursor ts_tree_cursor_copy(const TSTreeCursor *_cursor) {
  const TreeCursor *cursor = (const TreeCursor *)_cursor;
  TSTreeCursor res = {NULL, NULL, {0, 0}};
  TreeCursor *copy = (TreeCursor *)&res;
  copy->tree = cursor->tree;
  copy->root_alias_symbol = cursor->root_alias_symbol;
  array_init(&copy->stack);
  array_push_all(&copy->stack, &cursor->stack);
  return res;
}

void ts_tree_cursor_reset_to(TSTreeCursor *_dst, const TSTreeCursor *_src) {
  const TreeCursor *cursor = (const TreeCursor *)_src;
  TreeCursor *copy = (TreeCursor *)_dst;
  copy->tree = cursor->tree;
  copy->root_alias_symbol = cursor->root_alias_symbol;
  array_clear(&copy->stack);
  array_push_all(&copy->stack, &cursor->stack);
}
