import 'package:flutter/material.dart';

/// Lets the buyer pick a quantity and see the live total (qty × unit
/// price) for a wholesale or retail pricing option, before continuing to
/// PlaceOrderScreen. Shown when they tap a price option in chat.
Future<void> showPricingCalculatorSheet(
  BuildContext context, {
  required String pricingType, // 'retail' or 'wholesale'
  required num unitPrice,
  required int minimumQuantity,
  required int maximumQuantity, // 0 = no cap
  required void Function(int quantity) onProceed,
}) async {
  final isWholesale = pricingType == 'wholesale';
  final lowerBound = isWholesale ? (minimumQuantity < 1 ? 1 : minimumQuantity) : 1;
  final upperBound = maximumQuantity > 0 ? maximumQuantity : (isWholesale ? 9999 : lowerBound);
  int quantity = lowerBound.clamp(1, upperBound);

  await showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setState) {
          final total = unitPrice * quantity;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isWholesale ? 'Wholesale order' : 'Retail order',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isWholesale
                        ? 'Minimum $minimumQuantity kg for the wholesale rate.'
                        : maximumQuantity > 0
                            ? 'Up to $maximumQuantity kg at the retail rate.'
                            : 'Retail rate.',
                    style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Quantity (kg)', style: TextStyle(fontWeight: FontWeight.w600)),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: quantity > lowerBound
                                ? () => setState(() => quantity--)
                                : null,
                          ),
                          SizedBox(
                            width: 40,
                            child: Text(
                              '$quantity',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: quantity < upperBound
                                ? () => setState(() => quantity++)
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 28),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F8E9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '₱${unitPrice.toStringAsFixed(2)}/kg × $quantity kg',
                          style: const TextStyle(fontSize: 13, color: Colors.black54),
                        ),
                        Text(
                          '₱${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1B5E20),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        onProceed(quantity);
                      },
                      child: const Text('Continue to Order'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
