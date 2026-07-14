#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_insurance_audit.sh
set -e

# ── 1. types.ts — new InsuranceRequirement type + field on VersionDoc ──────
python3 - << 'PYEOF'
path = "src/lib/types.ts"
with open(path) as f:
    content = f.read()

if "InsuranceRequirement" in content:
    print("types.ts: InsuranceRequirement already present — nothing to do.")
else:
    old_iface_anchor = "export interface VersionDoc {"
    new_iface_anchor = """export interface InsuranceRequirement {
  requirement: string; // e.g. "Commercial General Liability"
  limit: string; // e.g. "$1,000,000 per occurrence / $2,000,000 aggregate"
  quote: string;
  location: string;
  // null when the limit looks typical/adequate — this is an inventory of
  // what's required, not a findings list, so most entries have no flag.
  flag: string | null;
}

export interface VersionDoc {"""

    old_field = """  findings: Finding[];
  deltaFromPrevious: string | null;"""
    new_field = """  findings: Finding[];
  insuranceRequirements: InsuranceRequirement[];
  deltaFromPrevious: string | null;"""

    missing = [l for l, n in [("VersionDoc anchor", old_iface_anchor), ("findings field", old_field)] if n not in content]
    if missing:
        raise SystemExit(f"Expected block(s) not found in types.ts: {missing} — aborting.")

    content = content.replace(old_iface_anchor, new_iface_anchor).replace(old_field, new_field)
    with open(path, "w") as f:
        f.write(content)
    print("types.ts: added InsuranceRequirement type and VersionDoc field.")
PYEOF

# ── 2. prompts.ts — request the insurance inventory in the same call ───────
python3 - << 'PYEOF'
path = "src/lib/claude/prompts.ts"
with open(path) as f:
    content = f.read()

if "INSURANCE REQUIREMENTS AUDIT" in content:
    print("prompts.ts: insurance audit already present — nothing to do.")
else:
    old = '''RESPONSE FORMAT
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
}'''

    new = '''INSURANCE REQUIREMENTS AUDIT
Separately from the standing concerns above, scan the document for every
insurance requirement it imposes on Versus Studio (types of coverage
required — e.g. Commercial General Liability, Workers\\' Compensation,
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
      "recommendation": string
    }
  ],
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
insurance requirements, insuranceRequirements should be [].

DOCUMENT TEXT
"""
${documentText.slice(0, 100_000)}
"""`;
}'''

    if old not in content:
        raise SystemExit("Expected RESPONSE FORMAT block not found in prompts.ts — aborting.")
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("prompts.ts: added the insurance requirements audit + object response shape.")
PYEOF

# ── 3. analyze/route.ts — parse the new {findings, insuranceRequirements} shape ──
python3 - << 'PYEOF'
path = "src/app/api/review/analyze/route.ts"
with open(path) as f:
    content = f.read()

if "RawAnalysisResponse" in content:
    print("analyze/route.ts: already updated — nothing to do.")
else:
    old_import = "import type { Finding, Severity } from '@/lib/types';"
    new_import = "import type { Finding, InsuranceRequirement, Severity } from '@/lib/types';"

    old_iface = """interface RawFinding {
  concernId: number;
  concernLabel: string;
  severity: Severity;
  issueTitle: string;
  quote: string;
  location: string;
  analysis: string;
  recommendation: string;
}"""
    new_iface = """interface RawFinding {
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
}"""

    old_parse = """    const raw = parseJsonResponse<RawFinding[]>(textBlock.text);
    const findings: Finding[] = raw.map((f) => ({ uid: `issue-${nanoid(8)}`, ...f }));

    return NextResponse.json({ findings });"""
    new_parse = """    const raw = parseJsonResponse<RawAnalysisResponse>(textBlock.text);
    const findings: Finding[] = raw.findings.map((f) => ({ uid: `issue-${nanoid(8)}`, ...f }));
    const insuranceRequirements = raw.insuranceRequirements ?? [];

    return NextResponse.json({ findings, insuranceRequirements });"""

    missing = [l for l, n in [("import", old_import), ("RawFinding interface", old_iface), ("parse/return", old_parse)] if n not in content]
    if missing:
        raise SystemExit(f"Expected block(s) not found in analyze/route.ts: {missing} — aborting.")

    content = content.replace(old_import, new_import).replace(old_iface, new_iface).replace(old_parse, new_parse)
    with open(path, "w") as f:
        f.write(content)
    print("analyze/route.ts: now parses and returns insuranceRequirements alongside findings.")
