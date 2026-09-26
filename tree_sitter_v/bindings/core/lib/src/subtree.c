#include <ctype.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdio.h>
#include "./alloc.h"
#include "./array.h"
#include "./atomic.h"
#include "./subtree.h"
#include "./length.h"
#include "./language.h"
#include "./error_costs.h"
#include "./ts_assert.h"
#include <stddef.h>

typedef struct {
  Length start;
  Length old_end;
  Length new_end;
} Edit;

#define TS_MAX_INLINE_TREE_LENGTH UINT8_MAX
#define TS_MAX_TREE_POOL_SIZE 32

// ExternalScannerState

void ts_external_scanner_state_init(ExternalScannerState *self, const char *data, unsigned length) {
  self->length = length;
  if (length > sizeof(self->short_data)) {
    self->long_data = ts_malloc(length);
    memcpy(self->long_data, data, length);
  } else {
    memcpy(self->short_data, data, length);
  }
}

ExternalScannerState ts_external_scanner_state_copy(const ExternalScannerState *self) {
  ExternalScannerState result = *self;
  if (self->length > sizeof(self->short_data)) {
    result.long_data = ts_malloc(self->length);
    memcpy(result.long_data, self->long_data, self->length);
  }
  return result;
}

void ts_external_scanner_state_delete(ExternalScannerState *self) {
  if (self->length > sizeof(self->short_data)) {
    ts_free(self->long_data);
  }
}

const char *ts_external_scanner_state_data(const ExternalScannerState *self) {
  if (self->length > sizeof(self->short_data)) {
    return self->long_data;
  } else {
    return self->short_data;
  }
}

bool ts_external_scanner_state_eq(const ExternalScannerState *self, const char *buffer, unsigned length) {
  return
    self->length == length &&
    memcmp(ts_external_scanner_state_data(self), buffer, length) == 0;
}

// SubtreeArray

void ts_subtree_array_copy(SubtreeArray self, SubtreeArray *dest) {
  dest->size = self.size;
  dest->capacity = self.capacity;
  dest->contents = self.contents;
  if (self.capacity > 0) {
    dest->contents = ts_calloc(self.capacity, sizeof(Subtree));
    memcpy(dest->contents, self.contents, self.size * sizeof(Subtree));
    for (uint32_t i = 0; i < self.size; i++) {
      ts_subtree_retain(*array_get(dest, i));
    }
  }
}

void ts_subtree_array_clear(SubtreePool *pool, SubtreeArray *self) {
  for (uint32_t i = 0; i < self->size; i++) {
    ts_subtree_release(pool, *array_get(self, i));
  }
  array_clear(self);
}

void ts_subtree_array_delete(SubtreePool *pool, SubtreeArray *self) {
  ts_subtree_array_clear(pool, self);
  array_delete(self);
}

void ts_subtree_array_remove_trailing_extras(
  SubtreeArray *self,
  SubtreeArray *destination
) {
  array_clear(destination);
  while (self->size > 0) {
    Subtree last = *array_get(self, self->size - 1);
    if (ts_subtree_extra(last)) {
      self->size--;
      array_push(destination, last);
    } else {
      break;
    }
  }
  ts_subtree_array_reverse(destination);
}

void ts_subtree_array_reverse(SubtreeArray *self) {
  for (uint32_t i = 0, limit = self->size / 2; i < limit; i++) {
    size_t reverse_index = self->size - 1 - i;
    Subtree swap = *array_get(self, i);
    *array_get(self, i) = *array_get(self, reverse_index);
    *array_get(self, reverse_index) = swap;
  }
}

// SubtreePool

SubtreePool ts_subtree_pool_new(uint32_t capacity) {
  SubtreePool self = {array_new(), array_new()};
  array_reserve(&self.free_trees, capacity);
  return self;
}

void ts_subtree_pool_delete(SubtreePool *self) {
  if (self->free_trees.contents) {
    for (unsigned i = 0; i < self->free_trees.size; i++) {
      ts_free(array_get(&self->free_trees, i)->ptr);
    }
    array_delete(&self->free_trees);
  }
  if (self->tree_stack.contents) array_delete(&self->tree_stack);
}

static SubtreeHeapData *ts_subtree_pool_allocate(SubtreePool *self) {
  if (self->free_trees.size > 0) {
    return array_pop(&self->free_trees).ptr;
  } else {
    return ts_malloc(sizeof(SubtreeHeapData));
  }
}

static void ts_subtree_pool_free(SubtreePool *self, SubtreeHeapData *tree) {
  if (self->free_trees.capacity > 0 && self->free_trees.size + 1 <= TS_MAX_TREE_POOL_SIZE) {
    array_push(&self->free_trees, (MutableSubtree) {.ptr = tree});
  } else {
    ts_free(tree);
  }
}

// Subtree

