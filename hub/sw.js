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

  /* Storage objects (photos) ARE cached, unlike the rest of Supabase. Photos used
     to live as base64 inside documents.payload, so they came along with the
     IndexedDB OfflineCache for free. Now that they are Storage URLs, a crew with
     no coverage would get blank photo slots unless we keep the bytes here.
     Stale-while-revalidate because uploads use upsert on a stable key, so a
     replaced photo can show the previous image once before the update lands. */
  if (url.hostname.includes('supabase.co') && url.pathname.includes('/storage/v1/object/')) {
    e.respondWith(
      caches.match(req).then(cached => {
        const network = fetch(req).then(res => {
          if (res.ok) caches.open(CACHE).then(c => c.put(req, res.clone()));
          return res;
        }).catch(() => cached || Response.error());
        return cached || network;
      })
    );
    return;
  }

  // Rest of the Supabase API: never cache — large data blobs that change constantly.
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
