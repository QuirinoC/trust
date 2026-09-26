import assert from "node:assert/strict";
import test from "node:test";
import worker from "../src/index.js";

function environment() {
  return {
    ASSETS: {
      fetch: async () => new Response("not found", { status: 404 }),
    },
  };
}

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
