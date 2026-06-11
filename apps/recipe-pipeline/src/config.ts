import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

export const config = {
  outPath: resolve(root, '../ios/FreshPantry/Resources/howtocook.json'),
  existingPath: resolve(root, '../ios/FreshPantry/Resources/howtocook.json'),
  rejectsPath: resolve(root, 'data/rejects.json'),
  sourcesPath: resolve(root, 'data/sources.json'),
  workDir: resolve(root, '.cache'),
  model: process.env.RECIPE_MODEL ?? 'anthropic/claude-sonnet-4-6',
  concurrency: Number(process.env.RECIPE_CONCURRENCY ?? '6'),
};
