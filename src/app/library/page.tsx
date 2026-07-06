'use client';

import { AuthGuard } from '@/components/layout/AuthGuard';
import { AppShell } from '@/components/layout/AppShell';
import { ClientListView } from '@/components/library/ClientListView';

export default function LibraryPage() {
  return (
    <AuthGuard requireRole="admin">
      <AppShell>
        <ClientListView />
      </AppShell>
    </AuthGuard>
  );
}
