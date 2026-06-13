import type { CleanRecipe } from './schema';
import type { RawRecipe } from '../sources/types';
import { isTool } from '../parse/howtocook-parser';

/**
 * 写盘前质量闸门:LLM 输出经 normalize 后仍必须满足的「无损数字 schema」硬约定。
 * 违规清单非空 → 该菜 reject(merge 保留既有版本),进 rejects.json 供排查。
 *
 * 约定:
 * - quantity/quantityMax 若出现必须是 number;quantityMax 必须 > quantity 且同样溯源。
 * - quantity 数值要能在源文本溯源(阿拉伯/中文数字/分数换算)。
 * - unit 若出现必须是非空字符串。
 * - note 若出现必须非空,且不含 markdown 残留/纯数字/公式标记。
 * - 不得存在 amount 字段。
 * - description 不含 markdown 残留;食材不得混入工具。
 */

const MD_RESIDUE_RE = /!?\[[^\]]*\]\([^)]*\)|[*_`#]/;
const FORMULA_RE = /[*×+]|份数|人份|\d+\s*人/;
// 除式系数 / 配比里被抽出的数字其实是「系数」而非用量。仅在该食材是某「定义行主语」
// (行首 name 后紧跟 = 或 :)、且该行是 变量/数 除式 或 三段配比 时才判定——避免把
// 含「肥瘦比例 3:7」「2 根/三人」「比例提示 1:1」等 prose/tip 行里的合法用量误杀。
const FORMULA_DIV_VAR_RE = /[张份]数|体积|斤数|数量/;
function escapeRe(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&');
}
function isFormulaCoefficient(name: string, lines: string[]): boolean {
  const subjectRe = new RegExp(`^[-*\\s]*${escapeRe(name)}\\s*[=:：]`);
  for (const raw of lines) {
    const line = raw.trim();
    if (!subjectRe.test(line)) continue;
    const division = FORMULA_DIV_VAR_RE.test(line) && /[/÷／]\s*\d/.test(line);
    const ratio3 = /\d\s*[:：]\s*\d\s*[:：]\s*\d/.test(line);
    if (division || ratio3) return true;
  }
  return false;
}
const CN_NUM: Record<string, string> = {
  '0.5': '半', '1': '一', '2': '两二', '3': '三', '4': '四',
  '5': '五', '6': '六', '7': '七', '8': '八', '9': '九', '10': '十',
};
const UNI_FRACTION: Record<string, number> = {
  '½': 0.5, '¼': 0.25, '¾': 0.75, '⅓': 1 / 3, '⅔': 2 / 3, '⅛': 0.125,
};
const CN_DIGIT: Record<string, number> = {
  一: 1, 两: 2, 二: 2, 三: 3, 四: 4, 五: 5, 六: 6, 七: 7, 八: 8, 九: 9, 十: 10,
};

/**
 * 从源文本解析分数形态(混合数「2 1/2」、纯分数「1/8」、Unicode「2½」、
 * 中文「二分之一」),收集对应小数字符串,供溯源比对转写后的 number。
 */
function fractionTokens(text: string): Set<string> {
  const tokens = new Set<string>();
  const add = (v: number) => {
    tokens.add(String(Math.round(v * 1000) / 1000));
    tokens.add(v.toFixed(2).replace(/0+$/, '').replace(/\.$/, ''));
  };
  for (const m of text.matchAll(/(\d+)\s+(\d+)\/(\d+)/g)) {
    add(Number(m[1]) + Number(m[2]) / Number(m[3]));
  }
  for (const m of text.matchAll(/(?<!\d\s)(\d+)\/(\d+)/g)) {
    add(Number(m[1]) / Number(m[2]));
  }
  for (const m of text.matchAll(/(\d+)?([½¼¾⅓⅔⅛])/g)) {
    add(Number(m[1] ?? 0) + UNI_FRACTION[m[2]]);
  }
  for (const m of text.matchAll(/([一两二三四五六七八九十])分之([一两二三四五六七八九十])/g)) {
    add(CN_DIGIT[m[2]] / CN_DIGIT[m[1]]);
  }
  return tokens;
}

function squash(s: string): string {
  return s.normalize('NFKC').replace(/\s+/g, '');
}

/** 数字有源依据:阿拉伯原样出现,或对应中文数字出现,或可由源中分数形态换算。 */
function numberSourced(num: number, src: string, fractions: Set<string>): boolean {
  const s = String(num);
  if (src.includes(s)) return true;
  const cn = CN_NUM[s];
  if (cn && [...cn].some((c) => src.includes(c))) return true;
  return fractions.has(s);
}

export function validateCleanRecipe(recipe: CleanRecipe, rawSource: RawRecipe): string[] {
  const violations: string[] = [];
  // 用量可写在计算段、原料行或步骤里(HowToCook 三种都有),网页源用 rawText
  const sourceText = [
    rawSource.portionText ?? '',
    rawSource.rawText ?? '',
    ...rawSource.rawIngredients,
    ...rawSource.steps,
  ].join('\n');
  const quantitySource = squash(sourceText);
  const fractions = fractionTokens(sourceText);
  // 未 squash 的源行:用于「食材名 → 公式行」匹配(除式/配比系数检测)
  const sourceLines = [
    ...(rawSource.portionText ?? '').split('\n'),
    ...(rawSource.rawText ?? '').split('\n'),
    ...rawSource.rawIngredients,
    ...rawSource.steps,
  ];

  if (MD_RESIDUE_RE.test(recipe.description)) {
    violations.push(`description 含 markdown 残留: ${recipe.description.slice(0, 50)}`);
  }

  for (const ing of recipe.ingredients) {
    if (isTool(ing.name)) {
      violations.push(`工具混入食材: ${ing.name}`);
    }
    // amount 字段已彻底删除:对象里仍带 amount 视为违规
    if ('amount' in ing) {
      violations.push(`残留 amount 字段: ${ing.name}`);
    }

    const { quantity, quantityMax, unit, note } = ing;

    if (quantity !== undefined && typeof quantity !== 'number') {
      violations.push(`quantity 非 number: ${ing.name}=${JSON.stringify(quantity)}`);
    }
    if (quantityMax !== undefined && typeof quantityMax !== 'number') {
      violations.push(`quantityMax 非 number: ${ing.name}=${JSON.stringify(quantityMax)}`);
    }
    if (quantityMax !== undefined && quantity === undefined) {
      violations.push(`quantityMax 出现但缺 quantity 下界: ${ing.name}`);
    }
    if (
      typeof quantity === 'number' && typeof quantityMax === 'number' && quantityMax <= quantity
    ) {
      violations.push(`quantityMax 未大于 quantity: ${ing.name}=${quantity}-${quantityMax}`);
    }

    if (typeof quantity === 'number' && quantitySource
      && !numberSourced(quantity, quantitySource, fractions)) {
      violations.push(`用量数字无法溯源: ${ing.name} quantity=${quantity}(不在源文本)`);
    }
    // 数字虽在源文本出现,但该食材是某除式/配比「定义行」的主语 → 抽出的是系数,非用量
    if (typeof quantity === 'number' && isFormulaCoefficient(ing.name, sourceLines)) {
      violations.push(`用量数字来自公式系数/配比: ${ing.name} quantity=${quantity}(非实际用量)`);
    }
    if (typeof quantityMax === 'number' && quantitySource
      && !numberSourced(quantityMax, quantitySource, fractions)) {
      violations.push(`用量上界无法溯源: ${ing.name} quantityMax=${quantityMax}(不在源文本)`);
    }

    if (unit !== undefined && (typeof unit !== 'string' || unit === '')) {
      violations.push(`unit 为空或非字符串: ${ing.name}=${JSON.stringify(unit)}`);
    }

    if (note !== undefined) {
      if (typeof note !== 'string' || note === '') {
        violations.push(`note 为空或非字符串: ${ing.name}=${JSON.stringify(note)}`);
      } else if (/^\d+(\.\d+)?$/.test(note.trim())) {
        violations.push(`note 是纯数字: ${ing.name}=${JSON.stringify(note)}`);
      } else if (FORMULA_RE.test(note)) {
        // 公式标记(* × + 份数…)先于 markdown 判定:乘式的 * 同时命中 markdown 正则,
        // 但在 note 语境里几乎一定是乘式而非加粗,优先归类为公式
        violations.push(`note 含公式标记: ${ing.name}=${JSON.stringify(note)}`);
      } else if (MD_RESIDUE_RE.test(note)) {
        violations.push(`note 含 markdown 残留: ${ing.name}=${JSON.stringify(note)}`);
      }
    }
  }
  return violations;
}
