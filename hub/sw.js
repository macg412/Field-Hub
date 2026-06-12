const CACHE = 'fieldhub-v3';
const STATIC = ['/dashboard.html', '/index.html', '/manifest.json', '/icon.svg',
                '/apps/storeman.html', '/apps/jobcard.html', '/apps/scoping.html',
                '/apps/fieldforms.html'];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE)
      .then(c => c.addAll(STATIC))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);

  // Navigation requests: network first, fall back to dashboard or login from cache
  if (req.mode === 'navigate') {
    e.respondWith(
      fetch(req).catch(() =>
        caches.match(url.pathname === '/' || url.pathname.includes('index') ? '/index.html' : '/dashboard.html')
      )
    );
    return;
  }

  // Same-origin static assets: cache first, update in background
  if (url.hostname === self.location.hostname) {
    e.respondWith(
      caches.match(req).then(cached => {
        const network = fetch(req).then(res => {
          if (res.ok) caches.open(CACHE).then(c => c.put(req, res.clone()));
          return res;
        }).catch(() => cached);
        return cached || network;
      })
    );
    return;
  }

  // Supabase API: never cache — responses are large data blobs that change constantly.
  // Offline data is handled by IndexedDB OfflineCache in dashboard.html.
  if (url.hostname.includes('supabase.co')) {
    e.respondWith(fetch(req).catch(() => caches.match(req) || Response.error()));
    return;
  }

  // External CDN (fonts, scripts): cache-first to support offline
  e.respondWith(
    caches.match(req).then(cached => {
      if (cached) return cached;
      return fetch(req).then(res => {
        if (res.ok) caches.open(CACHE).then(c => c.put(req, res.clone()));
        return res;
      }).catch(() => Response.error());
    })
  );
});
