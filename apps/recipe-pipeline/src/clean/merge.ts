import type { CleanRecipe } from './schema';

export interface MergeOptions {
  refreshDescriptions?: boolean;
}

// 旧导入工具会把 markdown 图片/链接/格式符漏进 description;
// 这种脏值不享受「黏住」保护,用 fresh 值自愈
const DIRTY_DESC_RE = /!?\[[^\]]*\]\([^)]*\)|[*_`#]/;

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
      continue; // 软删的不复活、不改写;计入 unchanged(末尾统一结算)
    }
    const stickPrevDesc =
      prev.description && !opts.refreshDescriptions && !DIRTY_DESC_RE.test(prev.description);
    const description = stickPrevDesc ? prev.description : f.description;
    byId.set(f.id, {
      ...f,
      imageUrl: prev.imageUrl || f.imageUrl,
      videoUrl: prev.videoUrl || f.videoUrl,
      description,
      remoteVersion: prev.remoteVersion,
      clientUpdatedAt: prev.clientUpdatedAt,
      deletedAt: prev.deletedAt,
    });
    stats.updated++;
  }

  // dishes/template/ 是菜谱模板示例,采集层已排除;存量残留在此剔除(幂等)
  const merged = [...byId.values()]
    .filter((r) => !r.id.startsWith('howtocook:template/'))
    .sort((a, b) => a.id.localeCompare(b.id));
  stats.unchanged = merged.length - stats.added - stats.updated;
  return { merged, stats };
}
