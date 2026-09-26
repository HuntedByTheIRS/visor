// Error recovery, split out of parser.c.

#include "./parser.h"

static void ts_parser__recover(
  TSParser *self,
  StackVersion version,
  Subtree lookahead
) {
  bool did_recover = false;
  unsigned previous_version_count = ts_stack_version_count(self->stack);
  Length position = ts_stack_position(self->stack, version);
  StackSummary *summary = ts_stack_get_summary(self->stack, version);
  unsigned node_count_since_error = ts_stack_node_count_since_error(self->stack, version);
  unsigned current_error_cost = ts_stack_error_cost(self->stack, version);

  // When the parser is in the error state, there are two strategies for recovering with a
  // given lookahead token:
  // 1. Find a previous state on the stack in which that lookahead token would be valid. Then,
  //    create a new stack version that is in that state again. This entails popping all of the
  //    subtrees that have been pushed onto the stack since that previous state, and wrapping
  //    them in an ERROR node.
  // 2. Wrap the lookahead token in an ERROR node, push that ERROR node onto the stack, and
  //    move on to the next lookahead token, remaining in the error state.
  //
  // First, try the strategy 1. Upon entering the error state, the parser recorded a summary
  // of the previous parse states and their depths. Look at each state in the summary, to see
  // if the current lookahead token would be valid in that state.
  if (summary && !ts_subtree_is_error(lookahead)) {
    for (unsigned i = 0; i < summary->size; i++) {
      StackSummaryEntry entry = *array_get(summary, i);

      if (entry.state == ERROR_STATE) continue;
      if (entry.position.bytes == position.bytes) continue;
      unsigned depth = entry.depth;
      if (node_count_since_error > 0) depth++;

      // Do not recover in ways that create redundant stack versions.
      bool would_merge = false;
      for (unsigned j = 0; j < previous_version_count; j++) {
        if (
          ts_stack_state(self->stack, j) == entry.state &&
          ts_stack_position(self->stack, j).bytes == position.bytes
        ) {
          would_merge = true;
          break;
        }
      }
      if (would_merge) continue;

      // Do not recover if the result would clearly be worse than some existing stack version.
      unsigned new_cost =
        current_error_cost +
        entry.depth * ERROR_COST_PER_SKIPPED_TREE +
        (position.bytes - entry.position.bytes) * ERROR_COST_PER_SKIPPED_CHAR +
        (position.extent.row - entry.position.extent.row) * ERROR_COST_PER_SKIPPED_LINE;
      if (ts_parser__better_version_exists(self, version, false, new_cost)) break;

      // If the current lookahead token is valid in some previous state, recover to that state.
      // Then stop looking for further recoveries.
      if (ts_language_has_actions(self->language, entry.state, ts_subtree_symbol(lookahead))) {
        if (ts_parser__recover_to_state(self, version, depth, entry.state)) {
          did_recover = true;
          LOG("recover_to_previous state:%u, depth:%u", entry.state, depth);
          LOG_STACK();
          break;
        }
      }
    }
  }

  // In the process of attempting to recover, some stack versions may have been created
  // and subsequently halted. Remove those versions.
  for (unsigned i = previous_version_count; i < ts_stack_version_count(self->stack); i++) {
    if (!ts_stack_is_active(self->stack, i)) {
      LOG("removed paused version:%u", i);
      ts_stack_remove_version(self->stack, i--);
      LOG_STACK();
    }
  }

  // If the parser is still in the error state at the end of the file, just wrap everything
  // in an ERROR node and terminate.
  if (ts_subtree_is_eof(lookahead)) {
    LOG("recover_eof");
    SubtreeArray children = array_new();
    Subtree parent = ts_subtree_new_error_node(&children, false, self->language);
    ts_stack_push(self->stack, version, parent, false, 1);
    ts_parser__accept(self, version, lookahead);
    return;
  }

  // If strategy 1 succeeded, a new stack version will have been created which is able to handle
  // the current lookahead token. Now, in addition, try strategy 2 described above: skip the
  // current lookahead token by wrapping it in an ERROR node.

  // Don't pursue this additional strategy if there are already too many stack versions.
  if (did_recover && ts_stack_version_count(self->stack) > MAX_VERSION_COUNT) {
    ts_stack_halt(self->stack, version);
    ts_subtree_release(&self->tree_pool, lookahead);
    return;
  }

  if (
    did_recover &&
    ts_subtree_has_external_scanner_state_change(lookahead)
  ) {
    ts_stack_halt(self->stack, version);
    ts_subtree_release(&self->tree_pool, lookahead);
    return;
  }

  // Do not recover if the result would clearly be worse than some existing stack version.
  unsigned new_cost =
    current_error_cost + ERROR_COST_PER_SKIPPED_TREE +
    ts_subtree_total_bytes(lookahead) * ERROR_COST_PER_SKIPPED_CHAR +
    ts_subtree_total_size(lookahead).extent.row * ERROR_COST_PER_SKIPPED_LINE;
  if (ts_parser__better_version_exists(self, version, false, new_cost)) {
    ts_stack_halt(self->stack, version);
    ts_subtree_release(&self->tree_pool, lookahead);
    return;
  }

  // If the current lookahead token is an extra token, mark it as extra. This means it won't
  // be counted in error cost calculations.
  unsigned n;
  const TSParseAction *actions = ts_language_actions(self->language, 1, ts_subtree_symbol(lookahead), &n);
  if (n > 0 && actions[n - 1].type == TSParseActionTypeShift && actions[n - 1].shift.extra) {
    MutableSubtree mutable_lookahead = ts_subtree_make_mut(&self->tree_pool, lookahead);
    ts_subtree_set_extra(&mutable_lookahead, true);
    lookahead = ts_subtree_from_mut(mutable_lookahead);
  }

  // Wrap the lookahead token in an ERROR.
  LOG("skip_token symbol:%s", TREE_NAME(lookahead));
  SubtreeArray children = array_new();
  array_reserve(&children, 1);
  array_push(&children, lookahead);
  MutableSubtree error_repeat = ts_subtree_new_node(
    ts_builtin_sym_error_repeat,
    &children,
    0,
    self->language
  );

  // If other tokens have already been skipped, so there is already an ERROR at the top of the
  // stack, then pop that ERROR off the stack and wrap the two ERRORs together into one larger
  // ERROR.
  if (node_count_since_error > 0) {
    StackSliceArray pop = ts_stack_pop_count(self->stack, version, 1);

    // TODO: Figure out how to make this condition occur.
    // See https://github.com/atom/atom/issues/18450#issuecomment-439579778
    // If multiple stack versions have merged at this point, just pick one of the errors
    // arbitrarily and discard the rest.
    if (pop.size > 1) {
      for (unsigned i = 1; i < pop.size; i++) {
        ts_subtree_array_delete(&self->tree_pool, &array_get(&pop, i)->subtrees);
      }
      while (ts_stack_version_count(self->stack) > array_get(&pop, 0)->version + 1) {
        ts_stack_remove_version(self->stack, array_get(&pop, 0)->version + 1);
      }
    }

    ts_stack_renumber_version(self->stack, array_get(&pop, 0)->version, version);
    array_push(&array_get(&pop, 0)->subtrees, ts_subtree_from_mut(error_repeat));
    error_repeat = ts_subtree_new_node(
      ts_builtin_sym_error_repeat,
      &array_get(&pop, 0)->subtrees,
      0,
      self->language
    );
  }

  // Push the new ERROR onto the stack.
  ts_stack_push(self->stack, version, ts_subtree_from_mut(error_repeat), false, ERROR_STATE);
  if (ts_subtree_has_external_tokens(lookahead)) {
    ts_stack_set_last_external_token(
      self->stack, version, ts_subtree_last_external_token(lookahead)
    );
  }

  bool has_error = true;
  for (unsigned i = 0; i < ts_stack_version_count(self->stack); i++) {
    ErrorStatus status = ts_parser__version_status(self, i);
    if (!status.is_in_error) {
      has_error = false;
      break;
    }
  }
  self->has_error = has_error;
}

