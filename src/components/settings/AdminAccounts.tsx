'use client';

import { useEffect, useState } from 'react';
import { Card } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';
import { listUsers, setUserRole } from '@/lib/firebase/firestore';
import type { UserDoc } from '@/lib/types';

export function AdminAccounts() {
  const [users, setUsers] = useState<UserDoc[]>([]);

  function refresh() {
    listUsers().then(setUsers);
  }

  useEffect(refresh, []);

  return (
    <Card className="p-5">
      <p className="mb-4 font-mono text-[11px] uppercase tracking-wide text-ink-faint">Admin accounts</p>
      <div className="space-y-2">
        {users.map((u) => (
          <div key={u.uid} className="flex items-center justify-between border-b border-rule py-2 text-sm">
            <div>
              <p className="text-ink">{u.name}</p>
              <p className="font-mono text-xs text-ink-faint">{u.email}</p>
            </div>
            <div className="flex items-center gap-3">
              <span className="font-mono text-xs uppercase text-ink-faint">{u.role}</span>
              <Button
                variant="ghost"
                onClick={async () => {
                  await setUserRole(u.uid, u.role === 'admin' ? 'reviewer' : 'admin');
                  refresh();
                }}
              >
                {u.role === 'admin' ? 'Remove admin' : 'Make admin'}
              </Button>
            </div>
          </div>
        ))}
        {users.length === 0 && <p className="font-mono text-sm text-ink-faint">No users have signed in yet.</p>}
      </div>
    </Card>
  );
}