PYEOF

# ── 4. page.tsx — capture, store, and pass insuranceRequirements through ───
python3 - << 'PYEOF'
import re
path = "src/app/page.tsx"
with open(path) as f:
    content = f.read()

if "newInsurance" in content:
    print("page.tsx: already wired up — nothing to do.")
else:
    # Type import — add InsuranceRequirement wherever Finding is imported from '@/lib/types'.
    import_pattern = re.compile(r"import\s+(?:type\s+)?\{[\s\S]*?Finding[\s\S]*?\}\s*from\s*'@/lib/types';")
    m = import_pattern.search(content)
    if not m:
        raise SystemExit("Could not find the @/lib/types import containing Finding in page.tsx — aborting.")
    import_block = m.group(0)
    if "InsuranceRequirement" not in import_block:
        new_import_block = import_block.replace("Finding", "Finding, InsuranceRequirement", 1)
        content = content.replace(import_block, new_import_block)

    old_decl = "      let newFindings: Finding[] = [];"
    new_decl = "      let newFindings: Finding[] = [];\n      let newInsurance: InsuranceRequirement[] = [];"

    old_assign = "        newFindings = analyzeData.findings;\n      }"
    new_assign = "        newFindings = analyzeData.findings;\n        newInsurance = analyzeData.insuranceRequirements ?? [];\n      }"

    old_addversion_field = "        findings: newFindings,\n        deltaFromPrevious: null,"
    new_addversion_field = "        findings: newFindings,\n        insuranceRequirements: newInsurance,\n        deltaFromPrevious: null,"

    old_setfindings = "      setFindings(newFindings);"
    new_setfindings = "      setFindings(newFindings);\n      setInsuranceRequirements(newInsurance);"

    old_resultsview = "        <ResultsView\n          contract={contractMeta}\n          contractId={contractMeta.contractId}\n          versionId={contractMeta.versionId}"
    new_resultsview = "        <ResultsView\n          contract={contractMeta}\n          contractId={contractMeta.contractId}\n          versionId={contractMeta.versionId}\n          insuranceRequirements={insuranceRequirements}"

    missing = [
        l for l, n in [
            ("newFindings decl", old_decl),
            ("newFindings assign", old_assign),
            ("addVersion fields", old_addversion_field),
            ("setFindings call", old_setfindings),
            ("ResultsView render", old_resultsview),
        ] if n not in content
    ]
    if missing:
        raise SystemExit(f"Expected block(s) not found in page.tsx: {missing} — aborting.")

    content = (
        content.replace(old_decl, new_decl)
        .replace(old_assign, new_assign)
        .replace(old_addversion_field, new_addversion_field)
        .replace(old_setfindings, new_setfindings)
        .replace(old_resultsview, new_resultsview)
    )

    # State declaration — mirror wherever `findings`/`setFindings` state lives.
    state_pattern = re.compile(r"const \[findings, setFindings\] = useState<Finding\[\]>\([^)]*\);")
    sm = state_pattern.search(content)
    if not sm:
        raise SystemExit("Could not find the findings useState declaration in page.tsx — aborting.")
    state_line = sm.group(0)
    new_state_line = state_line + "\n  const [insuranceRequirements, setInsuranceRequirements] = useState<InsuranceRequirement[]>([]);"
    content = content.replace(state_line, new_state_line)

    with open(path, "w") as f:
        f.write(content)
    print("page.tsx: now captures, stores, and passes insuranceRequirements through to results.")
PYEOF

# ── 5. Past-review page — read insuranceRequirements off the stored version ──
python3 - << 'PYEOF'
path = "src/app/review/[contractId]/[versionId]/page.tsx"
with open(path) as f:
    content = f.read()

if "insuranceRequirements={version.insuranceRequirements" in content:
    print("review page: already updated — nothing to do.")
