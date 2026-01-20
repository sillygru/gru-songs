import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'cache_management_screen.dart';
import 'downloader_screen.dart';
import '../../providers/auth_provider.dart';
import '../../providers/providers.dart';
import '../../services/api_service.dart';
import '../../models/shuffle_config.dart';
import '../widgets/fun_stats_view.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _newUsernameController = TextEditingController();

  Future<void> _selectMusicFolder() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      final storage = ref.read(storageServiceProvider);
      await storage.setMusicFolderPath(selectedDirectory);
      ref.invalidate(songsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Music folder updated")));
      }
    }
  }

  Future<void> _selectLyricsFolder() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      final storage = ref.read(storageServiceProvider);
      await storage.setLyricsFolderPath(selectedDirectory);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Lyrics folder updated")));
      }
    }
  }

  void _showServerSettingsDialog() {
    final controller = TextEditingController(text: ApiService.baseUrl);
    bool isTesting = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Server Connection'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Server URL',
                      hintText: 'http://[REDACTED]:9000',
                      border: OutlineInputBorder(),
                      helperText: 'Enter IP:Port (e.g. 10.0.0.5:9000) or full URL',
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (isTesting)
                    const Center(child: CircularProgressIndicator())
                  else
                    TextButton(
                      onPressed: () {
                        controller.text = ApiService.defaultBaseUrl;
                      },
                      child: const Text('Restore Default URL'),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isTesting
                      ? null
                      : () async {
                          setDialogState(() => isTesting = true);
                          String input = controller.text.trim();

                          if (!input.startsWith('http')) {
                            input = 'http://$input';
                          }

                          if (input.endsWith('/')) {
                            input = input.substring(0, input.length - 1);
                          }

                          try {
                            final client = ApiService.createClient();
                            // Use /stats/fun as it's a valid endpoint
                            final testUrl = '$input/stats/fun';
                            final username = ref.read(authProvider).username;
                            final headers = <String, String>{};
                            if (username != null) {
                              headers['x-username'] = username;
                            }

                            debugPrint("Testing connection to: $testUrl");

                            final response = await client
                                .get(Uri.parse(testUrl), headers: headers)
                                .timeout(const Duration(seconds: 5));

                            if (response.statusCode == 200 ||
                                response.statusCode == 401) {
                              ApiService.setBaseUrl(input);
                              await ref
                                  .read(storageServiceProvider)
                                  .setServerUrl(input);

                              if (context.mounted) {
                                Navigator.pop(context);
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text("Connected! Refreshing...")));
                                ref.invalidate(songsProvider);
                                ref.invalidate(userDataProvider);
                              }
                            } else {
                              throw Exception('Status ${response.statusCode}');
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text("Connection Failed: $e")));
                              setDialogState(() => isTesting = false);
                            }
                          }
                        },
                  child: const Text('Test & Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showChangeUsernameDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Username'),
        content: TextField(
          controller: _newUsernameController,
          decoration: const InputDecoration(
            labelText: 'New Username',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (_newUsernameController.text.isEmpty) return;
              try {
                await ref
                    .read(authProvider.notifier)
                    .updateUsername(_newUsernameController.text.trim());
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Username updated")));
                  _newUsernameController.clear();
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(e.toString())));
                }
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (_oldPasswordController.text.isEmpty ||
                  _newPasswordController.text.isEmpty) {
                return;
              }
              try {
                await ref.read(authProvider.notifier).updatePassword(
                      _oldPasswordController.text.trim(),
                      _newPasswordController.text.trim(),
                    );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Password updated")));
                  _oldPasswordController.clear();
                  _newPasswordController.clear();
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(e.toString())));
                }
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final userData = ref.watch(userDataProvider);
    final audioManager = ref.watch(audioPlayerManagerProvider);
    // Use ValueListenableBuilder to listen to shuffle state changes from manager
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(userDataProvider.notifier).refresh();
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 200,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Theme.of(context).colorScheme.primaryContainer,
                        Theme.of(context).scaffoldBackgroundColor,
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: Text(
                          (authState.username ?? "?")
                              .substring(0, 1)
                              .toUpperCase(),
                          style: const TextStyle(
                              fontSize: 32,
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        authState.username ?? "User",
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildStatColumn(
                            'Favorites', userData.favorites.length.toString()),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Fun Stats Section
                    Card(
                      elevation: 0,
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.3),
                      clipBehavior: Clip.antiAlias,
                      child: const ExpansionTile(
                        leading: Icon(Icons.insights),
                        title: Text("Fun Stats",
                            style: TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Text("Your listening habits analyzed"),
                        children: [
                          Padding(
                            padding: EdgeInsets.only(
                                bottom: 16.0, left: 16.0, right: 16.0),
                            child: FunStatsView(),
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Shuffle Personality Selector
                    _buildSectionTitle('Shuffle Personality'),
                    ValueListenableBuilder(
                        valueListenable: audioManager.shuffleStateNotifier,
                        builder: (context, shuffleState, child) {
                          final current = shuffleState.config.personality;
                          return Card(
                            elevation: 0,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.3),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: RadioGroup<ShufflePersonality>(
                                groupValue: current,
                                onChanged: (v) {
                                  if (v != null) {
                                    audioManager.updateShuffleConfig(
                                        shuffleState.config
                                            .copyWith(personality: v));
                                  }
                                },
                                child: Column(
                                  children: [
                                    _buildRadioTile(
                                      title: 'Default',
                                      subtitle: 'Balanced mix with anti-repeat',
                                      value: ShufflePersonality.defaultMode,
                                    ),
                                    _buildRadioTile(
                                      title: 'Explorer',
                                      subtitle: 'Prioritizes new & rare songs',
                                      value: ShufflePersonality.explorer,
                                    ),
                                    _buildRadioTile(
                                      title: 'Consistent',
                                      subtitle: 'Favorites heavy',
                                      value: ShufflePersonality.consistent,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                    const SizedBox(height: 24),

                    _buildSectionTitle('Account'),
                    _buildListTile(
                      icon: Icons.person_outline,
                      title: 'Change Username',
                      subtitle: 'Current: ${authState.username}',
                      onTap: _showChangeUsernameDialog,
                    ),
                    _buildListTile(
                      icon: Icons.lock_outline,
                      title: 'Change Password',
                      onTap: _showChangePasswordDialog,
                    ),
                    const SizedBox(height: 24),
                    _buildSectionTitle('Storage & Folders'),
                    FutureBuilder<String?>(
                      future: ref.read(storageServiceProvider).getMusicFolderPath(),
                      builder: (context, snapshot) {
                        return _buildListTile(
                          icon: Icons.library_music_outlined,
                          title: 'Music Folder',
                          subtitle: snapshot.data ?? 'Not selected',
                          onTap: _selectMusicFolder,
                        );
                      }
                    ),
                    FutureBuilder<String?>(
                      future: ref.read(storageServiceProvider).getLyricsFolderPath(),
                      builder: (context, snapshot) {
                        return _buildListTile(
                          icon: Icons.lyrics_outlined,
                          title: 'Lyrics Folder',
                          subtitle: snapshot.data ?? 'Not selected (Optional)',
                          onTap: _selectLyricsFolder,
                        );
                      }
                    ),
                    _buildListTile(
                      icon: Icons.dns,
                      title: 'Server Settings',
                      subtitle: ApiService.baseUrl,
                      onTap: _showServerSettingsDialog,
                    ),
                    _buildListTile(
                      icon: Icons.storage_outlined,
                      title: 'Manage Cache',
                      subtitle: 'Internal app cache management',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const CacheManagementScreen()),
                        );
                      },
                    ),
                    if (authState.username == 'gru') ...[
                      const SizedBox(height: 24),
                      _buildSectionTitle('Admin'),
                      _buildListTile(
                        icon: Icons.download_outlined,
                        title: 'Server Downloader',
                        subtitle: 'Download songs from YouTube via server',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const DownloaderScreen()),
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: 24),
                    _buildSectionTitle('Actions'),
                    _buildListTile(
                      icon: Icons.logout,
                      title: 'Logout',
                      textColor: Colors.red,
                      iconColor: Colors.red,
                      onTap: () {
                        ref.read(authProvider.notifier).logout();
                      },
                    ),
                    const SizedBox(height: 24),
                  const Text(
                    "Gru Songs v6.2.0",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadioTile({
    required String title,
    required String subtitle,
    required ShufflePersonality value,
  }) {
    return RadioListTile<ShufflePersonality>(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
      value: value,
      dense: true,
      activeColor: Theme.of(context).colorScheme.primary,
    );
  }

  Widget _buildStatColumn(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }

    Widget _buildListTile({

      required IconData icon,

      required String title,

      String? subtitle,

      required VoidCallback onTap,

      Color? textColor,

      Color? iconColor,

    }) {

      return Card(

        elevation: 0,

        color: Theme.of(context)

            .colorScheme

            .surfaceContainerHighest

            .withValues(alpha: 0.3),

        margin: const EdgeInsets.symmetric(vertical: 4),

        child: ListTile(

          leading: Icon(icon, color: iconColor),

          title: Text(title,

              style: TextStyle(color: textColor, fontWeight: FontWeight.w500)),

          subtitle: subtitle != null ? Text(subtitle) : null,

          trailing: const Icon(Icons.chevron_right, size: 20),

          onTap: onTap,

        ),

                  );

                }

              }

              

          

      

  

  

  