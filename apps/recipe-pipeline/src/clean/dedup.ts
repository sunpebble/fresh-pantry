import type { CleanRecipe } from './schema';

const PRIORITY: Array<[string, number]> = [
  ['howtocook:', 0],
  ['repo:', 1],
  ['url:', 2],
];

function sourcePriority(id: string): number {
  const hit = PRIORITY.find(([prefix]) => id.startsWith(prefix));
  return hit ? hit[1] : 99;
}

export function normalizeName(name: string): string {
  return name
    .normalize('NFKC')
    .replace(/[\s　]/g, '')
    .replace(/[（）()【】\[\]「」『』·・,，。.、！!？?~～\-—_]/g, '')
    .toLowerCase();
}

export function ingredientSet(r: CleanRecipe): Set<string> {
  return new Set(r.ingredients.map((i) => i.name.trim()).filter(Boolean));
}

export function jaccard(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 && b.size === 0) return 1;
  let inter = 0;
  for (const x of a) if (b.has(x)) inter++;
  const union = a.size + b.size - inter;
  return union === 0 ? 0 : inter / union;
}

export const DUP_THRESHOLD = 0.6;

export interface DedupeResult {
  kept: CleanRecipe[];
  dropped: Array<{ id: string; dupOf: string }>;
}

export function dedupe(recipes: CleanRecipe[]): DedupeResult {
  const ordered = [...recipes].sort((a, b) => sourcePriority(a.id) - sourcePriority(b.id));
  const kept: CleanRecipe[] = [];
  const dropped: Array<{ id: string; dupOf: string }> = [];
  for (const r of ordered) {
    const key = normalizeName(r.name);
    const set = ingredientSet(r);
    const dupOf = kept.find(
      (k) => normalizeName(k.name) === key && jaccard(ingredientSet(k), set) >= DUP_THRESHOLD,
    );
    if (dupOf) dropped.push({ id: r.id, dupOf: dupOf.id });
    else kept.push(r);
  }
  return { kept, dropped };
}
