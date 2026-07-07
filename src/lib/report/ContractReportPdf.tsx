import { Document, Page, View, Text, StyleSheet } from '@react-pdf/renderer';
import { STANDING_CONCERNS, CONCERN_SHORT_LABELS } from '@/lib/types';
import type { ContractDoc, Finding } from '@/lib/types';

const SEVERITY_COLOR: Record<string, string> = {
  high: '#8A3324',
  medium: '#A8761E',
  low: '#5A6B4F',
};

const SEVERITY_BG: Record<string, string> = {
  high: '#F3E4DF',
  medium: '#F4ECDA',
  low: '#E7ECE1',
};

// Built-in PDF fonts only (no network font registration, so generation can
// never silently fail on a bad font URL): Times-* stands in for the site's
// Georgia serif headings, Courier for its monospace labels/meta, Helvetica
// for body copy — mirroring the same three-typeface split used in the HTML
// report and the on-screen results view.
const styles = StyleSheet.create({
  page: { padding: 40, paddingBottom: 56, fontSize: 10, fontFamily: 'Helvetica', color: '#1C1B19', backgroundColor: '#F7F5F1' },

  eyebrow: { fontSize: 8, letterSpacing: 1.5, textTransform: 'uppercase', color: '#8C8777', marginBottom: 8, fontFamily: 'Courier' },
  masthead: { fontSize: 22, fontFamily: 'Times-Bold', marginBottom: 10 },
  mastheadAccent: { color: '#8A3324' },

  concernIndex: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    borderBottomWidth: 2,
    borderBottomColor: '#1C1B19',
    paddingBottom: 10,
    marginBottom: 16,
  },
  concernItem: { fontSize: 8, fontFamily: 'Courier', color: '#5B574D', marginRight: 12, marginBottom: 3 },
  concernNum: { fontFamily: 'Courier-Bold', color: '#1C1B19' },

  title: { fontSize: 16, fontFamily: 'Times-Bold', marginBottom: 4 },
  meta: { fontSize: 9, fontFamily: 'Courier', color: '#5B574D', marginBottom: 18 },

  summaryRow: { flexDirection: 'row', marginBottom: 22 },
  summaryBox: { flex: 1, borderWidth: 1, borderColor: '#D8D3C7', paddingVertical: 10, paddingHorizontal: 8, marginRight: 8, textAlign: 'center', backgroundColor: '#FFFFFF' },
  summaryNum: { fontSize: 20, fontFamily: 'Times-Bold', marginBottom: 3 },
  summaryLabel: { fontSize: 7, fontFamily: 'Courier', textTransform: 'uppercase', color: '#8C8777' },

  issue: { borderWidth: 1, borderColor: '#D8D3C7', borderLeftWidth: 4, padding: 14, marginBottom: 12, backgroundColor: '#FFFFFF' },
  issueHeaderRow: { flexDirection: 'row', alignItems: 'center', marginBottom: 8 },
  issueIndex: { fontSize: 9, fontFamily: 'Courier', color: '#8C8777', marginRight: 8 },
  severityPill: { borderWidth: 1, borderRadius: 8, paddingVertical: 2, paddingHorizontal: 7, marginRight: 8 },
  severityPillText: { fontSize: 8, fontFamily: 'Courier-Bold', textTransform: 'uppercase' },
  issueConcern: { fontSize: 8, fontFamily: 'Courier', textTransform: 'uppercase', color: '#8C8777' },

  issueTitle: { fontSize: 12.5, fontFamily: 'Times-Bold', marginBottom: 4 },
  issueLocation: { fontSize: 8, fontFamily: 'Courier', color: '#8C8777', marginBottom: 8 },

  sectionLabel: { fontSize: 7.5, fontFamily: 'Courier-Bold', textTransform: 'uppercase', letterSpacing: 0.5, color: '#8C8777', marginTop: 8, marginBottom: 3 },
  quote: { fontSize: 9.5, fontFamily: 'Times-Italic', color: '#5B574D', borderLeftWidth: 2, borderLeftColor: '#D8D3C7', paddingLeft: 10, lineHeight: 1.4 },
  body: { fontSize: 9.5, lineHeight: 1.45, fontFamily: 'Helvetica' },
  redline: { fontSize: 8.5, fontFamily: 'Courier', backgroundColor: '#EFE9DC', padding: 8, marginTop: 2, lineHeight: 1.4 },

  footer: { position: 'absolute', bottom: 20, left: 40, right: 40, flexDirection: 'row', justifyContent: 'space-between', fontSize: 7, fontFamily: 'Courier', color: '#8C8777', borderTopWidth: 1, borderTopColor: '#D8D3C7', paddingTop: 6 },
});

