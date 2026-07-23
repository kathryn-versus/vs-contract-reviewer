#!/usr/bin/env bash
# Run this from the root of your vs-contract-reviewer repo:
#   bash apply_tracker_error_visibility.sh
set -e

python3 - << 'PYEOF'
path = "src/components/library/ContractsTracker.tsx"
with open(path) as f:
    content = f.read()

if "loadError" in content:
    print("ContractsTracker.tsx: already present — nothing to do.")
else:
    old = """  const { user } = useAuth();
  const [clients, setClients] = useState<ClientDoc[]>([]);
  const [contracts, setContracts] = useState<ContractDoc[]>([]);
  const [executedContractIds, setExecutedContractIds] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState<FilterValue>('all');
  const [sortBy, setSortBy] = useState<'oldest' | 'client'>('oldest');
  const [uploadingId, setUploadingId] = useState<string | null>(null);

  async function refresh() {
    setLoading(true);
    try {
      const [clientsList, contractsList, agreements] = await Promise.all([
        listClients(),
        listAllContracts(),
        listAllExecutedAgreements(),
      ]);
      setClients(clientsList);
      setContracts(contractsList);
      setExecutedContractIds(
        new Set(agreements.map((a) => a.contractId).filter((id): id is string => Boolean(id)))
      );
    } finally {
      setLoading(false);
    }
  }"""
    new = """  const { user } = useAuth();
  const [clients, setClients] = useState<ClientDoc[]>([]);
  const [contracts, setContracts] = useState<ContractDoc[]>([]);
  const [executedContractIds, setExecutedContractIds] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState<FilterValue>('all');
  const [sortBy, setSortBy] = useState<'oldest' | 'client'>('oldest');
  const [uploadingId, setUploadingId] = useState<string | null>(null);

  // Each of the three loads independently (allSettled, not all) so one
  // failing — say a permissions issue on just one collection — doesn't blank
  // out the whole page silently. Any failure is logged AND shown on screen,
  // since a query that quietly returns nothing looks identical to "there's
  // truly no data" otherwise.
  async function refresh() {
    setLoading(true);
    setLoadError(null);
    try {
      const [clientsResult, contractsResult, agreementsResult] = await Promise.allSettled([
        listClients(),
        listAllContracts(),
        listAllExecutedAgreements(),
      ]);
      if (clientsResult.status === 'fulfilled') setClients(clientsResult.value);
      if (contractsResult.status === 'fulfilled') setContracts(contractsResult.value);
      if (agreementsResult.status === 'fulfilled') {
        setExecutedContractIds(
          new Set(agreementsResult.value.map((a) => a.contractId).filter((id): id is string => Boolean(id)))
        );
      }
      const failures = [
        ['clients', clientsResult] as const,
        ['contracts', contractsResult] as const,
        ['executed agreements', agreementsResult] as const,
      ].filter(([, r]) => r.status === 'rejected');
      if (failures.length > 0) {
        failures.forEach(([label, r]) => console.error(`ContractsTracker: failed to load ${label}`, (r as PromiseRejectedResult).reason));
        setLoadError(
          failures
            .map(([label, r]) => {
              const reason = (r as PromiseRejectedResult).reason;
              const message = reason instanceof Error ? reason.message : String(reason);
              return `${label}: ${message}`;
            })
            .join(' — ')
        );
      }
    } finally {
      setLoading(false);
    }
  }"""
    if old not in content:
        raise SystemExit("Expected ContractsTracker refresh() not found — aborting.")
    content = content.replace(old, new)

    old_render = """  if (loading) {
    return <p className="font-mono text-sm text-ink-faint">Loading contracts…</p>;
  }

  return (
    <div>
      <div className="mb-6 grid grid-cols-2 gap-3 sm:max-w-md">"""
    new_render = """  if (loading) {
    return <p className="font-mono text-sm text-ink-faint">Loading contracts…</p>;
  }

  return (
    <div>
      {loadError && (
        <p className="mb-4 border border-high bg-high-bg px-3 py-2 text-sm text-high">
          Could not load everything: {loadError}
        </p>
      )}
      <div className="mb-6 grid grid-cols-2 gap-3 sm:max-w-md">"""
    if old_render not in content:
        raise SystemExit("Expected loading/return block not found — aborting.")
    content = content.replace(old_render, new_render)

    with open(path, "w") as f:
        f.write(content)
    print("ContractsTracker.tsx: loads now fail independently and show a visible error if any part fails.")
PYEOF

echo ""
echo "Restart your dev server (or push to redeploy) and reload /library."
echo "If the KPIs are still 0 and the table still says 'No contracts match"
echo "this filter', you should now see a red banner naming exactly which"
echo "part failed and why (e.g. a permissions error) — send me that text"
echo "and I can fix the actual cause instead of guessing."
echo ""
echo "Then npm run build, commit, and push (via GitHub Desktop) to deploy."
