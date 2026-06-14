-- 菜谱目录(public.recipes)加「每份营养」+「每步时长」列。
--
-- 对齐懒饭 App 的「内容确定性」:nutrition 为每份营养估算(energyKcal/protein/carbs/fat),
-- step_durations 为与 steps 索引对齐的每步时长(秒,某步无时长为 null)。两列均由
-- recipe-pipeline 的 Cloudflare Kimi enrich 产出后随目录灌入。
--
-- additive + 幂等:add column if not exists,空列对现有匿名只读策略无影响;iOS
-- RemoteRecipeCatalog 以列别名直解码 Recipe(nutrition→NutritionFacts、
-- step_durations→[Int?]),老行值为 null 时解码为 nil,营养卡/倒计时自动隐藏。
alter table public.recipes add column if not exists nutrition jsonb;
alter table public.recipes add column if not exists step_durations jsonb;
