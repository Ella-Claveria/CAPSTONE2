import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/buyer_location_picker.dart';
import 'buyer_saved_products_screen.dart' show buyerSubScreenAppBar;

/// A buyer's optional delivery / pickup preferences.
///
/// The general location (barangay, city) is the same one saved on the
/// account and edited with the same picker used when placing an order. The
/// preferred method and the delivery note are private: they live in
/// users/{uid}/private/fulfillment, which only the account's owner (and an
/// admin) can read — never on the profile other users can see.
class BuyerFulfillmentPreferencesScreen extends StatefulWidget {
  const BuyerFulfillmentPreferencesScreen({super.key});

  @override
  State<BuyerFulfillmentPreferencesScreen> createState() =>
      _BuyerFulfillmentPreferencesScreenState();
}

class _BuyerFulfillmentPreferencesScreenState
    extends State<BuyerFulfillmentPreferencesScreen> {
  static const Color _dark = AppTheme.dark;
  static const _methods = {
    'delivery': 'Delivery',
    'pickup': 'Pickup',
    'either': 'Either',
  };

  final _authService = AuthService();
  final _noteController = TextEditingController();

  String _method = 'either';
  bool _loading = true;
  bool _saving = false;

  DocumentReference<Map<String, dynamic>>? get _userRef {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null
        ? null
        : FirebaseFirestore.instance.collection('users').doc(uid);
  }

  DocumentReference<Map<String, dynamic>>? get _prefsRef =>
      _userRef?.collection('private').doc('fulfillment');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = (await _prefsRef?.get())?.data();
      final method = data?['preferredMethod']?.toString();
      if (_methods.containsKey(method)) _method = method!;
      _noteController.text = (data?['deliveryNote'] ?? '').toString();
    } catch (_) {
      // Nothing saved yet, or offline — the defaults stand.
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final ref = _prefsRef;
    if (ref == null || _saving) return;
    setState(() => _saving = true);
    String message = 'Preferences saved.';
    try {
      await ref.set({
        'preferredMethod': _method,
        'deliveryNote': _noteController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      message = 'Could not save your preferences. Please try again.';
    }
    if (!mounted) return;
    setState(() => _saving = false);
    _snack(message);
  }

  // Same popup used when placing an order, pre-filled with whatever
  // readable address is already on file.
  Future<void> _editLocation(Map<String, dynamic>? data) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final region = data?['region']?.toString();
    final province = data?['province']?.toString();
    final city = data?['municipality']?.toString();
    final barangay = data?['barangay']?.toString();

    BuyerLocationResult? initial;
    if (province != null &&
        province.isNotEmpty &&
        city != null &&
        city.isNotEmpty &&
        barangay != null &&
        barangay.isNotEmpty) {
      initial = BuyerLocationResult(
        region: (region != null && region.isNotEmpty) ? region : province,
        province: province,
        city: city,
        barangay: barangay,
      );
    }

    final result = await showBuyerLocationPicker(context, initial: initial);
    if (result == null || !mounted) return;
    final error = await _authService.saveBuyerLocation(
      uid: uid,
      latitude: result.latitude,
      longitude: result.longitude,
      region: result.region,
      province: result.province,
      city: result.city,
      barangay: result.barangay,
    );
    if (!mounted) return;
    _snack(error ?? 'Location updated.');
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: _dark,
          content: Text(message),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: buyerSubScreenAppBar('Delivery & Pick-up'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _dark))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                _sectionTitle('Preferred method'),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: [
                      for (final entry in _methods.entries)
                        ButtonSegment(
                          value: entry.key,
                          label: Text(entry.value),
                        ),
                    ],
                    selected: {_method},
                    showSelectedIcon: false,
                    onSelectionChanged: (value) =>
                        setState(() => _method = value.first),
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: _dark,
                      selectedForegroundColor: Colors.white,
                      foregroundColor: _dark,
                      textStyle: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                _sectionTitle('Default location'),
                const SizedBox(height: 8),
                _locationCard(),
                const SizedBox(height: 24),

                _sectionTitle('Delivery instructions or landmark'),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteController,
                  maxLines: 3,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'e.g. Green gate beside the barangay hall',
                    hintStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: _dark, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Private to you. Other users never see this on your profile.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: AppTheme.primaryButton(),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text('Save Preferences', style: AppTheme.buttonText()),
                ),
              ],
            ),
    );
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w700,
      color: Colors.black87,
    ),
  );

  Widget _locationCard() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userRef?.snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final readable =
            [data?['barangay'], data?['municipality'], data?['province']]
                .map((v) => (v ?? '').toString())
                .where((v) => v.isNotEmpty)
                .join(', ');

        return Container(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.place_outlined, size: 20, color: _dark),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  readable.isEmpty ? 'Not set' : readable,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _editLocation(data),
                style: TextButton.styleFrom(foregroundColor: _dark),
                child: Text(
                  readable.isEmpty ? 'Set' : 'Change',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
