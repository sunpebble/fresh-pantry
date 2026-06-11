import { describe, it, expect } from 'vitest';
import { normalizeName, jaccard, dedupe } from '../src/clean/dedup';
import type { CleanRecipe } from '../src/clean/schema';

function rec(id: string, name: string, ings: string[]): CleanRecipe {
  return {
    id, name, category: '荤菜', difficulty: 2, cookingMinutes: 20,
    description: '', ingredients: ings.map((n) => ({ name: n, quantity: '', unit: '', amount: '' })),
    steps: [], tags: [], imageUrl: null, remoteVersion: 0, clientUpdatedAt: null, deletedAt: null,
  };
}

describe('normalizeName', () => {
  it('去空白/全半角/标点', () => {
    expect(normalizeName(' 番茄炒蛋（家常）')).toBe('番茄炒蛋家常');
    expect(normalizeName('番茄炒蛋')).toBe('番茄炒蛋');
  });
});

describe('jaccard', () => {
  it('交并比', () => {
    expect(jaccard(new Set(['a', 'b']), new Set(['a', 'b']))).toBe(1);
    expect(jaccard(new Set(['a', 'b', 'c', 'd']), new Set(['a']))).toBeCloseTo(0.25);
  });
});

describe('dedupe', () => {
  it('同名 + 食材高度重合 -> 留高优先级(howtocook),丢低优先', () => {
    const hc = rec('howtocook:meat_dish/番茄炒蛋', '番茄炒蛋', ['番茄', '鸡蛋', '盐']);
    const url = rec('url:abc', '番茄炒蛋', ['番茄', '鸡蛋', '糖']);
    const { kept, dropped } = dedupe([url, hc]);
    expect(kept.map((r) => r.id)).toEqual(['howtocook:meat_dish/番茄炒蛋']);
    expect(dropped).toEqual([{ id: 'url:abc', dupOf: 'howtocook:meat_dish/番茄炒蛋' }]);
  });
  it('同名但食材差异大 -> 都保留', () => {
    const a = rec('repo:x:糖醋里脊', '糖醋里脊', ['里脊', '糖', '醋']);
    const b = rec('url:y', '糖醋里脊', ['豆腐', '酱油']);
    const { kept } = dedupe([a, b]);
    expect(kept).toHaveLength(2);
  });
});
