import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _newUsernameController = TextEditingController();

  Future<void> _clearCache() async {
    await DefaultCacheManager().emptyCache();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cache cleared')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Profile', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Text('Current Username: ${authState.username}'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _newUsernameController,
                    decoration: const InputDecoration(
                      labelText: 'New Username',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: () async {
                       if (_newUsernameController.text.isEmpty) return;
                       try {
                         await ref.read(authProvider.notifier).updateUsername(_newUsernameController.text.trim());
                         if(context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Username updated")));
                            _newUsernameController.clear();
                         }
                       } catch (e) {
                         if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                       }
                    },
                    child: const Text('Update Username'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Security', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _oldPasswordController,
                    decoration: const InputDecoration(
                      labelText: 'Old Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _newPasswordController,
                    decoration: const InputDecoration(
                      labelText: 'New Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: () async {
                        if (_oldPasswordController.text.isEmpty || _newPasswordController.text.isEmpty) return;
                        try {
                             await ref.read(authProvider.notifier).updatePassword(
                                _oldPasswordController.text.trim(),
                                _newPasswordController.text.trim(),
                             );
                             if(context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password updated")));
                                _oldPasswordController.clear();
                                _newPasswordController.clear();
                             }
                        } catch (e) {
                            if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                        }
                    },
                    child: const Text('Change Password'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Storage', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  ListTile(
                    title: const Text('Clear Cache'),
                    subtitle: const Text('Remove cached images and temporary files'),
                    trailing: const Icon(Icons.delete_outline),
                    onTap: _clearCache,
                  ),
                ],
              ),
            ),
          ),
           const SizedBox(height: 16),
           OutlinedButton.icon(
             onPressed: () {
               ref.read(authProvider.notifier).logout();
             },
             icon: const Icon(Icons.logout),
             label: const Text('Logout'),
           ),
        ],
      ),
    );
  }
}
