import '../theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Pull to refresh, with the app's own spinner: a plain green circle in a
/// small white disc at the top while it loads.
class AgriRefreshIndicator extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onRefresh;
  final Color color;

  const AgriRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
    this.color = AppTheme.mid,
  });

  @override
  State<AgriRefreshIndicator> createState() => _AgriRefreshIndicatorState();
}

class _AgriRefreshIndicatorState extends State<AgriRefreshIndicator> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (mounted) setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        RefreshIndicator.noSpinner(onRefresh: _refresh, child: widget.child),
        if (_refreshing)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 34,
                  height: 34,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(widget.color),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The app's small loading spinner: a plain green circle.
class AgriLogoLoader extends StatelessWidget {
  final double size;
  final Color color;

  const AgriLogoLoader({super.key, this.size = 18, this.color = AppTheme.mid});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: size >= 28 ? 2.5 : 2,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}