static inline bool ts_subtree_can_inline(Length padding, Length size, uint32_t lookahead_bytes) {
  return
    padding.bytes < TS_MAX_INLINE_TREE_LENGTH &&
    padding.extent.row < 16 &&
    padding.extent.column < TS_MAX_INLINE_TREE_LENGTH &&
    size.bytes < TS_MAX_INLINE_TREE_LENGTH &&
    size.extent.row == 0 &&
    size.extent.column < TS_MAX_INLINE_TREE_LENGTH &&
    lookahead_bytes < 16;
}

Subtree ts_subtree_new_leaf(
  SubtreePool *pool, TSSymbol symbol, Length padding, Length size,
  uint32_t lookahead_bytes, TSStateId parse_state,
  bool has_external_tokens, bool depends_on_column,
  bool is_keyword, const TSLanguage *language
) {
  TSSymbolMetadata metadata = ts_language_symbol_metadata(language, symbol);
  bool extra = symbol == ts_builtin_sym_end;

  bool is_inline = (
    symbol <= UINT8_MAX &&
    !has_external_tokens &&
    ts_subtree_can_inline(padding, size, lookahead_bytes)
  );

  if (is_inline) {
    return (Subtree) {{
      .parse_state = parse_state,
      .symbol = symbol,
      .padding_bytes = padding.bytes,
      .padding_rows = padding.extent.row,
      .padding_columns = padding.extent.column,
      .size_bytes = size.bytes,
      .lookahead_bytes = lookahead_bytes,
      .visible = metadata.visible,
      .named = metadata.named,
      .extra = extra,
      .has_changes = false,
      .is_missing = false,
      .is_keyword = is_keyword,
      .is_inline = true,
    }};
  } else {
    SubtreeHeapData *data = ts_subtree_pool_allocate(pool);
    *data = (SubtreeHeapData) {
      .ref_count = 1,
      .padding = padding,
      .size = size,
      .lookahead_bytes = lookahead_bytes,
      .error_cost = 0,
      .child_count = 0,
      .symbol = symbol,
      .parse_state = parse_state,
      .visible = metadata.visible,
      .named = metadata.named,
      .extra = extra,
      .fragile_left = false,
      .fragile_right = false,
      .has_changes = false,
      .has_external_tokens = has_external_tokens,
      .has_external_scanner_state_change = false,
      .depends_on_column = depends_on_column,
      .is_missing = false,
      .is_keyword = is_keyword,
      {{.first_leaf = {.symbol = 0, .parse_state = 0}}}
    };
    return (Subtree) {.ptr = data};
  }
}

void ts_subtree_set_symbol(
  MutableSubtree *self,
  TSSymbol symbol,
  const TSLanguage *language
) {
  TSSymbolMetadata metadata = ts_language_symbol_metadata(language, symbol);
  if (self->data.is_inline) {
    ts_assert(symbol < UINT8_MAX);
    self->data.symbol = symbol;
    self->data.named = metadata.named;
    self->data.visible = metadata.visible;
  } else {
    self->ptr->symbol = symbol;
    self->ptr->named = metadata.named;
    self->ptr->visible = metadata.visible;
  }
}

Subtree ts_subtree_new_error(
  SubtreePool *pool, int32_t lookahead_char, Length padding, Length size,
  uint32_t bytes_scanned, TSStateId parse_state, const TSLanguage *language
) {
  Subtree result = ts_subtree_new_leaf(
    pool, ts_builtin_sym_error, padding, size, bytes_scanned,
    parse_state, false, false, false, language
  );
  SubtreeHeapData *data = (SubtreeHeapData *)result.ptr;
  data->fragile_left = true;
  data->fragile_right = true;
  data->lookahead_char = lookahead_char;
  return result;
}

// Clone a subtree.
MutableSubtree ts_subtree_clone(Subtree self) {
  size_t alloc_size = ts_subtree_alloc_size(self.ptr->child_count);
  Subtree *new_children = ts_malloc(alloc_size);
  Subtree *old_children = ts_subtree_children(self);
  memcpy(new_children, old_children, alloc_size);
  SubtreeHeapData *result = (SubtreeHeapData *)&new_children[self.ptr->child_count];
  if (self.ptr->child_count > 0) {
    for (uint32_t i = 0; i < self.ptr->child_count; i++) {
      ts_subtree_retain(new_children[i]);
    }
  } else if (self.ptr->has_external_tokens) {
    result->external_scanner_state = ts_external_scanner_state_copy(
      &self.ptr->external_scanner_state
    );
  }
  result->ref_count = 1;
  return (MutableSubtree) {.ptr = result};
}

// Get mutable version of a subtree.
//
// This takes ownership of the subtree. If the subtree has only one owner,
// this will directly convert it into a mutable version. Otherwise, it will
// perform a copy.
MutableSubtree ts_subtree_make_mut(SubtreePool *pool, Subtree self) {
  if (self.data.is_inline) return (MutableSubtree) {self.data};
  if (self.ptr->ref_count == 1) return ts_subtree_to_mut_unsafe(self);
  MutableSubtree result = ts_subtree_clone(self);
  ts_subtree_release(pool, self);
  return result;
}
