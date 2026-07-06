import clsx from 'clsx';

export function Chip({ className, ...props }: React.HTMLAttributes<HTMLSpanElement>) {
  return (
    <span
      className={clsx(
        'inline-flex items-center gap-1.5 rounded-full border border-rule bg-paper px-2.5 py-1 font-mono text-xs text-ink-soft',
        className
      )}
      {...props}
    />
  );
}
