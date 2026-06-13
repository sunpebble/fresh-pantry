import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

const CF_DEFAULT_BASE =
  'https://api.cloudflare.com/client/v4/accounts/3967805080c0f0812c8e59d1f9c699a6/ai/v1';
const recipeModel = process.env.RECIPE_MODEL ?? '@cf/moonshotai/kimi-k2.7-code';

export const config = {
  outPath: resolve(root, '../ios/FreshPantry/Resources/howtocook.json'),
  existingPath: resolve(root, '../ios/FreshPantry/Resources/howtocook.json'),
  imagesDir: resolve(root, '../ios/FreshPantry/Resources/RecipeImages'),
  rejectsPath: resolve(root, 'data/rejects.json'),
  sourcesPath: resolve(root, 'data/sources.json'),
  attributionsPath: resolve(root, 'data/image-attributions.json'),
  videoAttributionsPath: resolve(root, 'data/video-attributions.json'),
  workDir: resolve(root, '.cache'),
  acquireImages: process.env.RECIPE_ACQUIRE_IMAGES === '1',
  model: recipeModel,
  // RECIPE_MODEL 以 @cf/ 开头 → 走 CloudflareEnricher(直连 OpenAI 兼容端点),否则走 flue。
  useCloudflare: recipeModel.startsWith('@cf/'),
  cloudflare: {
    baseUrl: process.env.CLOUDFLARE_AI_BASE_URL ?? CF_DEFAULT_BASE,
    apiKey: process.env.CLOUDFLARE_AI_API_KEY ?? '',
    maxTokens: Number(process.env.RECIPE_MAX_TOKENS ?? '4096'),
  },
  thinkingLevel: (process.env.RECIPE_THINKING ?? 'xhigh') as 'off' | 'minimal' | 'low' | 'medium' | 'high' | 'xhigh',
  concurrency: Number(process.env.RECIPE_CONCURRENCY ?? '6'),
};
