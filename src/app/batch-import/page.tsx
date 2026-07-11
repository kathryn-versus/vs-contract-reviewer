import { AuthGuard } from '@/components/layout/AuthGuard';
import { AppShell } from '@/components/layout/AppShell';
import { BatchImportView } from '@/components/intake/BatchImportView';

export default function BatchImportPage() {
  return (
    <AuthGuard>
      <AppShell>
        <BatchImportView />
      </AppShell>
    </AuthGuard>
  );
}
