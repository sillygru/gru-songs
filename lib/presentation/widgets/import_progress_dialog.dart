import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Progress reported by a running import or restore.
class ImportProgress {
  final double progress;
  final String label;

  const ImportProgress({required this.progress, required this.label});
}

/// A modal that reports what an import is doing rather than just spinning.
///
/// Restores re-link every row in the library against the filesystem, which on a
/// large collection is thousands of stat calls — long enough that a bare
/// spinner reads as a hang.
class ImportProgressDialog extends StatelessWidget {
  final ValueListenable<ImportProgress> progress;
  final String title;

  const ImportProgressDialog({
    super.key,
    required this.progress,
    this.title = 'Restoring data',
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(title),
        content: ValueListenableBuilder<ImportProgress>(
          valueListenable: progress,
          builder: (context, value, _) {
            // An indeterminate bar until a stage actually reports a fraction,
            // so early work doesn't look stuck at zero.
            final showDeterminate = value.progress > 0 && value.progress < 1;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: showDeterminate ? value.progress : null,
                ),
                const SizedBox(height: 16),
                Text(value.label),
              ],
            );
          },
        ),
      ),
    );
  }
}
