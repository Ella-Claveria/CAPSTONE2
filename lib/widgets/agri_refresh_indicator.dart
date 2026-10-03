import '../theme/app_theme.dart';
import 'package:flutter/material.dart';

class AgriRefreshIndicator extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onRefresh;
  final Color color;

  const AgriRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
    this.color = AppTheme.dark,
  });

  @override
  State<AgriRefreshIndicator> createState() => _AgriRefreshIndicatorState();
}

class _AgriRefreshIndicatorState extends State<AgriRefreshIndicator>
    with SingleTickerProviderStateMixin {
  // Created in initState, not lazily: a lazy controller first touched in
  // dispose() would look up TickerMode on a deactivated element and throw.
  late final AnimationController _rotationController;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() => _refreshing = true);
      _rotationController.repeat();
    }
    try {
      await widget.onRefresh();
    } finally {
      _rotationController.stop();
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
                  width: 32,
                  height: 32,
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
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      RotationTransition(
                        turns: _rotationController,
                        child: SizedBox(
                          width: 27,
                          height: 27,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              widget.color,
                            ),
                          ),
                        ),
                      ),
                      Image.asset(
                        'assets/images/logo.png',
                        width: 17,
                        height: 17,
                        fit: BoxFit.contain,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class AgriLogoLoader extends StatefulWidget {
  final double size;
  final Color color;

  const AgriLogoLoader({super.key, this.size = 18, this.color = AppTheme.dark});

  @override
  State<AgriLogoLoader> createState() => _AgriLogoLoaderState();
}

class _AgriLogoLoaderState extends State<AgriLogoLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RotationTransition(
            turns: _controller,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                valueColor: AlwaysStoppedAnimation<Color>(widget.color),
              ),
            ),
          ),
          Image.asset(
            'assets/images/logo.png',
            width: widget.size * 0.56,
            height: widget.size * 0.56,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }
}
