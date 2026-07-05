import * as v from 'valibot';

export const LANGS = ['en', 'ja', 'fr'] as const;
export type Lang = (typeof LANGS)[number];

/** 按 id 覆盖到食谱上的译文层;结构字段(数量/时长/图片)不在其中。 */
export const RecipeOverlaySchema = v.object({
  name: v.pipe(v.string(), v.minLength(1)),
  description: v.string(),
  category: v.pipe(v.string(), v.minLength(1)),
  steps: v.array(v.string()),
  tags: v.array(v.string()),
  ingredients: v.array(v.object({
    name: v.pipe(v.string(), v.minLength(1)),
    unit: v.optional(v.string()),
    note: v.optional(v.string()),
  })),
});

export type RecipeOverlay = v.InferOutput<typeof RecipeOverlaySchema>;

/** .cache/i18n-<lang>.json:id → 内容 hash + 上次译文。 */
export type TranslationCache = Record<string, { hash: string; overlay: RecipeOverlay }>;
