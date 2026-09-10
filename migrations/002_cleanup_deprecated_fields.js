/**
 * AgriTrade+ Firestore cleanup — DESTRUCTIVE, second-phase script.
 *
 * DO NOT RUN THIS until:
 *   1. 001_standardize_schema.js has been run (for real, not dry-run)
 *      against this same project, AND
 *   2. You've verified the app works correctly reading the new
 *      standardized fields (see docs/firestore-schema-migration.md,
 *      "Verification checklist" section), AND
 *   3. You're comfortable that no code anywhere (including any other
 *      client, admin tool, or Cloud Function) still depends on the old
 *      field being present.
 *
 * WHAT THIS DOES
 * ---------------
 * Removes exactly two deprecated fields, and ONLY from documents where
 * the standardized replacement field already has a valid value (never
 * deletes an old field if the new one is missing — that document is
 * skipped and logged instead, so you can go investigate it):
 *   - users:         deletes `fullName`      (superseded by `name`)
 *   - conversations:  deletes `farmerImage`   (superseded by `productImageUrl`)
 *
 * Nothing else is touched. This script does not delete documents, does
 * not delete any other field, and does not touch any other collection.
 *
 * SAFETY GATES
 * ------------
 * This script no-ops (prints a warning, writes nothing) unless you pass
 * BOTH flags:
 *   --confirm   "I have read the warning above and verified the new schema"
 *   --apply     "actually perform the deletes, not just preview them"
 *
 * Passing only --confirm (without --apply) runs a full dry-run preview —
 * useful to see exactly which documents would be touched before the real
 * run.
 *
 * USAGE
 * -----
 *   cd migrations
 *   node 002_cleanup_deprecated_fields.js --confirm              # preview
 *   node 002_cleanup_deprecated_fields.js --confirm --apply       # for real
 *   node 002_cleanup_deprecated_fields.js --confirm --apply --collections=users
 */

const PAGE_SIZE = 300;

// ------------------------------------------------------------------
// Safety gate — checked BEFORE loading firebase-admin or touching any
// credentials/filesystem, so this refuses to proceed as early as
// possible when run without --confirm.
// ------------------------------------------------------------------
const args = process.argv.slice(2);
const isConfirmed = args.includes('--confirm');
const isApply = args.includes('--apply');
const isDryRun = !isApply; // dry-run unless explicitly told to apply
const collectionsFlag = args.find((a) => a.startsWith('--collections='));
const onlyCollections = collectionsFlag
  ? collectionsFlag.split('=')[1].split(',').map((s) => s.trim()).filter(Boolean)
  : null;

if (!isConfirmed) {
  console.log('='.repeat(70));
  console.log('This is a DESTRUCTIVE cleanup script. It deletes fields from');
  console.log('existing Firestore documents and cannot be undone.');
  console.log('');
  console.log('Read the comment block at the top of this file first, then');
  console.log('re-run with --confirm to preview what it would delete:');
  console.log('');
  console.log('  node 002_cleanup_deprecated_fields.js --confirm');
  console.log('='.repeat(70));
  process.exit(1);
}

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

function loadServiceAccount() {
  const localKeyPath = path.join(__dirname, 'serviceAccountKey.json');
  if (fs.existsSync(localKeyPath)) {
    return require(localKeyPath);
  }
  return null;
}

const serviceAccount = loadServiceAccount();
admin.initializeApp(
  serviceAccount ? { credential: admin.credential.cert(serviceAccount) } : {}
);

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

// ------------------------------------------------------------------
// Per-collection cleanup rules.
//
// Each returns either `null` ("nothing to delete here / not safe to
// delete yet") or a plain object using FieldValue.delete() for the
// specific old field(s) to remove.
// ------------------------------------------------------------------

function cleanupUsers(data) {
  const hasName = typeof data.name === 'string' && data.name.trim() !== '';
  const hasFullName = data.fullName !== undefined;
  if (hasName && hasFullName) {
    return { fullName: FieldValue.delete() };
  }
  return null; // not safe yet — 'name' isn't populated on this doc
}

function cleanupConversations(data) {
  const hasProductImageUrl = typeof data.productImageUrl === 'string' && data.productImageUrl !== '';
  const hasFarmerImage = data.farmerImage !== undefined;
  if (hasProductImageUrl && hasFarmerImage) {
    return { farmerImage: FieldValue.delete() };
  }
  return null;
}

