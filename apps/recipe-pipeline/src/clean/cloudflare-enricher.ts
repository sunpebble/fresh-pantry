import * as v from 'valibot';
import { toJsonSchema } from '@valibot/to-json-schema';
import { EnrichmentSchema, type Enrichment } from './schema';
import { buildEnrichPrompt, RECIPE_CLEANER_INSTRUCTIONS, type RecipeEnricher } from './enrich';
import type { RawRecipe } from '../sources/types';

export interface CloudflareEnricherOptions {
  baseUrl: string;            // …/accounts/<id>/ai/v1
  apiKey: string;
  model: string;              // @cf/moonshotai/kimi-k2.7-code
  maxTokens?: number;         // 默认 4096(推理模型烧 token,给足)
  maxRetries?: number;        // 默认 5
  fetchImpl?: typeof fetch;
  sleep?: (ms: number) => Promise<void>;
  log?: (msg: string) => void;
}

/** EnrichmentSchema → JSON Schema(模块加载时算一次)。strict 留给 v.parse 兜底。 */
export const ENRICHMENT_JSON_SCHEMA = toJsonSchema(EnrichmentSchema, { errorMode: 'ignore' });

/** 推理模型可能包 ```json fences 或前置思考文本;抽出第一个 {...} 块。 */
export function extractJson(text: string): string {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  const candidate = fenced ? fenced[1] : text;
  const start = candidate.indexOf('{');
  const end = candidate.lastIndexOf('}');
  return start >= 0 && end > start ? candidate.slice(start, end + 1) : candidate.trim();
}

interface Classified { ok: boolean; content?: string; retryable: boolean; message: string; }

/** 判定一次响应:成功取 content;失败识别容量/限流/5xx 为可重试。 */
function classify(status: number, body: unknown): Classified {
  const b = body as { choices?: { message?: { content?: unknown } }[]; errors?: { code?: number; message?: string }[]; error?: { message?: string } };
  const content = b?.choices?.[0]?.message?.content;
  if (typeof content === 'string' && content.length > 0) {
    return { ok: true, content, retryable: false, message: '' };
  }
  const errs = b?.errors ?? (b?.error ? [b.error] : []);
  const message = errs.map((e) => e?.message ?? '').filter(Boolean).join('; ') || `HTTP ${status}`;
  const code = (errs[0] as { code?: number })?.code;
  const capacity = code === 3040 || /capacity/i.test(message);
  const retryable = capacity || status === 429 || status >= 500;
  return { ok: false, retryable, message };
}

export function createCloudflareEnricher(opts: CloudflareEnricherOptions): RecipeEnricher {
  const fetchImpl = opts.fetchImpl ?? fetch;
  const sleep = opts.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  const maxTokens = opts.maxTokens ?? 4096;
  const maxRetries = opts.maxRetries ?? 5;
  const log = opts.log ?? (() => {});

  async function backoff(attempt: number): Promise<void> {
    const base = Math.min(30_000, 1_000 * 2 ** attempt);
    await sleep(base + base * 0.25 * Math.random()); // 抖动避免雪崩
  }

  async function call(messages: { role: string; content: string }[]): Promise<string> {
    let lastMsg = '';
    for (let attempt = 0; attempt <= maxRetries; attempt++) {
      let status = 0;
      let body: unknown;
      try {
        const res = await fetchImpl(`${opts.baseUrl}/chat/completions`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${opts.apiKey}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({
            model: opts.model,
            messages,
            response_format: { type: 'json_schema', json_schema: { name: 'enrichment', schema: ENRICHMENT_JSON_SCHEMA } },
            max_tokens: maxTokens,
          }),
        });
        status = res.status;
        body = await res.json();
      } catch (e) {
        lastMsg = e instanceof Error ? e.message : String(e);
        if (attempt < maxRetries) { log(`网络错重试 ${attempt + 1}/${maxRetries}: ${lastMsg}`); await backoff(attempt); continue; }
        throw new Error(`Cloudflare 请求失败(网络): ${lastMsg}`);
      }
      const c = classify(status, body);
      if (c.ok) return c.content!;
      lastMsg = c.message;
      if (c.retryable && attempt < maxRetries) { log(`重试 ${attempt + 1}/${maxRetries}: ${c.message}`); await backoff(attempt); continue; }
      throw new Error(`Cloudflare 返回错误: ${c.message}`);
    }
    throw new Error(`Cloudflare 重试耗尽: ${lastMsg}`);
  }

  async function parseOrThrow(content: string): Promise<Enrichment> {
    return v.parse(EnrichmentSchema, JSON.parse(extractJson(content)));
  }

  return {
    async enrich(raw: RawRecipe): Promise<Enrichment> {
      const messages = [
        { role: 'system', content: RECIPE_CLEANER_INSTRUCTIONS },
        { role: 'user', content: buildEnrichPrompt(raw) },
      ];
      const first = await call(messages);
      try {
        return await parseOrThrow(first);
      } catch {
        const retried = await call([
          ...messages,
          { role: 'assistant', content: first },
          { role: 'user', content: '只返回符合要求的 JSON 对象,不要任何解释或 markdown 代码块。' },
        ]);
        return await parseOrThrow(retried);
      }
    },
  };
}
