import { readFile } from 'node:fs/promises';
import * as v from 'valibot';
import type { RecipeSource, RawRecipe, SourceContext } from './sources/types';
import type { RecipeEnricher } from './clean/enrich';
import { assembleRecipe } from './clean/enrich';
import { CleanRecipeSchema, type CleanRecipe } from './clean/schema';
import { dedupe } from './clean/dedup';
import { mergeWithExisting, type MergeOptions } from './clean/merge';
import { mapWithConcurrency } from './util/pool';
import { atomicWriteJson } from './util/atomic-write';

export interface PipelineDeps extends MergeOptions {
  sources: RecipeSource[];
  enricher: RecipeEnricher;
  existingPath: string;
  outPath: string;
  rejectsPath: string;
  now: string;
  workDir?: string;
  concurrency?: number;
  limit?: number;
  dryRun?: boolean;
  log?: (msg: string) => void;
}

export interface PipelineReport {
  collected: number;
  cleaned: number;
  rejected: number;
  deduped: number;
  added: number;
  updated: number;
  unchanged: number;
  total: number;
}

interface Reject {
  id: string;
  name: string;
  sourceRef: string;
  error: string;
}

export async function runPipeline(deps: PipelineDeps): Promise<PipelineReport> {
  const log = deps.log ?? (() => {});
  const ctx: SourceContext = { workDir: deps.workDir ?? '.cache', log };

  const raws: RawRecipe[] = [];
  for (const src of deps.sources) {
    for await (const r of src.collect(ctx)) {
      raws.push(r);
      if (deps.limit && raws.length >= deps.limit) break;
    }
    if (deps.limit && raws.length >= deps.limit) break;
  }
  log(`collected ${raws.length}`);

  const rejects: Reject[] = [];
  const cleanedNullable = await mapWithConcurrency(
    raws,
    deps.concurrency ?? 6,
    async (raw): Promise<CleanRecipe | null> => {
      try {
        const enr = await deps.enricher.enrich(raw);
        const assembled = assembleRecipe(raw, enr);
        return v.parse(CleanRecipeSchema, assembled);
      } catch (err) {
        rejects.push({
          id: raw.id, name: raw.name, sourceRef: raw.sourceRef,
          error: err instanceof Error ? err.message : String(err),
        });
        return null;
      }
    },
  );
  const cleaned = cleanedNullable.filter((r): r is CleanRecipe => r !== null);
  log(`cleaned ${cleaned.length}, rejected ${rejects.length}`);

  const { kept, dropped } = dedupe(cleaned);
  log(`deduped: dropped ${dropped.length}`);

  const existingRaw = await readFile(deps.existingPath, 'utf8').catch(() => '[]');
  const existing = JSON.parse(existingRaw) as CleanRecipe[];
  const { merged, stats } = mergeWithExisting(kept, existing, deps.now, {
    refreshDescriptions: deps.refreshDescriptions,
  });

  if (!deps.dryRun) {
    await atomicWriteJson(deps.outPath, merged);
    if (rejects.length) await atomicWriteJson(deps.rejectsPath, rejects);
  }

  return {
    collected: raws.length, cleaned: cleaned.length, rejected: rejects.length,
    deduped: dropped.length, added: stats.added, updated: stats.updated,
    unchanged: stats.unchanged, total: merged.length,
  };
}
