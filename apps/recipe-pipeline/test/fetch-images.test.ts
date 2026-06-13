import { describe, it, expect } from 'vitest';
import { tmpdir } from 'node:os';
import { mkdtemp, mkdir, readFile, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import {
  acquireMissingImages,
  applyAcquiredImages,
  mergeAttributions,
  imageExtFromBuffer,
  webImageName,
  type ImageCandidate,
  type DishQuery,
} from '../src/clean/fetch-images';
import type { CleanRecipe } from '../src/clean/schema';

function rec(id: string, imageUrl: string | null, over: Partial<CleanRecipe> = {}): CleanRecipe {
  return {
    id, name: over.name ?? '咖喱炒蟹', category: '水产', difficulty: 2, cookingMinutes: 20,
    description: '', ingredients: [{ name: '蟹' }, { name: '咖喱' }], steps: [], tags: [],
    imageUrl, videoUrl: null, remoteVersion: 0, clientUpdatedAt: null, deletedAt: null, ...over,
  };
}

const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 16, 0x4a, 0x46, 0x49, 0x46, 0, 1]);
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0]);
const WEBP = Buffer.concat([Buffer.from('RIFF'), Buffer.from([0, 0, 0, 0]), Buffer.from('WEBP'), Buffer.alloc(4)]);
const HTML = Buffer.from('<!DOCTYPE html><html><body>404 not found</body></html>');
const LFS = Buffer.from('version https://git-lfs.github.com/spec/v1\noid sha256:abc\n');

async function setup() {
  const dir = await mkdtemp(join(tmpdir(), 'fi-'));
  const imagesDir = join(dir, 'RecipeImages');
  await mkdir(imagesDir, { recursive: true });
  return { imagesDir };
}

function staticSearch(cands: ImageCandidate[]) {
  return { search: async () => cands };
}

describe('imageExtFromBuffer', () => {
  it('按 magic bytes 识别 jpg/png/webp,非图片返回 null', () => {
    expect(imageExtFromBuffer(JPEG)).toBe('.jpg');
    expect(imageExtFromBuffer(PNG)).toBe('.png');
    expect(imageExtFromBuffer(WEBP)).toBe('.webp');
    expect(imageExtFromBuffer(HTML)).toBeNull();
    expect(imageExtFromBuffer(LFS)).toBeNull();
    expect(imageExtFromBuffer(Buffer.from([1, 2]))).toBeNull();
  });
});

describe('webImageName', () => {
  it('web_<id 去 source 前缀、/换_>.<ext>', () => {
    expect(webImageName('howtocook:aquatic/咖喱炒蟹', '.jpg')).toBe('web_aquatic_咖喱炒蟹.jpg');
    expect(webImageName('howtocook:breakfast/华夫饼/华夫饼', '.png')).toBe('web_breakfast_华夫饼_华夫饼.png');
  });
});

