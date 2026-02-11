import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionGateWidget extends StatelessWidget {
  final VoidCallback onPermissionGranted;

  const PermissionGateWidget({
    super.key,
    required this.onPermissionGranted,
  });

  Future<void> _requestPermission(BuildContext context) async {
    if (Platform.isAndroid) {
      final status = await Permission.manageExternalStorage.request();
      if (status.isGranted) {
        onPermissionGranted();
      } else if (status.isPermanentlyDenied) {
        await openAppSettings();
      }
    } else {
      onPermissionGranted();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.folder_outlined,
              size: 32,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Storage Access',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'To edit song metadata and album artwork, Wispie needs access to your files. This is only used for managing your music library.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _requestPermission(context),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Allow'),
          ),
        ],
      ),
    );
  }
}
