import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/agritrade_text.dart';
import '../widgets/login_form_fields.dart';
import '../services/session_prefs_service.dart';
import '../services/auth_routing_service.dart';
import 'auth_route_handler.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'page_transitions.dart';
import '../l10n/app_localizations.dart';

/// The app's front door. With no accounts saved on this device it's just
/// "Log In" or "Don't have an account? Create One." — no role picked here,
/// login itself is role-agnostic (see LoginScreen), and farmer vs. buyer is
/// now a toggle right on the registration form (see RegisterScreen).
///
/// Once "Save login info" has been used at least once, this screen instead
/// shows those accounts as one-tap "continue as" tiles — see the class doc
/// on [SessionPrefsService] for why only the most-recently-used one is
/// truly a single tap, and every other saved account still needs its
/// password typed once.
class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  static const Color dark = AppTheme.dark;
  static const Color _mid = Color(0xFF2E7D32);

  final _sessionPrefs = SessionPrefsService();
  List<SavedAccount> _accounts = [];
  bool _loaded = false;
  // Email currently being verified against Firestore, if any — disables
  // taps and shows a small spinner on that one tile while the check runs.
  String? _resolvingEmail;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final accounts = await _sessionPrefs.getSavedAccounts();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _loaded = true;
    });
  }

  // The account matching Firebase's currently-live session goes straight to
  // its home screen — genuinely one tap. Any other saved account still
  // needs its password: there's no secure way to switch a Firebase session
  // to a different user without it (see SessionPrefsService's doc comment).
  //
  // The locally-remembered `account.role` is only ever used to decide
  // *which* saved account this is — the actual navigation always goes
  // through AuthRoutingService, which re-reads the live role/approvalStatus
  // from Firestore first. That's what keeps a farmer whose approval status
  // changed (or, in principle, any other role change) from ever landing on
  // a screen that's no longer correct for their real, current status.
  Future<void> _continueWithAccount(SavedAccount account) async {
    final current = FirebaseAuth.instance.currentUser;
    if (current == null || (current.email ?? '').toLowerCase() != account.email.toLowerCase()) {
      Navigator.push(
        context,
        slideRoute(LoginScreen(role: account.role, initialEmail: account.email)),
      );
      return;
    }

    setState(() => _resolvingEmail = account.email);
    final result = await AuthRoutingService.decide(current.uid);
    if (!mounted) return;
    setState(() => _resolvingEmail = null);
    await applyAuthRouteResult(context, result);
  }

  Future<void> _removeAccount(SavedAccount account) async {
    await _sessionPrefs.removeSavedAccount(account.email);
    if (!mounted) return;
    setState(() => _accounts.removeWhere((a) => a.email == account.email));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SingleChildScrollView(
            child: Column(
              children: [
                  const SizedBox(height: 24),

                  // ----- Logo -----
                  Container(
                    width: 120,
                    height: 120,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Image.asset(
                      'assets/logo.png',
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.agriculture, size: 60, color: _mid);
                      },
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ----- "AgriTrade+" wordmark, sized to match the reference -----
                  const AgriTradeText(fontSize: 46),

                  const SizedBox(height: 10),

                  // ----- Tagline: "Grow together. Trade directly." -----
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: GoogleFonts.montserrat(
                        fontSize: 19,
                        fontWeight: FontWeight.w500,
                      ),
                      children: [
                        TextSpan(
                          text: 'Grow together. ',
                          style: TextStyle(color: Colors.grey[850]),
                        ),
                        const TextSpan(
                          text: 'Trade directly.',
                          style: TextStyle(color: _mid),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // ----- Small leaf divider -----
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _leafCurve(flipped: false),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.spa, size: 18, color: _mid),
                      ),
                      _leafCurve(flipped: true),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // Deliberately shows neither the tiles nor the login form
                  // until we actually know which one applies — briefly
                  // rendering the login form and then swapping to "Continue
                  // as" tiles (or vice versa) would let a fast tap land on
                  // whichever one wasn't there a moment ago.
                  if (!_loaded)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: dark),
                        ),
                      ),
                    )
                  else if (_accounts.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Continue as',
                        style: GoogleFonts.montserrat(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[800]),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._accounts.map(
                      (a) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _SavedAccountTile(
                          account: a,
                          isResolving: _resolvingEmail == a.email,
                          onTap: _resolvingEmail == null ? () => _continueWithAccount(a) : null,
                          onRemove: () => _removeAccount(a),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.push(context, slideRoute(const LoginScreen())),
                        child: Text(
                          'Log in with another account',
                          style: GoogleFonts.montserrat(fontSize: 13.5, fontWeight: FontWeight.w600, color: dark),
                        ),
                      ),
                    ),
                  ] else
                    // ----- Inline login form, right after the logo and -----
                    // ----- wordmark — the entry screen doubles as the  -----
                    // ----- sign-in door itself, in the same plain white-----
                    // ----- card style as Login/Register/ForgotPassword.-----
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 6)),
                        ],
                      ),
                      child: const LoginFormFields(),
                    ),

                  const SizedBox(height: 18),

                  // ----- Create account -----
                  GestureDetector(
                    onTap: () {
                      Navigator.push(context, slideRoute(const RegisterScreen()));
                    },
                    child: RichText(
                      text: TextSpan(
                        style: GoogleFonts.montserrat(fontSize: 14, color: Colors.black87),
                        children: [
                          TextSpan(text: AppLocalizations.of(context)!.noAccountSignUp),
                          TextSpan(
                            text: AppLocalizations.of(context)!.createOne,
                            style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, color: dark),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
    );
  }

  Widget _leafCurve({required bool flipped}) {
    return Transform.flip(
      flipX: flipped,
      child: CustomPaint(
        size: const Size(70, 16),
        painter: _LeafCurvePainter(),
      ),
    );
  }
}

class _SavedAccountTile extends StatelessWidget {
  final SavedAccount account;
  final VoidCallback? onTap;
  final VoidCallback onRemove;
  // True while this specific tile's tap is being verified against
  // Firestore (see _RoleSelectionScreenState._continueWithAccount) — shows
  // a small spinner in place of the remove button instead of letting the
  // row look like nothing happened.
  final bool isResolving;

  const _SavedAccountTile({
    required this.account,
    required this.onTap,
    required this.onRemove,
    this.isResolving = false,
  });

  static const Color _dark = AppTheme.dark;

  @override
  Widget build(BuildContext context) {
    final initial = account.email.isNotEmpty ? account.email[0].toUpperCase() : '?';
    final isLive = FirebaseAuth.instance.currentUser?.email?.toLowerCase() == account.email.toLowerCase();

    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: Colors.black26,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFE8F5E9),
                child: Text(initial, style: GoogleFonts.montserrat(fontWeight: FontWeight.bold, color: _dark)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.montserrat(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87),
                    ),
                    Text(
                      isResolving
                          ? 'Checking your account…'
                          : (isLive ? '${account.role} · tap to continue' : '${account.role} · needs password'),
                      style: GoogleFonts.montserrat(fontSize: 11.5, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              if (isResolving)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _dark),
                  ),
                )
              else
                IconButton(
                  icon: Icon(Icons.close, size: 18, color: Colors.grey[500]),
                  tooltip: 'Remove',
                  onPressed: onRemove,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeafCurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF9CCC65).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final path = Path()
      ..moveTo(0, size.height)
      ..quadraticBezierTo(size.width * 0.5, 0, size.width, size.height * 0.4);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
