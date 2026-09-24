const SECURITY = {
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "strict-origin-when-cross-origin",
  "X-Frame-Options": "DENY",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=(), interest-cohort=()",
  "Content-Security-Policy":
    "default-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'; font-src 'self'; base-uri 'self'; form-action 'none'; frame-ancestors 'none'",
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.hostname === "www.jointrust.app") {
      url.hostname = "jointrust.app";
      return Response.redirect(url.href, 301);
    }

    const asset = await env.ASSETS.fetch(request);
    const headers = new Headers(asset.headers);
    for (const [name, value] of Object.entries(SECURITY)) {
      headers.set(name, value);
    }

    if (url.hostname.endsWith("workers.dev")) {
      headers.set("X-Robots-Tag", "noindex, nofollow");
    }

    if (url.pathname.startsWith("/fonts/")) {
      headers.set("Cache-Control", "public, max-age=31536000, immutable");
    }

    return new Response(asset.body, {
      status: asset.status,
      statusText: asset.statusText,
      headers,
    });
  },
};
