#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_delta_aware_review.sh
set -e

# ── 1. types.ts — deltaStatus on Finding, new ResolvedFinding type, resolvedFindings on VersionDoc ──
python3 - << 'PYEOF'
import re
path = "src/lib/types.ts"
with open(path) as f:
    content = f.read()

finding_block = re.search(r"export interface Finding \{[\s\S]*?\n\}", content)
if finding_block and "deltaStatus" in finding_block.group(0):
    print("types.ts: Finding.deltaStatus already present — nothing to do.")
else:
    old_finding = """export interface Finding {
  uid: string;
  concernId: number;
  concernLabel: string;
  severity: Severity;
  issueTitle: string;
  quote: string;
  location: string;
  analysis: string;
  recommendation: string;
  // Set once a redline is drafted for this finding and persisted back to the
  // version doc — lets a past review be reopened with its drafted redlines
  // intact instead of needing them redrafted from scratch.
  redlineText?: string;
}"""
    new_finding = """export interface Finding {
  uid: string;
  concernId: number;
  concernLabel: string;
  severity: Severity;
  issueTitle: string;
  quote: string;
  location: string;
  analysis: string;
  recommendation: string;
  // Set once a redline is drafted for this finding and persisted back to the
  // version doc — lets a past review be reopened with its drafted redlines
  // intact instead of needing them redrafted from scratch.
  redlineText?: string;
  // Only set on a delta-aware review (a later version of a matter that's
  // already been reviewed once) — "new" means this issue wasn't flagged
  // last round, "carried_over" means it was flagged before and is still
  // unresolved in this draft. Undefined on a first-time review, since
  // there's nothing to compare against.
  deltaStatus?: 'new' | 'carried_over';
}

// A prior round's finding that this version's delta-aware review confirmed
// is now resolved — kept separate from Finding (not still "open") so the
// results view can show what got fixed without it cluttering the active
// findings list.
export interface ResolvedFinding {
  uid: string;
  concernId: number;
  concernLabel: string;
  issueTitle: string;
  resolutionNote: string;
}"""
    if old_finding not in content:
        raise SystemExit("Expected Finding interface not found in types.ts — aborting.")
    content = content.replace(old_finding, new_finding)
    with open(path, "w") as f:
        f.write(content)
    print("types.ts: added Finding.deltaStatus and the ResolvedFinding type.")

with open(path) as f:
    content = f.read()
version_block = re.search(r"export interface VersionDoc \{[\s\S]*?\n\}", content)
if version_block and "resolvedFindings" in version_block.group(0):
    print("types.ts: VersionDoc.resolvedFindings already present — nothing to do.")
else:
    old_version = """  findings: Finding[];
  insuranceRequirements: InsuranceRequirement[];
  deltaFromPrevious: string | null;"""
    new_version = """  findings: Finding[];
  insuranceRequirements: InsuranceRequirement[];
  // Prior findings this version's delta-aware review confirmed are now
  // resolved. Optional — absent on versions created before this existed,
  // and never populated on a first-time review (nothing to resolve yet).
  resolvedFindings?: ResolvedFinding[];
  deltaFromPrevious: string | null;"""
    if old_version not in content:
        raise SystemExit("Expected VersionDoc fields not found in types.ts — aborting.")
    content = content.replace(old_version, new_version)
    with open(path, "w") as f:
        f.write(content)
    print("types.ts: added resolvedFindings to VersionDoc.")
PYEOF

# ── 2. prompts.ts — buildAnalysisPrompt becomes delta-aware when given a previous round ──
cat > src/lib/claude/prompts.ts << 'EOF'
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
EOF
echo "prompts.ts: buildAnalysisPrompt is now delta-aware when given a previous round."

# ── 3. review/analyze route — fetch the previous draft's text and run the delta-aware prompt ──
cat > src/app/api/review/analyze/route.ts << 'EOF'
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
EOF
echo "review/analyze/route.ts: now runs a delta-aware review when a previous version is passed in."

