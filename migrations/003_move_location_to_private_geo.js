/**
 * AgriTrade+ location-privacy migration — moves exact GPS coordinates off
 * the public users/{uid} doc into the restricted users/{uid}/private/geo
 * subcollection (readable only by that account's own owner or an admin —
 * see firestore.rules).
 *
 * WHY THIS EXISTS
 * ----------------
 * Before this migration, `users/{uid}` (readable by ANY signed-in user —
 * `allow read: if request.auth != null;`) carried `latitude`/`longitude`
 * directly. That meant any buyer or farmer could read any other user's
 * exact coordinates straight from the Firestore SDK, regardless of what
 * the Flutter app's UI chose to display (barangay clusters, order-status
 * gating, etc. were all client-side conveniences, not a real data-layer
 * boundary). See docs/firestore-schema-migration.md and the location-
 * privacy audit for the full writeup.
 *
 * All client code (set_farm_location_screen.dart, auth_service.dart's
 * saveBuyerLocation, farmer_edit_profile_screen.dart, buyer_profile_screen
 * .dart, buyer_market_view.dart, buyer_orders_screen.dart,
 * dashboard_analytics_service.dart / admin_dashboard_screen.dart) has
 * already been updated to read/write the new private/geo location — this
 * migration only needs to run ONCE, to carry forward users who registered
 * before that change.
 *
 * WHAT THIS DOES
 * ---------------
 * For each users/{uid} doc with valid numeric latitude/longitude:
 *   1. Writes users/{uid}/private/geo = { latitude, longitude, updatedAt }
 *   2. Deletes latitude/longitude from the main users/{uid} doc
 * Both in the SAME atomic batch per document — there is never a moment
 * where the data exists in neither place, or in both.
 *
 * A document with no latitude/longitude (already migrated, or never had
 * one) is skipped, not touched.
 *
 * SAFETY GATES
 * ------------
 * This script no-ops (prints a warning, writes nothing) unless you pass
 * BOTH flags:
 *   --confirm   "I have read the comment block above"
 *   --apply     "actually perform the move, not just preview it"
 *
 * Passing only --confirm (without --apply) runs a full dry-run preview.
 *
 * USAGE
 * -----
 *   cd migrations
 *   node 003_move_location_to_private_geo.js --confirm              # preview
 *   node 003_move_location_to_private_geo.js --confirm --apply       # for real
 */

const PAGE_SIZE = 300;

const args = process.argv.slice(2);
const isConfirmed = args.includes('--confirm');
const isApply = args.includes('--apply');
const isDryRun = !isApply;

if (!isConfirmed) {
  console.log('='.repeat(70));
  console.log('This migration moves latitude/longitude off the public');
  console.log('users/{uid} doc and deletes them from there. Read the comment');
  console.log('block at the top of this file first, then re-run with');
  console.log('--confirm to preview what it would change:');
  console.log('');
  console.log('  node 003_move_location_to_private_geo.js --confirm');
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

async function run() {
  console.log(`AgriTrade+ location-privacy migration — ${isDryRun ? 'DRY RUN (no writes)' : 'LIVE RUN (moving fields)'}`);

  const stats = { scanned: 0, moved: 0, skipped: 0, errors: 0 };
  const log = [];
  let lastDoc = null;

  while (true) {
    let query = db.collection('users').orderBy(admin.firestore.FieldPath.documentId()).limit(PAGE_SIZE);
    if (lastDoc) query = query.startAfter(lastDoc.id);

    const snapshot = await query.get();
    if (snapshot.empty) break;

    for (const doc of snapshot.docs) {
      stats.scanned += 1;
      const docId = doc.id;

      try {
        const data = doc.data();
        const lat = typeof data.latitude === 'number' ? data.latitude : null;
        const lng = typeof data.longitude === 'number' ? data.longitude : null;

        if (lat === null || lng === null) {
          stats.skipped += 1;
          log.push({ docId, action: 'skipped', reason: 'no valid latitude/longitude on this doc' });
          continue;
        }

        if (isApply) {
          const batch = db.batch();
          batch.set(
            doc.ref.collection('private').doc('geo'),
            { latitude: lat, longitude: lng, updatedAt: FieldValue.serverTimestamp() },
            { merge: true }
          );
          batch.update(doc.ref, { latitude: FieldValue.delete(), longitude: FieldValue.delete() });
          await batch.commit();
        }

        stats.moved += 1;
        log.push({ docId, action: isDryRun ? 'would_move' : 'moved', latitude: lat, longitude: lng });
        console.log(`  ${isDryRun ? '[dry-run] would move' : 'moved'} users/${docId} location -> users/${docId}/private/geo`);
      } catch (err) {
        stats.errors += 1;
        log.push({ docId, action: 'error', error: String(err && err.message ? err.message : err) });
        console.error(`  ERROR users/${docId}:`, err && err.message ? err.message : err);
      }
    }

    lastDoc = snapshot.docs[snapshot.docs.length - 1];
    if (snapshot.docs.length < PAGE_SIZE) break;
  }

  console.log('\n=== Summary ===');
  console.log(`scanned ${stats.scanned}, ${isDryRun ? 'would move' : 'moved'} ${stats.moved}, skipped ${stats.skipped}, errors ${stats.errors}`);

  const logsDir = path.join(__dirname, 'logs');
  if (!fs.existsSync(logsDir)) fs.mkdirSync(logsDir, { recursive: true });
  const logPath = path.join(logsDir, `003-${isDryRun ? 'dryrun-' : ''}${Date.now()}.json`);
  fs.writeFileSync(logPath, JSON.stringify({ isDryRun, summary: stats, documents: log }, null, 2));
  console.log(`\nFull per-document log written to: ${logPath}`);

  if (isDryRun) {
    console.log('\nThis was a dry run — nothing was moved. Re-run with --apply to move for real.');
  }

  process.exit(0);
}

run().catch((err) => {
  console.error('Migration failed to run:', err);
  process.exit(1);
});
