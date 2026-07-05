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

export interface CfChatOptions {
  baseUrl: string;
  apiKey: string;
  model: string;
  maxTokens?: number;
  maxRetries?: number;
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
  const emptyContent = typeof content !== 'string' || content.length === 0;
  const message = errs.map((e) => e?.message ?? '').filter(Boolean).join('; ')
    || `HTTP ${status}${emptyContent ? '(content 为空,可能 token 截断或被过滤)' : ''}`;
  const code = (errs[0] as { code?: number })?.code;
  const capacity = code === 3040 || /capacity/i.test(message);
  const retryable = capacity || status === 429 || status >= 500;
  return { ok: false, retryable, message };
}

/** 通用 chat-completions 调用(json_schema 响应),含容量/限流/5xx 重试。 */
export function createCfChat(opts: CfChatOptions): (
  messages: { role: string; content: string }[],
  schemaName: string,
  jsonSchema: unknown,
) => Promise<string> {
  if (!opts.apiKey) {
    throw new Error('CLOUDFLARE_AI_API_KEY 未设置,无法使用 CloudflareEnricher');
  }
  const fetchImpl = opts.fetchImpl ?? fetch;
  const sleep = opts.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));
  const maxTokens = opts.maxTokens ?? 4096;
  const maxRetries = opts.maxRetries ?? 5;
  const log = opts.log ?? (() => {});

  async function backoff(attempt: number): Promise<void> {
    const base = Math.min(30_000, 1_000 * 2 ** attempt);
    await sleep(base + base * 0.25 * Math.random()); // 抖动避免雪崩
  }

  return async function call(
    messages: { role: string; content: string }[],
    schemaName: string,
    jsonSchema: unknown,
  ): Promise<string> {
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
            response_format: { type: 'json_schema', json_schema: { name: schemaName, schema: jsonSchema } },
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
    // 理论上不可达:循环内每条路径(成功 return / 不可重试 throw / 耗尽 throw)都已终止;仅为类型收敛。
    throw new Error(`Cloudflare 重试耗尽: ${lastMsg}`);
  };
}

export function createCloudflareEnricher(opts: CloudflareEnricherOptions): RecipeEnricher {
  const call = createCfChat(opts);
  const log = opts.log ?? (() => {});

  async function parseOrThrow(content: string): Promise<Enrichment> {
    return v.parse(EnrichmentSchema, JSON.parse(extractJson(content)));
  }

  return {
    async enrich(raw: RawRecipe): Promise<Enrichment> {
      const messages = [
        { role: 'system', content: RECIPE_CLEANER_INSTRUCTIONS },
        { role: 'user', content: buildEnrichPrompt(raw) },
      ];
      const first = await call(messages, 'enrichment', ENRICHMENT_JSON_SCHEMA);
      try {
        return await parseOrThrow(first);
      } catch (e) {
        log(`首响解析失败,重提修正: ${e instanceof Error ? e.message : String(e)};first=${first.slice(0, 200)}`);
        const retried = await call([
          ...messages,
          { role: 'assistant', content: first },
          { role: 'user', content: '只返回符合要求的 JSON 对象,不要任何解释或 markdown 代码块。' },
        ], 'enrichment', ENRICHMENT_JSON_SCHEMA);
        return await parseOrThrow(retried);
      }
    },
  };
}
