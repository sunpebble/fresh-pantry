import { describe, it, expect } from 'vitest';
import { normalizeIngredient } from '../src/clean/normalize';

const ing = (quantity: string, unit: string, amount: string, name = '食材') => ({
  name, quantity, unit, amount,
});

describe('normalizeIngredient:遗留字符串 → 无损数字结构(字段按需出现,绝不空字符串)', () => {
  it('纯数字/带单位文字 → quantity:number + unit', () => {
    expect(normalizeIngredient(ing('20', 'g', '20 g'))).toEqual({ name: '食材', quantity: 20, unit: 'g' });
    expect(normalizeIngredient(ing('1', '只', '300g'))).toEqual({ name: '食材', quantity: 1, unit: '只' });
    expect(normalizeIngredient(ing('1', 'ml', '每个生蚝 1 ml'))).toEqual({ name: '食材', quantity: 1, unit: 'ml' });
    expect(normalizeIngredient(ing('200', '克', ''))).toEqual({ name: '食材', quantity: 200, unit: '克' });
  });

  it('范围 → quantity(下界) + quantityMax(上界) + unit', () => {
    expect(normalizeIngredient(ing('300-500', 'g', '300g 至 500g')))
      .toEqual({ name: '食材', quantity: 300, quantityMax: 500, unit: 'g' });
    expect(normalizeIngredient(ing('5g-10g', 'g', '5-10')))
      .toEqual({ name: '食材', quantity: 5, quantityMax: 10, unit: 'g' });
    expect(normalizeIngredient(ing('0.9～1升', '升', '')))
      .toEqual({ name: '食材', quantity: 0.9, quantityMax: 1, unit: '升' });
  });

  it('LLM 字段颠倒(quantity 装原文)→ 提取数字;中文数字转 number', () => {
    expect(normalizeIngredient(ing('大约三斤', '斤', '3'))).toEqual({ name: '食材', quantity: 3, unit: '斤' });
    expect(normalizeIngredient(ing('八个', '个', '8'))).toEqual({ name: '食材', quantity: 8, unit: '个' });
    expect(normalizeIngredient(ing('半根', '根', '0.5'))).toEqual({ name: '食材', quantity: 0.5, unit: '根' });
    expect(normalizeIngredient(ing('一小把', '把', '1'))).toEqual({ name: '食材', quantity: 1, unit: '把' });
  });

  it('模糊量(无数字)→ note,不设 quantity/unit', () => {
    expect(normalizeIngredient(ing('', '', '适量'))).toEqual({ name: '食材', note: '适量' });
    expect(normalizeIngredient(ing('适量', '', ''))).toEqual({ name: '食材', note: '适量' });
    expect(normalizeIngredient(ing('', '', '一小把'))).toEqual({ name: '食材', note: '一小把' });
  });

  it('组合中文数字(两个以上)不转写,留 note', () => {
    expect(normalizeIngredient(ing('十五', '克', ''))).toEqual({ name: '食材', note: '十五' });
  });

  it('完全无量 → 只留 name(quantity/unit/note 全省略)', () => {
    expect(normalizeIngredient(ing('', '', ''))).toEqual({ name: '食材' });
  });

  it('unit 为空一律省略(不出现空字符串键)', () => {
    const r = normalizeIngredient(ing('200', '', ''));
    expect(r).toEqual({ name: '食材', quantity: 200 });
    expect('unit' in r).toBe(false);
  });

  it('绝不产出 amount 字段', () => {
    expect('amount' in normalizeIngredient(ing('200', '克', '200克'))).toBe(false);
    expect('amount' in normalizeIngredient(ing('', '', '适量'))).toBe(false);
  });
});

describe('normalizeIngredient:源公式不外漏', () => {
  it('「X * 份数 / N 人」乘式 → 抽单一明确数字进 quantity', () => {
    expect(normalizeIngredient(ing('250', 'g', '250g * 份数'))).toEqual({ name: '食材', quantity: 250, unit: 'g' });
    expect(normalizeIngredient(ing('300', 'g', '300g * 2 人'))).toEqual({ name: '食材', quantity: 300, unit: 'g' });
    expect(normalizeIngredient(ing('0.5', '个', '份数 * 0.5'))).toEqual({ name: '食材', quantity: 0.5, unit: '个' });
    expect(normalizeIngredient(ing('150', '克', '青茄子数量 * 150'))).toEqual({ name: '食材', quantity: 150, unit: '克' });
  });

  it('乘式但 quantity 无明确数字(份数 * X 全在文字里)→ 无量,不进 note', () => {
    expect(normalizeIngredient(ing('份数 * 青茄子数量', '克', ''))).toEqual({ name: '食材' });
  });

  it('「X + Y」加式单份量不明 → 无量(只抽不猜)', () => {
    expect(normalizeIngredient(ing('', '', '7.5 ml + 4 ml * 份数'))).toEqual({ name: '食材' });
    expect(normalizeIngredient(ing('10', 'ml', '10 + 25 ml'))).toEqual({ name: '食材' });
    expect(normalizeIngredient(ing('', '', '720g + 600g（720 克用于蒸饭）'))).toEqual({ name: '食材' });
  });

  it('除式("张数 / N")的除数是系数非用量 → 无量(油酥 面粉/盐 回归)', () => {
    expect(normalizeIngredient(ing('0.13', 'g', '要烙饼的张数 / 0.13'))).toEqual({ name: '食材' });
    expect(normalizeIngredient(ing('张数 / 2', 'g', ''))).toEqual({ name: '食材' });
  });

  it('配比("a : b : c")的比例数是系数非用量 → 无量(酸辣蕨根粉 回归)', () => {
    expect(normalizeIngredient(ing('3', '', '酱油 : 醋 : 油泼辣子 = 3 : 2 : 2'))).toEqual({ name: '食材' });
  });

  it('裸分数("1/4")无变量词 → 不当除式公式(不误伤)', () => {
    // 分数无 张数/份数 等变量,isDivisionOrRatio 不触发;留作数字处理而非丢量
    expect(normalizeIngredient(ing('1/4', '个', ''))).not.toEqual({ name: '食材' });
  });
});

describe('normalizeIngredient:已是新结构(number)的对象幂等收敛', () => {
  it('numeric quantity 透传,空 unit 省略', () => {
    expect(normalizeIngredient({ name: '盐', quantity: 200, unit: '克' }))
      .toEqual({ name: '盐', quantity: 200, unit: '克' });
    expect(normalizeIngredient({ name: '盐', quantity: 200, unit: '' }))
      .toEqual({ name: '盐', quantity: 200 });
  });
  it('范围结构透传;quantityMax 不大于下界则丢弃', () => {
    expect(normalizeIngredient({ name: '糖', quantity: 6, quantityMax: 15, unit: '克' }))
      .toEqual({ name: '糖', quantity: 6, quantityMax: 15, unit: '克' });
    expect(normalizeIngredient({ name: '糖', quantity: 6, quantityMax: 6, unit: '克' }))
      .toEqual({ name: '糖', quantity: 6, unit: '克' });
  });
  it('已带 note 的模糊量透传', () => {
    expect(normalizeIngredient({ name: '盐', note: '适量' })).toEqual({ name: '盐', note: '适量' });
  });
});
