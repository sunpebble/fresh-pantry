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
    { name: '黄瓜', quantity: 200, unit: '克' },
    { name: '醋', quantity: 7.5, unit: 'ml' },
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
  it('提示可从操作步骤抽用量(计算段漏写时回归,如生粉 5g 在步骤里)', () => {
    expect(buildEnrichPrompt(tier1)).toMatch(/步骤.*抽|从.*步骤.*用量|计算段.*没有.*步骤/);
  });
  it('源里没写任何数字的食材落「适量」note,不留裸 name', () => {
    expect(buildEnrichPrompt(tier1)).toContain('适量');
  });
  it('提示严禁对用量做运算(乘份数/相加幻觉的回归)', () => {
    expect(buildEnrichPrompt(tier1)).toContain('严禁运算');
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
    expect(r.ingredients[0]).toEqual({ name: '黄瓜', quantity: 200, unit: '克' }); // 无损数字结构,无 amount
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
  it('源声明的制作时长优先于 LLM 估算', () => {
    expect(assembleRecipe({ ...tier1, sourceCookingMinutes: 1440 }, enr).cookingMinutes).toBe(1440);
    expect(assembleRecipe(tier1, enr).cookingMinutes).toBe(20); // 无声明回落 enr
  });

  it('enrichment 食材 quantity 装文字时被 normalize 提取出数字(防御遗留/越权输出)', () => {
    // 真实管线里 valibot 强制 quantity 为 number;此处用 cast 模拟 LLM 越权塞文字,
    // 验证 assembleRecipe→normalizeIngredient 仍能确定性提取(中文数字→number)。
    const flipped = {
      ...enr,
      ingredients: [{ name: '草鱼', quantity: '大约三斤', unit: '斤', amount: '3' }],
    } as unknown as Enrichment;
    expect(assembleRecipe(tier1, flipped).ingredients[0])
      .toEqual({ name: '草鱼', quantity: 3, unit: '斤' });
  });

  it('enrichment 食材里的工具被剔除(LLM 从计算段抽到工具的回归)', () => {
    const withTools: Enrichment = {
      ...enr,
      ingredients: [
        { name: '黄瓜', quantity: 200, unit: '克' },
        { name: '一次性手套', quantity: 1, unit: '副' },
        { name: '密封袋' },
      ],
    };
    const r = assembleRecipe(tier1, withTools);
    expect(r.ingredients.map((i) => i.name)).toEqual(['黄瓜']);
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

describe('assembleRecipe — 每份营养 + 每步时长', () => {
  it('每份营养透传(估算值)', () => {
    const r = assembleRecipe(tier1, { ...enr, nutrition: { energyKcal: 120, protein: 3, carbs: 8, fat: 5 } });
    expect(r.nutrition).toEqual({ energyKcal: 120, protein: 3, carbs: 8, fat: 5 });
  });

  it('营养无有效字段 → 省略 nutrition', () => {
    expect(assembleRecipe(tier1, { ...enr, nutrition: {} }).nutrition).toBeUndefined();
  });

  it('营养负数/非有限值被剔除,小数保留一位', () => {
    const r = assembleRecipe(tier1, { ...enr, nutrition: { energyKcal: 120.46, protein: -3, carbs: NaN } });
    expect(r.nutrition).toEqual({ energyKcal: 120.5 });
  });

  it('步骤时长与最终 steps 等长则保留(对齐 raw.steps,tier1 有 2 步)', () => {
    const r = assembleRecipe(tier1, { ...enr, stepDurations: [null, 60] });
    expect(r.steps).toEqual(['拍碎', '调味']);
    expect(r.stepDurations).toEqual([null, 60]);
  });

  it('步骤时长长度与 steps 不符则整个丢弃(防错位)', () => {
    expect(assembleRecipe(tier1, { ...enr, stepDurations: [60] }).stepDurations).toBeUndefined();
  });

  it('步骤时长全 null / 非正数 → 不输出', () => {
    expect(assembleRecipe(tier1, { ...enr, stepDurations: [null, 0] }).stepDurations).toBeUndefined();
  });

  it('步骤时长小数取整、负数归 null', () => {
    expect(assembleRecipe(tier1, { ...enr, stepDurations: [120.7, -5] }).stepDurations).toEqual([121, null]);
  });

  it('缺营养/时长时不输出(向后兼容,老路径)', () => {
    const r = assembleRecipe(tier1, enr);
    expect(r.nutrition).toBeUndefined();
    expect(r.stepDurations).toBeUndefined();
  });
});

describe('buildEnrichPrompt — 营养 + 时长指令', () => {
  it('提示估算每份营养', () => {
    expect(buildEnrichPrompt(tier1)).toMatch(/营养|热量|nutrition/);
  });
  it('提示抽取每步时长', () => {
    expect(buildEnrichPrompt(tier1)).toMatch(/时长|stepDurations|多少秒/);
  });
});
