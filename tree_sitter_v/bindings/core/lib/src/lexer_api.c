// The public ts_lexer_* surface, split out of lexer.c.

#include "./length.h"
#include "./lexer.h"
#include "./unicode.h"
#include "tree_sitter/api.h"

void ts_lexer_init(Lexer *self) {
  *self = (Lexer) {
    .data = {
      // The lexer's methods are stored as struct fields so that generated
      // parsers can call them without needing to be linked against this
      // library.
      .advance = ts_lexer__advance,
      .mark_end = ts_lexer__mark_end,
      .get_column = ts_lexer__get_column,
      .is_at_included_range_start = ts_lexer__is_at_included_range_start,
      .eof = ts_lexer__eof,
      .log = ts_lexer__log,
      .lookahead = 0,
      .result_symbol = 0,
    },
    .chunk = NULL,
    .chunk_size = 0,
    .chunk_start = 0,
    .current_position = {0, {0, 0}},
    .logger = {
      .payload = NULL,
      .log = NULL
    },
    .included_ranges = NULL,
    .included_range_count = 0,
    .current_included_range_index = 0,
    .did_get_column = false,
    .column_data = {
      .valid = false,
      .value = 0
    }
  };
  ts_lexer_set_included_ranges(self, NULL, 0);
}

void ts_lexer_delete(Lexer *self) {
  ts_free(self->included_ranges);
}

void ts_lexer_set_input(Lexer *self, TSInput input) {
  self->input = input;
  ts_lexer__clear_chunk(self);
  ts_lexer_goto(self, self->current_position);
}

// Move the lexer to the given position. This doesn't do any work
// if the parser is already at the given position.
void ts_lexer_reset(Lexer *self, Length position) {
  if (position.bytes != self->current_position.bytes) {
    ts_lexer_goto(self, position);
  }
}

void ts_lexer_start(Lexer *self) {
  self->token_start_position = self->current_position;
  self->token_end_position = LENGTH_UNDEFINED;
  self->data.result_symbol = 0;
  self->did_get_column = false;
  if (!ts_lexer__eof(&self->data)) {
    if (!self->chunk_size) ts_lexer__get_chunk(self);
    if (!self->lookahead_size) ts_lexer__get_lookahead(self);
    if (self->current_position.bytes == 0) {
      if (self->data.lookahead == BYTE_ORDER_MARK) {
        ts_lexer__advance(&self->data, true);
      }
      ts_lexer__set_column_data(self, 0);
    }
  }
}

void ts_lexer_finish(Lexer *self, uint32_t *lookahead_end_byte) {
  if (length_is_undefined(self->token_end_position)) {
    ts_lexer__mark_end(&self->data);
  }

  // If the token ended at an included range boundary, then its end position
  // will have been reset to the end of the preceding range. Reset the start
  // position to match.
  if (self->token_end_position.bytes < self->token_start_position.bytes) {
    self->token_start_position = self->token_end_position;
  }

  uint32_t current_lookahead_end_byte = self->current_position.bytes + 1;

  // In order to determine that a byte sequence is invalid UTF8 or UTF16,
  // the character decoding algorithm may have looked at the following byte.
  // Therefore, the next byte *after* the current (invalid) character
  // affects the interpretation of the current character.
  if (self->data.lookahead == TS_DECODE_ERROR) {
    current_lookahead_end_byte += 4; // the maximum number of bytes read to identify an invalid code point
  }

  if (current_lookahead_end_byte > *lookahead_end_byte) {
    *lookahead_end_byte = current_lookahead_end_byte;
  }
}

void ts_lexer_mark_end(Lexer *self) {
  ts_lexer__mark_end(&self->data);
}

bool ts_lexer_set_included_ranges(
  Lexer *self,
  const TSRange *ranges,
  uint32_t count
) {
  if (count == 0 || !ranges) {
    ranges = &DEFAULT_RANGE;
    count = 1;
  } else {
    uint32_t previous_byte = 0;
    for (unsigned i = 0; i < count; i++) {
      const TSRange *range = &ranges[i];
      if (
        range->start_byte < previous_byte ||
        range->end_byte < range->start_byte
      ) return false;
      previous_byte = range->end_byte;
    }
  }

  size_t size = count * sizeof(TSRange);
  self->included_ranges = ts_realloc(self->included_ranges, size);
  memcpy(self->included_ranges, ranges, size);
  self->included_range_count = count;
  ts_lexer_goto(self, self->current_position);
  return true;
}

TSRange *ts_lexer_included_ranges(const Lexer *self, uint32_t *count) {
  *count = self->included_range_count;
  return self->included_ranges;
}

#undef LOG
