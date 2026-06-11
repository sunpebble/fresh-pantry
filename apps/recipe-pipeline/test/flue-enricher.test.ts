import { describe, it, expect } from 'vitest';
import { createFlueEnricher } from '../src/clean/flue-enricher';
import type { RawRecipe } from '../src/sources/types';
import type { Enrichment } from '../src/clean/schema';

const enrichment: Enrichment = {
  category: '荤菜', difficulty: 2, cookingMinutes: 15, description: 'x',
  ingredients: [], steps: [], tags: [],
};

function raw(id: string): RawRecipe {
  return { id, sourceId: 's', sourceRef: id, name: id, rawIngredients: [], steps: [], imageUrl: null };
}

describe('createFlueEnricher', () => {
  it('每条菜用各自 id 作为独立 session,并返回校验后的 data', async () => {
    const sessions: string[] = [];
    const fakeHarness = {
      async session(name?: string) {
        sessions.push(name ?? '(default)');
        return { prompt: async (_text: string, _opts: unknown) => ({ data: enrichment }) };
      },
    } as unknown as Parameters<typeof createFlueEnricher>[0];

    const enricher = createFlueEnricher(fakeHarness);
    const a = await enricher.enrich(raw('howtocook:x/a'));
    await enricher.enrich(raw('howtocook:x/b'));

    expect(sessions).toEqual(['howtocook:x/a', 'howtocook:x/b']); // 各自独立 session,非共享 default
    expect(a.category).toBe('荤菜'); // 返回 .data
  });
});
