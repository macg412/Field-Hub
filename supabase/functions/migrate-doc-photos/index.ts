/**
 * Move base64 photos out of documents.payload into the doc-photos bucket.
 *
 * Runs here rather than on a developer machine so the image data never leaves
 * Supabase's own network. Deliberately not done in SQL: Postgres cannot upload
 * bytes to Storage, and enabling the `http` extension to make it possible would
 * permanently widen the database's security surface.
 *
 * Safety properties, most important first:
 *  - A payload is rewritten ONLY if every photo in it uploaded AND was verified
 *    present in the bucket at the expected byte length. Any failure leaves that
 *    document completely untouched for a later retry.
 *  - Uploads all land before any payload is modified, so an interrupted run can
 *    never lose an image.
 *  - Idempotent: a document already in doc_photo_migration is skipped, and a
 *    repeated upload is an upsert to the same deterministic path.
 *  - The payload write goes through migrate_doc_payload(), which suppresses the
 *    updated_at trigger so documents are not all restamped "edited just now".
 *
 * signatureData is intentionally left inline: ~34 kB each, about 1% of the total.
 * Moving it would add failure modes for almost no space.
 *
 * POST { limit?: number, dryRun?: boolean }
 */
import { createClient } from "jsr:@supabase/supabase-js@2";

/**
 * verify_jwt only proves the caller holds a valid JWT, and the public anon key is
 * one -- so for a maintenance function that rewrites every document, that is not a
 * meaningful gate on its own. The deployed copy carried a random token baked into
 * its source (the source is never served, unlike the anon key).
 *
 * This repository is PUBLIC, so the literal must not live here. Set it as a
 * function secret instead:  supabase secrets set MIGRATION_GUARD_TOKEN=...
 *
 * Retained for reference only: this function was deleted after the migration
 * completed. A privileged one-shot endpoint should not outlive its purpose.
 */
const GUARD_TOKEN = Deno.env.get("MIGRATION_GUARD_TOKEN") ?? "";

const BUCKET = "doc-photos";
const ARRAY_KEYS = ["photoBefore", "photoAfter", "photoAdd"]; // [dataUrl | null, ...]
const OBJECT_KEYS = ["photoPages", "inlinePhotos"]; // [{ dataUrl, mimeType }, ...]

const EXT: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/jpg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};

function isDataUrl(v: unknown): v is string {
  return typeof v === "string" && v.startsWith("data:");
}

/** "data:image/jpeg;base64,AAAA" -> { mime, bytes } */
function decodeDataUrl(dataUrl: string): { mime: string; bytes: Uint8Array } {
  const comma = dataUrl.indexOf(",");
  if (comma < 0) throw new Error("malformed data URL (no comma)");
  const header = dataUrl.slice(5, comma);
  const mime = header.split(";")[0] || "image/jpeg";
  if (!header.includes("base64")) throw new Error("unsupported encoding: " + header);
  const bin = atob(dataUrl.slice(comma + 1));
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return { mime, bytes };
}

type Plan = { path: string; chars: number; apply: (url: string) => void; read: () => unknown };

/** Every base64 photo in this payload, as a list of read/write accessors. */
function planFor(payload: Record<string, unknown>): Plan[] {
  const plan: Plan[] = [];
  for (const key of ARRAY_KEYS) {
    const arr = payload[key];
    if (!Array.isArray(arr)) continue;
    arr.forEach((v, i) => {
      if (!isDataUrl(v)) return;
      plan.push({
        path: key + "." + i,
        chars: v.length,
        read: () => arr[i],
        apply: (url) => { arr[i] = url; },
      });
    });
  }
  for (const key of OBJECT_KEYS) {
    const arr = payload[key];
    if (!Array.isArray(arr)) continue;
    arr.forEach((o, i) => {
      const rec = o as Record<string, unknown> | null;
      if (!rec || !isDataUrl(rec.dataUrl)) return;
      plan.push({
        path: key + "." + i,
        chars: (rec.dataUrl as string).length,
        read: () => rec.dataUrl,
        apply: (url) => { rec.dataUrl = url; },
      });
    });
  }
  return plan;
}

