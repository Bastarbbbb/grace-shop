// Hors connexion : garde la boutique en cache. En ligne : toujours la dernière version (revalidée à chaque visite).
const CACHE="grace-shop-v14";
const CORE=["./","index.html","config.js","manifest.webmanifest","data/shop.json","icons/icon-192.png","icons/icon-512.png"];
self.addEventListener("install",e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(CORE)).catch(()=>{}));self.skipWaiting();});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k)))));self.clients.claim();});
self.addEventListener("fetch",e=>{
  if(e.request.method!=="GET") return;
  const same=new URL(e.request.url).origin===location.origin;
  const req=same?new Request(e.request.url,{cache:"no-cache",credentials:"same-origin"}):e.request;
  e.respondWith(fetch(req).then(r=>{ if(same&&r.ok){const copy=r.clone();caches.open(CACHE).then(c=>c.put(e.request,copy));} return r; }).catch(()=>caches.match(e.request)));
});
