import { STANDING_CONCERNS, CONCERN_SHORT_LABELS } from '@/lib/types';
import type { ContractDoc, Finding, InsuranceRequirement } from '@/lib/types';
import { computeReviewScore } from './scoring';

const SEV_COLOR: Record<string, string> = { high: '#C0392B', medium: '#C97A22', low: '#3F7D4A' };
const SEV_BG: Record<string, string> = { high: '#F7E1DF', medium: '#F6E9D5', low: '#E3EFE2' };
const GRADE_COLOR: Record<string, string> = { A: '#3F7D4A', B: '#3F7D4A', C: '#C97A22', D: '#C0392B', F: '#C0392B' };

/**
 * Builds a self-contained, downloadable HTML report — brief §4.1 "Share
 * Report": document metadata, severity summary, all issues with quotes and
 * recommendations, and redline language if drafted. Analysis/recommendation
 * per issue sit behind a native <details> toggle (collapsed by default) so
 * the report reads as a quick scan first, full detail one click away —
 * quote and severity/concern stay visible either way.
 */
export function generateReportHtml(params: {
  contract: Pick<ContractDoc, 'clientName' | 'projectName' | 'projectNumber' | 'docType' | 'counterparty'>;
  findings: Finding[];
  insuranceRequirements?: InsuranceRequirement[];
  redlines: Record<string, string>; // uid -> redlineText
  generatedAt?: Date;
  fileName?: string | null;
}): string {
  const { contract, findings, redlines, fileName } = params;
  const insuranceRequirements = params.insuranceRequirements ?? [];
  const generatedAt = params.generatedAt ?? new Date();

  const counts = {
    total: findings.length,
    high: findings.filter((f) => f.severity === 'high').length,
    medium: findings.filter((f) => f.severity === 'medium').length,
    low: findings.filter((f) => f.severity === 'low').length,
  };

  const { grade, summary } = computeReviewScore(findings);

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

  const insuranceHtml = insuranceRequirements.length
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

  const concernIndexHtml = STANDING_CONCERNS.map(
    (c, i) =>
      `<span style="white-space:nowrap;">${
        i > 0 ? '<span style="color:#DEDDD6;margin:0 10px;">|</span>' : ''
      }<span style="font-weight:600;color:#141414;">${c.id}.</span> ${escapeHtml(CONCERN_SHORT_LABELS[c.id] ?? c.label)}</span>`
  ).join('');

  const issuesHtml = findings
    .map(
      (f, i) => `
      <div id="issue-${i + 1}" style="border:1px solid #DEDDD6;border-left:4px solid ${SEV_COLOR[f.severity]};padding:16px;margin-bottom:16px;background:#FAFAF8;">
        <span style="display:inline-block;font-family:monospace;font-size:11px;color:#8C8A82;margin-right:10px;">${String(i + 1).padStart(2, '0')}</span>
        <span style="display:inline-block;border:1px solid ${SEV_COLOR[f.severity]};background:${SEV_BG[f.severity]};color:${SEV_COLOR[f.severity]};font-family:monospace;font-size:11px;text-transform:uppercase;padding:2px 8px;border-radius:999px;">${f.severity}</span>
        <span style="font-family:monospace;font-size:11px;color:#8C8A82;text-transform:uppercase;margin-left:8px;">Concern ${f.concernId} &middot; ${escapeHtml(f.concernLabel)}</span>
        <h3 style="font-family:'Oswald',Arial,sans-serif;font-weight:600;margin:8px 0 4px;">${escapeHtml(f.issueTitle)}</h3>
        <p style="font-family:monospace;font-size:12px;color:#8C8A82;margin:0 0 12px;">${escapeHtml(f.location || '')}</p>
        <p style="font-family:monospace;font-size:10px;text-transform:uppercase;letter-spacing:0.05em;color:#8C8A82;margin:0 0 2px;">Contract language</p>
        <p style="font-style:italic;color:#52514D;border-left:2px solid #DEDDD6;padding-left:12px;">"${escapeHtml(f.quote)}"</p>
        <details style="margin-top:12px;">
          <summary style="cursor:pointer;font-family:monospace;font-size:10px;text-transform:uppercase;letter-spacing:0.05em;color:#A5730E;">Why it matters + negotiation direction</summary>
          <p style="font-family:monospace;font-size:10px;text-transform:uppercase;letter-spacing:0.05em;color:#8C8A82;margin:10px 0 2px;">Why it matters</p>
          <p style="margin:0 0 12px;">${escapeHtml(f.analysis)}</p>
          <p style="font-family:monospace;font-size:10px;text-transform:uppercase;letter-spacing:0.05em;color:#8C8A82;margin:0 0 2px;">Suggested negotiation direction</p>
          <p style="margin:0;">${escapeHtml(f.recommendation)}</p>
        </details>
        ${
          redlines[f.uid]
            ? `<p style="font-family:monospace;font-size:10px;text-transform:uppercase;letter-spacing:0.05em;color:#8C8A82;margin:12px 0 2px;">Drafted redline</p><pre style="white-space:pre-wrap;background:#E8D9B0;padding:12px;font-family:monospace;font-size:12px;margin:0;">${escapeHtml(redlines[f.uid])}</pre>`
            : ''
        }
      </div>`
    )
    .join('\n');

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<title>Contract Review — ${escapeHtml(contract.clientName)} — ${escapeHtml(contract.projectName)}</title>
<link href="https://fonts.googleapis.com/css2?family=Oswald:wght@500;600;700&display=swap" rel="stylesheet">
<style>
  body { font-family: Inter, system-ui, sans-serif; background:#FAFAF8; color:#141414; max-width: 820px; margin: 0 auto; padding: 40px 24px; }
  h1 { font-family: 'Oswald', Arial, sans-serif; font-weight: 700; text-transform: uppercase; letter-spacing: 0.01em; }
  .meta { font-family: monospace; font-size: 12px; color:#52514D; margin-bottom: 24px; }
  .score { display:flex; align-items:center; gap:16px; border:1px solid #DEDDD6; padding:16px 20px; margin-bottom:24px; background:#FAFAF8; }
  .score .grade { font-family:'Oswald',Arial,sans-serif; font-weight:700; font-size:40px; color:${GRADE_COLOR[grade]}; }
  .score .txt { font-size:14px; color:#52514D; }
  .summary { display:flex; gap:12px; margin-bottom: 32px; }
  .summary div { border:1px solid #DEDDD6; padding:12px 16px; flex:1; text-align:center; }
  .summary .n { font-family: 'Oswald', Arial, sans-serif; font-weight:600; font-size: 24px; }
  .summary .l { font-family: monospace; font-size: 10px; text-transform: uppercase; color:#8C8A82; }
  .concern-index { font-family: monospace; font-size: 11px; color: #52514D; border-bottom: 2px solid #141414; padding-bottom: 14px; margin-bottom: 20px; line-height: 1.8; }
  .exec-summary { margin-bottom: 28px; }
  .exec-summary-label { font-family: monospace; font-size: 11px; text-transform: uppercase; letter-spacing: 0.05em; color: #8C8A82; margin-bottom: 8px; }
  .exec-table { width: 100%; border-collapse: collapse; }
  .exec-table td { padding: 6px 8px; border-bottom: 1px solid #DEDDD6; font-size: 13px; vertical-align: middle; }
  .exec-num { font-family: monospace; color: #8C8A82; width: 24px; }
  .exec-sev { display: inline-block; border: 1px solid; font-family: monospace; font-size: 10px; text-transform: uppercase; padding: 1px 7px; border-radius: 999px; }
  .exec-title a { color: #141414; text-decoration: none; }
  .exec-title a:hover { color: #A5730E; text-decoration: underline; }
</style>
</head>
<body>
  <p style="font-family:monospace;font-size:11px;text-transform:uppercase;letter-spacing:0.1em;color:#8C8A82;">Versus Studio · Contract Review Report</p>
  <h1 style="margin-bottom:2px;font-size:26px;">Contract Review <span style="color:#A5730E;">VS</span></h1>
  <div class="concern-index">${concernIndexHtml}</div>
  <h2 style="font-family:'Oswald',Arial,sans-serif;font-weight:600;font-size:18px;margin:0 0 4px;">${escapeHtml(contract.clientName)} — ${escapeHtml(contract.projectNumber)} — ${escapeHtml(contract.projectName)}</h2>
  <div class="meta">
    ${escapeHtml(contract.docType)} · Counterparty: ${escapeHtml(contract.counterparty)} · Reviewed against ${STANDING_CONCERNS.length} standing concerns · Generated ${generatedAt.toLocaleString()}
    ${fileName ? `<br />Source file: ${escapeHtml(fileName)}` : ''}
  </div>
  <div class="score">
    <span class="grade">${grade}</span>
    <span class="txt">${escapeHtml(summary)}</span>
  </div>
  ${execSummaryHtml}
  ${insuranceHtml}
  <div class="summary">
    <div><div class="n">${counts.total}</div><div class="l">Total flagged</div></div>
    <div><div class="n">${counts.high}</div><div class="l">High</div></div>
    <div><div class="n">${counts.medium}</div><div class="l">Medium</div></div>
    <div><div class="n">${counts.low}</div><div class="l">Low</div></div>
  </div>
  ${issuesHtml || `<p>No issues flagged against the ${STANDING_CONCERNS.length} standing concerns.</p>`}
</body>
</html>`;
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

export function downloadReport(html: string, filename: string) {
  const blob = new Blob([html], { type: 'text/html' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
