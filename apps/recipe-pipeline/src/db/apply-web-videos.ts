import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  applyAcquiredVideos, mergeVideoAttributions,
  type AcquiredVideo, type VideoAttribution,
} from '../clean/fetch-videos';
import type { CleanRecipe } from '../clean/schema';
import { config } from '../config';

/**
 * 把 ultracode「联网搜视频」workflow 的产物回写进 howtocook.json。
 * 用 tsx 直跑:`npx tsx src/db/apply-web-videos.ts`(= `npm run videos:apply`)。
 *
 * 每个 agent 把这一条结果写成 data/acquired-videos/<index>.json。本脚本聚合,
 * 经已测纯函数 applyAcquiredVideos 给仍缺视频的菜谱回填 videoUrl(外链,既有优先),
 * 并把出处合并进 data/video-attributions.json。重跑后 `npm run gen:seed` 同步 DB。
 */
const here = dirname(fileURLToPath(import.meta.url));
const acquiredDir = resolve(here, '../../data/acquired-videos');

interface MetaFile {
  index?: number;
  id?: string;
  ok?: boolean;
  videoUrl?: string | null;
  sourcePage?: string | null;
  title?: string | null;
  provider?: string | null;
  confidence?: string | null;
  reason?: string;
}

function readMetaFiles(): MetaFile[] {
  const metas: MetaFile[] = [];
  if (!existsSync(acquiredDir)) return metas;
  for (const name of readdirSync(acquiredDir)) {
    if (!/^\d+\.json$/.test(name)) continue; // 只收 <index>.json,跳过 _dishes.json
    try {
      metas.push(JSON.parse(readFileSync(join(acquiredDir, name), 'utf8')) as MetaFile);
    } catch {
      console.warn(`跳过损坏的 meta: ${name}`);
    }
  }
  return metas;
}

const metas = readMetaFiles();
// 只采纳 ok 且有真实 http(s) videoUrl 的(防 agent 自报 ok 但 url 空/无效)。
const acquired: AcquiredVideo[] = metas
  .filter((m) => m.ok && m.id && m.videoUrl && /^https?:\/\//.test(m.videoUrl))
  .map((m) => ({
    id: m.id!, videoUrl: m.videoUrl!,
    sourcePage: m.sourcePage ?? undefined, title: m.title ?? undefined,
    provider: m.provider ?? undefined,
  }));

const recipes = JSON.parse(readFileSync(config.outPath, 'utf8')) as CleanRecipe[];
const now = new Date().toISOString();
const { updated, attributions } = applyAcquiredVideos(recipes, acquired, now);

writeFileSync(config.outPath, JSON.stringify(recipes, null, 2) + '\n', 'utf8');

const prevAttr: VideoAttribution[] = existsSync(config.videoAttributionsPath)
  ? (JSON.parse(readFileSync(config.videoAttributionsPath, 'utf8')) as VideoAttribution[])
  : [];
const mergedAttr = mergeVideoAttributions(prevAttr, attributions);
writeFileSync(config.videoAttributionsPath, JSON.stringify(mergedAttr, null, 2) + '\n', 'utf8');

const stillMissing = recipes.filter((r) => (r.videoUrl === null || r.videoUrl === '') && !r.deletedAt).length;
console.log(`apply-web-videos:`);
console.log(`  meta 文件 ${metas.length} 条,有效外链 ${acquired.length} 条`);
console.log(`  回写 videoUrl ${updated} 条 → ${config.outPath}`);
console.log(`  出处累计 ${mergedAttr.length} 条 → ${config.videoAttributionsPath}`);
console.log(`  仍缺视频 ${stillMissing} 条`);
