import { describe, expect, it } from "vitest";
import worker from "../src/index";

describe("fresh-pantry-api", () => {
  it("returns health status", async () => {
    const response = await worker.fetch(new Request("https://api.fresh-pantry.kunish.eu.org/health"));

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      service: "fresh-pantry-api",
      ok: true,
    });
  });

  it("redirects valid invite tokens to the mobile deep link", async () => {
    const response = await worker.fetch(
      new Request("https://api.fresh-pantry.kunish.eu.org/invite/abcDEF123_-"),
    );

    expect(response.status).toBe(302);
    expect(response.headers.get("location")).toBe(
      "com.kunish.freshpantry://invite/abcDEF123_-",
    );
  });

  it("returns an HTML invite fallback for browser requests", async () => {
    const response = await worker.fetch(
      new Request("https://api.fresh-pantry.kunish.eu.org/invite/abcDEF123_-", {
        headers: { accept: "text/html" },
      }),
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("text/html; charset=utf-8");
    await expect(response.text()).resolves.toContain(
      'href="com.kunish.freshpantry://invite/abcDEF123_-"',
    );
  });

  it("rejects malformed invite tokens", async () => {
    const response = await worker.fetch(
      new Request("https://api.fresh-pantry.kunish.eu.org/invite/not valid"),
    );

    expect(response.status).toBe(400);
    await expect(response.text()).resolves.toContain("Invalid invite token");
  });

  it("rejects malformed percent-encoded invite tokens", async () => {
    const response = await worker.fetch(
      new Request("https://api.fresh-pantry.kunish.eu.org/invite/%E0%A4%A"),
    );

    expect(response.status).toBe(400);
    await expect(response.text()).resolves.toContain("Invalid invite token");
  });

  it("returns 405 for POST /health", async () => {
    const response = await worker.fetch(
      new Request("https://api.fresh-pantry.kunish.eu.org/health", {
        method: "POST",
      }),
    );

    expect(response.status).toBe(405);
    expect(response.headers.get("allow")).toBe("GET, HEAD");
  });

  it("returns 405 for POST /invite/<token>", async () => {
    const response = await worker.fetch(
      new Request("https://api.fresh-pantry.kunish.eu.org/invite/abcDEF123_-", {
        method: "POST",
      }),
    );

    expect(response.status).toBe(405);
    expect(response.headers.get("allow")).toBe("GET, HEAD");
  });
});
