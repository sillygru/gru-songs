import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../services/auto_backup_service.dart';
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
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  Timer? _autoDismissTimer;
  AutoBackupResult? _scheduledResult;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
      value: 1.0,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  void _scheduleAutoDismiss() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      _fadeController.reverse().then((_) {
        if (mounted) {
          ref.read(autoBackupProvider.notifier).clearLastError();
        }
      });
    });
  }

  void _handleDismiss() {
    _autoDismissTimer?.cancel();
    _fadeController.reverse().then((_) {
      if (mounted) {
        ref.read(autoBackupProvider.notifier).clearLastError();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AutoBackupState>(autoBackupProvider, (previous, next) {
      if (next.lastResult != null &&
          !next.isRunning &&
          next.lastResult != _scheduledResult) {
        _scheduledResult = next.lastResult;
        _fadeController.value = 1.0;
        _scheduleAutoDismiss();
      } else if (next.lastResult == null && !next.hasPermissionError) {
        _autoDismissTimer?.cancel();
        _scheduledResult = null;
      }
    });

    final autoBackupState = ref.watch(autoBackupProvider);
    final lastResult = autoBackupState.lastResult;
    final hasPermissionError = autoBackupState.hasPermissionError;

    if (lastResult == null &&
        !hasPermissionError &&
        !autoBackupState.isRunning) {
      return const SizedBox.shrink();
    }

    Widget content;
    if (autoBackupState.isRunning) {
      content = _buildNotification(
        context,
        key: const Key('auto_backup_running'),
        icon: AppIcons.cloudUpload,
        title: 'Backing Up',
        subtitle: 'Creating backup...',
        iconColor: AppTokens.info,
        showSpinner: true,
        onDismiss: _handleDismiss,
      );
    } else if (hasPermissionError ||
        (lastResult != null && lastResult.permissionDenied)) {
      content = _buildPermissionErrorIndicator(
        context,
        ref,
        onDismiss: _handleDismiss,
      );
    } else if (lastResult != null && lastResult.success) {
      content = _buildNotification(
        context,
        key: ValueKey('auto_backup_success_${lastResult.hashCode}'),
        icon: AppIcons.checkCircle,
        title: 'Auto-Backup Complete',
        subtitle: lastResult.backupFilename ?? 'Backup saved',
        iconColor: AppTokens.success,
        showSpinner: false,
        onDismiss: _handleDismiss,
      );
    } else if (lastResult != null) {
      content = _buildNotification(
        context,
        key: ValueKey('auto_backup_failed_${lastResult.hashCode}'),
        icon: AppIcons.error,
        title: 'Auto-Backup Failed',
        subtitle: lastResult.errorMessage ?? 'Unknown error',
        iconColor: AppTokens.danger,
        showSpinner: false,
        onDismiss: _handleDismiss,
      );
    } else {
      return const SizedBox.shrink();
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Align(
          alignment: Alignment.topCenter,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _buildNotification(
    BuildContext context, {
    required Key key,
    required AppIconData icon,
    required String title,
    required String subtitle,
    required Color iconColor,
    required bool showSpinner,
    VoidCallback? onDismiss,
  }) {
    final theme = Theme.of(context);

    return Dismissible(
      key: key,
      direction: DismissDirection.horizontal,
      onDismissed: (_) {
        _autoDismissTimer?.cancel();
        ref.read(autoBackupProvider.notifier).clearLastError();
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: AppTokens.danger.withValues(alpha: 0.2),
          borderRadius: AppTokens.brMd,
        ),
        child: const AppIcon(
          AppIcons.delete,
          color: Colors.white,
          size: 24,
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppTokens.danger.withValues(alpha: 0.2),
          borderRadius: AppTokens.brMd,
        ),
        child: const AppIcon(
          AppIcons.delete,
          color: Colors.white,
          size: 24,
        ),
      ),
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
    );
  }

  Widget _buildPermissionErrorIndicator(
    BuildContext context,
    WidgetRef ref, {
    VoidCallback? onDismiss,
  }) {
    final theme = Theme.of(context);

    return Dismissible(
      key: const Key('auto_backup_permission_error'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) {
        _autoDismissTimer?.cancel();
        ref.read(autoBackupProvider.notifier).clearLastError();
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: AppTokens.danger.withValues(alpha: 0.2),
          borderRadius: AppTokens.brMd,
        ),
        child: const AppIcon(
          AppIcons.delete,
          color: Colors.white,
          size: 24,
        ),
      ),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppTokens.danger.withValues(alpha: 0.2),
          borderRadius: AppTokens.brMd,
        ),
        child: const AppIcon(
          AppIcons.delete,
          color: Colors.white,
          size: 24,
        ),
      ),
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
                    ref.read(autoBackupProvider.notifier).requestPermission();
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
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
                if (onDismiss != null) ...[
                  const SizedBox(width: 8),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
