#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_prominent_upload_button.sh
#
# The "+ Upload contract" link was already added to the client page (same
# file as the MSA upload/No-MSA controls you confirmed working), but it was
# a small inline text link next to the client name — easy to miss. This
# upgrades it to a real button on the right side of the header, matching the
# "Batch import" button style on the Library home.
set -e

python3 - << 'PYEOF'
path = "src/components/library/ClientDetailView.tsx"
with open(path) as f:
    content = f.read()

old = """      <div>
        <div className="flex flex-wrap items-center gap-3">
          <h1 className="font-display text-2xl text-ink">{client.name}</h1>
          {client.driveFolderUrl ? (
            <a
              href={client.driveFolderUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="font-mono text-xs text-accent hover:underline"
            >
              Drive folder ↗
            </a>
          ) : (
            <button
              type="button"
              onClick={handleEnsureFolder}
              disabled={creatingFolder}
              className="font-mono text-xs text-ink-faint hover:text-ink disabled:opacity-50"
            >
              {creatingFolder ? 'Creating…' : '+ Create Drive folder'}
            </button>
          )}
          <Link
            href={`/?clientName=${encodeURIComponent(client.name)}`}
            className="font-mono text-xs text-accent hover:underline"
          >
            + Upload contract
          </Link>
        </div>
        <p className="font-mono text-xs text-ink-faint">{contracts.length} matters on file</p>
      </div>"""

new = """      <div>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex flex-wrap items-center gap-3">
            <h1 className="font-display text-2xl text-ink">{client.name}</h1>
            {client.driveFolderUrl ? (
              <a
                href={client.driveFolderUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="font-mono text-xs text-accent hover:underline"
              >
                Drive folder ↗
              </a>
            ) : (
              <button
                type="button"
                onClick={handleEnsureFolder}
                disabled={creatingFolder}
                className="font-mono text-xs text-ink-faint hover:text-ink disabled:opacity-50"
              >
                {creatingFolder ? 'Creating…' : '+ Create Drive folder'}
              </button>
            )}
          </div>
          <Link href={`/?clientName=${encodeURIComponent(client.name)}`}>
            <Button variant="secondary">+ Upload contract</Button>
          </Link>
        </div>
        <p className="font-mono text-xs text-ink-faint">{contracts.length} matters on file</p>
      </div>"""

if "justify-between gap-3\">\n          <div className=\"flex flex-wrap items-center gap-3\">" in content:
    print("ClientDetailView.tsx: upload button already prominent — nothing to do.")
elif old in content:
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("ClientDetailView.tsx: '+ Upload contract' is now a visible button.")
else:
    raise SystemExit(
        "Expected header block not found in "
        "src/components/library/ClientDetailView.tsx — the file may have "
        "changed since I last wrote it. Paste me the current file (cat "
        "src/components/library/ClientDetailView.tsx) and I'll fix it by hand."
    )
PYEOF

echo ""
echo "Restart your dev server and check a client's page — you should see a"
echo "clear 'Upload contract' button on the right side of the header, next"
echo "to the client name and Drive folder link on the left."
echo ""
echo "If you genuinely don't see ANY version of this (button or the old"
echo "text link) even after this, let me know — that'd mean something else"
echo "is going on and I'll dig further rather than guess again."
echo ""
echo "Then commit and push (via GitHub Desktop) to deploy."
