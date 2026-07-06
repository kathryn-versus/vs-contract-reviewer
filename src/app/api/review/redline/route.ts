import { NextRequest, NextResponse } from 'next/server';
import { claude, CLAUDE_MODEL, MAX_TOKENS, parseJsonResponse } from '@/lib/claude/client';
import { buildRedlinePrompt } from '@/lib/claude/prompts';

export async function POST(req: NextRequest) {
  try {
    const { issues } = await req.json();
    if (!Array.isArray(issues) || issues.length === 0) {
      return NextResponse.json({ error: 'issues[] is required.' }, { status: 400 });
    }

    const results = await Promise.all(
      issues.map(async (issue: { uid: string; quote: string; concernLabel: string; recommendation: string }) => {
        const prompt = buildRedlinePrompt({
          clause: issue.quote,
          concernLabel: issue.concernLabel,
          recommendation: issue.recommendation,
        });
        const message = await claude().messages.create({
          model: CLAUDE_MODEL,
          max_tokens: MAX_TOKENS.redline,
          messages: [{ role: 'user', content: prompt }],
        });
        const textBlock = message.content.find((b) => b.type === 'text');
        if (!textBlock || textBlock.type !== 'text') throw new Error('No text response from Claude.');
        const parsed = parseJsonResponse<{ redlineText: string; explanation: string }>(textBlock.text);
        return { uid: issue.uid, ...parsed };
      })
    );

    return NextResponse.json({ redlines: results });
  } catch (err) {
    console.error('review/redline failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Redline drafting failed.' },
      { status: 500 }
    );
  }
}
