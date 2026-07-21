'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { Card } from '@/components/ui/Card';
import { SeverityBadge } from '@/components/ui/SeverityBadge';
import { listVersionsForContract } from '@/lib/firebase/firestore';
import type { ContractDoc, VersionDoc } from '@/lib/types';

export function MatterCard({
  contract,
  onEdit,
  isGoverningMsa,
  onToggleGoverningMsa,
  autoExpand,
  hasExecutedAgreement,
  onToggleMarkedReceived,
}: {
  contract: ContractDoc;
  onEdit: () => void;
  isGoverningMsa?: boolean;
  onToggleGoverningMsa?: () => void;
  /** Expands and highlights this card on mount — set when arriving via a
   * Library search result's #matter-{id} deep link. */
  autoExpand?: boolean;
  /** True when a real executed agreement is linked to this matter — closes
   * it automatically, taking priority over the manual markedReceived flag. */
  hasExecutedAgreement?: boolean;
  /** Toggles contract.markedReceived — only meaningful when there's no
   * linked executed agreement (that path closes a matter on its own). */
  onToggleMarkedReceived?: () => void;
}) {
  const [versions, setVersions] = useState<VersionDoc[]>([]);
  const [expanded, setExpanded] = useState(Boolean(autoExpand));

  useEffect(() => {
    if (autoExpand) setExpanded(true);
  }, [autoExpand]);

  useEffect(() => {
    listVersionsForContract(contract.id).then(setVersions).catch(() => {});
  }, [contract.id]);

  const latest = versions[0];
  // reviewed is optional — missing/undefined means true (see types.ts), so
  // only an explicit false marks a matter filed without review.
  const latestUnreviewed = latest ? latest.reviewed === false : false;
  const counts = latest
    ? {
        high: latest.findings.filter((f) => f.severity === 'high').length,
        medium: latest.findings.filter((f) => f.severity === 'medium').length,
        low: latest.findings.filter((f) => f.severity === 'low').length,
      }
    : null;

  return (
    <Card
      className={autoExpand ? 'cursor-pointer p-5 ring-2 ring-accent' : 'cursor-pointer p-5'}
      onClick={() => setExpanded((v) => !v)}
    >
      <div className="flex items-start justify-between">
        <div>
          <p className="font-display text-lg text-ink">
            {contract.projectName} <span className="font-mono text-sm text-ink-faint">({contract.projectNumber})</span>
            {isGoverningMsa && (
              <span className="ml-2 rounded-full border border-accent/30 bg-high-bg px-2 py-0.5 align-middle font-mono text-[10px] uppercase tracking-wide text-accent">
                Governing MSA
              </span>
            )}
          </p>
          <p className="font-mono text-xs text-ink-faint">
            {contract.docType} · Counterparty: {contract.counterparty}
          </p>
        </div>
        <div className="flex items-center gap-3">
          {onToggleGoverningMsa && contract.docType !== 'SOW' && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                onToggleGoverningMsa();
              }}
              className="font-mono text-xs text-ink-faint hover:text-ink"
            >
              {isGoverningMsa ? 'Unset as MSA' : 'Set as governing MSA'}
            </button>
          )}
          {hasExecutedAgreement ? (
            <span className="rounded-full border border-low/30 bg-low-bg px-2 py-0.5 font-mono text-[10px] uppercase tracking-wide text-low">
              Executed
            </span>
          ) : contract.markedReceived ? (
            <span className="flex items-center gap-1.5">
              <span className="rounded-full border border-low/30 bg-low-bg px-2 py-0.5 font-mono text-[10px] uppercase tracking-wide text-low">
                Marked received
              </span>
              {onToggleMarkedReceived && (
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    onToggleMarkedReceived();
                  }}
                  className="font-mono text-xs text-ink-faint hover:text-ink"
                >
                  Undo
                </button>
              )}
            </span>
          ) : (
            onToggleMarkedReceived && (
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  onToggleMarkedReceived();
                }}
                className="font-mono text-xs text-ink-faint hover:text-ink"
              >
                Mark as received
              </button>
            )
          )}
          {latestUnreviewed ? (
            <span className="rounded-full border border-rule px-2 py-0.5 font-mono text-[10px] uppercase tracking-wide text-ink-faint">
              Filed — not reviewed
            </span>
          ) : (
            counts && (
              <div className="flex gap-1">
                {counts.high > 0 && <SeverityBadge severity="high" />}
                {counts.medium > 0 && <SeverityBadge severity="medium" />}
                {counts.low > 0 && <SeverityBadge severity="low" />}
              </div>
            )
          )}
          <button
            onClick={(e) => {
              e.stopPropagation();
              onEdit();
            }}
            className="font-mono text-xs text-ink-faint hover:text-ink"
          >
            Edit
          </button>
          {/* Plain label now, not its own button — the whole card toggles
              expansion, so a second click target here would double-toggle. */}
          <span className="font-mono text-xs text-ink-faint">
            {expanded ? 'Hide versions' : `${versions.length} version${versions.length === 1 ? '' : 's'}`}
          </span>
        </div>
      </div>
      {expanded && (
        <div className="mt-4 space-y-4 border-t border-rule pt-4" onClick={(e) => e.stopPropagation()}>
          {versions.map((v) => (
            <div key={v.id} className="text-sm">
              <div className="flex items-center justify-between">
                <p className="text-ink">v{v.versionNumber} · {v.fileName}</p>
                {v.reviewed === false ? (
                  <span className="font-mono text-xs text-ink-faint">Filed — not reviewed</span>
                ) : (
                  <Link href={`/review/${contract.id}/${v.id}`} className="font-mono text-xs text-accent hover:underline">
                    View results
                  </Link>
                )}
              </div>
              <p className="font-mono text-xs text-ink-faint">
                {new Date(v.uploadedAt).toLocaleDateString()} · uploaded by {v.uploadedBy.name}
              </p>
              {v.deltaFromPrevious && (
                <p className="mt-1 font-body text-xs text-ink-soft">Δ {v.deltaFromPrevious}</p>
              )}
              {/* Per-version Drive links — each version keeps its own, so
                  older versions still link correctly after later versions
                  are uploaded. */}
              <div className="mt-1.5 flex flex-wrap gap-x-3 gap-y-1">
                {v.driveFolderUrl && (
                  <a href={v.driveFolderUrl} target="_blank" rel="noreferrer" className="font-mono text-xs text-accent hover:underline">
                    Folder ↗
                  </a>
                )}
                {v.driveUrl && (
                  <a href={v.driveUrl} target="_blank" rel="noreferrer" className="font-mono text-xs text-accent hover:underline">
                    Source file ↗
                  </a>
                )}
                {v.googleDocUrl && (
                  <a href={v.googleDocUrl} target="_blank" rel="noreferrer" className="font-mono text-xs text-accent hover:underline">
                    Google Doc ↗
                  </a>
                )}
                {v.reportHtmlUrl && (
                  <a href={v.reportHtmlUrl} target="_blank" rel="noreferrer" className="font-mono text-xs text-accent hover:underline">
                    HTML report ↗
                  </a>
                )}
                {v.reportPdfUrl && (
                  <a href={v.reportPdfUrl} target="_blank" rel="noreferrer" className="font-mono text-xs text-accent hover:underline">
                    PDF report ↗
                  </a>
                )}
                {!v.driveUrl && !v.googleDocUrl && !v.reportHtmlUrl && !v.reportPdfUrl && (
                  <span className="font-mono text-xs text-ink-faint">No Drive links yet for this version.</span>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}