# ── 4. page.tsx — resolve the previous version BEFORE analysis, pass it through, capture resolvedFindings ──
python3 - << 'PYEOF'
path = "src/app/page.tsx"
with open(path) as f:
    content = f.read()

if "previousDriveFileId," in content and "ResolvedFinding" in content:
    print("page.tsx: already present — nothing to do.")
else:
    old_import_types = "import type { Finding, InsuranceRequirement, DocType } from '@/lib/types';"
    new_import_types = "import type { Finding, InsuranceRequirement, ResolvedFinding, DocType } from '@/lib/types';"
    if old_import_types not in content:
        raise SystemExit("Expected types import not found in page.tsx — aborting.")
    content = content.replace(old_import_types, new_import_types)

    old_state = """  const [findings, setFindings] = useState<Finding[]>([]);
  const [insuranceRequirements, setInsuranceRequirements] = useState<InsuranceRequirement[]>([]);"""
    new_state = """  const [findings, setFindings] = useState<Finding[]>([]);
  const [insuranceRequirements, setInsuranceRequirements] = useState<InsuranceRequirement[]>([]);
  const [resolvedFindings, setResolvedFindings] = useState<ResolvedFinding[]>([]);"""
    if old_state not in content:
        raise SystemExit("Expected findings/insurance state not found in page.tsx — aborting.")
    content = content.replace(old_state, new_state)

    old_block = """      // 2. Run the standing-concerns analysis — skipped entirely when
      //    filing for reference only, since nothing needs to go to Claude.
      let newFindings: Finding[] = [];
      let newInsurance: InsuranceRequirement[] = [];
      if (!values.skipReview) {
        const analyzeRes = await fetch('/api/review/analyze', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            docType: values.docType,
            counterparty: values.counterparty,
            clientName: values.clientName,
            clientId: client.id,
            clientNotes: clientDoc?.notes || null,
            documentText: values.documentText,
          }),
        });
        const analyzeData = await analyzeRes.json();
        if (analyzeData.error) throw new Error(analyzeData.error);
        newFindings = analyzeData.findings;
        newInsurance = analyzeData.insuranceRequirements ?? [];
      }

      // 3. Attach to the existing matter if one was picked, otherwise create
      //    a new contract + first version record in Firestore.
      const isExistingMatter = Boolean(values.existingContractId);
      const contractId = isExistingMatter
        ? values.existingContractId!
        : await createContract({
            clientId: client.id,
            clientName: client.name,
            projectName: values.projectName,
            projectNumber: values.projectNumber,
            docType: values.docType,
            counterparty: values.counterparty,
            submittedBy: { uid: user!.uid, name: user!.displayName ?? user!.email ?? '', email: user!.email ?? '' },
            driveFileId: null,
            driveUrl: null,
            driveFolderUrl: null,
            driveFolderId: null,
          });

      // Grab the current latest version's Drive file (if any) BEFORE adding
      // the new version below, so there's something to diff the new upload
      // against. Only relevant for an existing matter — a brand-new matter
      // has nothing prior to compare to.
      let previousDriveFileId: string | null = null;
      if (isExistingMatter) {
        const priorVersions = await listVersionsForContract(contractId);
        const priorLatest = priorVersions.reduce<typeof priorVersions[number] | null>(
          (max, v) => (!max || v.versionNumber > max.versionNumber ? v : max),
          null
        );
        previousDriveFileId = priorLatest?.driveFileId ?? null;
      }"""
    new_block = """      // 2. Determine whether this is a new version of an existing matter —
      //    resolved using existingContractId directly (a brand-new matter's
      //    contractId doesn't exist yet) so the prior version, if any, is
      //    known BEFORE running analysis below.
      const isExistingMatter = Boolean(values.existingContractId);
      let priorLatest: Awaited<ReturnType<typeof listVersionsForContract>>[number] | null = null;
      if (isExistingMatter) {
        const priorVersions = await listVersionsForContract(values.existingContractId!);
        priorLatest = priorVersions.reduce<typeof priorVersions[number] | null>(
          (max, v) => (!max || v.versionNumber > max.versionNumber ? v : max),
          null
        );
      }
      const previousDriveFileId = priorLatest?.driveFileId ?? null;

      // 3. Run the standing-concerns analysis — skipped entirely when
      //    filing for reference only, since nothing needs to go to Claude.
      //    When there's a previous version on file, passing its Drive file
      //    and findings switches this into a delta-aware review: Claude
      //    confirms what's resolved vs. still open and only flags what's
      //    genuinely new, instead of a blind fresh pass every time.
      let newFindings: Finding[] = [];
      let newInsurance: InsuranceRequirement[] = [];
      let newResolvedFindings: ResolvedFinding[] = [];
      if (!values.skipReview) {
        const analyzeRes = await fetch('/api/review/analyze', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            docType: values.docType,
            counterparty: values.counterparty,
            clientName: values.clientName,
            clientId: client.id,
            clientNotes: clientDoc?.notes || null,
            documentText: values.documentText,
            previousDriveFileId,
            previousFindings: priorLatest?.findings ?? null,
          }),
        });
        const analyzeData = await analyzeRes.json();
        if (analyzeData.error) throw new Error(analyzeData.error);
        newFindings = analyzeData.findings;
        newInsurance = analyzeData.insuranceRequirements ?? [];
        newResolvedFindings = analyzeData.resolvedFindings ?? [];
      }

      // 4. Attach to the existing matter if one was picked, otherwise create
      //    a new contract + first version record in Firestore.
      const contractId = isExistingMatter
        ? values.existingContractId!
        : await createContract({
            clientId: client.id,
            clientName: client.name,
            projectName: values.projectName,
            projectNumber: values.projectNumber,
            docType: values.docType,
            counterparty: values.counterparty,
            submittedBy: { uid: user!.uid, name: user!.displayName ?? user!.email ?? '', email: user!.email ?? '' },
            driveFileId: null,
            driveUrl: null,
            driveFolderUrl: null,
            driveFolderId: null,
          });"""
    if old_block not in content:
        raise SystemExit("Expected analyze/createContract block not found in page.tsx — aborting.")
    content = content.replace(old_block, new_block)

    old_addversion = """        findings: newFindings,
        insuranceRequirements: newInsurance,
        deltaFromPrevious: null,"""
    new_addversion = """        findings: newFindings,
        insuranceRequirements: newInsurance,
        resolvedFindings: newResolvedFindings,
        deltaFromPrevious: null,"""
    if old_addversion not in content:
        raise SystemExit("Expected addVersion fields not found in page.tsx — aborting.")
    content = content.replace(old_addversion, new_addversion)

    # Cosmetic only: the upload/email comments below were numbered "4."/"5."
    # against the OLD step order — renumber to "5."/"6." now that a step was
    # inserted above, so the trail of comments still reads in order.
    old_step4 = "      // 4. Upload the source file to Drive (server-side route). For a second"
    new_step5 = "      // 5. Upload the source file to Drive (server-side route). For a second"
    if old_step4 in content:
        content = content.replace(old_step4, new_step5)
    old_step5 = "      // 5. Fire the email notification (recipients controlled server-side by env vars)."
    new_step6 = "      // 6. Fire the email notification (recipients controlled server-side by env vars)."
    if old_step5 in content:
        content = content.replace(old_step5, new_step6)

    old_setfindings = """      setFindings(newFindings);
      setInsuranceRequirements(newInsurance);"""
    new_setfindings = """      setFindings(newFindings);
      setInsuranceRequirements(newInsurance);
      setResolvedFindings(newResolvedFindings);"""
    if old_setfindings not in content:
        raise SystemExit("Expected setFindings/setInsuranceRequirements calls not found in page.tsx — aborting.")
    content = content.replace(old_setfindings, new_setfindings)

    old_resultsview = """          insuranceRequirements={insuranceRequirements}
          versionNumber={contractMeta.versionNumber}
          findings={findings}"""
    new_resultsview = """          insuranceRequirements={insuranceRequirements}
          resolvedFindings={resolvedFindings}
          versionNumber={contractMeta.versionNumber}
          findings={findings}"""
    if old_resultsview not in content:
        raise SystemExit("Expected ResultsView props not found in page.tsx — aborting.")
    content = content.replace(old_resultsview, new_resultsview)

    with open(path, "w") as f:
        f.write(content)
    print("page.tsx: prior version is now resolved before analysis, passed through, and resolvedFindings is captured.")
