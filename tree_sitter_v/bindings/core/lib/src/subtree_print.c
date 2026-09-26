// Printing subtrees, split out of subtree.c.

#include "./subtree.h"

static size_t ts_subtree__write_char_to_string(char *str, size_t n, int32_t chr) {
  if (chr == -1)
    return snprintf(str, n, "INVALID");
  else if (chr == '\0')
    return snprintf(str, n, "'\\0'");
  else if (chr == '\n')
    return snprintf(str, n, "'\\n'");
  else if (chr == '\t')
    return snprintf(str, n, "'\\t'");
  else if (chr == '\r')
    return snprintf(str, n, "'\\r'");
  else if (0 < chr && chr < 128 && isprint(chr))
    return snprintf(str, n, "'%c'", chr);
  else
    return snprintf(str, n, "%d", chr);
}

static const char *const ROOT_FIELD = "__ROOT__";

static size_t ts_subtree__write_to_string(
  Subtree self, char *string, size_t limit,
  const TSLanguage *language, bool include_all,
  TSSymbol alias_symbol, bool alias_is_named, const char *field_name
) {
  if (!self.ptr) return snprintf(string, limit, "(NULL)");

  char *cursor = string;
  char **writer = (limit > 1) ? &cursor : &string;
  bool is_root = field_name == ROOT_FIELD;
  bool is_visible =
    include_all ||
    ts_subtree_missing(self) ||
    (
      alias_symbol
        ? alias_is_named
        : ts_subtree_visible(self) && ts_subtree_named(self)
    );

  if (is_visible) {
    if (!is_root) {
      cursor += snprintf(*writer, limit, " ");
      if (field_name) {
        cursor += snprintf(*writer, limit, "%s: ", field_name);
      }
    }

    if (ts_subtree_is_error(self) && ts_subtree_child_count(self) == 0 && self.ptr->size.bytes > 0) {
      cursor += snprintf(*writer, limit, "(UNEXPECTED ");
      cursor += ts_subtree__write_char_to_string(*writer, limit, self.ptr->lookahead_char);
    } else {
      TSSymbol symbol = alias_symbol ? alias_symbol : ts_subtree_symbol(self);
      const char *symbol_name = ts_language_symbol_name(language, symbol);
      if (ts_subtree_missing(self)) {
        cursor += snprintf(*writer, limit, "(MISSING ");
        if (alias_is_named || ts_subtree_named(self)) {
          cursor += snprintf(*writer, limit, "%s", symbol_name);
        } else {
          cursor += snprintf(*writer, limit, "\"%s\"", symbol_name);
        }
      } else {
        cursor += snprintf(*writer, limit, "(%s", symbol_name);
      }
    }
  } else if (is_root) {
    TSSymbol symbol = alias_symbol ? alias_symbol : ts_subtree_symbol(self);
    const char *symbol_name = ts_language_symbol_name(language, symbol);
    if (ts_subtree_child_count(self) > 0) {
      cursor += snprintf(*writer, limit, "(%s", symbol_name);
    } else if (ts_subtree_named(self)) {
      cursor += snprintf(*writer, limit, "(%s)", symbol_name);
    } else {
      cursor += snprintf(*writer, limit, "(\"%s\")", symbol_name);
    }
  }

  if (ts_subtree_child_count(self)) {
    const TSSymbol *alias_sequence = ts_language_alias_sequence(language, self.ptr->production_id);
    const TSFieldMapEntry *field_map, *field_map_end;
    ts_language_field_map(
      language,
      self.ptr->production_id,
      &field_map,
      &field_map_end
    );

    uint32_t structural_child_index = 0;
    for (uint32_t i = 0; i < self.ptr->child_count; i++) {
      Subtree child = ts_subtree_children(self)[i];
      if (ts_subtree_extra(child)) {
        cursor += ts_subtree__write_to_string(
          child, *writer, limit,
          language, include_all,
          0, false, NULL
        );
      } else {
        TSSymbol subtree_alias_symbol = alias_sequence
          ? alias_sequence[structural_child_index]
          : 0;
        bool subtree_alias_is_named = subtree_alias_symbol
          ? ts_language_symbol_metadata(language, subtree_alias_symbol).named
          : false;

        const char *child_field_name = is_visible ? NULL : field_name;
        for (const TSFieldMapEntry *map = field_map; map < field_map_end; map++) {
          if (!map->inherited && map->child_index == structural_child_index) {
            child_field_name = language->field_names[map->field_id];
            break;
          }
        }

        cursor += ts_subtree__write_to_string(
          child, *writer, limit,
          language, include_all,
          subtree_alias_symbol, subtree_alias_is_named, child_field_name
        );
        structural_child_index++;
      }
    }
  }

  if (is_visible) cursor += snprintf(*writer, limit, ")");

  return cursor - string;
}

