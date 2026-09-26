// The token lexer and its per-state cache, split out of parser.c.

#include "./parser.h"

static Subtree ts_parser__lex(
  TSParser *self,
  StackVersion version,
  TSStateId parse_state
) {
  TSLexerMode lex_mode = ts_language_lex_mode_for_state(self->language, parse_state);
  if (lex_mode.lex_state == (uint16_t)-1) {
    LOG("no_lookahead_after_non_terminal_extra");
    return NULL_SUBTREE;
  }

  const Length start_position = ts_stack_position(self->stack, version);
  const Subtree external_token = ts_stack_last_external_token(self->stack, version);

  bool found_external_token = false;
  bool error_mode = parse_state == ERROR_STATE;
  bool skipped_error = false;
  bool called_get_column = false;
  int32_t first_error_character = 0;
  Length error_start_position = length_zero();
  Length error_end_position = length_zero();
  uint32_t lookahead_end_byte = 0;
  uint32_t external_scanner_state_len = 0;
  bool external_scanner_state_changed = false;
  ts_lexer_reset(&self->lexer, start_position);

  for (;;) {
    bool found_token = false;
    Length current_position = self->lexer.current_position;
    ColumnData column_data = self->lexer.column_data;

    if (lex_mode.external_lex_state != 0) {
      LOG(
        "lex_external state:%d, row:%u, column:%u",
        lex_mode.external_lex_state,
        current_position.extent.row,
        current_position.extent.column
      );
      ts_lexer_start(&self->lexer);
      ts_parser__external_scanner_deserialize(self, external_token);
      found_token = ts_parser__external_scanner_scan(self, lex_mode.external_lex_state);
      if (self->has_scanner_error) return NULL_SUBTREE;
      ts_lexer_finish(&self->lexer, &lookahead_end_byte);

      if (found_token) {
        external_scanner_state_len = ts_parser__external_scanner_serialize(self);
        external_scanner_state_changed = !ts_external_scanner_state_eq(
          ts_subtree_external_scanner_state(external_token),
          self->lexer.debug_buffer,
          external_scanner_state_len
        );

        // Avoid infinite loops caused by the external scanner returning empty tokens.
        // Empty tokens are needed in some circumstances, e.g. indent/dedent tokens
        // in Python. Ignore the following classes of empty tokens:
        //
        // * Tokens produced during error recovery. When recovering from an error,
        //   all tokens are allowed, so it's easy to accidentally return unwanted
        //   empty tokens.
        // * Tokens that are marked as 'extra' in the grammar. These don't change
        //   the parse state, so they would definitely cause an infinite loop.
        if (
          self->lexer.token_end_position.bytes <= current_position.bytes &&
          !external_scanner_state_changed
        ) {
          TSSymbol symbol = self->language->external_scanner.symbol_map[self->lexer.data.result_symbol];
          TSStateId next_parse_state = ts_language_next_state(self->language, parse_state, symbol);
          bool token_is_extra = (next_parse_state == parse_state);
          if (error_mode || !ts_stack_has_advanced_since_error(self->stack, version) || token_is_extra) {
            LOG(
              "ignore_empty_external_token symbol:%s",
              SYM_NAME(self->language->external_scanner.symbol_map[self->lexer.data.result_symbol])
            );
            found_token = false;
          }
        }
      }

      if (found_token) {
        found_external_token = true;
        called_get_column = self->lexer.did_get_column;
        break;
      }

      ts_lexer_reset(&self->lexer, current_position);
      self->lexer.column_data = column_data;
    }

    LOG(
      "lex_internal state:%d, row:%u, column:%u",
      lex_mode.lex_state,
      current_position.extent.row,
      current_position.extent.column
    );
    ts_lexer_start(&self->lexer);
    found_token = ts_parser__call_main_lex_fn(self, lex_mode);
    ts_lexer_finish(&self->lexer, &lookahead_end_byte);
    if (found_token) break;

    if (!error_mode) {
      error_mode = true;
      lex_mode = ts_language_lex_mode_for_state(self->language, ERROR_STATE);
      ts_lexer_reset(&self->lexer, start_position);
      continue;
    }

    if (!skipped_error) {
      LOG("skip_unrecognized_character");
      skipped_error = true;
      error_start_position = self->lexer.token_start_position;
      error_end_position = self->lexer.token_start_position;
      first_error_character = self->lexer.data.lookahead;
    }

    if (self->lexer.current_position.bytes == error_end_position.bytes) {
      if (self->lexer.data.eof(&self->lexer.data)) {
        self->lexer.data.result_symbol = ts_builtin_sym_error;
        break;
      }
      self->lexer.data.advance(&self->lexer.data, false);
    }

    error_end_position = self->lexer.current_position;
  }

  Subtree result;
  if (skipped_error) {
    Length padding = length_sub(error_start_position, start_position);
    Length size = length_sub(error_end_position, error_start_position);
    uint32_t lookahead_bytes = lookahead_end_byte - error_end_position.bytes;
    result = ts_subtree_new_error(
      &self->tree_pool,
      first_error_character,
      padding,
      size,
      lookahead_bytes,
      parse_state,
      self->language
    );
  } else {
    bool is_keyword = false;
    TSSymbol symbol = self->lexer.data.result_symbol;
    Length padding = length_sub(self->lexer.token_start_position, start_position);
    Length size = length_sub(self->lexer.token_end_position, self->lexer.token_start_position);
    uint32_t lookahead_bytes = lookahead_end_byte - self->lexer.token_end_position.bytes;

    if (found_external_token) {
      symbol = self->language->external_scanner.symbol_map[symbol];
    } else if (symbol == self->language->keyword_capture_token && symbol != 0) {
      uint32_t end_byte = self->lexer.token_end_position.bytes;
      ts_lexer_reset(&self->lexer, self->lexer.token_start_position);
      ts_lexer_start(&self->lexer);

      is_keyword = ts_parser__call_keyword_lex_fn(self);

      if (
        is_keyword &&
        self->lexer.token_end_position.bytes == end_byte &&
        (
          ts_language_has_actions(self->language, parse_state, self->lexer.data.result_symbol) ||
          ts_language_is_reserved_word(self->language, parse_state, self->lexer.data.result_symbol)
        )
      ) {
        symbol = self->lexer.data.result_symbol;
      }
    }

    result = ts_subtree_new_leaf(
      &self->tree_pool,
      symbol,
      padding,
      size,
      lookahead_bytes,
      parse_state,
      found_external_token,
      called_get_column,
      is_keyword,
      self->language
    );

    if (found_external_token) {
      MutableSubtree mut_result = ts_subtree_to_mut_unsafe(result);
      ts_external_scanner_state_init(
        &mut_result.ptr->external_scanner_state,
        self->lexer.debug_buffer,
        external_scanner_state_len
      );
      mut_result.ptr->has_external_scanner_state_change = external_scanner_state_changed;
    }
  }

  LOG_LOOKAHEAD(
    SYM_NAME(ts_subtree_symbol(result)),
    ts_subtree_total_size(result).bytes
  );
  return result;
}

