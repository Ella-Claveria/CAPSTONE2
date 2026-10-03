import 'package:flutter/material.dart';

import '../services/saved_products_service.dart';
import '../theme/app_theme.dart';

/// The Liked Products heart: an outline in dark green when the product is
/// not liked, a filled red heart when it is, with a small bounce on tap.
///
/// Purely visual — [liked] and [onTap] come from the caller. Sits on a
/// white circle so it stays readable on top of any product photo.
class LikeHeart extends StatefulWidget {
  final bool liked;
  final VoidCallback? onTap;

  /// Diameter of the white circle; the heart is a little over half of it.
  final double size;

  const LikeHeart({
    super.key,
    required this.liked,
    required this.onTap,
    this.size = 34,
  });

  /// The colour of a liked heart.
  static const Color likedColor = Color(0xFFE53935);

  @override
  State<LikeHeart> createState() => _LikeHeartState();
}

class _LikeHeartState extends State<LikeHeart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1, end: 1.3), weight: 45),
    TweenSequenceItem(tween: Tween(begin: 1.3, end: 1), weight: 55),
  ]).animate(CurvedAnimation(parent: _bounce, curve: Curves.easeOut));

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.liked ? 'Remove from Liked Products' : 'Like product',
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 1.5,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap == null
              ? null
              : () {
                  _bounce.forward(from: 0);
                  widget.onTap!();
                },
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Center(
              child: ScaleTransition(
                scale: _scale,
                child: Icon(
                  widget.liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: widget.size * 0.58,
                  color: widget.liked ? LikeHeart.likedColor : AppTheme.dark,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Likes or unlikes [productId] for the signed-in buyer and confirms it
/// with the usual snackbar. Used by every heart in the app, so they all
/// behave — and read — the same.
Future<void> toggleLikedProduct(BuildContext context, String productId) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await LikedProducts.instance.toggle(productId);
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          result.error ??
              (result.liked
                  ? 'Added to Liked Products'
                  : 'Removed from Liked Products'),
        ),
      ),
    );
}

/// The heart on Product Details, wired to the buyer's real liked state
/// ([LikedProducts]). Draws nothing for anyone who isn't a buyer.
class SaveProductButton extends StatefulWidget {
  final String productId;

  const SaveProductButton({super.key, required this.productId});

  @override
  State<SaveProductButton> createState() => _SaveProductButtonState();
}

class _SaveProductButtonState extends State<SaveProductButton> {
  @override
  void initState() {
    super.initState();
    LikedProducts.instance.start();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LikedProducts.instance,
      builder: (context, _) {
        final likes = LikedProducts.instance;
        if (!likes.canLike) return const SizedBox.shrink();
        return LikeHeart(
          liked: likes.contains(widget.productId),
          size: 40,
          onTap: () => toggleLikedProduct(context, widget.productId),
        );
      },
    );
  }
}
