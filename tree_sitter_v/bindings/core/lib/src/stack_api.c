// The stack's accessor surface: versions, pops, summaries, merging.

#include "./stack.h"

uint32_t ts_stack_version_count(const Stack *self) {
  return self->heads.size;
}

uint32_t ts_stack_halted_version_count(Stack *self) {
  uint32_t count = 0;
  for (uint32_t i = 0; i < self->heads.size; i++) {
    StackHead *head = array_get(&self->heads, i);
    if (head->status == StackStatusHalted) {
      count++;
    }
  }
  return count;
}

TSStateId ts_stack_state(const Stack *self, StackVersion version) {
  return array_get(&self->heads, version)->node->state;
}

Length ts_stack_position(const Stack *self, StackVersion version) {
  return array_get(&self->heads, version)->node->position;
}

Subtree ts_stack_last_external_token(const Stack *self, StackVersion version) {
  return array_get(&self->heads, version)->last_external_token;
}

void ts_stack_set_last_external_token(Stack *self, StackVersion version, Subtree token) {
  StackHead *head = array_get(&self->heads, version);
  if (token.ptr) ts_subtree_retain(token);
  if (head->last_external_token.ptr) ts_subtree_release(self->subtree_pool, head->last_external_token);
  head->last_external_token = token;
}

unsigned ts_stack_error_cost(const Stack *self, StackVersion version) {
  StackHead *head = array_get(&self->heads, version);
  unsigned result = head->node->error_cost;
  if (
    head->status == StackStatusPaused ||
    (head->node->state == ERROR_STATE && !head->node->links[0].subtree.ptr)) {
    result += ERROR_COST_PER_RECOVERY;
  }
  return result;
}

unsigned ts_stack_node_count_since_error(const Stack *self, StackVersion version) {
  StackHead *head = array_get(&self->heads, version);
  if (head->node->node_count < head->node_count_at_last_error) {
    head->node_count_at_last_error = head->node->node_count;
  }
  return head->node->node_count - head->node_count_at_last_error;
}

void ts_stack_push(
  Stack *self,
  StackVersion version,
  Subtree subtree,
  bool pending,
  TSStateId state
) {
  StackHead *head = array_get(&self->heads, version);
  StackNode *new_node = stack_node_new(head->node, subtree, pending, state, &self->node_pool);
  if (!subtree.ptr) head->node_count_at_last_error = new_node->node_count;
  head->node = new_node;
}

forceinline StackAction pop_count_callback(void *payload, const StackIterator *iterator) {
  unsigned *goal_subtree_count = payload;
  if (iterator->subtree_count == *goal_subtree_count) {
    return StackActionPop | StackActionStop;
  } else {
    return StackActionNone;
  }
}

StackSliceArray ts_stack_pop_count(Stack *self, StackVersion version, uint32_t count) {
  return stack__iter(self, version, pop_count_callback, &count, (int)count);
}


forceinline StackAction pop_pending_callback(void *payload, const StackIterator *iterator) {
  (void)payload;
  if (iterator->subtree_count >= 1) {
    if (iterator->is_pending) {
      return StackActionPop | StackActionStop;
    } else {
      return StackActionStop;
    }
  } else {
    return StackActionNone;
  }
}

StackSliceArray ts_stack_pop_pending(Stack *self, StackVersion version) {
  StackSliceArray pop = stack__iter(self, version, pop_pending_callback, NULL, 0);
  if (pop.size > 0) {
    ts_stack_renumber_version(self, array_get(&pop, 0)->version, version);
    array_get(&pop, 0)->version = version;
  }
  return pop;
}

forceinline StackAction pop_error_callback(void *payload, const StackIterator *iterator) {
  if (iterator->subtrees.size > 0) {
    bool *found_error = payload;
    if (!*found_error && ts_subtree_is_error(*array_get(&iterator->subtrees, 0))) {
      *found_error = true;
      return StackActionPop | StackActionStop;
    } else {
      return StackActionStop;
    }
  } else {
    return StackActionNone;
  }
}

