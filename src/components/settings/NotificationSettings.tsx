'use client';

import { Card } from '@/components/ui/Card';

export function NotificationSettings({
  primary,
  secondary,
}: {
  primary: string;
  secondary: string | null;
}) {
  return (
    <Card className="p-5">
      <p className="mb-4 font-mono text-[11px] uppercase tracking-wide text-ink-faint">
        Notification recipients
      </p>
      <div className="space-y-2 text-sm">
        <div className="flex items-center justify-between border-b border-rule py-2">
          <span className="text-ink">{primary}</span>
          <span className="font-mono text-xs uppercase text-low">Active</span>
        </div>
        <div className="flex items-center justify-between py-2">
          <span className="text-ink-soft">{secondary ?? 'samantha@vsnyc.tv'}</span>
          <span className="font-mono text-xs uppercase text-ink-faint">
            {secondary ? 'Active' : 'Commented out — testing'}
          </span>
        </div>
      </div>
      <p className="mt-3 font-body text-xs text-ink-faint">
        Toggle by setting NOTIFY_EMAIL_SECONDARY in your environment config and redeploying.
      </p>
    </Card>
  );
}
