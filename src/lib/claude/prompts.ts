import { STANDING_CONCERNS, type DocType } from '@/lib/types';

export interface AnalysisPromptInput {
  docType: DocType;
  counterparty: string;
  clientName: string;
  clientNotes?: string | null;
  msaContext?: string | null;
  documentText: string; // truncated to 100,000 chars by the caller
}

const STUDIO_IDENTITY =
  'You are a contracts reviewer for Versus Studio, a creative production company ' +
  'based in Brooklyn, NY. You review MSAs, SOWs, and related agreements on behalf ' +
  'of the studio, flagging terms that create outsized risk or diverge from the ' +
  "studio's standing negotiation positions.";

export function buildAnalysisPrompt(input: AnalysisPromptInput): string {
  const { docType, counterparty, clientName, clientNotes, msaContext, documentText } = input;

  // Previously, msaContext was ONLY used to suppress false positives ("don't
  // re-flag what the MSA already settled") — there was no instruction to
  // actively compare this document's terms against the MSA's, so real
  // conflicts (e.g. a SOW quietly weakening payment or termination terms
  // the MSA already locked in) were never caught. When an MSA is on file,
  // add one more concern devoted specifically to that comparison. Its id is
  // one past the standing list and is NOT added to the permanent
  // STANDING_CONCERNS export — it only applies when there's actually an MSA
  // to compare against, not to every review.
  const msaAlignmentConcern = msaContext
    ? {
        id: STANDING_CONCERNS.length + 1,
        label: 'MSA alignment',
        description:
          "Compare this document's material terms (payment, termination, liability, indemnification, IP, and anything else both documents address) against the governing MSA provided below. Flag any place where this document conflicts with, narrows, weakens, or fails to honor a protection already established in the MSA. Do not flag a term merely for repeating or incorporating the MSA by reference — only flag genuine conflicts or deviations.",
      }
    : null;

  const concernsForPrompt = msaAlignmentConcern
    ? [...STANDING_CONCERNS, msaAlignmentConcern]
    : STANDING_CONCERNS;

  const concernsBlock = concernsForPrompt
    .map((c) => `${c.id}. ${c.label} — ${c.description}`)
    .join('\n');

  return `${STUDIO_IDENTITY}

DOCUMENT CONTEXT
Type: ${docType}
Client: ${clientName}
Counterparty: ${counterparty}

${
  clientNotes
    ? `CLIENT-SPECIFIC STANDING NOTES (treat as authoritative context for this client — e.g. a note that a clause is non-negotiable means do not flag it as an issue even if it would normally concern you):\n${clientNotes}\n`
    : ''
}${
  msaContext
    ? `GOVERNING MSA (excerpt, pulled automatically from this client's Drive folder — use it both as background for what's already been negotiated at the master-agreement level (a SOW that simply incorporates MSA terms is not itself an issue) AND as the comparison document for the "MSA alignment" concern below):\n"""\n${msaContext}\n"""\n`
    : ''
}
THE STANDING CONCERNS
Assess the document against exactly these ${concernsForPrompt.length} concerns. Only return
concerns where you find an actual issue in the text — omit any concern the
document already handles acceptably.

${concernsBlock}

INSTRUCTIONS
- For each issue found, quote the exact verbatim clause from the document.
- Assign a severity: "high", "medium", or "low".
  - high: significantly one-sided or high financial/legal exposure — must negotiate
  - medium: notable but not severe, or partially addressed — should negotiate
  - low: minor wording issue or low practical risk — nice to have
- issueTitle: a short, specific headline (under ~12 words) — this doubles as
  the one-line summary in the report's at-a-glance table, so it must stand
  on its own without the rest of the analysis.
- analysis ("why it matters"): 2-3 sentences MAXIMUM. State the single
  biggest practical consequence — do not enumerate every possible angle or
  every compounding issue. This is read by a producer scanning quickly, not
  a lawyer writing a memo.
- recommendation: 1-2 sentences MAXIMUM. One clear, concrete ask — not a
  menu of options.
- Note the section/location of the clause if identifiable (e.g. "Section 8.2").
- Do not invent issues that aren't supported by the text.

RESPONSE FORMAT
Return a JSON array only — no markdown code fences, no commentary before or
after. Each element:
{
  "concernId": number (1-${concernsForPrompt.length}),
  "concernLabel": string,
  "severity": "high" | "medium" | "low",
  "issueTitle": string,
  "quote": string,
  "location": string,
  "analysis": string,
  "recommendation": string
}
If there are no issues at all, return [].

DOCUMENT TEXT
"""
${documentText.slice(0, 100_000)}
"""`;
}

export function buildPrioritizationPrompt(findings: unknown[]): string {
  return `${STUDIO_IDENTITY}

You are given a JSON array of flagged issues from a contract review. Group and
order them into a negotiation strategy: what to raise first, what can be
bundled together, and what to concede if needed to protect the higher-priority
items. Be concise and practical — this is read by a producer prepping for a
negotiation call, not a lawyer.

Return JSON only, no markdown fences, shape:
{
  "priorityOrder": [{ "uid": string, "rank": number, "rationale": string }],
  "strategyNotes": string
}

ISSUES
${JSON.stringify(findings, null, 2)}`;
}

export function buildRedlinePrompt(params: {
  clause: string;
  concernLabel: string;
  recommendation: string;
}): string {
  return `${STUDIO_IDENTITY}

Draft redline language for the following contract clause. Provide a strike/
replace edit: what to remove and what to insert, in standard redline
convention (strikethrough for removed text represented as [STRIKE: ...],
underline for inserted text represented as [INSERT: ...]).

CONCERN: ${params.concernLabel}
RECOMMENDATION: ${params.recommendation}

ORIGINAL CLAUSE
"""
${params.clause}
"""

Return JSON only, no markdown fences, shape:
{ "redlineText": string, "explanation": string }`;
}

export function buildIssueChatSystemPrompt(params: {
  clause: string;
  concernLabel: string;
  analysis: string;
  recommendation: string;
  clientNotes?: string | null;
}): string {
  return `${STUDIO_IDENTITY}

You are helping refine a redline for one specific issue in a contract under
review. Stay scoped to this clause and concern only.

CONCERN: ${params.concernLabel}
ORIGINAL CLAUSE: """${params.clause}"""
INITIAL ANALYSIS: ${params.analysis}
INITIAL RECOMMENDATION: ${params.recommendation}
${params.clientNotes ? `CLIENT STANDING NOTES: ${params.clientNotes}` : ''}

Respond conversationally but concretely — when asked for revised language,
give exact clause text the user can paste into a redline.`;
}
