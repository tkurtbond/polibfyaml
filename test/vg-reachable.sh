#!/bin/sh
# vg-reachable.sh LOG: succeed if every "still reachable" loss record in
# the valgrind log LOG (from --show-leak-kinds=all) was allocated by poc's
# collector, GarbageCollectedHeap: its heap chunks and its finalization and
# marking tables, which it never frees. Any other still-reachable block is
# memory the program should have freed - a libfyaml document or node whose
# address is held only in the Oberon heap - and is printed.
#
# The allocator is the first frame after the C library's malloc, calloc or
# realloc in the record's stack.
awk '
  / are still reachable in loss record / { inrec = 1; seen = 0; rec = $0; next }
  inrec && /(at|by) 0x/ {
    if ($0 ~ /: (malloc|calloc|realloc) \(/) next
    if (!seen) {
      seen = 1
      if ($0 !~ /GarbageCollectedHeap\./) { print rec; print; bad = 1 }
    }
    next
  }
  inrec && /^==[0-9]+== *$/ { inrec = 0 }
  END { exit bad }
' "$1"
