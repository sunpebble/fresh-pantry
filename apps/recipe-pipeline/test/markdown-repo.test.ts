import { describe, it, expect } from 'vitest';
import { markdownRepoIdFor, rawFromRepoMarkdown } from '../src/sources/markdown-repo';

const cfg = { name: 'mycookbook', repo: 'https://github.com/x/y.git', dishesDir: 'recipes', category: '荤菜' as const };

describe('markdownRepoIdFor', () => {
  it('repo:<name>:<slug>', () => {
    expect(markdownRepoIdFor(cfg, 'recipes/红烧肉.md')).toBe('repo:mycookbook:红烧肉');
  });
});

describe('rawFromRepoMarkdown', () => {
  it('用配置兜底分类,复用 howtocook 解析', () => {
    const md = '# 红烧肉的做法\n\n预估烹饪难度：★★\n\n## 必备原料和工具\n\n* 五花肉\n\n## 操作\n\n1. 焯水\n';
    const r = rawFromRepoMarkdown(cfg, 'recipes/红烧肉.md', md);
    expect(r.id).toBe('repo:mycookbook:红烧肉');
    expect(r.sourceCategory).toBe('荤菜');
    expect(r.sourceId).toBe('repo:mycookbook');
    expect(r.rawIngredients).toEqual(['五花肉']);
  });
});
