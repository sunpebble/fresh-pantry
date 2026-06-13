import { readFile } from 'node:fs/promises';
import type { FlueContext } from '@flue/runtime';
import recipeCleaner from '../agents/recipe-cleaner';
import { createFlueEnricher } from '../clean/flue-enricher';
import { buildSources, type SourcesFile } from '../sources/registry';
import { runPipeline } from '../pipeline';
import { config } from '../config';

export interface BuildPayload {
  limit?: number;
  /** 只处理这些 id(单条补跑)。 */
  only?: string[];
  dryRun?: boolean;
  refreshDescriptions?: boolean;
}

export async function run({ init, payload }: FlueContext<BuildPayload>) {
  const harness = await init(recipeCleaner);
  const enricher = createFlueEnricher(harness);

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
    now: new Date().toISOString(),
    concurrency: config.concurrency,
    limit: payload?.limit,
    only: payload?.only,
    dryRun: payload?.dryRun,
    refreshDescriptions: payload?.refreshDescriptions,
    log: (m) => console.log(`[recipes] ${m}`),
  });

  console.log('[recipes] report', report);
  return report;
}
