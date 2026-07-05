import { handleAiChat, type Env } from "./ai";

const INVITE_TOKEN_PATTERN = /^[A-Za-z0-9_-]{10,160}$/;
const APP_DEEP_LINK_SCHEME = "com.sunpebble.freshpantry";

function json(body: unknown, init: ResponseInit = {}): Response {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: {
      "content-type": "application/json; charset=utf-8",
      ...init.headers,
    },
  });
}

function safeDecodePathSegment(value: string): string | null {
  try {
    return decodeURIComponent(value);
  } catch {
    return null;
  }
}

function inviteFallback(token: string): Response {
  const deepLink = `${APP_DEEP_LINK_SCHEME}://invite/${encodeURIComponent(token)}`;
  return new Response(
    `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Open Fresh Pantry</title>
  </head>
  <body>
    <main>
      <h1>Open Fresh Pantry</h1>
      <p>Use the button below to accept this household invite.</p>
      <p><a href="${deepLink}">Open invite</a></p>
    </main>
  </body>
</html>`,
    {
      headers: {
        "content-type": "text/html; charset=utf-8",
        "Cache-Control": "no-store",
        "Content-Security-Policy": "default-src 'none'; base-uri 'none'",
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "DENY",
      },
    },
  );
}

export default {
  async fetch(request: Request, env?: Env, _ctx?: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const method = request.method.toUpperCase();
    const isReadMethod = method === "GET" || method === "HEAD";

    if (url.pathname === "/ai/v1/chat/completions") {
      // env 在生产运行时恒有值；可选签名只是为了兼容既有直调 fetch 的测试。
      if (!env) return new Response("Service misconfigured", { status: 500 });
      return handleAiChat(request, env);
    }

    if (url.pathname === "/health") {
      if (!isReadMethod) {
        return new Response("Method Not Allowed", {
          status: 405,
          headers: { Allow: "GET, HEAD" },
        });
      }
      return json(
        { service: "fresh-pantry-api", ok: true, timestamp: new Date().toISOString() },
        { headers: { "Access-Control-Allow-Origin": "*" } },
      );
    }

    const inviteMatch = url.pathname.match(/^\/invite\/([^/]+)$/);
    if (inviteMatch) {
      if (!isReadMethod) {
        return new Response("Method Not Allowed", {
          status: 405,
          headers: { Allow: "GET, HEAD" },
        });
      }
      const token = safeDecodePathSegment(inviteMatch[1]);
      if (token === null || !INVITE_TOKEN_PATTERN.test(token)) {
        return new Response("Invalid invite token", { status: 400 });
      }
      const accept = request.headers.get("accept") ?? "";
      if (accept.includes("text/html")) {
        return inviteFallback(token);
      }
      const deepLink = `${APP_DEEP_LINK_SCHEME}://invite/${encodeURIComponent(token)}`;
      return new Response(null, {
        status: 302,
        headers: { Location: deepLink, "Cache-Control": "no-store" },
      });
    }

    return new Response("Not found", { status: 404 });
  },
};
