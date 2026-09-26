// Moving the cursor around the tree, split out of tree_cursor.c.

#include "tree_sitter/api.h"
#include "./tree_cursor.h"
#include "./language.h"
#include "./tree.h"

TreeCursorStep ts_tree_cursor_goto_first_child_internal(TSTreeCursor *_self) {
  TreeCursor *self = (TreeCursor *)_self;
  bool visible;
  TreeCursorEntry entry;
  CursorChildIterator iterator = ts_tree_cursor_iterate_children(self);
  while (ts_tree_cursor_child_iterator_next(&iterator, &entry, &visible)) {
    if (visible) {
      array_push(&self->stack, entry);
      return TreeCursorStepVisible;
    }
    if (ts_subtree_visible_child_count(*entry.subtree) > 0) {
      array_push(&self->stack, entry);
      return TreeCursorStepHidden;
    }
  }
  return TreeCursorStepNone;
}

bool ts_tree_cursor_goto_first_child(TSTreeCursor *self) {
  for (;;) {
    switch (ts_tree_cursor_goto_first_child_internal(self)) {
      case TreeCursorStepHidden:
        continue;
      case TreeCursorStepVisible:
        return true;
      default:
        return false;
    }
  }
}

TreeCursorStep ts_tree_cursor_goto_last_child_internal(TSTreeCursor *_self) {
  TreeCursor *self = (TreeCursor *)_self;
  bool visible;
  TreeCursorEntry entry;
  CursorChildIterator iterator = ts_tree_cursor_iterate_children(self);
  if (!iterator.parent.ptr || iterator.parent.ptr->child_count == 0) return TreeCursorStepNone;

  TreeCursorEntry last_entry = {0};
  TreeCursorStep last_step = TreeCursorStepNone;
  while (ts_tree_cursor_child_iterator_next(&iterator, &entry, &visible)) {
    if (visible) {
      last_entry = entry;
      last_step = TreeCursorStepVisible;
    }
    else if (ts_subtree_visible_child_count(*entry.subtree) > 0) {
      last_entry = entry;
      last_step = TreeCursorStepHidden;
    }
  }
  if (last_entry.subtree) {
    array_push(&self->stack, last_entry);
    return last_step;
  }

  return TreeCursorStepNone;
}

bool ts_tree_cursor_goto_last_child(TSTreeCursor *self) {
  for (;;) {
    switch (ts_tree_cursor_goto_last_child_internal(self)) {
      case TreeCursorStepHidden:
        continue;
      case TreeCursorStepVisible:
        return true;
      default:
        return false;
    }
  }
}

static inline int64_t ts_tree_cursor_goto_first_child_for_byte_and_point(
  TSTreeCursor *_self,
  uint32_t goal_byte,
  TSPoint goal_point
) {
  TreeCursor *self = (TreeCursor *)_self;
  uint32_t initial_size = self->stack.size;
  uint32_t visible_child_index = 0;

  bool did_descend;
  do {
    did_descend = false;

    bool visible;
    TreeCursorEntry entry;
    CursorChildIterator iterator = ts_tree_cursor_iterate_children(self);
    while (ts_tree_cursor_child_iterator_next(&iterator, &entry, &visible)) {
      Length entry_end = length_add(entry.position, ts_subtree_size(*entry.subtree));
      bool at_goal = entry_end.bytes > goal_byte && point_gt(entry_end.extent, goal_point);
      uint32_t visible_child_count = ts_subtree_visible_child_count(*entry.subtree);
      if (at_goal) {
        if (visible) {
          array_push(&self->stack, entry);
          return visible_child_index;
        }
        if (visible_child_count > 0) {
          array_push(&self->stack, entry);
          did_descend = true;
          break;
        }
      } else if (visible) {
        visible_child_index++;
      } else {
        visible_child_index += visible_child_count;
      }
    }
  } while (did_descend);

  self->stack.size = initial_size;
  return -1;
}

int64_t ts_tree_cursor_goto_first_child_for_byte(TSTreeCursor *self, uint32_t goal_byte) {
  return ts_tree_cursor_goto_first_child_for_byte_and_point(self, goal_byte, POINT_ZERO);
}

