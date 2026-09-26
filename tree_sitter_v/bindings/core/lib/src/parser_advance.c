// The parse step: progress checks, stack condensing, subtree balancing.

#include "./parser.h"

static bool ts_parser__check_progress(TSParser *self, Subtree *lookahead, const uint32_t *position, unsigned operations) {
  self->operation_count += operations;
  if (self->operation_count >= OP_COUNT_PER_PARSER_CALLBACK_CHECK) {
    self->operation_count = 0;
  }
  if (position != NULL) {
    self->parse_state.current_byte_offset = *position;
    self->parse_state.has_error = self->has_error;
  }
  if (
    self->operation_count == 0 &&
    (self->parse_options.progress_callback && self->parse_options.progress_callback(&self->parse_state))
  ) {
    if (lookahead && lookahead->ptr) {
      ts_subtree_release(&self->tree_pool, *lookahead);
    }
    return false;
  }
  return true;
}

static bool ts_parser__advance(
  TSParser *self,
  StackVersion version,
  bool allow_node_reuse
) {
  TSStateId state = ts_stack_state(self->stack, version);
  uint32_t position = ts_stack_position(self->stack, version).bytes;
  Subtree last_external_token = ts_stack_last_external_token(self->stack, version);

  bool did_reuse = true;
  Subtree lookahead = NULL_SUBTREE;
  TableEntry table_entry = {.action_count = 0};

  // If possible, reuse a node from the previous syntax tree.
  if (allow_node_reuse) {
    lookahead = ts_parser__reuse_node(
      self, version, &state, position, last_external_token, &table_entry
    );
  }

  // If no node from the previous syntax tree could be reused, then try to
  // reuse the token previously returned by the lexer.
  if (!lookahead.ptr) {
    did_reuse = false;
    lookahead = ts_parser__get_cached_token(
      self, state, position, last_external_token, &table_entry
    );
  }

  bool needs_lex = !lookahead.ptr;
  for (;;) {
    // Otherwise, re-run the lexer.
    if (needs_lex) {
      needs_lex = false;
      lookahead = ts_parser__lex(self, version, state);
      if (self->has_scanner_error) return false;

      if (lookahead.ptr) {
        ts_parser__set_cached_token(self, position, last_external_token, lookahead);
        ts_language_table_entry(self->language, state, ts_subtree_symbol(lookahead), &table_entry);
      }

      // When parsing a non-terminal extra, a null lookahead indicates the
      // end of the rule. The reduction is stored in the EOF table entry.
      // After the reduction, the lexer needs to be run again.
      else {
        ts_language_table_entry(self->language, state, ts_builtin_sym_end, &table_entry);
      }
    }

    // If a progress callback was provided, then check every
    // time a fixed number of parse actions has been processed.
    if (!ts_parser__check_progress(self, &lookahead, &position, 1)) {
      return false;
    }

    // Process each parse action for the current lookahead token in
    // the current state. If there are multiple actions, then this is
    // an ambiguous state. REDUCE actions always create a new stack
    // version, whereas SHIFT actions update the existing stack version
    // and terminate this loop.
    bool did_reduce = false;
    StackVersion last_reduction_version = STACK_VERSION_NONE;
    for (uint32_t i = 0; i < table_entry.action_count; i++) {
      TSParseAction action = table_entry.actions[i];

      switch (action.type) {
        case TSParseActionTypeShift: {
          if (action.shift.repetition) break;
          TSStateId next_state;
          if (action.shift.extra) {
            next_state = state;
            LOG("shift_extra");
          } else {
            next_state = action.shift.state;
            LOG("shift state:%u", next_state);
          }

          if (ts_subtree_child_count(lookahead) > 0) {
            ts_parser__breakdown_lookahead(self, &lookahead, state, &self->reusable_node);
            next_state = ts_language_next_state(self->language, state, ts_subtree_symbol(lookahead));
          }

          ts_parser__shift(self, version, next_state, lookahead, action.shift.extra);
          if (did_reuse) reusable_node_advance(&self->reusable_node);
          return true;
        }

        case TSParseActionTypeReduce: {
          bool is_fragile = table_entry.action_count > 1;
          bool end_of_non_terminal_extra = lookahead.ptr == NULL;
          LOG("reduce sym:%s, child_count:%u", SYM_NAME(action.reduce.symbol), action.reduce.child_count);
          StackVersion reduction_version = ts_parser__reduce(
            self, version, action.reduce.symbol, action.reduce.child_count,
            action.reduce.dynamic_precedence, action.reduce.production_id,
            is_fragile, end_of_non_terminal_extra
          );
          did_reduce = true;
          if (reduction_version != STACK_VERSION_NONE) {
            last_reduction_version = reduction_version;
          }
          break;
        }

        case TSParseActionTypeAccept: {
          LOG("accept");
          ts_parser__accept(self, version, lookahead);
          return true;
        }

        case TSParseActionTypeRecover: {
          if (ts_subtree_child_count(lookahead) > 0) {
            ts_parser__breakdown_lookahead(self, &lookahead, ERROR_STATE, &self->reusable_node);
          }

          ts_parser__recover(self, version, lookahead);
          if (did_reuse) reusable_node_advance(&self->reusable_node);
          return true;
        }
      }
    }

    // If a reduction was performed, then replace the current stack version
    // with one of the stack versions created by a reduction, and continue
    // processing this version of the stack with the same lookahead symbol.
    if (last_reduction_version != STACK_VERSION_NONE) {
      ts_stack_renumber_version(self->stack, last_reduction_version, version);
      LOG_STACK();
      state = ts_stack_state(self->stack, version);

      // At the end of a non-terminal extra rule, the lexer will return a
      // null subtree, because the parser needs to perform a fixed reduction
      // regardless of the lookahead node. After performing that reduction,
      // (and completing the non-terminal extra rule) run the lexer again based
      // on the current parse state.
      if (!lookahead.ptr) {
        needs_lex = true;
      } else {
        ts_language_table_entry(
          self->language,
          state,
          ts_subtree_leaf_symbol(lookahead),
          &table_entry
        );
      }

      continue;
    }

    // A reduction was performed, but was merged into an existing stack version.
    // This version can be discarded.
    if (did_reduce) {
      if (lookahead.ptr) {
        ts_subtree_release(&self->tree_pool, lookahead);
      }
      ts_stack_halt(self->stack, version);
      return true;
    }

    // If the current lookahead token is a keyword that is not valid, but the
    // default word token *is* valid, then treat the lookahead token as the word
    // token instead.
    if (
      ts_subtree_is_keyword(lookahead) &&
      ts_subtree_symbol(lookahead) != self->language->keyword_capture_token &&
      !ts_language_is_reserved_word(self->language, state, ts_subtree_symbol(lookahead))
    ) {
      ts_language_table_entry(
        self->language,
        state,
        self->language->keyword_capture_token,
        &table_entry
      );
      if (table_entry.action_count > 0) {
        LOG(
          "switch from_keyword:%s, to_word_token:%s",
          TREE_NAME(lookahead),
          SYM_NAME(self->language->keyword_capture_token)
        );

        MutableSubtree mutable_lookahead = ts_subtree_make_mut(&self->tree_pool, lookahead);
        ts_subtree_set_symbol(&mutable_lookahead, self->language->keyword_capture_token, self->language);
        lookahead = ts_subtree_from_mut(mutable_lookahead);
        continue;
      }
    }

    // If the current lookahead token is not valid and the previous subtree on
    // the stack was reused from an old tree, then it wasn't actually valid to
    // reuse that previous subtree. Remove it from the stack, and in its place,
    // push each of its children. Then try again to process the current lookahead.
    if (ts_parser__breakdown_top_of_stack(self, version)) {
      state = ts_stack_state(self->stack, version);
      ts_subtree_release(&self->tree_pool, lookahead);
      needs_lex = true;
      continue;
    }

    // Otherwise, there is definitely an error in this version of the parse stack.
    // Mark this version as paused and continue processing any other stack
    // versions that exist. If some other version advances successfully, then
    // this version can simply be removed. But if all versions end up paused,
    // then error recovery is needed.
    LOG("detect_error lookahead:%s", TREE_NAME(lookahead));
    ts_stack_pause(self->stack, version, lookahead);
    return true;
  }
}

