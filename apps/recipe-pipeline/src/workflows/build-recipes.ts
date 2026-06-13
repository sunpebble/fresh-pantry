import { readFile } from 'node:fs/promises';
import type { FlueContext } from '@flue/runtime';
import recipeCleaner from '../agents/recipe-cleaner';
import { createFlueEnricher } from '../clean/flue-enricher';
import { createCloudflareEnricher } from '../clean/cloudflare-enricher';
import { buildSources, type SourcesFile } from '../sources/registry';
import { createOpenverseSearch } from '../sources/image-search-openverse';
import { runPipeline } from '../pipeline';
import { config } from '../config';

export interface BuildPayload {
  limit?: number;
  /** 只处理这些 id(单条补跑)。 */
  only?: string[];
  /** 跳过封面 acquire/vendor(只修用量时护住已迁 Storage 的 imageUrl)。 */
  skipImages?: boolean;
  dryRun?: boolean;
  refreshDescriptions?: boolean;
}

export async function run({ init, payload }: FlueContext<BuildPayload>) {
  const enricher = config.useCloudflare
    ? createCloudflareEnricher({
        baseUrl: config.cloudflare.baseUrl,
        apiKey: config.cloudflare.apiKey,
        model: config.model,
        maxTokens: config.cloudflare.maxTokens,
        log: (m) => console.log(`[recipes:cf] ${m}`),
      })
    : createFlueEnricher(await init(recipeCleaner));

  const sourcesFile = JSON.parse(await readFile(config.sourcesPath, 'utf8')) as SourcesFile;
  const sources = buildSources(sourcesFile, enricher);

  const report = await runPipeline({
    sources,
    enricher,
    existingPath: config.existingPath,
    outPath: config.outPath,
    rejectsPath: config.rejectsPath,
    workDir: config.workDir,
    imagesDir: config.imagesDir,
    imageSearch: config.acquireImages ? createOpenverseSearch() : undefined,
    attributionsPath: config.attributionsPath,
    now: new Date().toISOString(),
    concurrency: config.concurrency,
    limit: payload?.limit,
    only: payload?.only,
    skipImages: payload?.skipImages,
    dryRun: payload?.dryRun,
    refreshDescriptions: payload?.refreshDescriptions,
    log: (m) => console.log(`[recipes] ${m}`),
  });

  console.log('[recipes] report', report);
  return report;
}
