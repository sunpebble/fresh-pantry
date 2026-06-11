import { describe, it, expect } from 'vitest';
import { urlIdFor, htmlToText, urlBatchSource } from '../src/sources/url-batch';
import type { RecipeEnricher } from '../src/clean/enrich';

const enr: RecipeEnricher = { async enrich() { throw new Error('unused'); } };

describe('urlIdFor', () => {
  it('host+path slug', () => {
    expect(urlIdFor('https://www.douguo.com/recipe/123.html')).toBe('url:douguo.com/recipe/123.html');
  });
});

describe('htmlToText', () => {
  it('剥标签、压空白', () => {
    expect(htmlToText('<h1>番茄炒蛋</h1><p>步骤:<br>1. 打蛋</p>')).toContain('番茄炒蛋');
    expect(htmlToText('<script>x</script><p>正文</p>')).not.toContain('x');
  });
});

describe('urlBatchSource', () => {
  it('注入 fetch,产出带 rawText 的 RawRecipe(llm-extract)', async () => {
    const fakeFetch = async () => ({ text: async () => '<title>番茄炒蛋</title><p>正文内容</p>' }) as unknown as Response;
    const src = urlBatchSource({ urls: ['https://x.com/r/1'], fetchImpl: fakeFetch }, enr);
    expect(src.kind).toBe('llm-extract');
    const out: string[] = [];
    for await (const r of src.collect({ workDir: '.', log: () => {} })) {
      out.push(r.id);
      expect(r.rawText).toContain('正文内容');
      expect(r.name).toBe('番茄炒蛋');
    }
    expect(out).toEqual(['url:x.com/r/1']);
  });

  it('fetch 失败的 url 被跳过,不中断其余', async () => {
    const seq = [
      async () => { throw new Error('network'); },
      async () => ({ text: async () => '<title>好菜</title><p>正文</p>' }) as unknown as Response,
    ];
    let i = 0;
    const fakeFetch = (async () => seq[i++]()) as unknown as typeof fetch;
    const src = urlBatchSource({ urls: ['https://a.com/1', 'https://b.com/2'], fetchImpl: fakeFetch }, enr);
    const out: string[] = [];
    for await (const r of src.collect({ workDir: '.', log: () => {} })) out.push(r.id);
    expect(out).toEqual(['url:b.com/2']); // 第一个失败被跳过,第二个产出
  });
});
