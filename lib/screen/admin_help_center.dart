import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../services/admin_faq.dart';
import '../theme/app_theme.dart';
import 'admin_dashboard_screen.dart'
    show AdminEmptyState, AdminPalette, AdminStatusBadge, AdminThemeScope;
import 'admin_filter_controls.dart';

// Help & Support for the Admin Portal: the FAQ (a search with a category
// filter beside it, each answer opening on a click), and FAQ Management,
// where administrators edit the FAQ. The FAQ itself is lib/services/
// admin_faq.dart.

AdminPalette _paletteOf(BuildContext context) =>
    context.getInheritedWidgetOfExactType<AdminThemeScope>()?.palette ??
    AdminPalette.light;

IconData _categoryIcon(AdminFaqCategory category) => switch (category) {
  AdminFaqCategory.account => Icons.lock_person_outlined,
  AdminFaqCategory.users => Icons.groups_outlined,
  AdminFaqCategory.listings => Icons.inventory_2_outlined,
  AdminFaqCategory.transactions => Icons.receipt_long_outlined,
  AdminFaqCategory.pricing => Icons.price_change_outlined,
  AdminFaqCategory.security => Icons.fact_check_outlined,
  AdminFaqCategory.maintenance => Icons.engineering_outlined,
  AdminFaqCategory.general => Icons.help_outline_rounded,
};

/// The FAQ entries to show, and where they came from.
typedef _FaqSource = ({List<AdminFaq> faqs, bool builtIn, bool failed});

/// Published entries from the database; the built-in ones while the
/// database has none (or cannot be read).
_FaqSource _resolve(AsyncSnapshot<List<AdminFaq>> snapshot) {
  if (snapshot.hasError) {
    return (faqs: kDefaultAdminFaqs, builtIn: true, failed: true);
  }
  final stored = snapshot.data ?? const <AdminFaq>[];
  if (stored.isEmpty) {
    return (faqs: kDefaultAdminFaqs, builtIn: true, failed: false);
  }
  return (
    faqs: [
      for (final f in stored)
        if (f.published) f,
    ],
    builtIn: false,
    failed: false,
  );
}

/// Admin menu → Help & Support. [faqs] replaces the database in tests.
Future<void> showAdminHelpCenter(
  BuildContext context, {
  @visibleForTesting Stream<List<AdminFaq>>? faqs,
}) {
  final palette = _paletteOf(context);
  return showDialog<void>(
    context: context,
    builder: (_) => AdminThemeScope(
      palette: palette,
      child: _HelpCenterDialog(palette: palette, faqs: faqs),
    ),
  );
}

class _HelpCenterDialog extends StatefulWidget {
  final AdminPalette palette;
  final Stream<List<AdminFaq>>? faqs;
  const _HelpCenterDialog({required this.palette, this.faqs});

  @override
  State<_HelpCenterDialog> createState() => _HelpCenterDialogState();
}

