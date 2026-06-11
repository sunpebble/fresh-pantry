import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile, readdir, stat } from 'node:fs/promises';
import { join, relative, basename } from 'node:path';
import type { RecipeSource, RawRecipe, SourceContext } from './types';
import type { Category } from '../clean/schema';
import { parseHowtocook } from '../parse/howtocook-parser';

const exec = promisify(execFile);

export interface MarkdownRepoConfig {
  name: string;
  repo: string;
  dishesDir: string;
  category?: Category;
}

export function markdownRepoIdFor(cfg: MarkdownRepoConfig, relPath: string): string {
  const slug = basename(relPath, '.md');
  return `repo:${cfg.name}:${slug}`;
}

export function rawFromRepoMarkdown(cfg: MarkdownRepoConfig, relPath: string, md: string): RawRecipe {
  const parsed = parseHowtocook(md);
  return {
    id: markdownRepoIdFor(cfg, relPath),
    sourceId: `repo:${cfg.name}`,
    sourceRef: relPath,
    name: parsed.name || basename(relPath, '.md'),
    sourceCategory: cfg.category,
    sourceDifficulty: parsed.difficulty,
    description: parsed.description,
    rawIngredients: parsed.rawIngredients,
    portionText: parsed.portionText,
    steps: parsed.steps,
    imageUrl: null,
  };
}

async function* walkMd(dir: string, root: string): AsyncIterable<string> {
  for (const entry of await readdir(dir)) {
    const full = join(dir, entry);
    const s = await stat(full);
    if (s.isDirectory()) yield* walkMd(full, root);
    else if (entry.endsWith('.md') && entry !== 'README.md') yield relative(root, full);
  }
}

export function markdownRepoSource(cfg: MarkdownRepoConfig): RecipeSource {
  return {
    id: `repo:${cfg.name}`,
    kind: 'deterministic',
    async *collect(ctx: SourceContext): AsyncIterable<RawRecipe> {
      const repoDir = join(ctx.workDir, cfg.name);
      await exec('git', ['clone', '--depth', '1', cfg.repo, repoDir]).catch((e) =>
        ctx.log(`clone ${cfg.name} 跳过/失败 (${String(e)});尝试复用缓存`),
      );
      const base = join(repoDir, cfg.dishesDir);
      const ok = await stat(base).then((s) => s.isDirectory()).catch(() => false);
      if (!ok) {
        throw new Error(`仓库 ${cfg.name} 不可用(克隆失败且无缓存): ${base}`);
      }
      for await (const relPath of walkMd(base, repoDir)) {
        const md = await readFile(join(repoDir, relPath), 'utf8');
        const raw = rawFromRepoMarkdown(cfg, relPath, md);
        if (raw.rawIngredients.length || raw.steps.length) yield raw;
      }
    },
  };
}
