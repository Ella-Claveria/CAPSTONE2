import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/commodity_master_list.dart';
import '../main.dart' show rootNavigatorKey;
import '../screen/product_detail_screen.dart';
import 'market_price_helpers.dart';

/// Where shared product links point: the AgriTrade+ web app on Firebase
/// Hosting (see firebase.json). The same address is registered as an app
/// link in AndroidManifest.xml, so on a phone with the app installed (and
/// the link verified — see web/.well-known/assetlinks.json) it opens the
/// app instead; everyone else lands on the web app.
const String kProductLinkBase = 'https://agritrade-bef87.web.app';

/// The link to one product listing. Only the product's id is in it.
Uri productLink(String productId) =>
    Uri.parse('$kProductLinkBase/product/$productId');

/// The product id a shared link points to, or null if [uri] isn't one.
/// Accepts the web link (`…/product/<id>`) and the app's own scheme
/// (`agritrade://product/<id>`).
String? productIdFromLink(Uri uri) {
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  String? id;
  if (uri.scheme == 'agritrade' && uri.host == 'product') {
    id = segments.isEmpty ? null : segments.first;
  } else if (segments.length >= 2 && segments.first == 'product') {
    id = segments[1];
  }
  // Firestore ids only — never treat arbitrary text as a document path.
  return id != null && RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id)
      ? id
      : null;
}

/// What gets shared: the listing's name, price, stock and the farmer's
/// general location (municipality, province), plus the link. Never an
/// exact address, GPS position, phone number or email.
String productShareText({
  required String name,
  required num price,
  required String unit,
  required num quantity,
  required String location,
  required Uri link,
}) => [
  '$name available on AgriTrade+',
  formatPriceWithUnit(price, unit),
  quantity > 0
      ? 'Available Stock: ${formatStock(quantity, unit)}'
      : 'Currently out of stock',
  if (location.isNotEmpty) 'Location: $location',
  'View Product: $link',
].join('\n');

class ProductShareService {
  const ProductShareService._();

  /// Opens the device's share sheet for an existing listing. Nothing is
  /// written anywhere — the link just names the product.
  static Future<void> share(
    BuildContext context,
    String productId,
    Map<String, dynamic> product,
  ) async {
    // iPad anchors the share sheet to the button that opened it.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null || !box.hasSize
        ? null
        : box.localToGlobal(Offset.zero) & box.size;

    final name = (product['name'] ?? 'Product').toString();
    final unit = (product['unit'] as String?)?.trim().isNotEmpty == true
        ? product['unit'] as String
        : unitForProductName(name);
    final text = productShareText(
      name: name,
      price:
          (product['retailPrice'] as num?) ?? (product['price'] as num?) ?? 0,
      unit: unit,
      quantity: (product['quantity'] as num?) ?? 0,
      location: await _generalLocation(product['farmerId']?.toString()),
      link: productLink(productId),
    );
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: '$name on AgriTrade+',
        sharePositionOrigin: origin,
      ),
    );
  }

  // "Laurel, Batangas" from the farmer's public profile — the general area
  // already shown on the listing, nothing more precise.
  static Future<String> _generalLocation(String? farmerId) async {
    if (farmerId == null || farmerId.isEmpty) return '';
    try {
      final profile =
          (await FirebaseFirestore.instance
                  .collection('publicProfiles')
                  .doc(farmerId)
                  .get())
              .data() ??
          const {};
      return [profile['municipality'], profile['province']]
          .map((v) => (v ?? '').toString().trim())
          .where((v) => v.isNotEmpty)
          .join(', ');
    } catch (_) {
      return '';
    }
  }
}

/// Opens Product Details when the app is launched from, or receives, a
/// shared product link.
///
/// A link can arrive before anyone is signed in or before Home exists, so
/// it is held until a Home screen reports it is ready (the same approach
/// PushNotificationService uses for a notification tapped at cold start).
/// The product is then read under the signed-in user's normal permissions
/// — a link grants no access of its own.
class ProductLinkService {
  const ProductLinkService._();

  static StreamSubscription<Uri>? _links;
  static String? _pendingProductId;
  static bool _homeReady = false;

  /// Call once at startup. Delivers the launch link as well as any that
  /// arrive while the app is running.
  static void start() {
    try {
      _links ??= AppLinks().uriLinkStream.listen(_onLink, onError: (_) {});
    } catch (_) {
      // Links unsupported on this platform — sharing still works.
    }
  }

  /// Call from the Farmer/Buyer Home screen's initState.
  static void homeReady() {
    _homeReady = true;
    _openPending();
  }

  static void _onLink(Uri uri) {
    final productId = productIdFromLink(uri);
    if (productId == null) return;
    _pendingProductId = productId;
    if (_homeReady) _openPending();
  }

  static Future<void> _openPending() async {
    final productId = _pendingProductId;
    if (productId == null || FirebaseAuth.instance.currentUser == null) return;
    _pendingProductId = null;
    // Let Home finish its first frame before pushing on top of it.
    await Future.delayed(const Duration(milliseconds: 300));

    Map<String, dynamic>? product;
    try {
      product =
          (await FirebaseFirestore.instance
                  .collection('products')
                  .doc(productId)
                  .get())
              .data();
    } catch (_) {
      product = null;
    }
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null || !navigator.mounted) return;
    if (product == null ||
        product['isArchived'] == true ||
        product['isSuspended'] == true) {
      ScaffoldMessenger.maybeOf(navigator.context)?.showSnackBar(
        const SnackBar(content: Text('This product is no longer available.')),
      );
      return;
    }
    navigator.push(
      MaterialPageRoute(
        builder: (_) =>
            ProductDetailScreen(productId: productId, data: product!),
      ),
    );
  }
}