else:
    old = """        findings={version.findings}
        clientNotes={clientNotes}"""
    new = """        findings={version.findings}
        insuranceRequirements={version.insuranceRequirements ?? []}
        clientNotes={clientNotes}"""
    if old not in content:
        raise SystemExit("Expected ResultsView block not found in the review page — aborting.")
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("review page: now passes the version's stored insuranceRequirements through.")
PYEOF

# ── 6. ResultsView.tsx — accept the prop, render a dedicated section, thread to reports ──
python3 - << 'PYEOF'
path = "src/components/review/ResultsView.tsx"
with open(path) as f:
    content = f.read()

if "InsuranceRequirementsSection" in content:
    print("ResultsView.tsx: already updated — nothing to do.")
else:
    old_import = "import type { ContractDoc, Finding, ThreadMessage } from '@/lib/types';"
    new_import = "import type { ContractDoc, Finding, InsuranceRequirement, ThreadMessage } from '@/lib/types';"

    old_destructure = """export function ResultsView({
  contract,
  contractId,
  versionId,
  versionNumber,
  findings,
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
  clientNotes?: string | null;
  driveFileId?: string | null;
  driveFolderId?: string | null;
  sourceFileName?: string | null;
}) {"""
    new_destructure = """export function ResultsView({
  contract,
  contractId,
  versionId,
  versionNumber,
  findings,
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

    old_html_call = "    const html = generateReportHtml({ contract, findings, redlines, fileName: sourceFileName });"
    new_html_call = "    const html = generateReportHtml({ contract, findings, insuranceRequirements, redlines, fileName: sourceFileName });"

    old_pdf_call = "    const blob = await downloadReportPdf({ contract, findings, redlines, filename, sourceFileName });"
    new_pdf_call = "    const blob = await downloadReportPdf({ contract, findings, insuranceRequirements, redlines, filename, sourceFileName });"

    old_section_anchor = "      <SeveritySummary findings={findings} active={filter} onChange={setFilter} />"
    new_section_anchor = "      <SeveritySummary findings={findings} active={filter} onChange={setFilter} />\n      <InsuranceRequirementsSection insuranceRequirements={insuranceRequirements} />"

    missing = [
        l for l, n in [
            ("type import", old_import),
            ("destructure/props", old_destructure),
            ("html call", old_html_call),
            ("pdf call", old_pdf_call),
            ("section anchor", old_section_anchor),
        ] if n not in content
    ]
    if missing:
        raise SystemExit(f"Expected block(s) not found in ResultsView.tsx: {missing} — aborting.")

    content = (
        content.replace(old_import, new_import)
        .replace(old_destructure, new_destructure)
        .replace(old_html_call, new_html_call)
        .replace(old_pdf_call, new_pdf_call)
        .replace(old_section_anchor, new_section_anchor)
    )

    # Append the new local section component at the end of the file.
    content += """
