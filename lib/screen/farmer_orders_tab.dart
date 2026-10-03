import 'package:flutter/material.dart';

import '../services/order_format.dart';
import 'orders_view.dart';

// The Farmer's Orders tab. Body-only — it renders inside the
// FarmerHomeScreen Scaffold (which already provides the AgriTrade+ app bar
// and bottom nav). The screen itself is shared with the Buyer side; see
// OrdersView.
class OrdersTab extends StatelessWidget {
  const OrdersTab({super.key});

  @override
  Widget build(BuildContext context) =>
      const OrdersView(role: OrderRole.farmer);
}
