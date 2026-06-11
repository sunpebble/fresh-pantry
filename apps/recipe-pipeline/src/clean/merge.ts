import type { CleanRecipe } from './schema';

export interface MergeOptions {
  refreshDescriptions?: boolean;
}

export interface MergeResult {
  merged: CleanRecipe[];
  stats: { added: number; updated: number; unchanged: number };
}

export function mergeWithExisting(
  fresh: CleanRecipe[],
  existing: CleanRecipe[],
  now: string,
  opts: MergeOptions = {},
): MergeResult {
  void now;
  const byId = new Map<string, CleanRecipe>(existing.map((r) => [r.id, r]));
  const stats = { added: 0, updated: 0, unchanged: 0 };

  for (const f of fresh) {
    const prev = byId.get(f.id);
    if (!prev) {
      byId.set(f.id, { ...f, remoteVersion: 0, clientUpdatedAt: null, deletedAt: null });
      stats.added++;
      continue;
    }
    if (prev.deletedAt) {
      stats.unchanged++;
      continue;
    }
    const description =
      prev.description && !opts.refreshDescriptions ? prev.description : f.description;
    byId.set(f.id, {
      ...f,
      imageUrl: prev.imageUrl ?? f.imageUrl,
      description,
      remoteVersion: prev.remoteVersion,
      clientUpdatedAt: prev.clientUpdatedAt,
      deletedAt: prev.deletedAt,
    });
    stats.updated++;
  }

  const merged = [...byId.values()].sort((a, b) => a.id.localeCompare(b.id));
  return { merged, stats };
}
