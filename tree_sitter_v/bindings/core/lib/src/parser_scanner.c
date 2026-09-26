// External scanner callbacks and the leaf-reuse test, split out of parser.c.

#include "./parser.h"

static void ts_parser__external_scanner_create(
  TSParser *self
) {
  if (self->language && self->language->external_scanner.states) {
    if (ts_language_is_wasm(self->language)) {
      self->external_scanner_payload = (void *)(uintptr_t)ts_wasm_store_call_scanner_create(
        self->wasm_store
      );
      if (ts_wasm_store_has_error(self->wasm_store)) {
        self->has_scanner_error = true;
      }
    } else if (self->language->external_scanner.create) {
      self->external_scanner_payload = self->language->external_scanner.create();
    }
  }
}

static void ts_parser__external_scanner_destroy(
  TSParser *self
) {
  if (
    self->language &&
    self->external_scanner_payload &&
    self->language->external_scanner.destroy &&
    !ts_language_is_wasm(self->language)
  ) {
    self->language->external_scanner.destroy(
      self->external_scanner_payload
    );
  }
  self->external_scanner_payload = NULL;
}

static unsigned ts_parser__external_scanner_serialize(
  TSParser *self
) {
  uint32_t length;
  if (ts_language_is_wasm(self->language)) {
    length = ts_wasm_store_call_scanner_serialize(
      self->wasm_store,
      (uintptr_t)self->external_scanner_payload,
      self->lexer.debug_buffer
    );
    if (ts_wasm_store_has_error(self->wasm_store)) {
      self->has_scanner_error = true;
    }
  } else {
    length = self->language->external_scanner.serialize(
      self->external_scanner_payload,
      self->lexer.debug_buffer
    );
  }
  ts_assert(length <= TREE_SITTER_SERIALIZATION_BUFFER_SIZE);
  return length;
}

static void ts_parser__external_scanner_deserialize(
  TSParser *self,
  Subtree external_token
) {
  const char *data = NULL;
  uint32_t length = 0;
  if (external_token.ptr) {
    data = ts_external_scanner_state_data(&external_token.ptr->external_scanner_state);
    length = external_token.ptr->external_scanner_state.length;
  }

  if (ts_language_is_wasm(self->language)) {
    ts_wasm_store_call_scanner_deserialize(
      self->wasm_store,
      (uintptr_t)self->external_scanner_payload,
      data,
      length
    );
    if (ts_wasm_store_has_error(self->wasm_store)) {
      self->has_scanner_error = true;
    }
  } else {
    self->language->external_scanner.deserialize(
      self->external_scanner_payload,
      data,
      length
    );
  }
}

static bool ts_parser__external_scanner_scan(
  TSParser *self,
  TSStateId external_lex_state
) {
  if (ts_language_is_wasm(self->language)) {
    bool result = ts_wasm_store_call_scanner_scan(
      self->wasm_store,
      (uintptr_t)self->external_scanner_payload,
      external_lex_state * self->language->external_token_count
    );
    if (ts_wasm_store_has_error(self->wasm_store)) {
      self->has_scanner_error = true;
    }
    return result;
  } else {
    const bool *valid_external_tokens = ts_language_enabled_external_tokens(
      self->language,
      external_lex_state
    );
    return self->language->external_scanner.scan(
      self->external_scanner_payload,
      &self->lexer.data,
      valid_external_tokens
    );
  }
}

static bool ts_parser__can_reuse_first_leaf(
  TSParser *self,
  TSStateId state,
  Subtree tree,
  TableEntry *table_entry
) {
  TSSymbol leaf_symbol = ts_subtree_leaf_symbol(tree);
  TSStateId leaf_state = ts_subtree_leaf_parse_state(tree);
  TSLexerMode current_lex_mode = ts_language_lex_mode_for_state(self->language, state);
  TSLexerMode leaf_lex_mode = ts_language_lex_mode_for_state(self->language, leaf_state);

  // At the end of a non-terminal extra node, the lexer normally returns
  // NULL, which indicates that the parser should look for a reduce action
  // at symbol `0`. Avoid reusing tokens in this situation to ensure that
  // the same thing happens when incrementally reparsing.
  if (current_lex_mode.lex_state == (uint16_t)(-1)) return false;

  // If the token was created in a state with the same set of lookaheads, it is reusable.
  if (
    table_entry->action_count > 0 &&
    memcmp(&leaf_lex_mode, &current_lex_mode, sizeof(TSLexerMode)) == 0 &&
    (
      leaf_symbol != self->language->keyword_capture_token ||
      (!ts_subtree_is_keyword(tree) && ts_subtree_parse_state(tree) == state)
    )
  ) return true;

  // Empty tokens are not reusable in states with different lookaheads.
  if (ts_subtree_size(tree).bytes == 0 && leaf_symbol != ts_builtin_sym_end) return false;

  // If the current state allows external tokens or other tokens that conflict with this
  // token, this token is not reusable.
  return current_lex_mode.external_lex_state == 0 && table_entry->is_reusable;
}
