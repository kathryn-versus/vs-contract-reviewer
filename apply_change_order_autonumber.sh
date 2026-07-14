#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_change_order_autonumber.sh
set -e

python3 - << 'PYEOF'
path = "src/components/library/ClientDetailView.tsx"
with open(path) as f:
    content = f.read()

if "Change Order #${count" in content or "next Change Order number" in content:
    print("ClientDetailView.tsx: auto-numbering already present — nothing to do.")
else:
    old = """  const [agreementError, setAgreementError] = useState<string | null>(null);
  const { user } = useAuth();"""
    new = """  const [agreementError, setAgreementError] = useState<string | null>(null);
  const { user } = useAuth();

  // Auto-suggest the next Change Order number so multiple change orders for
  // the same client don't collide or skip numbers — still editable/
  // overridable before upload, and only fires when switching TO Change
  // Order with an empty label (never overwrites something already typed).
  // Clears the suggestion back out if you switch to a different type
  // without having edited it, so a stale "Change Order #3" doesn't linger
  // on an MSA upload.
  useEffect(() => {
    if (agreementDocType === 'Change Order') {
      if (agreementLabel.trim() !== '') return;
      const count = executedAgreements.filter((a) => a.docType === 'Change Order').length;
      setAgreementLabel(`Change Order #${count + 1}`);
    } else if (/^Change Order #\\d+$/.test(agreementLabel)) {
      setAgreementLabel('');
    }
  }, [agreementDocType, executedAgreements]);"""

    if old not in content:
        raise SystemExit(
            "Expected anchor not found in ClientDetailView.tsx — this depends on "
            "apply_executed_agreements.sh having already run successfully. If that "
            "one hasn't been applied yet, run it first."
        )
    content = content.replace(old, new)
    with open(path, "w") as f:
        f.write(content)
    print("ClientDetailView.tsx: Change Order label now auto-suggests the next number.")
PYEOF

echo ""
echo "Restart your dev server and test on a client with at least one Change"
echo "Order already on file:"
echo "  1. Pick 'Change Order' as the type — label field should auto-fill"
echo "     with the next number (e.g. 'Change Order #2')."
echo "  2. You should still be able to edit/replace it before uploading."
echo "  3. Switch to MSA/SOW/Other — the auto-filled label should clear so"
echo "     it doesn't carry over onto the wrong type."
echo ""
echo "Then commit and push (via GitHub Desktop) to deploy."
