import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/indexer_provider.dart';
import '../widgets/indexer_choice_dialog.dart';

class IndexerScreen extends ConsumerStatefulWidget {
  const IndexerScreen({super.key});

  @override
  ConsumerState<IndexerScreen> createState() => _IndexerScreenState();
}

class _IndexerScreenState extends ConsumerState<IndexerScreen> {
  @override
  void initState() {
    super.initState();
    // Load counts when screen initializes
    Future.microtask(() {
      ref.read(indexerProvider.notifier).loadCounts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final indexerState = ref.watch(indexerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Indexer'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        children: [
          _buildSettingsGroup(
            title: 'Database Operations',
            icon: Icons.storage_rounded,
            children: [
              _buildOperationTile(
                id: 'optimize_stats_db',
                icon: Icons.analytics_rounded,
                warningMessage:
                    'This operation requires an app restart to apply changes.',
              ),
              _buildOperationTile(
                id: 'optimize_user_data_db',
                icon: Icons.people_rounded,
                warningMessage:
                    'This operation requires an app restart to apply changes.',
              ),
            ],
          ),
          _buildSettingsGroup(
            title: 'Cover & Search',
            icon: Icons.image_search_rounded,
            children: [
              _buildOperationTile(
                id: 'rebuild_cover_caches',
                icon: Icons.image_rounded,
              ),
              _buildOperationTile(
                id: 'rebuild_search_indexes',
                icon: Icons.search_rounded,
                warningMessage:
                    'You may need to restart the app for search index changes to fully apply.',
              ),
            ],
          ),
          _buildSettingsGroup(
            title: 'Content Caches',
            icon: Icons.collections_bookmark_rounded,
            children: [
              _buildOperationTile(
                id: 'rebuild_lyrics_cache',
                icon: Icons.lyrics_rounded,
              ),
              _buildOperationTile(
                id: 'rebuild_waveform_cache',
                icon: Icons.graphic_eq_rounded,
              ),
              _buildOperationTile(
                id: 'rebuild_color_cache',
                icon: Icons.palette_rounded,
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSettingsGroup({
    required String title,
    required List<Widget> children,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    final List<Widget> childrenWithDividers = [];

    for (int i = 0; i < children.length; i++) {
      childrenWithDividers.add(children[i]);
      if (i < children.length - 1) {
        childrenWithDividers.add(
          Divider(
            height: 1,
            indent: 56,
            endIndent: 16,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0),
          child: Row(
            children: [
              Icon(icon, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        Card(
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: childrenWithDividers,
          ),
        ),
      ],
    );
  }

  Widget _buildOperationTile({
    required String id,
    required IconData icon,
    String? warningMessage,
  }) {
    final operation = ref.watch(indexerProvider).operations[id];
    if (operation == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final bool isRunning = operation.isRunning;
    final bool hasError = operation.state == IndexerOperationState.error;
    final bool isCompleted = operation.state == IndexerOperationState.completed;
    final bool isFullyCached = operation.isFullyCached;

    String subtitle;
    if (isRunning) {
      subtitle = 'Processing ${operation.progressText}...';
    } else if (hasError) {
      subtitle = 'Error: ${operation.errorMessage ?? 'Unknown error'}';
    } else if (isCompleted) {
      if (operation.isDatabaseOperation) {
        subtitle = 'Completed';
      } else {
        subtitle =
            'Completed - ${operation.processedCount}/${operation.totalCount} cached' +
                (operation.failedCount > 0
                    ? ' (${operation.failedCount} failed)'
                    : '');
      }
    } else {
      // Not running and not completed
      if (operation.isDatabaseOperation) {
        subtitle = 'Ready to optimize';
      } else if (operation.processedCount == 0 && operation.totalCount > 0) {
        subtitle = '0/${operation.totalCount} cached';
      } else {
        subtitle =
            '${operation.processedCount}/${operation.totalCount} cached' +
                (operation.failedCount > 0
                    ? ' (${operation.failedCount} failed)'
                    : '');
      }
    }

    // Determine icon color
    Color iconColor;
    if (hasError) {
      iconColor = Colors.red;
    } else if (isCompleted) {
      iconColor = theme.colorScheme.primary;
    } else if (isFullyCached) {
      iconColor = theme.colorScheme.primary;
    } else {
      iconColor = theme.colorScheme.onSurfaceVariant;
    }

    return ListTile(
      leading: Icon(
        icon,
        color: iconColor,
      ),
      title: Text(
        operation.name,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(operation.description),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: hasError
                  ? Colors.red.shade700
                  : isRunning
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
              fontWeight: isRunning ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
          if (isRunning && operation.totalCount > 0) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: operation.progress,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(2),
            ),
          ],
        ],
      ),
      trailing: isRunning
          ? IconButton(
              icon: const Icon(Icons.stop_rounded, color: Colors.red),
              onPressed: () => _cancelOperation(),
            )
          : operation.failedCount > 0 && !isRunning
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${operation.failedCount}',
                        style: TextStyle(
                          color: Colors.red.shade800,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, size: 20),
                  ],
                )
              : const Icon(Icons.chevron_right, size: 20),
      onTap: isRunning
          ? null
          : () => _handleOperationTap(operation, warningMessage),
    );
  }

  Future<void> _handleOperationTap(
      IndexerOperation operation, String? warningMessage) async {
    // If operation has failed items (regardless of completion state), show choice dialog with failed option
    if (operation.failedCount > 0) {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(operation.name),
          content: Text(
              'This cache has ${operation.failedCount} failed items. What would you like to do?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'view_fails'),
              child: Text('View ${operation.failedCount} Failed'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'retry_failed'),
              child: const Text('Retry Failed'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'force'),
              child: const Text('Force Rebuild'),
            ),
          ],
        ),
      );

      if (action == 'view_fails') {
        await _showFailedItemsDialog(operation);
        return;
      } else if (action == 'retry_failed') {
        await _retryFailedItems(operation);
        return;
      } else if (action != 'force') {
        return; // Cancelled
      }

      // User chose force, continue with force=true
      await _startOperation(operation,
          force: true, warningMessage: warningMessage);
      return;
    }

    // If operation is fully cached with no failures, show simple choice
    if (operation.isFullyCached && !operation.isDatabaseOperation) {
      final forceRebuild = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(operation.name),
          content: Text(
            'This cache is already complete (${operation.processedCount}/${operation.totalCount}). Do you want to force rebuild it?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Force Rebuild'),
            ),
          ],
        ),
      );

      if (forceRebuild != true) return;
      await _startOperation(operation,
          force: true, warningMessage: warningMessage);
      return;
    }

    // For database operations, just show cancel/do-it dialog
    if (operation.isDatabaseOperation) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(operation.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(operation.description),
              if (warningMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          warningMessage!,
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Do It'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
      await _startOperation(operation,
          force: false, warningMessage: warningMessage);
      return;
    }

    // Show normal choice dialog (Just Missing / Force All)
    final force = await showIndexerChoiceDialog(
      context,
      title: operation.name,
      description: operation.description,
      warningMessage: warningMessage,
    );

    if (force == null) return; // Cancelled

    await _startOperation(operation,
        force: force, warningMessage: warningMessage);
  }

  Future<void> _startOperation(IndexerOperation operation,
      {required bool force, String? warningMessage}) async {
    // Show progress dialog for blocking operations
    if (operation.isBlocking) {
      _showBlockingProgressDialog(operation);
    }

    final result = await ref.read(indexerProvider.notifier).startOperation(
          operation.id,
          force: force,
        );

    // Close blocking dialog if shown
    if (operation.isBlocking && mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    // Show restart dialog if required
    if (result.success && operation.requiresRestart && mounted) {
      await _showRestartDialog();
    }

    // Show warning dialog if there are warnings
    if (result.warnings != null && result.warnings!.isNotEmpty && mounted) {
      await _showWarningsDialog(operation.name, result.warnings!);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? null : Colors.red.shade700,
      ),
    );
  }

  void _cancelOperation() {
    ref.read(indexerProvider.notifier).cancelOperation();
  }

  void _showBlockingProgressDialog(IndexerOperation operation) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(operation.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('Optimizing ${operation.name.toLowerCase()}...'),
              const SizedBox(height: 8),
              const Text(
                'Please do not close the app',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRestartDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.restart_alt, color: Colors.blue, size: 48),
        title: const Text('Restart Required'),
        content: const Text(
          'The operation has been completed successfully.\n\n'
          'The app needs to restart to apply all changes properly.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _restartApp();
            },
            child: const Text('Restart Now'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFailedItemsDialog(IndexerOperation operation) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.error_outline, color: Colors.red, size: 48),
        title: Text('${operation.failedCount} Failed Items'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The following items could not be processed:',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: operation.failedItems.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Expanded(
                            child: Text(
                              operation.failedItems[index],
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _retryFailedItems(IndexerOperation operation) async {
    // For now, just restart the operation with force=false to retry failed items
    // This will re-process all missing items including the failed ones
    final result = await ref
        .read(indexerProvider.notifier)
        .startOperation(operation.id, force: false);

    if (result.warnings != null && result.warnings!.isNotEmpty && mounted) {
      await _showWarningsDialog(operation.name, result.warnings!);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? null : Colors.red.shade700,
      ),
    );
  }

  Future<void> _showWarningsDialog(
      String operationName, List<String> warnings) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: Colors.orange, size: 48),
        title: Text('$operationName Warnings'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The following items could not be processed:',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: warnings.length.clamp(0, 10),
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          Expanded(
                            child: Text(
                              warnings[index],
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (warnings.length > 10) ...[
                const SizedBox(height: 8),
                Text(
                  '... and ${warnings.length - 10} more',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _restartApp() async {
    if (Platform.isAndroid) {
      try {
        const platform = MethodChannel('gru_songs/app');
        await platform.invokeMethod('restartApp');
      } catch (e) {
        exit(0);
      }
    } else {
      exit(0);
    }
  }
}
