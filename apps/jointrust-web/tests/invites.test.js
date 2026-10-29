import assert from "node:assert/strict";
import test from "node:test";
import worker, { siteConfig } from "../src/index.js";

function environment() {
  return {
    ASSETS: {
      fetch: async () => new Response("not found", { status: 404 }),
    },
  };
}

function stagingEnvironment(overrides = {}) {
  return {
    ENVIRONMENT: "staging",
    PUBLIC_HOST: "staging.jointrust.app",
    APP_ID: "3S529795M9.com.collapsetechnologies.trust.staging",
    APP_SCHEME: "trust-staging",
    APP_LABEL: "Trust Staging",
    ...environment(),
    ...overrides,
  };
}

function requestWithCountry(url, country, headers = {}) {
  const request = new Request(url, { headers });
  if (country !== undefined) {
    Object.defineProperty(request, "cf", { value: { country } });
  }
  return request;
}

test("region endpoint returns only valid Cloudflare country codes without caching", async () => {
  for (const countryCode of ["US", "GB", "BR"]) {
    const response = await worker.fetch(
      requestWithCountry("https://jointrust.app/api/region", countryCode),
      environment(),
    );

    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-type"), "application/json; charset=utf-8");
    assert.equal(response.headers.get("cache-control"), "private, no-store");
    assert.equal(response.headers.get("vary"), null);
    assert.deepEqual(await response.json(), { countryCode });
  }
});

test("region endpoint returns null for unavailable, unknown, and invalid edge country values", async () => {
  for (const country of [undefined, null, "XX", "T1", "USA", "1A", 12]) {
    const response = await worker.fetch(
      requestWithCountry("https://jointrust.app/api/region", country, { "CF-IPCountry": "US" }),
      environment(),
    );

    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { countryCode: null });
  }
});

test("staging region endpoint is public, noindex, uncached, and isolated to the staging host", async () => {
  const response = await worker.fetch(
    requestWithCountry("https://staging.jointrust.app/api/region", "gb"),
    stagingEnvironment(),
  );

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("x-robots-tag"), "noindex, nofollow");
  assert.equal(response.headers.get("cache-control"), "private, no-store");
  assert.equal(response.headers.get("vary"), null);
  assert.deepEqual(await response.json(), { countryCode: "GB" });

  const crossDomain = await worker.fetch(
    requestWithCountry("https://jointrust.app/api/region", "US"),
    stagingEnvironment(),
  );
  assert.equal(crossDomain.status, 404);
  assert.equal(crossDomain.headers.get("x-robots-tag"), "noindex, nofollow");
  assert.equal(await crossDomain.text(), "Not found");
});

test("invite landing makes acceptance explicit and links to the app", async () => {
  const response = await worker.fetch(
    new Request("https://jointrust.app/i/ABC234"),
    environment(),
  );
  const html = await response.text();

  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type"), /^text\/html; charset=utf-8$/);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.equal(response.headers.get("x-robots-tag"), "noindex, nofollow");
  assert.match(html, /href="trust:\/\/invite\/ABC234"/);
  assert.match(html, /Invitation to connect/);
  assert.match(html, /sharing stays off until you choose a mode/);
  assert.match(html, /use your TestFlight invitation to install it/);
  assert.doesNotMatch(html, /invite-fallback|invite-code|Need a fallback code|save this code/i);
  assert.doesNotMatch(html, /Join your circle/);
  assert.match(html, /does not accept the invitation/);
  assert.doesNotMatch(html, /http-equiv="refresh"|<script\b/i);
});

test("invite landing rejects malformed codes without reflecting them", async () => {
  const response = await worker.fetch(
    new Request("https://jointrust.app/i/%3Cscript%3E"),
    environment(),
  );
  const body = await response.text();

  assert.equal(response.status, 404);
  assert.doesNotMatch(body, /<script>|trust:\/\/invite/);
});

