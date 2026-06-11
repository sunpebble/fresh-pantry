import type { RawRecipe } from '../sources/types';
import { CATEGORIES, type CleanRecipe, type Enrichment } from './schema';

export interface RecipeEnricher {
  enrich(raw: RawRecipe): Promise<Enrichment>;
}

export const RECIPE_CLEANER_INSTRUCTIONS = `你是中文家常菜谱清洗助手。把输入整理成结构化菜谱字段。规则:
- 分类必须取自:${CATEGORIES.join('、')}。
- 食材用量「只抽不猜」:quantity/unit/amount 仅当源文本(尤其「计算/总量」段)明确写了才填,源没写就一律留空字符串,严禁估算或编造。
- difficulty 取 1-5 整数;cookingMinutes 取正整数(可据步骤数与描述合理估算时长)。
- description:若已提供则原样沿用,否则写一两句简介。
- 只返回符合 schema 的结构化结果。`;

export function buildEnrichPrompt(raw: RawRecipe): string {
  if (raw.rawText) {
    return [
      `从以下网页正文抽取一道中文菜谱。名称参考:「${raw.name}」。`,
      `严格遵守「只抽不猜」:用量只在正文写明时才填。`,
      `分类必须取自:${CATEGORIES.join('、')}。`,
      `--- 网页正文 ---`,
      raw.rawText,
    ].join('\n');
  }
  return [
    `清洗下面这道菜谱「${raw.name}」。`,
    raw.sourceCategory ? `分类:${raw.sourceCategory}(沿用)。` : `请归类到 10 个分类之一。`,
    raw.sourceDifficulty ? `难度:${raw.sourceDifficulty}(沿用)。` : ``,
    `食材名:${raw.rawIngredients.join('、') || '(无)'}`,
    `步骤:`,
    ...raw.steps.map((s, i) => `${i + 1}. ${s}`),
    `--- 计算/总量段(用量来源,只抽不猜) ---`,
    raw.portionText ?? '(源未提供用量,ingredients 的 quantity/unit/amount 全部留空字符串)',
    raw.description ? `已有描述(沿用):${raw.description}` : `请补写一两句描述。`,
    `把每个食材名映射到用量(只从上面的计算段抽,抽不到就留空)。`,
    `⚠️ 用量「只抽不猜」:quantity/unit/amount 只在源文本写了才填,不要编造或猜测。`,
  ].filter(Boolean).join('\n');
}

function uniq(xs: string[]): string[] {
  return [...new Set(xs.filter(Boolean))];
}

export function assembleRecipe(raw: RawRecipe, enr: Enrichment): CleanRecipe {
  const category =
    raw.sourceCategory && (CATEGORIES as readonly string[]).includes(raw.sourceCategory)
      ? (raw.sourceCategory as CleanRecipe['category'])
      : enr.category;
  const difficulty = raw.sourceDifficulty ?? enr.difficulty;
  const description = raw.description?.trim() || enr.description;
  const steps = raw.steps.length ? raw.steps : enr.steps;
  return {
    id: raw.id,
    name: raw.name,
    category,
    difficulty,
    cookingMinutes: enr.cookingMinutes,
    description,
    ingredients: enr.ingredients,
    steps,
    tags: uniq([category, ...enr.tags]),
    imageUrl: raw.imageUrl ?? null,
    remoteVersion: 0,
    clientUpdatedAt: null,
    deletedAt: null,
  };
}
