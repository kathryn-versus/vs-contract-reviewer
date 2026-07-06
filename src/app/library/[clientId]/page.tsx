'use client';

import { AuthGuard } from '@/components/layout/AuthGuard';
import { AppShell } from '@/components/layout/AppShell';
import { ClientDetailView } from '@/components/library/ClientDetailView';

export default function ClientDetailPage({ params }: { params: { clientId: string } }) {
  return (
    <AuthGuard requireRole="admin">
      <AppShell>
        <ClientDetailView clientId={params.clientId} />
      </AppShell>
    </AuthGuard>
  );
}
