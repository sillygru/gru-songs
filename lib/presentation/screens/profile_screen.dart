import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../providers/auth_provider.dart';
import '../../providers/providers.dart';
import '../../models/shuffle_config.dart';
import '../widgets/fun_stats_view.dart';
import '../widgets/scanning_progress_bar.dart';
import '../components/app_dialog.dart';
import '../components/app_feedback.dart';
import '../components/app_list_row.dart';
import '../components/app_screen_header.dart';
import '../components/app_section_header.dart';
import '../components/app_surface.dart';
import '../tokens/app_tokens.dart';
import 'settings_screen.dart';
import 'backup_management_screen.dart';
import 'custom_shuffle_settings_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  final ScrollController? scrollController;

  const ProfileScreen({super.key, this.scrollController});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  static const double _bottomDockDragDistance = 88.0;

  String _appVersion = '';
  ShufflePersonality? _pendingPersonality;
  bool _hasPersonalityChanges = false;
  bool _isScrolled = false;

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    final scrolled = notification.metrics.pixels > 0;
    if (scrolled != _isScrolled) {
      setState(() => _isScrolled = scrolled);
    }

    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final delta = notification.scrollDelta ?? 0;
      if (delta != 0) {
        ref.read(bottomDockVisibilityProvider.notifier).updateFromDrag(
              scrollDelta: delta,
              dragDistanceForFullToggle: _bottomDockDragDistance,
            );
      }
    } else if (notification is ScrollEndNotification) {
      ref.read(bottomDockVisibilityProvider.notifier).settle();
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _getAppVersion();
  }

  Future<void> _getAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _appVersion = packageInfo.version);
  }

  Future<void> _showChangeUsernameDialog(String? current) async {
    final name = await showAppTextPrompt(
      context,
      title: 'Change Display Name',
      initialValue: current,
      hintText: 'New name',
      confirmLabel: 'Update',
    );
    if (name == null || !mounted) return;

    try {
      await ref.read(authProvider.notifier).setDisplayName(name);
      if (mounted) {
        appSnack(context, 'Name updated', tone: AppTone.success);
      }
    } catch (e) {
      if (mounted) appSnack(context, '$e', tone: AppTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(isScanningProvider)) {
      return const ScanningProgressBar();
    }

    final authState = ref.watch(authProvider);
    final userData = ref.watch(userDataProvider);
    final audioManager = ref.watch(audioPlayerManagerProvider);
    final accent = AppTokens.accentOf(context, ref);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(userDataProvider.notifier).refresh(force: true),
        child: NotificationListener<ScrollNotification>(
          onNotification: _handleScrollNotification,
          child: CustomScrollView(
            controller: widget.scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              AppSliverHeader(title: 'Profile', isScrolled: _isScrolled),

              // Identity — a plain avatar and name, sitting on the background
              // rather than on a gradient banner.
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.s5,
                    AppTokens.s2,
                    AppTokens.s5,
                    AppTokens.s5,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accent.withValues(
                            alpha: AppTokens.accentWashAlpha,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          (authState.username ?? 'U')
                              .substring(0, 1)
                              .toUpperCase(),
                          style: AppTokens.screenTitle(context)
                              .copyWith(color: accent),
                        ),
                      ),
                      const SizedBox(width: AppTokens.s4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              authState.username ?? 'User',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTokens.screenTitle(context),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Wispie v$_appVersion',
                              style: AppTokens.meta(context),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Stats
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.s4,
                  ),
                  child: AppSurface(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppTokens.s4,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        AppStatTile(
                          label: 'Favorites',
                          value: '${userData.favorites.length}',
                        ),
                        AppStatTile(
                          label: 'Playlists',
                          value:
                              '${userData.playlists.where((p) => !p.isRecommendation).length}',
                        ),
                        AppStatTile(
                          label: 'Hidden',
                          value: '${userData.hidden.length}',
                        ),
                        AppStatTile(
                          label: 'Suggest-less',
                          value: '${userData.suggestLess.length}',
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Fun stats
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppTokens.s4,
                    AppTokens.s4,
                    AppTokens.s4,
                    0,
                  ),
                  child: AppSurface(
                    padding: EdgeInsets.zero,
                    child: ClipRRect(
                      borderRadius: AppTokens.brMd,
                      child: ExpansionTile(
                        leading: Icon(Icons.insights_rounded, color: accent),
                        title: const Text('Fun Stats'),
                        subtitle: const Text('Your listening habits analyzed'),
                        shape: const Border(),
                        collapsedShape: const Border(),
                        children: const [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              AppTokens.s4,
                              0,
                              AppTokens.s4,
                              AppTokens.s4,
                            ),
                            child: FunStatsView(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Shuffle personality
              const SliverToBoxAdapter(
                child: AppSectionHeader(label: 'Shuffle Personality'),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.s4,
                  ),
                  child: ValueListenableBuilder<ShuffleState>(
                    valueListenable: audioManager.shuffleStateNotifier,
                    builder: (context, shuffleState, child) {
                      final current = shuffleState.config.personality;
                      final selectedValue = _pendingPersonality ?? current;

                      return AppSurface(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppTokens.s2,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RadioGroup<ShufflePersonality>(
                              groupValue: selectedValue,
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() {
                                  _pendingPersonality = v;
                                  _hasPersonalityChanges = v != current;
                                });
                              },
                              child: const Column(
                                children: [
                                  _PersonalityTile(
                                    title: 'Default',
                                    subtitle: 'Balanced mix with anti-repeat',
                                    value: ShufflePersonality.defaultMode,
                                  ),
                                  _PersonalityTile(
                                    title: 'Explorer',
                                    subtitle: 'Prioritizes new & rare songs',
                                    value: ShufflePersonality.explorer,
                                  ),
                                  _PersonalityTile(
                                    title: 'Consistent',
                                    subtitle: 'Favorites heavy',
                                    value: ShufflePersonality.consistent,
                                  ),
                                  _PersonalityTile(
                                    title: 'Custom',
                                    subtitle: 'Configure your own shuffle',
                                    value: ShufflePersonality.custom,
                                  ),
                                ],
                              ),
                            ),
                            if (_hasPersonalityChanges)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppTokens.s4,
                                  AppTokens.s2,
                                  AppTokens.s2,
                                  AppTokens.s1,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Applies to the next queue',
                                        style: AppTokens.meta(context)
                                            .copyWith(color: accent),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => setState(() {
                                        _pendingPersonality = null;
                                        _hasPersonalityChanges = false;
                                      }),
                                      child: const Text('Cancel'),
                                    ),
                                    const SizedBox(width: AppTokens.s2),
                                    FilledButton(
                                      onPressed: () {
                                        audioManager.updateShuffleConfig(
                                          shuffleState.config.copyWith(
                                            personality: _pendingPersonality!,
                                          ),
                                          applyToCurrentQueue: false,
                                        );
                                        setState(() {
                                          _pendingPersonality = null;
                                          _hasPersonalityChanges = false;
                                        });
                                        appSnack(context, 'Personality saved',
                                            tone: AppTone.success);
                                      },
                                      child: const Text('Apply'),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: ValueListenableBuilder<ShuffleState>(
                  valueListenable: audioManager.shuffleStateNotifier,
                  builder: (context, shuffleState, child) {
                    if (shuffleState.config.personality !=
                        ShufflePersonality.custom) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppTokens.s4,
                        AppTokens.s3,
                        AppTokens.s4,
                        0,
                      ),
                      child: AppSurfaceGroup(
                        children: [
                          _navRow(
                            icon: Icons.tune_rounded,
                            title: 'Configure Custom Shuffle',
                            subtitle: 'Adjust shuffle behavior settings',
                            accent: accent,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const CustomShuffleSettingsScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Profile / Data / App
              const SliverToBoxAdapter(
                child: AppSectionHeader(label: 'Profile'),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
                  child: AppSurfaceGroup(
                    children: [
                      _navRow(
                        icon: Icons.person_outline_rounded,
                        title: 'Change Display Name',
                        subtitle: 'Current: ${authState.username}',
                        accent: accent,
                        onTap: () =>
                            _showChangeUsernameDialog(authState.username),
                      ),
                      _navRow(
                        icon: Icons.backup_rounded,
                        title: 'Manage Backups',
                        subtitle: 'Create, restore, and manage app backups',
                        accent: accent,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BackupManagementScreen(),
                          ),
                        ),
                      ),
                      _navRow(
                        icon: Icons.settings_rounded,
                        title: 'Settings',
                        subtitle: 'Theme & storage',
                        accent: accent,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SliverPadding(
                padding: EdgeInsets.only(bottom: AppTokens.scrollBottomInset),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return AppListRow(
      leading: AppRowIcon(icon: icon, color: accent),
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: AppTokens.fgTertiary,
      ),
    );
  }
}

class _PersonalityTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final ShufflePersonality value;

  const _PersonalityTile({
    required this.title,
    required this.subtitle,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<ShufflePersonality>(
      value: value,
      dense: true,
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}
