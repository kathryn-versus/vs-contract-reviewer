'use client';

import { createElement } from 'react';
import { pdf } from '@react-pdf/renderer';
import { ContractReportPdf } from './ContractReportPdf';
import type { ContractDoc, Finding } from '@/lib/types';

export async function downloadReportPdf(params: {
  contract: Pick<ContractDoc, 'clientName' | 'projectName' | 'projectNumber' | 'docType' | 'counterparty'>;
  findings: Finding[];
  redlines: Record<string, string>;
  filename: string;
  sourceFileName?: string | null;
}): Promise<Blob> {
  const element = createElement(ContractReportPdf, {
    contract: params.contract,
    findings: params.findings,
    redlines: params.redlines,
    fileName: params.sourceFileName,
  });
  const blob = await pdf(element).toBlob();

  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = params.filename;
  a.click();
  URL.revokeObjectURL(url);

  // Returned so callers can also stash a copy in Drive without re-rendering.
  return blob;
}
