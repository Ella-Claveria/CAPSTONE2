import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// "Public Location Preview" on farmer registration: once a barangay is
/// chosen, exactly what buyers will see — the barangay, then the
/// municipality and province — and a note that the exact coordinates stay
/// private. Uses the real selected barangay, never a sample. Registration
/// is open to Laurel, Batangas only, so those two are fixed.
class PublicLocationPreview extends StatelessWidget {
  final String barangay;
  final String municipality;
  final String province;

  const PublicLocationPreview({
    super.key,
    required this.barangay,
    this.municipality = 'Laurel',
    this.province = 'Batangas',
  });

  static const _font = 'Montserrat';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accent),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: what this is, and who sees it.
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: AppTheme.accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.visibility_outlined,
                  size: 16,
                  color: AppTheme.dark,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Public Location Preview',
                      style: TextStyle(
                        fontFamily: _font,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.dark,
                      ),
                    ),
                    Text(
                      'What buyers will see',
                      style: TextStyle(
                        fontFamily: _font,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // The location as it appears to buyers.
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0F0E3210),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on_rounded,
                  size: 22,
                  color: AppTheme.mid,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        barangay,
                        style: const TextStyle(
                          fontFamily: _font,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.dark,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '$municipality, $province',
                        style: const TextStyle(
                          fontFamily: _font,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // What stays private.
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.lock_outline_rounded,
                  size: 14,
                  color: Colors.black45,
                ),
              ),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Your exact coordinates will not be displayed publicly.',
                  style: TextStyle(
                    fontFamily: _font,
                    fontSize: 11.5,
                    color: Colors.black54,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
