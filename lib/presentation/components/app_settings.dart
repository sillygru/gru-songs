import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import 'app_list_row.dart';
import 'app_section_header.dart';
import 'app_surface.dart';
import 'app_icon.dart';
import '../tokens/app_icons.dart';

/// The settings vocabulary, in one place.
///
/// `_buildSettingsGroup`, `_buildListTile` and `_buildCompactSlider` had been
/// copy-pasted into nearly every settings screen, each copy drifting a little.
/// These are the shared versions; the screens now only describe *what* the
/// settings are.
class AppSettingsGroup extends StatelessWidget {
  final String label;
  final AppIconData? icon;
  final List<Widget> children;

  const AppSettingsGroup({
    super.key,
    required this.label,
    this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionHeader(
          label: label,
          icon: icon,
          padding: const EdgeInsets.fromLTRB(
            AppTokens.s3,
            AppTokens.s5,
            AppTokens.s3,
            AppTokens.s2,
          ),
        ),
        AppSurfaceGroup(children: children),
      ],
    );
  }
}

/// Marks a row so settings search can find it again and jump to it.
///
/// Rows opt in by passing `searchId:`; the id is the same string the search
/// registry (`settings_registry.dart`) carries. When [AppSettingsList] is given
/// a matching `highlightId`, the row scrolls into view and pulses once.
class _SettingsAnchorScope extends InheritedWidget {
  final String? highlightId;
  final void Function(BuildContext rowContext) register;

  const _SettingsAnchorScope({
    required this.highlightId,
    required this.register,
    required super.child,
  });

  static _SettingsAnchorScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SettingsAnchorScope>();

  @override
  bool updateShouldNotify(_SettingsAnchorScope old) =>
      old.highlightId != highlightId;
}

/// Wraps a row that isn't one of the [AppSettingsTile] family — a bare
/// [AppListRow] with a dropdown, say — so settings search can still reach it.
class AppSettingsAnchor extends StatefulWidget {
  final String id;
  final Widget child;

  const AppSettingsAnchor({super.key, required this.id, required this.child});

  @override
  State<AppSettingsAnchor> createState() => _AppSettingsAnchorState();
}

class _AppSettingsAnchorState extends State<AppSettingsAnchor>
    with SingleTickerProviderStateMixin {
  /// Two washes in and out — long enough to catch the eye after a jump,
  /// short enough that it's gone before it becomes decoration.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  late final Animation<double> _wash = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 3),
  ]).animate(CurvedAnimation(parent: _pulse, curve: AppTokens.cStandard));

  bool _claimed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = _SettingsAnchorScope.maybeOf(context);
    if (_claimed || scope == null || scope.highlightId != widget.id) return;

    _claimed = true;
    scope.register(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pulse.forward();
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_claimed) return widget.child;

    final accent = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _wash,
      builder: (context, child) => DecoratedBox(
        decoration: BoxDecoration(
          color: accent.withValues(
            alpha: AppTokens.accentWashAlpha * _wash.value,
          ),
          borderRadius: AppTokens.brMd,
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// Wraps [child] in a search anchor when [searchId] is set. Every settings row
/// funnels through this, so opting in stays a one-argument change.
Widget _anchored(String? searchId, Widget child) =>
    searchId == null ? child : AppSettingsAnchor(id: searchId, child: child);

/// A settings row that navigates somewhere or performs an action.
class AppSettingsTile extends StatelessWidget {
  final AppIconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Registry id, so settings search can jump to this row. See
  /// `settings_registry.dart`.
  final String? searchId;

  /// Right-hand slot — a value label, a chevron by default.
  final Widget? trailing;

  /// Destructive rows: reset, delete, wipe.
  final bool isDanger;

  const AppSettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.isDanger = false,
    this.searchId,
  });

  @override
  Widget build(BuildContext context) {
    return _anchored(
      searchId,
      AppListRow(
        dense: true,
        // A destructive row overrides the accent with danger — there the colour
        // is the warning, not the theme. With no plate behind the glyph, colour
        // is the only thing marking it out.
        leading: AppRowIcon(
          icon: icon,
          color: isDanger ? AppTokens.danger : null,
          size: 40,
        ),
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        trailing: trailing ??
            (onTap == null
                ? null
                : AppIcon(
                    AppIcons.chevronRight,
                    size: AppTokens.iconSm,
                    color: AppTokens.fgTertiary,
                  )),
      ),
    );
  }
}

/// A boolean setting.
class AppSettingsSwitch extends StatelessWidget {
  final AppIconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Registry id, so settings search can jump to this row.
  final String? searchId;

  const AppSettingsSwitch({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.searchId,
  });

  @override
  Widget build(BuildContext context) {
    return _anchored(
      searchId,
      AppListRow(
        dense: true,
        // The switch itself carries the on/off state, so the glyph is not
        // marked active — it would double up on it.
        leading: AppRowIcon(icon: icon, size: 40),
        title: title,
        subtitle: subtitle,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: Switch(value: value, onChanged: onChanged),
      ),
    );
  }
}

/// A numeric setting with a live value label above its track.
class AppSettingsSlider extends StatelessWidget {
  final AppIconData icon;
  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  /// Registry id, so settings search can jump to this row.
  final String? searchId;

  const AppSettingsSlider({
    super.key,
    required this.icon,
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
    this.onChangeEnd,
    this.searchId,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return _anchored(
      searchId,
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.s3,
          AppTokens.s3,
          AppTokens.s3,
          AppTokens.s1,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppIcon(icon, size: 18, color: AppTokens.fgSecondary),
                const SizedBox(width: AppTokens.s3),
                Expanded(
                  child: Text(title, style: AppTokens.rowTitle(context)),
                ),
                Text(
                  valueLabel,
                  style: AppTokens.meta(context).copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ],
        ),
      ),
    );
  }
}

/// Standard page body for a settings screen: one scroll view, one set of
/// margins, room at the bottom for the now-playing bar.
///
/// Given a [highlightId] — set when the page was opened from settings search —
/// it scrolls the matching row into view and lets it pulse. Reaching a row that
/// hasn't been laid out yet means the list can't stay lazy in that case, so it
/// builds every child up front; settings pages are short enough that this costs
/// nothing.
class AppSettingsList extends StatefulWidget {
  final List<Widget> children;

  /// Registry id of the row to reveal, from `settings_registry.dart`.
  final String? highlightId;

  const AppSettingsList({
    super.key,
    required this.children,
    this.highlightId,
  });

  @override
  State<AppSettingsList> createState() => _AppSettingsListState();
}

class _AppSettingsListState extends State<AppSettingsList> {
  static const EdgeInsets _padding = EdgeInsets.fromLTRB(
    AppTokens.s4,
    0,
    AppTokens.s4,
    AppTokens.scrollBottomInset,
  );

  bool _revealed = false;

  void _register(BuildContext rowContext) {
    if (_revealed) return;
    _revealed = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!rowContext.mounted) return;
      Scrollable.ensureVisible(
        rowContext,
        // A hair above centre: the row lands where the eye already is, with
        // its group header still visible above it for context.
        alignment: 0.3,
        duration: AppTokens.dBase,
        curve: AppTokens.cStandard,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.highlightId == null) {
      return ListView(
        physics: const BouncingScrollPhysics(),
        padding: _padding,
        children: widget.children,
      );
    }

    return _SettingsAnchorScope(
      highlightId: widget.highlightId,
      register: _register,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: _padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: widget.children,
        ),
      ),
    );
  }
}
