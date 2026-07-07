'use client';

import { useEffect, useRef, useState } from 'react';

export interface ComboboxOption {
  id: string;
  label: string;
  sublabel?: string;
}

/**
 * Lightweight searchable dropdown: type to filter existing options, click one
 * to select it, or (if provided) click the "create new" row to signal that
 * whatever's typed doesn't exist yet. No external dependency — just a text
 * input plus a floating option list.
 */
export function Combobox({
  value,
  onChange,
  options,
  onSelect,
  placeholder,
  onCreateNew,
  createNewLabel,
}: {
  value: string;
  onChange: (text: string) => void;
  options: ComboboxOption[];
  onSelect: (option: ComboboxOption) => void;
  placeholder?: string;
  onCreateNew?: () => void;
  createNewLabel?: string;
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function onClickOutside(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener('mousedown', onClickOutside);
    return () => document.removeEventListener('mousedown', onClickOutside);
  }, []);

  const filtered = value.trim()
    ? options.filter((o) =>
        (o.label + ' ' + (o.sublabel ?? '')).toLowerCase().includes(value.trim().toLowerCase())
      )
    : options;

  return (
    <div className="relative" ref={ref}>
      <input
        value={value}
        onChange={(e) => {
          onChange(e.target.value);
          setOpen(true);
        }}
        onFocus={() => setOpen(true)}
        placeholder={placeholder}
        className="input"
      />
      {open && (filtered.length > 0 || onCreateNew) && (
        <div className="absolute z-20 mt-1 max-h-56 w-full overflow-y-auto rounded-sm border border-rule bg-paper shadow-md">
          {filtered.length === 0 && (
            <p className="px-3 py-2 font-mono text-xs text-ink-faint">No matches yet</p>
          )}
          {filtered.map((o) => (
            <button
              key={o.id}
              type="button"
              onMouseDown={(e) => e.preventDefault()}
              onClick={() => {
                onSelect(o);
                setOpen(false);
              }}
              className="flex w-full items-baseline justify-between gap-3 px-3 py-2 text-left text-sm hover:bg-accent-soft/20"
            >
              <span className="text-ink">{o.label}</span>
              {o.sublabel && <span className="font-mono text-xs text-ink-faint">{o.sublabel}</span>}
            </button>
          ))}
          {onCreateNew && (
            <button
              type="button"
              onMouseDown={(e) => e.preventDefault()}
              onClick={() => {
                onCreateNew();
                setOpen(false);
              }}
              className="block w-full border-t border-rule px-3 py-2 text-left font-mono text-xs text-accent hover:bg-accent-soft/20"
            >
              {createNewLabel ?? '+ Create new'}
            </button>
          )}
        </div>
      )}
    </div>
  );
}
