import { describe, expect, it } from 'vitest';
import type { CleanRecipe } from '../src/clean/schema';
import { translatableHash, translateCorpus } from '../src/i18n/translate';

const r1: CleanRecipe = {
  id: 'howtocook:meat/番茄牛肉',
  name: '番茄牛肉',
  category: '荤菜',
  difficulty: 2,
  cookingMinutes: 25,
  description: '酸甜下饭。',
  ingredients: [
    { name: '牛肉', quantity: 200, unit: '克' },
    { name: '番茄', quantity: 2, unit: '个' },
  ],
  steps: ['切牛肉', '炒番茄', '合炒'],
  tags: ['下饭', '快手'],
  imageUrl: null,
  videoUrl: null,
  remoteVersion: 0,
  clientUpdatedAt: null,
  deletedAt: null,
};

const r2: CleanRecipe = {
  ...r1,
  id: 'howtocook:vegetable/蒜蓉生菜',
  name: '蒜蓉生菜',
  category: '素菜',
  ingredients: [{ name: '生菜', quantity: 1, unit: '颗' }],
  steps: ['洗菜', '爆香蒜末', '快炒'],
};

function okOverlay(recipe: CleanRecipe): string {
  return JSON.stringify({
    name: `EN ${recipe.name}`,
    description: 'd',
    category: 'ignored-by-impl',
    steps: recipe.steps.map((_, index) => `step${index}`),
    tags: recipe.tags.map((tag) => `tag-${tag}`),
    ingredients: recipe.ingredients.map((ingredient) => ({
      name: `en-${ingredient.name}`,
      unit: ingredient.unit ? 'g' : undefined,
      note: ingredient.note,
    })),
  });
}

describe('translatableHash', () => {
  it('只随可译字段变化', () => {
    const base = translatableHash(r1);
    expect(translatableHash({ ...r1, imageUrl: 'https://example.com/a.jpg' })).toBe(base);
    expect(translatableHash({ ...r1, name: '红烧牛肉' })).not.toBe(base);
  });
});

describe('translateCorpus', () => {
  it('翻译未命中缓存的条目,category 走固定映射表而非 AI 输出', async () => {
    const chat = async () => okOverlay(r1);
    const { overlays } = await translateCorpus([r1], 'en', { chat, cache: {} });
    expect(overlays[r1.id].name).toBe(`EN ${r1.name}`);
    expect(overlays[r1.id].category).toBe('Meat Dishes');
  });

  it('缓存命中时不调 AI', async () => {
    let calls = 0;
    const chat = async () => {
      calls += 1;
      return okOverlay(r1);
    };
    const first = await translateCorpus([r1], 'en', { chat, cache: {} });
    const second = await translateCorpus([r1], 'en', { chat, cache: first.cache });
    expect(calls).toBe(1);
    expect(second.overlays[r1.id]).toEqual(first.overlays[r1.id]);
  });

  it('steps 或 ingredients 数量与原文不齐时该条失败,不产出 overlay', async () => {
    const chat = async () => JSON.stringify({ ...JSON.parse(okOverlay(r1)), steps: ['only-one'] });
    const { overlays, failures } = await translateCorpus([r1], 'en', { chat, cache: {} });
    expect(overlays[r1.id]).toBeUndefined();
    expect(failures).toHaveLength(1);
  });

  it('单条 chat 抛错不阻塞其余条目', async () => {
    const chat = async (messages: { role: string; content: string }[]) => {
      if (messages[0].content.includes(r1.name)) throw new Error('boom');
      return okOverlay(r2);
    };
    const { overlays, failures } = await translateCorpus([r1, r2], 'en', { chat, cache: {} });
    expect(overlays[r2.id]).toBeDefined();
    expect(failures.map((failure) => failure.id)).toEqual([r1.id]);
  });
});
