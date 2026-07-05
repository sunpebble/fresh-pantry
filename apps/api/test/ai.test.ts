import { env as runtimeEnv } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { handleAiChat, type Env } from "../src/ai";
import worker from "../src/index";

const AI_PATH = "https://api.freshpantry.sunpebblelabs.com/ai/v1/chat/completions";
const today = new Date().toISOString().slice(0, 10).replaceAll("-", "");
const env = runtimeEnv as unknown as Env;

function post(body: unknown, token?: string): Request {
  return new Request(AI_PATH, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
}

/// 记录出站请求并按 URL 前缀回放的 fetch stub（本版本 vitest-pool-workers 无 fetchMock）。
function stubFetch(
  routes: Record<string, (req: Request) => Response | Promise<Response>>,
): { fetcher: typeof fetch; calls: Request[] } {
  const calls: Request[] = [];
  const fetcher = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const req = new Request(input, init);
    calls.push(req);
    for (const [prefix, handler] of Object.entries(routes)) {
      if (req.url.startsWith(prefix)) return handler(req);
    }
    throw new Error(`unexpected outbound fetch: ${req.url}`);
  }) as typeof fetch;
  return { fetcher, calls };
}

const supabaseOk = () =>
  new Response(JSON.stringify({ id: "user-1" }), { status: 200 });

describe("POST /ai/v1/chat/completions", () => {
  it("缺 token 返回 401（经完整路由）", async () => {
    const res = await worker.fetch(post({ messages: [] }), env);
    expect(res.status).toBe(401);
    const json = (await res.json()) as { error: { code: string; message: string } };
    expect(json.error.code).toBe("auth_missing");
    expect(json.error.message).toBe("缺少登录凭证");
  });

  it("非 POST 返回 405（经完整路由）", async () => {
    const res = await worker.fetch(new Request(AI_PATH, { method: "GET" }), env);
    expect(res.status).toBe(405);
  });

  it("token 校验失败返回 401", async () => {
    const { fetcher } = stubFetch({
      [env.SUPABASE_URL]: () => new Response("{}", { status: 401 }),
    });
    const res = await handleAiChat(post({ messages: [] }, "bad-token"), env, fetcher);
    expect(res.status).toBe(401);
    const json = (await res.json()) as { error: { code: string; message: string } };
    expect(json.error.code).toBe("auth_expired");
    expect(json.error.message).toBe("登录已过期，请重新登录");
  });

  it("转发 DeepSeek 并强制服务端模型", async () => {
    const { fetcher, calls } = stubFetch({
      [env.SUPABASE_URL]: supabaseOk,
      "https://api.deepseek.com/chat/completions": () =>
        new Response(JSON.stringify({ choices: [{ message: { content: "ok" } }] }), {
          status: 200,
        }),
    });
    const res = await handleAiChat(
      post({ model: "gpt-4", messages: [{ role: "user", content: "hi" }] }, "good-token"),
      env,
      fetcher,
    );
    expect(res.status).toBe(200);
    const json = (await res.json()) as { choices: { message: { content: string } }[] };
    expect(json.choices[0].message.content).toBe("ok");

    const upstream = calls.find((r) => r.url.startsWith("https://api.deepseek.com"));
    expect(upstream).toBeDefined();
    const sent = (await upstream!.json()) as { model: string };
    expect(sent.model).toBe("deepseek-v4-flash");
    expect(upstream!.headers.get("authorization")).toBe("Bearer test-deepseek-key");
  });

  it("非法 JSON 返回 400，不扣配额也不发出站请求", async () => {
    await env.AI_RATE.delete(`ai:user-1:${today}`); // 本文件测试共享存储，先清计数
    const { fetcher, calls } = stubFetch({});
    const req = new Request(AI_PATH, {
      method: "POST",
      headers: { authorization: "Bearer good-token" },
      body: "not-json",
    });
    const res = await handleAiChat(req, env, fetcher);
    expect(res.status).toBe(400);
    const json = (await res.json()) as { error: { code: string; message: string } };
    expect(json.error.code).toBe("bad_json");
    expect(json.error.message).toBe("请求不是合法 JSON");
    expect(calls.length).toBe(0); // 未打 Supabase 也未打 DeepSeek
    expect(await env.AI_RATE.get(`ai:user-1:${today}`)).toBeNull(); // 配额未消耗
  });

  it("超过日限额返回 429 + 中文提示，且不再请求 DeepSeek", async () => {
    await env.AI_RATE.put(`ai:user-1:${today}`, "100");
    const { fetcher, calls } = stubFetch({ [env.SUPABASE_URL]: supabaseOk });
    const res = await handleAiChat(post({ messages: [] }, "good-token"), env, fetcher);
    expect(res.status).toBe(429);
    const json = (await res.json()) as { error: { code: string; message: string } };
    expect(json.error.code).toBe("quota_exhausted");
    expect(json.error.message).toContain("今天的 AI 次数用完了");
    expect(calls.some((r) => r.url.startsWith("https://api.deepseek.com"))).toBe(false);
  });
});
