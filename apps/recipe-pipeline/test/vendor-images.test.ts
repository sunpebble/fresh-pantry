import { describe, it, expect } from 'vitest';
import { tmpdir } from 'node:os';
import { mkdtemp, mkdir, writeFile, readFile, access } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { vendoredImageName, vendorRemoteImages } from '../src/clean/vendor-images';
import type { CleanRecipe } from '../src/clean/schema';

function rec(id: string, imageUrl: string | null): CleanRecipe {
  return {
    id, name: '菜', category: '荤菜', difficulty: 2, cookingMinutes: 20,
    description: '', ingredients: [], steps: [], tags: [], imageUrl,
    remoteVersion: 0, clientUpdatedAt: null, deletedAt: null,
  };
}

const URL_BASE = 'https://media.githubusercontent.com/media/Anduin2017/HowToCook/master';
const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
const POINTER = Buffer.from('version https://git-lfs.github.com/spec/v1\noid sha256:abc\nsize 7\n');

async function setup() {
  const dir = await mkdtemp(join(tmpdir(), 'vi-'));
  const imagesDir = join(dir, 'RecipeImages');
  const repoDir = join(dir, 'howtocook');
  await mkdir(imagesDir, { recursive: true });
  return { imagesDir, repoDir };
}

describe('vendoredImageName(沿用旧 Dart 导入的命名约定)', () => {
  it('howtocook_<id 路径下划线连接>.<URL 扩展名小写>', () => {
    expect(vendoredImageName(
      'howtocook:aquatic/小龙虾/小龙虾',
      `${URL_BASE}/dishes/aquatic/%E5%B0%8F%E9%BE%99%E8%99%BE/%E6%88%90%E5%93%81.jpg`,
    )).toBe('howtocook_aquatic_小龙虾_小龙虾.jpg');
    expect(vendoredImageName(
      'howtocook:vegetable_dish/蒜蓉空心菜/蒜蓉空心菜',
      `${URL_BASE}/dishes/vegetable_dish/x/1.JPG`,
    )).toBe('howtocook_vegetable_dish_蒜蓉空心菜_蒜蓉空心菜.jpg');
    expect(vendoredImageName('howtocook:aquatic/蛏抱蛋', `${URL_BASE}/d/x.jpeg`))
      .toBe('howtocook_aquatic_蛏抱蛋.jpeg');
  });
});

describe('vendorRemoteImages', () => {
  it('本地克隆有真图(非 LFS pointer)→ 直接 copy,不走网络', async () => {
    const { imagesDir, repoDir } = await setup();
    const local = join(repoDir, 'dishes/aquatic/小龙虾/成品.jpg');
    await mkdir(dirname(local), { recursive: true });
    await writeFile(local, JPEG);
    const recipes = [rec('howtocook:aquatic/小龙虾/小龙虾',
      `${URL_BASE}/dishes/aquatic/%E5%B0%8F%E9%BE%99%E8%99%BE/%E6%88%90%E5%93%81.jpg`)];
    let fetched = 0;
    const report = await vendorRemoteImages(recipes, {
      imagesDir, repoDir, fetchImage: async () => { fetched++; return JPEG; },
    });
    expect(report.vendored).toBe(1);
    expect(fetched).toBe(0);
    expect(recipes[0].imageUrl).toBe('assets/recipes/images/howtocook_aquatic_小龙虾_小龙虾.jpg');
    expect(await readFile(join(imagesDir, 'howtocook_aquatic_小龙虾_小龙虾.jpg'))).toEqual(JPEG);
  });

  it('本地是 LFS pointer → 走 fetchImage 下载真图', async () => {
    const { imagesDir, repoDir } = await setup();
    const local = join(repoDir, 'dishes/meat_dish/农家一碗香/农家一碗香成品.jpg');
    await mkdir(dirname(local), { recursive: true });
    await writeFile(local, POINTER);
    const recipes = [rec('howtocook:meat_dish/农家一碗香/农家一碗香',
      `${URL_BASE}/dishes/meat_dish/${encodeURIComponent('农家一碗香')}/${encodeURIComponent('农家一碗香成品')}.jpg`)];
    const report = await vendorRemoteImages(recipes, {
      imagesDir, repoDir, fetchImage: async () => JPEG,
    });
    expect(report.vendored).toBe(1);
    expect(recipes[0].imageUrl).toBe('assets/recipes/images/howtocook_meat_dish_农家一碗香_农家一碗香.jpg');
  });

  it('下载失败(或回包仍是 pointer)→ 保留远程 URL 下次再试', async () => {
    const { imagesDir, repoDir } = await setup();
    const url = `${URL_BASE}/dishes/x/y/z.jpg`;
    const recipes = [rec('howtocook:x/y', url)];
    const report = await vendorRemoteImages(recipes, {
      imagesDir, repoDir, fetchImage: async () => null,
    });
    expect(report.vendored).toBe(0);
    expect(recipes[0].imageUrl).toBe(url);

    const recipes2 = [rec('howtocook:x/y', url)];
    await vendorRemoteImages(recipes2, {
      imagesDir, repoDir, fetchImage: async () => POINTER,
    });
    expect(recipes2[0].imageUrl).toBe(url);
  });

  it('目标文件已存在 → 幂等跳过下载,直接改写路径', async () => {
    const { imagesDir, repoDir } = await setup();
    await writeFile(join(imagesDir, 'howtocook_x_y.jpg'), JPEG);
    const recipes = [rec('howtocook:x/y', `${URL_BASE}/dishes/x/y/cover.jpg`)];
    let fetched = 0;
    await vendorRemoteImages(recipes, {
      imagesDir, repoDir, fetchImage: async () => { fetched++; return JPEG; },
    });
    expect(fetched).toBe(0);
    expect(recipes[0].imageUrl).toBe('assets/recipes/images/howtocook_x_y.jpg');
  });

  it('本地路径(assets/)与空 imageUrl 不受影响', async () => {
    const { imagesDir, repoDir } = await setup();
    const recipes = [rec('a', 'assets/recipes/images/已有.jpg'), rec('b', null)];
    const report = await vendorRemoteImages(recipes, {
      imagesDir, repoDir, fetchImage: async () => JPEG,
    });
    expect(report.vendored).toBe(0);
    expect(recipes[0].imageUrl).toBe('assets/recipes/images/已有.jpg');
    expect(recipes[1].imageUrl).toBeNull();
    await access(imagesDir); // 目录仍在,无副作用文件
  });
});
