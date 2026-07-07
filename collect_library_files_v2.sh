#!/usr/bin/env bash
# Run from the root of your vs-contract-reviewer repo:
#   bash collect_library_files_v2.sh > library_files_dump2.txt
# Then paste the contents of library_files_dump2.txt back into chat (or drag
# the file in).
set -e

FILES=$(find src -type f -path "*library*" ! -path "*/node_modules/*")
FILES="$FILES src/app/api/drive/duplicate-to-docs/route.ts"

for f in $FILES; do
  if [ -f "$f" ]; then
    echo "----- $f -----"
    cat "$f"
    echo ""
    echo ""
  fi
done
