import { describe, it, expect } from 'vitest';
import * as v from 'valibot';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';
import { CleanRecipeSchema, CATEGORIES } from '../src/clean/schema';

const valid = {
  id: 'howtocook:vegetable_dish/凉拌黄瓜',
  name: '凉拌黄瓜',
  category: '素菜',
  difficulty: 1,
  cookingMinutes: 20,
  description: '清爽开胃',
  ingredients: [{ name: '黄瓜', quantity: 200, unit: '克' }],
  steps: ['拍碎'],
  tags: ['素菜'],
  imageUrl: null,
  remoteVersion: 0,
  clientUpdatedAt: null,
  deletedAt: null,
};

describe('CleanRecipeSchema', () => {
  it('接受合法记录', () => {
    expect(() => v.parse(CleanRecipeSchema, valid)).not.toThrow();
  });
  it('拒绝非法分类', () => {
    expect(() => v.parse(CleanRecipeSchema, { ...valid, category: '夜宵' })).toThrow();
  });
  it('拒绝难度越界', () => {
    expect(() => v.parse(CleanRecipeSchema, { ...valid, difficulty: 6 })).toThrow();
  });
  it('CATEGORIES 恰为 10 个', () => {
    expect(CATEGORIES).toHaveLength(10);
  });
  it('接受真实 howtocook.json 首条', () => {
    const jsonPath = join(
      dirname(fileURLToPath(import.meta.url)),
      '../../ios/FreshPantry/Resources/howtocook.json',
    );
    const recipes = JSON.parse(readFileSync(jsonPath, 'utf8')) as unknown[];
    expect(() => v.parse(CleanRecipeSchema, recipes[0])).not.toThrow();
  });
});
