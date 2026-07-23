import 'package:flutter/material.dart';
import '../components/app_dialog.dart';
import '../tokens/app_tokens.dart';

/// Dialog for choosing between "Just Missing" and "Force All" options
class IndexerChoiceDialog extends StatelessWidget {
  final String title;
  final String description;
  final String? warningMessage;

  const IndexerChoiceDialog({
    super.key,
    required this.title,
    required this.description,
    this.warningMessage,
  });

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(description),
          if (warningMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTokens.warning.withValues(alpha: 0.14),
                borderRadius: AppTokens.brSm,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: AppTokens.warning,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      warningMessage!,
                      style: TextStyle(
                        color: AppTokens.warning,
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
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, false),
          style: AppTokens.tonalButton,
          child: const Text('Just Missing'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Force All'),
        ),
      ],
    );
  }
}

/// Shows the indexer choice dialog and returns the selected option
/// Returns: null = cancelled, false = just missing, true = force all
Future<bool?> showIndexerChoiceDialog(
  BuildContext context, {
  required String title,
  required String description,
  String? warningMessage,
}) async {
  return showDialog<bool>(
    context: context,
    builder: (context) => IndexerChoiceDialog(
      title: title,
      description: description,
      warningMessage: warningMessage,
    ),
  );
}
