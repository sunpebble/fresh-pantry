import { copyFile, readFile, writeFile, access } from 'node:fs/promises';
import { join, extname } from 'node:path';
import type { CleanRecipe } from './schema';

/**
 * 远程菜谱封面 vendor 进 app bundle:浏览页必须离线可用、零外链依赖
 * (HowToCook 的图是 Git-LFS,公共 CDN 行为不稳定)。merge 之后调用,
 * 只处理 imageUrl 仍是 http(s) 的条目(既有 assets/ 路径不会被碰)。
 */

export interface VendorImagesDeps {
  /** app bundle 的 RecipeImages 目录(folder reference,丢文件即打包)。 */
  imagesDir: string;
  /** HowToCook 本地克隆;非 LFS 文件直接 copy,零网络。 */
  repoDir: string;
  /** 下载真图;失败返回 null。注入以便测试 mock。 */
  fetchImage: (url: string) => Promise<Buffer | null>;
  log?: (msg: string) => void;
}

export interface VendorReport {
  vendored: number;
  kept: number;
}

const LFS_POINTER_PREFIX = 'version https://git-lfs';
const ASSETS_PREFIX = 'assets/recipes/images/';

function isLfsPointer(buf: Buffer): boolean {
  return buf.subarray(0, LFS_POINTER_PREFIX.length).toString('utf8') === LFS_POINTER_PREFIX;
}

/** 旧 Dart 导入的命名约定:howtocook_<id 路径下划线连接>.<URL 扩展名小写>。 */
export function vendoredImageName(id: string, remoteUrl: string): string {
  const idPath = id.replace(/^howtocook:/, '').replace(/\//g, '_');
  const ext = extname(new URL(remoteUrl).pathname).toLowerCase() || '.jpg';
  return `howtocook_${idPath}${ext}`;
}

/** URL 还原为本地克隆内的相对路径(…/master/<path>)。非该仓库的 URL 返回 null。 */
function repoRelativePath(remoteUrl: string): string | null {
  const m = remoteUrl.match(/\/master\/(.+)$/);
  return m ? decodeURIComponent(m[1]) : null;
}

async function exists(path: string): Promise<boolean> {
  return access(path).then(() => true).catch(() => false);
}

export async function vendorRemoteImages(
  recipes: CleanRecipe[],
  deps: VendorImagesDeps,
): Promise<VendorReport> {
  const log = deps.log ?? (() => {});
  const report: VendorReport = { vendored: 0, kept: 0 };

  for (const r of recipes) {
    const url = r.imageUrl;
    if (!url || !/^https?:\/\//.test(url)) continue;

    const name = vendoredImageName(r.id, url);
    const target = join(deps.imagesDir, name);
    if (await exists(target)) {
      r.imageUrl = ASSETS_PREFIX + name;
      report.vendored++;
      continue;
    }

    let image: Buffer | null = null;
    const rel = repoRelativePath(url);
    if (rel) {
      const localPath = join(deps.repoDir, rel);
      if (await exists(localPath)) {
        const buf = await readFile(localPath);
        if (!isLfsPointer(buf)) {
          await copyFile(localPath, target);
          r.imageUrl = ASSETS_PREFIX + name;
          report.vendored++;
          continue;
        }
      }
    }

    image = await deps.fetchImage(url).catch(() => null);
    if (!image || isLfsPointer(image)) {
      log(`封面下载失败,保留远程 URL 下次再试: ${r.id}`);
      report.kept++;
      continue;
    }
    await writeFile(target, image);
    r.imageUrl = ASSETS_PREFIX + name;
    report.vendored++;
  }
  return report;
}

/** 生产实现:全局 fetch 下载;非 2xx 或非图片体返回 null。 */
export async function fetchImageBuffer(url: string): Promise<Buffer | null> {
  const res = await fetch(url).catch(() => null);
  if (!res || !res.ok) return null;
  return Buffer.from(await res.arrayBuffer());
}