static void ts_parser__handle_error(
  TSParser *self,
  StackVersion version,
  Subtree lookahead
) {
  uint32_t previous_version_count = ts_stack_version_count(self->stack);

  // Perform any reductions that can happen in this state, regardless of the lookahead. After
  // skipping one or more invalid tokens, the parser might find a token that would have allowed
  // a reduction to take place.
  ts_parser__do_all_potential_reductions(self, version, 0);
  uint32_t version_count = ts_stack_version_count(self->stack);
  Length position = ts_stack_position(self->stack, version);

  // Push a discontinuity onto the stack. Merge all of the stack versions that
  // were created in the previous step.
  bool did_insert_missing_token = false;
  for (StackVersion v = version; v < version_count;) {
    if (!did_insert_missing_token) {
      TSStateId state = ts_stack_state(self->stack, v);
      for (
        TSSymbol missing_symbol = 1;
        missing_symbol < (uint16_t)self->language->token_count;
        missing_symbol++
      ) {
        TSStateId state_after_missing_symbol = ts_language_next_state(
          self->language, state, missing_symbol
        );
        if (state_after_missing_symbol == 0 || state_after_missing_symbol == state) {
          continue;
        }

        if (ts_language_has_reduce_action(
          self->language,
          state_after_missing_symbol,
          ts_subtree_leaf_symbol(lookahead)
        )) {
          // In case the parser is currently outside of any included range, the lexer will
          // snap to the beginning of the next included range. The missing token's padding
          // must be assigned to position it within the next included range.
          ts_lexer_reset(&self->lexer, position);
          ts_lexer_mark_end(&self->lexer);
          Length padding = length_sub(self->lexer.token_end_position, position);
          uint32_t lookahead_bytes = ts_subtree_total_bytes(lookahead) + ts_subtree_lookahead_bytes(lookahead);

          StackVersion version_with_missing_tree = ts_stack_copy_version(self->stack, v);
          Subtree missing_tree = ts_subtree_new_missing_leaf(
            &self->tree_pool, missing_symbol,
            padding, lookahead_bytes,
            self->language
          );
          ts_stack_push(
            self->stack, version_with_missing_tree,
            missing_tree, false,
            state_after_missing_symbol
          );

          if (ts_parser__do_all_potential_reductions(
            self, version_with_missing_tree,
            ts_subtree_leaf_symbol(lookahead)
          )) {
            LOG(
              "recover_with_missing symbol:%s, state:%u",
              SYM_NAME(missing_symbol),
              ts_stack_state(self->stack, version_with_missing_tree)
            );
            did_insert_missing_token = true;
            break;
          }
        }
      }
    }

    ts_stack_push(self->stack, v, NULL_SUBTREE, false, ERROR_STATE);
    v = (v == version) ? previous_version_count : v + 1;
  }

  for (unsigned i = previous_version_count; i < version_count; i++) {
    bool did_merge = ts_stack_merge(self->stack, version, previous_version_count);
    ts_assert(did_merge);
  }

  ts_stack_record_summary(self->stack, version, MAX_SUMMARY_DEPTH);

  // Begin recovery with the current lookahead node, rather than waiting for the
  // next turn of the parse loop. This ensures that the tree accounts for the
  // current lookahead token's "lookahead bytes" value, which describes how far
  // the lexer needed to look ahead beyond the content of the token in order to
  // recognize it.
  if (ts_subtree_child_count(lookahead) > 0) {
    ts_parser__breakdown_lookahead(self, &lookahead, ERROR_STATE, &self->reusable_node);
  }
  ts_parser__recover(self, version, lookahead);

  LOG_STACK();
}
