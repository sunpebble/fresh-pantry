export interface ParsedHowtocook {
  name: string;
  difficulty: number;
  description?: string;
  rawIngredients: string[];
  portionText?: string;
  steps: string[];
  /** 全文第一张图的原始引用(相对路径或绝对 URL),无图则缺省。 */
  imageRef?: string;
  /** preamble 里声明的总制作时长(分钟),如「制作时长约 30 分钟」「约需 1 小时」。 */
  sourceCookingMinutes?: number;
}

const TOOL_KEYWORDS = [
  '锅', '铲', '勺', '刀', '案板', '砧板', '菜板', '碗', '盆', '筷', '烤箱',
  '微波炉', '电饭煲', '空气炸锅', '高压锅', '料理机', '搅拌机', '榨汁',
  '量杯', '量勺', '厨房秤', '电子秤', '保鲜膜', '锡纸', '油纸', '牙签',
  '厨房纸', '吸油纸', '喷壶', '刷子', '夹子', '漏勺', '蒸笼', '蒸架',
  '烤盘', '模具', '裱花', '擀面杖', '筛',
  '手套', '密封袋', '保鲜袋', '盘夹', '打蛋器', '温度计', '吸管', '滤网', '纱布', '剪', '盅',
];

/**
 * Returns true if `line` appears to describe a kitchen tool rather than an ingredient.
 *
 * **Heuristic risk**: single-character keywords (锅/碗/刀/勺/盆) may rarely match
 * food names (e.g. 砂锅配料, 花刀鱼). These false-positive drops are acceptable
 * because downstream LLM enrichment acts as a fallback to recover missing ingredients.
 */
export function isTool(line: string): boolean {
  return TOOL_KEYWORDS.some((kw) => line.includes(kw));
}

export function stripInlineMarkdown(s: string): string {
  return s
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/[*_`]+/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function bulletLines(block: string): string[] {
  return block
    .split('\n')
    .map((l) => l.trim())
    .filter((l) => /^([*\-]|\d+\.)\s+/.test(l))
    .map((l) => l.replace(/^([*\-]|\d+\.)\s+/, '').trim());
}

interface Section {
  heading: string;
  body: string;
}

function splitSections(md: string): { preamble: string; sections: Section[] } {
  const parts = md.split(/^##\s+/m);
  const preamble = parts[0];
  const sections = parts.slice(1).map((p) => {
    const nl = p.indexOf('\n');
    return nl === -1
      ? { heading: p.trim(), body: '' }
      : { heading: p.slice(0, nl).trim(), body: p.slice(nl + 1) };
  });
  return { preamble, sections };
}

export function parseHowtocook(markdown: string): ParsedHowtocook {
  const { preamble, sections } = splitSections(markdown);

  const titleMatch = preamble.match(/^#\s+(.+?)\s*$/m);
  const rawTitle = titleMatch ? titleMatch[1].trim() : '';
  const name = rawTitle.replace(/的做法\s*$/, '').trim();

  const starMatch = preamble.match(/预估烹饪难度[:：]\s*(★+)/);
  const difficulty = starMatch ? Math.min(5, starMatch[1].length) : 3;

  const descLines: string[] = [];
  for (const line of preamble.split('\n')) {
    const t = line.trim();
    if (!t || t.startsWith('#') || t.startsWith('![')) continue;
    if (t.startsWith('预估')) break;
    descLines.push(t);
  }
  const description = descLines.length ? descLines.join(' ') : undefined;

  // 文件名可含一层配平括号,如 血浆鸭(特辣).jpg / 石凉粉(冰粉)成品1.jpg
  const imgMatch = markdown.match(/!\[[^\]]*\]\(((?:[^()\s]|\([^()]*\))+)\)/);
  const imageRef = imgMatch ? imgMatch[1] : undefined;

  // 只认 preamble 的总时长声明;步骤里的「腌制 10 分钟」不算
  const cmMatch = preamble.match(/(?:制作时长|约需)\s*约?\s*(\d+(?:\.\d+)?)\s*(?:个)?\s*(分钟|小时)/);
  const sourceCookingMinutes = cmMatch
    ? Math.round(Number(cmMatch[1]) * (cmMatch[2] === '小时' ? 60 : 1))
    : undefined;

  const find = (kw: string) => sections.find((s) => s.heading.includes(kw));

  const ingSection = find('必备原料') ?? find('原料');
  const rawIngredients = ingSection
    ? bulletLines(ingSection.body).filter((l) => !isTool(l))
    : [];

  const calcSection = find('计算');
  const portionText = calcSection ? calcSection.body.trim() || undefined : undefined;

  const opSection = find('操作') ?? find('步骤');
  const steps = opSection ? bulletLines(opSection.body).map(stripInlineMarkdown) : [];

  return { name, difficulty, description, rawIngredients, portionText, steps, imageRef, sourceCookingMinutes };
}
