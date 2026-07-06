'use client';

import { AuthGuard } from '@/components/layout/AuthGuard';
import { AppShell } from '@/components/layout/AppShell';
import { AdminAccounts } from '@/components/settings/AdminAccounts';
import { DriveConfig } from '@/components/settings/DriveConfig';
import { NotificationSettings } from '@/components/settings/NotificationSettings';
import { ClientLibraryManagement } from '@/components/settings/ClientLibraryManagement';

export default function SettingsPage() {
  return (
    <AuthGuard requireRole="admin">
      <AppShell>
        <div className="space-y-6">
          <h1 className="font-display text-2xl text-ink">Settings</h1>
          <AdminAccounts />
          <DriveConfig currentFolderId={process.env.NEXT_PUBLIC_DRIVE_ROOT_FOLDER_ID ?? '1xJZEDZdyC2mw6_nvKIFiGqzkpe1b5Cdv'} />
          <NotificationSettings primary="kathryn@vsnyc.tv" secondary={null} />
          <ClientLibraryManagement />
        </div>
      </AppShell>
    </AuthGuard>
  );
}
