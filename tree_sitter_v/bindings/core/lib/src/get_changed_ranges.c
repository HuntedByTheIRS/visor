// ts_subtree_get_changed_ranges, the entry point the library calls for a reparse diff.

#include "./get_changed_ranges.h"
#include "./subtree.h"
#include "./language.h"
#include "./error_costs.h"
#include "./tree_cursor.h"
#include "./ts_assert.h"

unsigned ts_subtree_get_changed_ranges(
  const Subtree *old_tree, const Subtree *new_tree,
  TreeCursor *cursor1, TreeCursor *cursor2,
  const TSLanguage *language,
  const TSRangeArray *included_range_differences,
  TSRange **ranges
) {
  TSRangeArray results = array_new();

  Iterator old_iter = iterator_new(cursor1, old_tree, language);
  Iterator new_iter = iterator_new(cursor2, new_tree, language);

  unsigned included_range_difference_index = 0;

  Length position = iterator_start_position(&old_iter);
  Length next_position = iterator_start_position(&new_iter);
  if (position.bytes < next_position.bytes) {
    ts_range_array_add(&results, position, next_position);
    position = next_position;
  } else if (position.bytes > next_position.bytes) {
    ts_range_array_add(&results, next_position, position);
    next_position = position;
  }

  do {
    #ifdef DEBUG_GET_CHANGED_RANGES
    printf("At [%-2u, %-2u] Compare ", position.extent.row, position.extent.column);
    iterator_print_state(&old_iter);
    printf("\tvs\t");
    iterator_print_state(&new_iter);
    puts("");
    #endif

    // Compare the old and new subtrees.
    IteratorComparison comparison = iterator_compare(&old_iter, &new_iter);

    // Even if the two subtrees appear to be identical, they could differ
    // internally if they contain a range of text that was previously
    // excluded from the parse, and is now included, or vice-versa.
    if (comparison == IteratorMatches && ts_range_array_intersects(
      included_range_differences,
      included_range_difference_index,
      position.bytes,
      iterator_end_position(&old_iter).bytes
    )) {
      comparison = IteratorMayDiffer;
    }

    bool is_changed = false;
    switch (comparison) {
      // If the subtrees are definitely identical, move to the end
      // of both subtrees.
      case IteratorMatches:
        next_position = iterator_end_position(&old_iter);
        break;

      // If the subtrees might differ internally, descend into both
      // subtrees, finding the first child that spans the current position.
      case IteratorMayDiffer:
        if (iterator_descend(&old_iter, position.bytes)) {
          if (!iterator_descend(&new_iter, position.bytes)) {
            is_changed = true;
            next_position = iterator_end_position(&old_iter);
          }
        } else if (iterator_descend(&new_iter, position.bytes)) {
          is_changed = true;
          next_position = iterator_end_position(&new_iter);
        } else {
          next_position = length_min(
            iterator_end_position(&old_iter),
            iterator_end_position(&new_iter)
          );
        }
        break;

      // If the subtrees are different, record a change and then move
      // to the end of both subtrees.
      case IteratorDiffers:
        is_changed = true;
        next_position = length_min(
          iterator_end_position(&old_iter),
          iterator_end_position(&new_iter)
        );
        break;
    }

    // Ensure that both iterators are caught up to the current position.
    while (
      !iterator_done(&old_iter) &&
      iterator_end_position(&old_iter).bytes <= next_position.bytes
    ) iterator_advance(&old_iter);
    while (
      !iterator_done(&new_iter) &&
      iterator_end_position(&new_iter).bytes <= next_position.bytes
    ) iterator_advance(&new_iter);

    // Ensure that both iterators are at the same depth in the tree.
    while (old_iter.visible_depth > new_iter.visible_depth) {
      iterator_ascend(&old_iter);
    }
    while (new_iter.visible_depth > old_iter.visible_depth) {
      iterator_ascend(&new_iter);
    }

    if (is_changed) {
      #ifdef DEBUG_GET_CHANGED_RANGES
      printf(
        "  change: [[%u, %u] - [%u, %u]]\n",
        position.extent.row + 1, position.extent.column,
        next_position.extent.row + 1, next_position.extent.column
      );
      #endif

      ts_range_array_add(&results, position, next_position);
    }

    position = next_position;

    // Keep track of the current position in the included range differences
    // array in order to avoid scanning the entire array on each iteration.
    while (included_range_difference_index < included_range_differences->size) {
      const TSRange *range = array_get(included_range_differences,
        included_range_difference_index
      );
      if (range->end_byte <= position.bytes) {
        included_range_difference_index++;
      } else {
        break;
      }
    }
  } while (!iterator_done(&old_iter) && !iterator_done(&new_iter));

  Length old_size = ts_subtree_total_size(*old_tree);
  Length new_size = ts_subtree_total_size(*new_tree);
  if (old_size.bytes < new_size.bytes) {
    ts_range_array_add(&results, old_size, new_size);
  } else if (new_size.bytes < old_size.bytes) {
    ts_range_array_add(&results, new_size, old_size);
  }

  *cursor1 = old_iter.cursor;
  *cursor2 = new_iter.cursor;
  *ranges = results.contents;
  return results.size;
}
