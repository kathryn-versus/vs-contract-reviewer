import clsx from 'clsx';

export function Card({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={clsx('rounded-sm border border-rule bg-paper', className)}
      {...props}
    />
  );
}
