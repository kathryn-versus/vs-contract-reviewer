'use client';

import { useEffect, useState } from 'react';
import { Card } from '@/components/ui/Card';
import { SeverityBadge } from '@/components/ui/SeverityBadge';
import { listVersionsForContract } from '@/lib/firebase/firestore';
import type { ContractDoc, VersionDoc } from '@/lib/types';

export function MatterCard({ contract, onEdit }: { contract: ContractDoc; onEdit: () => void }) {
  const [versions, setVersions] = useState<VersionDoc[]>([]);
  const [expanded, setExpanded] = useState(false);

  useEffect(() => {
    listVersionsForContract(contract.id).then(setVersions).catch(() => {});
  }, [contract.id]);

  const latest = versions[0];
  const counts = latest
    ? {
        high: latest.findings.filter((f) => f.severity === 'high').length,
        medium: latest.findings.filter((f) => f.severity === 'medium').length,
        low: latest.findings.filter((f) => f.severity === 'low').length,
      }
    : null;

  return (
    <Card className="p-5">
      <div className="flex items-start justify-between">
        <div>
          <p className="font-display text-lg text-ink">
            {contract.projectName} <span className="font-mono text-sm text-ink-faint">({contract.projectNumber})</span>
          </p>
          <p className="font-mono text-xs text-ink-faint">
            {contract.docType} · Counterparty: {contract.counterparty}
          </p>
        </div>
        <div className="flex items-center gap-3">
          {counts && (
            <div className="flex gap-1">
              {counts.high > 0 && <SeverityBadge severity="high" />}
              {counts.medium > 0 && <SeverityBadge severity="medium" />}
              {counts.low > 0 && <SeverityBadge severity="low" />}
            </div>
          )}
          <button onClick={onEdit} className="font-mono text-xs text-ink-faint hover:text-ink">
            Edit
          </button>
          <button
            onClick={() => setExpanded((v) => !v)}
            className="font-mono text-xs text-ink-faint hover:text-ink"
          >
            {expanded ? 'Hide versions' : `${versions.length} version${versions.length === 1 ? '' : 's'}`}
          </button>
        </div>
      </div>

      {expanded && (
        <div className="mt-4 space-y-3 border-t border-rule pt-4">
          {versions.map((v) => (
            <div key={v.id} className="flex items-center justify-between text-sm">
              <div>
                <p className="text-ink">v{v.versionNumber} · {v.fileName}</p>
                <p className="font-mono text-xs text-ink-faint">
                  {new Date(v.uploadedAt).toLocaleDateString()} · uploaded by {v.uploadedBy.name}
                </p>
                {v.deltaFromPrevious && (
                  <p className="mt-1 font-body text-xs text-ink-soft">Δ {v.deltaFromPrevious}</p>
                )}
              </div>
              {contract.driveUrl && (
                <a
                  href={contract.driveUrl}
                  target="_blank"
                  rel="noreferrer"
                  className="font-mono text-xs text-accent hover:underline"
                >
                  Drive ↗
                </a>
              )}
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}