export function ContractReportPdf({
  contract,
  findings,
  redlines,
  generatedAt,
  fileName,
}: {
  contract: Pick<ContractDoc, 'clientName' | 'projectName' | 'projectNumber' | 'docType' | 'counterparty'>;
  findings: Finding[];
  redlines: Record<string, string>;
  generatedAt?: Date;
  fileName?: string | null;
}) {
  const when = generatedAt ?? new Date();
  const counts = {
    total: findings.length,
    high: findings.filter((f) => f.severity === 'high').length,
    medium: findings.filter((f) => f.severity === 'medium').length,
    low: findings.filter((f) => f.severity === 'low').length,
  };

  return (
    <Document>
      <Page size="LETTER" style={styles.page}>
        <Text style={styles.eyebrow}>Versus Studio · Contract Review Report</Text>
        <Text style={styles.masthead}>
          Contract Review <Text style={styles.mastheadAccent}>VS</Text>
        </Text>

        <View style={styles.concernIndex}>
          {STANDING_CONCERNS.map((c) => (
            <Text key={c.id} style={styles.concernItem}>
              <Text style={styles.concernNum}>{c.id}. </Text>
              {CONCERN_SHORT_LABELS[c.id] ?? c.label}
            </Text>
          ))}
        </View>

        <Text style={styles.title}>
          {contract.clientName} — {contract.projectNumber} — {contract.projectName}
        </Text>
        <Text style={styles.meta}>
          {contract.docType} · Counterparty: {contract.counterparty} · Reviewed against {STANDING_CONCERNS.length} standing concerns{'\n'}
          Generated {when.toLocaleString()}
          {fileName ? `\nSource file: ${fileName}` : ''}
        </Text>

        <View style={styles.summaryRow}>
          <View style={styles.summaryBox}>
            <Text style={styles.summaryNum}>{counts.total}</Text>
            <Text style={styles.summaryLabel}>Total flagged</Text>
          </View>
          <View style={styles.summaryBox}>
            <Text style={styles.summaryNum}>{counts.high}</Text>
            <Text style={styles.summaryLabel}>High</Text>
          </View>
          <View style={styles.summaryBox}>
            <Text style={styles.summaryNum}>{counts.medium}</Text>
            <Text style={styles.summaryLabel}>Medium</Text>
          </View>
          <View style={[styles.summaryBox, { marginRight: 0 }]}>
            <Text style={styles.summaryNum}>{counts.low}</Text>
            <Text style={styles.summaryLabel}>Low</Text>
          </View>
        </View>

        {findings.length === 0 && (
          <Text style={styles.body}>No issues flagged against the {STANDING_CONCERNS.length} standing concerns.</Text>
        )}

        {findings.map((f, i) => (
          <View key={f.uid} style={[styles.issue, { borderLeftColor: SEVERITY_COLOR[f.severity] }]}>
            <View style={styles.issueHeaderRow}>
              <Text style={styles.issueIndex}>{String(i + 1).padStart(2, '0')}</Text>
              <View style={[styles.severityPill, { borderColor: SEVERITY_COLOR[f.severity], backgroundColor: SEVERITY_BG[f.severity] }]}>
                <Text style={[styles.severityPillText, { color: SEVERITY_COLOR[f.severity] }]}>{f.severity}</Text>
              </View>
              <Text style={styles.issueConcern}>
                Concern {f.concernId} · {f.concernLabel}
              </Text>
            </View>

            <Text style={styles.issueTitle}>{f.issueTitle}</Text>
            {f.location ? <Text style={styles.issueLocation}>{f.location}</Text> : null}

            <Text style={styles.sectionLabel}>Contract language</Text>
            <Text style={styles.quote}>&ldquo;{f.quote}&rdquo;</Text>

            <Text style={styles.sectionLabel}>Why it matters</Text>
            <Text style={styles.body}>{f.analysis}</Text>

            <Text style={styles.sectionLabel}>Suggested negotiation direction</Text>
            <Text style={styles.body}>{f.recommendation}</Text>

            {redlines[f.uid] && (
              <>
                <Text style={styles.sectionLabel}>Drafted redline</Text>
                <Text style={styles.redline}>{redlines[f.uid]}</Text>
              </>
            )}
          </View>
        ))}

        <View style={styles.footer} fixed>
          <Text>
            {contract.clientName} — {contract.projectName} ({contract.projectNumber})
          </Text>
          <Text
            render={({ pageNumber, totalPages }) => `Page ${pageNumber} of ${totalPages}`}
          />
        </View>
      </Page>
    </Document>
  );
}
