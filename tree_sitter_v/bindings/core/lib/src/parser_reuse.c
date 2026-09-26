// Node reuse and version selection during a parse, split out of parser.c.

#include "./parser.h"

static Subtree ts_parser__reuse_node(
  TSParser *self,
  StackVersion version,
  TSStateId *state,
  uint32_t position,
  Subtree last_external_token,
  TableEntry *table_entry
) {
  Subtree result;
  while ((result = reusable_node_tree(&self->reusable_node)).ptr) {
    uint32_t byte_offset = reusable_node_byte_offset(&self->reusable_node);
    uint32_t end_byte_offset = byte_offset + ts_subtree_total_bytes(result);

    // Do not reuse an EOF node if the included ranges array has changes
    // later on in the file.
    if (ts_subtree_is_eof(result)) end_byte_offset = UINT32_MAX;

    if (byte_offset > position) {
      LOG("before_reusable_node symbol:%s", TREE_NAME(result));
      break;
    }

    if (byte_offset < position) {
      LOG("past_reusable_node symbol:%s", TREE_NAME(result));
      if (end_byte_offset <= position || !reusable_node_descend(&self->reusable_node)) {
        reusable_node_advance(&self->reusable_node);
      }
      continue;
    }

    if (!ts_subtree_external_scanner_state_eq(self->reusable_node.last_external_token, last_external_token)) {
      LOG("reusable_node_has_different_external_scanner_state symbol:%s", TREE_NAME(result));
      reusable_node_advance(&self->reusable_node);
      continue;
    }

    const char *reason = NULL;
    if (ts_subtree_has_changes(result)) {
      reason = "has_changes";
    } else if (ts_subtree_is_error(result)) {
      reason = "is_error";
    } else if (ts_subtree_missing(result)) {
      reason = "is_missing";
    } else if (ts_subtree_is_fragile(result)) {
      reason = "is_fragile";
    } else if (ts_parser__has_included_range_difference(self, byte_offset, end_byte_offset)) {
      reason = "contains_different_included_range";
    }

    if (reason) {
      LOG("cant_reuse_node_%s tree:%s", reason, TREE_NAME(result));
      if (!reusable_node_descend(&self->reusable_node)) {
        reusable_node_advance(&self->reusable_node);
        ts_parser__breakdown_top_of_stack(self, version);
        *state = ts_stack_state(self->stack, version);
      }
      continue;
    }

    TSSymbol leaf_symbol = ts_subtree_leaf_symbol(result);
    ts_language_table_entry(self->language, *state, leaf_symbol, table_entry);
    if (!ts_parser__can_reuse_first_leaf(self, *state, result, table_entry)) {
      LOG(
        "cant_reuse_node symbol:%s, first_leaf_symbol:%s",
        TREE_NAME(result),
        SYM_NAME(leaf_symbol)
      );
      reusable_node_advance_past_leaf(&self->reusable_node);
      break;
    }

    LOG("reuse_node symbol:%s", TREE_NAME(result));
    ts_subtree_retain(result);
    return result;
  }

  return NULL_SUBTREE;
}

// Determine if a given tree should be replaced by an alternative tree.
//
// The decision is based on the trees' error costs (if any), their dynamic precedence,
// and finally, as a default, by a recursive comparison of the trees' symbols.
static bool ts_parser__select_tree(TSParser *self, Subtree left, Subtree right) {
  if (!left.ptr) return true;
  if (!right.ptr) return false;

  if (ts_subtree_error_cost(right) < ts_subtree_error_cost(left)) {
    LOG("select_smaller_error symbol:%s, over_symbol:%s", TREE_NAME(right), TREE_NAME(left));
    return true;
  }

  if (ts_subtree_error_cost(left) < ts_subtree_error_cost(right)) {
    LOG("select_smaller_error symbol:%s, over_symbol:%s", TREE_NAME(left), TREE_NAME(right));
    return false;
  }

  if (ts_subtree_dynamic_precedence(right) > ts_subtree_dynamic_precedence(left)) {
    LOG("select_higher_precedence symbol:%s, prec:%" PRId32 ", over_symbol:%s, other_prec:%" PRId32,
        TREE_NAME(right), ts_subtree_dynamic_precedence(right), TREE_NAME(left),
        ts_subtree_dynamic_precedence(left));
    return true;
  }

  if (ts_subtree_dynamic_precedence(left) > ts_subtree_dynamic_precedence(right)) {
    LOG("select_higher_precedence symbol:%s, prec:%" PRId32 ", over_symbol:%s, other_prec:%" PRId32,
        TREE_NAME(left), ts_subtree_dynamic_precedence(left), TREE_NAME(right),
        ts_subtree_dynamic_precedence(right));
    return false;
  }

  if (ts_subtree_error_cost(left) > 0) return true;

  int comparison = ts_subtree_compare(left, right, &self->tree_pool);
  switch (comparison) {
    case -1:
      LOG("select_earlier symbol:%s, over_symbol:%s", TREE_NAME(left), TREE_NAME(right));
      return false;
      break;
    case 1:
      LOG("select_earlier symbol:%s, over_symbol:%s", TREE_NAME(right), TREE_NAME(left));
      return true;
    default:
      LOG("select_existing symbol:%s, over_symbol:%s", TREE_NAME(left), TREE_NAME(right));
      return false;
  }
}

// Determine if a given tree's children should be replaced by an alternative
// array of children.
static bool ts_parser__select_children(
  TSParser *self,
  Subtree left,
  const SubtreeArray *children
) {
  array_assign(&self->scratch_trees, children);

  // Create a temporary subtree using the scratch trees array. This node does
  // not perform any allocation except for possibly growing the array to make
  // room for its own heap data. The scratch tree is never explicitly released,
  // so the same 'scratch trees' array can be reused again later.
  MutableSubtree scratch_tree = ts_subtree_new_node(
    ts_subtree_symbol(left),
    &self->scratch_trees,
    0,
    self->language
  );

  return ts_parser__select_tree(
    self,
    left,
    ts_subtree_from_mut(scratch_tree)
  );
}

static void ts_parser__shift(
  TSParser *self,
  StackVersion version,
  TSStateId state,
  Subtree lookahead,
  bool extra
) {
  bool is_leaf = ts_subtree_child_count(lookahead) == 0;
  Subtree subtree_to_push = lookahead;
  if (extra != ts_subtree_extra(lookahead) && is_leaf) {
    MutableSubtree result = ts_subtree_make_mut(&self->tree_pool, lookahead);
    ts_subtree_set_extra(&result, extra);
    subtree_to_push = ts_subtree_from_mut(result);
  }

  ts_stack_push(self->stack, version, subtree_to_push, !is_leaf, state);
  if (ts_subtree_has_external_tokens(subtree_to_push)) {
    ts_stack_set_last_external_token(
      self->stack, version, ts_subtree_last_external_token(subtree_to_push)
    );
  }
}
