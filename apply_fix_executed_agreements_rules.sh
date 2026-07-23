#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_fix_executed_agreements_rules.sh
set -e

python3 - << 'PYEOF'
path = "firestore.rules"
with open(path) as f:
    content = f.read()

if "path=**}/executedAgreements" in content:
    print("firestore.rules: already present — nothing to do.")
else:
    old = """      match /executedAgreements/{agreementId} {
        allow read: if isSignedIn();
        allow write: if isAdmin();
      }
    }"""
    new = """      match /executedAgreements/{agreementId} {
        allow read: if isSignedIn();
        allow write: if isAdmin();
      }
    }

    // Explicit collection-group rule for executedAgreements — belt-and-
    // suspenders alongside the nested match above, so a collectionGroup()
    // query (used by the Library's contracts tracker and client list to
    // read executed agreements across every client at once) is unambiguously
    // covered under Firestore's rules resolution, not just direct per-client
    // subcollection access.
    match /{path=**}/executedAgreements/{agreementId} {
      allow read: if isSignedIn();
    }"""
    if old not in content:
        raise SystemExit("Expected executedAgreements match block not found in firestore.rules — aborting.")
    content = content.replace(old, new)

    with open(path, "w") as f:
        f.write(content)
    print("firestore.rules: added explicit collection-group read rule for executedAgreements.")
PYEOF

echo ""
echo "IMPORTANT — this is a rules change, not app code. npm run build and a"
echo "normal git push will NOT deploy this. You need a SEPARATE command:"
echo ""
echo "  firebase deploy --only firestore:rules"
echo ""
echo "(If that errors with an auth/credentials message, run"
echo "'firebase login --reauth' first, then retry the deploy command above.)"
echo ""
echo "After that finishes, reload /library — the red 'executed agreements:"
echo "Missing or insufficient permissions' banner should be gone, the"
echo "Eversana DSE Animation row should show as Executed (not Open), and any"
echo "other already-executed contracts should show correctly too."
echo ""
echo "This also explains the earlier 'missing agreement' mismatch — the"
echo "Library page couldn't read ANY executed agreements at all, so every"
echo "contract fell back to showing as Open/Received regardless of what's"
echo "actually on file, even though the client page (which loads this data"
echo "differently) showed it correctly."
