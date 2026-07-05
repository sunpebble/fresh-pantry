import { createHash } from 'node:crypto';
import * as v from 'valibot';
import { toJsonSchema } from '@valibot/to-json-schema';
import type { CleanRecipe } from '../clean/schema';
import { extractJson } from '../clean/cloudflare-enricher';
import { mapWithConcurrency } from '../util/pool';
import { CATEGORY_I18N } from './category-map';
import { RecipeOverlaySchema, type Lang, type RecipeOverlay, type TranslationCache } from './schema';

export const OVERLAY_JSON_SCHEMA = toJsonSchema(RecipeOverlaySchema, { errorMode: 'ignore' });

const LANG_NAMES: Record<Lang, string> = {
  en: 'English',
  ja: 'Japanese (日本語)',
  fr: 'French (français)',
};

/** 只对可译字段取 hash:结构字段变化(图片/时长)不触发重译。 */
export function translatableHash(r: CleanRecipe): string {
  const subset = {
    name: r.name,
    description: r.description,
    category: r.category,
    steps: r.steps,
    tags: r.tags,
    ingredients: r.ingredients.map(({ name, unit, note }) => ({ name, unit, note })),
  };
  return createHash('sha256').update(JSON.stringify(subset)).digest('hex');
}

export function buildTranslatePrompt(r: CleanRecipe, lang: Lang): string {
  return [
    `Translate this Chinese home-cooking recipe into ${LANG_NAMES[lang]}.`,
    'Rules:',
    '- Keep the tone plain and friendly, like a well-kept kitchen note.',
    '- steps must have EXACTLY the same number of items as the source, same order.',
    '- ingredients must have EXACTLY the same number of items as the source, same order; translate name/unit/note only.',
    '- Use natural culinary units for the target language.',
    '- Do not add, drop, or merge content. Numbers and quantities stay as-is.',
    '- Return ONLY the JSON object.',
    '',
    JSON.stringify({
      name: r.name,
      description: r.description,
      category: r.category,
      steps: r.steps,
      tags: r.tags,
      ingredients: r.ingredients.map(({ name, unit, note }) => ({ name, unit, note })),
    }),
  ].join('\n');
}

export interface TranslateDeps {
  chat: (
    messages: { role: string; content: string }[],
    schemaName: string,
    jsonSchema: unknown,
  ) => Promise<string>;
  cache: TranslationCache;
  concurrency?: number;
  log?: (msg: string) => void;
}

export async function translateCorpus(
  recipes: CleanRecipe[],
  lang: Lang,
  deps: TranslateDeps,
): Promise<{
  overlays: Record<string, RecipeOverlay>;
  cache: TranslationCache;
  failures: { id: string; error: string }[];
}> {
  const log = deps.log ?? (() => {});
  const overlays: Record<string, RecipeOverlay> = {};
  const nextCache: TranslationCache = {};
  const failures: { id: string; error: string }[] = [];

  await mapWithConcurrency(recipes, deps.concurrency ?? 6, async (recipe) => {
    const hash = translatableHash(recipe);
    const hit = deps.cache[recipe.id];
    if (hit && hit.hash === hash) {
      overlays[recipe.id] = hit.overlay;
      nextCache[recipe.id] = hit;
      return;
    }

    try {
      const raw = await deps.chat(
        [{ role: 'user', content: buildTranslatePrompt(recipe, lang) }],
        'recipe_overlay',
        OVERLAY_JSON_SCHEMA,
      );
      const parsed = v.parse(RecipeOverlaySchema, JSON.parse(extractJson(raw)));
      if (parsed.steps.length !== recipe.steps.length) {
        throw new Error(`steps 数量不齐: ${parsed.steps.length}≠${recipe.steps.length}`);
      }
      if (parsed.ingredients.length !== recipe.ingredients.length) {
        throw new Error(`ingredients 数量不齐: ${parsed.ingredients.length}≠${recipe.ingredients.length}`);
      }
      const overlay: RecipeOverlay = {
        ...parsed,
        category: CATEGORY_I18N[recipe.category][lang],
      };
      overlays[recipe.id] = overlay;
      nextCache[recipe.id] = { hash, overlay };
      log(`translated ${recipe.id} → ${lang}`);
    } catch (error) {
      failures.push({
        id: recipe.id,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  });

  return { overlays, cache: nextCache, failures };
}