static unsigned ts_parser__condense_stack(TSParser *self) {
  bool made_changes = false;
  unsigned min_error_cost = UINT_MAX;
  for (StackVersion i = 0; i < ts_stack_version_count(self->stack); i++) {
    // Prune any versions that have been marked for removal.
    if (ts_stack_is_halted(self->stack, i)) {
      ts_stack_remove_version(self->stack, i);
      i--;
      continue;
    }

    // Keep track of the minimum error cost of any stack version so
    // that it can be returned.
    ErrorStatus status_i = ts_parser__version_status(self, i);
    if (!status_i.is_in_error && status_i.cost < min_error_cost) {
      min_error_cost = status_i.cost;
    }

    // Examine each pair of stack versions, removing any versions that
    // are clearly worse than another version. Ensure that the versions
    // are ordered from most promising to least promising.
    for (StackVersion j = 0; j < i; j++) {
      ErrorStatus status_j = ts_parser__version_status(self, j);

      switch (ts_parser__compare_versions(self, status_j, status_i)) {
        case ErrorComparisonTakeLeft:
          made_changes = true;
          ts_stack_remove_version(self->stack, i);
          i--;
          j = i;
          break;

        case ErrorComparisonPreferLeft:
        case ErrorComparisonNone:
          if (ts_stack_merge(self->stack, j, i)) {
            made_changes = true;
            i--;
            j = i;
          }
          break;

        case ErrorComparisonPreferRight:
          made_changes = true;
          if (ts_stack_merge(self->stack, j, i)) {
            i--;
            j = i;
          } else {
            ts_stack_swap_versions(self->stack, i, j);
          }
          break;

        case ErrorComparisonTakeRight:
          made_changes = true;
          ts_stack_remove_version(self->stack, j);
          i--;
          j--;
          break;
      }
    }
  }

  // Enforce a hard upper bound on the number of stack versions by
  // discarding the least promising versions.
  while (ts_stack_version_count(self->stack) > MAX_VERSION_COUNT) {
    ts_stack_remove_version(self->stack, MAX_VERSION_COUNT);
    made_changes = true;
  }

  // If the best-performing stack version is currently paused, or all
  // versions are paused, then resume the best paused version and begin
  // the error recovery process. Otherwise, remove the paused versions.
  if (ts_stack_version_count(self->stack) > 0) {
    bool has_unpaused_version = false;
    for (StackVersion i = 0, n = ts_stack_version_count(self->stack); i < n; i++) {
      if (ts_stack_is_paused(self->stack, i)) {
        if (!has_unpaused_version && self->accept_count < MAX_VERSION_COUNT) {
          LOG("resume version:%u", i);
          min_error_cost = ts_stack_error_cost(self->stack, i);
          Subtree lookahead = ts_stack_resume(self->stack, i);
          ts_parser__handle_error(self, i, lookahead);
          has_unpaused_version = true;
        } else {
          ts_stack_remove_version(self->stack, i);
          made_changes = true;
          i--;
          n--;
        }
      } else {
        has_unpaused_version = true;
      }
    }
  }

  if (made_changes) {
    LOG("condense");
    LOG_STACK();
  }

  return min_error_cost;
}

