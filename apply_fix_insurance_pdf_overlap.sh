#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_fix_insurance_pdf_overlap.sh
set -e

python3 - << 'PYEOF'
path = "src/lib/report/ContractReportPdf.tsx"
with open(path) as f:
    content = f.read()

if "insuranceRow:" in content:
    print("ContractReportPdf.tsx: already fixed — nothing to do.")
else:
    # The "At a glance" findings row (execRow/execTitle, flexDirection: row +
    # alignItems: center) works fine because every issueTitle is a short,
    # single-line string by design (the analysis prompt caps it at ~12
    # words). Insurance rows were built by reusing that same row/flex/
    # center-aligned pattern, but requirement + limit + flag text is often
    # multiple long, wrapping sentences — react-pdf's layout engine
    # miscalculates row height for wrapped multi-line text inside an
    # alignItems: 'center' flex row, which renders as every insurance row
    # stacked on top of each other instead of flowing down the page. The
    # findings section never hits this because it stacks Text elements
    # directly with no row/flex/center-align wrapper at all — this gives
    # insurance rows that same plain vertical-stack treatment instead.
    old_styles = """  execTitle: { fontSize: 9, fontFamily: 'Helvetica', flex: 1 },
});"""
    new_styles = """  execTitle: { fontSize: 9, fontFamily: 'Helvetica', flex: 1 },

  insuranceRow: { borderBottomWidth: 1, borderBottomColor: '#DEDDD6', paddingVertical: 6 },
  insuranceTitle: { fontSize: 9, fontFamily: 'Helvetica', lineHeight: 1.35 },
  insuranceFlag: { fontSize: 8, fontFamily: 'Helvetica', color: '#C97A22', marginTop: 2, lineHeight: 1.35 },
});"""
    if old_styles not in content:
        raise SystemExit("Expected execTitle style block not found in ContractReportPdf.tsx — aborting.")
    content = content.replace(old_styles, new_styles)

    old_jsx = """            {insuranceRequirements.map((r, i) => (
              <View key={i} style={styles.execRow}>
                <View style={{ flex: 1 }}>
                  <Text style={styles.execTitle}>
                    {r.requirement} — {r.limit}
                  </Text>
                  {r.flag && (
                    <Text style={[styles.execTitle, { color: '#C97A22', fontSize: 8 }]}>{r.flag}</Text>
                  )}
                </View>
              </View>
            ))}"""
    new_jsx = """            {insuranceRequirements.map((r, i) => (
              <View key={i} style={styles.insuranceRow}>
                <Text style={styles.insuranceTitle}>
                  {r.requirement} — {r.limit}
                </Text>
                {r.flag && <Text style={styles.insuranceFlag}>{r.flag}</Text>}
              </View>
            ))}"""
    if old_jsx not in content:
        raise SystemExit("Expected insurance requirements JSX not found in ContractReportPdf.tsx — aborting.")
    content = content.replace(old_jsx, new_jsx)

    with open(path, "w") as f:
        f.write(content)
    print("ContractReportPdf.tsx: insurance rows now use a plain vertical stack instead of the row/center-align pattern that was overlapping.")
PYEOF

echo ""
echo "Restart your dev server and download a PDF report for a matter that has"
echo "insurance requirements on file (the Omnicom/Novartis Kisqali one you"
echo "flagged is a good test — it has 4 long, multi-sentence entries). The"
echo "insurance section should now read top-to-bottom cleanly, each entry"
echo "separated by a thin rule, instead of overlapping into an unreadable"
echo "block. The HTML report/on-screen results were never affected — this"
echo "only touches the PDF export."
echo ""
echo "Then npm run build, commit, and push (via GitHub Desktop) to deploy."
