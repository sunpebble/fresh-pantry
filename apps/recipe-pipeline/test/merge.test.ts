import { describe, it, expect } from 'vitest';
import { mergeWithExisting } from '../src/clean/merge';
import type { CleanRecipe } from '../src/clean/schema';

function rec(over: Partial<CleanRecipe> & { id: string }): CleanRecipe {
  return {
    id: over.id, name: over.name ?? '菜', category: over.category ?? '荤菜',
    difficulty: over.difficulty ?? 2, cookingMinutes: over.cookingMinutes ?? 20,
    description: over.description ?? '', ingredients: over.ingredients ?? [],
    steps: over.steps ?? [], tags: over.tags ?? [], imageUrl: over.imageUrl ?? null,
    videoUrl: over.videoUrl ?? null,
    remoteVersion: over.remoteVersion ?? 0, clientUpdatedAt: over.clientUpdatedAt ?? null,
    deletedAt: over.deletedAt ?? null,
  };
}
const NOW = '2026-06-12T00:00:00.000Z';

describe('mergeWithExisting', () => {
  it('imageUrl 既有优先;用量取 fresh;description 黏住;remoteVersion 保留', () => {
    const existing = [rec({
      id: 'a', imageUrl: 'https://img/a.jpg', description: '老描述', remoteVersion: 7,
      ingredients: [{ name: '蛋' }],
    })];
    const fresh = [rec({
      id: 'a', imageUrl: null, description: '新描述', remoteVersion: 0,
      ingredients: [{ name: '蛋', quantity: 2, unit: '个' }],
    })];
    const { merged, stats } = mergeWithExisting(fresh, existing, NOW);
    const a = merged.find((r) => r.id === 'a')!;
    expect(a.imageUrl).toBe('https://img/a.jpg');
    expect(a.description).toBe('老描述');
    expect(a.remoteVersion).toBe(7);
    expect(a.ingredients[0]).toEqual({ name: '蛋', quantity: 2, unit: '个' });
    expect(stats.updated).toBe(1);
  });

  it('refreshDescriptions 时才覆盖描述', () => {
    const existing = [rec({ id: 'a', description: '老描述' })];
    const fresh = [rec({ id: 'a', description: '新描述' })];
    const { merged } = mergeWithExisting(fresh, existing, NOW, { refreshDescriptions: true });
    expect(merged[0].description).toBe('新描述');
  });

  it('既有描述为空 -> 用新描述', () => {
    const existing = [rec({ id: 'a', description: '' })];
    const fresh = [rec({ id: 'a', description: '新描述' })];
    const { merged } = mergeWithExisting(fresh, existing, NOW);
    expect(merged[0].description).toBe('新描述');
  });

  it('软删的菜不复活、不被改写', () => {
    const existing = [rec({ id: 'a', deletedAt: '2026-01-01T00:00:00.000Z', name: '旧名' })];
    const fresh = [rec({ id: 'a', deletedAt: null, name: '新名' })];
    const { merged, stats } = mergeWithExisting(fresh, existing, NOW);
    expect(merged[0].deletedAt).toBe('2026-01-01T00:00:00.000Z');
    expect(merged[0].name).toBe('旧名');
    expect(stats.updated).toBe(0);
  });

  it('新菜:remoteVersion 0、clientUpdatedAt/deletedAt null', () => {
    const { merged, stats } = mergeWithExisting([rec({ id: 'b' })], [], NOW);
    expect(stats.added).toBe(1);
    expect(merged[0].remoteVersion).toBe(0);
    expect(merged[0].clientUpdatedAt).toBeNull();
  });

  it('本轮未触及的既有菜原样保留', () => {
    const existing = [rec({ id: 'a' }), rec({ id: 'keep' })];
    const { merged } = mergeWithExisting([rec({ id: 'a' })], existing, NOW);
    expect(merged.map((r) => r.id).sort()).toEqual(['a', 'keep']);
  });

  it('输出按 id 稳定排序', () => {
    const { merged } = mergeWithExisting([rec({ id: 'c' }), rec({ id: 'a' })], [rec({ id: 'b' })], NOW);
    expect(merged.map((r) => r.id)).toEqual(['a', 'b', 'c']);
  });

  it('stats 自洽:added+updated+unchanged === 输出总数', () => {
    const existing = [rec({ id: 'a' }), rec({ id: 'keep' }), rec({ id: 'gone', deletedAt: '2026-01-01T00:00:00.000Z' })];
    const fresh = [rec({ id: 'a' }), rec({ id: 'b' }), rec({ id: 'gone' })];
    const { merged, stats } = mergeWithExisting(fresh, existing, NOW);
    expect(stats.added).toBe(1);   // b
    expect(stats.updated).toBe(1); // a
    expect(stats.added + stats.updated + stats.unchanged).toBe(merged.length);
  });

  it('更新既有菜时保留 clientUpdatedAt', () => {
    const existing = [rec({ id: 'a', clientUpdatedAt: '2026-05-01T00:00:00.000Z' })];
    const { merged } = mergeWithExisting([rec({ id: 'a', name: '新名' })], existing, NOW);
    expect(merged[0].clientUpdatedAt).toBe('2026-05-01T00:00:00.000Z');
    expect(merged[0].name).toBe('新名');
  });

  it('既有描述含 markdown 残留(旧导入脏数据)→ 不黏住,用新描述自愈', () => {
    const existing = [rec({ id: 'a', description: '![小龙虾-预览图-1](./成品.jpg)' })];
    const fresh = [rec({ id: 'a', description: '麻辣鲜香的下酒菜。' })];
    const { merged } = mergeWithExisting(fresh, existing, NOW);
    expect(merged[0].description).toBe('麻辣鲜香的下酒菜。');
  });

  it('既有 template 示例菜条目被剔除(幂等防残留)', () => {
    const existing = [rec({ id: 'howtocook:template/示例菜/示例菜' }), rec({ id: 'a' })];
    const { merged } = mergeWithExisting([rec({ id: 'a' })], existing, NOW);
    expect(merged.map((r) => r.id)).toEqual(['a']);
  });
});

describe('mergeWithExisting videoUrl', () => {
  const baseV = (over: Partial<CleanRecipe> = {}): CleanRecipe => ({
    id: 'r1', name: '番茄炒蛋', category: '荤菜', difficulty: 1, cookingMinutes: 10,
    description: 'd', ingredients: [], steps: [], tags: [], imageUrl: null,
    videoUrl: null, remoteVersion: 0, clientUpdatedAt: null, deletedAt: null, ...over,
  });
  it('既有 videoUrl 优先,不被 fresh 的 null 覆盖', () => {
    const { merged } = mergeWithExisting([baseV({ videoUrl: null })], [baseV({ videoUrl: 'https://b23.tv/x' })], '2026-06-13T00:00:00Z');
    expect(merged[0].videoUrl).toBe('https://b23.tv/x');
  });
  it('既有无 videoUrl 时采纳 fresh 的', () => {
    const { merged } = mergeWithExisting([baseV({ videoUrl: 'https://youtu.be/y' })], [baseV({ videoUrl: null })], '2026-06-13T00:00:00Z');
    expect(merged[0].videoUrl).toBe('https://youtu.be/y');
  });
});
