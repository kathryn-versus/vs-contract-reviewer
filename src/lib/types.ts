// Core data model — mirrors the Firestore schema in the project brief §6.

export type Role = 'admin' | 'reviewer';

export interface UserDoc {
  uid: string;
  email: string;
  name: string;
  role: Role;
  createdAt: number; // ms epoch
  lastLoginAt: number;
}

export interface ClientDoc {
  id: string;
  name: string;
  slug: string;
  notes: string;
  msaContractId: string | null;
  createdAt: number;
  createdBy: string;
}

export type DocType = 'MSA' | 'SOW' | 'MSA+SOW' | 'Other';

export interface SubmittedBy {
  uid: string;
  name: string;
  email: string;
}

export interface ContractDoc {
  id: string;
  clientId: string;
  clientName: string;
  projectName: string;
  projectNumber: string;
  docType: DocType;
  counterparty: string;
  submittedBy: SubmittedBy;
  driveFileId: string | null;
  driveUrl: string | null;
  driveFolderUrl: string | null;
  driveFolderId: string | null;
  createdAt: number;
  latestVersionId: string | null;
}

export type Severity = 'high' | 'medium' | 'low';

export interface Finding {
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
}

export interface VersionDoc {
  id: string;
  versionNumber: number;
  uploadedAt: number;
  uploadedBy: { name: string; email: string };
  fileName: string;
  characterCount: number;
  findings: Finding[];
  deltaFromPrevious: string | null;
  // Per-version Drive links — kept on each version (not just the top-level
  // ContractDoc) so version history survives later uploads instead of being
  // silently overwritten by the next version's links. Populated once the
  // Drive upload / Google Doc duplication / report uploads for THIS version
  // succeed; null until then.
  driveFileId: string | null;
  driveUrl: string | null;
  driveFolderId: string | null;
  driveFolderUrl: string | null;
  googleDocId: string | null;
  googleDocUrl: string | null;
  reportHtmlUrl: string | null;
  reportPdfUrl: string | null;
}

export interface ThreadMessage {
  role: 'user' | 'assistant';
  content: string;
  timestamp: number;
}

export interface IssueThreadDoc {
  id: string;
  messages: ThreadMessage[];
}

// The standing concerns — brief §5, plus additions since. Count is not fixed
// at eight anymore, so nothing downstream should hardcode a number; use
// STANDING_CONCERNS.length wherever a count needs to be displayed.
export interface Concern {
  id: number;
  label: string;
  description: string;
}

export const STANDING_CONCERNS: Concern[] = [
  {
    id: 1,
    label: 'Mutual termination for convenience',
    description:
      'Both parties should be able to terminate for convenience, not just the client.',
  },
  {
    id: 2,
    label: 'Cure period before termination for cause',
    description:
      'Termination for cause should require notice and opportunity to cure. Watch for overly broad "cause" definitions.',
  },
  {
    id: 3,
    label: 'Narrow indemnification obligations',
    description:
      "Indemnity should be tied to actual fault — not cover the client's own acts or ordinary business risk.",
  },
  {
    id: 4,
    label: 'Liability cap applies to indemnification',
    description:
      "If there's a liability cap, indemnification shouldn't be carved out (or only narrow carve-outs like IP/confidentiality should survive).",
  },
  {
    id: 5,
    label: 'Permit normal use of freelancers/subcontractors',
    description:
      'Standard production use of freelancers shouldn\'t require case-by-case prior written approval.',
  },
  {
    id: 6,
    label: 'Relax AI restrictions',
    description:
      'Restrictions should target real risk (training on client IP, undisclosed AI deliverables) — not block ordinary AI tool use in the production workflow.',
  },
  {
    id: 7,
    label: 'Portfolio use and awards submissions',
    description:
      "After public release, portfolio use and awards submissions shouldn't require separate approval each time.",
  },
  {
    id: 8,
    label: 'Standard kill fee / cancellation fee',
    description:
      'SOWs should include a defined cancellation fee structure tied to notice period or production stage.',
  },
  {
    id: 9,
    label: 'Standard payment terms',
    description:
      "Versus's standard payment terms depend on production type. Post-production/post work: 1st payment 50% NET 5 upon award of the SOW; 2nd payment 50% NET 30 following receipt of deliverables. Live-action production (per standard AICP Payment Guidelines): first payment of 75% of the contract price, due upon signing of the contract but not later than 5 business days prior to the first shoot day — due whether or not a written contract/PO/letter of agreement is in hand, since a verbal order to commence production is enough to trigger it; second payment of 25% of the contract price (plus all additional approved and invoiced overages) due upon approval of dailies but not later than airing of the commercial or 30 days from the date of the final invoice, whichever is sooner — the firm-bid portion of a cost-plus job is paid on this schedule regardless of whether the cost-plus items have been actualized yet, and cost-plus invoices are separately due within 30 days of invoice. Determine which structure applies from the nature of the deliverables/scope described in the document (post/edit/sound/animation work vs. a live-action shoot), then flag any payment schedule that requires more up-front risk from Versus than these terms, defers payment materially longer, ties payment to a condition Versus doesn't control without a fallback deadline (e.g., an undefined 'client approval' with no outside date), or omits a clear payment schedule entirely.",
  },
];

// Condensed labels for the always-visible concern index strip (on-screen and
// in exported reports) — short enough to fit all of them on one line, unlike
// the full concern descriptions above.
export const CONCERN_SHORT_LABELS: Record<number, string> = {
  1: 'Mutual termination',
  2: 'Cure period',
  3: 'Indemnification scope',
  4: 'Cap applies to indemnity',
  5: 'Freelancers/subs',
  6: 'AI tool use',
  7: 'Portfolio/awards',
  8: 'Kill fee structure',
  9: 'Payment terms',
};

export const SEVERITY_LABELS: Record<Severity, string> = {
  high: 'Significantly one-sided or high financial/legal exposure — must negotiate',
  medium: 'Notable but not severe, or partially addressed — should negotiate',
  low: 'Minor wording issue or low practical risk — nice to have',
};
