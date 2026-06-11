import { describe, it, expect } from 'vitest';
import { mergeWithExisting } from '../src/clean/merge';
import type { CleanRecipe } from '../src/clean/schema';

function rec(over: Partial<CleanRecipe> & { id: string }): CleanRecipe {
  return {
    id: over.id, name: over.name ?? '菜', category: over.category ?? '荤菜',
    difficulty: over.difficulty ?? 2, cookingMinutes: over.cookingMinutes ?? 20,
    description: over.description ?? '', ingredients: over.ingredients ?? [],
    steps: over.steps ?? [], tags: over.tags ?? [], imageUrl: over.imageUrl ?? null,
    remoteVersion: over.remoteVersion ?? 0, clientUpdatedAt: over.clientUpdatedAt ?? null,
    deletedAt: over.deletedAt ?? null,
  };
}
const NOW = '2026-06-12T00:00:00.000Z';

describe('mergeWithExisting', () => {
  it('imageUrl 既有优先;amount 回填;description 黏住;remoteVersion 保留', () => {
    const existing = [rec({
      id: 'a', imageUrl: 'https://img/a.jpg', description: '老描述', remoteVersion: 7,
      ingredients: [{ name: '蛋', quantity: '', unit: '', amount: '' }],
    })];
    const fresh = [rec({
      id: 'a', imageUrl: null, description: '新描述', remoteVersion: 0,
      ingredients: [{ name: '蛋', quantity: '2', unit: '个', amount: '2 个' }],
    })];
    const { merged, stats } = mergeWithExisting(fresh, existing, NOW);
    const a = merged.find((r) => r.id === 'a')!;
    expect(a.imageUrl).toBe('https://img/a.jpg');
    expect(a.description).toBe('老描述');
    expect(a.remoteVersion).toBe(7);
    expect(a.ingredients[0].amount).toBe('2 个');
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
});
