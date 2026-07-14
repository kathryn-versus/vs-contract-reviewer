'use client';

import { createElement } from 'react';
import { pdf } from '@react-pdf/renderer';
import { ContractReportPdf } from './ContractReportPdf';
import type { ContractDoc, Finding, InsuranceRequirement } from '@/lib/types';

export async function downloadReportPdf(params: {
  contract: Pick<ContractDoc, 'clientName' | 'projectName' | 'projectNumber' | 'docType' | 'counterparty'>;
  findings: Finding[];
  insuranceRequirements?: InsuranceRequirement[];
  redlines: Record<string, string>;
  filename: string;
  sourceFileName?: string | null;
}): Promise<Blob> {
  const element = createElement(ContractReportPdf, {
    contract: params.contract,
    findings: params.findings,
    insuranceRequirements: params.insuranceRequirements ?? [],
    redlines: params.redlines,
    fileName: params.sourceFileName,
  });
  // react-pdf's pdf() type signature expects a <Document> element directly.
  // ContractReportPdf is a component that renders one internally, so what it
  // produces at runtime is correct, but its own prop types don't structurally
  // match DocumentProps — a known friction point with this library. Cast to
  // bypass the overly strict check rather than fight react-pdf's types.
  const blob = await pdf(element as Parameters<typeof pdf>[0]).toBlob();

  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = params.filename;
  a.click();
  URL.revokeObjectURL(url);

  // Returned so callers can also stash a copy in Drive without re-rendering.
  return blob;
}
