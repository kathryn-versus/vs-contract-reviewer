#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_msa_alignment_check.sh
set -e

# ── 1. src/lib/claude/prompts.ts — add a real MSA-vs-document comparison ───
python3 - << 'PYEOF'
path = "src/lib/claude/prompts.ts"
with open(path) as f:
    content = f.read()

if "MSA alignment" in content:
    print("prompts.ts: MSA alignment concern already present — nothing to do.")
else:
    old = """const CONCERNS_BLOCK = STANDING_CONCERNS.map(
  (c) => `${c.id}. ${c.label} — ${c.description}`
).join('\\n');

export function buildAnalysisPrompt(input: AnalysisPromptInput): string {
  const { docType, counterparty, clientName, clientNotes, msaContext, documentText } = input;

  return `${STUDIO_IDENTITY}

DOCUMENT CONTEXT
Type: ${docType}
Client: ${clientName}
Counterparty: ${counterparty}

${
  clientNotes
    ? `CLIENT-SPECIFIC STANDING NOTES (treat as authoritative context for this client — e.g. a note that a clause is non-negotiable means do not flag it as an issue even if it would normally concern you):\\n${clientNotes}\\n`
    : ''
}${
  msaContext
    ? `GOVERNING MSA (excerpt, pulled automatically from this client's Drive folder — use it to understand what's already been negotiated at the master-agreement level; a SOW that simply incorporates MSA terms is not itself an issue):\\n\"\"\"\\n${msaContext}\\n\"\"\"\\n`
    : ''
}
THE STANDING CONCERNS
Assess the document against exactly these ${STANDING_CONCERNS.length} concerns. Only return
concerns where you find an actual issue in the text — omit any concern the
document already handles acceptably.

${CONCERNS_BLOCK}"""

    new = """export function buildAnalysisPrompt(input: AnalysisPromptInput): string {
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
    .join('\\n');

  return `${STUDIO_IDENTITY}

DOCUMENT CONTEXT
Type: ${docType}
Client: ${clientName}
Counterparty: ${counterparty}

${
  clientNotes
    ? `CLIENT-SPECIFIC STANDING NOTES (treat as authoritative context for this client — e.g. a note that a clause is non-negotiable means do not flag it as an issue even if it would normally concern you):\\n${clientNotes}\\n`
    : ''
}${
  msaContext
    ? `GOVERNING MSA (excerpt, pulled automatically from this client's Drive folder — use it both as background for what's already been negotiated at the master-agreement level (a SOW that simply incorporates MSA terms is not itself an issue) AND as the comparison document for the "MSA alignment" concern below):\\n\"\"\"\\n${msaContext}\\n\"\"\"\\n`
    : ''
}
THE STANDING CONCERNS
Assess the document against exactly these ${concernsForPrompt.length} concerns. Only return
concerns where you find an actual issue in the text — omit any concern the
document already handles acceptably.

${concernsBlock}"""

    if old not in content:
        raise SystemExit(
            "Expected block not found in src/lib/claude/prompts.ts — aborting "
            "so nothing is silently corrupted. Paste me the current file and "
            "I'll fix it by hand."
        )

    content = content.replace(old, new)

    # The JSON response format section still refers to the fixed
    # STANDING_CONCERNS.length for the concernId range — update it to the
    # dynamic count too.
    old_range = '"concernId": number (1-${STANDING_CONCERNS.length}),'
    new_range = '"concernId": number (1-${concernsForPrompt.length}),'
    if old_range in content:
        content = content.replace(old_range, new_range)

    with open(path, "w") as f:
        f.write(content)
    print("prompts.ts: added the MSA alignment concern, active whenever msaContext is present.")
PYEOF

# ── 2. src/lib/types.ts — defensive short-label entry for the new concern ──
python3 - << 'PYEOF'
path = "src/lib/types.ts"
with open(path) as f:
    content = f.read()

if "'MSA alignment'" in content or "MSA alignment" in content and "CONCERN_SHORT_LABELS" in content and "9: 'Payment terms'," in content and "10:" in content:
    print("types.ts: short label already present — skipping check, verifying below.")

old = "  9: 'Payment terms',\n};"
new = "  9: 'Payment terms',\n  // Not a standing concern (not in STANDING_CONCERNS) — only ever appears\n  // when prompts.ts's buildAnalysisPrompt added the MSA alignment concern\n  // for a review that had a governing MSA on file. Included here so any UI\n  // that looks up a short label by concernId doesn't render blank/undefined\n  // for it.\n  10: 'MSA alignment',\n};"

if "10: 'MSA alignment'" in content:
    print("types.ts: already has the MSA alignment short label — nothing to do.")
elif old in content:
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("types.ts: added short label for the MSA alignment concern (id 10).")
else:
    raise SystemExit(
        "Expected CONCERN_SHORT_LABELS closing block not found in "
        "src/lib/types.ts — aborting. Paste me the current file and I'll "
        "fix it by hand."
    )
PYEOF

echo ""
echo "Restart your dev server and test on a client that has a governing MSA"
echo "on file (either the toggle-a-reviewed-matter flow or the direct MSA"
echo "upload) — run (or re-run) a SOW review for that client and confirm an"
echo "'MSA alignment' issue shows up if the SOW actually conflicts with the"
echo "MSA on something like payment or termination terms. A clean SOW should"
echo "show no MSA alignment issues, same as any other concern with no findings."
echo ""
echo "Then commit and push (via GitHub Desktop) to deploy."
