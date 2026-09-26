const SECURITY = {
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "X-Frame-Options": "DENY",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=(), interest-cohort=()",
  "Content-Security-Policy":
    "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; font-src 'self'; base-uri 'self'; form-action 'none'; frame-ancestors 'none'",
};

const INVITE_CODE_PATTERN = /^[A-HJ-NP-Z2-9]{6}$/;
const APP_ID = "3S529795M9.com.collapsetechnologies.trust";

function inviteLanding(code) {
  const escapedCode = code.replace(/[&<>"']/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[character]);

  return `<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Trust invitation</title>
    <meta name="robots" content="noindex, nofollow" />
    <meta name="theme-color" content="#F6F8FC" />
    <meta name="color-scheme" content="light dark" />
    <link rel="canonical" href="https://jointrust.app/i/${escapedCode}" />
    <link rel="icon" href="/favicon.svg" type="image/svg+xml" />
    <link rel="stylesheet" href="/styles.css?v=together-lines" />
  </head>
  <body>
    <header class="top">
      <p class="wordmark"><a href="/" aria-label="Trust home"><svg class="brand-mark" viewBox="0 0 30 30" aria-hidden="true" focusable="false"><path class="mark-ink" d="M2.4 22.2 C9 18.3 12 7.2 21 5.1"/><path class="mark-blue" d="M9.6 26.4 C14.7 21.6 20.1 11.7 27.9 9.9"/></svg><span>Trust</span></a><span class="publisher">by Collapse Technologies</span></p>
      <nav class="legal" aria-label="Trust links"><a href="/privacy">Privacy</a></nav>
    </header>
    <main>
      <h1>Invitation to connect</h1>
      <div class="rule" aria-hidden="true"></div>
      <p class="lede">You’re invited to connect on Trust.</p>
      <p>Review the invitation in Trust. Accepting connects your accounts; sharing stays off until you choose a mode.</p>
      <p><a class="invite-action" href="trust://invite/${escapedCode}">Open Trust</a></p>
      <p class="invite-note">Opening the app does not accept the invitation. If Trust isn’t installed, use your TestFlight invitation to install it, then open this link again.</p>
      <p class="back"><a href="/">About Trust</a></p>
    </main>
  </body>
</html>`;
}

function withSecurityHeaders(response, { noIndex = false } = {}) {
  const headers = new Headers(response.headers);
  for (const [name, value] of Object.entries(SECURITY)) {
    headers.set(name, value);
  }
  if (noIndex) headers.set("X-Robots-Tag", "noindex, nofollow");
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.hostname === "www.jointrust.app") {
      url.hostname = "jointrust.app";
      return Response.redirect(url.href, 301);
    }

    if (request.method === "GET" && url.pathname === "/.well-known/apple-app-site-association") {
      return withSecurityHeaders(new Response(JSON.stringify({
        applinks: {
          details: [{ appID: APP_ID, paths: ["/i/*"] }],
        },
      }), {
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "Cache-Control": "public, max-age=3600",
        },
      }));
    }

    const inviteMatch = request.method === "GET" && url.pathname.match(/^\/i\/([A-HJ-NP-Z2-9]{6})\/?$/);
    if (inviteMatch && INVITE_CODE_PATTERN.test(inviteMatch[1])) {
      return withSecurityHeaders(new Response(inviteLanding(inviteMatch[1]), {
        headers: {
          "Content-Type": "text/html; charset=utf-8",
          "Cache-Control": "no-store",
        },
      }), { noIndex: true });
    }

    const asset = await env.ASSETS.fetch(request);
    const securedAsset = withSecurityHeaders(asset, {
      noIndex: url.hostname.endsWith("workers.dev"),
    });

    if (url.pathname.startsWith("/fonts/")) {
      securedAsset.headers.set("Cache-Control", "public, max-age=31536000, immutable");
    }

    return securedAsset;
  },
};
