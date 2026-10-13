import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../l10n/locale_controller.dart';
import '../theme/app_theme.dart';
import 'coach_mark.dart';

/// The small E | F (English | Filipino) switch — a white pill with the
/// active language in the app's dark green — shown over the photo on the
/// login screens, so the language can be chosen before
/// signing in. The same choice lives under Settings → Language; both go through
/// [LocaleController], which changes the whole app and saves the choice.
///
/// With [introduce], a one-time coach mark points at the switch and says
/// what it is for — the first time a login screen is ever shown on this
/// device, and never again.
class LanguageToggle extends StatefulWidget {
  final bool introduce;

  const LanguageToggle({super.key, this.introduce = false});

  @override
  State<LanguageToggle> createState() => _LanguageToggleState();
}

class _LanguageToggleState extends State<LanguageToggle> {
  // Shared by every login screen, so the tip shows once in total.
  static const _introSeenKey = 'language_toggle_intro_seen';

  final GlobalKey _pillKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.introduce) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _introduce());
    }
  }

  void _introduce() {
    if (!mounted) return;
    final t = AppLocalizations.of(context);
    if (t == null) return;
    showCoachMarksOnce(
      context: context,
      prefsKey: _introSeenKey,
      steps: [
        CoachMarkStep(
          targetKey: _pillKey,
          title: t.languageHintTitle,
          message: t.languageHintMessage,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleController.instance,
      builder: (context, _) {
        final code = LocaleController.instance.languageCode;
        return Container(
          key: _pillKey,
          padding: const EdgeInsets.all(3),
          // The same white surface and soft shadow as the Back button that
          // floats over the photo on the other side (AppBackIcon).
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 6,
                offset: const Offset(0, 1.5),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _segment('E', 'English', 'en', code),
              _segment('F', 'Filipino', 'tl', code),
            ],
          ),
        );
      },
    );
  }

  Widget _segment(String letter, String name, String code, String current) {
    final selected = code == current;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => LocaleController.instance.setLocale(Locale(code)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: 30,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppTheme.dark : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            letter,
            style: GoogleFonts.montserrat(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppTheme.dark,
            ),
          ),
        ),
      ),
    );
  }
}
