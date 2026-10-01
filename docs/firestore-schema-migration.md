# AgriTrade+ Firestore Schema — Audit & Migration Plan

Status: **Phase 1 complete** — standardized fields are now written by the app going forward, and a non-destructive migration script exists to backfill existing documents. No destructive changes have been made or run.

This document is the record of what was found, what was decided, and what
to do next. Read it before running anything in `migrations/`.

## 1. How this was produced

Every collection was audited by reading the actual Flutter source (not
just the seed data) — every `.collection('<name>')` call across `lib/`,
tracing each field to every file/line that reads or writes it. `seed_data/*.json`
was used only as a secondary cross-check, since it represents an intended
shape that the real app code doesn't always match.

## 2. Collections in scope

The 6 named in the original request, plus 3 more discovered during the
audit that share the same standardization concerns:

| Collection | In original request? | Notes |
|---|---|---|
| `users` | yes | keyed by Firebase Auth UID |
| `products` | yes | |
| `orders` | yes | |
| `conversations` | yes | has a `messages` subcollection |
| `productReviews` | yes | doc ID == source `orderId` |
| `verificationDocs` | yes | doc ID == farmer's Auth UID |
| `market_prices` | found during audit | admin-only writes, doc ID = commodity slug |
| `reports` | found during audit | two structurally different report shapes exist today |
| `searchEvents` | found during audit | buyer search logging for the Demand Heatmap |

## 3. Findings summary (highest impact first)

1. **`users` name duplication.** `fullName` is set once at signup and
   never updated again. `name` is written only by `EditProfileScreen` when
   a user edits their profile. Three read sites had independently added a
   `fullName ?? name` fallback — in the wrong priority order, so an edited
   name was being ignored in favor of the stale signup name. **Fixed** (see
   §5) — priority flipped in the two display-purpose read sites; the
   identity-verification queue intentionally keeps `fullName`-first
   (reviewing the name as originally submitted is correct there).
2. **`users.isVerified` was write-only.** Set only by one admin approval
   path, never read anywhere, and never set at all for buyers or via the
   (unused) `AuthService.approveFarmer`. **Fixed** — now set at signup
   for both roles and backfilled by the migration for existing accounts.
3. **`conversations` product-context fields were read but never
   written.** `chat_list_screen.dart` reads `productId`, `productName`,
   `productImageUrl`, `productPrice`, `deliveryAvailable`, `pickupOnly`
   off every conversation document; `message_service.dart` never wrote
   any of them. Real effect: the "Re: {product}" subtitle never showed,
   and every order started from the chat list got an empty/default
   product. There was also a straight naming bug — the product image was
   being written under the key `farmerImage` instead of `productImageUrl`.
   **Fixed** — see §5. The migration script recovers `productImageUrl` for
   *existing* conversations from the old `farmerImage` value (the data was
   never actually missing, just under the wrong key).
4. **`products.rating` / `products.reviewCount` were read in 3 places but
   never written anywhere.** The star-rating badge on the marketplace grid
   and product detail screen was permanently empty. **Fixed** — see §5.
5. **`productReviews.buyerName` was hardcoded to the literal string
   `'Buyer'`** even though a real `buyerId` was captured on every review.
   **Fixed** — see §5.
6. **`products.isSuspended` was write-only.** The moderation queue's
   "Suspend" action set it, but no buyer-facing query ever excluded
   suspended products — a suspended listing stayed fully visible and
   orderable. **Fixed** — see §5.
7. **`orders.status` has no enforced value set.** `buyer_orders_screen.dart`
   has UI for a `'rejected'` status that nothing in the app ever writes
   (farmers can only Confirm or Mark Complete — there's no reject/decline
   action). Not a schema fix — flagged as a product/feature gap in §7.
