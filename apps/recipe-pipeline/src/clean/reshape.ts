import { normalizeIngredient, type IngredientLike } from './normalize';
import type { CleanRecipe } from './schema';

/**
 * 旧形态 json → 无损数字结构的数据迁移。
 *
 * 旧形态每条食材是 {name, quantity:string, unit:string, amount:string};本函数把每条食材
 * 经 normalizeIngredient 重新派生为新结构 {name, quantity?, quantityMax?, unit?, note?},
 * 复用管线既有的清洗逻辑(不另写一份转换),其余菜谱字段(id/category/imageUrl/
 * remoteVersion/clientUpdatedAt/deletedAt/…)原样保留。
 */
export function reshapeLegacyRecipes(old: unknown[]): CleanRecipe[] {
  return old.map((recipe) => {
    const r = recipe as Record<string, unknown>;
    const rawIngredients = Array.isArray(r.ingredients) ? r.ingredients : [];
    const ingredients = rawIngredients.map((ing) =>
      normalizeIngredient(ing as IngredientLike),
    );
    return { ...r, ingredients } as CleanRecipe;
  });
}
