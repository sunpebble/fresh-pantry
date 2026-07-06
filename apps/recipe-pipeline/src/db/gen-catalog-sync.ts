import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { CleanRecipe } from '../clean/schema';
import { LANGS, type RecipeOverlay } from '../i18n/schema';
import { recipesToPruneSQL, recipesToSeedSQL, type CatalogRecipe } from './recipe-sql';
import { overlaysToRows, recipeI18nToSeedSQL } from './recipe-i18n-sql';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../../../..');
const resourcesDir = resolve(repoRoot, 'apps/ios/FreshPantry/Resources');
const outFile = process.argv[2] ? resolve(repoRoot, process.argv[2]) : null;
if (!outFile) {
  throw new Error('usage: npx tsx src/db/gen-catalog-sync.ts supabase/migrations/<file>.sql');
}

const recipes = (JSON.parse(readFileSync(resolve(resourcesDir, 'howtocook.json'), 'utf8')) as CleanRecipe[])
  .filter((recipe) => !recipe.deletedAt) as CatalogRecipe[];
const i18nRows = LANGS.flatMap((lang) => {
  const path = resolve(resourcesDir, `howtocook.i18n.${lang}.json`);
  const overlays = JSON.parse(readFileSync(path, 'utf8')) as Record<string, RecipeOverlay>;
  return overlaysToRows(lang, overlays);
});

const sql = [
  recipesToSeedSQL(recipes),
  recipesToPruneSQL(recipes),
  recipeI18nToSeedSQL(i18nRows),
].filter(Boolean).join('\n\n');

writeFileSync(outFile, sql, 'utf8');
console.log(`gen:catalog-sync -> ${recipes.length} recipes, ${i18nRows.length} i18n rows -> ${outFile}`);