8. **`reports` has two incompatible shapes with no discriminator field.**
   The moderation queue (and seed data) expect product-flag reports
   (`productId`, `productName`, `sellerName`, `issueType` in
   {Price Gouging, Counterfeit Goods, Quality Issues}). The only real
   writer (`chat_screen.dart`'s "report user" button) produces a
   different shape (`conversationId`, `reportedUserId`,
   `issueType: 'Chat Report'`) that renders as "Unknown Product/Seller"
   in the queue and matches none of the filter chips.
   `message_order_screen.dart` has a second "Report Seller" button that
   doesn't write to Firestore at all — it's a no-op that only shows a
   success message. Added a `reportType` discriminator via migration;
   the moderation UI still needs follow-up work to branch on it (out of
   scope here — see §7).
9. Several fields are write-only/dead with no live inconsistency risk
   (`users.hasVerificationDoc`, `users.lastTokenUpdate`,
   `conversations.farmerName`, `productReviews.productName`/`.sellerId`,
   `orders.reviewRating`, `searchEvents.userId`/`.category`). Left alone —
   harmless, not worth the churn of removing in this pass.
10. Confirmed **no relationship-breaking issue**: `users` docs are keyed
    by Auth UID everywhere, `products.farmerId` and `orders.sellerId`/
    `orders.buyerId` consistently reference that same UID in every write
    path checked. Nothing in this plan changes any document ID or UID.

Full per-field detail (every file:line, every read/write site) is in the
two research passes this plan was built from — ask if you need the raw
inventory; it's not duplicated here to keep this document maintainable.

## 4. Standardized schema

Only fields with a status other than "keep as-is" are listed per
collection — everything else already matches its one consistent shape and
needs no action.

### `users` (doc ID = Firebase Auth UID)

| Field | Status | Type | Notes |
|---|---|---|---|
| `name` | **standardize on this** | string | canonical display name; kept fresh by `EditProfileScreen` |
| `fullName` | keep (deprecated) | string | legacy signup-time name; do not read for display purposes anymore. Removed only in Phase 2 cleanup, once `name` is confirmed present everywhere |
| `isVerified` | keep, now maintained | bool | mirrors `approvalStatus == 'approved'`; now set at signup too |
| `approvalStatus` | keep | string enum | `'pending' \| 'approved' \| 'rejected'` — unchanged, already the one real source of truth |
| `hasVerificationDoc` | keep (dead) | bool | write-only, no known consumer; left alone |
| `location` | keep (known bug, not fixed here) | string | orphaned field written by `EditProfileScreen`; never read; editing "Location" does **not** actually update `barangay`. See §7 |
| `barangay` / `municipality` / `province` | keep | string | unchanged — coarse, public-safe, shown to buyers as-is |
| `latitude` / `longitude` | **removed** (see migration `003_move_location_to_private_geo.js`) | double | previously lived here, meaning ANY signed-in user could read any other user's exact GPS pin directly via the Firestore SDK, regardless of what the app's UI chose to display. Moved to `users/{uid}/private/geo` (own subcollection, own rule: owner or admin only — see `firestore.rules`). Nothing else about this doc changed. |
| `updatedAt` | **new** | Timestamp | added by migration/going-forward writes so every doc has a "last touched" reference |

### `users/{uid}/private/geo` (new)

| Field | Status | Type | Notes |
|---|---|---|---|
| `latitude` / `longitude` | new | double | the exact pin, moved off the parent doc above. Read by: the doc's own owner (their own profile screens), an admin (Demand Heatmap analytics), and Cloud Functions via the Admin SDK (order-confirmation snapshot, barangay cluster aggregation) — never by any other client. |
| `updatedAt` | new | Timestamp | |

### `barangayClusters/{barangay}` (new)

PII-free, server-computed aggregate the buyer marketplace map reads instead of any individual farmer's exact coordinates. Maintained entirely by Cloud Functions (`recomputeBarangayCluster` in `functions/index.js`); clients cannot write to it.

| Field | Status | Type | Notes |
|---|---|---|---|
| `barangay` | new | string | matches the doc ID |
| `lat` / `lng` | new | double | average of that barangay's approved, active farmers' exact pins |
| `farmerCount` | new | number | how many farmers contributed to the average — never which ones |
| `updatedAt` | new | Timestamp | |

### `products`

| Field | Status | Type | Notes |
|---|---|---|---|
| `isArchived` | keep, now defaulted | bool | now explicitly `false` at creation instead of implied-by-absence |
| `isSuspended` | keep, **now enforced** | bool | now explicitly `false` at creation; buyer marketplace queries and order placement now actually exclude suspended products |
| `rating` | **new, now maintained** | number | running average, updated transactionally by `ReviewService.submitReview` |
| `reviewCount` | **new, now maintained** | number | updated in the same transaction |
| `updatedAt` | **new** | Timestamp | |

### `orders`

No field renames. `status` should be treated as a closed enum going
forward: `'pending' | 'confirmed' | 'completed' | 'rejected'` — the
migration normalizes any document with an unexpected/missing value to
`'pending'`.

### `conversations`

| Field | Status | Type | Notes |
|---|---|---|---|
| `productId` | **standardize on this** | string | now actually written by `startOrGetConversation` |
| `productName` | **standardize on this** | string | now actually written |
| `productImageUrl` | **standardize on this** | string | now actually written; migration recovers historical value from `farmerImage` |
| `productPrice` | **new** | string | display string, e.g. `"₱50/kilo"`, matching the format used elsewhere in the app |
| `deliveryAvailable` / `pickupOnly` | **new** | bool | now passed through from the product |
| `farmerImage` | keep (deprecated) | string | superseded by `productImageUrl`; removed only in Phase 2, once every doc has `productImageUrl` |
| `farmerName` | keep (dead) | string | write-only, no consumer |

### `productReviews` (doc ID = source `orderId`)

No field renames. `buyerName` is now populated with the real
reviewer's resolved name (Auth `displayName` → `users.name` →
`users.fullName` → `'Buyer'`) instead of the hardcoded literal.

