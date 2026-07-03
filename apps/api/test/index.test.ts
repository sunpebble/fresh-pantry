import { describe, expect, it } from "vitest";
import worker from "../src/index";

describe("fresh-pantry-api", () => {
  it("returns health status", async () => {
    const response = await worker.fetch(new Request("https://api.freshpantry.sunpebblelabs.com/health"));

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      service: "fresh-pantry-api",
      ok: true,
    });
  });

  it("redirects valid invite tokens to the mobile deep link", async () => {
    const response = await worker.fetch(
      new Request("https://api.freshpantry.sunpebblelabs.com/invite/abcDEF123_-"),
    );

    expect(response.status).toBe(302);
    expect(response.headers.get("location")).toBe(
      "com.sunpebble.freshpantry://invite/abcDEF123_-",
    );
  });

  it("returns an HTML invite fallback for browser requests", async () => {
    const response = await worker.fetch(
      new Request("https://api.freshpantry.sunpebblelabs.com/invite/abcDEF123_-", {
        headers: { accept: "text/html" },
      }),
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("text/html; charset=utf-8");
    await expect(response.text()).resolves.toContain(
      'href="com.sunpebble.freshpantry://invite/abcDEF123_-"',
    );
  });

  it("rejects malformed invite tokens", async () => {
    const response = await worker.fetch(
      new Request("https://api.freshpantry.sunpebblelabs.com/invite/not valid"),
    );

    expect(response.status).toBe(400);
    await expect(response.text()).resolves.toContain("Invalid invite token");
  });

  it("rejects malformed percent-encoded invite tokens", async () => {
    const response = await worker.fetch(
      new Request("https://api.freshpantry.sunpebblelabs.com/invite/%E0%A4%A"),
    );

    expect(response.status).toBe(400);
    await expect(response.text()).resolves.toContain("Invalid invite token");
  });

  it("returns 405 for POST /health", async () => {
    const response = await worker.fetch(
      new Request("https://api.freshpantry.sunpebblelabs.com/health", {
        method: "POST",
      }),
    );

    expect(response.status).toBe(405);
    expect(response.headers.get("allow")).toBe("GET, HEAD");
  });

  it("returns 405 for POST /invite/<token>", async () => {
    const response = await worker.fetch(
      new Request("https://api.freshpantry.sunpebblelabs.com/invite/abcDEF123_-", {
        method: "POST",
      }),
    );

    expect(response.status).toBe(405);
    expect(response.headers.get("allow")).toBe("GET, HEAD");
  });

  it("HEAD /health returns 200", async () => {
    const response = await worker.fetch(
      new Request("https://api.freshpantry.sunpebblelabs.com/health", { method: "HEAD" }),
    );

    expect(response.status).toBe(200);
  });

  it("HEAD /invite/<token> returns 302", async () => {
    const response = await worker.fetch(
      new Request("https://api.freshpantry.sunpebblelabs.com/invite/abcDEF123_-", {
        method: "HEAD",
      }),
    );

    expect(response.status).toBe(302);
  });

  it("GET /nonexistent returns 404", async () => {
    const response = await worker.fetch(
      new Request("https://api.freshpantry.sunpebblelabs.com/nonexistent"),
    );

    expect(response.status).toBe(404);
  });

  it("rejects a 9-char invite token (below minimum length)", async () => {
    const response = await worker.fetch(
      new Request("https://api.freshpantry.sunpebblelabs.com/invite/123456789"),
    );

    expect(response.status).toBe(400);
  });

  it("accepts a 10-char invite token (minimum valid length)", async () => {
    const response = await worker.fetch(
      new Request("https://api.freshpantry.sunpebblelabs.com/invite/1234567890"),
    );

    expect(response.status).toBe(302);
  });

  it("accepts a 160-char invite token (maximum valid length)", async () => {
    const token = "a".repeat(160);
    const response = await worker.fetch(
      new Request(`https://api.freshpantry.sunpebblelabs.com/invite/${token}`),
    );

    expect(response.status).toBe(302);
  });

  it("rejects a 161-char invite token (above maximum length)", async () => {
    const token = "a".repeat(161);
    const response = await worker.fetch(
      new Request(`https://api.freshpantry.sunpebblelabs.com/invite/${token}`),
    );

    expect(response.status).toBe(400);
  });
});
