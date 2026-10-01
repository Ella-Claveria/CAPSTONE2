import 'package:flutter/material.dart';

import 'buyer_location_picker.dart';
import '../theme/app_theme.dart';

/// Tap-to-open field backing the buyer location popup (see
/// buyer_location_picker.dart) — only ever displays the readable address
/// it comes back with, never a raw coordinate.
class BuyerLocationField extends StatelessWidget {
  final BuyerLocationResult? value;
  final ValueChanged<BuyerLocationResult> onPicked;
  final String? errorText;
  final String label;

  const BuyerLocationField({
    super.key,
    required this.value,
    required this.onPicked,
    this.errorText,
    this.label = 'My Location',
  });

  Future<void> _open(BuildContext context) async {
    final picked = await showBuyerLocationPicker(context, initial: value);
    if (picked != null) onPicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTheme.label()),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _open(context),
          child: InputDecorator(
            decoration: AppTheme.inputBox(
              hint: 'Tap to set your location',
              icon: Icons.location_on_outlined,
              suffix: const Icon(Icons.chevron_right, color: Colors.grey),
            ),
            isEmpty: value == null,
            child: value != null
                ? Text(
                    value!.readable,
                    style: const TextStyle(color: Colors.black87, fontSize: 14.5),
                  )
                : null,
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, size: 14, color: Colors.red.shade700),
              const SizedBox(width: 4),
              Expanded(
                child: Text(errorText!, style: TextStyle(color: Colors.red.shade700, fontSize: 11)),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}