Deno.serve(async (req) => {
  let limit = 2;
  let dryRun = false;
  try {
    const body = await req.json();
    if (typeof body?.limit === "number") limit = body.limit;
    if (body?.dryRun === true) dryRun = true;
    if (body?.token !== GUARD_TOKEN) return json({ ok: false, error: "forbidden" }, 403);
  } catch { return json({ ok: false, error: "forbidden" }, 403); }

  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const { data: ids, error: batchErr } = await sb.rpc("next_photo_migration_batch", { p_limit: limit });
  if (batchErr) return json({ ok: false, stage: "batch", error: batchErr.message }, 500);

  const results: unknown[] = [];

  for (const docId of (ids ?? []) as string[]) {
    const { data: doc, error: readErr } = await sb
      .from("documents").select("id, payload").eq("id", docId).single();
    if (readErr) {
      results.push({ docId, ok: false, stage: "read", error: readErr.message });
      continue;
    }

    const payload = doc?.payload as Record<string, unknown> | null;
    if (!payload || typeof payload !== "object") {
      if (!dryRun) await record(sb, docId, {}, 0, 0, 0);
      results.push({ docId, ok: true, photos: 0, note: "no payload" });
      continue;
    }

    const payloadBefore = JSON.stringify(payload).length;
    const plan = planFor(payload);

    if (!plan.length) {
      if (!dryRun) await record(sb, docId, {}, 0, 0, payloadBefore);
      results.push({ docId, ok: true, photos: 0, note: "no base64 photos", payloadBefore });
      continue;
    }

    if (dryRun) {
      results.push({
        docId, ok: true, dryRun: true, photos: plan.length, payloadBefore,
        base64Chars: plan.reduce((n, p) => n + p.chars, 0),
        paths: plan.map((p) => p.path),
      });
      continue;
    }

    // ---- upload and verify every photo before touching the payload ----
    const moved: Record<string, string> = {};
    let bytesUploaded = 0;
    let failure: string | null = null;

    for (const item of plan) {
      const value = item.read();
      if (!isDataUrl(value)) { failure = item.path + ": not a data URL"; break; }

      let mime: string, bytes: Uint8Array;
      try { ({ mime, bytes } = decodeDataUrl(value)); }
      catch (e) { failure = item.path + ": " + (e as Error).message; break; }

      const objectPath = docId + "/" + item.path + "." + (EXT[mime] ?? "jpg");
      const { error: upErr } = await sb.storage.from(BUCKET)
        .upload(objectPath, bytes, { contentType: mime, upsert: true });
      if (upErr) { failure = item.path + ": upload failed: " + upErr.message; break; }

      // Confirm it is really in the bucket at the right length before trusting it.
      const slash = objectPath.lastIndexOf("/");
      const dir = objectPath.slice(0, slash);
      const name = objectPath.slice(slash + 1);
      const { data: listed, error: lsErr } = await sb.storage.from(BUCKET)
        .list(dir, { search: name, limit: 100 });
      if (lsErr) { failure = item.path + ": verify failed: " + lsErr.message; break; }
      const found = listed?.find((o) => o.name === name);
      if (!found) { failure = item.path + ": not found after upload"; break; }
      const size = (found.metadata as Record<string, unknown> | null)?.size as number | undefined;
      if (size !== bytes.length) {
        failure = item.path + ": size mismatch (bucket " + size + " vs " + bytes.length + ")";
        break;
      }

      moved[item.path] = sb.storage.from(BUCKET).getPublicUrl(objectPath).data.publicUrl;
      bytesUploaded += bytes.length;
    }

    if (failure) {
      // Document left exactly as it was. Uploads already done are harmless -- the
      // identical upsert on retry overwrites them.
      results.push({ docId, ok: false, stage: "upload", error: failure, photos: plan.length });
      continue;
    }

    for (const item of plan) item.apply(moved[item.path]);

    const { error: wrErr } = await sb.rpc("migrate_doc_payload", { p_doc_id: docId, p_payload: payload });
    if (wrErr) {
      results.push({ docId, ok: false, stage: "write", error: wrErr.message, photos: plan.length });
      continue;
    }

    await record(sb, docId, moved, plan.length, bytesUploaded, payloadBefore);
    results.push({
      docId, ok: true, photos: plan.length, bytesUploaded,
      payloadBefore, payloadAfter: JSON.stringify(payload).length,
    });
  }

  const { count: documentsTotal } = await sb
    .from("documents").select("id", { count: "exact", head: true });
  const { count: migratedTotal } = await sb
    .from("doc_photo_migration").select("doc_id", { count: "exact", head: true });

  return json({
    ok: true, dryRun,
    processed: results.length,
    migratedTotal: migratedTotal ?? null,
    documentsTotal: documentsTotal ?? null,
    remaining: (documentsTotal ?? 0) - (migratedTotal ?? 0),
    failures: results.filter((r) => !(r as { ok: boolean }).ok).length,
    results,
  });
});

async function record(
  sb: ReturnType<typeof createClient>,
  docId: string,
  photos: Record<string, string>,
  count: number,
  bytes: number,
  payloadBefore: number,
) {
  await sb.from("doc_photo_migration").upsert({
    doc_id: docId,
    photos,
    photo_count: count,
    bytes_uploaded: bytes,
    payload_before: payloadBefore,
    rewritten_at: new Date().toISOString(),
  }, { onConflict: "doc_id" });
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
