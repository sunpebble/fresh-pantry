import type { RecipeSource, RawRecipe, SourceContext } from './types';
import type { RecipeEnricher } from '../clean/enrich';

export interface UrlBatchConfig {
  urls: string[];
  fetchImpl?: typeof fetch;
}

export function urlIdFor(url: string): string {
  const u = new URL(url);
  const host = u.host.replace(/^www\./, '');
  return `url:${host}${u.pathname}`;
}

export function htmlToText(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(p|div|li|h[1-6])>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/[ \t]+/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function titleOf(html: string): string | undefined {
  const m = html.match(/<title>([^<]*)<\/title>/i);
  return m ? m[1].trim() : undefined;
}

export function urlBatchSource(cfg: UrlBatchConfig, _enricher: RecipeEnricher): RecipeSource {
  const doFetch = cfg.fetchImpl ?? fetch;
  return {
    id: 'url',
    kind: 'llm-extract',
    async *collect(ctx: SourceContext): AsyncIterable<RawRecipe> {
      for (const url of cfg.urls) {
        try {
          const res = await doFetch(url);
          const html = await res.text();
          yield {
            id: urlIdFor(url),
            sourceId: 'url',
            sourceRef: url,
            name: titleOf(html) ?? url,
            rawIngredients: [],
            steps: [],
            rawText: htmlToText(html),
            imageUrl: null,
          };
        } catch (e) {
          ctx.log(`fetch failed ${url}: ${String(e)}`);
        }
      }
    },
  };
}