function InsuranceRequirementsSection({ insuranceRequirements }: { insuranceRequirements: InsuranceRequirement[] }) {
  if (insuranceRequirements.length === 0) return null;

  return (
    <div className="rounded-sm border border-rule bg-paper p-5">
      <p className="mb-3 font-mono text-[11px] uppercase tracking-wide text-ink-faint">
        Insurance requirements on file
      </p>
      <div className="space-y-2">
        {insuranceRequirements.map((r, i) => (
          <div key={i} className="border-b border-rule pb-2 last:border-0 last:pb-0">
            <p className="font-body text-sm text-ink">
              <span className="font-medium">{r.requirement}</span> — {r.limit}
            </p>
            {r.flag && <p className="mt-0.5 font-mono text-xs text-med">{r.flag}</p>}
          </div>
        ))}
      </div>
    </div>
  );
}
"""

    with open(path, "w") as f:
        f.write(content)
    print("ResultsView.tsx: renders the dedicated insurance section and threads it into both report exports.")
PYEOF

# ── 7. generatePdf.ts — forward insuranceRequirements to the PDF component ──
python3 - << 'PYEOF'
path = "src/lib/report/generatePdf.ts"
with open(path) as f:
    content = f.read()

if "InsuranceRequirement" in content:
    print("generatePdf.ts: already updated — nothing to do.")
else:
    old_import = "import type { ContractDoc, Finding } from '@/lib/types';"
    new_import = "import type { ContractDoc, Finding, InsuranceRequirement } from '@/lib/types';"

    old_params = """export async function downloadReportPdf(params: {
  contract: Pick<ContractDoc, 'clientName' | 'projectName' | 'projectNumber' | 'docType' | 'counterparty'>;
  findings: Finding[];
  redlines: Record<string, string>;
  filename: string;
  sourceFileName?: string | null;
}): Promise<Blob> {
  const element = createElement(ContractReportPdf, {
    contract: params.contract,
    findings: params.findings,
    redlines: params.redlines,
    fileName: params.sourceFileName,
  });"""
    new_params = """export async function downloadReportPdf(params: {
  contract: Pick<ContractDoc, 'clientName' | 'projectName' | 'projectNumber' | 'docType' | 'counterparty'>;
  findings: Finding[];
  insuranceRequirements?: InsuranceRequirement[];
  redlines: Record<string, string>;
  filename: string;
  sourceFileName?: string | null;
}): Promise<Blob> {
  const element = createElement(ContractReportPdf, {
    contract: params.contract,
    findings: params.findings,
    insuranceRequirements: params.insuranceRequirements ?? [],
    redlines: params.redlines,
    fileName: params.sourceFileName,
  });"""

    missing = [l for l, n in [("import", old_import), ("params/element", old_params)] if n not in content]
    if missing:
        raise SystemExit(f"Expected block(s) not found in generatePdf.ts: {missing} — aborting.")

    content = content.replace(old_import, new_import).replace(old_params, new_params)
    with open(path, "w") as f:
        f.write(content)
    print("generatePdf.ts: now forwards insuranceRequirements to ContractReportPdf.")
PYEOF

# ── 8. ContractReportPdf.tsx — render the insurance section in the PDF ─────
python3 - << 'PYEOF'
path = "src/lib/report/ContractReportPdf.tsx"
with open(path) as f:
    content = f.read()

if "insuranceRequirements" in content:
    print("ContractReportPdf.tsx: already updated — nothing to do.")
else:
    old_import = "import type { ContractDoc, Finding } from '@/lib/types';"
    new_import = "import type { ContractDoc, Finding, InsuranceRequirement } from '@/lib/types';"

    old_sig = """export function ContractReportPdf({
  contract,
  findings,
  redlines,
  generatedAt,
  fileName,
}: {
  contract: Pick<ContractDoc, 'clientName' | 'projectName' | 'projectNumber' | 'docType' | 'counterparty'>;
  findings: Finding[];
  redlines: Record<string, string>;
  generatedAt?: Date;
  fileName?: string | null;
}) {"""
    new_sig = """export function ContractReportPdf({
  contract,
  findings,
  insuranceRequirements = [],
  redlines,
  generatedAt,
  fileName,
}: {
  contract: Pick<ContractDoc, 'clientName' | 'projectName' | 'projectNumber' | 'docType' | 'counterparty'>;
  findings: Finding[];
  insuranceRequirements?: InsuranceRequirement[];
  redlines: Record<string, string>;
  generatedAt?: Date;
  fileName?: string | null;
}) {"""

    old_anchor = """                <Text style={styles.execTitle}>{f.issueTitle}</Text>
              </View>
            ))}
          </View>
        )}

        <View style={styles.summaryRow}>"""
    new_anchor = """                <Text style={styles.execTitle}>{f.issueTitle}</Text>
              </View>
            ))}
          </View>
        )}

        {insuranceRequirements.length > 0 && (
          <View style={styles.execSummary}>
            <Text style={styles.execSummaryLabel}>Insurance requirements on file</Text>
            {insuranceRequirements.map((r, i) => (
              <View key={i} style={styles.execRow}>
                <View style={{ flex: 1 }}>
                  <Text style={styles.execTitle}>
                    {r.requirement} — {r.limit}
                  </Text>
                  {r.flag && (
                    <Text style={[styles.execTitle, { color: '#C97A22', fontSize: 8 }]}>{r.flag}</Text>
                  )}
                </View>
              </View>
            ))}
          </View>
        )}

        <View style={styles.summaryRow}>"""

    missing = [l for l, n in [("import", old_import), ("signature", old_sig), ("insertion anchor", old_anchor)] if n not in content]
    if missing:
        raise SystemExit(f"Expected block(s) not found in ContractReportPdf.tsx: {missing} — aborting.")

    content = content.replace(old_import, new_import).replace(old_sig, new_sig).replace(old_anchor, new_anchor)
    with open(path, "w") as f:
        f.write(content)
    print("ContractReportPdf.tsx: renders the insurance requirements section.")
PYEOF

# ── 9. generateReport.ts — render the insurance section in the HTML report ──
python3 - << 'PYEOF'
path = "src/lib/report/generateReport.ts"
with open(path) as f:
    content = f.read()

if "insuranceHtml" in content:
    print("generateReport.ts: already updated — nothing to do.")
else:
    old_import = "import type { ContractDoc, Finding } from '@/lib/types';"
    new_import = "import type { ContractDoc, Finding, InsuranceRequirement } from '@/lib/types';"

    old_sig = """export function generateReportHtml(params: {
  contract: Pick<ContractDoc, 'clientName' | 'projectName' | 'projectNumber' | 'docType' | 'counterparty'>;
  findings: Finding[];
  redlines: Record<string, string>; // uid -> redlineText
  generatedAt?: Date;
  fileName?: string | null;
}): string {
  const { contract, findings, redlines, fileName } = params;"""
    new_sig = """export function generateReportHtml(params: {
  contract: Pick<ContractDoc, 'clientName' | 'projectName' | 'projectNumber' | 'docType' | 'counterparty'>;
  findings: Finding[];
  insuranceRequirements?: InsuranceRequirement[];
  redlines: Record<string, string>; // uid -> redlineText
  generatedAt?: Date;
  fileName?: string | null;
}): string {
  const { contract, findings, redlines, fileName } = params;
  const insuranceRequirements = params.insuranceRequirements ?? [];"""

    old_concern_anchor = "  const concernIndexHtml = STANDING_CONCERNS.map("
    new_concern_anchor = """  const insuranceHtml = insuranceRequirements.length
    ? `<div class="exec-summary">
        <p class="exec-summary-label">Insurance requirements on file</p>
        <table class="exec-table"><tbody>
          ${insuranceRequirements
            .map(
              (r) => `<tr>
                <td class="exec-title" style="width:38%;">${escapeHtml(r.requirement)}</td>
                <td class="exec-title" style="width:24%;">${escapeHtml(r.limit)}</td>
                <td class="exec-title" style="color:${r.flag ? '#C97A22' : '#8C8A82'};">${r.flag ? escapeHtml(r.flag) : 'Looks standard'}</td>
              </tr>`
            )
            .join('')}
        </tbody></table>
      </div>`
    : '';

  const concernIndexHtml = STANDING_CONCERNS.map("""

    old_body_anchor = "  ${execSummaryHtml}\n  <div class=\"summary\">"
    new_body_anchor = "  ${execSummaryHtml}\n  ${insuranceHtml}\n  <div class=\"summary\">"

    missing = [
        l for l, n in [
            ("import", old_import),
            ("signature", old_sig),
            ("concernIndexHtml anchor", old_concern_anchor),
            ("body anchor", old_body_anchor),
        ] if n not in content
    ]
    if missing:
        raise SystemExit(f"Expected block(s) not found in generateReport.ts: {missing} — aborting.")

    content = (
        content.replace(old_import, new_import)
        .replace(old_sig, new_sig)
        .replace(old_concern_anchor, new_concern_anchor)
        .replace(old_body_anchor, new_body_anchor)
    )
    with open(path, "w") as f:
        f.write(content)
    print("generateReport.ts: renders the insurance requirements section in the HTML report.")
PYEOF

echo ""
echo "Restart your dev server and run a fresh review on a contract that has"
echo "insurance language in it (most MSAs/SOWs do):"
echo "  1. Results screen should show a new 'Insurance requirements on file'"
echo "     card, listing each coverage type + limit found, with an amber"
echo "     note under anything Claude flagged."
echo "  2. Download HTML and PDF reports — same section should appear near"
echo "     the top, after the grade/at-a-glance summary."
echo "  3. A document with no insurance language at all should just show no"
echo "     insurance section anywhere, not an empty/broken one."
echo ""
echo "Note: like the report-conciseness change, this only applies going"
echo "forward — past reviews won't retroactively get an insurance section"
echo "since that data was never extracted for them."
echo ""
echo "Then commit and push (via GitHub Desktop) to deploy."
