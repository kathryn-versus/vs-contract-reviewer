import { STANDING_CONCERNS, CONCERN_SHORT_LABELS } from '@/lib/types';
import type { ContractDoc, Finding } from '@/lib/types';

/**
 * Builds a self-contained, downloadable HTML report — brief §4.1 "Share
 * Report": document metadata, severity summary, all issues with quotes and
 * recommendations, and redline language if drafted.
 */
export function generateReportHtml(params: {
  contract: Pick<ContractDoc, 'clientName' | 'projectName' | 'projectNumber' | 'docType' | 'counterparty'>;
  findings: Finding[];
  redlines: Record<string, string>; // uid -> redlineText
  generatedAt?: Date;
  fileName?: string | null;
}): string {
  const { contract, findings, redlines, fileName } = params;
  const generatedAt = params.generatedAt ?? new Date();

  const counts = {
    total: findings.length,
    high: findings.filter((f) => f.severity === 'high').length,
    medium: findings.filter((f) => f.severity === 'medium').length,
    low: findings.filter((f) => f.severity === 'low').length,
  };

  const sevColor: Record<string, string> = { high: '#8A3324', medium: '#A8761E', low: '#5A6B4F' };
  const sevBg: Record<string, string> = { high: '#F3E4DF', medium: '#F4ECDA', low: '#E7ECE1' };

  const concernIndexHtml = STANDING_CONCERNS.map(
    (c, i) =>
      `<span style="white-space:nowrap;">${
        i > 0 ? '<span style="color:#D8D3C7;margin:0 10px;">|</span>' : ''
      }<span style="font-weight:600;color:#1C1B19;">${c.id}.</span> ${escapeHtml(CONCERN_SHORT_LABELS[c.id] ?? c.label)}</span>`
  ).join('');

  const issuesHtml = findings
    .map(
      (f, i) => `
      <div style="border-left:4px solid ${sevColor[f.severity]};border:1px solid #D8D3C7;border-left-width:4px;padding:16px;margin-bottom:16px;background:#F7F5F1;">
        <span style="display:inline-block;font-family:monospace;font-size:11px;color:#8C8777;margin-right:10px;">${String(i + 1).padStart(2, '0')}</span>
        <span style="display:inline-block;border:1px solid ${sevColor[f.severity]};background:${sevBg[f.severity]};color:${sevColor[f.severity]};font-family:monospace;font-size:11px;text-transform:uppercase;padding:2px 8px;border-radius:999px;">${f.severity}</span>
        <span style="font-family:monospace;font-size:11px;color:#8C8777;text-transform:uppercase;margin-left:8px;">Concern ${f.concernId} &middot; ${escapeHtml(f.concernLabel)}</span>
        <h3 style="font-family:Georgia,serif;margin:8px 0 4px;">${escapeHtml(f.issueTitle)}</h3>
        <p style="font-family:monospace;font-size:12px;color:#8C8777;margin:0 0 12px;">${escapeHtml(f.location || '')}</p>
        <p style="font-family:monospace;font-size:10px;text-transform:uppercase;letter-spacing:0.05em;color:#8C8777;margin:0 0 2px;">Contract language</p>
        <p style="font-style:italic;color:#5B574D;border-left:2px solid #D8D3C7;padding-left:12px;">"${escapeHtml(f.quote)}"</p>
        <p style="font-family:monospace;font-size:10px;text-transform:uppercase;letter-spacing:0.05em;color:#8C8777;margin:12px 0 2px;">Why it matters</p>
        <p style="margin:0 0 12px;">${escapeHtml(f.analysis)}</p>
        <p style="font-family:monospace;font-size:10px;text-transform:uppercase;letter-spacing:0.05em;color:#8C8777;margin:0 0 2px;">Suggested negotiation direction</p>
        <p style="margin:0;">${escapeHtml(f.recommendation)}</p>
        ${
          redlines[f.uid]
            ? `<p style="font-family:monospace;font-size:10px;text-transform:uppercase;letter-spacing:0.05em;color:#8C8777;margin:12px 0 2px;">Drafted redline</p><pre style="white-space:pre-wrap;background:#EFE9DC;padding:12px;font-family:monospace;font-size:12px;margin:0;">${escapeHtml(redlines[f.uid])}</pre>`
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
<style>
  body { font-family: Inter, system-ui, sans-serif; background:#F7F5F1; color:#1C1B19; max-width: 820px; margin: 0 auto; padding: 40px 24px; }
  h1 { font-family: Georgia, serif; }
  .meta { font-family: monospace; font-size: 12px; color:#5B574D; margin-bottom: 24px; }
  .summary { display:flex; gap:12px; margin-bottom: 32px; }
  .summary div { border:1px solid #D8D3C7; padding:12px 16px; flex:1; text-align:center; }
  .summary .n { font-family: Georgia, serif; font-size: 24px; }
  .summary .l { font-family: monospace; font-size: 10px; text-transform: uppercase; color:#8C8777; }
  .concern-index { font-family: monospace; font-size: 11px; color: #5B574D; border-bottom: 2px solid #1C1B19; padding-bottom: 14px; margin-bottom: 20px; line-height: 1.8; }
</style>
</head>
<body>
  <p style="font-family:monospace;font-size:11px;text-transform:uppercase;letter-spacing:0.1em;color:#8C8777;">Versus Studio · Contract Review Report</p>
  <h1 style="margin-bottom:2px;">Contract Review <span style="color:#8A3324;">VS</span></h1>
  <div class="concern-index">${concernIndexHtml}</div>
  <h2 style="font-family:Georgia,serif;font-size:18px;margin:0 0 4px;">${escapeHtml(contract.clientName)} — ${escapeHtml(contract.projectNumber)} — ${escapeHtml(contract.projectName)}</h2>
  <div class="meta">
    ${escapeHtml(contract.docType)} · Counterparty: ${escapeHtml(contract.counterparty)} · Reviewed against ${STANDING_CONCERNS.length} standing concerns · Generated ${generatedAt.toLocaleString()}
    ${fileName ? `<br />Source file: ${escapeHtml(fileName)}` : ''}
  </div>
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