SubtreeArray ts_stack_pop_error(Stack *self, StackVersion version) {
  StackNode *node = array_get(&self->heads, version)->node;
  for (unsigned i = 0; i < node->link_count; i++) {
    if (node->links[i].subtree.ptr && ts_subtree_is_error(node->links[i].subtree)) {
      bool found_error = false;
      StackSliceArray pop = stack__iter(self, version, pop_error_callback, &found_error, 1);
      if (pop.size > 0) {
        ts_assert(pop.size == 1);
        ts_stack_renumber_version(self, array_get(&pop, 0)->version, version);
        return array_get(&pop, 0)->subtrees;
      }
      break;
    }
  }
  return (SubtreeArray) {.size = 0};
}

forceinline StackAction pop_all_callback(void *payload, const StackIterator *iterator) {
  (void)payload;
  return iterator->node->link_count == 0 ? StackActionPop : StackActionNone;
}

StackSliceArray ts_stack_pop_all(Stack *self, StackVersion version) {
  return stack__iter(self, version, pop_all_callback, NULL, 0);
}

typedef struct {
  StackSummary *summary;
  unsigned max_depth;
} SummarizeStackSession;

forceinline StackAction summarize_stack_callback(void *payload, const StackIterator *iterator) {
  SummarizeStackSession *session = payload;
  TSStateId state = iterator->node->state;
  unsigned depth = iterator->subtree_count;
  if (depth > session->max_depth) return StackActionStop;
  for (unsigned i = session->summary->size - 1; i + 1 > 0; i--) {
    StackSummaryEntry entry = *array_get(session->summary, i);
    if (entry.depth < depth) break;
    if (entry.depth == depth && entry.state == state) return StackActionNone;
  }
  array_push(session->summary, ((StackSummaryEntry) {
    .position = iterator->node->position,
    .depth = depth,
    .state = state,
  }));
  return StackActionNone;
}

void ts_stack_record_summary(Stack *self, StackVersion version, unsigned max_depth) {
  SummarizeStackSession session = {
    .summary = ts_malloc(sizeof(StackSummary)),
    .max_depth = max_depth
  };
  array_init(session.summary);
  stack__iter(self, version, summarize_stack_callback, &session, -1);
  StackHead *head = array_get(&self->heads, version);
  if (head->summary) {
    array_delete(head->summary);
    ts_free(head->summary);
  }
  head->summary = session.summary;
}

StackSummary *ts_stack_get_summary(Stack *self, StackVersion version) {
  return array_get(&self->heads, version)->summary;
}

int ts_stack_dynamic_precedence(Stack *self, StackVersion version) {
  return array_get(&self->heads, version)->node->dynamic_precedence;
}

bool ts_stack_has_advanced_since_error(const Stack *self, StackVersion version) {
  const StackHead *head = array_get(&self->heads, version);
  const StackNode *node = head->node;
  if (node->error_cost == 0) return true;
  while (node) {
    if (node->link_count > 0) {
      Subtree subtree = node->links[0].subtree;
      if (subtree.ptr) {
        if (ts_subtree_total_bytes(subtree) > 0) {
          return true;
        } else if (
          node->node_count > head->node_count_at_last_error &&
          ts_subtree_error_cost(subtree) == 0
        ) {
          node = node->links[0].node;
          continue;
        }
      }
    }
    break;
  }
  return false;
}

void ts_stack_remove_version(Stack *self, StackVersion version) {
  stack_head_delete(array_get(&self->heads, version), &self->node_pool, self->subtree_pool);
  array_erase(&self->heads, version);
}

void ts_stack_renumber_version(Stack *self, StackVersion v1, StackVersion v2) {
  if (v1 == v2) return;
  ts_assert(v2 < v1);
  ts_assert((uint32_t)v1 < self->heads.size);
  StackHead *source_head = array_get(&self->heads, v1);
  StackHead *target_head = array_get(&self->heads, v2);
  if (target_head->summary && !source_head->summary) {
    source_head->summary = target_head->summary;
    target_head->summary = NULL;
  }
  stack_head_delete(target_head, &self->node_pool, self->subtree_pool);
  *target_head = *source_head;
  array_erase(&self->heads, v1);
}

