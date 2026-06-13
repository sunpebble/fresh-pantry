import * as v from 'valibot';

export const CATEGORIES = [
  '主食', '半成品', '早餐', '水产', '汤羹', '甜品', '素菜', '荤菜', '酱料', '饮品',
] as const;

export type Category = (typeof CATEGORIES)[number];

/**
 * 食材「无损数字 schema」:字段全部按需出现,绝不写空值/空字符串,能省则省。
 * - quantity/quantityMax 是 JSON number(不是字符串);范围用量 quantity=下界、quantityMax=上界。
 * - unit 为空省略;模糊量(无数字)清洗后进 note;完全无量只留 name。
 * - 不存在 amount 字段(展示文本改由 UI 计算属性派生)。
 */
export const IngredientSchema = v.object({
  name: v.pipe(v.string(), v.minLength(1)),
  quantity: v.optional(v.number()),
  quantityMax: v.optional(v.number()),
  unit: v.optional(v.string()),
  note: v.optional(v.string()),
});

export type Ingredient = v.InferOutput<typeof IngredientSchema>;

export const CleanRecipeSchema = v.object({
  id: v.pipe(v.string(), v.minLength(1)),
  name: v.pipe(v.string(), v.minLength(1)),
  category: v.picklist(CATEGORIES),
  difficulty: v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(5)),
  cookingMinutes: v.pipe(v.number(), v.integer(), v.minValue(1)),
  description: v.string(),
  ingredients: v.array(IngredientSchema),
  steps: v.array(v.string()),
  tags: v.array(v.string()),
  imageUrl: v.nullable(v.string()),
  remoteVersion: v.pipe(v.number(), v.integer()),
  clientUpdatedAt: v.nullable(v.string()),
  deletedAt: v.nullable(v.string()),
});

export type CleanRecipe = v.InferOutput<typeof CleanRecipeSchema>;

export const EnrichmentSchema = v.object({
  category: v.picklist(CATEGORIES),
  difficulty: v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(5)),
  cookingMinutes: v.pipe(v.number(), v.integer(), v.minValue(1)),
  description: v.string(),
  ingredients: v.array(IngredientSchema),
  steps: v.array(v.string()),
  tags: v.array(v.string()),
});

export type Enrichment = v.InferOutput<typeof EnrichmentSchema>;
