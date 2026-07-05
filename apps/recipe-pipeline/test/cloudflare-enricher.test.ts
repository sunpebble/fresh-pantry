import { describe, it, expect, vi } from 'vitest';
import { createCfChat, createCloudflareEnricher, extractJson } from '../src/clean/cloudflare-enricher';
import type { RawRecipe } from '../src/sources/types';

const raw: RawRecipe = {
  id: 'howtocook:vegetable_dish/番茄炒蛋',
  name: '番茄炒蛋',
  sourceRef: 'x',
  rawIngredients: ['番茄', '鸡蛋'],
  steps: ['切番茄', '打蛋', '炒'],
} as RawRecipe;

const validEnrichment = {
  category: '荤菜',
  difficulty: 1,
  cookingMinutes: 10,
  description: '经典家常菜。',
  ingredients: [{ name: '番茄', quantity: 2, unit: '个' }, { name: '鸡蛋', quantity: 3, unit: '个' }],
  steps: ['切番茄', '打蛋', '炒'],
  tags: ['快手'],
};

function okResponse(content: string) {
  return { ok: true, status: 200, json: async () => ({ choices: [{ message: { content } }] }) };
}
function capacityResponse() {
  return { ok: false, status: 200, json: async () => ({ errors: [{ code: 3040, message: 'AiError: Capacity temporarily exceeded' }] }) };
}

describe('extractJson', () => {
  it('剥掉 ```json fences 与前置思考文本', () => {
    expect(JSON.parse(extractJson('思考...\n```json\n{"a":1}\n```'))).toEqual({ a: 1 });
    expect(JSON.parse(extractJson('{"a":1}'))).toEqual({ a: 1 });
  });
});

describe('createCloudflareEnricher', () => {
  it('json_object 模式用于 DeepSeek 这类不支持 json_schema 的 OpenAI 兼容后端', async () => {
    const fetchImpl = vi.fn().mockResolvedValue(okResponse('{"ok":true}'));
    const chat = createCfChat({
      baseUrl: 'https://api.deepseek.com',
      apiKey: 'k',
      model: 'deepseek-v4-flash',
      responseFormat: 'json_object',
      fetchImpl: fetchImpl as unknown as typeof fetch,
    });
    await chat([{ role: 'user', content: 'JSON only' }], 'ignored', { type: 'object' });
    const body = JSON.parse(fetchImpl.mock.calls[0][1].body as string);
    expect(body.response_format).toEqual({ type: 'json_object' });
  });

  it('容量错(code 3040)先重试、后成功', async () => {
    const fetchImpl = vi.fn()
      .mockResolvedValueOnce(capacityResponse())
      .mockResolvedValueOnce(okResponse(JSON.stringify(validEnrichment)));
    const sleep = vi.fn().mockResolvedValue(undefined);
    const enricher = createCloudflareEnricher({
      baseUrl: 'https://x/ai/v1', apiKey: 'k', model: '@cf/moonshotai/kimi-k2.7-code',
      fetchImpl: fetchImpl as unknown as typeof fetch, sleep,
    });
    const out = await enricher.enrich(raw);
    expect(out.category).toBe('荤菜');
    expect(fetchImpl).toHaveBeenCalledTimes(2);
    expect(sleep).toHaveBeenCalledTimes(1);
  });

  it('429 也重试', async () => {
    const fetchImpl = vi.fn()
      .mockResolvedValueOnce({ ok: false, status: 429, json: async () => ({ error: { message: 'rate limited' } }) })
      .mockResolvedValueOnce(okResponse(JSON.stringify(validEnrichment)));
    const enricher = createCloudflareEnricher({
      baseUrl: 'https://x/ai/v1', apiKey: 'k', model: 'm',
      fetchImpl: fetchImpl as unknown as typeof fetch, sleep: async () => {},
    });
    await expect(enricher.enrich(raw)).resolves.toMatchObject({ difficulty: 1 });
  });

  it('不可重试错误(400)直接抛', async () => {
    const fetchImpl = vi.fn().mockResolvedValue({ ok: false, status: 400, json: async () => ({ error: { message: 'bad request' } }) });
    const enricher = createCloudflareEnricher({
      baseUrl: 'https://x/ai/v1', apiKey: 'k', model: 'm', maxRetries: 2,
      fetchImpl: fetchImpl as unknown as typeof fetch, sleep: async () => {},
    });
    await expect(enricher.enrich(raw)).rejects.toThrow(/bad request/);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  it('首响坏 JSON → 重提一次后成功', async () => {
    const fetchImpl = vi.fn()
      .mockResolvedValueOnce(okResponse('这不是 JSON'))
      .mockResolvedValueOnce(okResponse(JSON.stringify(validEnrichment)));
    const enricher = createCloudflareEnricher({
      baseUrl: 'https://x/ai/v1', apiKey: 'k', model: 'm',
      fetchImpl: fetchImpl as unknown as typeof fetch, sleep: async () => {},
    });
    await expect(enricher.enrich(raw)).resolves.toMatchObject({ category: '荤菜' });
    expect(fetchImpl).toHaveBeenCalledTimes(2);
  });

  it('apiKey 为空时构造即抛', () => {
    expect(() => createCloudflareEnricher({ baseUrl: 'https://x/ai/v1', apiKey: '', model: 'm' }))
      .toThrow(/CLOUDFLARE_AI_API_KEY/);
  });
});
