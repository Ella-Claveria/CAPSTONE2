/**
 * AgriTrade+ Firestore schema-standardization migration.
 *
 * WHAT THIS DOES
 * ---------------
 * For each document in the target collections, it adds any missing
 * standardized fields using safe defaults, or copies an existing value
 * into a new standardized field when one is clearly derivable. It NEVER:
 *   - deletes a field
 *   - renames a field (old fields are left in place, untouched)
 *   - overwrites a field that already has a valid value
 *   - touches a document it doesn't need to change
 *
 * Every write is a Firestore `.update()` with only the specific fields
 * that need to change — `.update()` never touches fields you don't name,
 * so existing data (including fields this script doesn't know about) is
 * never at risk. See ../docs/firestore-schema-migration.md for the full
 * inventory of what's inconsistent today and why each patch below exists.
 *
 * USAGE
 * -----
 *   cd migrations
 *   npm install
 *   npm run migrate:dry-run                  # preview only, writes nothing
 *   npm run migrate                           # apply for real
 *
 *   # Scope to one or more collections while verifying (recommended the
 *   # first time you run this against a real project):
 *   node 001_standardize_schema.js --dry-run --collections=users
 *   node 001_standardize_schema.js --collections=users,products
 *
 * See README.md for how to get a service account key. Point it at a
 * dev/staging project first if you have one.
 *
 * SAFETY
 * ------
 * - Dry-run by default is NOT the default — pass --dry-run explicitly to
 *   preview. Read the printed summary before running for real.
 * - Every document is processed independently (own try/catch); one
 *   document failing never stops the rest of the migration.
 * - Every scanned document's outcome (updated / skipped / errored) is
 *   logged to the console AND to a timestamped JSON file under ./logs/
 *   for a durable audit trail.
 * - Documents are paginated (cursor-based), so this is safe to run
 *   against collections too large to fit in memory at once.
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const PAGE_SIZE = 300;

// ------------------------------------------------------------------
// CLI flags
// ------------------------------------------------------------------
const args = process.argv.slice(2);
const isDryRun = args.includes('--dry-run');
const collectionsFlag = args.find((a) => a.startsWith('--collections='));
const onlyCollections = collectionsFlag
  ? collectionsFlag.split('=')[1].split(',').map((s) => s.trim()).filter(Boolean)
  : null;

// ------------------------------------------------------------------
// Firebase Admin init — same pattern as seed_data/import.js
// ------------------------------------------------------------------
function loadServiceAccount() {
  const localKeyPath = path.join(__dirname, 'serviceAccountKey.json');
  if (fs.existsSync(localKeyPath)) {
    return require(localKeyPath);
  }
  return null; // falls back to GOOGLE_APPLICATION_CREDENTIALS env var
}

const serviceAccount = loadServiceAccount();
admin.initializeApp(
  serviceAccount ? { credential: admin.credential.cert(serviceAccount) } : {}
);

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

// ------------------------------------------------------------------
// Per-collection patch functions.
//
// Each returns either `null` ("this document is already standardized,
// nothing to do") or a plain object of the SPECIFIC fields to `.update()`.
// Never build a full replacement document here — only what needs to change.
// ------------------------------------------------------------------

function computeUsersPatch(data) {
  const patch = {};

  // 'name' is the standardized display-name field (kept fresh by
  // EditProfileScreen); 'fullName' is the legacy signup-time-only field.
  // Backfill 'name' from 'fullName' where it's missing — never overwrite
  // an existing 'name'.
  const hasName = typeof data.name === 'string' && data.name.trim() !== '';
  const hasFullName = typeof data.fullName === 'string' && data.fullName.trim() !== '';
  if (!hasName && hasFullName) {
    patch.name = data.fullName.trim();
  }

  // 'isVerified' was write-only in old code paths (never set for buyers,
  // and only set for farmers approved through one specific admin screen).
  // Backfill it to mirror 'approvalStatus' wherever it's missing/invalid.
  if (typeof data.isVerified !== 'boolean') {
    patch.isVerified = data.approvalStatus === 'approved';
  }

  if (data.updatedAt === undefined) {
    patch.updatedAt = data.createdAt || FieldValue.serverTimestamp();
  }

  return Object.keys(patch).length ? patch : null;
}

function computeProductsPatch(data) {
  const patch = {};

  if (typeof data.isArchived !== 'boolean') patch.isArchived = false;
  if (typeof data.isSuspended !== 'boolean') patch.isSuspended = false;

  // Read in 3 places in the app but never written anywhere until now —
  // backfill to 0 so the "★ rating (N reviews)" UI shows a real, honest
  // empty state instead of null. ReviewService.submitReview keeps these
  // current going forward.
  if (typeof data.rating !== 'number') patch.rating = 0;
  if (typeof data.reviewCount !== 'number') patch.reviewCount = 0;

  if ((!data.imageUrl || data.imageUrl === '') && Array.isArray(data.imageUrls) && data.imageUrls.length > 0) {
    patch.imageUrl = data.imageUrls[0];
  }

  if (data.updatedAt === undefined) {
    patch.updatedAt = data.createdAt || FieldValue.serverTimestamp();
  }

  return Object.keys(patch).length ? patch : null;
}

const VALID_ORDER_STATUSES = ['pending', 'confirmed', 'completed', 'rejected'];

function computeOrdersPatch(data) {
  const patch = {};

  if (!VALID_ORDER_STATUSES.includes(data.status)) {
    patch.status = 'pending';
  }

  if (data.updatedAt === undefined) {
    patch.updatedAt = data.createdAt || FieldValue.serverTimestamp();
  }

  return Object.keys(patch).length ? patch : null;
}

function computeConversationsPatch(data) {
  const patch = {};

  if (data.productId === undefined) patch.productId = '';
  if (data.productName === undefined) patch.productName = '';

  if (data.productImageUrl === undefined) {
    // 'farmerImage' was a NAMING BUG, not missing data — every existing
    // write actually put the product's image URL under that wrong key.
    // Recover the real value instead of defaulting to '' where possible.
    patch.productImageUrl = typeof data.farmerImage === 'string' ? data.farmerImage : '';
  }

  if (data.productPrice === undefined) {
    patch.productPrice = typeof data.retailPrice === 'number' ? `₱${data.retailPrice}/kilo` : '';
  }

  if (typeof data.deliveryAvailable !== 'boolean') patch.deliveryAvailable = false;
  if (typeof data.pickupOnly !== 'boolean') patch.pickupOnly = false;

  return Object.keys(patch).length ? patch : null;
}

function computeReportsPatch(data) {
  const patch = {};

  // No discriminator field exists today, so the moderation queue can't
  // tell a product report from a chat/user report apart. Infer it from
  // whichever identifying fields are already present.
  if (data.reportType === undefined) {
    if (data.productId) {
      patch.reportType = 'product';
    } else if (data.conversationId || data.reportedUserId) {
      patch.reportType = 'user';
    } else {
      patch.reportType = 'unknown';
    }
  }

  return Object.keys(patch).length ? patch : null;
}

// Collections with no actionable inconsistency found during the schema
// audit — included for visibility/completeness, not because anything
// needs to change. See docs/firestore-schema-migration.md.
function noChangesNeeded() {
  return null;
}

const MIGRATIONS = {
  users: computeUsersPatch,
  products: computeProductsPatch,
  orders: computeOrdersPatch,
  conversations: computeConversationsPatch,
  reports: computeReportsPatch,
  verificationDocs: noChangesNeeded,
  market_prices: noChangesNeeded,
  searchEvents: noChangesNeeded,
};

// ------------------------------------------------------------------
// Engine
// ------------------------------------------------------------------

async function migrateCollection(collectionName, computePatch, log) {
  const stats = { scanned: 0, updated: 0, skipped: 0, errors: 0 };
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
        const patch = computePatch(data, docId);

        if (!patch) {
          stats.skipped += 1;
          log.push({ collection: collectionName, docId, action: 'skipped', reason: 'already standardized' });
          continue;
        }

        if (!isDryRun) {
          await doc.ref.update(patch);
        }

        stats.updated += 1;
        const patchSummary = Object.fromEntries(
          Object.entries(patch).map(([k, v]) => [k, v instanceof FieldValue ? '<serverTimestamp>' : v])
        );
        log.push({
          collection: collectionName,
          docId,
          action: isDryRun ? 'would_update' : 'updated',
          fields: patchSummary,
        });
        console.log(`  ${isDryRun ? '[dry-run] would update' : 'updated'} ${collectionName}/${docId}: ${Object.keys(patch).join(', ')}`);
      } catch (err) {
        stats.errors += 1;
        log.push({ collection: collectionName, docId, action: 'error', error: String(err && err.message ? err.message : err) });
        console.error(`  ERROR ${collectionName}/${docId}:`, err && err.message ? err.message : err);
        // Deliberately swallowed — one bad document must never stop the
        // rest of the migration.
      }
    }

    lastDoc = snapshot.docs[snapshot.docs.length - 1];
    if (snapshot.docs.length < PAGE_SIZE) break;
  }

  console.log(
    `  ${collectionName}: scanned ${stats.scanned}, ${isDryRun ? 'would update' : 'updated'} ${stats.updated}, skipped ${stats.skipped}, errors ${stats.errors}`
  );
  return stats;
}

async function run() {
  const targetCollections = onlyCollections || Object.keys(MIGRATIONS);
  const unknown = targetCollections.filter((c) => !(c in MIGRATIONS));
  if (unknown.length) {
    console.error(`Unknown collection(s) in --collections: ${unknown.join(', ')}`);
    console.error(`Valid collections: ${Object.keys(MIGRATIONS).join(', ')}`);
    process.exit(1);
  }

  console.log(`AgriTrade+ schema migration — ${isDryRun ? 'DRY RUN (no writes)' : 'LIVE RUN (writing changes)'}`);
  console.log(`Target collections: ${targetCollections.join(', ')}`);

  const log = [];
  const overall = {};

  for (const collectionName of targetCollections) {
    overall[collectionName] = await migrateCollection(collectionName, MIGRATIONS[collectionName], log);
  }

  console.log('\n=== Summary ===');
  for (const [name, stats] of Object.entries(overall)) {
    console.log(`${name}: scanned ${stats.scanned}, ${isDryRun ? 'would update' : 'updated'} ${stats.updated}, skipped ${stats.skipped}, errors ${stats.errors}`);
  }

  const logsDir = path.join(__dirname, 'logs');
  if (!fs.existsSync(logsDir)) fs.mkdirSync(logsDir, { recursive: true });
  const logPath = path.join(logsDir, `001-${isDryRun ? 'dryrun-' : ''}${Date.now()}.json`);
  fs.writeFileSync(logPath, JSON.stringify({ isDryRun, targetCollections, summary: overall, documents: log }, null, 2));
  console.log(`\nFull per-document log written to: ${logPath}`);

  if (isDryRun) {
    console.log('\nThis was a dry run — nothing was written. Re-run without --dry-run to apply.');
  }

  process.exit(0);
}

run().catch((err) => {
  console.error('Migration failed to run:', err);
  process.exit(1);
});
