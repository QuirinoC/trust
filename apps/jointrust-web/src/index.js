const SECURITY = {
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "X-Frame-Options": "DENY",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=(), interest-cohort=()",
  "Content-Security-Policy":
    "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; font-src 'self'; base-uri 'self'; form-action 'none'; frame-ancestors 'none'",
};

const INVITE_CODE_PATTERN = /^[A-HJ-NP-Z2-9]{6}$/;
const ISO_3166_ALPHA_2 = new Set(`
  AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ
  BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ
  CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ
  DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR
  GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY
  HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP
  KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY
  MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ
  NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY
  QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ
  TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ
  VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW
`.trim().split(/\s+/));
const PRODUCTION_SITE = {
  host: "jointrust.app",
  appId: "3S529795M9.com.collapsetechnologies.trust",
  scheme: "trust",
  label: "Trust",
};
const STAGING_SITE = {
  host: "staging.jointrust.app",
  appId: "3S529795M9.com.collapsetechnologies.trust.staging",
  scheme: "trust-staging",
  label: "Trust Staging",
};

export function siteConfig(env) {
  if (env.ENVIRONMENT !== "staging") {
    if (env.PUBLIC_HOST || env.APP_ID || env.APP_SCHEME || env.APP_LABEL) {
      throw new Error("Staging Worker configuration is present without ENVIRONMENT=staging.");
    }
    return PRODUCTION_SITE;
  }
  if (env.PUBLIC_HOST !== STAGING_SITE.host
    || env.APP_ID !== STAGING_SITE.appId
    || env.APP_SCHEME !== STAGING_SITE.scheme
    || env.APP_LABEL !== STAGING_SITE.label) {
    throw new Error("Staging Worker configuration is incomplete or crosses into production.");
  }
  return STAGING_SITE;
}

function inviteLanding(code, site) {
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
    <title>${site.label} invitation</title>
    <meta name="robots" content="noindex, nofollow" />
    <meta name="theme-color" content="#F6F8FC" />
    <meta name="color-scheme" content="light dark" />
    <link rel="canonical" href="https://${site.host}/i/${escapedCode}" />
    <link rel="icon" href="/favicon.svg" type="image/svg+xml" />
    <link rel="stylesheet" href="/styles.css?v=location-sharing" />
  </head>
  <body>
    <header class="top">
      <p class="wordmark"><a href="/" aria-label="${site.label} home"><svg class="brand-mark" viewBox="0 0 30 30" aria-hidden="true" focusable="false"><path class="mark-ink" d="M2.4 22.2 C9 18.3 12 7.2 21 5.1"/><path class="mark-blue" d="M9.6 26.4 C14.7 21.6 20.1 11.7 27.9 9.9"/></svg><span>${site.label}</span></a><span class="publisher">by Collapse Technologies</span></p>
      <nav class="legal" aria-label="Trust links"><a href="/privacy">Privacy</a></nav>
    </header>
    <main>
      <h1>Invitation to connect</h1>
      <div class="rule" aria-hidden="true"></div>
      <p class="lede">You’re invited to connect on Trust.</p>
      <p>Review the invitation in Trust. Accepting connects your accounts; sharing stays off until you choose a mode.</p>
      <p><a class="invite-action" href="${site.scheme}://invite/${escapedCode}">Open ${site.label}</a></p>
      <p class="invite-note">Opening the app does not accept the invitation. If Trust isn’t installed, use your TestFlight invitation to install it, then open this link again.</p>
      <p class="back"><a href="/">About Trust</a></p>
    </main>
  </body>
</html>`;
}

async function withSecurityHeaders(response, {
  noIndex = false,
  rewriteStagingHtml = false,
  site = PRODUCTION_SITE,
} = {}) {
  const headers = new Headers(response.headers);
  for (const [name, value] of Object.entries(SECURITY)) {
    headers.set(name, value);
  }
  if (noIndex) headers.set("X-Robots-Tag", "noindex, nofollow");
  let body = response.body;
  if (rewriteStagingHtml && headers.get("content-type")?.toLowerCase().includes("text/html")) {
    // Static public files use production canonicals. Stage HTML is deliberately
    // rewritten to stay on the staging origin and carry a document-level noindex.
    body = (await response.text())
      .replace(/<head(\s[^>]*)?>/i, (head, _attributes, _offset, fullHtml) =>
        /<meta\s+name=["']robots["']/i.test(fullHtml) ? head : `${head}<meta name="robots" content="noindex, nofollow" />`)
      .replaceAll("https://jointrust.app", `https://${site.host}`);
  }
  return new Response(body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const site = siteConfig(env);
    const staging = env.ENVIRONMENT === "staging";

    if (staging && url.hostname !== site.host) {
      return withSecurityHeaders(new Response("Not found", { status: 404 }), { noIndex: true, site });
    }

    if (!staging && url.hostname === "www.jointrust.app") {
      url.hostname = "jointrust.app";
      return Response.redirect(url.href, 301);
    }

    if (request.method === "GET" && url.pathname === "/api/region") {
      const rawCountryCode = request.cf?.country;
      const normalizedCountryCode = typeof rawCountryCode === "string"
        ? rawCountryCode.toUpperCase()
        : null;
      const countryCode = normalizedCountryCode && ISO_3166_ALPHA_2.has(normalizedCountryCode)
        ? normalizedCountryCode
        : null;
      return withSecurityHeaders(new Response(JSON.stringify({ countryCode }), {
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "Cache-Control": "private, no-store",
        },
      }), { noIndex: staging, site });
    }

    if (request.method === "GET" && url.pathname === "/.well-known/apple-app-site-association") {
      return withSecurityHeaders(new Response(JSON.stringify({
        applinks: {
          details: [{ appID: site.appId, paths: ["/i/*"] }],
        },
      }), {
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "Cache-Control": "public, max-age=3600",
        },
      }), { noIndex: staging, site });
    }

    const inviteMatch = request.method === "GET" && url.pathname.match(/^\/i\/([A-HJ-NP-Z2-9]{6})\/?$/);
    if (inviteMatch && INVITE_CODE_PATTERN.test(inviteMatch[1])) {
      return withSecurityHeaders(new Response(inviteLanding(inviteMatch[1], site), {
        headers: {
          "Content-Type": "text/html; charset=utf-8",
          "Cache-Control": "no-store",
        },
      }), { noIndex: true, site });
    }

    const asset = await env.ASSETS.fetch(request);
    const securedAsset = await withSecurityHeaders(asset, {
      noIndex: staging || url.hostname.endsWith("workers.dev"),
      rewriteStagingHtml: staging,
      site,
    });

    if (url.pathname.startsWith("/fonts/")) {
      securedAsset.headers.set("Cache-Control", "public, max-age=31536000, immutable");
    }

    return securedAsset;
  },
};
