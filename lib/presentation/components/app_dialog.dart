import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';

/// Confirmation dialog — the shape most of the app's ~50 `AlertDialog`s were
/// hand-building, including the red-text destructive variant.
///
/// Returns true when confirmed, null/false otherwise.
Future<bool?> showAppConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool isDanger = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AppDialog(
      title: title,
      message: message,
      actions: [
        AppDialogAction(
          label: cancelLabel,
          onPressed: () => Navigator.pop(context, false),
        ),
        AppDialogAction(
          label: confirmLabel,
          isDanger: isDanger,
          isPrimary: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
}

/// Prompts for a single line of text. Returns the trimmed value, or null if
/// dismissed or left empty.
Future<String?> showAppTextPrompt(
  BuildContext context, {
  required String title,
  String? initialValue,
  String hintText = 'Enter name...',
  String confirmLabel = 'Save',
}) {
  final controller = TextEditingController(text: initialValue ?? '');

  return showDialog<String>(
    context: context,
    builder: (context) => AppDialog(
      title: title,
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hintText),
        onSubmitted: (value) {
          final trimmed = value.trim();
          Navigator.pop(context, trimmed.isEmpty ? null : trimmed);
        },
      ),
      actions: [
        AppDialogAction(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        AppDialogAction(
          label: confirmLabel,
          isPrimary: true,
          onPressed: () {
            final trimmed = controller.text.trim();
            Navigator.pop(context, trimmed.isEmpty ? null : trimmed);
          },
        ),
      ],
    ),
  );
}

/// The app's dialog shell: flat fill, large radius, no outline.
class AppDialog extends StatelessWidget {
  final String title;
  final String? message;

  /// Richer body — a text field, a list of options. Takes precedence over
  /// [message] when both are given.
  final Widget? content;

  final List<Widget> actions;

  const AppDialog({
    super.key,
    required this.title,
    this.message,
    this.content,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: content ??
          (message == null
              ? null
              : Text(message!, style: AppTokens.rowSubtitle(context))),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppTokens.s3,
        0,
        AppTokens.s3,
        AppTokens.s3,
      ),
      actions: actions.isEmpty ? null : actions,
    );
  }
}

/// A dialog button. Primary is filled with the accent; danger is filled with
/// the danger role — the colour carries the meaning, so the label does not need
/// to be red text on a transparent button.
class AppDialogAction extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isDanger;

  const AppDialogAction({
    super.key,
    required this.label,
    this.onPressed,
    this.isPrimary = false,
    this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!isPrimary) {
      return TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: isDanger ? AppTokens.danger : AppTokens.fgSecondary,
        ),
        child: Text(label),
      );
    }

    final fill =
        isDanger ? AppTokens.danger : Theme.of(context).colorScheme.primary;

    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: fill,
        foregroundColor: AppTokens.onAccent(fill),
      ),
      child: Text(label),
    );
  }
}
