import { describe, it, expect } from 'vitest';
import { recipesToSeedSQL, recipesToUpsertSQL, RECIPES_DDL, type CatalogRecipe } from '../src/db/recipe-sql';

const recipe = (over: Partial<CatalogRecipe> = {}): CatalogRecipe => ({
  id: 'howtocook:vegetable_dish/凉拌黄瓜',
  name: '凉拌黄瓜',
  category: '素菜',
  difficulty: 1,
  cookingMinutes: 15,
  description: '清爽开胃。',
  ingredients: [
    { name: '黄瓜', quantity: 200, unit: '克' },
    { name: '盐', note: '适量' },
  ],
  steps: ['拍碎', '调味'],
  tags: ['素菜', '快手'],
  imageUrl: 'assets/recipes/images/howtocook_vegetable_凉拌黄瓜.jpg',
  videoUrl: null,
  ...over,
});

describe('recipesToSeedSQL', () => {
  it('DDL 幂等且匿名只读', () => {
    expect(RECIPES_DDL).toContain('create table if not exists public.recipes');
    expect(RECIPES_DDL).toContain('enable row level security');
    expect(RECIPES_DDL).toContain('for select to anon, authenticated');
    expect(RECIPES_DDL).toContain('grant select on public.recipes to anon, authenticated');
  });

  it('upsert:数字字段裸写、ingredients 走 jsonb、on conflict 更新', () => {
    const sql = recipesToUpsertSQL([recipe()]);
    expect(sql).toContain('insert into public.recipes');
    expect(sql).toContain('on conflict (id) do update set');
    expect(sql).toContain('1, 15,'); // difficulty, cooking_minutes 裸数字
    expect(sql).toContain('::jsonb');
    expect(sql).toContain('"quantity":200'); // 数字结构保留进 jsonb
    expect(sql).toContain('updated_at = now()');
  });

  it('imageUrl 空 → null;非空 → 字符串字面量', () => {
    expect(recipesToUpsertSQL([recipe({ imageUrl: null })])).toContain(', null)');
    expect(recipesToUpsertSQL([recipe()])).toContain("assets/recipes/images");
  });

  it("单引号转义防注入(名称含撇号不破 SQL)", () => {
    const sql = recipesToUpsertSQL([recipe({ name: "O'Brien 沙拉", id: 'x' })]);
    expect(sql).toContain("'O''Brien 沙拉'");
  });

  it('空列表 → 空 upsert;完整种子仍含 DDL', () => {
    expect(recipesToUpsertSQL([])).toBe('');
    const seed = recipesToSeedSQL([]);
    expect(seed).toContain('create table if not exists');
  });

  it('video_url 入列:DDL 含 alter 升级,空 → null,有值 → 字面量', () => {
    expect(RECIPES_DDL).toContain('video_url text');
    expect(RECIPES_DDL).toContain('add column if not exists video_url text');
    expect(recipesToUpsertSQL([recipe({ videoUrl: null })])).toContain(', null)');
    expect(recipesToUpsertSQL([recipe({ videoUrl: 'https://b23.tv/x' })])).toContain("'https://b23.tv/x'");
    expect(recipesToUpsertSQL([recipe()])).toContain('video_url');
  });

  it('多条 → 多行 VALUES', () => {
    const sql = recipesToUpsertSQL([recipe({ id: 'a' }), recipe({ id: 'b' })]);
    expect(sql).toContain("'a'");
    expect(sql).toContain("'b'");
    expect((sql.match(/::jsonb/g) ?? []).length).toBe(6); // 2 条 × (ingredients+steps+tags),营养/时长缺省 → null
  });

  it('nutrition / step_durations 入列:DDL 含列 + 幂等 alter,缺省 → null,有值 → jsonb', () => {
    expect(RECIPES_DDL).toContain('nutrition jsonb');
    expect(RECIPES_DDL).toContain('step_durations jsonb');
    expect(RECIPES_DDL).toContain('add column if not exists nutrition jsonb');
    expect(RECIPES_DDL).toContain('add column if not exists step_durations jsonb');
    // 列名进入 insert 列清单
    expect(recipesToUpsertSQL([recipe()])).toContain('nutrition, step_durations');
    // 老菜缺这俩 → null(不增 ::jsonb)
    expect((recipesToUpsertSQL([recipe()]).match(/::jsonb/g) ?? []).length).toBe(3);
    // 有值 → jsonb 字面量
    const withData = recipesToUpsertSQL([recipe({ nutrition: { energyKcal: 120 }, stepDurations: [null, 60] })]);
    expect(withData).toContain('"energyKcal":120');
    expect(withData).toContain('[null,60]');
    expect((withData.match(/::jsonb/g) ?? []).length).toBe(5); // ingredients+steps+tags+nutrition+step_durations
  });
});
