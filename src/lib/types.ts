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
  reportUrl: string | null;
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

// The eight standing concerns — brief §5.
export interface Concern {
  id: number;
  label: string;
  description: string;
}

export const EIGHT_CONCERNS: Concern[] = [
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
];

export const SEVERITY_LABELS: Record<Severity, string> = {
  high: 'Significantly one-sided or high financial/legal exposure — must negotiate',
  medium: 'Notable but not severe, or partially addressed — should negotiate',
  low: 'Minor wording issue or low practical risk — nice to have',
};
