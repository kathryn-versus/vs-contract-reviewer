#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_clickable_matter_card.sh
set -e

python3 - << 'PYEOF'
path = "src/components/library/MatterCard.tsx"
with open(path) as f:
    content = f.read()

old = """  return (
    <Card className={autoExpand ? 'p-5 ring-2 ring-accent' : 'p-5'}>
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
              onClick={onToggleGoverningMsa}
              className="font-mono text-xs text-ink-faint hover:text-ink"
            >
              {isGoverningMsa ? 'Unset as MSA' : 'Set as governing MSA'}
            </button>
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
        <div className="mt-4 space-y-4 border-t border-rule pt-4">"""

new = """  return (
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
        <div className="mt-4 space-y-4 border-t border-rule pt-4" onClick={(e) => e.stopPropagation()}>"""

if "cursor-pointer p-5" in content:
    print("MatterCard.tsx: already clickable — nothing to do.")
elif old in content:
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("MatterCard.tsx: whole card now toggles versions; Edit/Set-as-MSA buttons stop propagation so they still work independently.")
else:
    raise SystemExit(
        "Expected block not found in src/components/library/MatterCard.tsx — "
        "the file may have changed since I last wrote it. Paste me the "
        "current file (cat src/components/library/MatterCard.tsx) and I'll "
        "fix it by hand."
    )
PYEOF

echo ""
echo "Restart your dev server and click anywhere on a matter card (not just"
echo "the small version-count text) — it should expand/collapse. Edit and"
echo "Set as governing MSA should still work as their own separate clicks"
echo "without also toggling the card."
echo ""
echo "Then commit and push (via GitHub Desktop) to deploy."
