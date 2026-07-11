#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_report_conciseness.sh
set -e

# ── 1. Tighten what Claude actually writes ──────────────────────────────────
python3 - << 'PYEOF'
path = "src/lib/claude/prompts.ts"
with open(path) as f:
    content = f.read()

old = """INSTRUCTIONS
- For each issue found, quote the exact verbatim clause from the document.
- Assign a severity: "high", "medium", or "low".
  - high: significantly one-sided or high financial/legal exposure — must negotiate
  - medium: notable but not severe, or partially addressed — should negotiate
  - low: minor wording issue or low practical risk — nice to have
- Write a concise "why it matters" analysis and a concrete negotiation
  recommendation for each issue.
- Note the section/location of the clause if identifiable (e.g. "Section 8.2").
- Do not invent issues that aren't supported by the text."""

new = """INSTRUCTIONS
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
- Do not invent issues that aren't supported by the text."""

if "MAXIMUM" in content:
    print("prompts.ts: already tightened — nothing to do.")
elif old in content:
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("prompts.ts: analysis/recommendation now capped at 2-3 / 1-2 sentences.")
else:
    raise SystemExit(
        "Expected INSTRUCTIONS block not found in src/lib/claude/prompts.ts — "
        "aborting. Paste me the current file and I'll fix it by hand."
    )
PYEOF

# ── 2. HTML report — at-a-glance summary table with jump links ─────────────
python3 - << 'PYEOF'
path = "src/lib/report/generateReport.ts"
with open(path) as f:
    content = f.read()

if "exec-summary" in content:
    print("generateReport.ts: at-a-glance table already present — nothing to do.")
else:
    old_issue_div = '      <div style="border:1px solid #DEDDD6;border-left:4px solid ${SEV_COLOR[f.severity]};padding:16px;margin-bottom:16px;background:#FAFAF8;">'
    new_issue_div = '      <div id="issue-${i + 1}" style="border:1px solid #DEDDD6;border-left:4px solid ${SEV_COLOR[f.severity]};padding:16px;margin-bottom:16px;background:#FAFAF8;">'

    old_body = """  <div class="score">
    <span class="grade">${grade}</span>
    <span class="txt">${escapeHtml(summary)}</span>
  </div>
  <div class="summary">"""
    new_body = """  <div class="score">
    <span class="grade">${grade}</span>
    <span class="txt">${escapeHtml(summary)}</span>
  </div>
  ${execSummaryHtml}
  <div class="summary">"""

    old_style_close = """  .concern-index { font-family: monospace; font-size: 11px; color: #52514D; border-bottom: 2px solid #141414; padding-bottom: 14px; margin-bottom: 20px; line-height: 1.8; }
</style>"""
    new_style_close = """  .concern-index { font-family: monospace; font-size: 11px; color: #52514D; border-bottom: 2px solid #141414; padding-bottom: 14px; margin-bottom: 20px; line-height: 1.8; }
  .exec-summary { margin-bottom: 28px; }
  .exec-summary-label { font-family: monospace; font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; color: #8C8A82; margin-bottom: 8px; }
  .exec-table { width: 100%; border-collapse: collapse; }
  .exec-table td { padding: 6px 8px; border-bottom: 1px solid #DEDDD6; font-size: 13px; vertical-align: middle; }
  .exec-num { font-family: monospace; color: #8C8A82; width: 24px; }
  .exec-sev { display: inline-block; border: 1px solid; font-family: monospace; font-size: 10px; text-transform: uppercase; padding: 1px 7px; border-radius: 999px; }
  .exec-title a { color: #141414; text-decoration: none; }
  .exec-title a:hover { color: #A5730E; text-decoration: underline; }
</style>"""

    old_counts_block = """  const { grade, summary } = computeReviewScore(findings);

  const concernIndexHtml = STANDING_CONCERNS.map("""
    new_counts_block = """  const { grade, summary } = computeReviewScore(findings);

  const execSummaryHtml = findings.length
    ? `<div class="exec-summary">
        <p class="exec-summary-label">At a glance — click any row to jump to full detail</p>
        <table class="exec-table"><tbody>
          ${findings
            .map(
              (f, i) => `<tr>
                <td class="exec-num">${String(i + 1).padStart(2, '0')}</td>
                <td><span class="exec-sev" style="border-color:${SEV_COLOR[f.severity]};background:${SEV_BG[f.severity]};color:${SEV_COLOR[f.severity]};">${f.severity}</span></td>
                <td class="exec-title"><a href="#issue-${i + 1}">${escapeHtml(f.issueTitle)}</a></td>
              </tr>`
            )
            .join('')}
        </tbody></table>
      </div>`
    : '';

  const concernIndexHtml = STANDING_CONCERNS.map("""

    missing = [
        l for l, n in [
            ("issue div id", old_issue_div),
            ("body score/summary", old_body),
            ("style block", old_style_close),
            ("counts/concernIndexHtml block", old_counts_block),
        ] if n not in content
    ]
    if missing:
        raise SystemExit(
            f"Expected block(s) not found in src/lib/report/generateReport.ts: {missing} "
            "— aborting. Paste me the current file and I'll fix it by hand."
        )

    content = (
        content.replace(old_issue_div, new_issue_div)
        .replace(old_body, new_body)
        .replace(old_style_close, new_style_close)
        .replace(old_counts_block, new_counts_block)
    )
    with open(path, "w") as f:
        f.write(content)
    print("generateReport.ts: added the at-a-glance summary table with real jump links.")
