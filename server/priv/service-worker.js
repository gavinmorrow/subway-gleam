const CACHE_NAME = "sbwy-v1";
const getCache = async () => caches.open(CACHE_NAME);

const STATIC_PATHS = [
  "stop.js",
  "stops.js",
  "style.css",
  "train.js",
  "icons/192.png",
  "icons/512.png",
];
const cacheStaticResources = async () => {
  const cache = await getCache();
  cache.addAll(STATIC_PATHS);
};
self.addEventListener("install", (event) => {
  event.waitUntil(cacheStaticResources());
  // TODO: find a way to cache templates.
  event.waitUntil(cache.add("/stops"));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(self.registration?.navigationPreload?.enable?.());
  // TODO: does the activate event need to *wait* on this
  event.waitUntil(clearPreviousCaches());
});

self.addEventListener("fetch", (event) => {
  if (
    event.request.url.includes("model_stream") ||
    event.request.url.includes("service-worker")
  )
    return;

  event.respondWith(handleRequest(event.request));
});

/** @returns {Response} */
async function handleRequest(/** @type {Request} */ req) {
  const cache = await getCache();
  const cachedResponse = await cache.match(req, { ignoreSearch: true });
  // Start the work in the background
  const networkPromise = fetch(req).then((res) => {
    console.log(`Fetching ${req.url} from network...`);
    cache.add(req, res.clone());
    return res;
  });
  if (cachedResponse) console.log(` Serving ${req.url} from cache...`);
  return cachedResponse || networkPromise;
}

async function clearPreviousCaches() {
  const keys = await caches.keys();
  await Promise.all(
    keys.map((cache) => {
      if (cache === CACHE_NAME) return;
      return caches.delete(cache);
    }),
  );
}
