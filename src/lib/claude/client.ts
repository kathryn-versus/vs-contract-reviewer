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

/** Strips accidental markdown code fences before JSON.parse. */
export function parseJsonResponse<T>(text: string): T {
  const trimmed = text
    .trim()
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/```\s*$/i, '');
  return JSON.parse(trimmed) as T;
}