static Subtree ts_parser__get_cached_token(
  TSParser *self,
  TSStateId state,
  size_t position,
  Subtree last_external_token,
  TableEntry *table_entry
) {
  TokenCache *cache = &self->token_cache;
  if (
    cache->token.ptr && cache->byte_index == position &&
    ts_subtree_external_scanner_state_eq(cache->last_external_token, last_external_token)
  ) {
    ts_language_table_entry(self->language, state, ts_subtree_symbol(cache->token), table_entry);
    if (ts_parser__can_reuse_first_leaf(self, state, cache->token, table_entry)) {
      ts_subtree_retain(cache->token);
      return cache->token;
    }
  }
  return NULL_SUBTREE;
}

static void ts_parser__set_cached_token(
  TSParser *self,
  uint32_t byte_index,
  Subtree last_external_token,
  Subtree token
) {
  TokenCache *cache = &self->token_cache;
  if (token.ptr) ts_subtree_retain(token);
  if (last_external_token.ptr) ts_subtree_retain(last_external_token);
  if (cache->token.ptr) ts_subtree_release(&self->tree_pool, cache->token);
  if (cache->last_external_token.ptr) ts_subtree_release(&self->tree_pool, cache->last_external_token);
  cache->token = token;
  cache->byte_index = byte_index;
  cache->last_external_token = last_external_token;
}

static bool ts_parser__has_included_range_difference(
  const TSParser *self,
  uint32_t start_position,
  uint32_t end_position
) {
  return ts_range_array_intersects(
    &self->included_range_differences,
    self->included_range_difference_index,
    start_position,
    end_position
  );
}
