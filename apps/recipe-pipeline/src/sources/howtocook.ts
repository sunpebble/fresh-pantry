import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile, readdir, stat } from 'node:fs/promises';
import { join, relative, basename } from 'node:path';
import type { RecipeSource, RawRecipe, SourceContext } from './types';
import { parseHowtocook } from '../parse/howtocook-parser';
import { mapHowtocookCategory } from '../parse/category-map';

const exec = promisify(execFile);
const REPO = 'https://github.com/Anduin2017/HowToCook.git';
// HowToCook 的图是 Git-LFS;jsDelivr 对 LFS 解析不可靠(部分文件返回 pointer 文本),
// media.githubusercontent.com 是官方 LFS CDN,稳定回真图。远程 URL 仅作新菜临时兜底,
// 长期应 vendor 进 app bundle(RecipeImages/)换成 assets/ 路径。
const MEDIA_BASE = 'https://media.githubusercontent.com/media/Anduin2017/HowToCook/master';
// 绝对外链只信 GitHub 系 CDN;其余第三方热链(防盗链/失效,如 msn 404)一律丢弃
const TRUSTED_IMAGE_HOSTS = /^https:\/\/[\w.-]+\.githubusercontent\.com\//;

/** dishes/template/ 下是菜谱模板示例,不是真菜。 */
export function isTemplateDish(relPath: string): boolean {
  return relPath.startsWith('dishes/template/');
}

/** md 里的图片引用 → 可直接加载的绝对 URL(相对引用拼 jsDelivr 并 percent-encode)。 */
export function resolveImageUrl(relPath: string, imageRef?: string): string | null {
  if (!imageRef) return null;
  if (/^https?:\/\//.test(imageRef)) {
    return TRUSTED_IMAGE_HOSTS.test(imageRef) ? imageRef : null;
  }
  const dir = relPath.split('/').slice(0, -1).join('/');
  const ref = imageRef.replace(/^\.\//, '');
  return encodeURI(`${MEDIA_BASE}/${dir}/${ref}`);
}

export function howtocookIdFromPath(relPath: string): string {
  const noPrefix = relPath.replace(/^dishes\//, '').replace(/\.md$/, '');
  return `howtocook:${noPrefix}`;
}

export function rawFromMarkdown(relPath: string, md: string): RawRecipe {
  const parsed = parseHowtocook(md);
  const engCat = relPath.replace(/^dishes\//, '').split('/')[0];
  return {
    id: howtocookIdFromPath(relPath),
    sourceId: 'howtocook',
    sourceRef: relPath,
    name: parsed.name || basename(relPath, '.md'),
    sourceCategory: mapHowtocookCategory(engCat),
    sourceDifficulty: parsed.difficulty,
    sourceCookingMinutes: parsed.sourceCookingMinutes,
    description: parsed.description,
    rawIngredients: parsed.rawIngredients,
    portionText: parsed.portionText,
    steps: parsed.steps,
    imageUrl: resolveImageUrl(relPath, parsed.imageRef),
  };
}

async function* walkMarkdown(dir: string, root: string): AsyncIterable<string> {
  for (const entry of await readdir(dir)) {
    const full = join(dir, entry);
    const s = await stat(full);
    if (s.isDirectory()) yield* walkMarkdown(full, root);
    else if (entry.endsWith('.md') && entry !== 'README.md') yield relative(root, full);
  }
}

export function howtocookSource(): RecipeSource {
  return {
    id: 'howtocook',
    kind: 'deterministic',
    async *collect(ctx: SourceContext): AsyncIterable<RawRecipe> {
      const repoDir = join(ctx.workDir, 'howtocook');
      await exec('git', ['clone', '--depth', '1', REPO, repoDir]).catch((e) => {
        ctx.log(`clone 跳过/失败 (${String(e)});尝试复用已有缓存 ${repoDir}`);
      });
      const dishesDir = join(repoDir, 'dishes');
      const ok = await stat(dishesDir).then((s) => s.isDirectory()).catch(() => false);
      if (!ok) {
        throw new Error(
          `HowToCook 仓库不可用(克隆失败且无缓存): ${dishesDir} —— 请检查网络,或手动克隆到 ${repoDir}`,
        );
      }
      for await (const relPath of walkMarkdown(dishesDir, repoDir)) {
        if (isTemplateDish(relPath)) continue;
        const md = await readFile(join(repoDir, relPath), 'utf8');
        const raw = rawFromMarkdown(relPath, md);
        if (raw.rawIngredients.length || raw.steps.length) yield raw;
      }
    },
  };
}
