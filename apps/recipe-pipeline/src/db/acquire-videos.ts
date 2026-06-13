import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { acquireMissingVideos, mergeVideoAttributions, type VideoAttribution } from '../clean/fetch-videos';
import { createBilibiliVideoSearch } from '../sources/video-search-bilibili';
import type { CleanRecipe } from '../clean/schema';
import { config } from '../config';

/**
 * pipeline 自带的视频补齐:读 howtocook.json,为缺视频的菜谱用 B站搜索 provider 补一条
 * 做法视频外链,写回 + 合并出处。确定性、可复跑、免 key、无需 LLM/agent。
 * 用 tsx 直跑:`npx tsx src/db/acquire-videos.ts`(= `npm run videos:acquire`)。
 * 重跑后 `npm run gen:seed` 同步 DB。
 */
const recipes = JSON.parse(readFileSync(config.outPath, 'utf8')) as CleanRecipe[];
const now = new Date().toISOString();
const report = await acquireMissingVideos(recipes, {
  search: createBilibiliVideoSearch(),
  now,
  // B站按请求频率风控:默认慢节流 1.5s(可用 RECIPE_VIDEO_DELAY_MS 调),配合 provider 命中风控重取 cookie 退避。
  delayMs: Number(process.env.RECIPE_VIDEO_DELAY_MS ?? '1500'),
  log: (m) => console.log(`[videos] ${m}`),
});
writeFileSync(config.outPath, JSON.stringify(recipes, null, 2) + '\n', 'utf8');

const prev: VideoAttribution[] = existsSync(config.videoAttributionsPath)
  ? (JSON.parse(readFileSync(config.videoAttributionsPath, 'utf8')) as VideoAttribution[])
  : [];
writeFileSync(
  config.videoAttributionsPath,
  JSON.stringify(mergeVideoAttributions(prev, report.attributions), null, 2) + '\n',
  'utf8',
);

console.log(`videos:acquire — 补 ${report.acquired} 条,未找到 ${report.failed} 条,跳过(已有/软删)${report.skipped} 条`);
console.log(`出处 → ${config.videoAttributionsPath}`);