PYEOF

# ── 3. PDF report — at-a-glance summary section ─────────────────────────────
python3 - << 'PYEOF'
path = "src/lib/report/ContractReportPdf.tsx"
with open(path) as f:
    content = f.read()

if "execSummary" in content:
    print("ContractReportPdf.tsx: at-a-glance section already present — nothing to do.")
else:
    old_styles_tail = """  footer: { position: 'absolute', bottom: 20, left: 40, right: 40, flexDirection: 'row', justifyContent: 'space-between', fontSize: 7, fontFamily: 'Courier', color: '#8C8A82', borderTopWidth: 1, borderTopColor: '#DEDDD6', paddingTop: 6 },
});"""
    new_styles_tail = """  footer: { position: 'absolute', bottom: 20, left: 40, right: 40, flexDirection: 'row', justifyContent: 'space-between', fontSize: 7, fontFamily: 'Courier', color: '#8C8A82', borderTopWidth: 1, borderTopColor: '#DEDDD6', paddingTop: 6 },

  execSummary: { marginBottom: 20 },
  execSummaryLabel: { fontSize: 7.5, fontFamily: 'Courier-Bold', textTransform: 'uppercase', letterSpacing: 0.5, color: '#8C8A82', marginBottom: 6 },
  execRow: { flexDirection: 'row', alignItems: 'center', borderBottomWidth: 1, borderBottomColor: '#DEDDD6', paddingVertical: 5 },
  execNum: { fontSize: 8, fontFamily: 'Courier', color: '#8C8A82', width: 18 },
  execSevPill: { borderWidth: 1, borderRadius: 8, paddingVertical: 1, paddingHorizontal: 6, marginRight: 8 },
  execSevText: { fontSize: 7, fontFamily: 'Courier-Bold', textTransform: 'uppercase' },
  execTitle: { fontSize: 9, fontFamily: 'Helvetica', flex: 1 },
});"""

    old_render = """        <View style={styles.scoreRow}>
          <Text style={[styles.scoreGrade, { color: GRADE_COLOR[grade] }]}>{grade}</Text>
          <Text style={styles.scoreText}>{summary}</Text>
        </View>

        <View style={styles.summaryRow}>"""
    new_render = """        <View style={styles.scoreRow}>
          <Text style={[styles.scoreGrade, { color: GRADE_COLOR[grade] }]}>{grade}</Text>
          <Text style={styles.scoreText}>{summary}</Text>
        </View>

        {findings.length > 0 && (
          <View style={styles.execSummary}>
            <Text style={styles.execSummaryLabel}>At a glance</Text>
            {findings.map((f, i) => (
              <View key={f.uid} style={styles.execRow}>
                <Text style={styles.execNum}>{String(i + 1).padStart(2, '0')}</Text>
                <View
                  style={[
                    styles.execSevPill,
                    { borderColor: SEVERITY_COLOR[f.severity], backgroundColor: SEVERITY_BG[f.severity] },
                  ]}
                >
                  <Text style={[styles.execSevText, { color: SEVERITY_COLOR[f.severity] }]}>{f.severity}</Text>
                </View>
                <Text style={styles.execTitle}>{f.issueTitle}</Text>
              </View>
            ))}
          </View>
        )}

        <View style={styles.summaryRow}>"""

    missing = [l for l, n in [("styles tail", old_styles_tail), ("render", old_render)] if n not in content]
    if missing:
        raise SystemExit(
            f"Expected block(s) not found in src/lib/report/ContractReportPdf.tsx: {missing} "
            "— aborting. Paste me the current file and I'll fix it by hand."
        )

    content = content.replace(old_styles_tail, new_styles_tail).replace(old_render, new_render)
    with open(path, "w") as f:
        f.write(content)
    print("ContractReportPdf.tsx: added the at-a-glance summary section.")
PYEOF

echo ""
echo "Note: the prompt change only affects NEW reviews — it can't retroactively"
echo "shorten findings already saved on past matters. Re-run a review (or use"
echo "'View results' on an old one, which will still show the old wording) to"
echo "see tighter analysis/recommendation text."
echo ""
echo "Restart your dev server, run a fresh review, and check:"
echo "  1. Analysis and recommendation read noticeably shorter/punchier."
echo "  2. HTML report has an 'At a glance' table right under the grade —"
echo "     click a row, confirm it jumps to that issue's full card."
echo "  3. PDF report has the same at-a-glance list (no links, just a"
echo "     compact scan) before the full detail sections."
echo ""
echo "Then commit and push (via GitHub Desktop) to deploy."