PYEOF

# ── 5. ResultsView.tsx — accept resolvedFindings, render a "Resolved since last round" panel ──
python3 - << 'PYEOF'
path = "src/components/review/ResultsView.tsx"
with open(path) as f:
    content = f.read()

if "resolvedFindings" in content:
    print("ResultsView.tsx: already present — nothing to do.")
else:
    old_import_types = "import type { ContractDoc, Finding, InsuranceRequirement, ThreadMessage } from '@/lib/types';"
    new_import_types = "import type { ContractDoc, Finding, InsuranceRequirement, ResolvedFinding, ThreadMessage } from '@/lib/types';"
    if old_import_types not in content:
        raise SystemExit("Expected types import not found in ResultsView.tsx — aborting.")
    content = content.replace(old_import_types, new_import_types)

    old_props_destructure = """  findings,
  insuranceRequirements = [],
  clientNotes,
  driveFileId,
  driveFolderId,
  sourceFileName,
}: {
  contract: Pick<ContractDoc, 'clientName' | 'projectName' | 'projectNumber' | 'docType' | 'counterparty'>;
  contractId: string;
  versionId: string;
  versionNumber: number;
  findings: Finding[];
  insuranceRequirements?: InsuranceRequirement[];
  clientNotes?: string | null;
  driveFileId?: string | null;
  driveFolderId?: string | null;
  sourceFileName?: string | null;
}) {"""
    new_props_destructure = """  findings,
  insuranceRequirements = [],
  resolvedFindings = [],
  clientNotes,
  driveFileId,
  driveFolderId,
  sourceFileName,
}: {
  contract: Pick<ContractDoc, 'clientName' | 'projectName' | 'projectNumber' | 'docType' | 'counterparty'>;
  contractId: string;
  versionId: string;
  versionNumber: number;
  findings: Finding[];
  insuranceRequirements?: InsuranceRequirement[];
  resolvedFindings?: ResolvedFinding[];
  clientNotes?: string | null;
  driveFileId?: string | null;
  driveFolderId?: string | null;
  sourceFileName?: string | null;
}) {"""
    if old_props_destructure not in content:
        raise SystemExit("Expected ResultsView props not found in ResultsView.tsx — aborting.")
    content = content.replace(old_props_destructure, new_props_destructure)

    old_render = """      <InsuranceRequirementsSection insuranceRequirements={insuranceRequirements} />"""
    new_render = """      <InsuranceRequirementsSection insuranceRequirements={insuranceRequirements} />
      <ResolvedFindingsSection resolvedFindings={resolvedFindings} />"""
    if old_render not in content:
        raise SystemExit("Expected InsuranceRequirementsSection render not found in ResultsView.tsx — aborting.")
    content = content.replace(old_render, new_render)

    old_section_fn = """function InsuranceRequirementsSection({ insuranceRequirements }: { insuranceRequirements: InsuranceRequirement[] }) {"""
    new_section_fn = """function ResolvedFindingsSection({ resolvedFindings }: { resolvedFindings: ResolvedFinding[] }) {
  if (resolvedFindings.length === 0) return null;

  return (
    <div className="rounded-sm border border-rule bg-paper p-5">
      <p className="mb-3 font-mono text-[11px] uppercase tracking-wide text-ink-faint">
        Resolved since last round ({resolvedFindings.length})
      </p>
      <div className="space-y-2">
        {resolvedFindings.map((r) => (
          <div key={r.uid} className="border-b border-rule pb-2 last:border-0 last:pb-0">
            <p className="font-body text-sm text-ink">
              <span className="font-medium">{r.issueTitle}</span>{' '}
              <span className="font-mono text-[10px] uppercase tracking-wide text-ink-faint">
                Concern {r.concernId} · {r.concernLabel}
              </span>
            </p>
            <p className="mt-0.5 font-mono text-xs text-ink-faint">{r.resolutionNote}</p>
          </div>
        ))}
      </div>
    </div>
  );
}

function InsuranceRequirementsSection({ insuranceRequirements }: { insuranceRequirements: InsuranceRequirement[] }) {"""
    if old_section_fn not in content:
        raise SystemExit("Expected InsuranceRequirementsSection function not found in ResultsView.tsx — aborting.")
    content = content.replace(old_section_fn, new_section_fn)

    with open(path, "w") as f:
        f.write(content)
    print("ResultsView.tsx: added the resolvedFindings prop and a 'Resolved since last round' panel.")
