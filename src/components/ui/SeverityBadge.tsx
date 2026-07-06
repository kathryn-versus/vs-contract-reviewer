import clsx from 'clsx';
import type { Severity } from '@/lib/types';

const styles: Record<Severity, string> = {
  high: 'text-high bg-high-bg border-high/30',
  medium: 'text-med bg-med-bg border-med/30',
  low: 'text-low bg-low-bg border-low/30',
};

export function SeverityBadge({ severity }: { severity: Severity }) {
  return (
    <span
      className={clsx(
        'inline-flex items-center rounded-full border px-2 py-0.5 font-mono text-[11px] uppercase tracking-wide',
        styles[severity]
      )}
    >
      {severity}
    </span>
  );
}
