// Reduction and the potential-reduction loop, split out of parser.c.

#include "./parser.h"

static StackVersion ts_parser__reduce(
  TSParser *self,
  StackVersion version,
  TSSymbol symbol,
  uint32_t count,
  int dynamic_precedence,
  uint16_t production_id,
  bool is_fragile,
  bool end_of_non_terminal_extra
) {
  uint32_t initial_version_count = ts_stack_version_count(self->stack);

  // Pop the given number of nodes from the given version of the parse stack.
  // If stack versions have previously merged, then there may be more than one
  // path back through the stack. For each path, create a new parent node to
  // contain the popped children, and push it onto the stack in place of the
  // children.
  StackSliceArray pop = ts_stack_pop_count(self->stack, version, count);
  uint32_t removed_version_count = 0;
  uint32_t halted_version_count = ts_stack_halted_version_count(self->stack);
  for (uint32_t i = 0; i < pop.size; i++) {
    StackSlice slice = *array_get(&pop, i);
    StackVersion slice_version = slice.version - removed_version_count;

    // This is where new versions are added to the parse stack. The versions
    // will all be sorted and truncated at the end of the outer parsing loop.
    // Allow the maximum version count to be temporarily exceeded, but only
    // by a limited threshold.
    if (slice_version > MAX_VERSION_COUNT + MAX_VERSION_COUNT_OVERFLOW + halted_version_count) {
      ts_stack_remove_version(self->stack, slice_version);
      ts_subtree_array_delete(&self->tree_pool, &slice.subtrees);
      removed_version_count++;
      while (i + 1 < pop.size) {
        LOG("aborting reduce with too many versions")
        StackSlice next_slice = *array_get(&pop, i + 1);
        if (next_slice.version != slice.version) break;
        ts_subtree_array_delete(&self->tree_pool, &next_slice.subtrees);
        i++;
      }
      continue;
    }

    // Extra tokens on top of the stack should not be included in this new parent
    // node. They will be re-pushed onto the stack after the parent node is
    // created and pushed.
    SubtreeArray children = slice.subtrees;
    ts_subtree_array_remove_trailing_extras(&children, &self->trailing_extras);

    MutableSubtree parent = ts_subtree_new_node(
      symbol, &children, production_id, self->language
    );

    // This pop operation may have caused multiple stack versions to collapse
    // into one, because they all diverged from a common state. In that case,
    // choose one of the arrays of trees to be the parent node's children, and
    // delete the rest of the tree arrays.
    while (i + 1 < pop.size) {
      StackSlice next_slice = *array_get(&pop, i + 1);
      if (next_slice.version != slice.version) break;
      i++;

      SubtreeArray next_slice_children = next_slice.subtrees;
      ts_subtree_array_remove_trailing_extras(&next_slice_children, &self->trailing_extras2);

      if (ts_parser__select_children(
        self,
        ts_subtree_from_mut(parent),
        &next_slice_children
      )) {
        ts_subtree_array_clear(&self->tree_pool, &self->trailing_extras);
        ts_subtree_release(&self->tree_pool, ts_subtree_from_mut(parent));
        array_swap(&self->trailing_extras, &self->trailing_extras2);
        parent = ts_subtree_new_node(
          symbol, &next_slice_children, production_id, self->language
        );
      } else {
        array_clear(&self->trailing_extras2);
        ts_subtree_array_delete(&self->tree_pool, &next_slice.subtrees);
      }
    }

    TSStateId state = ts_stack_state(self->stack, slice_version);
    TSStateId next_state = ts_language_next_state(self->language, state, symbol);
    if (end_of_non_terminal_extra && next_state == state) {
      parent.ptr->extra = true;
    }
    if (is_fragile || pop.size > 1 || initial_version_count > 1) {
      parent.ptr->fragile_left = true;
      parent.ptr->fragile_right = true;
      parent.ptr->parse_state = TS_TREE_STATE_NONE;
    } else {
      parent.ptr->parse_state = state;
    }
    parent.ptr->dynamic_precedence += dynamic_precedence;

    // Push the parent node onto the stack, along with any extra tokens that
    // were previously on top of the stack.
    ts_stack_push(self->stack, slice_version, ts_subtree_from_mut(parent), false, next_state);
    for (uint32_t j = 0; j < self->trailing_extras.size; j++) {
      ts_stack_push(self->stack, slice_version, *array_get(&self->trailing_extras, j), false, next_state);
    }

    for (StackVersion j = 0; j < slice_version; j++) {
      if (j == version) continue;
      if (ts_stack_merge(self->stack, j, slice_version)) {
        removed_version_count++;
        break;
      }
    }
  }

  // Return the first new stack version that was created.
  return ts_stack_version_count(self->stack) > initial_version_count
    ? initial_version_count
    : STACK_VERSION_NONE;
}

