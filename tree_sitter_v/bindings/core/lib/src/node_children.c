// Child, field and sibling lookups, split out of node.c.

#include "./point.h"
#include "./subtree.h"
#include "./tree.h"
#include "./language.h"

TSNode ts_node_child_with_descendant(TSNode self, TSNode descendant) {
  uint32_t start_byte = ts_node_start_byte(descendant);
  uint32_t end_byte = ts_node_end_byte(descendant);
  bool is_empty = start_byte == end_byte;

  do {
    NodeChildIterator iter = ts_node_iterate_children(&self);
    do {
      if (
        !ts_node_child_iterator_next(&iter, &self)
        || ts_node_start_byte(self) > start_byte
      ) {
        return ts_node__null();
      }
      if (self.id == descendant.id) {
        return self;
      }

      // If the descendant is empty, and the end byte is within `self`,
      // we check whether `self` contains it or not.
      if (is_empty && iter.position.bytes >= end_byte && ts_node_child_count(self) > 0) {
        TSNode child = ts_node_child_with_descendant(self, descendant);
        // If the child is not null, return self if it's relevant, else return the child
        if (!ts_node_is_null(child)) {
          return ts_node__is_relevant(self, true) ? self : child;
        }
      }
    } while ((is_empty ? iter.position.bytes <= end_byte : iter.position.bytes < end_byte) || ts_node_child_count(self) == 0);
  } while (!ts_node__is_relevant(self, true));

  return self;
}

TSNode ts_node_child(TSNode self, uint32_t child_index) {
  return ts_node__child(self, child_index, true);
}

TSNode ts_node_named_child(TSNode self, uint32_t child_index) {
  return ts_node__child(self, child_index, false);
}

TSNode ts_node_child_by_field_id(TSNode self, TSFieldId field_id) {
recur:
  if (!field_id || ts_node_child_count(self) == 0) return ts_node__null();

  const TSFieldMapEntry *field_map, *field_map_end;
  ts_language_field_map(
    self.tree->language,
    ts_node__subtree(self).ptr->production_id,
    &field_map,
    &field_map_end
  );
  if (field_map == field_map_end) return ts_node__null();

  // The field mappings are sorted by their field id. Scan all
  // the mappings to find the ones for the given field id.
  while (field_map->field_id < field_id) {
    field_map++;
    if (field_map == field_map_end) return ts_node__null();
  }
  while (field_map_end[-1].field_id > field_id) {
    field_map_end--;
    if (field_map == field_map_end) return ts_node__null();
  }

  TSNode child;
  NodeChildIterator iterator = ts_node_iterate_children(&self);
  while (ts_node_child_iterator_next(&iterator, &child)) {
    if (!ts_subtree_extra(ts_node__subtree(child))) {
      uint32_t index = iterator.structural_child_index - 1;
      if (index < field_map->child_index) continue;

      // Hidden nodes' fields are "inherited" by their visible parent.
      if (field_map->inherited) {

        // If this is the *last* possible child node for this field,
        // then perform a tail call to avoid recursion.
        if (field_map + 1 == field_map_end) {
          self = child;
          goto recur;
        }

        // Otherwise, descend into this child, but if it doesn't contain
        // the field, continue searching subsequent children.
        else {
          TSNode result = ts_node_child_by_field_id(child, field_id);
          if (result.id) return result;
          field_map++;
          if (field_map == field_map_end) return ts_node__null();
        }
      }

      else if (ts_node__is_relevant(child, true)) {
        return child;
      }

      // If the field refers to a hidden node with visible children,
      // return the first visible child.
      else if (ts_node_child_count(child) > 0 ) {
        return ts_node_child(child, 0);
      }

      // Otherwise, continue searching subsequent children.
      else {
        field_map++;
        if (field_map == field_map_end) return ts_node__null();
      }
    }
  }

  return ts_node__null();
}

static inline const char *ts_node__field_name_from_language(TSNode self, uint32_t structural_child_index) {
    const TSFieldMapEntry *field_map, *field_map_end;
    ts_language_field_map(
      self.tree->language,
      ts_node__subtree(self).ptr->production_id,
      &field_map,
      &field_map_end
    );
    for (; field_map != field_map_end; field_map++) {
      if (!field_map->inherited && field_map->child_index == structural_child_index) {
        return self.tree->language->field_names[field_map->field_id];
      }
    }
    return NULL;
}

