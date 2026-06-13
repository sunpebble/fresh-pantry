import { describe, it, expect } from 'vitest';
import { applyBackfill, type RecipeCorrections } from '../src/clean/backfill';
import type { CleanRecipe, Ingredient } from '../src/clean/schema';

function recipe(id: string, ingredients: Ingredient[]): CleanRecipe {
  return {
    id, name: id, category: '荤菜', difficulty: 2, cookingMinutes: 30,
    description: '', ingredients, steps: [], tags: [],
    imageUrl: null, videoUrl: null, remoteVersion: 0, clientUpdatedAt: null, deletedAt: null,
  };
}

describe('applyBackfill:把校验后的用量回填到缺量食材', () => {
  it('amount 修正 → quantity + unit,清掉旧 note', () => {
    const recipes = [recipe('r1', [{ name: '生粉', note: '旧' }])];
    const corr: RecipeCorrections[] = [
      { id: 'r1', corrections: [{ name: '生粉', kind: 'amount', quantity: 5, unit: '克' }] },
    ];
    const { recipes: out, report } = applyBackfill(recipes, corr);
    expect(out[0].ingredients[0]).toEqual({ name: '生粉', quantity: 5, unit: '克' });
    expect(report.amountsApplied).toBe(1);
  });

  it('amount 范围 → quantity 下界 + quantityMax 上界 + unit', () => {
    const recipes = [recipe('r1', [{ name: '豆瓣酱' }])];
    const corr: RecipeCorrections[] = [
      { id: 'r1', corrections: [{ name: '豆瓣酱', kind: 'amount', quantity: 15, quantityMax: 20, unit: '克' }] },
    ];
    const { recipes: out } = applyBackfill(recipes, corr);
    expect(out[0].ingredients[0]).toEqual({ name: '豆瓣酱', quantity: 15, quantityMax: 20, unit: '克' });
  });

  it('fuzzy 修正 → 裸食材填「适量」note', () => {
    const recipes = [recipe('r1', [{ name: '盐' }])];
    const corr: RecipeCorrections[] = [
      { id: 'r1', corrections: [{ name: '盐', kind: 'fuzzy' }] },
    ];
    const { recipes: out, report } = applyBackfill(recipes, corr);
    expect(out[0].ingredients[0]).toEqual({ name: '盐', note: '适量' });
    expect(report.fuzzyMarked).toBe(1);
  });

  it('缺量但完全没有对应修正 → 兜底填「适量」', () => {
    const recipes = [recipe('r1', [{ name: '葱花' }])];
    const { recipes: out, report } = applyBackfill(recipes, []);
    expect(out[0].ingredients[0]).toEqual({ name: '葱花', note: '适量' });
    expect(report.fuzzyMarked).toBe(1);
  });

  it('已有数量的食材原样不动,即便误来一条修正', () => {
    const recipes = [recipe('r1', [{ name: '青蟹', quantity: 1, unit: '只' }])];
    const corr: RecipeCorrections[] = [
      { id: 'r1', corrections: [{ name: '青蟹', kind: 'amount', quantity: 9, unit: '只' }] },
    ];
    const { recipes: out, report } = applyBackfill(recipes, corr);
    expect(out[0].ingredients[0]).toEqual({ name: '青蟹', quantity: 1, unit: '只' });
    expect(report.alreadyQuantified).toBe(1);
    expect(report.unmatched).toBe(1);
  });

  it('fuzzy 时保留已有的有意义 note,不覆盖成「适量」', () => {
    const recipes = [recipe('r1', [{ name: '香菜', note: '一小把' }])];
    const corr: RecipeCorrections[] = [
      { id: 'r1', corrections: [{ name: '香菜', kind: 'fuzzy' }] },
    ];
    const { recipes: out } = applyBackfill(recipes, corr);
    expect(out[0].ingredients[0]).toEqual({ name: '香菜', note: '一小把' });
  });

  it('kind=amount 但 quantity 非数字 → 当 fuzzy 兜底', () => {
    const recipes = [recipe('r1', [{ name: '糖' }])];
    const corr: RecipeCorrections[] = [
      { id: 'r1', corrections: [{ name: '糖', kind: 'amount', unit: '克' }] },
    ];
    const { recipes: out } = applyBackfill(recipes, corr);
    expect(out[0].ingredients[0]).toEqual({ name: '糖', note: '适量' });
  });

  it('不修改入参(纯函数)', () => {
    const recipes = [recipe('r1', [{ name: '生粉' }])];
    const corr: RecipeCorrections[] = [
      { id: 'r1', corrections: [{ name: '生粉', kind: 'amount', quantity: 5, unit: '克' }] },
    ];
    applyBackfill(recipes, corr);
    expect(recipes[0].ingredients[0]).toEqual({ name: '生粉' });
  });
});