static void ts_parser__accept(
  TSParser *self,
  StackVersion version,
  Subtree lookahead
) {
  ts_assert(ts_subtree_is_eof(lookahead));
  ts_stack_push(self->stack, version, lookahead, false, 1);

  StackSliceArray pop = ts_stack_pop_all(self->stack, version);
  for (uint32_t i = 0; i < pop.size; i++) {
    SubtreeArray trees = array_get(&pop, i)->subtrees;

    Subtree root = NULL_SUBTREE;
    for (uint32_t j = trees.size - 1; j + 1 > 0; j--) {
      Subtree tree = *array_get(&trees, j);
      if (!ts_subtree_extra(tree)) {
        ts_assert(!tree.data.is_inline);
        uint32_t child_count = ts_subtree_child_count(tree);
        const Subtree *children = ts_subtree_children(tree);
        for (uint32_t k = 0; k < child_count; k++) {
          ts_subtree_retain(children[k]);
        }
        array_splice(&trees, j, 1, child_count, children);
        root = ts_subtree_from_mut(ts_subtree_new_node(
          ts_subtree_symbol(tree),
          &trees,
          tree.ptr->production_id,
          self->language
        ));
        ts_subtree_release(&self->tree_pool, tree);
        break;
      }
    }

    ts_assert(root.ptr);
    self->accept_count++;

    if (self->finished_tree.ptr) {
      if (ts_parser__select_tree(self, self->finished_tree, root)) {
        ts_subtree_release(&self->tree_pool, self->finished_tree);
        self->finished_tree = root;
      } else {
        ts_subtree_release(&self->tree_pool, root);
      }
    } else {
      self->finished_tree = root;
    }
  }

  ts_stack_remove_version(self->stack, array_get(&pop, 0)->version);
  ts_stack_halt(self->stack, version);
}