describe('acquireMissingImages', () => {
  it('缺图菜谱:下载首张通过校验的图、落盘、改路径、记出处', async () => {
    const { imagesDir } = await setup();
    const recipes = [rec('howtocook:aquatic/咖喱炒蟹', null)];
    const report = await acquireMissingImages(recipes, {
      imagesDir,
      search: staticSearch([{ url: 'https://x.test/crab.jpg', sourcePage: 'https://x.test/p', license: 'CC0' }]),
      fetchImage: async () => JPEG,
      now: '2026-06-13T00:00:00Z',
    });
    expect(report.acquired).toBe(1);
    expect(report.failed).toBe(0);
    expect(recipes[0].imageUrl).toBe('assets/recipes/images/web_aquatic_咖喱炒蟹.jpg');
    expect(await readFile(join(imagesDir, 'web_aquatic_咖喱炒蟹.jpg'))).toEqual(JPEG);
    expect(report.attributions[0]).toMatchObject({
      id: 'howtocook:aquatic/咖喱炒蟹', file: 'web_aquatic_咖喱炒蟹.jpg',
      sourceUrl: 'https://x.test/crab.jpg', sourcePage: 'https://x.test/p', license: 'CC0',
    });
  });

  it('跳过非图片体(HTML 错误页),试下一张候选', async () => {
    const { imagesDir } = await setup();
    const recipes = [rec('howtocook:aquatic/咖喱炒蟹', null)];
    const bodies = [HTML, PNG];
    let i = 0;
    const report = await acquireMissingImages(recipes, {
      imagesDir,
      search: staticSearch([{ url: 'https://x/a' }, { url: 'https://x/b' }]),
      fetchImage: async () => bodies[i++],
      now: 'now',
    });
    expect(report.acquired).toBe(1);
    expect(recipes[0].imageUrl).toBe('assets/recipes/images/web_aquatic_咖喱炒蟹.png');
  });

  it('校验器拒绝所有候选 → 留 null,记 failure', async () => {
    const { imagesDir } = await setup();
    const recipes = [rec('howtocook:aquatic/咖喱炒蟹', null)];
    const report = await acquireMissingImages(recipes, {
      imagesDir,
      search: staticSearch([{ url: 'https://x/a' }, { url: 'https://x/b' }]),
      fetchImage: async () => JPEG,
      verify: { verify: async () => ({ ok: false, reason: '不是这道菜' }) },
      now: 'now',
    });
    expect(report.acquired).toBe(0);
    expect(report.failed).toBe(1);
    expect(report.failures[0].id).toBe('howtocook:aquatic/咖喱炒蟹');
    expect(recipes[0].imageUrl).toBeNull();
    expect(await readdir(imagesDir)).toEqual([]); // 没落任何脏文件
  });

  it('校验器接受 → 取该张', async () => {
    const { imagesDir } = await setup();
    const recipes = [rec('howtocook:aquatic/咖喱炒蟹', null)];
    let seen: DishQuery | null = null;
    const report = await acquireMissingImages(recipes, {
      imagesDir,
      search: staticSearch([{ url: 'https://x/a.webp' }]),
      fetchImage: async () => WEBP,
      verify: { verify: async (_b, d) => { seen = d; return { ok: true }; } },
      now: 'now',
    });
    expect(report.acquired).toBe(1);
    expect(recipes[0].imageUrl).toBe('assets/recipes/images/web_aquatic_咖喱炒蟹.webp');
    expect(seen!.name).toBe('咖喱炒蟹');
    expect(seen!.ingredients).toContain('蟹');
  });

  it('已有图 / 软删条目不动,只补 null', async () => {
    const { imagesDir } = await setup();
    const recipes = [
      rec('a', 'assets/recipes/images/已有.jpg'),
      rec('b', null, { deletedAt: '2026-01-01T00:00:00Z' }),
      rec('howtocook:c/c', null, { name: '番茄炒蛋' }),
    ];
    let fetched = 0;
    const report = await acquireMissingImages(recipes, {
      imagesDir,
      search: staticSearch([{ url: 'https://x/c.jpg' }]),
      fetchImage: async () => { fetched++; return JPEG; },
      now: 'now',
    });
    expect(report.skipped).toBe(2);
    expect(report.acquired).toBe(1);
    expect(fetched).toBe(1); // 只为 c 下载
    expect(recipes[0].imageUrl).toBe('assets/recipes/images/已有.jpg');
    expect(recipes[1].imageUrl).toBeNull();
    expect(recipes[2].imageUrl).toBe('assets/recipes/images/web_c_c.jpg');
  });

  it('搜索无结果 / 下载全失败 → failed,不抛', async () => {
    const { imagesDir } = await setup();
    const recipes = [rec('howtocook:x/y', null), rec('howtocook:z/w', null, { name: '别的菜' })];
    const report = await acquireMissingImages(recipes, {
      imagesDir,
      search: { search: async (d) => (d.name === '别的菜' ? [] : [{ url: 'https://x/a' }]) },
      fetchImage: async () => null,
      now: 'now',
    });
    expect(report.acquired).toBe(0);
    expect(report.failed).toBe(2);
  });

  it('maxCandidates 限制尝试张数', async () => {
    const { imagesDir } = await setup();
    const recipes = [rec('howtocook:x/y', null)];
    let fetched = 0;
    await acquireMissingImages(recipes, {
      imagesDir,
      search: staticSearch([{ url: 'a' }, { url: 'b' }, { url: 'c' }, { url: 'd' }]),
      fetchImage: async () => { fetched++; return HTML; }, // 全非图片
      maxCandidates: 2,
      now: 'now',
    });
    expect(fetched).toBe(2);
  });
});

describe('applyAcquiredImages (workflow 回写路径)', () => {
  it('按 id 回写已落盘图的 imageUrl,只动缺图条目', () => {
    const recipes = [
      rec('howtocook:a/a', null, { name: '菜A' }),
      rec('howtocook:b/b', 'assets/recipes/images/有图.jpg', { name: '菜B' }),
      rec('howtocook:c/c', null, { name: '菜C' }),
    ];
    const { updated, attributions } = applyAcquiredImages(
      recipes,
      [
        { id: 'howtocook:a/a', file: 'web_a_a.jpg', sourceUrl: 'https://s/a.jpg', sourcePage: 'https://s/a' },
        { id: 'howtocook:b/b', file: 'web_b_b.jpg', sourceUrl: 'https://s/b.jpg' }, // 已有图,应忽略
      ],
      '2026-06-13T00:00:00Z',
    );
    expect(updated).toBe(1);
    expect(recipes[0].imageUrl).toBe('assets/recipes/images/web_a_a.jpg');
    expect(recipes[1].imageUrl).toBe('assets/recipes/images/有图.jpg');
    expect(recipes[2].imageUrl).toBeNull();
    expect(attributions).toHaveLength(1);
    expect(attributions[0]).toMatchObject({ id: 'howtocook:a/a', file: 'web_a_a.jpg', name: '菜A' });
  });
});

describe('mergeAttributions', () => {
  it('按 id 合并(新覆盖旧)并按 id 排序', () => {
    const prev = [
      { id: 'b', name: 'B', file: 'b.jpg', sourceUrl: 'u', acquiredAt: 't1' },
      { id: 'a', name: 'A', file: 'a-old.jpg', sourceUrl: 'u', acquiredAt: 't1' },
    ];
    const next = [{ id: 'a', name: 'A', file: 'a-new.jpg', sourceUrl: 'u2', acquiredAt: 't2' }];
    const merged = mergeAttributions(prev, next);
    expect(merged.map((m) => m.id)).toEqual(['a', 'b']);
    expect(merged[0].file).toBe('a-new.jpg');
  });
});