int64_t ts_tree_cursor_goto_first_child_for_point(TSTreeCursor *self, TSPoint goal_point) {
  return ts_tree_cursor_goto_first_child_for_byte_and_point(self, 0, goal_point);
}

TreeCursorStep ts_tree_cursor_goto_sibling_internal(
  TSTreeCursor *_self,
  bool (*advance)(CursorChildIterator *, TreeCursorEntry *, bool *)
) {
  TreeCursor *self = (TreeCursor *)_self;
  uint32_t initial_size = self->stack.size;

  while (self->stack.size > 1) {
    TreeCursorEntry entry = array_pop(&self->stack);
    CursorChildIterator iterator = ts_tree_cursor_iterate_children(self);
    iterator.child_index = entry.child_index;
    iterator.structural_child_index = entry.structural_child_index;
    iterator.position = entry.position;
    iterator.descendant_index = entry.descendant_index;

    bool visible = false;
    advance(&iterator, &entry, &visible);
    if (visible && self->stack.size + 1 < initial_size) break;

    while (advance(&iterator, &entry, &visible)) {
      if (visible) {
        array_push(&self->stack, entry);
        return TreeCursorStepVisible;
      }

      if (ts_subtree_visible_child_count(*entry.subtree)) {
        array_push(&self->stack, entry);
        return TreeCursorStepHidden;
      }
    }
  }

  self->stack.size = initial_size;
  return TreeCursorStepNone;
}

TreeCursorStep ts_tree_cursor_goto_next_sibling_internal(TSTreeCursor *_self) {
  return ts_tree_cursor_goto_sibling_internal(_self, ts_tree_cursor_child_iterator_next);
}

bool ts_tree_cursor_goto_next_sibling(TSTreeCursor *self) {
  switch (ts_tree_cursor_goto_next_sibling_internal(self)) {
    case TreeCursorStepHidden:
      ts_tree_cursor_goto_first_child(self);
      return true;
    case TreeCursorStepVisible:
      return true;
    default:
      return false;
  }
}

TreeCursorStep ts_tree_cursor_goto_previous_sibling_internal(TSTreeCursor *_self) {
  // since subtracting across row loses column information, we may have to
  // restore it
  TreeCursor *self = (TreeCursor *)_self;

  // for that, save current position before traversing
  TreeCursorStep step = ts_tree_cursor_goto_sibling_internal(
      _self, ts_tree_cursor_child_iterator_previous);
  if (step == TreeCursorStepNone)
    return step;

  // if length is already valid, there's no need to recompute it
  if (!length_is_undefined(array_back(&self->stack)->position))
    return step;

  // restore position from the parent node
  const TreeCursorEntry *parent = array_get(&self->stack, self->stack.size - 2);
  Length position = parent->position;
  uint32_t child_index = array_back(&self->stack)->child_index;
  const Subtree *children = ts_subtree_children((*(parent->subtree)));

  if (child_index > 0) {
    // skip first child padding since its position should match the position of the parent
    position = length_add(position, ts_subtree_size(children[0]));
    for (uint32_t i = 1; i < child_index; ++i) {
      position = length_add(position, ts_subtree_total_size(children[i]));
    }
    position = length_add(position, ts_subtree_padding(children[child_index]));
  }

  array_back(&self->stack)->position = position;

  return step;
}

bool ts_tree_cursor_goto_previous_sibling(TSTreeCursor *self) {
  switch (ts_tree_cursor_goto_previous_sibling_internal(self)) {
    case TreeCursorStepHidden:
      ts_tree_cursor_goto_last_child(self);
      return true;
    case TreeCursorStepVisible:
      return true;
    default:
      return false;
  }
}

bool ts_tree_cursor_goto_parent(TSTreeCursor *_self) {
  TreeCursor *self = (TreeCursor *)_self;
  for (unsigned i = self->stack.size - 2; i + 1 > 0; i--) {
    if (ts_tree_cursor_is_entry_visible(self, i)) {
      self->stack.size = i + 1;
      return true;
    }
  }
  return false;
}
