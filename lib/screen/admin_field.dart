import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The Admin Portal's text field, in the look of the mobile app's
/// registration fields (GlowField): the field's name above it, then a
/// white pill on a soft shadow — an icon and a thin divider before the
/// text — that glows green while it is being typed in.
///
/// It takes a TextField's own arguments, so a field is switched over by
/// its name alone: the [decoration]'s labelText becomes the name above,
/// its hintText the hint inside, its helperText the line under.
///
/// Search boxes keep their own, plainer pill (adminPillDecoration).
class AdminField extends StatefulWidget {
  final TextEditingController controller;
  final InputDecoration decoration;

  /// Shown before the text, with a divider after it.
  final IconData? icon;
  final bool enabled;
  final int? minLines;
  final int? maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  const AdminField({
    super.key,
    required this.controller,
    this.decoration = const InputDecoration(),
    this.icon,
    this.enabled = true,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  @override
  State<AdminField> createState() => _AdminFieldState();
}

class _AdminFieldState extends State<AdminField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focused != _focusNode.hasFocus) {
        setState(() => _focused = _focusNode.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decoration = widget.decoration;
    final multiline = (widget.maxLines ?? 2) > 1 || (widget.minLines ?? 1) > 1;
    final max = widget.maxLength;

    return AdminFieldFrame(
      label: decoration.labelText,
      helper: decoration.helperText,
      // How much of the allowed length is used, under the field.
      counter: max == null
          ? null
          : ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (context, value, _) => Text(
                '${value.text.characters.length}/$max',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ),
      icon: widget.icon,
      focused: _focused,
      enabled: widget.enabled,
      multiline: multiline,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        maxLength: max,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.inputFormatters,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        style: TextStyle(
          fontSize: 13.5,
          color: scheme.onSurface.withValues(alpha: widget.enabled ? 1 : 0.6),
        ),
        decoration: InputDecoration(
          hintText: decoration.hintText,
          hintStyle: TextStyle(
            fontSize: 13.5,
            color: scheme.onSurface.withValues(alpha: 0.42),
          ),
          suffixIcon: decoration.suffixIcon,
          // The plate around it is the field's shape and colour.
          filled: false,
          isDense: true,
          counterText: '',
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: EdgeInsets.fromLTRB(
            widget.icon == null ? 18 : 12,
            15,
            18,
            15,
          ),
        ),
      ),
    );
  }
}

/// A value that is chosen, not typed (a date), on the same plate as an
/// [AdminField]: its name above, the icon and divider, the value, and a
/// click anywhere on it to choose.
class AdminFieldPlate extends StatelessWidget {
  final String? label;
  final String? helper;
  final IconData? icon;
  final String value;
  final VoidCallback? onTap;

  /// Shown at the end of the plate (a chevron by default).
  final IconData trailing;

  const AdminFieldPlate({
    super.key,
    this.label,
    this.helper,
    this.icon,
    required this.value,
    required this.onTap,
    this.trailing = Icons.expand_more_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AdminFieldFrame(
      label: label,
      helper: helper,
      icon: icon,
      enabled: onTap != null,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(icon == null ? 18 : 12, 15, 12, 15),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, color: scheme.onSurface),
              ),
            ),
            Icon(
              trailing,
              size: 20,
              color: scheme.onSurface.withValues(alpha: 0.55),
            ),
          ],
        ),
      ),
    );
  }
}

/// The name above, the plate, and the line under it — shared by
/// [AdminField] and [AdminFieldPlate].
class AdminFieldFrame extends StatelessWidget {
  final String? label;
  final String? helper;
  final Widget? counter;
  final IconData? icon;
  final bool focused;
  final bool enabled;
  final bool multiline;
  final VoidCallback? onTap;
  final Widget child;

  const AdminFieldFrame({
    super.key,
    this.label,
    this.helper,
    this.counter,
    this.icon,
    this.focused = false,
    this.enabled = true,
    this.multiline = false,
    this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(multiline ? 20 : 30);
    final muted = scheme.onSurface.withValues(alpha: 0.6);

    Widget plate = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: dark
            ? Color.alphaBlend(
                Colors.white.withValues(alpha: enabled ? 0.07 : 0.03),
                scheme.surface,
              )
            : (enabled ? Colors.white : const Color(0xFFF4F5F1)),
        borderRadius: radius,
        border: Border.all(
          color: focused
              ? scheme.primary.withValues(alpha: 0.55)
              : scheme.onSurface.withValues(alpha: 0.07),
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.2),
                  blurRadius: 12,
                  spreadRadius: 0.5,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.25 : 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Row(
        crossAxisAlignment: multiline
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 10,
                top: multiline ? 14 : 0,
              ),
              child: Icon(icon, size: 18, color: scheme.primary),
            ),
            Padding(
              padding: EdgeInsets.only(top: multiline ? 13 : 0),
              child: Container(
                height: 20,
                width: 1,
                color: scheme.onSurface.withValues(alpha: 0.12),
              ),
            ),
          ],
          Expanded(child: child),
        ],
      ),
    );
    if (onTap != null) {
      plate = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: plate,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 7),
        ],
        plate,
        if (helper != null || counter != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: helper == null
                      ? const SizedBox.shrink()
                      : Text(
                          helper!,
                          style: TextStyle(fontSize: 11.5, color: muted),
                        ),
                ),
                ?counter,
              ],
            ),
          ),
      ],
    );
  }
}
