import { NextRequest, NextResponse } from 'next/server';
import { nanoid } from 'nanoid';
import { claude, CLAUDE_MODEL, MAX_TOKENS, parseJsonResponse } from '@/lib/claude/client';
import { buildAnalysisPrompt } from '@/lib/claude/prompts';
import { getGoverningMsaContext } from '@/lib/drive/msaContext';
import { downloadFileBuffer } from '@/lib/drive/client';
import { extractDocText } from '@/lib/drive/extractDocText';
import type { Finding, InsuranceRequirement, ResolvedFinding, Severity } from '@/lib/types';

interface RawFinding {
  concernId: number;
  concernLabel: string;
  severity: Severity;
  issueTitle: string;
  quote: string;
  location: string;
  analysis: string;
  recommendation: string;
  deltaStatus?: 'new' | 'carried_over';
}

interface RawResolvedFinding {
  concernId: number;
  concernLabel: string;
  issueTitle: string;
  resolutionNote: string;
}

interface RawAnalysisResponse {
  findings: RawFinding[];
  resolvedFindings?: RawResolvedFinding[];
  insuranceRequirements: InsuranceRequirement[];
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const {
      docType,
      counterparty,
      clientName,
      clientId,
      clientNotes,
      documentText,
      previousDriveFileId,
      previousFindings,
    } = body ?? {};

    if (!docType || !counterparty || !clientName || !documentText) {
      return NextResponse.json(
        { error: 'docType, counterparty, clientName, and documentText are required.' },
        { status: 400 }
      );
    }

    // Auto-pull the client's governing MSA text from Drive, if one is on
    // file — never blocks the review if it's missing or fails to extract.
    const msaContext = clientId ? await getGoverningMsaContext(clientId) : null;

    // When a previous version is on file, pull its text so the review can
    // be delta-aware — confirming what's resolved vs. still open instead of
    // re-deriving the whole findings list blind. Best-effort: if the
    // previous file can't be downloaded or its text can't be extracted
    // (e.g. a scanned PDF), fall back to a normal fresh review rather than
    // failing the whole request.
    let previousDocumentText: string | null = null;
    if (previousDriveFileId && Array.isArray(previousFindings) && previousFindings.length > 0) {
      try {
        const prev = await downloadFileBuffer(previousDriveFileId);
        previousDocumentText = await extractDocText(prev.buffer, prev.mimeType, prev.name);
      } catch (err) {
        console.error('review/analyze: could not load previous version for delta review, falling back to full review', err);
        previousDocumentText = null;
      }
    }

    const prompt = buildAnalysisPrompt({
      docType,
      counterparty,
      clientName,
      clientNotes,
      msaContext,
      documentText,
      previousDocumentText,
      previousFindings: previousDocumentText ? previousFindings : null,
    });

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
    const resolvedFindings: ResolvedFinding[] = (raw.resolvedFindings ?? []).map((r) => ({
      uid: `resolved-${nanoid(8)}`,
      ...r,
    }));
    const insuranceRequirements = raw.insuranceRequirements ?? [];

    return NextResponse.json({ findings, resolvedFindings, insuranceRequirements });
  } catch (err) {
    console.error('review/analyze failed', err);
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Analysis failed.' },
      { status: 500 }
    );
  }
}
