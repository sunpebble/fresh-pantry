import { describe, it, expect } from 'vitest';
import { buildEnrichPrompt, assembleRecipe } from '../src/clean/enrich';
import type { RawRecipe } from '../src/sources/types';
import type { Enrichment } from '../src/clean/schema';

const tier1: RawRecipe = {
  id: 'howtocook:vegetable_dish/凉拌黄瓜',
  sourceId: 'howtocook',
  sourceRef: 'dishes/vegetable_dish/凉拌黄瓜.md',
  name: '凉拌黄瓜',
  sourceCategory: '素菜',
  sourceDifficulty: 1,
  description: '清爽开胃',
  rawIngredients: ['黄瓜', '醋'],
  portionText: '黄瓜 200 克 * 份数\n醋 7.5 ml * 份数',
  steps: ['拍碎', '调味'],
  imageUrl: null,
};

const enr: Enrichment = {
  category: '荤菜',
  difficulty: 4,
  cookingMinutes: 20,
  description: 'LLM 写的',
  ingredients: [
    { name: '黄瓜', quantity: '200', unit: '克', amount: '200 克' },
    { name: '醋', quantity: '7.5', unit: 'ml', amount: '7.5 ml' },
  ],
  steps: ['LLM步骤'],
  tags: ['爽口'],
};

describe('buildEnrichPrompt', () => {
  it('Tier1 含原料、计算段,并强调只抽不猜', () => {
    const p = buildEnrichPrompt(tier1);
    expect(p).toContain('黄瓜 200 克');
    expect(p).toContain('凉拌黄瓜');
    expect(p).toMatch(/只.*源文本写了才填|不要(编造|估算|猜)/);
  });
  it('Tier2 走 rawText 抽取', () => {
    const p = buildEnrichPrompt({ ...tier1, rawText: '网页正文…', portionText: undefined });
    expect(p).toContain('网页正文');
  });
  it('Tier1 无计算段时提示留空', () => {
    expect(buildEnrichPrompt({ ...tier1, portionText: undefined })).toContain('全部留空字符串');
  });
});

describe('assembleRecipe', () => {
  it('确定性字段优先:分类/难度/描述/步骤来自 raw,用量来自 enrichment', () => {
    const r = assembleRecipe(tier1, enr);
    expect(r.id).toBe(tier1.id);
    expect(r.name).toBe('凉拌黄瓜');
    expect(r.category).toBe('素菜');
    expect(r.difficulty).toBe(1);
    expect(r.description).toBe('清爽开胃');
    expect(r.steps).toEqual(['拍碎', '调味']);
    expect(r.ingredients[0].amount).toBe('200 克');
    expect(r.tags).toContain('素菜');
    expect(r.remoteVersion).toBe(0);
    expect(r.clientUpdatedAt).toBeNull();
    expect(r.deletedAt).toBeNull();
  });
  it('非法 sourceCategory 回落到 enrichment 分类', () => {
    const r = assembleRecipe({ ...tier1, sourceCategory: '素食' }, enr);
    expect(r.category).toBe('荤菜'); // enr.category
  });
  it('imageUrl 透传:raw 有图则保留,undefined 归 null', () => {
    expect(assembleRecipe({ ...tier1, imageUrl: 'http://img' }, enr).imageUrl).toBe('http://img');
    expect(assembleRecipe({ ...tier1, imageUrl: undefined }, enr).imageUrl).toBeNull();
  });
  it('URL 源缺确定性字段时回落 enrichment', () => {
    const url: RawRecipe = {
      id: 'url:example', sourceId: 'url', sourceRef: 'http://x',
      name: '番茄炒蛋', rawIngredients: [], steps: [], rawText: '…',
    };
    const r = assembleRecipe(url, enr);
    expect(r.category).toBe('荤菜');
    expect(r.difficulty).toBe(4);
    expect(r.description).toBe('LLM 写的');
    expect(r.steps).toEqual(['LLM步骤']);
  });
});
