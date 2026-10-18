import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/order_format.dart';
import 'orders_view.dart';

// The Buyer's Orders tab. The screen itself is shared with the Farmer
// side; see OrdersView.
class BuyerOrdersScreen extends StatelessWidget {
  final VoidCallback? onBrowseMarketplace;

  /// A status tab to open on request (see OrderStatusPager.showStatus).
  final ValueListenable<String?>? showStatus;

  const BuyerOrdersScreen({
    super.key,
    this.onBrowseMarketplace,
    this.showStatus,
  });

  @override
  Widget build(BuildContext context) => OrdersView(
    role: OrderRole.buyer,
    onBrowseMarketplace: onBrowseMarketplace,
    showStatus: showStatus,
  );
}