class _HelpCenterDialogState extends State<_HelpCenterDialog> {
  late final Stream<List<AdminFaq>> _faqs =
      widget.faqs ?? AdminFaqService.watchAll();
  final _search = TextEditingController();
  AdminFaqCategory? _category;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matchesSearch(AdminFaq faq) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    if ('${faq.question} ${faq.answer} ${faq.keywords.join(' ')}'
        .toLowerCase()
        .contains(q)) {
      return true;
    }
    // Words in any order ("password change").
    final terms = adminFaqTerms(q);
    if (terms.isEmpty) return false;
    final own = adminFaqTerms(
      '${faq.question} ${faq.answer} ${faq.keywords.join(' ')}',
    );
    return terms.every(own.contains);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.palette;
    final size = MediaQuery.sizeOf(context);
    final width = math.min(860.0, size.width - 32);
    final height = math.min(760.0, size.height - 48);
    final narrow = width < 620;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: StreamBuilder<List<AdminFaq>>(
          stream: _faqs,
          builder: (context, snapshot) {
            final loading =
                snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData &&
                !snapshot.hasError;
            final source = _resolve(snapshot);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(c),
                _toolbar(c, narrow),
                Divider(height: 1, color: c.border),
                Expanded(
                  child: loading
                      ? const Center(child: AdminLoadingBar())
                      : _faqList(c, source),
                ),
                Divider(height: 1, color: c.border),
                _footer(c, narrow),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(AdminPalette c) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 20, 16, 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: c.greenBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.support_agent_outlined,
            color: AppTheme.dark,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Help & Support',
                style: TextStyle(
                  color: AppTheme.dark,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Answers to common questions about the Admin Portal.',
                style: TextStyle(color: c.textSecondary, fontSize: 12.5),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: () => showAdminFaqManager(context),
          icon: const Icon(Icons.edit_note_rounded, size: 18),
          label: const Text('Manage FAQs'),
          style: TextButton.styleFrom(foregroundColor: AppTheme.dark),
        ),
      ],
    ),
  );

  // The search, with the category filter beside it (under it on a narrow
  // window).
  Widget _toolbar(AdminPalette c, bool narrow) {
    final search = TextField(
      controller: _search,
      onChanged: (_) => setState(() {}),
      style: TextStyle(color: c.textPrimary, fontSize: 13),
      decoration: adminPillDecoration(
        c,
        hint: 'Search questions and answers…',
        icon: Icons.search,
      ),
    );
    final filter = AdminPillDropdown<String>(
      value: _category?.name ?? 'all',
      width: narrow ? double.infinity : 260,
      icon: _category == null
          ? Icons.filter_list_rounded
          : _categoryIcon(_category!),
      items: [
        const DropdownMenuItem(value: 'all', child: Text('All categories')),
        for (final category in AdminFaqCategory.values)
          DropdownMenuItem(value: category.name, child: Text(category.label)),
      ],
      onChanged: (value) => setState(
        () =>
            _category = value == 'all' ? null : AdminFaqCategory.fromId(value),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [search, const SizedBox(height: 8), filter],
            )
          : Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: 10),
                filter,
              ],
            ),
    );
  }

  Widget _faqList(AdminPalette c, _FaqSource source) {
    final shown = [
      for (final faq in source.faqs)
        if ((_category == null || faq.category == _category) &&
            _matchesSearch(faq))
          faq,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 90),
      children: [
        if (source.failed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _notice(
              c,
              'The FAQ database could not be reached, so the built-in FAQs '
              'are shown.',
            ),
          ),
        if (shown.isEmpty)
          AdminEmptyState(
            icon: Icons.search_off_rounded,
            title: 'No matching questions',
            subtitle: _search.text.trim().isEmpty
                ? 'This category has no published questions yet.'
                : 'Try other words, or choose All categories.',
          )
        else
          for (final category in AdminFaqCategory.values)
            if (shown.any((f) => f.category == category)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      _categoryIcon(category),
                      size: 18,
                      color: AppTheme.dark,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      category.label,
                      style: const TextStyle(
                        color: AppTheme.dark,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              for (final faq in shown)
                if (faq.category == category)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _FaqTile(
                      palette: c,
                      faq: faq,
                      expanded: _search.text.trim().isNotEmpty,
                    ),
                  ),
              const SizedBox(height: 6),
            ],
      ],
    );
  }

  // The support team's confirmed contacts (or that they are coming soon),
  // then Close.
  Widget _footer(AdminPalette c, bool narrow) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 10, 24, 14),
    child: Row(
      children: [
        Expanded(child: AdminSupportContacts(palette: c)),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// The support team's confirmed email and number ([adminSupportContacts]),
/// each with a Copy button, at the bottom of Help & Support. Nothing at
/// all while the client has confirmed none.
class AdminSupportContacts extends StatelessWidget {
  final AdminPalette palette;
  const AdminSupportContacts({super.key, required this.palette});

  @override
  Widget build(BuildContext context) {
    final c = palette;
    final contacts = adminSupportContacts;
    if (contacts.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Support:',
          style: TextStyle(
            color: c.textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        for (final contact in contacts)
          Container(
            padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  contact.label == 'Email'
                      ? Icons.mail_outline_rounded
                      : Icons.phone_outlined,
                  size: 15,
                  color: AppTheme.dark,
                ),
                const SizedBox(width: 6),
                SelectableText(
                  contact.value,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  tooltip: 'Copy ${contact.label.toLowerCase()}',
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: contact.value));
                    if (!context.mounted) return;
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      SnackBar(content: Text('${contact.label} copied.')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 15),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

Widget _notice(AdminPalette c, String text) => Container(
  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
  decoration: BoxDecoration(
    color: c.amberBg,
    borderRadius: BorderRadius.circular(12),
  ),
  child: Row(
    children: [
      Icon(Icons.info_outline_rounded, size: 18, color: c.amber),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: TextStyle(color: c.textPrimary, fontSize: 12.5),
        ),
      ),
    ],
  ),
);

/// "Needs review" beside an answer whose procedure is not confirmed yet.
Widget _needsReviewBadge(AdminPalette c) =>
    AdminStatusBadge(text: 'Needs review', color: c.amber, bg: c.amberBg);

/// One question, its answer opening on a click.
class _FaqTile extends StatelessWidget {
  final AdminPalette palette;
  final AdminFaq faq;

  /// Open from the start (while searching).
  final bool expanded;

  const _FaqTile({
    required this.palette,
    required this.faq,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = palette;
    return Material(
      color: c.surfaceAlt,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('${faq.id}-$expanded'),
        initiallyExpanded: expanded,
        title: Text(
          faq.question,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: null,
        iconColor: AppTheme.dark,
        collapsedIconColor: c.textSecondary,
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            faq.answer,
            style: TextStyle(color: c.textSecondary, fontSize: 13, height: 1.5),
          ),
          if (faq.needsReview) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _needsReviewBadge(c),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This procedure still needs to be confirmed.',
                    style: TextStyle(color: c.textMuted, fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ===================================================================
// FAQ Management
// ===================================================================

/// Help & Support › Manage FAQs: every entry, published or not, with
/// search and filters; add, edit, publish or unpublish, and delete. Only an
/// active administrator can read or change `adminFaqs` (firestore.rules).
Future<void> showAdminFaqManager(BuildContext context) {
  final palette = _paletteOf(context);
  return showDialog<void>(
    context: context,
    builder: (_) => AdminThemeScope(
      palette: palette,
      child: _FaqManagerDialog(palette: palette),
    ),
  );
}

class _FaqManagerDialog extends StatefulWidget {
  final AdminPalette palette;
  const _FaqManagerDialog({required this.palette});

  @override
  State<_FaqManagerDialog> createState() => _FaqManagerDialogState();
}

class _FaqManagerDialogState extends State<_FaqManagerDialog> {
  final Stream<List<AdminFaq>> _faqs = AdminFaqService.watchAll();
  String _search = '';
  // 'all' or a category's name.
  String _category = 'all';
  // 'all', 'published' or 'draft'.
  String _status = 'all';
  String? _busyId;

  // Saving the built-in FAQs, the first time the database has none, so
  // they can be edited here: started once, and its result.
  bool _seedStarted = false;
  bool _seedFailed = false;

  void _snack(String text) => ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(text)));

  void _seedOnce() {
    if (_seedStarted) return;
    _seedStarted = true;
    AdminFaqService.importDefaults().catchError((Object _) {
      if (mounted) setState(() => _seedFailed = true);
      return 0;
    });
  }

  Future<void> _togglePublished(AdminFaq faq) async {
    setState(() => _busyId = faq.id);
    try {
      await AdminFaqService.setPublished(faq.id, !faq.published);
      _snack(faq.published ? 'Unpublished.' : 'Published.');
    } catch (_) {
      _snack('The change could not be saved. Please try again.');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(AdminFaq faq) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this FAQ?'),
        content: SizedBox(
          width: 380,
          child: Text(
            '"${faq.question}" will be removed from Help & Support. To hide '
            'it for now instead, unpublish it.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: widget.palette.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;
    setState(() => _busyId = faq.id);
    try {
      await AdminFaqService.delete(faq.id);
      _snack('FAQ deleted.');
    } catch (_) {
      _snack('The FAQ could not be deleted. Please try again.');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _edit(AdminFaq? faq, {required int nextOrder}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AdminThemeScope(
        palette: widget.palette,
        child: _FaqEditorDialog(
          palette: widget.palette,
          faq: faq,
          nextOrder: nextOrder,
        ),
      ),
    );
    if (saved == true) _snack(faq == null ? 'FAQ added.' : 'FAQ saved.');
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.palette;
    final size = MediaQuery.sizeOf(context);
    final width = math.min(860.0, size.width - 32);
    final height = math.min(720.0, size.height - 48);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SizedBox(
        width: width,
        height: height,
        child: StreamBuilder<List<AdminFaq>>(
          stream: _faqs,
          builder: (context, snapshot) {
            final all = snapshot.data ?? const <AdminFaq>[];
            final q = _search.trim().toLowerCase();
            final shown = [
              for (final f in all)
                if ((_category == 'all' || f.category.name == _category) &&
                    (_status == 'all' ||
                        (_status == 'published') == f.published) &&
                    (q.isEmpty ||
                        '${f.question} ${f.answer} ${f.keywords.join(' ')}'
                            .toLowerCase()
                            .contains(q)))
                  f,
            ];
            final nextOrder =
                all.fold<int>(0, (m, f) => math.max(m, f.order)) + 1;

            Widget body;
            if (snapshot.hasError) {
              body = Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'The FAQs could not be loaded. Check your connection, and '
                    'that the database rules for adminFaqs have been '
                    'deployed.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.textSecondary, fontSize: 13),
                  ),
                ),
              );
            } else if (!snapshot.hasData) {
              body = const Center(child: AdminLoadingBar());
            } else if (all.isEmpty && !_seedFailed) {
              // None saved yet: the built-in FAQs are saved, and appear
              // here once they are.
              WidgetsBinding.instance.addPostFrameCallback((_) => _seedOnce());
              body = const Center(child: AdminLoadingBar());
            } else if (all.isEmpty) {
              body = const AdminEmptyState(
                icon: Icons.quiz_outlined,
                title: 'No FAQs yet',
                subtitle: 'Use Add FAQ to write the first one.',
              );
            } else if (shown.isEmpty) {
              body = const AdminEmptyState(
                icon: Icons.search_off_rounded,
                title: 'No FAQs match',
                subtitle: 'Try clearing the search or filters.',
              );
            } else {
              body = ListView.separated(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                itemCount: shown.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _row(c, shown[i], nextOrder),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 14, 2),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Manage FAQs',
                          style: TextStyle(
                            color: AppTheme.dark,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: snapshot.hasData
                            ? () => _edit(null, nextOrder: nextOrder)
                            : null,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add FAQ'),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 10),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: math.min(320, width - 48),
                        child: TextField(
                          onChanged: (v) => setState(() => _search = v),
                          style: TextStyle(color: c.textPrimary, fontSize: 13),
                          decoration: adminPillDecoration(
                            c,
                            hint: 'Search FAQs…',
                            icon: Icons.search,
                          ),
                        ),
                      ),
                      AdminPillDropdown<String>(
                        value: _category,
                        width: 230,
                        icon: Icons.category_outlined,
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text('All categories'),
                          ),
                          for (final cat in AdminFaqCategory.values)
                            DropdownMenuItem(
                              value: cat.name,
                              child: Text(cat.label),
                            ),
                        ],
                        onChanged: (v) => setState(() => _category = v),
                      ),
                      AdminPillDropdown<String>(
                        value: _status,
                        width: 160,
                        icon: Icons.filter_list_rounded,
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All')),
                          DropdownMenuItem(
                            value: 'published',
                            child: Text('Published'),
                          ),
                          DropdownMenuItem(
                            value: 'draft',
                            child: Text('Unpublished'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _status = v),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: c.border),
                Expanded(child: body),
                Divider(height: 1, color: c.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Only published FAQs appear in Help & Support.',
                          style: TextStyle(color: c.textMuted, fontSize: 11.5),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(AdminPalette c, AdminFaq faq, int nextOrder) {
    final busy = _busyId == faq.id;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(_categoryIcon(faq.category), size: 18, color: c.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  faq.question,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      faq.category.label,
                      style: TextStyle(color: c.textSecondary, fontSize: 12),
                    ),
                    faq.published
                        ? AdminStatusBadge(
                            text: 'Published',
                            color: c.green,
                            bg: c.greenBg,
                          )
                        : AdminStatusBadge(
                            text: 'Unpublished',
                            color: c.textSecondary,
                            bg: c.border,
                          ),
                    if (faq.needsReview) _needsReviewBadge(c),
                  ],
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: busy ? null : () => _togglePublished(faq),
            style: TextButton.styleFrom(foregroundColor: AppTheme.dark),
            child: Text(faq.published ? 'Unpublish' : 'Publish'),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: busy ? null : () => _edit(faq, nextOrder: nextOrder),
            icon: Icon(Icons.edit_outlined, size: 18, color: c.textSecondary),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: busy ? null : () => _delete(faq),
            icon: Icon(Icons.delete_outline_rounded, size: 18, color: c.red),
          ),
        ],
      ),
    );
  }
}

/// Add FAQ / Edit: category, question, answer, matching keywords, and
/// whether it is published and needs review.
class _FaqEditorDialog extends StatefulWidget {
  final AdminPalette palette;

  /// Null to add a new entry.
  final AdminFaq? faq;
  final int nextOrder;

  const _FaqEditorDialog({
    required this.palette,
    required this.faq,
    required this.nextOrder,
  });

  @override
  State<_FaqEditorDialog> createState() => _FaqEditorDialogState();
}

class _FaqEditorDialogState extends State<_FaqEditorDialog> {
  late AdminFaqCategory _category =
      widget.faq?.category ?? AdminFaqCategory.general;
  late final _question = TextEditingController(text: widget.faq?.question);
  late final _answer = TextEditingController(text: widget.faq?.answer);
  late final _keywords = TextEditingController(
    text: widget.faq?.keywords.join(', '),
  );
  late bool _published = widget.faq?.published ?? false;
  late bool _needsReview = widget.faq?.needsReview ?? false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _question.dispose();
    _answer.dispose();
    _keywords.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final question = _question.text.trim();
    final answer = _answer.text.trim();
    if (question.length < 5 || answer.length < 5) {
      setState(() => _error = 'Write both the question and its answer.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final faq = AdminFaq(
      id: widget.faq?.id ?? '',
      category: _category,
      question: question,
      answer: answer,
      keywords: [
        for (final k in _keywords.text.split(','))
          if (k.trim().isNotEmpty) k.trim(),
      ],
      published: _published,
      needsReview: _needsReview,
      order: widget.faq?.order ?? widget.nextOrder,
    );
    try {
      await AdminFaqService.save(faq, isNew: widget.faq == null);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'The FAQ could not be saved. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.palette;
    return AlertDialog(
      title: Text(widget.faq == null ? 'Add FAQ' : 'Edit FAQ'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<AdminFaqCategory>(
                initialValue: _category,
                borderRadius: BorderRadius.circular(kAdminPopupRadius),
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final cat in AdminFaqCategory.values)
                    DropdownMenuItem(value: cat, child: Text(cat.label)),
                ],
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 14),
              AdminField(
                controller: _question,
                enabled: !_saving,
                maxLength: 200,
                decoration: adminMultilineDecoration(
                  context,
                  labelText: 'Question',
                ),
              ),
              const SizedBox(height: 10),
              AdminField(
                controller: _answer,
                enabled: !_saving,
                minLines: 4,
                maxLines: 8,
                maxLength: 2000,
                decoration: adminMultilineDecoration(
                  context,
                  labelText: 'Answer',
                ),
              ),
              const SizedBox(height: 10),
              AdminField(
                controller: _keywords,
                enabled: !_saving,
                decoration: adminMultilineDecoration(
                  context,
                  labelText: 'Keywords (comma-separated, optional)',
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  'Other words people may use for this question; the search '
                  'finds it by them too.',
                  style: TextStyle(color: c.textMuted, fontSize: 11.5),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _published,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _published = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Published'),
                subtitle: const Text('Shown in Help & Support.'),
              ),
              CheckboxListTile(
                value: _needsReview,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _needsReview = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Needs review'),
                subtitle: const Text(
                  'The procedure is not confirmed yet; marked on the answer.',
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _error!,
                    style: TextStyle(color: c.red, fontSize: 12.5),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
