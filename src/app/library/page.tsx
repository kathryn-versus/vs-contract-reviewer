'use client';

import { useState } from 'react';
import { AuthGuard } from '@/components/layout/AuthGuard';
import { AppShell } from '@/components/layout/AppShell';
import { ClientListView } from '@/components/library/ClientListView';
import { ContractsTracker } from '@/components/library/ContractsTracker';

export default function LibraryPage() {
  const [view, setView] = useState<'contracts' | 'clients'>('contracts');

  const tabClass = (active: boolean) =>
    active
      ? 'border-b-2 border-ink px-1 pb-2 font-mono text-xs uppercase tracking-wide text-ink'
      : 'border-b-2 border-transparent px-1 pb-2 font-mono text-xs uppercase tracking-wide text-ink-faint hover:text-ink';

  return (
    <AuthGuard requireRole="admin">
      <AppShell>
        <div className="mb-6 flex gap-4 border-b border-rule">
          <button type="button" onClick={() => setView('contracts')} className={tabClass(view === 'contracts')}>
            Open contracts
          </button>
          <button type="button" onClick={() => setView('clients')} className={tabClass(view === 'clients')}>
            Clients
          </button>
        </div>
        {view === 'contracts' ? <ContractsTracker /> : <ClientListView />}
      </AppShell>
    </AuthGuard>
  );
}
