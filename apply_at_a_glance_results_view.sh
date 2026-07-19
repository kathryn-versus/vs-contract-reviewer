#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_at_a_glance_results_view.sh
set -e

python3 - << 'PYEOF'
path = "src/components/review/ResultsView.tsx"
with open(path) as f:
    content = f.read()

if "AtAGlanceSection" in content:
    print("ResultsView.tsx: already present — nothing to do.")
else:
    old_imports = """import { SeveritySummary, type FilterValue } from './SeveritySummary';
import { ReviewScoreBanner } from './ReviewScoreBanner';
import { IssueCard } from './IssueCard';"""
    new_imports = """import { SeveritySummary, type FilterValue } from './SeveritySummary';
import { ReviewScoreBanner } from './ReviewScoreBanner';
import { IssueCard } from './IssueCard';
import { SeverityBadge } from '@/components/ui/SeverityBadge';"""
    if old_imports not in content:
        raise SystemExit("Expected imports block not found in ResultsView.tsx — aborting.")
    content = content.replace(old_imports, new_imports)

    old_render = """  return (
    <div className="space-y-6">
      <ReviewScoreBanner findings={findings} />
      <SeveritySummary findings={findings} active={filter} onChange={setFilter} />
      <InsuranceRequirementsSection insuranceRequirements={insuranceRequirements} />
      <ResolvedFindingsSection resolvedFindings={resolvedFindings} />"""
    new_render = """  // Same idea as the "At a glance" table already on the PDF/HTML exports —
  // a numbered, severity-tagged jump list at the top of the results, so a
  // reviewer can scan what was found before scrolling through every card.
  // Always jumps against the FULL findings list regardless of the current
  // severity filter, so a row is never a dead link — switches the filter
  // back to "all" first if something's filtered out, then scrolls.
  function handleJumpToIssue(uid: string) {
    setFilter('all');
    requestAnimationFrame(() => {
      document.getElementById(`issue-${uid}`)?.scrollIntoView({ behavior: 'smooth', block: 'center' });
    });
  }

  return (
    <div className="space-y-6">
      <ReviewScoreBanner findings={findings} />
      <SeveritySummary findings={findings} active={filter} onChange={setFilter} />
      <AtAGlanceSection findings={findings} onJump={handleJumpToIssue} />
      <InsuranceRequirementsSection insuranceRequirements={insuranceRequirements} />
      <ResolvedFindingsSection resolvedFindings={resolvedFindings} />"""
    if old_render not in content:
        raise SystemExit("Expected top-of-render block not found in ResultsView.tsx — aborting.")
    content = content.replace(old_render, new_render)

    old_list = """        {visible.map((f, i) => (
          <IssueCard
            key={f.uid}
            index={i}
            finding={f}
            selected={selected.has(f.uid)}
            onToggleSelect={() => toggle(f.uid)}
            clientNotes={clientNotes}
            threadMessages={threads[f.uid] ?? []}
            onPersistThread={(msgs) => persistThread(f.uid, msgs)}
            redlineText={redlines[f.uid]}
          />
        ))}"""
    new_list = """        {visible.map((f, i) => (
          <div key={f.uid} id={`issue-${f.uid}`} className="scroll-mt-20">
            <IssueCard
              index={i}
              finding={f}
              selected={selected.has(f.uid)}
              onToggleSelect={() => toggle(f.uid)}
              clientNotes={clientNotes}
              threadMessages={threads[f.uid] ?? []}
              onPersistThread={(msgs) => persistThread(f.uid, msgs)}
              redlineText={redlines[f.uid]}
            />
          </div>
        ))}"""
    if old_list not in content:
        raise SystemExit("Expected issue-card list not found in ResultsView.tsx — aborting.")
    content = content.replace(old_list, new_list)

    old_section_fn = """function ResolvedFindingsSection({ resolvedFindings }: { resolvedFindings: ResolvedFinding[] }) {"""
    new_section_fn = """function AtAGlanceSection({ findings, onJump }: { findings: Finding[]; onJump: (uid: string) => void }) {
  if (findings.length === 0) return null;

  return (
    <div className="rounded-sm border border-rule bg-paper p-5">
      <p className="mb-3 font-mono text-[11px] uppercase tracking-wide text-ink-faint">
        At a glance — click any row to jump to full detail
      </p>
      <div>
        {findings.map((f, i) => (
          <button
            key={f.uid}
            type="button"
            onClick={() => onJump(f.uid)}
            className="flex w-full items-center gap-3 border-b border-rule py-2 text-left last:border-0 hover:bg-accent-soft/20"
          >
            <span className="w-6 font-mono text-xs text-ink-faint">{String(i + 1).padStart(2, '0')}</span>
            <SeverityBadge severity={f.severity} />
            <span className="flex-1 font-body text-sm text-ink">{f.issueTitle}</span>
          </button>
        ))}
      </div>
    </div>
  );
}

function ResolvedFindingsSection({ resolvedFindings }: { resolvedFindings: ResolvedFinding[] }) {"""
    if old_section_fn not in content:
        raise SystemExit("Expected ResolvedFindingsSection function not found in ResultsView.tsx — aborting.")
    content = content.replace(old_section_fn, new_section_fn)

    with open(path, "w") as f:
        f.write(content)
    print("ResultsView.tsx: added an 'At a glance' jump list to the top of the live results view.")
PYEOF

echo ""
echo "Restart your dev server and run (or reopen) a review with a few"
echo "findings:"
echo "  1. An 'At a glance' panel should appear right below the severity"
echo "     filter row — numbered rows with a severity pill and title, same"
echo "     idea as the PDF/HTML exports."
echo "  2. Click a row — it should scroll smoothly down to that issue's full"
echo "     card, clearing any active severity filter first so the row is"
echo "     never a dead link."
echo "  3. A review with zero findings should show nothing new — the panel"
echo "     only renders when there's something to list."
echo ""
echo "Then npm run build, commit, and push (via GitHub Desktop) to deploy."
