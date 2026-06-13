import { describe, it, expect } from 'vitest';
import { validateCleanRecipe } from '../src/clean/validate';
import type { CleanRecipe } from '../src/clean/schema';
import type { RawRecipe } from '../src/sources/types';

function clean(over: Partial<CleanRecipe>): CleanRecipe {
  return {
    id: 'howtocook:x/菜', name: '菜', category: '荤菜', difficulty: 2, cookingMinutes: 20,
    description: '好吃。', ingredients: [], steps: ['做'], tags: ['荤菜'], imageUrl: null,
    remoteVersion: 0, clientUpdatedAt: null, deletedAt: null, ...over,
  };
}

function raw(over: Partial<RawRecipe> = {}): RawRecipe {
  return {
    id: 'howtocook:x/菜', sourceId: 'howtocook', sourceRef: 'dishes/x/菜.md', name: '菜',
    rawIngredients: [], steps: ['做'], ...over,
  };
}

type Ing = CleanRecipe['ingredients'][number];

describe('validateCleanRecipe(写盘前质量闸门:无损数字 schema)', () => {
  it('规范数据零违规(quantity:number + unit;模糊量 note)', () => {
    const r = clean({
      ingredients: [
        { name: '黄瓜', quantity: 200, unit: '克' },
        { name: '盐', note: '适量' },
        { name: '生粉' },
      ],
    });
    expect(validateCleanRecipe(r, raw({ portionText: '黄瓜 200 克\n盐 适量' }))).toEqual([]);
  });

  it('范围用量(quantity 下界 + quantityMax 上界)溯源零违规', () => {
    const r = clean({ ingredients: [{ name: '白糖', quantity: 6, quantityMax: 15, unit: '克' }] });
    expect(validateCleanRecipe(r, raw({ portionText: '白糖 6-15 克' }))).toEqual([]);
  });

  it('quantity 是字符串 → 违规(必须 number)', () => {
    const r = clean({ ingredients: [{ name: '草鱼', quantity: '3' as unknown as number, unit: '斤' }] });
    expect(validateCleanRecipe(r, raw({ portionText: '草鱼 3 斤' }))).toContainEqual(
      expect.stringContaining('quantity 非 number'),
    );
  });

  it('quantityMax 不大于 quantity → 违规', () => {
    const r = clean({ ingredients: [{ name: '糖', quantity: 10, quantityMax: 5, unit: '克' }] });
    expect(validateCleanRecipe(r, raw({ portionText: '糖 5-10 克' }))).toContainEqual(
      expect.stringContaining('quantityMax 未大于'),
    );
  });

  it('quantityMax 出现但缺 quantity 下界 → 违规', () => {
    const r = clean({ ingredients: [{ name: '糖', quantityMax: 10, unit: '克' } as Ing] });
    expect(validateCleanRecipe(r, raw({ portionText: '糖 10 克' }))).toContainEqual(
      expect.stringContaining('缺 quantity 下界'),
    );
  });

  it('残留 amount 字段 → 违规', () => {
    const r = clean({ ingredients: [{ name: '盐', quantity: 20, unit: 'g', amount: '20g' } as Ing] });
    expect(validateCleanRecipe(r, raw({ portionText: '盐 20 g' }))).toContainEqual(
      expect.stringContaining('amount'),
    );
  });

  it('unit 为空字符串 → 违规(应省略)', () => {
    const r = clean({ ingredients: [{ name: '盐', quantity: 20, unit: '' } as Ing] });
    expect(validateCleanRecipe(r, raw({ portionText: '盐 20' }))).toContainEqual(
      expect.stringContaining('unit 为空'),
    );
  });

  it('note 为空 / 纯数字 / 含 markdown / 含公式 → 违规', () => {
    expect(validateCleanRecipe(clean({ ingredients: [{ name: '盐', note: '' } as Ing] }), raw()))
      .toContainEqual(expect.stringContaining('note 为空'));
    expect(validateCleanRecipe(clean({ ingredients: [{ name: '盐', note: '200' }] }), raw({ portionText: '盐 200' })))
      .toContainEqual(expect.stringContaining('note 是纯数字'));
    expect(validateCleanRecipe(clean({ ingredients: [{ name: '盐', note: '![x](y.jpg)' }] }), raw()))
      .toContainEqual(expect.stringContaining('note 含 markdown'));
    expect(validateCleanRecipe(clean({ ingredients: [{ name: '盐', note: '300g * 份数' }] }), raw()))
      .toContainEqual(expect.stringContaining('note 含公式'));
  });

  it('用量数字在源文本找不到(LLM 运算/编造)→ 违规;中文数字算依据', () => {
    const bad = clean({ ingredients: [{ name: '醋', quantity: 11.5, unit: 'ml' }] });
    expect(validateCleanRecipe(bad, raw({ portionText: '醋 7.5 ml + 4 ml * 份数' })))
      .toContainEqual(expect.stringContaining('溯源'));
    // 「两个」→ quantity 2 有源依据
    const ok = clean({ ingredients: [{ name: '八角', quantity: 2, unit: '个' }] });
    expect(validateCleanRecipe(ok, raw({ portionText: '八角 两个' }))).toEqual([]);
  });

  it('范围上界无法溯源 → 违规', () => {
    const r = clean({ ingredients: [{ name: '水', quantity: 180, quantityMax: 999, unit: 'mL' }] });
    expect(validateCleanRecipe(r, raw({ portionText: '水 180 mL' }))).toContainEqual(
      expect.stringContaining('上界无法溯源'),
    );
  });

  it('溯源范围覆盖原料行与步骤(量不一定写在计算段)', () => {
    const fromIng = clean({ ingredients: [{ name: '奶油奶酪', quantity: 212, unit: 'g' }] });
    expect(validateCleanRecipe(fromIng, raw({ rawIngredients: ['奶油奶酪：212g （这是一块的质量）'] })))
      .toEqual([]);
    const fromStep = clean({ ingredients: [{ name: '沸水', quantity: 180, quantityMax: 200, unit: 'mL' }] });
    expect(validateCleanRecipe(fromStep, raw({ steps: ['取袋泡红茶 2 包放入杯中，加入 180-200mL 沸水。'] })))
      .toEqual([]);
  });

  it('源写分数(1/4、1/2)时小数转写有依据', () => {
    const quarter = clean({ ingredients: [{ name: '美人椒', quantity: 0.25, unit: '个' }] });
    expect(validateCleanRecipe(quarter, raw({ portionText: '美人椒 1/4 个' }))).toEqual([]);
    const half = clean({ ingredients: [{ name: '葡萄柚', quantity: 0.5, unit: '粒' }] });
    expect(validateCleanRecipe(half, raw({ rawIngredients: ['葡萄柚 1/2 粒'] }))).toEqual([]);
  });

  it('混合数/Unicode 分数/中文分数转写都有依据(咕噜肉/冷吃兔/牛奶面包回归)', () => {
    const mixed = clean({ ingredients: [{ name: '生粉', quantity: 2.5, unit: '茶匙' }] });
    expect(validateCleanRecipe(mixed, raw({ portionText: '生粉 2 1/2 茶匙' }))).toEqual([]);
    const uni = clean({ ingredients: [{ name: '生粉', quantity: 2.5, unit: '茶匙' }] });
    expect(validateCleanRecipe(uni, raw({ steps: ['加入生粉（2½ 茶匙）拌匀。'] }))).toEqual([]);
    const cn = clean({ ingredients: [{ name: '蒜', quantity: 0.5, unit: '头' }] });
    expect(validateCleanRecipe(cn, raw({ portionText: '蒜量 = 兔肉斤数 * 二分之一头蒜' }))).toEqual([]);
    const eighth = clean({ ingredients: [{ name: '糖', quantity: 0.125, unit: 'cup' }] });
    expect(validateCleanRecipe(eighth, raw({ portionText: '糖 1/8 cup' }))).toEqual([]);
  });

  it('数字虽在源出现,但所在行是除式/配比公式 → 系数误当用量,违规', () => {
    // 油酥:面粉 =（张数 / 0.13)g —— 0.13 是除数系数
    const div = clean({ ingredients: [{ name: '面粉', quantity: 0.13, unit: 'g' }] });
    expect(validateCleanRecipe(div, raw({ portionText: '- 面粉 = （要烙饼的张数 / 0.13）g' })))
      .toContainEqual(expect.stringContaining('公式系数/配比'));
    // 酸辣蕨根粉:酱油 : 醋 : 油泼辣子 = 3 : 2 : 2 —— 配比系数
    const ratio = clean({ ingredients: [{ name: '酱油', quantity: 3 }] });
    expect(validateCleanRecipe(ratio, raw({ portionText: '酱油 : 醋 : 油泼辣子 = 3 : 2 : 2' })))
      .toContainEqual(expect.stringContaining('公式系数/配比'));
  });

  it('乘式每份率(份数 * X)不算配比/除式公式 → 不误伤', () => {
    // 盐量 = 份数 * 3g —— 乘式抽出的 3 是合法每份量
    const ok = clean({ ingredients: [{ name: '盐', quantity: 3, unit: '克' }] });
    expect(validateCleanRecipe(ok, raw({ portionText: '盐量 = 份数 * 3g' }))).toEqual([]);
  });

  it('description 含 markdown 残留 → 违规', () => {
    const r = clean({ description: '![预览](./成品.jpg)' });
    expect(validateCleanRecipe(r, raw())).toContainEqual(
      expect.stringContaining('description'),
    );
  });

  it('食材名是工具 → 违规', () => {
    const r = clean({ ingredients: [{ name: '一次性手套', quantity: 1, unit: '副' }] });
    expect(validateCleanRecipe(r, raw({ portionText: '一次性手套 1 副' }))).toContainEqual(
      expect.stringContaining('工具'),
    );
  });
});
