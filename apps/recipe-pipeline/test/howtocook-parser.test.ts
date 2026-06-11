import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { parseHowtocook, isTool, stripInlineMarkdown } from '../src/parse/howtocook-parser';

const here = dirname(fileURLToPath(import.meta.url));
const fx = (n: string) => readFileSync(join(here, 'fixtures/howtocook', n), 'utf8');

describe('parseHowtocook', () => {
  it('凉拌黄瓜:名称/难度/原料/步骤/描述/计算段', () => {
    const r = parseHowtocook(fx('凉拌黄瓜.md'));
    expect(r.name).toBe('凉拌黄瓜');
    expect(r.difficulty).toBe(1);
    expect(r.rawIngredients).toEqual(['黄瓜', '醋', '酱油', '蒜']);
    expect(r.steps).toHaveLength(6);
    expect(r.steps[0]).toContain('黄瓜拍扁');
    expect(r.description).toContain('清爽开胃');
    expect(r.portionText).toContain('黄瓜 200 克');
  });

  it('带工具样本:剥离锅/勺,保留食材;步骤去内联 markdown', () => {
    const r = parseHowtocook(fx('带工具样本.md'));
    expect(r.difficulty).toBe(3);
    expect(r.rawIngredients).toEqual(['鸡蛋', '西红柿', '盐']);
    expect(r.steps[1]).toBe('翻炒至熟');
  });
});

describe('isTool', () => {
  it.each(['一个不粘锅', '炒勺', '菜刀', '案板'])('%s 是工具', (s) => {
    expect(isTool(s)).toBe(true);
  });
  it.each(['鸡蛋', '西红柿', '盐', '黄瓜'])('%s 不是工具', (s) => {
    expect(isTool(s)).toBe(false);
  });
});

describe('stripInlineMarkdown', () => {
  it('去 ** _ ` 链接', () => {
    expect(stripInlineMarkdown('**翻炒**至 _熟_')).toBe('翻炒至 熟');
    expect(stripInlineMarkdown('见 [图](http://x)')).toBe('见 图');
  });
});
