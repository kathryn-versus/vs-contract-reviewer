'use client';

// Tracks recently-viewed clients in localStorage — a lightweight convenience
// for the Library home page, not critical data, so every function here fails
// silently rather than throwing (e.g. if localStorage is unavailable, as in
// some private-browsing modes).

const RECENTS_KEY = 'vs_recent_clients';
const MAX_RECENTS = 8;

export function getRecentClientIds(): string[] {
  if (typeof window === 'undefined') return [];
  try {
    const raw = localStorage.getItem(RECENTS_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

export function recordRecentClient(clientId: string) {
  if (typeof window === 'undefined') return;
  try {
    const existing = getRecentClientIds().filter((id) => id !== clientId);
    const updated = [clientId, ...existing].slice(0, MAX_RECENTS);
    localStorage.setItem(RECENTS_KEY, JSON.stringify(updated));
  } catch {
    // Non-fatal.
  }
}