PYEOF

# ── 6. IssueCard.tsx — small badge for new / carried-over findings ──────────
python3 - << 'PYEOF'
path = "src/components/review/IssueCard.tsx"
with open(path) as f:
    content = f.read()

if "deltaStatus" in content:
    print("IssueCard.tsx: already present — nothing to do.")
else:
    old = """        <button className="flex-1 text-left" onClick={() => setExpanded((v) => !v)}>
          <p className="font-mono text-[11px] uppercase tracking-wide text-ink-faint">
            Concern {finding.concernId} · {finding.concernLabel}
          </p>"""
    new = """        <button className="flex-1 text-left" onClick={() => setExpanded((v) => !v)}>
          <p className="font-mono text-[11px] uppercase tracking-wide text-ink-faint">
            Concern {finding.concernId} · {finding.concernLabel}
            {finding.deltaStatus === 'new' && (
              <span className="ml-2 rounded-full bg-accent/15 px-1.5 py-0.5 text-accent">New</span>
            )}
            {finding.deltaStatus === 'carried_over' && (
              <span className="ml-2 rounded-full border border-rule px-1.5 py-0.5 text-ink-faint">
                Still open
              </span>
            )}
          </p>"""
    if old not in content:
        raise SystemExit("Expected concern label block not found in IssueCard.tsx — aborting.")
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("IssueCard.tsx: added New / Still open badges for delta-aware findings.")
PYEOF

