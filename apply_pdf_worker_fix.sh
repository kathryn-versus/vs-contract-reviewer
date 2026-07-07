#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_pdf_worker_fix.sh
set -e

mkdir -p "$(dirname "src/lib/parsing/extractText.ts")"
cat > "src/lib/parsing/extractText.ts" << 'VS_APPLY_EOF_pdfworker'
'use client';

// Client-side text extraction — PDF via pdf.js, DOCX via mammoth.js, per
// brief §4.1 ("extract text client-side (pdf.js for PDF, mammoth.js for DOCX)").

export async function extractText(file: File): Promise<string> {
  const name = file.name.toLowerCase();

  if (name.endsWith('.pdf') || file.type === 'application/pdf') {
    return extractPdfText(file);
  }
  if (name.endsWith('.docx')) {
    return extractDocxText(file);
  }
  if (name.endsWith('.txt') || file.type === 'text/plain') {
    return file.text();
  }
  throw new Error('Unsupported file type. Please upload a PDF, DOCX, or TXT file.');
}

async function extractPdfText(file: File): Promise<string> {
  const pdfjs = await import('pdfjs-dist');
  // Load the worker from a CDN pinned to the exact installed pdfjs-dist
  // version, rather than letting Next's bundler resolve it via
  // import.meta.url — that path was 404ing in dev ("Setting up fake worker
  // failed: Failed to fetch dynamically imported module ... pdf.worker.min
  // ....mjs") because the hashed worker asset wasn't reliably emitted/served.
  // pdf.js is strict about the worker and API versions matching exactly, so
  // this reads the version straight off the loaded library instead of
  // hardcoding it.
  pdfjs.GlobalWorkerOptions.workerSrc = `https://unpkg.com/pdfjs-dist@${pdfjs.version}/build/pdf.worker.min.mjs`;

  const buffer = await file.arrayBuffer();
  const doc = await pdfjs.getDocument({ data: buffer }).promise;

  let text = '';
  for (let i = 1; i <= doc.numPages; i++) {
    const page = await doc.getPage(i);
    const content = await page.getTextContent();
    text += content.items.map((item) => ('str' in item ? item.str : '')).join(' ') + '\n\n';
  }
  return text.trim();
}

async function extractDocxText(file: File): Promise<string> {
  const mammoth = await import('mammoth/mammoth.browser');
  const buffer = await file.arrayBuffer();
  const result = await mammoth.extractRawText({ arrayBuffer: buffer });
  return result.value.trim();
}
VS_APPLY_EOF_pdfworker

echo ""
echo "Done. 1 file updated: src/lib/parsing/extractText.ts"
echo "No new npm packages needed — restart your dev server (Ctrl+C, then npm run dev) and try uploading the PDF again."
echo "Note: this now loads the pdf.js worker from unpkg.com at runtime, so it needs normal internet access (fine for local dev and once deployed)."
