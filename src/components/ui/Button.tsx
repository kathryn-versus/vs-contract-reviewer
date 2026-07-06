'use client';

import clsx from 'clsx';
import type { ButtonHTMLAttributes } from 'react';

type Variant = 'primary' | 'secondary' | 'ghost' | 'danger';

export function Button({
  variant = 'secondary',
  className,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant }) {
  return (
    <button
      className={clsx(
        'inline-flex items-center justify-center gap-2 rounded-sm border px-3.5 py-2 font-body text-sm font-medium transition disabled:cursor-not-allowed disabled:opacity-50',
        variant === 'primary' && 'border-ink bg-ink text-paper hover:bg-ink-soft',
        variant === 'secondary' && 'border-rule bg-paper text-ink hover:border-ink',
        variant === 'ghost' && 'border-transparent bg-transparent text-ink-soft hover:text-ink',
        variant === 'danger' && 'border-high bg-paper text-high hover:bg-high-bg',
        className
      )}
      {...props}
    />
  );
}
