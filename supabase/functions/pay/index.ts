// Grace Shop · paiement T-Money / Flooz dans l'application (via PayGate Global).
// La clé PayGate reste ici, côté serveur (secret PAYGATE_TOKEN), jamais dans l'application.
// Actions : ?action=config | start | check | callback (appelé par PayGate).
import { createClient } from "npm:@supabase/supabase-js@2";

const PG = "https://paygateglobal.com/api";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

const DEFAULT_ZONES: [string, number][] = [
  ["Centre · Nyékonakpoè · Kodjoviakopé · Bè", 1000],
  ["Tokoin · Hédzranawoé · Amoutiévé · Bè-Kpota", 1000],
  ["Adidogomé · Djidjolé · Agbalépédo · Totsi", 1500],
  ["Agoè · Avédji · Kégué · Légbassito", 1500],
  ["Baguida · Avépozo · Kpogan · Sagbado", 2000],
  ["Hors de Lomé (Tsévié, Aného, Kpalimé…)", 3000],
];

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const TOKEN = Deno.env.get("PAYGATE_TOKEN") || "";

// Recalcule le montant à partir du catalogue en base : le prix ne vient jamais du téléphone.
async function amountOf(order: any): Promise<number> {
  const { data } = await db.from("shop").select("data").eq("id", 1).maybeSingle();
  const shop = data?.data || {};
  const S = shop.settings || {};
  const byId = new Map((shop.products || []).map((p: any) => [p.id, p]));
  let sub = 0;
  for (const it of order.items || []) {
    const p: any = byId.get(it.id);
    if (!p) throw new Error("article_inconnu");
    sub += Math.round(+p.price) * Math.max(1, Math.min(99, Math.round(+it.qty || 1)));
  }
  let disc = 0;
  if (order.promo) {
    const c = (S.codes || []).find((x: any) => String(x.code).toUpperCase() === String(order.promo).toUpperCase());
    if (c) disc = Math.round((sub * +c.pct) / 100);
  }
  let fee = 0;
  if (order.mode === "livraison") {
    const zones: [string, number][] = S.zones && S.zones.length ? S.zones : DEFAULT_ZONES;
    const z = zones.find((x) => x[0] === order.zone);
    fee = z ? +z[1] : +S.delivery || 0;
    if (+S.freeFrom && sub >= +S.freeFrom) fee = 0;
  }
  return Math.max(0, sub - disc + fee);
}

async function pgStatus(ident: string) {
  const r = await fetch(PG + "/v2/status", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ auth_token: TOKEN, identifier: ident }),
  });
  return await r.json().catch(() => ({}));
}

// Vérifie auprès de PayGate et met la commande à jour. Ne fait jamais confiance au téléphone ni au rappel seul.
async function refresh(order: any) {
  if (!order.pay_ident || order.pay_status === "payé") return order.pay_status;
  const st = await pgStatus(order.pay_ident);
  const code = Number(st.status);
  if (code === 0) {
    await db.from("orders").update({
      pay_status: "payé",
      paid_at: new Date().toISOString(),
      pay_ref: st.payment_reference ? String(st.payment_reference).slice(0, 40) : order.pay_ref,
      tx_reference: st.tx_reference ? String(st.tx_reference) : order.tx_reference,
      status: ["nouvelle", "confirmée"].includes(order.status) ? "payée" : order.status,
    }).eq("id", order.id);
    return "payé";
  }
  if (code === 4 || code === 6) {
    await db.from("orders").update({ pay_status: "échoué" }).eq("id", order.id);
    return "échoué";
  }
  return "en cours";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const url = new URL(req.url);
  let body: any = {};
  try {
    const ct = req.headers.get("content-type") || "";
    const txt = await req.text();
    body = ct.includes("json") ? JSON.parse(txt || "{}") : Object.fromEntries(new URLSearchParams(txt));
  } catch { body = {}; }
  const action = url.searchParams.get("action") || body.action || "";

  if (action === "config") return json({ auto: !!TOKEN });
  if (!TOKEN) return json({ error: "not_configured" });

  // Rappel de PayGate : on retrouve la commande puis on vérifie le statut nous-mêmes.
  if (action === "callback") {
    const ident = String(body.identifier || "");
    if (!ident) return json({ ok: false });
    const { data: o } = await db.from("orders").select("*").eq("pay_ident", ident).maybeSingle();
    if (o) await refresh(o);
    return json({ ok: true });
  }

  const ref = String(body.ref || "").slice(0, 20);
  const key = String(body.key || "");
  const { data: order } = await db.from("orders").select("*").eq("ref", ref).maybeSingle();
  if (!order || !key || order.client_key !== key) return json({ error: "commande_introuvable" }, 404);

  if (action === "check") return json({ pay_status: await refresh(order) });

  if (action === "start") {
    if (order.pay_status === "payé") return json({ pay_status: "payé" });
    const network = body.network === "FLOOZ" ? "FLOOZ" : "TMONEY";
    let d = String(body.phone || "").replace(/\D/g, "");
    if (d.startsWith("00228")) d = d.slice(5); else if (d.startsWith("228") && d.length > 8) d = d.slice(3);
    if (d.length !== 8) return json({ error: "numero_invalide" }, 400);
    let amount: number;
    try { amount = await amountOf(order); } catch { return json({ error: "panier_invalide" }, 400); }
    if (amount < 100) return json({ error: "montant_invalide" }, 400);
    const ident = (ref + "-" + Date.now().toString(36)).slice(0, 40);
    const r = await fetch(PG + "/v1/pay", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        auth_token: TOKEN, phone_number: d, amount, identifier: ident, network,
        description: "Commande " + ref,
      }),
    });
    const res = await r.json().catch(() => ({}));
    if (Number(res.status) !== 0) return json({ error: "paygate_" + (res.status ?? "erreur") }, 502);
    await db.from("orders").update({
      pay_status: "en cours", pay_method: network === "FLOOZ" ? "Flooz" : "T-Money", pay_phone: d,
      pay_ident: ident, tx_reference: res.tx_reference ? String(res.tx_reference) : null,
      total: amount,
    }).eq("id", order.id);
    return json({ pay_status: "en cours", amount });
  }
  return json({ error: "action_inconnue" }, 400);
});
