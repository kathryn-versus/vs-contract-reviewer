'use client';

import { useState } from 'react';
import { Card } from '@/components/ui/Card';
import { Button } from '@/components/ui/Button';

// Note: the actual DRIVE_ROOT_FOLDER_ID env var is server-side config —
// changing it here is a UI affordance that should call an admin API route
// wired to your secrets manager. Left as a controlled input for now.
export function DriveConfig({ currentFolderId }: { currentFolderId: string }) {
  const [folderId, setFolderId] = useState(currentFolderId);
  const [saved, setSaved] = useState(false);

  return (
    <Card className="p-5">
      <p className="mb-4 font-mono text-[11px] uppercase tracking-wide text-ink-faint">
        Drive folder configuration
      </p>
      <label className="block">
        <span className="mb-1 block font-mono text-xs text-ink-faint">Root folder ID</span>
        <input
          value={folderId}
          onChange={(e) => {
            setFolderId(e.target.value);
            setSaved(false);
          }}
          className="w-full border border-rule px-3 py-2 font-mono text-sm outline-none focus:border-ink"
        />
      </label>
      <div className="mt-3 flex items-center gap-3">
        <Button variant="primary" onClick={() => setSaved(true)}>
          Update (requires redeploy of DRIVE_ROOT_FOLDER_ID)
        </Button>
        {saved && <span className="font-mono text-xs text-low">Noted — update the env var and redeploy.</span>}
      </div>
    </Card>
  );
}
