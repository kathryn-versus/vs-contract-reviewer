import { NextRequest, NextResponse } from 'next/server';
import { claude, CLAUDE_MODEL, MAX_TOKENS } from '@/lib/claude/client';
import { buildIssueChatSystemPrompt } from '@/lib/claude/prompts';
import type { ThreadMessage } from '@/lib/types';

export async function POST(req: NextRequest) {
  try {
    const { issue, clientNotes, messages } = await req.json() as {
      issue: { quote: string; concernLabel: string; analysis: string; recommendation: string };
      clientNotes?: string | null;
      messages: ThreadMessage[];
    };

    if (!issue || !Array.isArray(messages)) {
      return NextResponse.json({ error: 'issue and messages[] are required.' }, { status: 400 });
    }

    const system = buildIssueChatSystemPrompt({
      clause: issue.quote,
      concernLabel: issue.concernLabel,
      analysis: issue.analysis,
      recommendation: issue.recommendation,
      clientNotes,
    });

    const response = await claude().messages.create({
      model: CLAUDE_MODEL,
      max_tokens: MAX_TOKENS.chat,
      system,
      messages: messages.map((m) => ({ role: m.role, content: m.content })),
    });

    const textBlock = response.content.find((b) => b.type === 'text');
    const reply = textBlock && textBlock.type === 'text' ? textBlock.text : '';

    return NextResponse.json({
      message: { role: 'assistant', content: reply, timestamp: Date.now() },
    });
  } catch (err) {
    console.error('review/chat failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Chat failed.' },
      { status: 500 }
    );
  }
}
