import 'package:flutter/material.dart';
import 'shimmer.dart';

// Skeleton placeholders for the farmer-side tabs. Each one mirrors the
// dimensions of the real widget it stands in for (card padding, radius,
// row/column layout) so swapping skeleton <-> real content doesn't shift
// the page, and wraps its whole layout in a single Shimmer so every
// placeholder sweeps together.

BoxDecoration _cardDecoration({double radius = 18}) => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3)),
      ],
    );

// ---- Market tab (farmer home) ----
// Mirrors MarketTab: welcome header, a row of two stat cards, then two
// large content cards (sales performance + market objectives).
class MarketTabSkeleton extends StatelessWidget {
  const MarketTabSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _header(),
          const SizedBox(height: 16),
          Row(
            children: const [
              Expanded(child: _StatCardSkeleton()),
              SizedBox(width: 12),
              Expanded(child: _StatCardSkeleton()),
            ],
          ),
          const SizedBox(height: 16),
          const SalesPerformanceCardSkeleton(),
          const SizedBox(height: 16),
          const MarketObjectiveCardSkeleton(),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(radius: 20),
      child: Row(
        children: [
          const SkeletonCircle(size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(width: 90, height: 11),
                SizedBox(height: 8),
                SkeletonBox(width: 140, height: 18),
                SizedBox(height: 8),
                SkeletonBox(width: 110, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

// Standalone market-objective card skeleton — reused both inside
// MarketTabSkeleton (already wrapped in a Shimmer) and on its own by
// market_tab.dart while this one card's marketplace-wide data is still
// loading (wrap it in a Shimmer at the call site in that case).
class MarketObjectiveCardSkeleton extends StatelessWidget {
  const MarketObjectiveCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(width: 160, height: 16),
          const SizedBox(height: 12),
          for (var i = 0; i < 3; i++) ...[
            _objectiveRow(),
            if (i != 2) const SizedBox(height: 10),
          ],
          const SizedBox(height: 12),
          const SkeletonBox(width: double.infinity, height: 44, borderRadius: BorderRadius.all(Radius.circular(12))),
        ],
      ),
    );
  }

  Widget _objectiveRow() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBF6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonCircle(size: 8),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(width: 130, height: 10),
                SizedBox(height: 6),
                SkeletonBox(width: 90, height: 16),
                SizedBox(height: 4),
                SkeletonBox(width: 160, height: 9),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Standalone sales-performance card skeleton — reused both inside
// MarketTabSkeleton (already wrapped in a Shimmer) and on its own by
// market_tab.dart while the user/orders data behind that one card is
// still loading (wrap it in a Shimmer at the call site in that case).
class SalesPerformanceCardSkeleton extends StatelessWidget {
  const SalesPerformanceCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              SkeletonBox(width: 150, height: 16),
              SkeletonBox(width: 90, height: 22, borderRadius: BorderRadius.all(Radius.circular(20))),
            ],
          ),
          const SizedBox(height: 12),
          const SkeletonBox(width: 90, height: 10),
          const SizedBox(height: 6),
          const SkeletonBox(width: 120, height: 22),
          const SizedBox(height: 14),
          SizedBox(
            height: 108,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [60.0, 80.0, 45.0, 70.0, 55.0].map((h) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SkeletonBox(
                      width: 18,
                      height: h,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                    ),
                    const SizedBox(height: 6),
                    const SkeletonBox(width: 18, height: 8),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          const SkeletonBox(width: 200, height: 9),
        ],
      ),
    );
  }
}

class _StatCardSkeleton extends StatelessWidget {
  const _StatCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: _cardDecoration(),
      child: Column(
        children: const [
          SkeletonBox(width: 70, height: 11),
          SizedBox(height: 4),
          SkeletonBox(width: 50, height: 11),
          SizedBox(height: 10),
          SkeletonBox(width: 44, height: 30),
        ],
      ),
    );
  }
}

// ---- Orders tab ----
// Mirrors OrdersTab: filter pills, then a scrollable list of order cards.
class OrdersTabSkeleton extends StatelessWidget {
  const OrdersTabSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Row(
            children: const [
              Expanded(child: SkeletonBox(height: 38, borderRadius: BorderRadius.all(Radius.circular(24)))),
              SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 38, borderRadius: BorderRadius.all(Radius.circular(24)))),
              SizedBox(width: 8),
              Expanded(child: SkeletonBox(height: 38, borderRadius: BorderRadius.all(Radius.circular(24)))),
            ],
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < 4; i++) ...[
            const OrderCardSkeleton(),
            if (i != 3) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class OrderCardSkeleton extends StatelessWidget {
  const OrderCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(width: 58, height: 58, borderRadius: BorderRadius.all(Radius.circular(12))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonBox(width: 120, height: 14),
                    SizedBox(height: 6),
                    SkeletonBox(width: 90, height: 11),
                    SizedBox(height: 6),
                    SkeletonBox(width: 80, height: 11),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const SkeletonBox(width: 60, height: 20, borderRadius: BorderRadius.all(Radius.circular(20))),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: 36, height: 10),
                  SizedBox(height: 4),
                  SkeletonBox(width: 64, height: 16),
                ],
              ),
              const Spacer(),
              const SkeletonBox(width: 90, height: 32, borderRadius: BorderRadius.all(Radius.circular(10))),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- Profile tab ----
// Mirrors ProfileTab: avatar, name, location, then the "My Products" list.
class ProfileTabSkeleton extends StatelessWidget {
  const ProfileTabSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 90, top: 16),
        child: Column(
          children: [
            const SkeletonCircle(size: 92),
            const SizedBox(height: 14),
            const SkeletonBox(width: 150, height: 22),
            const SizedBox(height: 10),
            const SkeletonBox(width: 130, height: 13),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Row(
                    children: const [
                      Expanded(child: SkeletonBox(width: 90, height: 11)),
                      SkeletonBox(width: 40, height: 12),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: _cardDecoration(radius: 16),
                    child: Column(
                      children: [
                        for (var i = 0; i < 3; i++) ...[
                          if (i != 0) const Divider(height: 1, indent: 16, endIndent: 16),
                          const ProductRowSkeleton(),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductRowSkeleton extends StatelessWidget {
  const ProductRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const SkeletonBox(width: 46, height: 46, borderRadius: BorderRadius.all(Radius.circular(10))),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(width: 140, height: 14),
                SizedBox(height: 8),
                SkeletonBox(width: 90, height: 12),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const SkeletonCircle(size: 16),
        ],
      ),
    );
  }
}
