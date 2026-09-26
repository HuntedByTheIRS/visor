// The public ts_parser_* surface, split out of parser.c.

#include "./parser.h"

static bool ts_parser_has_outstanding_parse(TSParser *self) {
  return (
    self->canceled_balancing ||
    self->external_scanner_payload ||
    ts_stack_state(self->stack, 0) != 1 ||
    ts_stack_node_count_since_error(self->stack, 0) != 0
  );
}

// Parser - Public

TSParser *ts_parser_new(void) {
  TSParser *self = ts_calloc(1, sizeof(TSParser));
  ts_lexer_init(&self->lexer);
  array_init(&self->reduce_actions);
  array_reserve(&self->reduce_actions, 4);
  self->tree_pool = ts_subtree_pool_new(32);
  self->stack = ts_stack_new(&self->tree_pool);
  self->finished_tree = NULL_SUBTREE;
  self->reusable_node = reusable_node_new();
  self->dot_graph_file = NULL;
  self->language = NULL;
  self->has_scanner_error = false;
  self->has_error = false;
  self->canceled_balancing = false;
  self->external_scanner_payload = NULL;
  self->operation_count = 0;
  self->old_tree = NULL_SUBTREE;
  self->included_range_differences = (TSRangeArray) array_new();
  self->included_range_difference_index = 0;
  ts_parser__set_cached_token(self, 0, NULL_SUBTREE, NULL_SUBTREE);
  return self;
}

void ts_parser_delete(TSParser *self) {
  if (!self) return;

  ts_parser_set_language(self, NULL);
  ts_stack_delete(self->stack);
  if (self->reduce_actions.contents) {
    array_delete(&self->reduce_actions);
  }
  if (self->included_range_differences.contents) {
    array_delete(&self->included_range_differences);
  }
  if (self->old_tree.ptr) {
    ts_subtree_release(&self->tree_pool, self->old_tree);
    self->old_tree = NULL_SUBTREE;
  }
  ts_wasm_store_delete(self->wasm_store);
  ts_lexer_delete(&self->lexer);
  ts_parser__set_cached_token(self, 0, NULL_SUBTREE, NULL_SUBTREE);
  ts_subtree_pool_delete(&self->tree_pool);
  reusable_node_delete(&self->reusable_node);
  array_delete(&self->trailing_extras);
  array_delete(&self->trailing_extras2);
  array_delete(&self->scratch_trees);
  ts_free(self);
}

const TSLanguage *ts_parser_language(const TSParser *self) {
  return self->language;
}

bool ts_parser_set_language(TSParser *self, const TSLanguage *language) {
  ts_parser_reset(self);
  ts_language_delete(self->language);
  self->language = NULL;

  if (language) {
    if (
      language->abi_version > TREE_SITTER_LANGUAGE_VERSION ||
      language->abi_version < TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION
    ) return false;

    if (ts_language_is_wasm(language)) {
      if (
        !self->wasm_store ||
        !ts_wasm_store_start(self->wasm_store, &self->lexer.data, language)
      ) return false;
    }
  }

  self->language = ts_language_copy(language);
  return true;
}

TSLogger ts_parser_logger(const TSParser *self) {
  return self->lexer.logger;
}

void ts_parser_set_logger(TSParser *self, TSLogger logger) {
  self->lexer.logger = logger;
}

void ts_parser_print_dot_graphs(TSParser *self, int fd) {
  if (self->dot_graph_file) {
    fclose(self->dot_graph_file);
  }

  if (fd >= 0) {
    #ifdef _WIN32
    self->dot_graph_file = _fdopen(fd, "a");
    #else
    self->dot_graph_file = fdopen(fd, "a");
    #endif
  } else {
    self->dot_graph_file = NULL;
  }
}

bool ts_parser_set_included_ranges(
  TSParser *self,
  const TSRange *ranges,
  uint32_t count
) {
  return ts_lexer_set_included_ranges(&self->lexer, ranges, count);
}

const TSRange *ts_parser_included_ranges(const TSParser *self, uint32_t *count) {
  return ts_lexer_included_ranges(&self->lexer, count);
}

void ts_parser_reset(TSParser *self) {
  ts_parser__external_scanner_destroy(self);
  if (self->wasm_store) {
    ts_wasm_store_reset(self->wasm_store);
  }

  if (self->old_tree.ptr) {
    ts_subtree_release(&self->tree_pool, self->old_tree);
    self->old_tree = NULL_SUBTREE;
  }

  reusable_node_clear(&self->reusable_node);
  ts_lexer_reset(&self->lexer, length_zero());
  ts_stack_clear(self->stack);
  ts_parser__set_cached_token(self, 0, NULL_SUBTREE, NULL_SUBTREE);
  if (self->finished_tree.ptr) {
    ts_subtree_release(&self->tree_pool, self->finished_tree);
    self->finished_tree = NULL_SUBTREE;
  }
  self->accept_count = 0;
  self->has_scanner_error = false;
  self->has_error = false;
  self->canceled_balancing = false;
  self->parse_options = (TSParseOptions) {0};
  self->parse_state = (TSParseState) {0};
}

