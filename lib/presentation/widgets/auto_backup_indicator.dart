import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';

class AutoBackupIndicator extends ConsumerStatefulWidget {
  const AutoBackupIndicator({super.key});

  @override
  ConsumerState<AutoBackupIndicator> createState() =>
      _AutoBackupIndicatorState();
}

class _AutoBackupIndicatorState extends ConsumerState<AutoBackupIndicator> {
  @override
  Widget build(BuildContext context) {
    final autoBackupState = ref.watch(autoBackupProvider);
    final lastResult = autoBackupState.lastResult;

    if (lastResult == null) {
      return const SizedBox.shrink();
    }

    if (autoBackupState.isRunning) {
      return _buildIndicator(
        context,
        bgColor: Colors.blue.shade700,
        icon: Icons.backup_rounded,
        text: 'Creating auto-backup...',
        showSpinner: true,
      );
    }

    if (lastResult.success) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) {
            ref.read(autoBackupProvider.notifier).clearLastError();
          }
        });
      });

      return _buildIndicator(
        context,
        bgColor: Colors.green.shade700,
        icon: Icons.check_circle_rounded,
        text: 'Auto-backup completed: ${lastResult.backupFilename}',
        showSpinner: false,
      );
    }

    if (lastResult.permissionDenied) {
      return _buildPermissionErrorIndicator(context, ref);
    }

    return _buildIndicator(
      context,
      bgColor: Colors.red.shade700,
      icon: Icons.error_rounded,
      text: 'Auto-backup failed: ${lastResult.errorMessage}',
      showSpinner: false,
      onTap: () {
        ref.read(autoBackupProvider.notifier).clearLastError();
      },
    );
  }

  Widget _buildIndicator(
    BuildContext context, {
    required Color bgColor,
    required IconData icon,
    required String text,
    required bool showSpinner,
    VoidCallback? onTap,
  }) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Align(
          alignment: Alignment.topCenter,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(20),
            color: bgColor,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showSpinner)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    else
                      Icon(icon, size: 14, color: Colors.white),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        text,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
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

  Widget _buildPermissionErrorIndicator(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 8.0),
        child: Align(
          alignment: Alignment.topCenter,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(20),
            color: Colors.orange.shade800,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_rounded,
                      size: 14, color: Colors.white),
                  const SizedBox(width: 8),
                  const Text(
                    'Permission required for auto-backup',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      ref.read(autoBackupProvider.notifier).requestPermission();
                    },
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.orange.shade800,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Give Permission',
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
