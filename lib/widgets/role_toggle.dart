import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// "Choose your role": Buyer | Farmer, in one rounded pill. The selected
/// side is a dark green thumb with white text that slides across when the
/// choice changes; the other side is dark green text on off-white. Both
/// halves are the same size. Used by registration and by Google sign-up's
/// profile step.
class RoleToggle extends StatelessWidget {
  /// 'buyer' or 'farmer'.
  final String selected;
  final ValueChanged<String> onChanged;
  final String buyerLabel;
  final String farmerLabel;

  const RoleToggle({
    super.key,
    required this.selected,
    required this.onChanged,
    this.buyerLabel = 'Buyer',
    this.farmerLabel = 'Farmer',
  });

  static const double height = 50;
  static const _duration = Duration(milliseconds: 220);
  static const _curve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    final farmer = selected == 'farmer';
    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8F6),
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: const Color(0xFFDDE2DA)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F0E3210),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // The thumb: half the width, sliding to the chosen side.
          AnimatedAlign(
            duration: _duration,
            curve: _curve,
            alignment: farmer ? Alignment.centerRight : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.dark,
                  borderRadius: BorderRadius.circular(height / 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x290E3210),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              _side('buyer', buyerLabel),
              _side('farmer', farmerLabel),
            ],
          ),
        ],
      ),
    );
  }

  Widget _side(String role, String label) {
    final isSelected = selected == role;
    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: isSelected ? null : () => onChanged(role),
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: _duration,
              curve: _curve,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : AppTheme.dark,
              ),
              child: Text(label),
            ),
          ),
        ),
      ),
    );
  }
}