const CLEANUPS = {
  users: cleanupUsers,
  conversations: cleanupConversations,
};

// ------------------------------------------------------------------
// Engine (same shape as 001_standardize_schema.js — per-document
// try/catch, cursor pagination, full JSON audit log).
// ------------------------------------------------------------------

async function cleanupCollection(collectionName, computeCleanup, log) {
  const stats = { scanned: 0, deleted: 0, skipped: 0, errors: 0 };
  let lastDoc = null;

  console.log(`\n--- ${collectionName} ---`);

  while (true) {
    let query = db.collection(collectionName).orderBy(admin.firestore.FieldPath.documentId()).limit(PAGE_SIZE);
    if (lastDoc) query = query.startAfter(lastDoc.id);

    const snapshot = await query.get();
    if (snapshot.empty) break;

    for (const doc of snapshot.docs) {
      stats.scanned += 1;
      const docId = doc.id;

      try {
        const data = doc.data();
        const patch = computeCleanup(data);

        if (!patch) {
          stats.skipped += 1;
          log.push({ collection: collectionName, docId, action: 'skipped', reason: 'replacement field not confirmed present' });
          continue;
        }

        if (isApply) {
          await doc.ref.update(patch);
        }

        stats.deleted += 1;
        log.push({
          collection: collectionName,
          docId,
          action: isDryRun ? 'would_delete' : 'deleted',
          fields: Object.keys(patch),
        });
        console.log(`  ${isDryRun ? '[dry-run] would delete field(s) on' : 'deleted field(s) on'} ${collectionName}/${docId}: ${Object.keys(patch).join(', ')}`);
      } catch (err) {
        stats.errors += 1;
        log.push({ collection: collectionName, docId, action: 'error', error: String(err && err.message ? err.message : err) });
        console.error(`  ERROR ${collectionName}/${docId}:`, err && err.message ? err.message : err);
      }
    }

    lastDoc = snapshot.docs[snapshot.docs.length - 1];
    if (snapshot.docs.length < PAGE_SIZE) break;
  }

  console.log(
    `  ${collectionName}: scanned ${stats.scanned}, ${isDryRun ? 'would delete' : 'deleted'} ${stats.deleted}, skipped ${stats.skipped}, errors ${stats.errors}`
  );
  return stats;
}

async function run() {
  const targetCollections = onlyCollections || Object.keys(CLEANUPS);
  const unknown = targetCollections.filter((c) => !(c in CLEANUPS));
  if (unknown.length) {
    console.error(`Unknown collection(s) in --collections: ${unknown.join(', ')}`);
    console.error(`Valid collections: ${Object.keys(CLEANUPS).join(', ')}`);
    process.exit(1);
  }

  console.log(`AgriTrade+ deprecated-field cleanup — ${isDryRun ? 'DRY RUN (no deletes)' : 'LIVE RUN (deleting fields)'}`);
  console.log(`Target collections: ${targetCollections.join(', ')}`);

  const log = [];
  const overall = {};

  for (const collectionName of targetCollections) {
    overall[collectionName] = await cleanupCollection(collectionName, CLEANUPS[collectionName], log);
  }

  console.log('\n=== Summary ===');
  for (const [name, stats] of Object.entries(overall)) {
    console.log(`${name}: scanned ${stats.scanned}, ${isDryRun ? 'would delete' : 'deleted'} ${stats.deleted}, skipped ${stats.skipped}, errors ${stats.errors}`);
  }

  const logsDir = path.join(__dirname, 'logs');
  if (!fs.existsSync(logsDir)) fs.mkdirSync(logsDir, { recursive: true });
  const logPath = path.join(logsDir, `002-${isDryRun ? 'dryrun-' : ''}${Date.now()}.json`);
  fs.writeFileSync(logPath, JSON.stringify({ isDryRun, targetCollections, summary: overall, documents: log }, null, 2));
  console.log(`\nFull per-document log written to: ${logPath}`);

  if (isDryRun) {
    console.log('\nThis was a dry run — nothing was deleted. Re-run with --apply to actually delete.');
  }

  process.exit(0);
}

run().catch((err) => {
  console.error('Cleanup failed to run:', err);
  process.exit(1);
});
