# AgriTrade+ Firestore schema migration

Two scripts, meant to be run in order, months apart if needed:

1. **`001_standardize_schema.js`** — safe, additive, non-destructive.
   Adds missing standardized fields with safe defaults, and copies old
   values into new fields where derivable. Never deletes or overwrites
   anything. Read `../docs/firestore-schema-migration.md` first — it
   explains exactly what's inconsistent today and what each patch does.

2. **`002_cleanup_deprecated_fields.js`** — destructive. Deletes exactly
   two now-superseded fields (`users.fullName`, `conversations.farmerImage`),
   and only from documents where the replacement field is already
   confirmed present. **Do not run this until you've run #1 for real and
   verified the app works correctly with the new fields** (see the
   verification checklist in the plan doc).

## How to run either script

1. **Get a service account key** (a credential for *your* Firebase
   project — nobody else should have it): Firebase Console → Project
   Settings → Service Accounts → *Generate new private key*. Save the
   downloaded file as `serviceAccountKey.json` right in this `migrations/`
   folder (already gitignored — it will never be committed).

   If you have a separate dev/staging Firebase project, use that key
   first — safer than pointing straight at production.

2. **Install dependencies:**
   ```
   cd migrations
   npm install
   ```

3. **Preview first, always:**
   ```
   npm run migrate:dry-run
   ```
   This writes nothing — it just prints (and logs to
   `logs/001-dryrun-<timestamp>.json`) exactly what it would change.

4. **Apply for real:**
   ```
   npm run migrate
   ```

5. **Scope to one collection at a time** if you want to verify
   incrementally instead of migrating everything at once:
   ```
   node 001_standardize_schema.js --dry-run --collections=users
   node 001_standardize_schema.js --collections=users
   ```

6. **After verifying the app works correctly** with the new fields (see
   the checklist in the plan doc), the cleanup script requires two
   explicit flags — it refuses to do anything without both:
   ```
   node 002_cleanup_deprecated_fields.js --confirm              # preview only
   node 002_cleanup_deprecated_fields.js --confirm --apply       # for real
   ```

## What these scripts will NOT do

- Delete a document.
- Delete or rename a field during `001_standardize_schema.js` (that's
  the whole point of running it first).
- Touch Firebase Authentication accounts or UIDs.
- Touch any collection other than the ones listed in
  `docs/firestore-schema-migration.md`.
- Stop partway through because one document had bad/unexpected data —
  every document is processed independently, and failures are logged,
  not fatal.

## Logs

Every run writes a full JSON log to `logs/` (gitignored — these can
contain real user/order data) with the outcome of every single document
it touched. Keep these around for your own audit trail; they're not
needed by the scripts themselves on a later run.

## Which project this hits

Same as `seed_data/`: whichever Firebase project your service account
key belongs to. Double-check before running `002_cleanup_deprecated_fields.js
--apply` against anything you can't easily restore from a backup.
