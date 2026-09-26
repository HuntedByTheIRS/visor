// The stack's dot graph printer, split out of stack.c.

#include "./stack.h"

bool ts_stack_print_dot_graph(Stack *self, const TSLanguage *language, FILE *f) {
  array_reserve(&self->iterators, 32);
  if (!f) f = stderr;

  fprintf(f, "digraph stack {\n");
  fprintf(f, "rankdir=\"RL\";\n");
  fprintf(f, "edge [arrowhead=none]\n");

  Array(StackNode *) visited_nodes = array_new();

  array_clear(&self->iterators);
  for (uint32_t i = 0; i < self->heads.size; i++) {
    StackHead *head = array_get(&self->heads, i);
    if (head->status == StackStatusHalted) continue;

    fprintf(f, "node_head_%u [shape=none, label=\"\"]\n", i);
    fprintf(f, "node_head_%u -> node_%p [", i, (void *)head->node);

    if (head->status == StackStatusPaused) {
      fprintf(f, "color=red ");
    }
    fprintf(f,
      "label=%u, fontcolor=blue, weight=10000, labeltooltip=\"node_count: %u\nerror_cost: %u",
      i,
      ts_stack_node_count_since_error(self, i),
      ts_stack_error_cost(self, i)
    );

    if (head->summary) {
      fprintf(f, "\nsummary:");
      for (uint32_t j = 0; j < head->summary->size; j++) fprintf(f, " %u", array_get(head->summary, j)->state);
    }

    if (head->last_external_token.ptr) {
      const ExternalScannerState *state = &head->last_external_token.ptr->external_scanner_state;
      const char *data = ts_external_scanner_state_data(state);
      fprintf(f, "\nexternal_scanner_state:");
      for (uint32_t j = 0; j < state->length; j++) fprintf(f, " %2X", data[j]);
    }

    fprintf(f, "\"]\n");
    array_push(&self->iterators, ((StackIterator) {
      .node = head->node
    }));
  }

  bool all_iterators_done = false;
  while (!all_iterators_done) {
    all_iterators_done = true;

    for (uint32_t i = 0; i < self->iterators.size; i++) {
      StackIterator iterator = *array_get(&self->iterators, i);
      StackNode *node = iterator.node;

      for (uint32_t j = 0; j < visited_nodes.size; j++) {
        if (*array_get(&visited_nodes, j) == node) {
          node = NULL;
          break;
        }
      }

      if (!node) continue;
      all_iterators_done = false;

      fprintf(f, "node_%p [", (void *)node);
      if (node->state == ERROR_STATE) {
        fprintf(f, "label=\"?\"");
      } else if (
        node->link_count == 1 &&
        node->links[0].subtree.ptr &&
        ts_subtree_extra(node->links[0].subtree)
      ) {
        fprintf(f, "shape=point margin=0 label=\"\"");
      } else {
        fprintf(f, "label=\"%d\"", node->state);
      }

      fprintf(
        f,
        " tooltip=\"position: %u,%u\nnode_count:%u\nerror_cost: %u\ndynamic_precedence: %d\"];\n",
        node->position.extent.row + 1,
        node->position.extent.column,
        node->node_count,
        node->error_cost,
        node->dynamic_precedence
      );

      for (int j = 0; j < node->link_count; j++) {
        StackLink link = node->links[j];
        fprintf(f, "node_%p -> node_%p [", (void *)node, (void *)link.node);
        if (link.is_pending) fprintf(f, "style=dashed ");
        if (link.subtree.ptr && ts_subtree_extra(link.subtree)) fprintf(f, "fontcolor=gray ");

        if (!link.subtree.ptr) {
          fprintf(f, "color=red");
        } else {
          fprintf(f, "label=\"");
          bool quoted = ts_subtree_visible(link.subtree) && !ts_subtree_named(link.subtree);
          if (quoted) fprintf(f, "'");
          ts_language_write_symbol_as_dot_string(language, f, ts_subtree_symbol(link.subtree));
          if (quoted) fprintf(f, "'");
          fprintf(f, "\"");
          fprintf(
            f,
            "labeltooltip=\"error_cost: %u\ndynamic_precedence: %" PRId32 "\"",
            ts_subtree_error_cost(link.subtree),
            ts_subtree_dynamic_precedence(link.subtree)
          );
        }

        fprintf(f, "];\n");

        StackIterator *next_iterator;
        if (j == 0) {
          next_iterator = array_get(&self->iterators, i);
        } else {
          array_push(&self->iterators, iterator);
          next_iterator = array_back(&self->iterators);
        }
        next_iterator->node = link.node;
      }

      array_push(&visited_nodes, node);
    }
  }

  fprintf(f, "}\n");

  array_delete(&visited_nodes);
  return true;
}

#undef forceinline