# ── 7. Past-review page — pass resolvedFindings through when reopening a stored version ──
python3 - << 'PYEOF'
path = "src/app/review/[contractId]/[versionId]/page.tsx"
with open(path) as f:
    content = f.read()

if "resolvedFindings" in content:
    print("review/[contractId]/[versionId]/page.tsx: already present — nothing to do.")
else:
    old = """        findings={version.findings}
        insuranceRequirements={version.insuranceRequirements ?? []}
        clientNotes={clientNotes}"""
    new = """        findings={version.findings}
        insuranceRequirements={version.insuranceRequirements ?? []}
        resolvedFindings={version.resolvedFindings ?? []}
        clientNotes={clientNotes}"""
    if old not in content:
        raise SystemExit("Expected ResultsView props not found in review/[contractId]/[versionId]/page.tsx — aborting.")
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("review/[contractId]/[versionId]/page.tsx: now passes resolvedFindings through when reopening a past review.")
PYEOF

echo ""
echo "Restart your dev server and test on a matter that already has one"
echo "reviewed version on file:"
echo "  1. Upload a revised draft as a new version of that same matter."
echo "  2. Results should now include a 'Resolved since last round' panel"
echo "     (if anything was fixed) above the findings list, and each finding"
echo "     should show a 'New' or 'Still open' tag next to its concern label."
echo "  3. Reopen that version later from the Library — the same panel and"
echo "     tags should still show (they're stored on the version, not"
echo "     recomputed on reopen)."
echo "  4. A brand-new matter's first review should look completely"
echo "     unchanged — no tags, no resolved panel, same as before this"
echo "     change (there's nothing to diff against yet)."
echo ""
echo "Then run npm run build before pushing, and commit/push (via GitHub"
echo "Desktop) to deploy."
