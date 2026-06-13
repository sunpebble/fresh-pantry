import type { Ingredient } from './schema';

/**
 * 「LLM/遗留字符串 → 无损数字结构」转换边界。
 *
 * 输入 `IngredientLike` 仍是字符串三字段(quantity/unit/amount):
 * - LLM 原始输出会被 valibot 强成新结构,但历史 prompt/迁移旧 json 走的都是字符串,
 *   故此函数统一接受字符串输入,做确定性转换。
 *
 * 输出新结构 `{name, quantity?, quantityMax?, unit?, note?}`(参见 IngredientSchema):
 * - 纯数字 "200" → quantity:200(number)。中文数字转写(半→0.5, 两→2…)成 number。
 * - 范围 "6-15"/"5g-10g"/"5~10" → quantity:下界, quantityMax:上界。
 * - 模糊量(无数字,如「适量」「一小把」「几滴」)→ note:清洗后的模糊词(去 markdown/纯数字/公式),
 *   不设 quantity/unit。
 * - 完全无量 → 只留 name。
 * - 公式净化:乘式(星号 或 ×、份数、N人)抽单一明确数字进 quantity+unit;加式(X+Y)单份量不明 → 无量。
 * - unit 为空一律省略;绝不产出空字符串或 amount 字段。
 */

/**
 * 转换输入:既容纳遗留/LLM 的「字符串三字段」(quantity/unit/amount 都是 string),
 * 也容纳已是新结构的对象(quantity/quantityMax 是 number)。两路都收敛到无损数字结构。
 */
export interface IngredientLike {
  name: string;
  quantity?: string | number;
  quantityMax?: number;
  unit?: string;
  amount?: string;
  note?: string;
}

const CN_NUM: Record<string, string> = {
  半: '0.5', 一: '1', 两: '2', 二: '2', 三: '3', 四: '4',
  五: '5', 六: '6', 七: '7', 八: '8', 九: '9', 十: '10',
};
// 范围两端可夹单位字符,如 "5g-10g" → 5-10
const RANGE_RE = /(\d+(?:\.\d+)?)[^\d-~～至]*[-~～至]\s*(\d+(?:\.\d+)?)/;
const SINGLE_RE = /(\d+(?:\.\d+)?)/;

// 源「计算」段的公式标记:乘式(每份量可重组)与加式(单份量不明,只能丢量)
const FORMULA_MUL_RE = /[*×]|份数|人份|\d+\s*人/;
const FORMULA_ADD_RE = /\+/;
// 除式系数(X / N)与配比(a:b:c)里的数字都不是用量;带变量词时一律判公式 → 丢量。
// 加变量词约束以免误伤分数("1/4 个")——分数无 张数/份数 等变量。
const FORMULA_VAR_RE = /张数|份数|人份|数量|体积|斤数|根据|比例|配比|倍/;
function isDivisionOrRatio(text: string): boolean {
  if (!text) return false;
  // 三段及以上配比(a:b:c)本身即强配比信号,无需变量词
  if (/\d\s*[:：]\s*\d\s*[:：]\s*\d/.test(text)) return true;
  // 除式 / 两段比例:需配合变量词,避免误伤分数("1/4")、时间("3:20")
  const hasDivOrRatio = /[/÷／]/.test(text) || /\d\s*[:：]\s*\d/.test(text);
  return hasDivOrRatio && FORMULA_VAR_RE.test(text);
}
// note 清洗:剔除 markdown 残留与公式标记
const MD_RESIDUE_RE = /!?\[[^\]]*\]\([^)]*\)|[*_`#]/g;

/** 把 "6"/"6-15"/"5g-10g"/"0.9～1升" 解析成下界/上界数字;无明确数字返回 null。 */
function parseQuantityString(text: string): { quantity: number; quantityMax?: number } | null {
  const cnChars = text.match(/[半一两二三四五六七八九十]/g) ?? [];
  let candidate = text;
  if (!/\d/.test(text)) {
    // 组合中文数字(两个以上,如「十五」)有歧义,放弃
    if (cnChars.length !== 1) return null;
    candidate = text.replace(/[半一两二三四五六七八九十]/, (c) => CN_NUM[c]);
  }
  const range = candidate.match(RANGE_RE);
  if (range) {
    const lo = Number(range[1]);
    const hi = Number(range[2]);
    return hi > lo ? { quantity: lo, quantityMax: hi } : { quantity: lo };
  }
  const single = candidate.match(SINGLE_RE);
  return single ? { quantity: Number(single[1]) } : null;
}

/** 清洗模糊词:去 markdown/公式标记并 trim;只剩纯数字/空 → 无效(返回空)。 */
function cleanNote(text: string): string {
  const cleaned = text.replace(MD_RESIDUE_RE, '').trim();
  if (!cleaned) return '';
  if (FORMULA_MUL_RE.test(cleaned) || FORMULA_ADD_RE.test(cleaned)) return '';
  if (/^\d+(\.\d+)?$/.test(cleaned)) return '';
  return cleaned;
}

export function normalizeIngredient(i: IngredientLike): Ingredient {
  const name = i.name;
  const u = (i.unit ?? '').trim();
  const a = (i.amount ?? '').trim();
  const out: Ingredient = { name };
  const setUnit = () => { if (u) out.unit = u; };

  // 已是新结构(quantity 是 number):直接派生,只做字段净化(空 unit 省略、空 note 省略)
  if (typeof i.quantity === 'number') {
    out.quantity = i.quantity;
    if (typeof i.quantityMax === 'number' && i.quantityMax > i.quantity) {
      out.quantityMax = i.quantityMax;
    }
    setUnit();
    return out;
  }
  // 无 quantity 但已带 note(新结构的模糊量):清洗后保留
  if (i.quantity === undefined && i.note !== undefined) {
    const fuzzy = cleanNote(i.note);
    if (fuzzy) out.note = fuzzy;
    return out;
  }

  const q = (i.quantity ?? '').trim();

  // 加式公式(7.5 ml + 4 ml * 份数)单份量不明 → 丢量,也不进 note
  if (FORMULA_ADD_RE.test(q) || FORMULA_ADD_RE.test(a)) {
    return out;
  }
  // 除式("张数 / 0.13")/配比("3 : 2 : 2")公式 → 系数非用量,丢量(防 LLM 把公式文本带进字段)
  if (isDivisionOrRatio(q) || isDivisionOrRatio(a)) {
    return out;
  }

  // 明确数字优先:quantity 本身是纯数字/范围,或含文字可提取单一数字
  const parsed = q ? parseQuantityString(q) : null;
  if (parsed) {
    out.quantity = parsed.quantity;
    if (parsed.quantityMax !== undefined) out.quantityMax = parsed.quantityMax;
    setUnit();
    return out;
  }

  // quantity 无明确数字:乘式公式 → 无量(不进 note);否则尝试把模糊词写进 note
  if (q && FORMULA_MUL_RE.test(q)) {
    return out;
  }

  // 模糊量承载于源 amount 或 quantity 文字:清洗后进 note
  const fuzzy = cleanNote(q) || cleanNote(a);
  if (fuzzy) out.note = fuzzy;
  return out;
}
