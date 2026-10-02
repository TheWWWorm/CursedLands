// Serves the exported Web build from the static asset store.
//
// Assets above Cloudflare's 25 MiB limit are stored as sequential .part0,
// .part1, ... files and listed in parts.json with their total size. This
// streams them back together under the original name with a Content-Length,
// so the loading bar can show progress, and a missing part fails instead of
// ending in a short file. The parts are stored uncompressed: Cloudflare
// negotiates its own Content-Encoding and strips one set here.
//
// The game reads your files through SharedArrayBuffer, which needs a
// cross-origin isolated page, so every response gets the isolation headers.
import parts from './parts.json';

const CONTENT_TYPES = {
  wasm: 'application/wasm',
  js: 'text/javascript; charset=utf-8',
  json: 'application/json; charset=utf-8',
  pck: 'application/octet-stream',
};

function isolate(headers) {
  headers.set('Cross-Origin-Opener-Policy', 'same-origin');
  headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
  headers.set('Cross-Origin-Resource-Policy', 'same-origin');
  headers.set('X-Content-Type-Options', 'nosniff');
  return headers;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.protocol === 'http:' && url.hostname !== 'localhost' && url.hostname !== '127.0.0.1') {
      url.protocol = 'https:';
      return Response.redirect(url.href, 308);
    }
    const entry = parts[url.pathname];
    if (!entry) {
      const response = await env.ASSETS.fetch(request);
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: isolate(new Headers(response.headers)),
      });
    }
    const headers = isolate(new Headers());
    headers.set('Content-Type', CONTENT_TYPES[url.pathname.split('.').pop().toLowerCase()] || 'application/octet-stream');
    headers.set('Content-Length', String(entry.size));
    // index.wasm keeps its name across exports; the service worker's install
    // must not pick up a stale copy from the HTTP cache.
    headers.set('Cache-Control', 'no-cache');
    if (request.method === 'HEAD') return new Response(null, { headers });
    if (request.method !== 'GET') return new Response('Method not allowed', { status: 405, headers });
    let index = 0;
    let reader = null;
    const body = new ReadableStream({
      async pull(controller) {
        try {
          while (true) {
            if (!reader) {
              if (index === entry.count) {
                controller.close();
                return;
              }
              const response = await env.ASSETS.fetch(new URL(`${url.pathname}.part${index++}`, url.origin));
              if (!response.ok) throw new Error('Incomplete engine export');
              reader = response.body.getReader();
            }
            const chunk = await reader.read();
            if (!chunk.done) {
              controller.enqueue(chunk.value);
              return;
            }
            reader.releaseLock();
            reader = null;
          }
        } catch (error) {
          controller.error(error);
        }
      },
      async cancel() {
        if (reader) await reader.cancel();
      },
    });
    return new Response(body, { headers });
  },
};
