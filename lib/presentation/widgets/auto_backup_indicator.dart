import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../tokens/app_tokens.dart';
import '../components/app_icon.dart';
import '../tokens/app_icons.dart';

class AutoBackupIndicator extends ConsumerStatefulWidget {
  const AutoBackupIndicator({super.key});

  @override
  ConsumerState<AutoBackupIndicator> createState() =>
      _AutoBackupIndicatorState();
}

class _AutoBackupIndicatorState extends ConsumerState<AutoBackupIndicator>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _scheduleAutoDismiss() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _fadeController.reverse().then((_) {
          if (mounted) {
            ref.read(autoBackupProvider.notifier).clearLastError();
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final autoBackupState = ref.watch(autoBackupProvider);
    final lastResult = autoBackupState.lastResult;

    if (lastResult == null) {
      return const SizedBox.shrink();
    }

    _fadeController.value = 1.0;

    if (autoBackupState.isRunning) {
      return _buildNotification(
        context,
        icon: AppIcons.cloudUpload,
        title: 'Backing Up',
        subtitle: 'Creating backup...',
        iconColor: AppTokens.info,
        showSpinner: true,
        onDismiss: () {
          ref.read(autoBackupProvider.notifier).clearLastError();
        },
      );
    }

    _scheduleAutoDismiss();

    if (lastResult.success) {
      return _buildNotification(
        context,
        icon: AppIcons.checkCircle,
        title: 'Auto-Backup Complete',
        subtitle: lastResult.backupFilename ?? 'Backup saved',
        iconColor: AppTokens.success,
        showSpinner: false,
        onDismiss: () {
          ref.read(autoBackupProvider.notifier).clearLastError();
        },
      );
    }

    if (lastResult.permissionDenied) {
      return _buildPermissionErrorIndicator(context, ref);
    }

    return _buildNotification(
      context,
      icon: AppIcons.error,
      title: 'Auto-Backup Failed',
      subtitle: lastResult.errorMessage ?? 'Unknown error',
      iconColor: AppTokens.danger,
      showSpinner: false,
      onDismiss: () {
        ref.read(autoBackupProvider.notifier).clearLastError();
      },
    );
  }

  Widget _buildNotification(
    BuildContext context, {
    required AppIconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required bool showSpinner,
    VoidCallback? onDismiss,
  }) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Align(
          alignment: Alignment.topCenter,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Dismissible(
              key: const Key('auto_backup_notification'),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  color: AppTokens.danger,
                  borderRadius: AppTokens.brMd,
                ),
                child: const AppIcon(
                  AppIcons.delete,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              confirmDismiss: (direction) async {
                if (onDismiss != null) {
                  onDismiss();
                }
                return false;
              },
              child: ClipRRect(
                borderRadius: AppTokens.brMd,
                child: RepaintBoundary(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 400),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                        AppTokens.surface(2),
                        theme.colorScheme.surface,
                      ),
                      borderRadius: AppTokens.brMd,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: iconColor.withValues(alpha: 0.12),
                            borderRadius: AppTokens.brSm,
                          ),
                          child: showSpinner
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: iconColor,
                                  ),
                                )
                              : AppIcon(
                                  icon,
                                  color: iconColor,
                                  size: 24,
                                ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                subtitle,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (onDismiss != null)
                          InkWell(
                            onTap: onDismiss,
                            borderRadius: AppTokens.brSm,
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: AppIcon(
                                AppIcons.close,
                                size: 18,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionErrorIndicator(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Align(
          alignment: Alignment.topCenter,
          child: ClipRRect(
            borderRadius: AppTokens.brMd,
            child: RepaintBoundary(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    AppTokens.surface(2),
                    theme.colorScheme.surface,
                  ),
                  borderRadius: AppTokens.brMd,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTokens.warning.withValues(alpha: 0.12),
                        borderRadius: AppTokens.brSm,
                      ),
                      child: const AppIcon(
                        AppIcons.warning,
                        color: AppTokens.warning,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Permission Required',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Auto-backup needs storage access',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      onPressed: () {
                        ref
                            .read(autoBackupProvider.notifier)
                            .requestPermission();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTokens.warning,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppTokens.brSm,
                        ),
                      ),
                      child: const Text(
                        'Grant',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
