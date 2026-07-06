import 'server-only';
import { gmailClient } from '@/lib/drive/client'; // shares the doco@vsnyc.tv OAuth client

function encodeMessage(params: {
  to: string[];
  from: string;
  subject: string;
  html: string;
}): string {
  const lines = [
    `To: ${params.to.join(', ')}`,
    `From: ${params.from}`,
    `Subject: ${params.subject}`,
    'Content-Type: text/html; charset=utf-8',
    '',
    params.html,
  ];
  const message = lines.join('\r\n');
  return Buffer.from(message).toString('base64url');
}

export async function sendReviewNotification(params: {
  to: string[];
  clientName: string;
  projectName: string;
  severityCounts: { high: number; medium: number; low: number };
  submittedBy: { name: string; email: string };
  docType: string;
  counterparty: string;
  topHighIssues: { issueTitle: string; recommendation: string }[];
  reportDriveUrl: string;
  libraryUrl: string;
}) {
  if (params.to.length === 0) return; // no active recipients (e.g. all commented out during testing)

  const subject = `[Contract Review] ${params.clientName} — ${params.projectName} (H:${params.severityCounts.high} M:${params.severityCounts.medium} L:${params.severityCounts.low})`;

  const issuesHtml = params.topHighIssues
    .slice(0, 3)
    .map((i) => `<li><strong>${escapeHtml(i.issueTitle)}</strong><br/>${escapeHtml(i.recommendation)}</li>`)
    .join('');

  const html = `
    <div style="font-family:sans-serif;color:#1C1B19;">
      <p>Submitted by ${escapeHtml(params.submittedBy.name)} (${escapeHtml(params.submittedBy.email)})</p>
      <p><strong>${escapeHtml(params.docType)}</strong> — Counterparty: ${escapeHtml(params.counterparty)}</p>
      <table style="border-collapse:collapse;margin:12px 0;">
        <tr><td style="padding:4px 12px;border:1px solid #D8D3C7;">High</td><td style="padding:4px 12px;border:1px solid #D8D3C7;">${params.severityCounts.high}</td></tr>
        <tr><td style="padding:4px 12px;border:1px solid #D8D3C7;">Medium</td><td style="padding:4px 12px;border:1px solid #D8D3C7;">${params.severityCounts.medium}</td></tr>
        <tr><td style="padding:4px 12px;border:1px solid #D8D3C7;">Low</td><td style="padding:4px 12px;border:1px solid #D8D3C7;">${params.severityCounts.low}</td></tr>
      </table>
      <p><strong>Top high-severity issues</strong></p>
      <ul>${issuesHtml || '<li>None</li>'}</ul>
      <p><a href="${params.reportDriveUrl}">Full report in Drive</a> · <a href="${params.libraryUrl}">View in app library</a></p>
    </div>`;

  const raw = encodeMessage({ to: params.to, from: 'doco@vsnyc.tv', subject, html });

  await gmailClient().users.messages.send({
    userId: 'me',
    requestBody: { raw },
  });
}

function escapeHtml(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}
