import { cloudflareTest } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.jsonc" },
      // 测试环境注入假 secret（真值走 wrangler secret，不进仓库）。
      miniflare: { bindings: { DEEPSEEK_API_KEY: "test-deepseek-key" } },
    }),
  ],
});
