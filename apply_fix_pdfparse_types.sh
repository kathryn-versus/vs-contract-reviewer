#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_fix_pdfparse_types.sh
set -e

mkdir -p "src/types"
cat > "src/types/pdf-parse.d.ts" << 'VS_APPLY_EOF_pdftypes'
// pdf-parse doesn't ship its own TypeScript types, and there's no matching
// @types/pdf-parse package to install — this just tells TypeScript to treat
// it as untyped (implicit any) instead of failing the production build,
// which type-checks more strictly than local `next dev` does.
declare module 'pdf-parse';
VS_APPLY_EOF_pdftypes

echo ""
echo "Restart your dev server if it's running to confirm nothing broke locally,"
echo "then commit and push (via GitHub Desktop) to trigger the next rollout."