### `verificationDocs` (doc ID = farmer's Auth UID)

No changes — already internally consistent. (The only issue found here
was a redundant duplicate write in `register_screen.dart`'s post-signup
step, which is harmless — not a schema issue.)

### `reports`

| Field | Status | Type | Notes |
|---|---|---|---|
| `reportType` | **new** | string enum | `'product' \| 'user' \| 'unknown'`, inferred from which identifying fields are present. UI still needs to branch on this — see §7 |

### `market_prices`, `searchEvents`

No changes — both are internally consistent with their one real
writer/reader pair.

## 5. Flutter-side changes made in this pass

All changes are additive/backward-compatible — every read site that used
to fall back to a default still works exactly as before if a field is
absent; nothing assumes the migration has already run.

- `lib/services/auth_service.dart` — `signUp()` now also writes `name`
  and `isVerified` (dual-write alongside the legacy `fullName`).
- `lib/screen/chat_list_screen.dart`, `lib/services/message_service.dart`
  — flipped the `fullName`/`name` fallback priority to prefer the fresher
  `name` field, for the two display-purpose read sites only (the
  verification queue's `fullName`-first priority was left as-is — that's
  the *correct* priority there, not a bug).
- `lib/services/message_service.dart` — `startOrGetConversation()` now
  writes `productId`, `productName`, `productImageUrl`, `productPrice`,
  `deliveryAvailable`, `pickupOnly` on every conversation doc it
  creates/refreshes (previously only `farmerImage`, under the wrong key,
  was written).
- `lib/screen/product_detail_screen.dart` — passes the new
  `deliveryAvailable`/`pickupOnly` parameters through to
  `startOrGetConversation`.
- `lib/services/product_service.dart` — `addProduct()` now defaults
  `isArchived: false`, `isSuspended: false`, `rating: 0`,
  `reviewCount: 0` on every new listing.
