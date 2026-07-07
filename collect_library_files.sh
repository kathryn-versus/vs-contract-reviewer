#!/usr/bin/env bash
# Run from the root of your vs-contract-reviewer repo:
#   bash collect_library_files.sh > library_files_dump.txt
# Then paste the contents of library_files_dump.txt back into chat (or drag
# the file in) so the current Library/version code can be extended accurately
# instead of guessed at.
set -e

FILES=$(find src -type f \( -iname "*library*" -o -iname "*version*" \) ! -path "*/node_modules/*")
FILES="$FILES src/lib/types.ts src/components/intake/IntakeForm.tsx src/lib/report/googleDocsHandoff.ts src/app/page.tsx"

for f in $FILES; do
  if [ -f "$f" ]; then
    echo "----- $f -----"
    cat "$f"
    echo ""
    echo ""
  fi
done