test("Apple association endpoint returns JSON directly with the expected app and path", async () => {
  const response = await worker.fetch(
    new Request("https://jointrust.app/.well-known/apple-app-site-association"),
    environment(),
  );
  const association = await response.json();

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "application/json; charset=utf-8");
  assert.equal(response.headers.get("location"), null);
  assert.deepEqual(association, {
    applinks: {
      details: [{ appID: "3S529795M9.com.collapsetechnologies.trust", paths: ["/i/*"] }],
    },
  });
});

test("staging invite uses staging identity, app scheme, canonical origin, and noindex", async () => {
  const response = await worker.fetch(
    new Request("https://staging.jointrust.app/i/ABC234"),
    stagingEnvironment(),
  );
  const html = await response.text();

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("x-robots-tag"), "noindex, nofollow");
  assert.match(html, /<meta name="robots" content="noindex, nofollow"/);
  assert.match(html, /<title>Trust Staging invitation<\/title>/);
  assert.match(html, /href="https:\/\/staging\.jointrust\.app\/i\/ABC234"/);
  assert.match(html, /href="trust-staging:\/\/invite\/ABC234"/);
  assert.doesNotMatch(html, /https:\/\/jointrust\.app\/i\/ABC234|href="trust:\/\/invite/);
});

test("staging association points only at the staging app and response is noindex", async () => {
  const response = await worker.fetch(
    new Request("https://staging.jointrust.app/.well-known/apple-app-site-association"),
    stagingEnvironment(),
  );
  const association = await response.json();

  assert.equal(response.headers.get("x-robots-tag"), "noindex, nofollow");
  assert.deepEqual(association, {
    applinks: {
      details: [{ appID: "3S529795M9.com.collapsetechnologies.trust.staging", paths: ["/i/*"] }],
    },
  });
});

test("staging blocks cross-domain requests and rejects missing or production config", async () => {
  const response = await worker.fetch(
    new Request("https://jointrust.app/i/ABC234"),
    stagingEnvironment(),
  );
  assert.equal(response.status, 404);
  assert.equal(response.headers.get("x-robots-tag"), "noindex, nofollow");

  assert.throws(() => siteConfig(stagingEnvironment({ APP_ID: "3S529795M9.com.collapsetechnologies.trust" })), /crosses into production/);
  assert.throws(() => siteConfig(stagingEnvironment({ PUBLIC_HOST: "jointrust.app" })), /crosses into production/);
  assert.throws(() => siteConfig({ ENVIRONMENT: "staging" }), /incomplete or crosses into production/);
  assert.throws(() => siteConfig({ ...stagingEnvironment(), ENVIRONMENT: "production" }), /present without ENVIRONMENT=staging/);
  assert.throws(() => siteConfig({ PUBLIC_HOST: "staging.jointrust.app" }), /present without ENVIRONMENT=staging/);
});

test("all staged static asset responses carry noindex and staging canonical URLs", async () => {
  const env = stagingEnvironment({
    ASSETS: {
      fetch: async () => new Response('<!doctype html><html><head><link rel="canonical" href="https://jointrust.app/"></head><body>stage</body></html>', {
        headers: { "Content-Type": "text/html; charset=utf-8" },
      }),
    },
  });
  const response = await worker.fetch(new Request("https://staging.jointrust.app/"), env);
  const html = await response.text();

  assert.equal(response.headers.get("x-robots-tag"), "noindex, nofollow");
  assert.match(html, /name="robots" content="noindex, nofollow"/);
  assert.match(html, /https:\/\/staging\.jointrust\.app\//);
  assert.doesNotMatch(html, /https:\/\/jointrust\.app\//);
});

test("font assets retain immutable caching in production and staging", async () => {
  for (const { url, env } of [
    { url: "https://jointrust.app/fonts/test.woff2", env: environment() },
    { url: "https://staging.jointrust.app/fonts/test.woff2", env: stagingEnvironment() },
  ]) {
    const response = await worker.fetch(new Request(url), env);

    assert.equal(response.status, 404);
    assert.equal(response.headers.get("cache-control"), "public, max-age=31536000, immutable");
    assert.equal(response.headers.get("x-robots-tag"), url.includes("staging.") ? "noindex, nofollow" : null);
  }
});
