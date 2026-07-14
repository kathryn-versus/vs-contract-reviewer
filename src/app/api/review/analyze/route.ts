import { NextRequest, NextResponse } from 'next/server';
import { nanoid } from 'nanoid';
import { claude, CLAUDE_MODEL, MAX_TOKENS, parseJsonResponse } from '@/lib/claude/client';
import { buildAnalysisPrompt } from '@/lib/claude/prompts';
import { getGoverningMsaContext } from '@/lib/drive/msaContext';
import type { Finding, InsuranceRequirement, Severity } from '@/lib/types';

interface RawFinding {
  concernId: number;
  concernLabel: string;
  severity: Severity;
  issueTitle: string;
  quote: string;
  location: string;
  analysis: string;
  recommendation: string;
}

interface RawAnalysisResponse {
  findings: RawFinding[];
  insuranceRequirements: InsuranceRequirement[];
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { docType, counterparty, clientName, clientId, clientNotes, documentText } = body ?? {};

    if (!docType || !counterparty || !clientName || !documentText) {
      return NextResponse.json(
        { error: 'docType, counterparty, clientName, and documentText are required.' },
        { status: 400 }
      );
    }

    // Auto-pull the client's governing MSA text from Drive, if one is on
    // file — never blocks the review if it's missing or fails to extract.
    const msaContext = clientId ? await getGoverningMsaContext(clientId) : null;

    const prompt = buildAnalysisPrompt({ docType, counterparty, clientName, clientNotes, msaContext, documentText });

    const message = await claude().messages.create({
      model: CLAUDE_MODEL,
      max_tokens: MAX_TOKENS.analysis,
      messages: [{ role: 'user', content: prompt }],
    });

    const textBlock = message.content.find((b) => b.type === 'text');
    if (!textBlock || textBlock.type !== 'text') {
      throw new Error('No text response from Claude.');
    }

    const raw = parseJsonResponse<RawAnalysisResponse>(textBlock.text);
    const findings: Finding[] = raw.findings.map((f) => ({ uid: `issue-${nanoid(8)}`, ...f }));
    const insuranceRequirements = raw.insuranceRequirements ?? [];

    return NextResponse.json({ findings, insuranceRequirements });
  } catch (err) {
    console.error('review/analyze failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Analysis failed.' },
      { status: 500 }
    );
  }
}

