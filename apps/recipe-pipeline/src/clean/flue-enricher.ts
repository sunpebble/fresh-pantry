import type { FlueHarness } from '@flue/runtime';
import { EnrichmentSchema } from './schema';
import { buildEnrichPrompt, type RecipeEnricher } from './enrich';

// Confines flue's session/prompt specifics behind the RecipeEnricher seam.
// `FlueHarness` is the real type returned by `FlueContext.init(agent)`.
// `session.prompt(text, { result: <valibot schema> })` resolves with a
// `PromptResultResponse` whose `.data` is the valibot-inferred output —
// which for EnrichmentSchema is exactly `Enrichment` (the enricher's return).
export function createFlueEnricher(harness: FlueHarness): RecipeEnricher {
  return {
    async enrich(raw) {
      const session = await harness.session();
      const res = await session.prompt(buildEnrichPrompt(raw), { result: EnrichmentSchema });
      return res.data;
    },
  };
}
