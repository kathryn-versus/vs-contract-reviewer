import { NextRequest, NextResponse } from 'next/server';
import { claude, CLAUDE_MODEL, MAX_TOKENS, parseJsonResponse } from '@/lib/claude/client';
import { buildPrioritizationPrompt } from '@/lib/claude/prompts';

export async function POST(req: NextRequest) {
  try {
    const { findings } = await req.json();
    if (!Array.isArray(findings) || findings.length === 0) {
      return NextResponse.json({ error: 'findings[] is required.' }, { status: 400 });
    }

    const prompt = buildPrioritizationPrompt(findings);
    const message = await claude().messages.create({
      model: CLAUDE_MODEL,
      max_tokens: MAX_TOKENS.prioritization,
      messages: [{ role: 'user', content: prompt }],
    });

    const textBlock = message.content.find((b) => b.type === 'text');
    if (!textBlock || textBlock.type !== 'text') throw new Error('No text response from Claude.');

    const result = parseJsonResponse<{
      priorityOrder: { uid: string; rank: number; rationale: string }[];
      strategyNotes: string;
    }>(textBlock.text);

    return NextResponse.json(result);
  } catch (err) {
    console.error('review/prioritize failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Prioritization failed.' },
      { status: 500 }
    );
  }
}
