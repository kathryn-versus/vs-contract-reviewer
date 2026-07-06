'use client';

import { useEffect } from 'react';
import clsx from 'clsx';

export function Drawer({
  open,
  onClose,
  title,
  children,
  widthClassName = 'w-full max-w-xl',
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  children: React.ReactNode;
  widthClassName?: string;
}) {
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose();
    }
    if (open) document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-40">
      <div
        className="absolute inset-0 bg-ink/30 backdrop-blur-[1px]"
        onClick={onClose}
        aria-hidden
      />
      <div
        className={clsx(
          'absolute right-0 top-0 h-full overflow-y-auto border-l border-rule bg-paper shadow-xl',
          widthClassName
        )}
      >
        <div className="flex items-center justify-between border-b border-rule px-6 py-4">
          <h2 className="font-display text-lg text-ink">{title}</h2>
          <button onClick={onClose} className="font-mono text-xs text-ink-faint hover:text-ink">
            ESC · Close
          </button>
        </div>
        <div className="p-6">{children}</div>
      </div>
    </div>
  );
}
