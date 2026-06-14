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

/** 每份营养(LLM 估算,UI 展示标注「约」)。字段全部可选,能估则填。 */
export const NutritionSchema = v.object({
  energyKcal: v.optional(v.number()),
  protein: v.optional(v.number()),
  carbs: v.optional(v.number()),
  fat: v.optional(v.number()),
});

export type Nutrition = v.InferOutput<typeof NutritionSchema>;

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
  // 老数据无此键:optional+default=null 兼容缺键(imageUrl 历史上必有该键所以纯 nullable 即可)
  videoUrl: v.optional(v.nullable(v.string()), null),
  // 每份营养(LLM 估算)+ 每步时长秒(与 steps 索引对齐,某步无时长为 null);老数据无键 → optional 兼容
  nutrition: v.optional(NutritionSchema),
  stepDurations: v.optional(v.array(v.nullable(v.number()))),
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
  // LLM 额外产出:每份营养估算 + 每步时长(与步骤等长,无明确时长填 null)
  nutrition: v.optional(NutritionSchema),
  stepDurations: v.optional(v.array(v.nullable(v.number()))),
});

export type Enrichment = v.InferOutput<typeof EnrichmentSchema>;