const char *ts_node_field_name_for_child(TSNode self, uint32_t child_index) {
  TSNode result = self;
  bool did_descend = true;
  const char *inherited_field_name = NULL;

  while (did_descend) {
    did_descend = false;

    TSNode child;
    uint32_t index = 0;
    NodeChildIterator iterator = ts_node_iterate_children(&result);
    while (ts_node_child_iterator_next(&iterator, &child)) {
      if (ts_node__is_relevant(child, true)) {
        if (index == child_index) {
          if (ts_node_is_extra(child)) {
            return NULL;
          }
          const char *field_name = ts_node__field_name_from_language(result, iterator.structural_child_index - 1);
          if (field_name) return field_name;
          return inherited_field_name;
        }
        index++;
      } else {
        uint32_t grandchild_index = child_index - index;
        uint32_t grandchild_count = ts_node__relevant_child_count(child, true);
        if (grandchild_index < grandchild_count) {
          const char *field_name = ts_node__field_name_from_language(result, iterator.structural_child_index - 1);
          if (field_name) inherited_field_name = field_name;

          did_descend = true;
          result = child;
          child_index = grandchild_index;
          break;
        }
        index += grandchild_count;
      }
    }
  }

  return NULL;
}

const char *ts_node_field_name_for_named_child(TSNode self, uint32_t named_child_index) {
  TSNode result = self;
  bool did_descend = true;
  const char *inherited_field_name = NULL;

  while (did_descend) {
    did_descend = false;

    TSNode child;
    uint32_t index = 0;
    NodeChildIterator iterator = ts_node_iterate_children(&result);
    while (ts_node_child_iterator_next(&iterator, &child)) {
      if (ts_node__is_relevant(child, false)) {
        if (index == named_child_index) {
          if (ts_node_is_extra(child)) {
            return NULL;
          }
          const char *field_name = ts_node__field_name_from_language(result, iterator.structural_child_index - 1);
          if (field_name) return field_name;
          return inherited_field_name;
        }
        index++;
      } else {
        uint32_t named_grandchild_index = named_child_index - index;
        uint32_t grandchild_count = ts_node__relevant_child_count(child, false);
        if (named_grandchild_index < grandchild_count) {
          const char *field_name = ts_node__field_name_from_language(result, iterator.structural_child_index - 1);
          if (field_name) inherited_field_name = field_name;

          did_descend = true;
          result = child;
          named_child_index = named_grandchild_index;
          break;
        }
        index += grandchild_count;
      }
    }
  }

  return NULL;
}

TSNode ts_node_child_by_field_name(
  TSNode self,
  const char *name,
  uint32_t name_length
) {
  TSFieldId field_id = ts_language_field_id_for_name(
    self.tree->language,
    name,
    name_length
  );
  return ts_node_child_by_field_id(self, field_id);
}

uint32_t ts_node_child_count(TSNode self) {
  Subtree tree = ts_node__subtree(self);
  if (ts_subtree_child_count(tree) > 0) {
    return tree.ptr->visible_child_count;
  } else {
    return 0;
  }
}

uint32_t ts_node_named_child_count(TSNode self) {
  Subtree tree = ts_node__subtree(self);
  if (ts_subtree_child_count(tree) > 0) {
    return tree.ptr->named_child_count;
  } else {
    return 0;
  }
}

TSNode ts_node_next_sibling(TSNode self) {
  return ts_node__next_sibling(self, true);
}

TSNode ts_node_next_named_sibling(TSNode self) {
  return ts_node__next_sibling(self, false);
}

TSNode ts_node_prev_sibling(TSNode self) {
  return ts_node__prev_sibling(self, true);
}

TSNode ts_node_prev_named_sibling(TSNode self) {
  return ts_node__prev_sibling(self, false);
}

TSNode ts_node_first_child_for_byte(TSNode self, uint32_t byte) {
  return ts_node__first_child_for_byte(self, byte, true);
}

TSNode ts_node_first_named_child_for_byte(TSNode self, uint32_t byte) {
  return ts_node__first_child_for_byte(self, byte, false);
}

TSNode ts_node_descendant_for_byte_range(
  TSNode self,
  uint32_t start,
  uint32_t end
) {
  return ts_node__descendant_for_byte_range(self, start, end, true);
}

TSNode ts_node_named_descendant_for_byte_range(
  TSNode self,
  uint32_t start,
  uint32_t end
) {
  return ts_node__descendant_for_byte_range(self, start, end, false);
}

TSNode ts_node_descendant_for_point_range(
  TSNode self,
  TSPoint start,
  TSPoint end
) {
  return ts_node__descendant_for_point_range(self, start, end, true);
}

TSNode ts_node_named_descendant_for_point_range(
  TSNode self,
  TSPoint start,
  TSPoint end
) {
  return ts_node__descendant_for_point_range(self, start, end, false);
}

void ts_node_edit(TSNode *self, const TSInputEdit *edit) {
  uint32_t start_byte = ts_node_start_byte(*self);
  TSPoint start_point = ts_node_start_point(*self);

  ts_point_edit(&start_point, &start_byte, edit);

  self->context[0] = start_byte;
  self->context[1] = start_point.row;
  self->context[2] = start_point.column;
}
