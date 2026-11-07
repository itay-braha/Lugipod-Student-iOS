// Removes the Apple *development* certificates that THIS CI run created, so the account never reaches
// Apple's certificate limit ("Your account has reached the maximum number of certificates").
//
// Why it exists: automatic signing on a fresh runner has an empty keychain, so Xcode asks Apple for a new
// "Apple Development: Created via API" certificate on every run and never reuses it. They pile up.
//
// Safety (this script shares an Apple account with other projects' CI):
//   * it only deletes a certificate whose fingerprint (SHA-1 of its DER) matches a code-signing identity in
//     THIS runner's keychain, i.e. one this very run created. A certificate made by another run, another
//     repository or a person is never touched, even if it was created a second ago;
//   * only certificateType DEVELOPMENT. Distribution certificates are never deleted;
//   * it never fails the job: every problem is logged and the exit code is 0.
//
// Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (the .p8). Optional: DRY_RUN=1 (print, delete nothing),
// IDENTITIES_FILE (read `security find-identity` output from a file instead of running it; for tests).
import { execSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";

const { ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, DRY_RUN, IDENTITIES_FILE } = process.env;

/** SHA-1 fingerprints (uppercase hex) of the code-signing identities in the keychain output. */
export function fingerprints(securityOutput) {
  return new Set([...securityOutput.matchAll(/\b([0-9A-Fa-f]{40})\b/g)].map((m) => m[1].toUpperCase()));
}

/** Which of the account's certificates may be deleted: DEVELOPMENT ones whose fingerprint is local. */
export function deletable(certs, local) {
  return certs.filter((c) => {
    if (c.attributes?.certificateType !== "DEVELOPMENT") return false;
    const der = Buffer.from(c.attributes.certificateContent ?? "", "base64");
    if (!der.length) return false;
    return local.has(crypto.createHash("sha1").update(der).digest("hex").toUpperCase());
  });
}

async function main() {
  if (!ASC_KEY_ID || !ASC_ISSUER_ID || !ASC_KEY_PATH) return console.log("cert cleanup: missing ASC env, skipping");

  const raw = IDENTITIES_FILE
    ? fs.readFileSync(IDENTITIES_FILE, "utf8")
    : execSync("security find-identity -p codesigning", { encoding: "utf8" });
  const local = fingerprints(raw);
  if (local.size === 0) return console.log("cert cleanup: no code-signing identities on this machine, nothing to remove");

  const b64 = (b) => Buffer.from(b).toString("base64url");
  const now = Math.floor(Date.now() / 1000);
  const head = b64(JSON.stringify({ alg: "ES256", kid: ASC_KEY_ID, typ: "JWT" }));
  const body = b64(JSON.stringify({ iss: ASC_ISSUER_ID, iat: now, exp: now + 600, aud: "appstoreconnect-v1" }));
  const sig = crypto.sign("sha256", Buffer.from(`${head}.${body}`), { key: fs.readFileSync(ASC_KEY_PATH), dsaEncoding: "ieee-p1363" });
  const auth = { Authorization: `Bearer ${head}.${body}.${b64(sig)}` };

  const list = await fetch("https://api.appstoreconnect.apple.com/v1/certificates?limit=200", { headers: auth });
  if (!list.ok) return console.log(`cert cleanup: listing failed (HTTP ${list.status}), skipping`);
  const { data } = await list.json();

  const mine = deletable(data ?? [], local);
  console.log(`cert cleanup: ${local.size} local identities, ${data?.length ?? 0} certificates on the account, ${mine.length} created by this run`);
  for (const c of mine) {
    if (DRY_RUN) { console.log(`  would revoke ${c.id} (${c.attributes.name})`); continue; }
    const del = await fetch(`https://api.appstoreconnect.apple.com/v1/certificates/${c.id}`, { method: "DELETE", headers: auth });
    console.log(`  revoked ${c.id}: HTTP ${del.status}`);
  }
}

if (import.meta.url === `file:///${process.argv[1]?.replace(/\\/g, "/")}` || process.argv[1]?.endsWith("revoke-own-certs.mjs")) {
  main().catch((e) => console.log(`cert cleanup: ${e.message} (ignored)`)).finally(() => { process.exitCode = 0; });
}
