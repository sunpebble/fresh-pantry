import { describe, it, expect } from 'vitest';
import { tmpdir } from 'node:os';
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { runPipeline } from '../src/pipeline';
import type { RecipeSource, RawRecipe } from '../src/sources/types';
import type { RecipeEnricher } from '../src/clean/enrich';
import type { Enrichment } from '../src/clean/schema';

function source(id: string, recipes: RawRecipe[]): RecipeSource {
  return {
    id, kind: 'deterministic',
    async *collect() { for (const r of recipes) yield r; },
  };
}

const stubEnricher: RecipeEnricher = {
  async enrich(raw): Promise<Enrichment> {
    return {
      category: '荤菜', difficulty: 2, cookingMinutes: 15, description: raw.description ?? '描述',
      ingredients: raw.rawIngredients.map((n) => ({ name: n, quantity: '', unit: '', amount: '' })),
      steps: raw.steps, tags: [],
    };
  },
};

async function setup() {
  const dir = await mkdtemp(join(tmpdir(), 'rp-'));
  const existingPath = join(dir, 'howtocook.json');
  const outPath = existingPath;
  const rejectsPath = join(dir, 'rejects.json');
  return { dir, existingPath, outPath, rejectsPath };
}

const raw = (id: string, name: string): RawRecipe => ({
  id, sourceId: 'howtocook', sourceRef: id, name, sourceCategory: '素菜', sourceDifficulty: 1,
  rawIngredients: ['黄瓜'], steps: ['切'], imageUrl: null,
});

describe('runPipeline', () => {
  it('空既有 -> 全部新增并写盘', async () => {
    const { existingPath, outPath, rejectsPath, dir } = await setup();
    await writeFile(existingPath, '[]', 'utf8');
    const report = await runPipeline({
      sources: [source('howtocook', [raw('howtocook:vegetable_dish/凉拌黄瓜', '凉拌黄瓜')])],
      enricher: stubEnricher, existingPath, outPath, rejectsPath,
      now: '2026-06-12T00:00:00.000Z', concurrency: 2,
    });
    expect(report.added).toBe(1);
    const written = JSON.parse(await readFile(outPath, 'utf8'));
    expect(written).toHaveLength(1);
    expect(written[0].category).toBe('素菜');
    void dir;
  });

  it('保住既有 imageUrl', async () => {
    const { existingPath, outPath, rejectsPath } = await setup();
    await writeFile(existingPath, JSON.stringify([{
      id: 'howtocook:vegetable_dish/凉拌黄瓜', name: '凉拌黄瓜', category: '素菜', difficulty: 1,
      cookingMinutes: 20, description: '老描述', ingredients: [], steps: [], tags: [],
      imageUrl: 'https://img.jpg', remoteVersion: 5, clientUpdatedAt: null, deletedAt: null,
    }]), 'utf8');
    await runPipeline({
      sources: [source('howtocook', [raw('howtocook:vegetable_dish/凉拌黄瓜', '凉拌黄瓜')])],
      enricher: stubEnricher, existingPath, outPath, rejectsPath,
      now: '2026-06-12T00:00:00.000Z',
    });
    const written = JSON.parse(await readFile(outPath, 'utf8'));
    expect(written[0].imageUrl).toBe('https://img.jpg');
    expect(written[0].description).toBe('老描述');
    expect(written[0].remoteVersion).toBe(5);
  });

  it('dry-run 不写盘', async () => {
    const { existingPath, outPath, rejectsPath } = await setup();
    await writeFile(existingPath, '[]', 'utf8');
    const report = await runPipeline({
      sources: [source('howtocook', [raw('howtocook:x/a', 'A')])],
      enricher: stubEnricher, existingPath, outPath, rejectsPath,
      now: '2026-06-12T00:00:00.000Z', dryRun: true,
    });
    expect(report.added).toBe(1);
    expect(await readFile(outPath, 'utf8')).toBe('[]');
  });

  it('enricher 抛错的菜进 rejects 不中断', async () => {
    const { existingPath, outPath, rejectsPath } = await setup();
    await writeFile(existingPath, '[]', 'utf8');
    const flaky: RecipeEnricher = {
      async enrich(r) {
        if (r.name === '坏菜') throw new Error('boom');
        return stubEnricher.enrich(r);
      },
    };
    const report = await runPipeline({
      sources: [source('s', [raw('howtocook:x/good', '好菜'), raw('howtocook:x/bad', '坏菜')])],
      enricher: flaky, existingPath, outPath, rejectsPath,
      now: '2026-06-12T00:00:00.000Z',
    });
    expect(report.rejected).toBe(1);
    expect(report.added).toBe(1);
    const rejects = JSON.parse(await readFile(rejectsPath, 'utf8'));
    expect(rejects[0].name).toBe('坏菜');
  });

  it('limit 截断采集', async () => {
    const { existingPath, outPath, rejectsPath } = await setup();
    await writeFile(existingPath, '[]', 'utf8');
    const report = await runPipeline({
      sources: [source('s', [raw('howtocook:x/a', 'A'), raw('howtocook:x/b', 'B'), raw('howtocook:x/c', 'C')])],
      enricher: stubEnricher, existingPath, outPath, rejectsPath,
      now: '2026-06-12T00:00:00.000Z', limit: 2,
    });
    expect(report.collected).toBe(2);
  });
});