static bool ts_parser__balance_subtree(TSParser *self) {
  Subtree finished_tree = self->finished_tree;

  // If we haven't canceled balancing in progress before, then we want to clear the tree stack and
  // push the initial finished tree onto it. Otherwise, if we're resuming balancing after a
  // cancellation, we don't want to clear the tree stack.
  if (!self->canceled_balancing) {
    array_clear(&self->tree_pool.tree_stack);
    if (ts_subtree_child_count(finished_tree) > 0 && finished_tree.ptr->ref_count == 1) {
      array_push(&self->tree_pool.tree_stack, ts_subtree_to_mut_unsafe(finished_tree));
    }
  }

  while (self->tree_pool.tree_stack.size > 0) {
    if (!ts_parser__check_progress(self, NULL, NULL, 1)) {
      return false;
    }

    MutableSubtree tree = *array_get(&self->tree_pool.tree_stack, 
      self->tree_pool.tree_stack.size - 1
    );

    if (tree.ptr->repeat_depth > 0) {
      Subtree child1 = ts_subtree_children(tree)[0];
      Subtree child2 = ts_subtree_children(tree)[tree.ptr->child_count - 1];
      long repeat_delta = (long)ts_subtree_repeat_depth(child1) - (long)ts_subtree_repeat_depth(child2);
      if (repeat_delta > 0) {
        unsigned n = (unsigned)repeat_delta;

        for (unsigned i = n / 2; i > 0; i /= 2) {
          ts_subtree_compress(tree, i, self->language, &self->tree_pool.tree_stack);
          n -= i;

          // We scale the operation count increment in `ts_parser__check_progress` proportionately to the compression
          // size since larger values of i take longer to process. Shifting by 4 empirically provides good check
          // intervals (e.g. 193 operations when i=3100) to prevent blocking during large compressions.
          uint8_t operations = i >> 4 > 0 ? i >> 4 : 1;
          if (!ts_parser__check_progress(self, NULL, NULL, operations)) {
            return false;
          }
        }
      }
    }

    (void)array_pop(&self->tree_pool.tree_stack);

    for (uint32_t i = 0; i < tree.ptr->child_count; i++) {
      Subtree child = ts_subtree_children(tree)[i];
      if (ts_subtree_child_count(child) > 0 && child.ptr->ref_count == 1) {
        array_push(&self->tree_pool.tree_stack, ts_subtree_to_mut_unsafe(child));
      }
    }
  }

  return true;
}
