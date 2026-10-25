import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/commodity_master_list.dart';
import 'agri_dialog.dart';

/// The most Available Stock a listing can have: four digits.
const int kMaxStock = 9999;

/// Keeps a stock field to at most four digits before the decimal point —
/// whole numbers only when [countBased] (pieces, head), otherwise up to two
/// decimals (kg). Used by Add Product and Update Available Stock.
List<TextInputFormatter> stockInputFormatters(bool countBased) {
  final allowed = countBased
      ? RegExp(r'^\d{0,4}$')
      : RegExp(r'^\d{0,4}(\.\d{0,2})?$');
  return [
    TextInputFormatter.withFunction(
      (oldValue, newValue) =>
          allowed.hasMatch(newValue.text) ? newValue : oldValue,
    ),
  ];
}

/// The "Update Available Stock" dialog for one listing. Resolves to the
/// new quantity when Save is tapped with a valid one, or to null when the
/// dialog is cancelled or dismissed (back button, tap outside) — in which
/// case nothing is to be saved.
///
/// [onInvalid] is told why Save was refused (shown by the caller as a
/// snackbar, as before).
Future<num?> showUpdateStockDialog(
  BuildContext context, {
  required String name,
  required num currentQuantity,
  required String unit,
  void Function(BuildContext dialogContext, String message)? onInvalid,
}) {
  return showAgriDialog<num?>(
    context: context,
    builder: (_) => UpdateStockDialog(
      name: name,
      currentQuantity: currentQuantity,
      unit: unit,
      onInvalid: onInvalid,
    ),
  );
}

/// The dialog itself. It owns the text field's controller: created with
/// the dialog and disposed with it — that is, only once the dialog has
/// finished closing and its field is gone. (Disposing it from the code
/// that opened the dialog, as soon as a result came back, was too early:
/// the dialog is still on screen, animating away, at that moment.)
class UpdateStockDialog extends StatefulWidget {
  final String name;
  final num currentQuantity;
  final String unit;
  final void Function(BuildContext dialogContext, String message)? onInvalid;

  const UpdateStockDialog({
    super.key,
    required this.name,
    required this.currentQuantity,
    required this.unit,
    this.onInvalid,
  });

  @override
  State<UpdateStockDialog> createState() => _UpdateStockDialogState();
}

class _UpdateStockDialogState extends State<UpdateStockDialog> {
  late final bool _countBased = isCountBasedUnit(widget.unit);
  late final TextEditingController _controller = TextEditingController(
    text: _countBased
        ? widget.currentQuantity.toStringAsFixed(0)
        : widget.currentQuantity.toString(),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final parsed = num.tryParse(_controller.text.trim());
    if (parsed == null || parsed < 0) {
      widget.onInvalid?.call(
        context,
        'Please enter a valid, non-negative quantity.',
      );
      return;
    }
    if (_countBased && parsed != parsed.roundToDouble()) {
      widget.onInvalid?.call(
        context,
        'Available Stock for ${widget.unit} must be a whole number.',
      );
      return;
    }
    if (parsed.floor() > kMaxStock) {
      widget.onInvalid?.call(
        context,
        'Available Stock can be at most 9,999 ${widget.unit}.',
      );
      return;
    }
    Navigator.of(context).pop<num?>(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AgriDialog(
      title: const Text('Update Available Stock'),
      // Scrolls if a small screen with the keyboard open leaves too
      // little room, instead of overflowing.
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(
              decimal: !_countBased,
            ),
            // Four digits at most (see kMaxStock).
            inputFormatters: stockInputFormatters(_countBased),
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              // The app's curved field (AppTheme), like every other.
              labelText: 'Available Stock (${widget.unit})',
            ),
          ),
        ],
      ),
      actions: [
        AgriDialogButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop<num?>(null),
        ),
        AgriDialogButton(
          label: 'Save',
          kind: AgriButtonKind.primary,
          onPressed: _save,
        ),
      ],
    );
  }
}