- `lib/services/review_service.dart` — `submitReview()` now resolves and
  stores the real reviewer name (was hardcoded `'Buyer'`), and
  transactionally keeps `products.rating`/`products.reviewCount` in sync
  (handles both a first-time review and an edit of an existing one
  correctly — average is recomputed, count isn't double-incremented).
- `lib/screen/buyer_explore_screen.dart`, `lib/screen/buyer_market_view.dart`,
  `lib/screen/place_order_screen.dart`, `lib/services/order_service.dart`
  — all now also exclude/reject `isSuspended == true` products, mirroring
  the existing `isArchived` exclusion. `order_service.dart`'s check is the
  authoritative one (inside the same transaction that deducts stock).

Verified with `flutter analyze` (clean) and the existing test suite
(`flutter test`, all passing) after every change.

## 6. Running the migration

See `migrations/README.md` for full instructions. Summary:

```
cd migrations
npm install
npm run migrate:dry-run        # preview — writes nothing
npm run migrate                 # apply for real
```

The migration script (`001_standardize_schema.js`):
- adds missing fields with the safe defaults listed in §4 above
- copies old values into new standardized fields where derivable
  (e.g. recovers `productImageUrl` from the buggy `farmerImage` field)
- never overwrites a field that already has a valid value
- never deletes or renames anything
- processes every document independently — one bad document is logged
  and skipped, it never aborts the run
- logs every scanned document's outcome (updated / skipped / errored) to
  the console and to a timestamped JSON file under `migrations/logs/`
- supports `--collections=users,products` to migrate one collection at a
  time, and `--dry-run` to preview before writing

## 7. Verification checklist (do this before Phase 2 cleanup)

- [ ] Run `npm run migrate:dry-run`, read the summary and log file.
- [ ] Run `npm run migrate` for real against a dev/staging project first
      if you have one.
- [ ] Spot-check a handful of `users` docs — `name` present, `isVerified`
      matches `approvalStatus`.
- [ ] Spot-check `products` docs — `isArchived`/`isSuspended`/`rating`/
      `reviewCount` present.
- [ ] Open the app: farmer marketplace shows correct product counts;
      buyer marketplace excludes archived/suspended products.
- [ ] Start a new chat from a product's detail page → confirm the chat
      list shows the "Re: {product}" context and that opening
      "Message Order" from the chat list carries the right product/price.
- [ ] Submit a review → confirm the product's rating/review count badge
      updates on the marketplace grid.
- [ ] Only once all of the above look right in production: run
      `node 002_cleanup_deprecated_fields.js --confirm` (dry-run preview),
      review it, then `--confirm --apply` for real.

## 8. Recommended follow-ups (not done in this pass — scope/risk judgment calls, not schema renames)

These came up during the audit but are feature gaps or UX decisions, not
naming/structure inconsistencies, so they were left for a separate task:

- **`orders` has no reject/decline path.** The buyer UI already expects a
  `'rejected'` status; farmers just have no button that sets it.
- **`reports` moderation UI doesn't branch on report type.** Even with
  the new `reportType` field, `moderation_queue_view.dart` still renders
  every report as if it were a product-flag report. `message_order_screen.dart`'s
  "Report Seller" button should actually write a report instead of just
  showing a success message.
- **`EditProfileScreen`'s "Location" field doesn't update `barangay`.**
  It's a single free-text field, so it can't be safely auto-split back
  into `barangay`/`municipality`/`province` without risking corrupting
  data the admin demand-heatmap and buyer filters rely on. Needs a UX
  decision (structured pickers vs. a real address-parsing step), not a
  migration.
- **Dead code found, safe to delete whenever convenient:**
  `lib/screen/admin_verification_queue.dart` (unreachable, name-collides
  with the real `verification_queue_view.dart`), the duplicate
  `AdminLoginScreen` class living inside `lib/widgets/agritrade_text.dart`,
  `lib/screen/application_under_review_screen.dart` (unreachable),
  `AuthService.approveFarmer`/`.rejectFarmer`/`.getVerificationDocument`
  (unused, and the first two don't update `verificationDocs.status` —
  don't wire them up as-is if you ever do use them),
  `ReviewService.productReviewsStream()` (unused — callers query
  `productReviews` directly).
- **Redundant FCM token registration.** Both `PushNotificationService`
  and `MessageService` independently `arrayUnion` the same
  `users.fcmTokens` field via near-identical code paths.
