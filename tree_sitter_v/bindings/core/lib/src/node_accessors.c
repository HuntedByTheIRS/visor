// Node accessors and the range walkers behind them, from node.c.

#include "./point.h"
#include "./subtree.h"
#include "./tree.h"
#include "./language.h"

static inline TSNode ts_node__first_child_for_byte(
  TSNode self,
  uint32_t goal,
  bool include_anonymous
) {
  TSNode node = self;
  bool did_descend = true;

  NodeChildIterator last_iterator;
  bool has_last_iterator = false;

  while (did_descend) {
    did_descend = false;

    TSNode child;
    NodeChildIterator iterator = ts_node_iterate_children(&node);
  loop:
    while (ts_node_child_iterator_next(&iterator, &child)) {
      if (ts_node_end_byte(child) > goal) {
        if (ts_node__is_relevant(child, include_anonymous)) {
          return child;
        } else if (ts_node_child_count(child) > 0) {
          if (iterator.child_index < ts_subtree_child_count(ts_node__subtree(child))) {
            last_iterator = iterator;
            has_last_iterator = true;
          }
          did_descend = true;
          node = child;
          break;
        }
      }
    }

    if (!did_descend && has_last_iterator) {
      iterator = last_iterator;
      has_last_iterator = false;
      goto loop;
    }
  }

  return ts_node__null();
}

static inline TSNode ts_node__descendant_for_byte_range(
  TSNode self,
  uint32_t range_start,
  uint32_t range_end,
  bool include_anonymous
) {
  if (range_start > range_end) {
    return ts_node__null();
  }
  TSNode node = self;
  TSNode last_visible_node = self;

  bool did_descend = true;
  while (did_descend) {
    did_descend = false;

    TSNode child;
    NodeChildIterator iterator = ts_node_iterate_children(&node);
    while (ts_node_child_iterator_next(&iterator, &child)) {
      uint32_t node_end = iterator.position.bytes;

      // The end of this node must extend far enough forward to touch
      // the end of the range
      if (node_end < range_end) continue;

      // ...and exceed the start of the range, unless the node itself is
      // empty, in which case it must at least be equal to the start of the range.
      bool is_empty = ts_node_start_byte(child) == node_end;
      if (is_empty ? node_end < range_start : node_end <= range_start) continue;

      // The start of this node must extend far enough backward to
      // touch the start of the range.
      if (range_start < ts_node_start_byte(child)) break;

      node = child;
      if (ts_node__is_relevant(node, include_anonymous)) {
        last_visible_node = node;
      }
      did_descend = true;
      break;
    }
  }

  return last_visible_node;
}

static inline TSNode ts_node__descendant_for_point_range(
  TSNode self,
  TSPoint range_start,
  TSPoint range_end,
  bool include_anonymous
) {
  if (point_gt(range_start, range_end)) {
    return ts_node__null();
  }
  TSNode node = self;
  TSNode last_visible_node = self;

  bool did_descend = true;
  while (did_descend) {
    did_descend = false;

    TSNode child;
    NodeChildIterator iterator = ts_node_iterate_children(&node);
    while (ts_node_child_iterator_next(&iterator, &child)) {
      TSPoint node_end = iterator.position.extent;

      // The end of this node must extend far enough forward to touch
      // the end of the range
      if (point_lt(node_end, range_end)) continue;

      // ...and exceed the start of the range, unless the node itself is
      // empty, in which case it must at least be equal to the start of the range.
      bool is_empty =  point_eq(ts_node_start_point(child), node_end);
      if (is_empty ? point_lt(node_end, range_start) : point_lte(node_end, range_start)) {
        continue;
      }

      // The start of this node must extend far enough backward to
      // touch the start of the range.
      if (point_lt(range_start, ts_node_start_point(child))) break;

      node = child;
      if (ts_node__is_relevant(node, include_anonymous)) {
        last_visible_node = node;
      }
      did_descend = true;
      break;
    }
  }

  return last_visible_node;
}

// TSNode - public

uint32_t ts_node_end_byte(TSNode self) {
  return ts_node_start_byte(self) + ts_subtree_size(ts_node__subtree(self)).bytes;
}

TSPoint ts_node_end_point(TSNode self) {
  return point_add(ts_node_start_point(self), ts_subtree_size(ts_node__subtree(self)).extent);
}

TSSymbol ts_node_symbol(TSNode self) {
  TSSymbol symbol = ts_node__alias(&self);
  if (!symbol) symbol = ts_subtree_symbol(ts_node__subtree(self));
  return ts_language_public_symbol(self.tree->language, symbol);
}

const char *ts_node_type(TSNode self) {
  TSSymbol symbol = ts_node__alias(&self);
  if (!symbol) symbol = ts_subtree_symbol(ts_node__subtree(self));
  return ts_language_symbol_name(self.tree->language, symbol);
}

const TSLanguage *ts_node_language(TSNode self) {
  return self.tree->language;
}

TSSymbol ts_node_grammar_symbol(TSNode self) {
  return ts_subtree_symbol(ts_node__subtree(self));
}

const char *ts_node_grammar_type(TSNode self) {
  TSSymbol symbol = ts_subtree_symbol(ts_node__subtree(self));
  return ts_language_symbol_name(self.tree->language, symbol);
}

char *ts_node_string(TSNode self) {
  TSSymbol alias_symbol = ts_node__alias(&self);
  return ts_subtree_string(
    ts_node__subtree(self),
    alias_symbol,
    ts_language_symbol_metadata(self.tree->language, alias_symbol).visible,
    self.tree->language,
    false
  );
}

bool ts_node_eq(TSNode self, TSNode other) {
  return self.tree == other.tree && self.id == other.id;
}

bool ts_node_is_null(TSNode self) {
  return self.id == 0;
}

bool ts_node_is_extra(TSNode self) {
  return ts_subtree_extra(ts_node__subtree(self));
}

bool ts_node_is_named(TSNode self) {
  TSSymbol alias = ts_node__alias(&self);
  return alias
    ? ts_language_symbol_metadata(self.tree->language, alias).named
    : ts_subtree_named(ts_node__subtree(self));
}

bool ts_node_is_missing(TSNode self) {
  return ts_subtree_missing(ts_node__subtree(self));
}

bool ts_node_has_changes(TSNode self) {
  return ts_subtree_has_changes(ts_node__subtree(self));
}

bool ts_node_has_error(TSNode self) {
  return ts_subtree_error_cost(ts_node__subtree(self)) > 0;
}

bool ts_node_is_error(TSNode self) {
  TSSymbol symbol = ts_node_symbol(self);
  return symbol == ts_builtin_sym_error;
}

uint32_t ts_node_descendant_count(TSNode self) {
  return ts_subtree_visible_descendant_count(ts_node__subtree(self)) + 1;
}

TSStateId ts_node_parse_state(TSNode self) {
  return ts_subtree_parse_state(ts_node__subtree(self));
}

TSStateId ts_node_next_parse_state(TSNode self) {
  const TSLanguage *language = self.tree->language;
  uint16_t state = ts_node_parse_state(self);
  if (state == TS_TREE_STATE_NONE) {
    return TS_TREE_STATE_NONE;
  }
  uint16_t symbol = ts_node_grammar_symbol(self);
  return ts_language_next_state(language, state, symbol);
}

TSNode ts_node_parent(TSNode self) {
  TSNode node = ts_tree_root_node(self.tree);
  if (node.id == self.id) return ts_node__null();

  while (true) {
    TSNode next_node = ts_node_child_with_descendant(node, self);
    if (next_node.id == self.id || ts_node_is_null(next_node)) break;
    node = next_node;
  }

  return node;
}