void ts_stack_swap_versions(Stack *self, StackVersion v1, StackVersion v2) {
  StackHead temporary_head = *array_get(&self->heads, v1);
  *array_get(&self->heads, v1) = *array_get(&self->heads, v2);
  *array_get(&self->heads, v2) = temporary_head;
}

StackVersion ts_stack_copy_version(Stack *self, StackVersion version) {
  ts_assert(version < self->heads.size);
  StackHead version_head = *array_get(&self->heads, version);
  array_push(&self->heads, version_head);
  StackHead *head = array_back(&self->heads);
  stack_node_retain(head->node);
  if (head->last_external_token.ptr) ts_subtree_retain(head->last_external_token);
  head->summary = NULL;
  return self->heads.size - 1;
}

bool ts_stack_merge(Stack *self, StackVersion version1, StackVersion version2) {
  if (!ts_stack_can_merge(self, version1, version2)) return false;
  StackHead *head1 = array_get(&self->heads, version1);
  StackHead *head2 = array_get(&self->heads, version2);
  for (uint32_t i = 0; i < head2->node->link_count; i++) {
    stack_node_add_link(head1->node, head2->node->links[i], self->subtree_pool);
  }
  if (head1->node->state == ERROR_STATE) {
    head1->node_count_at_last_error = head1->node->node_count;
  }
  ts_stack_remove_version(self, version2);
  return true;
}

bool ts_stack_can_merge(Stack *self, StackVersion version1, StackVersion version2) {
  StackHead *head1 = array_get(&self->heads, version1);
  StackHead *head2 = array_get(&self->heads, version2);
  return
    head1->status == StackStatusActive &&
    head2->status == StackStatusActive &&
    head1->node->state == head2->node->state &&
    head1->node->position.bytes == head2->node->position.bytes &&
    head1->node->error_cost == head2->node->error_cost &&
    ts_subtree_external_scanner_state_eq(head1->last_external_token, head2->last_external_token);
}

void ts_stack_halt(Stack *self, StackVersion version) {
  array_get(&self->heads, version)->status = StackStatusHalted;
}

void ts_stack_pause(Stack *self, StackVersion version, Subtree lookahead) {
  StackHead *head = array_get(&self->heads, version);
  head->status = StackStatusPaused;
  head->lookahead_when_paused = lookahead;
  head->node_count_at_last_error = head->node->node_count;
}

bool ts_stack_is_active(const Stack *self, StackVersion version) {
  return array_get(&self->heads, version)->status == StackStatusActive;
}

bool ts_stack_is_halted(const Stack *self, StackVersion version) {
  return array_get(&self->heads, version)->status == StackStatusHalted;
}

bool ts_stack_is_paused(const Stack *self, StackVersion version) {
  return array_get(&self->heads, version)->status == StackStatusPaused;
}

Subtree ts_stack_resume(Stack *self, StackVersion version) {
  StackHead *head = array_get(&self->heads, version);
  ts_assert(head->status == StackStatusPaused);
  Subtree result = head->lookahead_when_paused;
  head->status = StackStatusActive;
  head->lookahead_when_paused = NULL_SUBTREE;
  return result;
}

void ts_stack_clear(Stack *self) {
  stack_node_retain(self->base_node);
  for (uint32_t i = 0; i < self->heads.size; i++) {
    stack_head_delete(array_get(&self->heads, i), &self->node_pool, self->subtree_pool);
  }
  array_clear(&self->heads);
  array_push(&self->heads, ((StackHead) {
    .node = self->base_node,
    .status = StackStatusActive,
    .last_external_token = NULL_SUBTREE,
    .lookahead_when_paused = NULL_SUBTREE,
  }));
}
