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

/// A settings row that navigates somewhere or performs an action.
class AppSettingsTile extends StatelessWidget {
  final AppIconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

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
  });

  @override
  Widget build(BuildContext context) {
    return AppListRow(
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

  const AppSettingsSwitch({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppListRow(
      dense: true,
      // The switch itself carries the on/off state, so the glyph is not marked
      // active — it would double up on it.
      leading: AppRowIcon(icon: icon, size: 40),
      title: title,
      subtitle: subtitle,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: Switch(value: value, onChanged: onChanged),
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
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Padding(
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
    );
  }
}

/// Standard page body for a settings screen: one scroll view, one set of
/// margins, room at the bottom for the now-playing bar.
class AppSettingsList extends StatelessWidget {
  final List<Widget> children;

  const AppSettingsList({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppTokens.s4,
        0,
        AppTokens.s4,
        AppTokens.scrollBottomInset,
      ),
      children: children,
    );
  }
}