TSTree *ts_parser_parse(
  TSParser *self,
  const TSTree *old_tree,
  TSInput input
) {
  TSTree *result = NULL;
  if (!self->language || !input.read) return NULL;

  if (ts_language_is_wasm(self->language)) {
    if (!self->wasm_store) return NULL;
    ts_wasm_store_start(self->wasm_store, &self->lexer.data, self->language);
  }

  ts_lexer_set_input(&self->lexer, input);
  array_clear(&self->included_range_differences);
  self->included_range_difference_index = 0;

  self->operation_count = 0;

  if (ts_parser_has_outstanding_parse(self)) {
    LOG("resume_parsing");
    if (self->canceled_balancing) goto balance;
  } else {
    ts_parser__external_scanner_create(self);
    if (self->has_scanner_error) goto exit;

    if (old_tree) {
      ts_subtree_retain(old_tree->root);
      self->old_tree = old_tree->root;
      ts_range_array_get_changed_ranges(
        old_tree->included_ranges, old_tree->included_range_count,
        self->lexer.included_ranges, self->lexer.included_range_count,
        &self->included_range_differences
      );
      reusable_node_reset(&self->reusable_node, old_tree->root);
      LOG("parse_after_edit");
      LOG_TREE(self->old_tree);
      for (unsigned i = 0; i < self->included_range_differences.size; i++) {
        TSRange *range = array_get(&self->included_range_differences, i);
        LOG("different_included_range %u - %u", range->start_byte, range->end_byte);
      }
    } else {
      reusable_node_clear(&self->reusable_node);
      LOG("new_parse");
    }
  }

  uint32_t position = 0, last_position = 0, version_count = 0;
  do {
    for (
      StackVersion version = 0;
      version_count = ts_stack_version_count(self->stack),
      version < version_count;
      version++
    ) {
      bool allow_node_reuse = version_count == 1;
      while (ts_stack_is_active(self->stack, version)) {
        LOG(
          "process version:%u, version_count:%u, state:%d, row:%u, col:%u",
          version,
          ts_stack_version_count(self->stack),
          ts_stack_state(self->stack, version),
          ts_stack_position(self->stack, version).extent.row,
          ts_stack_position(self->stack, version).extent.column
        );

        if (!ts_parser__advance(self, version, allow_node_reuse)) {
          if (self->has_scanner_error) goto exit;
          return NULL;
        }

        LOG_STACK();

        position = ts_stack_position(self->stack, version).bytes;
        if (position > last_position || (version > 0 && position == last_position)) {
          last_position = position;
          break;
        }
      }
    }

    // After advancing each version of the stack, re-sort the versions by their cost,
    // removing any versions that are no longer worth pursuing.
    unsigned min_error_cost = ts_parser__condense_stack(self);

    // If there's already a finished parse tree that's better than any in-progress version,
    // then terminate parsing. Clear the parse stack to remove any extra references to subtrees
    // within the finished tree, ensuring that these subtrees can be safely mutated in-place
    // for rebalancing.
    if (self->finished_tree.ptr && ts_subtree_error_cost(self->finished_tree) < min_error_cost) {
      ts_stack_clear(self->stack);
      break;
    }

    while (self->included_range_difference_index < self->included_range_differences.size) {
      TSRange *range = array_get(&self->included_range_differences, self->included_range_difference_index);
      if (range->end_byte <= position) {
        self->included_range_difference_index++;
      } else {
        break;
      }
    }
  } while (version_count != 0);

balance:
  ts_assert(self->finished_tree.ptr);
  if (!ts_parser__balance_subtree(self)) {
    self->canceled_balancing = true;
    return false;
  }
  self->canceled_balancing = false;
  LOG("done");
  LOG_TREE(self->finished_tree);

  result = ts_tree_new(
    self->finished_tree,
    self->language,
    self->lexer.included_ranges,
    self->lexer.included_range_count
  );
  self->finished_tree = NULL_SUBTREE;

exit:
  ts_parser_reset(self);
  return result;
}

TSTree *ts_parser_parse_with_options(
  TSParser *self,
  const TSTree *old_tree,
  TSInput input,
  TSParseOptions parse_options
) {
  self->parse_options = parse_options;
  self->parse_state.payload = parse_options.payload;
  TSTree *result = ts_parser_parse(self, old_tree, input);
  // Reset parser options before further parse calls.
  self->parse_options = (TSParseOptions) {0};
  return result;
}

TSTree *ts_parser_parse_string(
  TSParser *self,
  const TSTree *old_tree,
  const char *string,
  uint32_t length
) {
  return ts_parser_parse_string_encoding(self, old_tree, string, length, TSInputEncodingUTF8);
}

TSTree *ts_parser_parse_string_encoding(
  TSParser *self,
  const TSTree *old_tree,
  const char *string,
  uint32_t length,
  TSInputEncoding encoding
) {
  TSStringInput input = {string, length};
  return ts_parser_parse(self, old_tree, (TSInput) {
    &input,
    ts_string_input_read,
    encoding,
    NULL,
  });
}

void ts_parser_set_wasm_store(TSParser *self, TSWasmStore *store) {
  if (self->language && ts_language_is_wasm(self->language)) {
    // Copy the assigned language into the new store.
    const TSLanguage *copy = ts_language_copy(self->language);
    ts_parser_set_language(self, copy);
    ts_language_delete(copy);
  }

  ts_wasm_store_delete(self->wasm_store);
  self->wasm_store = store;
}

TSWasmStore *ts_parser_take_wasm_store(TSParser *self) {
  if (self->language && ts_language_is_wasm(self->language)) {
    ts_parser_set_language(self, NULL);
  }

  TSWasmStore *result = self->wasm_store;
  self->wasm_store = NULL;
  return result;
}

#undef LOG
