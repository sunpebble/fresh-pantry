import type { Lang, RecipeOverlay } from '../i18n/schema';

type RecipeI18nRow = {
  recipeId: string;
  lang: Lang;
  overlay: RecipeOverlay;
};

function lit(s: string): string {
  return `'${s.replace(/'/g, "''")}'`;
}

function jsonbLit(value: unknown): string {
  return `${lit(JSON.stringify(value))}::jsonb`;
}

const COLUMNS = [
  'recipe_id', 'lang', 'name', 'category', 'description',
  'ingredients', 'steps', 'tags',
] as const;

export const RECIPE_I18N_DDL = `create table if not exists public.recipe_i18n (
  recipe_id text not null references public.recipes(id) on delete cascade,
  lang text not null,
  name text not null,
  category text not null default '',
  description text not null default '',
  ingredients jsonb not null default '[]'::jsonb,
  steps jsonb not null default '[]'::jsonb,
  tags jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (recipe_id, lang),
  constraint recipe_i18n_lang_check check (lang in ('en', 'ja', 'fr'))
);

alter table public.recipe_i18n enable row level security;
drop policy if exists "recipe_i18n_public_read" on public.recipe_i18n;
create policy "recipe_i18n_public_read" on public.recipe_i18n
  for select to anon, authenticated using (true);
grant select on public.recipe_i18n to anon, authenticated;`;

function valuesRow(row: RecipeI18nRow): string {
  const overlay = row.overlay;
  return `  (${lit(row.recipeId)}, ${lit(row.lang)}, ${lit(overlay.name)}, `
    + `${lit(overlay.category)}, ${lit(overlay.description)}, `
    + `${jsonbLit(overlay.ingredients)}, ${jsonbLit(overlay.steps)}, ${jsonbLit(overlay.tags)})`;
}

export function overlaysToRows(lang: Lang, overlays: Record<string, RecipeOverlay>): RecipeI18nRow[] {
  return Object.entries(overlays)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([recipeId, overlay]) => ({ recipeId, lang, overlay }));
}

export function recipeI18nToSyncSQL(rows: RecipeI18nRow[]): string {
  if (!rows.length) return '';
  const values = rows.map(valuesRow).join(',\n');
  const updates = COLUMNS.filter((c) => c !== 'recipe_id' && c !== 'lang')
    .map((c) => `  ${c} = excluded.${c}`)
    .concat('  updated_at = now()')
    .join(',\n');
  return `with seed (${COLUMNS.join(', ')}) as (values\n${values}\n),\n`
    + `upserted as (\n`
    + `  insert into public.recipe_i18n (${COLUMNS.join(', ')})\n`
    + `  select ${COLUMNS.join(', ')} from seed\n`
    + `  on conflict (recipe_id, lang) do update set\n${updates}\n`
    + `  returning recipe_id, lang\n`
    + `)\n`
    + `delete from public.recipe_i18n t\n`
    + `where t.lang in ('en', 'ja', 'fr')\n`
    + `  and t.recipe_id like 'howtocook:%'\n`
    + `  and not exists (select 1 from seed s where s.recipe_id = t.recipe_id and s.lang = t.lang);`;
}

export function recipeI18nToSeedSQL(rows: RecipeI18nRow[]): string {
  return `${RECIPE_I18N_DDL}\n\n${recipeI18nToSyncSQL(rows)}\n`;
}
