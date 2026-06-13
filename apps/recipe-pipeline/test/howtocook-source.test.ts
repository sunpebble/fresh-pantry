import { describe, it, expect } from 'vitest';
import { howtocookIdFromPath, rawFromMarkdown, resolveImageUrl, isTemplateDish } from '../src/sources/howtocook';

describe('howtocookIdFromPath', () => {
  it('直挂文件', () => {
    expect(howtocookIdFromPath('dishes/vegetable_dish/凉拌黄瓜.md'))
      .toBe('howtocook:vegetable_dish/凉拌黄瓜');
  });
  it('子目录文件', () => {
    expect(howtocookIdFromPath('dishes/vegetable_dish/鸡蛋花/鸡蛋花.md'))
      .toBe('howtocook:vegetable_dish/鸡蛋花/鸡蛋花');
  });
});

describe('rawFromMarkdown', () => {
  it('组装 RawRecipe:分类来自目录、难度来自解析', () => {
    const md = '# 凉拌黄瓜的做法\n\n描述。\n\n预估烹饪难度：★\n\n## 必备原料和工具\n\n* 黄瓜\n\n## 操作\n\n1. 切\n';
    const r = rawFromMarkdown('dishes/vegetable_dish/凉拌黄瓜.md', md);
    expect(r.id).toBe('howtocook:vegetable_dish/凉拌黄瓜');
    expect(r.sourceCategory).toBe('素菜');
    expect(r.sourceDifficulty).toBe(1);
    expect(r.name).toBe('凉拌黄瓜');
    expect(r.rawIngredients).toEqual(['黄瓜']);
    expect(r.sourceId).toBe('howtocook');
    expect(r.imageUrl).toBeNull();
  });

  it('md 带相对图时 imageUrl 解析为 GitHub LFS media CDN 绝对 URL(jsDelivr 对 LFS 不可靠)', () => {
    const md = '# 拔丝土豆的做法\n\n## 操作\n\n1. 切\n\n![预览](./1.jpeg)\n';
    const r = rawFromMarkdown('dishes/vegetable_dish/拔丝土豆/拔丝土豆.md', md);
    expect(r.imageUrl).toBe(
      encodeURI('https://media.githubusercontent.com/media/Anduin2017/HowToCook/master/dishes/vegetable_dish/拔丝土豆/1.jpeg'),
    );
  });
});

describe('resolveImageUrl', () => {
  it('相对引用拼到 md 所在目录并 percent-encode 中文', () => {
    const url = resolveImageUrl('dishes/aquatic/清蒸鲈鱼/清蒸鲈鱼.md', './成品.jpg');
    expect(url).toBe(encodeURI('https://media.githubusercontent.com/media/Anduin2017/HowToCook/master/dishes/aquatic/清蒸鲈鱼/成品.jpg'));
    expect(url).not.toContain('成');
  });

  it('不带 ./ 前缀的相对引用同样可解析', () => {
    expect(resolveImageUrl('dishes/drink/citrus-tea/citrus-tea.md', 'citrus-tea.jpg'))
      .toBe('https://media.githubusercontent.com/media/Anduin2017/HowToCook/master/dishes/drink/citrus-tea/citrus-tea.jpg');
  });

  it('白名单域的绝对引用沿用(GitHub 系 CDN)', () => {
    expect(resolveImageUrl('dishes/x/y.md', 'https://user-images.githubusercontent.com/4/205.jpg'))
      .toBe('https://user-images.githubusercontent.com/4/205.jpg');
  });

  it('jsDelivr 不再信任(对 LFS 返回 pointer 文本)', () => {
    expect(resolveImageUrl('dishes/x/y.md', 'https://cdn.jsdelivr.net/gh/a/b@master/c.jpg')).toBeNull();
  });

  it('白名单外的第三方热链丢弃(防死链/防盗链,如 msn 404)', () => {
    expect(resolveImageUrl('dishes/x/y.md', 'https://img-s-msn-com.akamaized.net/a.img?w=768')).toBeNull();
    expect(resolveImageUrl('dishes/x/y.md', 'http://example.com/a.jpg')).toBeNull();
  });

  it('无引用返回 null', () => {
    expect(resolveImageUrl('dishes/x/y.md', undefined)).toBeNull();
  });
});

describe('isTemplateDish', () => {
  it('template 目录下的示例菜不是真菜', () => {
    expect(isTemplateDish('dishes/template/示例菜/示例菜.md')).toBe(true);
  });
  it('普通菜谱不受影响', () => {
    expect(isTemplateDish('dishes/vegetable_dish/凉拌黄瓜.md')).toBe(false);
  });
});
