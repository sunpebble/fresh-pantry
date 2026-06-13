import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

export const config = {
  outPath: resolve(root, '../ios/FreshPantry/Resources/howtocook.json'),
  existingPath: resolve(root, '../ios/FreshPantry/Resources/howtocook.json'),
  imagesDir: resolve(root, '../ios/FreshPantry/Resources/RecipeImages'),
  rejectsPath: resolve(root, 'data/rejects.json'),
  sourcesPath: resolve(root, 'data/sources.json'),
  workDir: resolve(root, '.cache'),
  model: process.env.RECIPE_MODEL ?? 'anthropic/claude-sonnet-4-6',
  // 'xhigh' 在 deepseek-v4-pro 上映射到 "max" 思考档(pi-ai thinkingLevelMap)
  thinkingLevel: (process.env.RECIPE_THINKING ?? 'xhigh') as 'off' | 'minimal' | 'low' | 'medium' | 'high' | 'xhigh',
  concurrency: Number(process.env.RECIPE_CONCURRENCY ?? '6'),
};