static bool ts_parser__do_all_potential_reductions(
  TSParser *self,
  StackVersion starting_version,
  TSSymbol lookahead_symbol
) {
  uint32_t initial_version_count = ts_stack_version_count(self->stack);

  bool can_shift_lookahead_symbol = false;
  StackVersion version = starting_version;
  for (unsigned i = 0; true; i++) {
    uint32_t version_count = ts_stack_version_count(self->stack);
    if (version >= version_count) break;

    bool merged = false;
    for (StackVersion j = initial_version_count; j < version; j++) {
      if (ts_stack_merge(self->stack, j, version)) {
        merged = true;
        break;
      }
    }
    if (merged) continue;

    TSStateId state = ts_stack_state(self->stack, version);
    bool has_shift_action = false;
    array_clear(&self->reduce_actions);

    TSSymbol first_symbol, end_symbol;
    if (lookahead_symbol != 0) {
      first_symbol = lookahead_symbol;
      end_symbol = lookahead_symbol + 1;
    } else {
      first_symbol = 1;
      end_symbol = self->language->token_count;
    }

    for (TSSymbol symbol = first_symbol; symbol < end_symbol; symbol++) {
      TableEntry entry;
      ts_language_table_entry(self->language, state, symbol, &entry);
      for (uint32_t j = 0; j < entry.action_count; j++) {
        TSParseAction action = entry.actions[j];
        switch (action.type) {
          case TSParseActionTypeShift:
          case TSParseActionTypeRecover:
            if (!action.shift.extra && !action.shift.repetition) has_shift_action = true;
            break;
          case TSParseActionTypeReduce:
            if (action.reduce.child_count > 0)
              ts_reduce_action_set_add(&self->reduce_actions, (ReduceAction) {
                .symbol = action.reduce.symbol,
                .count = action.reduce.child_count,
                .dynamic_precedence = action.reduce.dynamic_precedence,
                .production_id = action.reduce.production_id,
              });
            break;
          default:
            break;
        }
      }
    }

    StackVersion reduction_version = STACK_VERSION_NONE;
    for (uint32_t j = 0; j < self->reduce_actions.size; j++) {
      ReduceAction action = *array_get(&self->reduce_actions, j);

      reduction_version = ts_parser__reduce(
        self, version, action.symbol, action.count,
        action.dynamic_precedence, action.production_id,
        true, false
      );
    }

    if (has_shift_action) {
      can_shift_lookahead_symbol = true;
    } else if (reduction_version != STACK_VERSION_NONE && i < MAX_VERSION_COUNT) {
      ts_stack_renumber_version(self->stack, reduction_version, version);
      continue;
    } else if (lookahead_symbol != 0) {
      ts_stack_remove_version(self->stack, version);
    }

    if (version == starting_version) {
      version = version_count;
    } else {
      version++;
    }
  }

  return can_shift_lookahead_symbol;
}

static bool ts_parser__recover_to_state(
  TSParser *self,
  StackVersion version,
  unsigned depth,
  TSStateId goal_state
) {
  StackSliceArray pop = ts_stack_pop_count(self->stack, version, depth);
  StackVersion previous_version = STACK_VERSION_NONE;

  for (unsigned i = 0; i < pop.size; i++) {
    StackSlice slice = *array_get(&pop, i);

    if (slice.version == previous_version) {
      ts_subtree_array_delete(&self->tree_pool, &slice.subtrees);
      array_erase(&pop, i--);
      continue;
    }

    if (ts_stack_state(self->stack, slice.version) != goal_state) {
      ts_stack_halt(self->stack, slice.version);
      ts_subtree_array_delete(&self->tree_pool, &slice.subtrees);
      array_erase(&pop, i--);
      continue;
    }

    SubtreeArray error_trees = ts_stack_pop_error(self->stack, slice.version);
    if (error_trees.size > 0) {
      ts_assert(error_trees.size == 1);
      Subtree error_tree = *array_get(&error_trees, 0);
      uint32_t error_child_count = ts_subtree_child_count(error_tree);
      if (error_child_count > 0) {
        array_splice(&slice.subtrees, 0, 0, error_child_count, ts_subtree_children(error_tree));
        for (unsigned j = 0; j < error_child_count; j++) {
          ts_subtree_retain(*array_get(&slice.subtrees, j));
        }
      }
      ts_subtree_array_delete(&self->tree_pool, &error_trees);
    }

    ts_subtree_array_remove_trailing_extras(&slice.subtrees, &self->trailing_extras);

    if (slice.subtrees.size > 0) {
      Subtree error = ts_subtree_new_error_node(&slice.subtrees, true, self->language);
      ts_stack_push(self->stack, slice.version, error, false, goal_state);
    } else {
      array_delete(&slice.subtrees);
    }

    for (unsigned j = 0; j < self->trailing_extras.size; j++) {
      Subtree tree = *array_get(&self->trailing_extras, j);
      ts_stack_push(self->stack, slice.version, tree, false, goal_state);
    }

    previous_version = slice.version;
  }

  return previous_version != STACK_VERSION_NONE;
}
