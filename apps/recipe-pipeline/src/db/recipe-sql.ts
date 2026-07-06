import type { CleanRecipe } from '../clean/schema';

/**
 * 把清洗后的菜谱目录生成「可重复应用」的 Supabase 种子迁移 SQL。
 *
 * 设计(与用户敲定):howtocook 是全局共享目录(人人一样),不走按家庭 RLS;
 * `public.recipes` 表匿名只读、仅服务端/迁移可写。iOS 以 DB 为权威源 + 本地缓存,
 * 内置 json 作离线兜底。ingredients/steps/tags 存 jsonb(沿用无损数字结构)。
 *
 * 幂等:`create table if not exists` + `insert ... on conflict (id) do update`,
 * 重跑管线后重新生成、重新应用都安全(既灌新、又更新旧)。
 */

/** 取菜谱目录真正需要的字段(剔除同步元数据 remoteVersion/clientUpdatedAt/deletedAt)。 */
export type CatalogRecipe = Pick<
  CleanRecipe,
  'id' | 'name' | 'category' | 'difficulty' | 'cookingMinutes' | 'description'
  | 'ingredients' | 'steps' | 'tags' | 'imageUrl' | 'videoUrl' | 'nutrition' | 'stepDurations'
>;

/** SQL 字符串字面量转义:单引号翻倍。 */
function lit(s: string): string {
  return `'${s.replace(/'/g, "''")}'`;
}

/** jsonb 字面量:JSON.stringify 后按字符串字面量转义,带 ::jsonb 强转。 */
function jsonbLit(value: unknown): string {
  return `${lit(JSON.stringify(value))}::jsonb`;
}

/** 可空文本:空/缺失 → null,否则字符串字面量。 */
function nullableText(s: string | null | undefined): string {
  return s ? lit(s) : 'null';
}

/** 可空 jsonb:undefined/null → null,否则 jsonb 字面量(营养/步骤时长按需出现)。 */
function nullableJsonb(value: unknown): string {
  return value == null ? 'null' : jsonbLit(value);
}

const COLUMNS = [
  'id', 'name', 'category', 'difficulty', 'cooking_minutes',
  'description', 'ingredients', 'steps', 'tags', 'image_url', 'video_url',
  'nutrition', 'step_durations',
] as const;

export const RECIPES_DDL = `create table if not exists public.recipes (
  id text primary key,
  name text not null,
  category text not null default '',
  difficulty integer not null default 0,
  cooking_minutes integer not null default 30,
  description text not null default '',
  ingredients jsonb not null default '[]'::jsonb,
  steps jsonb not null default '[]'::jsonb,
  tags jsonb not null default '[]'::jsonb,
  image_url text,
  video_url text,
  nutrition jsonb,
  step_durations jsonb,
  updated_at timestamptz not null default now()
);

-- 老库幂等升级:新增列(已存在则无操作)
alter table public.recipes add column if not exists video_url text;
alter table public.recipes add column if not exists nutrition jsonb;
alter table public.recipes add column if not exists step_durations jsonb;

alter table public.recipes enable row level security;
-- 共享菜谱目录:匿名 + 已登录均可只读;无写策略(仅 service_role/迁移可写)
drop policy if exists "recipes_public_read" on public.recipes;
create policy "recipes_public_read" on public.recipes
  for select to anon, authenticated using (true);
grant select on public.recipes to anon, authenticated;`;

function valuesRow(r: CatalogRecipe): string {
  return `  (${lit(r.id)}, ${lit(r.name)}, ${lit(r.category)}, ${r.difficulty}, `
    + `${r.cookingMinutes}, ${lit(r.description)}, ${jsonbLit(r.ingredients)}, `
    + `${jsonbLit(r.steps)}, ${jsonbLit(r.tags)}, ${nullableText(r.imageUrl)}, `
    + `${nullableText(r.videoUrl)}, ${nullableJsonb(r.nutrition)}, ${nullableJsonb(r.stepDurations)})`;
}

/** 生成 upsert 语句(多行 VALUES + on conflict 更新)。空列表返回空串。 */
export function recipesToUpsertSQL(recipes: CatalogRecipe[]): string {
  if (!recipes.length) return '';
  const rows = recipes.map(valuesRow).join(',\n');
  const updates = COLUMNS.filter((c) => c !== 'id')
    .map((c) => `  ${c} = excluded.${c}`)
    .concat('  updated_at = now()')
    .join(',\n');
  return `insert into public.recipes (${COLUMNS.join(', ')}) values\n${rows}\n`
    + `on conflict (id) do update set\n${updates};`;
}

export function recipesToPruneSQL(recipes: Pick<CatalogRecipe, 'id'>[], prefix = 'howtocook:'): string {
  const ids = recipes.map((r) => r.id).filter((id) => id.startsWith(prefix));
  if (!ids.length) return '';
  return `delete from public.recipes\n`
    + `where id like ${lit(`${prefix}%`)}\n`
    + `  and id not in (${ids.map(lit).join(', ')});`;
}

/**
 * 完整种子迁移体:建表 + RLS + upsert。可整体交给 Supabase apply_migration,
 * 或写入 supabase/migrations/<version>_recipes_catalog.sql。
 */
export function recipesToSeedSQL(recipes: CatalogRecipe[]): string {
  return `${RECIPES_DDL}\n\n${recipesToUpsertSQL(recipes)}\n`;
}
