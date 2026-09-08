# AgriTrade+ sample historical data

Sample records for every feature that needs *history* to show anything
meaningful: farmer revenue charts, the AI price recommendation, the admin
Analytics Dashboard, Price Management, and the Demand Heatmap all show
empty states on a fresh database until there's real (or realistic-looking)
data behind them.

## What's in here

| File                     | Collection         | What it feeds |
|---------------------------|---------------------|----------------|
| `users.json`              | `users`             | Farmer/buyer counts, barangay-based map & filters |
| `products.json`           | `products`          | Marketplace listings, AI price recommendation, live market averages |
| `orders.json`             | `orders`            | Revenue charts, platform transactions, demand heatmap, price recommendation history |
| `verificationDocs.json`   | `verificationDocs`  | Admin verification queue + recent-requests table |
| `market_prices.json`      | `market_prices`     | Admin Price Management baselines |
| `reports.json`            | `reports`           | Moderation queue + flagged-reports count |
| `searchEvents.json`       | `searchEvents`      | Demand Heatmap's "Top Buyer Searches" panel |

5 sample farmers (across 5 different Laurel barangays), 2 sample buyers,
10 products (including one archived and one out-of-stock, to exercise
those states), 15 completed orders spread from May–September 2026, and a
handful of verification/report/search records.

**All seeded IDs are prefixed `seed_`** (`seed_farmer_01`, `seed_order_01`,
etc.) — market_prices uses commodity slugs (`rice`, `chicken`, …) instead,
matching what the app itself would generate. This makes seeded data easy
to spot and safe to delete later without touching anything real.

## Important limitation

**These seeded farmers/buyers are Firestore documents only — they have no
matching Firebase Authentication account.** You cannot log into the app as
`seed_farmer_01`. They exist purely to populate dashboards, charts, and the
recommendation engine with history. If you also want interactive test
accounts you can actually log in as, register them normally through the
app instead.

## Why not a plain Firebase console import

The Firebase console doesn't have a bulk "import this JSON" button for
Firestore — bulk import there means the `gcloud firestore import` format
(a special export from Cloud Storage), not plain JSON. So instead this
folder pairs the JSON with a tiny Node script that reads it and writes it
using the Firebase Admin SDK, which is the standard way this is actually
done.

## How to run it

1. **Get a service account key** (this is a credential for *your* Firebase
   project — nobody else should have it):
   Firebase Console → Project Settings → Service Accounts → *Generate new
   private key*. Save the downloaded file as `serviceAccountKey.json`
   right in this `seed_data/` folder (already gitignored — it will never
   be committed).

2. **Install dependencies:**
   ```
   cd seed_data
   npm install
   ```

3. **Load the data:**
   ```
   npm run import
   ```
   You'll see a line per collection confirming how many documents were
   written.

4. **Remove it later, if you want:** this deletes only the `seed_`-prefixed
   documents listed in these JSON files — nothing else in your database.
   ```
   npm run delete
   ```

## A note on which project this hits

This runs against whichever Firebase project your service account key
belongs to. If you have a separate dev/staging project, download that
project's key instead of your production one — safer for experimenting.

## After importing

- Farmer app → Market tab should show non-zero revenue bars.
- Add Product screen → typing "Rice", "Chicken", etc. should show a real
  price recommendation instead of "No market data yet."
- Admin Dashboard → Analytics should show 7 users, pending verifications,
  and the commodity price panel. Price Management should list 5
  commodities. Demand Heatmap should show barangay circles and a top
  searches panel.
