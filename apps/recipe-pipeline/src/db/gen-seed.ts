import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { recipesToSeedSQL, type CatalogRecipe } from './recipe-sql';
import { config } from '../config';

/**
 * 从已清洗的 howtocook.json 生成 Supabase 种子迁移文件(`npm run gen:seed`)。
 * 管线重跑后再跑本脚本即可重新生成迁移;幂等 upsert,重新应用安全。
 * 用 tsx 直跑(非 flue bundle),故 import.meta.url 是真实文件路径。
 */
const MIGRATION = '20260613120000_recipes_catalog.sql';
const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../../../..');
const outFile = resolve(repoRoot, 'supabase/migrations', MIGRATION);

const recipes = JSON.parse(readFileSync(config.outPath, 'utf8')) as CatalogRecipe[];
const sql = recipesToSeedSQL(recipes);
writeFileSync(outFile, sql, 'utf8');
console.log(`gen:seed → ${recipes.length} recipes, ${sql.length} bytes → ${outFile}`);
