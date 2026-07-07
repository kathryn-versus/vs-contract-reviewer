#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_json_parse_fix.sh
set -e

mkdir -p "$(dirname "src/lib/claude/client.ts")"
cat > "src/lib/claude/client.ts" << 'VS_APPLY_EOF_jsonfix'
import 'server-only';
import Anthropic from '@anthropic-ai/sdk';

let _client: Anthropic | null = null;

export function claude(): Anthropic {
  if (!_client) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
      throw new Error('ANTHROPIC_API_KEY is not set.');
    }
    _client = new Anthropic({ apiKey });
  }
  return _client;
}

export const CLAUDE_MODEL = process.env.CLAUDE_MODEL || 'claude-sonnet-4-6';

export const MAX_TOKENS = {
  analysis: 4000,
  prioritization: 2500,
  redline: 3000,
  chat: 1000,
} as const;

/**
 * Strips accidental markdown code fences before JSON.parse, and falls back
 * to extracting the first balanced [...] or {...} block if Claude prepends
 * conversational text (e.g. "Looking at the document, here's what I
 * found:") despite being told to return JSON only — that preamble is what
 * was breaking this with "Unexpected token 'L'..." errors.
 */
export function parseJsonResponse<T>(text: string): T {
  let trimmed = text
    .trim()
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/```\s*$/i, '')
    .trim();

  if (!(trimmed.startsWith('[') || trimmed.startsWith('{'))) {
    const firstBracket = trimmed.search(/[[{]/);
    if (firstBracket === -1) {
      throw new Error(`Claude did not return JSON: ${trimmed.slice(0, 200)}`);
    }
    const opening = trimmed[firstBracket];
    const closing = opening === '[' ? ']' : '}';
    const lastBracket = trimmed.lastIndexOf(closing);
    if (lastBracket === -1 || lastBracket < firstBracket) {
      throw new Error(`Claude did not return well-formed JSON: ${trimmed.slice(0, 200)}`);
    }
    trimmed = trimmed.slice(firstBracket, lastBracket + 1);
  }

  return JSON.parse(trimmed) as T;
}
VS_APPLY_EOF_jsonfix

echo ""
echo "Done. 1 file updated: src/lib/claude/client.ts"
echo "No new npm packages needed — restart your dev server (Ctrl+C, then npm run dev) and try the review again."
