import { STANDING_CONCERNS, type DocType, type Finding } from '@/lib/types';

export interface AnalysisPromptInput {
  docType: DocType;
  counterparty: string;
  clientName: string;
  clientNotes?: string | null;
  msaContext?: string | null;
  documentText: string; // truncated to 100,000 chars by the caller
  // Passing both of these switches this from a fresh full review into a
  // delta-aware one: Claude is asked to confirm which of the previous
  // round's findings are now resolved versus still open in this draft, and
  // to only flag genuinely new issues — rather than re-deriving the whole
  // findings list from scratch and leaving it to the reviewer to work out
  // what's actually different from last time.
  previousDocumentText?: string | null;
  previousFindings?: Finding[] | null;
}

const STUDIO_IDENTITY =
  'You are a contracts reviewer for Versus Studio, a creative production company ' +
  'based in Brooklyn, NY. You review MSAs, SOWs, and related agreements on behalf ' +
  'of the studio, flagging terms that create outsized risk or diverge from the ' +
  "studio's standing negotiation positions.";

export function buildAnalysisPrompt(input: AnalysisPromptInput): string {
  const {
    docType,
    counterparty,
    clientName,
    clientNotes,
    msaContext,
    documentText,
    previousDocumentText,
    previousFindings,
  } = input;

  const isDeltaReview = Boolean(previousDocumentText && previousFindings && previousFindings.length >= 0 && previousDocumentText.trim());

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
}${
  isDeltaReview
    ? `THIS IS A RE-REVIEW — a previous round of this same document was already reviewed. Here is what was flagged last time, and the previous draft's text for comparison:

PREVIOUS ROUND'S FINDINGS
${JSON.stringify(
        previousFindings!.map((f) => ({
          uid: f.uid,
          concernId: f.concernId,
          concernLabel: f.concernLabel,
          severity: f.severity,
          issueTitle: f.issueTitle,
          quote: f.quote,
          location: f.location,
        })),
        null,
        2
      )}

PREVIOUS DRAFT TEXT
"""
${previousDocumentText!.slice(0, 100_000)}
"""
`
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
- Do not invent issues that aren't supported by the text.${
  isDeltaReview
    ? `

DELTA REVIEW — this is a re-review of a revised draft, not a first pass.
- For EVERY item in the previous round's findings above, check the new
  document text: has the flagged language changed in a way that actually
  addresses the concern? If yes, do NOT include it in "findings" — instead
  add it to "resolvedFindings" with a one-sentence "resolutionNote"
  describing what changed.
- If the flagged language is unchanged, or changed only cosmetically and the
  underlying issue still stands, include it again in "findings" with
  "deltaStatus": "carried_over" — keep the same severity/analysis/
  recommendation unless the surrounding context changed enough to warrant
  updating them.
- Then check the rest of the document — including parts that didn't change
  — for issues not already covered by a carried-over finding. Add these to
  "findings" with "deltaStatus": "new".
- Do not list the same underlying issue in both "findings" and
  "resolvedFindings".`
    : ''
}

INSURANCE REQUIREMENTS AUDIT
Separately from the standing concerns above, scan the document for every
insurance requirement it imposes on Versus Studio (types of coverage
required — e.g. Commercial General Liability, Workers\' Compensation,
Umbrella/Excess, Professional/E&O, Auto, Cyber — and their limits). List
every one you find, even if it looks standard and unremarkable — this is an
inventory, not a findings list. For each, set "flag" to null if the limit
looks typical/adequate for a production services engagement, or a short
one-sentence note if it looks unusually high, unusually low, missing a
coverage type you'd expect for this kind of engagement, or otherwise worth
being aware of.

RESPONSE FORMAT
Return a JSON object only — no markdown code fences, no commentary before or
after. Shape:
{
  "findings": [
    {
      "concernId": number (1-${concernsForPrompt.length}),
      "concernLabel": string,
      "severity": "high" | "medium" | "low",
      "issueTitle": string,
      "quote": string,
      "location": string,
      "analysis": string,
      "recommendation": string${isDeltaReview ? ',\n      "deltaStatus": "new" | "carried_over"' : ''}
    }
  ],${
    isDeltaReview
      ? `
  "resolvedFindings": [
    {
      "concernId": number,
      "concernLabel": string,
      "issueTitle": string,
      "resolutionNote": string
    }
  ],`
      : ''
  }
  "insuranceRequirements": [
    {
      "requirement": string,
      "limit": string,
      "quote": string,
      "location": string,
      "flag": string | null
    }
  ]
}
If there are no issues at all, findings should be []. If the document has no
insurance requirements, insuranceRequirements should be [].${
    isDeltaReview ? ' If nothing from the previous round was resolved, resolvedFindings should be [].' : ''
  }

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

export function buildVersionDeltaPrompt(params: { previousText: string; newText: string }): string {
  return `${STUDIO_IDENTITY}

You are comparing two versions of the same contract document to summarize
what changed for a producer who doesn't have time to reread the whole thing.

PREVIOUS VERSION
"""
${params.previousText.slice(0, 60_000)}
"""

NEW VERSION
"""
${params.newText.slice(0, 60_000)}
"""

INSTRUCTIONS
- If the new version is substantively identical to the previous one (only
  formatting, whitespace, or non-substantive wording differs), respond with
  exactly: "No substantive changes from the previous version."
- Otherwise, summarize what changed in 1-3 sentences — focus on material
  terms (payment, scope, dates, deliverables, termination, liability) that a
  producer would actually care about. Do not describe every wording tweak.

Return plain text only — no JSON, no markdown, no preamble.`;
}
