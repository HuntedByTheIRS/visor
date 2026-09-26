// Editing subtrees after a reparse, split out of subtree.c.

#include "./subtree.h"

Subtree ts_subtree_edit(Subtree self, const TSInputEdit *input_edit, SubtreePool *pool) {
  typedef struct {
    Subtree *tree;
    Edit edit;
  } EditEntry;

  Array(EditEntry) stack = array_new();
  array_push(&stack, ((EditEntry) {
    .tree = &self,
    .edit = (Edit) {
      .start = {input_edit->start_byte, input_edit->start_point},
      .old_end = {input_edit->old_end_byte, input_edit->old_end_point},
      .new_end = {input_edit->new_end_byte, input_edit->new_end_point},
    },
  }));

  while (stack.size) {
    EditEntry entry = array_pop(&stack);
    Edit edit = entry.edit;
    bool is_noop = edit.old_end.bytes == edit.start.bytes && edit.new_end.bytes == edit.start.bytes;
    bool is_pure_insertion = edit.old_end.bytes == edit.start.bytes;
    bool parent_depends_on_column = ts_subtree_depends_on_column(*entry.tree);
    bool column_shifted = edit.new_end.extent.column != edit.old_end.extent.column;

    Length size = ts_subtree_size(*entry.tree);
    Length padding = ts_subtree_padding(*entry.tree);
    Length total_size = length_add(padding, size);
    uint32_t lookahead_bytes = ts_subtree_lookahead_bytes(*entry.tree);
    uint32_t end_byte = total_size.bytes + lookahead_bytes;
    if (edit.start.bytes > end_byte || (is_noop && edit.start.bytes == end_byte)) continue;

    // If the edit is entirely within the space before this subtree, then shift this
    // subtree over according to the edit without changing its size.
    if (edit.old_end.bytes <= padding.bytes) {
      padding = length_add(edit.new_end, length_sub(padding, edit.old_end));
    }

    // If the edit starts in the space before this subtree and extends into this subtree,
    // shrink the subtree's content to compensate for the change in the space before it.
    else if (edit.start.bytes < padding.bytes) {
      size = length_saturating_sub(size, length_sub(edit.old_end, padding));
      padding = edit.new_end;
    }

    // If the edit is within this subtree, resize the subtree to reflect the edit.
    else if (
      edit.start.bytes < total_size.bytes ||
      (edit.start.bytes == total_size.bytes && is_pure_insertion)
    ) {
      size = length_add(
        length_sub(edit.new_end, padding),
        length_saturating_sub(total_size, edit.old_end)
      );
    }

    MutableSubtree result = ts_subtree_make_mut(pool, *entry.tree);

    if (result.data.is_inline) {
      if (ts_subtree_can_inline(padding, size, lookahead_bytes)) {
        result.data.padding_bytes = padding.bytes;
        result.data.padding_rows = padding.extent.row;
        result.data.padding_columns = padding.extent.column;
        result.data.size_bytes = size.bytes;
      } else {
        SubtreeHeapData *data = ts_subtree_pool_allocate(pool);
        data->ref_count = 1;
        data->padding = padding;
        data->size = size;
        data->lookahead_bytes = lookahead_bytes;
        data->error_cost = 0;
        data->child_count = 0;
        data->symbol = result.data.symbol;
        data->parse_state = result.data.parse_state;
        data->visible = result.data.visible;
        data->named = result.data.named;
        data->extra = result.data.extra;
        data->fragile_left = false;
        data->fragile_right = false;
        data->has_changes = false;
        data->has_external_tokens = false;
        data->depends_on_column = false;
        data->is_missing = result.data.is_missing;
        data->is_keyword = result.data.is_keyword;
        result.ptr = data;
      }
    } else {
      result.ptr->padding = padding;
      result.ptr->size = size;
    }

    ts_subtree_set_has_changes(&result);
    *entry.tree = ts_subtree_from_mut(result);

    Length child_left, child_right = length_zero();
    for (uint32_t i = 0, n = ts_subtree_child_count(*entry.tree); i < n; i++) {
      Subtree *child = &ts_subtree_children(*entry.tree)[i];
      Length child_size = ts_subtree_total_size(*child);
      child_left = child_right;
      child_right = length_add(child_left, child_size);

      // If this child ends before the edit, it is not affected.
      if (child_right.bytes + ts_subtree_lookahead_bytes(*child) < edit.start.bytes) continue;

      // Keep editing child nodes until a node is reached that starts after the edit.
      // Also, if this node's validity depends on its column position, then continue
      // invalidating child nodes until reaching a line break.
      if ((
        (child_left.bytes > edit.old_end.bytes) ||
        (child_left.bytes == edit.old_end.bytes && child_size.bytes > 0 && i > 0)
      ) && (
        !parent_depends_on_column ||
        child_left.extent.row > padding.extent.row
      ) && (
        !ts_subtree_depends_on_column(*child) ||
        !column_shifted ||
        child_left.extent.row > edit.old_end.extent.row
      )) {
        break;
      }

      // Transform edit into the child's coordinate space.
      Edit child_edit = {
        .start = length_saturating_sub(edit.start, child_left),
        .old_end = length_saturating_sub(edit.old_end, child_left),
        .new_end = length_saturating_sub(edit.new_end, child_left),
      };

      // Interpret all inserted text as applying to the *first* child that touches the edit.
      // Subsequent children are only never have any text inserted into them; they are only
      // shrunk to compensate for the edit.
      if (
        child_right.bytes > edit.start.bytes ||
        (child_right.bytes == edit.start.bytes && is_pure_insertion)
      ) {
        edit.new_end = edit.start;
      }

      // Children that occur before the edit are not reshaped by the edit.
      else {
        child_edit.old_end = child_edit.start;
        child_edit.new_end = child_edit.start;
      }

      // Queue processing of this child's subtree.
      array_push(&stack, ((EditEntry) {
        .tree = child,
        .edit = child_edit,
      }));
    }
  }

  array_delete(&stack);
  return self;
}

Subtree ts_subtree_last_external_token(Subtree tree) {
  if (!ts_subtree_has_external_tokens(tree)) return NULL_SUBTREE;
  while (tree.ptr->child_count > 0) {
    for (uint32_t i = tree.ptr->child_count - 1; i + 1 > 0; i--) {
      Subtree child = ts_subtree_children(tree)[i];
      if (ts_subtree_has_external_tokens(child)) {
        tree = child;
        break;
      }
    }
  }
  return tree;
}