char *ts_subtree_string(
  Subtree self,
  TSSymbol alias_symbol,
  bool alias_is_named,
  const TSLanguage *language,
  bool include_all
) {
  char scratch_string[1];
  size_t size = ts_subtree__write_to_string(
    self, scratch_string, 1,
    language, include_all,
    alias_symbol, alias_is_named, ROOT_FIELD
  ) + 1;
  char *result = ts_malloc(size * sizeof(char));
  ts_subtree__write_to_string(
    self, result, size,
    language, include_all,
    alias_symbol, alias_is_named, ROOT_FIELD
  );
  return result;
}

void ts_subtree__print_dot_graph(const Subtree *self, uint32_t start_offset,
                                 const TSLanguage *language, TSSymbol alias_symbol,
                                 FILE *f) {
  TSSymbol subtree_symbol = ts_subtree_symbol(*self);
  TSSymbol symbol = alias_symbol ? alias_symbol : subtree_symbol;
  uint32_t end_offset = start_offset + ts_subtree_total_bytes(*self);
  fprintf(f, "tree_%p [label=\"", (void *)self);
  ts_language_write_symbol_as_dot_string(language, f, symbol);
  fprintf(f, "\"");

  if (ts_subtree_child_count(*self) == 0) fprintf(f, ", shape=plaintext");
  if (ts_subtree_extra(*self)) fprintf(f, ", fontcolor=gray");
  if (ts_subtree_has_changes(*self)) fprintf(f, ", color=green, penwidth=2");

  fprintf(f, ", tooltip=\""
    "range: %u - %u\n"
    "state: %d\n"
    "error-cost: %u\n"
    "has-changes: %u\n"
    "depends-on-column: %u\n"
    "descendant-count: %u\n"
    "repeat-depth: %u\n"
    "lookahead-bytes: %u",
    start_offset, end_offset,
    ts_subtree_parse_state(*self),
    ts_subtree_error_cost(*self),
    ts_subtree_has_changes(*self),
    ts_subtree_depends_on_column(*self),
    ts_subtree_visible_descendant_count(*self),
    ts_subtree_repeat_depth(*self),
    ts_subtree_lookahead_bytes(*self)
  );

  if (ts_subtree_is_error(*self) && ts_subtree_child_count(*self) == 0 && self->ptr->lookahead_char != 0) {
    fprintf(f, "\ncharacter: '%c'", self->ptr->lookahead_char);
  }

  fprintf(f, "\"]\n");

  uint32_t child_start_offset = start_offset;
  uint32_t child_info_offset =
    language->max_alias_sequence_length *
    ts_subtree_production_id(*self);
  for (uint32_t i = 0, n = ts_subtree_child_count(*self); i < n; i++) {
    const Subtree *child = &ts_subtree_children(*self)[i];
    TSSymbol subtree_alias_symbol = 0;
    if (!ts_subtree_extra(*child) && child_info_offset) {
      subtree_alias_symbol = language->alias_sequences[child_info_offset];
      child_info_offset++;
    }
    ts_subtree__print_dot_graph(child, child_start_offset, language, subtree_alias_symbol, f);
    fprintf(f, "tree_%p -> tree_%p [tooltip=%u]\n", (void *)self, (void *)child, i);
    child_start_offset += ts_subtree_total_bytes(*child);
  }
}

void ts_subtree_print_dot_graph(Subtree self, const TSLanguage *language, FILE *f) {
  fprintf(f, "digraph tree {\n");
  fprintf(f, "edge [arrowhead=none]\n");
  ts_subtree__print_dot_graph(&self, 0, language, 0, f);
  fprintf(f, "}\n");
}

const ExternalScannerState *ts_subtree_external_scanner_state(Subtree self) {
  static const ExternalScannerState empty_state = {{.short_data = {0}}, .length = 0};
  if (
    self.ptr &&
    !self.data.is_inline &&
    self.ptr->has_external_tokens &&
    self.ptr->child_count == 0
  ) {
    return &self.ptr->external_scanner_state;
  } else {
    return &empty_state;
  }
}

bool ts_subtree_external_scanner_state_eq(Subtree self, Subtree other) {
  const ExternalScannerState *state_self = ts_subtree_external_scanner_state(self);
  const ExternalScannerState *state_other = ts_subtree_external_scanner_state(other);
  return ts_external_scanner_state_eq(
    state_self,
    ts_external_scanner_state_data(state_other),
    state_other->length
  );
}
