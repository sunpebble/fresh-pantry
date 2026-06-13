import type { RawRecipe } from '../sources/types';
import { isTool } from '../parse/howtocook-parser';
import { normalizeIngredient } from './normalize';
import { CATEGORIES, type CleanRecipe, type Enrichment } from './schema';

export interface RecipeEnricher {
  enrich(raw: RawRecipe): Promise<Enrichment>;
}

export const RECIPE_CLEANER_INSTRUCTIONS = `你是中文家常菜谱清洗助手。把输入整理成结构化菜谱字段。规则:
- 分类必须取自:${CATEGORIES.join('、')}。
- 食材用量「只抽不猜」:仅当源文本(尤其「计算/总量」段)明确写了才填,源没写就省略对应字段,严禁估算或编造。
- 食材每个字段「按需出现」,绝不写空值/空字符串,能省则省:
  - name:食材名,必有,非空。
  - quantity:数字(JSON number,不是字符串!),如 200、7.5、0.5。中文数字转写成数字("两个"→2、"半根"→0.5);源没明确数量就省略该字段。
  - quantityMax:数字,仅【范围用量】出现(上界)。如源「6-15 克」→ quantity:6, quantityMax:15, unit:"克";非范围时省略。
  - unit:计量单位,如 "克"、"ml"、"只"、"瓣";没有就省略(绝不写空字符串)。
  - note:仅【模糊用量】(如 "适量"、"一小把"、"几滴"、"一小片")且无数字时出现,填清洗后的模糊词;有 quantity 时不要 note。note 里不含数字/公式/markdown。
- 严禁对用量做任何运算;公式里的「系数/比例/除数」都不是用量:
  - 乘式每份率(如 "300g * 份数"、"张数 * 10ml"):抽出带单位的每份量(300/克、10/ml)填 quantity+unit;若单位不明确(如 "份数 * 0.8")则留空 quantity。
  - 除式「变量 / 数字」(如 "张数 / 0.13"、"兔肉斤数 / 2"):斜杠后的数是除数系数、不是用量,一律留空 quantity。
  - 每份率「数字+单位 / 人数或份」(如 "1.5 只/三人"、"15 克/斤"、"2 根/三人"):斜杠前的数字+单位才是用量,填 quantity+unit(取斜杠前的量),不要因为有斜杠就留空。
  - 配比(如 "酱油 : 醋 : 油泼辣子 = 3 : 2 : 2"):冒号比例是配比系数、不是用量,一律留空 quantity(配比说明不要塞进任何字段)。
  - 加式(如 "7.5ml + 4ml * 份数"):单份量不明,留空 quantity。
  不要把公式原文塞进 quantity/unit/note 任何字段。
- 没有 amount 字段,不要输出 amount。
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
    raw.portionText ?? '(源未提供用量,各食材只留 name,不要给 quantity/unit/note)',
    raw.description ? `已有描述(沿用):${raw.description}` : `请补写一两句描述。`,
    `把每个食材名映射到用量(只从上面的计算段抽,抽不到就只留 name)。`,
    `⚠️ 用量「只抽不猜」:quantity(数字)/quantityMax(范围上界)/unit/note 只在源文本写了才填,字段按需出现、能省则省、绝不写空字符串,不要编造或猜测。`,
    `⚠️ 严禁运算:不乘份数/人数、不相加。公式里的系数不是用量——除式("张数 / 0.13"、"张数 / 2")的除数、配比("3 : 2 : 2")的比例数,一律留空 quantity;乘式每份率("X * 份数")抽带单位的每份量,单位不明则留空。不要把公式塞进任何字段。模糊量("适量"、"一小把")进 note。无 amount 字段。`,
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
    cookingMinutes: raw.sourceCookingMinutes ?? enr.cookingMinutes,
    description,
    // LLM 可能从「计算/总量」段把工具(手套/密封袋/打蛋器…)带进来,统一兜底剔除;
    // 三字段语义(quantity 纯数字)由 normalizeIngredient 确定性兜底
    ingredients: enr.ingredients.filter((i) => !isTool(i.name)).map(normalizeIngredient),
    steps,
    tags: uniq([category, ...enr.tags]),
    imageUrl: raw.imageUrl ?? null,
    remoteVersion: 0,
    clientUpdatedAt: null,
    deletedAt: null,
  };
}
