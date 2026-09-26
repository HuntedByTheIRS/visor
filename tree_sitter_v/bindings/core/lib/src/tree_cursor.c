#include "tree_sitter/api.h"
#include "./tree_cursor.h"
#include "./language.h"
#include "./tree.h"

typedef struct {
  Subtree parent;
  const TSTree *tree;
  Length position;
  uint32_t child_index;
  uint32_t structural_child_index;
  uint32_t descendant_index;
  const TSSymbol *alias_sequence;
} CursorChildIterator;

// CursorChildIterator

static inline bool ts_tree_cursor_is_entry_visible(const TreeCursor *self, uint32_t index) {
  TreeCursorEntry *entry = array_get(&self->stack, index);
  if (index == 0 || ts_subtree_visible(*entry->subtree)) {
    return true;
  } else if (!ts_subtree_extra(*entry->subtree)) {
    TreeCursorEntry *parent_entry = array_get(&self->stack, index - 1);
    return ts_language_alias_at(
      self->tree->language,
      parent_entry->subtree->ptr->production_id,
      entry->structural_child_index
    );
  } else {
    return false;
  }
}

static inline CursorChildIterator ts_tree_cursor_iterate_children(const TreeCursor *self) {
  TreeCursorEntry *last_entry = array_back(&self->stack);
  if (ts_subtree_child_count(*last_entry->subtree) == 0) {
    return (CursorChildIterator) {NULL_SUBTREE, self->tree, length_zero(), 0, 0, 0, NULL};
  }
  const TSSymbol *alias_sequence = ts_language_alias_sequence(
    self->tree->language,
    last_entry->subtree->ptr->production_id
  );

  uint32_t descendant_index = last_entry->descendant_index;
  if (ts_tree_cursor_is_entry_visible(self, self->stack.size - 1)) {
    descendant_index += 1;
  }

  return (CursorChildIterator) {
    .tree = self->tree,
    .parent = *last_entry->subtree,
    .position = last_entry->position,
    .child_index = 0,
    .structural_child_index = 0,
    .descendant_index = descendant_index,
    .alias_sequence = alias_sequence,
  };
}

static inline bool ts_tree_cursor_child_iterator_next(
  CursorChildIterator *self,
  TreeCursorEntry *result,
  bool *visible
) {
  if (!self->parent.ptr || self->child_index == self->parent.ptr->child_count) return false;
  const Subtree *child = &ts_subtree_children(self->parent)[self->child_index];
  *result = (TreeCursorEntry) {
    .subtree = child,
    .position = self->position,
    .child_index = self->child_index,
    .structural_child_index = self->structural_child_index,
    .descendant_index = self->descendant_index,
  };
  *visible = ts_subtree_visible(*child);
  bool extra = ts_subtree_extra(*child);
  if (!extra) {
    if (self->alias_sequence) {
      *visible |= self->alias_sequence[self->structural_child_index];
    }
    self->structural_child_index++;
  }

  self->descendant_index += ts_subtree_visible_descendant_count(*child);
  if (*visible) {
    self->descendant_index += 1;
  }

  self->position = length_add(self->position, ts_subtree_size(*child));
  self->child_index++;

  if (self->child_index < self->parent.ptr->child_count) {
    Subtree next_child = ts_subtree_children(self->parent)[self->child_index];
    self->position = length_add(self->position, ts_subtree_padding(next_child));
  }

  return true;
}

// Return a position that, when `b` is added to it, yields `a`. This
// can only be computed if `b` has zero rows. Otherwise, this function
// returns `LENGTH_UNDEFINED`, and the caller needs to recompute
// the position some other way.
static inline Length length_backtrack(Length a, Length b) {
  if (length_is_undefined(a) || b.extent.row != 0) {
    return LENGTH_UNDEFINED;
  }

  Length result;
  result.bytes = a.bytes - b.bytes;
  result.extent.row = a.extent.row;
  result.extent.column = a.extent.column - b.extent.column;
  return result;
}

static inline bool ts_tree_cursor_child_iterator_previous(
  CursorChildIterator *self,
  TreeCursorEntry *result,
  bool *visible
) {
  // this is mostly a reverse `ts_tree_cursor_child_iterator_next` taking into
  // account unsigned underflow
  if (!self->parent.ptr || (int8_t)self->child_index == -1) return false;
  const Subtree *child = &ts_subtree_children(self->parent)[self->child_index];
  *result = (TreeCursorEntry) {
    .subtree = child,
    .position = self->position,
    .child_index = self->child_index,
    .structural_child_index = self->structural_child_index,
  };
  *visible = ts_subtree_visible(*child);
  bool extra = ts_subtree_extra(*child);

  self->position = length_backtrack(self->position, ts_subtree_padding(*child));
  self->child_index--;

  if (!extra && self->alias_sequence) {
    *visible |= self->alias_sequence[self->structural_child_index];
    if (self->structural_child_index > 0) {
      self->structural_child_index--;
    }
  }

  // unsigned can underflow so compare it to child_count
  if (self->child_index < self->parent.ptr->child_count) {
    Subtree previous_child = ts_subtree_children(self->parent)[self->child_index];
    Length size = ts_subtree_size(previous_child);
    self->position = length_backtrack(self->position, size);
  }

  return true;
}

// TSTreeCursor - lifecycle

TSTreeCursor ts_tree_cursor_new(TSNode node) {
  TSTreeCursor self = {NULL, NULL, {0, 0, 0}};
  ts_tree_cursor_init((TreeCursor *)&self, node);
  return self;
}

void ts_tree_cursor_reset(TSTreeCursor *_self, TSNode node) {
  ts_tree_cursor_init((TreeCursor *)_self, node);
}

void ts_tree_cursor_init(TreeCursor *self, TSNode node) {
  self->tree = node.tree;
  self->root_alias_symbol = node.context[3];
  array_clear(&self->stack);
  array_push(&self->stack, ((TreeCursorEntry) {
    .subtree = (const Subtree *)node.id,
    .position = {
      ts_node_start_byte(node),
      ts_node_start_point(node)
    },
    .child_index = 0,
    .structural_child_index = 0,
    .descendant_index = 0,
  }));
}

void ts_tree_cursor_delete(TSTreeCursor *_self) {
  TreeCursor *self = (TreeCursor *)_self;
  array_delete(&self->stack);
}

// TSTreeCursor - walking the tree
