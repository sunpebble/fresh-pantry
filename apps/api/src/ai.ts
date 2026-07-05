const DAY_LIMIT = 100;
const MODEL = "deepseek-v4-flash";
const DEEPSEEK_URL = "https://api.deepseek.com/chat/completions";

export interface Env {
  AI_RATE: KVNamespace;
  DEEPSEEK_API_KEY: string;
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
}

function aiError(status: number, message: string): Response {
  return new Response(JSON.stringify({ error: { message } }), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

// fetcher 可注入：测试传 stub，生产用全局 fetch（本版本 vitest-pool-workers 已移除 fetchMock）。
export async function handleAiChat(
  request: Request,
  env: Env,
  fetcher: typeof fetch = fetch,
): Promise<Response> {
  if (request.method.toUpperCase() !== "POST") {
    return new Response("Method Not Allowed", { status: 405, headers: { Allow: "POST" } });
  }

  const auth = request.headers.get("authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!token) return aiError(401, "缺少登录凭证");

  // 体校验放在鉴权/计数之前：坏请求既不打 Supabase 也不消耗当日配额。
  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return aiError(400, "请求不是合法 JSON");
  }
  body.model = MODEL; // 服务端固定模型，不信任客户端

  // 用 Supabase 侧校验 token：免去 JWKS/HS256 双路径的密钥管理，AI 调用本身秒级，
  // 多一次子请求可接受。ponytail: 若这次往返成为瓶颈，再换本地 JWT 校验。
  // ponytail: 两处出站 fetch 未包 try/catch——网络层 reject 会以运行时 500 呈现，
  // 客户端 AiClient 对 5xx 已有中文兜底文案；出现真实抖动再统一包装。
  const userRes = await fetcher(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: env.SUPABASE_ANON_KEY, authorization: `Bearer ${token}` },
  });
  if (!userRes.ok) return aiError(401, "登录已过期，请重新登录");
  const user = (await userRes.json()) as { id?: string };
  if (!user.id) return aiError(401, "登录已过期，请重新登录");

  // ponytail: KV 日计数最终一致，突发并发可能略超限——可接受；真滥用再换 Durable Object。
  const day = new Date().toISOString().slice(0, 10).replaceAll("-", "");
  const key = `ai:${user.id}:${day}`;
  const used = Number((await env.AI_RATE.get(key)) ?? "0");
  if (used >= DAY_LIMIT) return aiError(429, "今天的 AI 次数用完了，明天再来");
  await env.AI_RATE.put(key, String(used + 1), { expirationTtl: 172800 });

  const upstream = await fetcher(DEEPSEEK_URL, {
    method: "POST",
    headers: {
      authorization: `Bearer ${env.DEEPSEEK_API_KEY}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
  return new Response(upstream.body, {
    status: upstream.status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}
