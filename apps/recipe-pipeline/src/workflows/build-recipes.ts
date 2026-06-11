import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import type { FlueContext } from '@flue/runtime';
import recipeCleaner from '../agents/recipe-cleaner';
import { createFlueEnricher } from '../clean/flue-enricher';
import { buildSources, type SourcesFile } from '../sources/registry';
import { runPipeline } from '../pipeline';
import { config } from '../config';

export interface BuildPayload {
  limit?: number;
  dryRun?: boolean;
  refreshDescriptions?: boolean;
}

export async function run({ init, payload }: FlueContext<BuildPayload>) {
  const harness = await init(recipeCleaner);
  const enricher = createFlueEnricher(harness);

  const sourcesPath = resolve(dirname(fileURLToPath(import.meta.url)), '../../data/sources.json');
  const sourcesFile = JSON.parse(await readFile(sourcesPath, 'utf8')) as SourcesFile;
  const sources = buildSources(sourcesFile, enricher);

  const report = await runPipeline({
    sources,
    enricher,
    existingPath: config.existingPath,
    outPath: config.outPath,
    rejectsPath: config.rejectsPath,
    workDir: config.workDir,
    now: new Date().toISOString(),
    concurrency: config.concurrency,
    limit: payload?.limit,
    dryRun: payload?.dryRun,
    refreshDescriptions: payload?.refreshDescriptions,
    log: (m) => console.log(`[recipes] ${m}`),
  });

  console.log('[recipes] report', report);
  return report;
}
