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

  it('缺少标题时 name 为空字符串', () => {
    const r = parseHowtocook('## 操作\n\n1. 打蛋\n');
    expect(r.name).toBe('');
    expect(r.steps).toHaveLength(1);
  });

  it('无计算段时 portionText 为 undefined', () => {
    const r = parseHowtocook('# 炒蛋的做法\n\n## 操作\n\n1. 打蛋\n');
    expect(r.portionText).toBeUndefined();
  });
});

describe('parseHowtocook sourceCookingMinutes', () => {
  it('preamble 声明「制作时长约 30 分钟」→ 30', () => {
    const md = '# 拔丝土豆的做法\n\n从备料到出锅，预计制作时长约 30 分钟。\n\n预估烹饪难度：★★★\n\n## 操作\n\n1. 切\n';
    expect(parseHowtocook(md).sourceCookingMinutes).toBe(30);
  });

  it('「约需 1 小时」→ 60;「制作时长约 24 小时」→ 1440', () => {
    const md1 = '# 咖喱饭的做法\n\n从备料到出锅约需 1 小时。\n\n## 操作\n\n1. 炒\n';
    expect(parseHowtocook(md1).sourceCookingMinutes).toBe(60);
    const md2 = '# 猪皮冻的做法\n\n含冷藏定型，制作时长约 24 小时。\n\n## 操作\n\n1. 煮\n';
    expect(parseHowtocook(md2).sourceCookingMinutes).toBe(1440);
  });

  it('步骤里的「腌制 10 分钟」不算总时长声明', () => {
    const md = '# 某菜的做法\n\n好吃。\n\n## 操作\n\n1. 腌制 10 分钟以上\n';
    expect(parseHowtocook(md).sourceCookingMinutes).toBeUndefined();
  });
});

describe('parseHowtocook imageRef', () => {
  it('取全文第一张图的相对引用', () => {
    const md = '# 拔丝土豆的做法\n\n简介。\n\n## 操作\n\n1. 切\n\n![拔丝土豆-预览图-1](./1.jpeg)\n![拔丝土豆-预览图-2](./2.jpeg)\n';
    expect(parseHowtocook(md).imageRef).toBe('./1.jpeg');
  });

  it('绝对 http 引用原样保留', () => {
    const md = '# 某菜的做法\n\n![成品](https://example.com/a.jpg?w=768)\n\n## 操作\n\n1. 切\n';
    expect(parseHowtocook(md).imageRef).toBe('https://example.com/a.jpg?w=768');
  });

  it('文件名含半角括号不被截断', () => {
    const md = '# 血浆鸭的做法\n\n## 操作\n\n1. 炒\n\n![血浆鸭](./血浆鸭(特辣).jpg)\n';
    expect(parseHowtocook(md).imageRef).toBe('./血浆鸭(特辣).jpg');
  });

  it('无图时为 undefined', () => {
    expect(parseHowtocook('# 炒蛋的做法\n\n## 操作\n\n1. 打蛋\n').imageRef).toBeUndefined();
  });

  it('preamble 中的图片行不混入 description', () => {
    const md = '# 凉拌黄瓜的做法\n\n![凉拌黄瓜](./cover.jpg)\n\n清爽开胃。\n\n预估烹饪难度：★\n\n## 操作\n\n1. 拍\n';
    const r = parseHowtocook(md);
    expect(r.description).toBe('清爽开胃。');
    expect(r.imageRef).toBe('./cover.jpg');
  });
});

describe('isTool', () => {
  it.each(['一个不粘锅', '炒勺', '菜刀', '案板'])('%s 是工具', (s) => {
    expect(isTool(s)).toBe(true);
  });
  it.each([
    '一次性手套', '隔热手套', '密封袋', '保鲜袋', '防烫盘夹', '煲汤盅',
    '电动打蛋器', '温度计', '吸管', '过滤网', '滤网', '过滤豆浆渣的纱布', '厨房剪刀',
  ])('%s 是工具(全量跑混入回归)', (s) => {
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
