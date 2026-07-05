import { readFile, rm } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { CleanRecipe } from '../clean/schema';
import { createCfChat } from '../clean/cloudflare-enricher';
import { LANGS, type Lang, type TranslationCache } from '../i18n/schema';
import { translateCorpus } from '../i18n/translate';
import { atomicWriteJson } from '../util/atomic-write';

const pipelineRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');

async function loadDotEnv(path: string): Promise<void> {
  const content = await readFile(path, 'utf8').catch(() => '');
  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#') || !line.includes('=')) continue;
    const [key, ...rest] = line.split('=');
    if (process.env[key] != null) continue;
    let value = rest.join('=').trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    process.env[key] = value;
  }
}

await loadDotEnv(resolve(pipelineRoot, '.env'));
const { config } = await import('../config');

function selectedLangs(): Lang[] {
  const raw = process.env.RECIPE_I18N_LANGS;
  if (!raw) return [...LANGS];
  const langs = raw.split(',').map((value) => value.trim()).filter(Boolean);
  const unsupported = langs.filter((lang) => !(LANGS as readonly string[]).includes(lang));
  if (unsupported.length > 0) {
    throw new Error(`RECIPE_I18N_LANGS 包含不支持的语言: ${unsupported.join(', ')}`);
  }
  return langs as Lang[];
}

const recipes = JSON.parse(await readFile(config.existingPath, 'utf8')) as CleanRecipe[];
const limit = Number(process.env.RECIPE_I18N_LIMIT ?? '0');
const live = recipes
  .filter((recipe) => !recipe.deletedAt)
  .slice(0, Number.isFinite(limit) && limit > 0 ? limit : undefined);
const chatBaseUrl = config.cloudflare.baseUrl || process.env.OPENAI_BASE_URL || '';
const chatApiKey = config.cloudflare.apiKey || process.env.OPENAI_API_KEY || '';
if (!chatBaseUrl || !chatApiKey) {
  throw new Error('需要设置 CLOUDFLARE_AI_BASE_URL/CLOUDFLARE_AI_API_KEY 或 OPENAI_BASE_URL/OPENAI_API_KEY');
}
const chat = createCfChat({
  baseUrl: chatBaseUrl,
  apiKey: chatApiKey,
  model: config.model,
  responseFormat: chatBaseUrl.includes('deepseek.com') ? 'json_object' : 'json_schema',
  maxTokens: config.cloudflare.maxTokens,
  log: (message) => console.log(`[i18n:cf] ${message}`),
});

const allFailures: { lang: string; id: string; error: string }[] = [];

for (const lang of selectedLangs()) {
  const cachePath = resolve(config.workDir, `i18n-${lang}.json`);
  const cache = await readFile(cachePath, 'utf8')
    .then((content) => JSON.parse(content) as TranslationCache)
    .catch(() => ({} as TranslationCache));

  const { overlays, cache: nextCache, failures } = await translateCorpus(live, lang, {
    chat,
    cache,
    concurrency: config.concurrency,
    log: (message) => console.log(`[i18n] ${message}`),
  });

  await atomicWriteJson(resolve(dirname(config.outPath), `howtocook.i18n.${lang}.json`), overlays);
  await atomicWriteJson(cachePath, nextCache);
  allFailures.push(...failures.map((failure) => ({ lang, ...failure })));
  console.log(`[i18n] ${lang}: ${Object.keys(overlays).length}/${live.length} 就绪, ${failures.length} 失败`);
}

const i18nRejectsPath = resolve(config.rejectsPath, '../i18n-rejects.json');
if (allFailures.length > 0) {
  await atomicWriteJson(i18nRejectsPath, allFailures);
  console.log(`[i18n] ${allFailures.length} 条失败已记入 data/i18n-rejects.json(app 内回退中文)`);
} else {
  await rm(i18nRejectsPath, { force: true });
}
