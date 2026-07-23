import 'package:flutter/material.dart';
import '../components/ambient_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/theme_provider.dart';
import '../components/app_feedback.dart';
import '../components/app_screen_header.dart';
import '../tokens/app_tokens.dart';

class ThemeSelectionScreen extends ConsumerStatefulWidget {
  const ThemeSelectionScreen({super.key});

  @override
  ConsumerState<ThemeSelectionScreen> createState() =>
      _ThemeSelectionScreenState();
}

class _ThemeSelectionScreenState extends ConsumerState<ThemeSelectionScreen> {
  late PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    final currentTheme = ref.read(themeProvider).mode;
    _currentIndex = AppThemeMode.values.indexOf(currentTheme);
    _pageController = PageController(
      viewportFraction: 0.7,
      initialPage: _currentIndex,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _getModeName(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.defaultTheme:
        return "SIGNATURE";
      case AppThemeMode.lightBlue:
        return "BLUE";
      case AppThemeMode.oled:
        return "OLED";
      case AppThemeMode.matchCover:
        return "MATCH WITH COVER";
    }
  }

  void _applyTheme() {
    final selectedMode = AppThemeMode.values[_currentIndex];
    ref.read(themeProvider.notifier).setTheme(selectedMode);

    appSnack(context, 'Theme set to ${_getModeName(selectedMode)}');
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    final currentThemeMode = themeState.mode;

    return AmbientScaffold(
      appBar: const AppTopBar(title: 'Choose Theme'),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            SizedBox(
              height: 400,
              child: PageView.builder(
                controller: _pageController,
                itemCount: AppThemeMode.values.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  final mode = AppThemeMode.values[index];
                  final isApplied = mode == currentThemeMode;
                  final isFocused = index == _currentIndex;

                  return AnimatedScale(
                    scale: isFocused ? 1.0 : 0.9,
                    duration: const Duration(milliseconds: 300),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 9 / 18,
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: AppTokens.s2,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: AppTokens.brMd,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              RepaintBoundary(
                                child: IgnorePointer(
                                  child: FittedBox(
                                    fit: BoxFit.contain,
                                    child: SizedBox(
                                      width: 420,
                                      height: 840,
                                      child: ThemePreviewWidget(
                                        mode: mode,
                                        themeState:
                                            themeState, // Pass state for custom/cover preview
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (isApplied)
                                Positioned(
                                  top: 10,
                                  right: 10,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.check_rounded,
                                      color: AppTokens.onAccent(
                                        Theme.of(context).colorScheme.primary,
                                      ),
                                      size: 20,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Text(
                    _getModeName(AppThemeMode.values[_currentIndex]),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      onPressed:
                          currentThemeMode == AppThemeMode.values[_currentIndex]
                              ? null
                              : _applyTheme,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: AppTokens.brMd,
                        ),
                      ),
                      child: Text(
                        currentThemeMode == AppThemeMode.values[_currentIndex]
                            ? "Active Theme"
                            : "Apply Theme",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ThemePreviewWidget extends StatelessWidget {
  final AppThemeMode mode;
  final ThemeState themeState;

  const ThemePreviewWidget(
      {super.key, required this.mode, required this.themeState});

  @override
  Widget build(BuildContext context) {
    // Generate a temporary state to preview the selected mode
    final previewState = themeState.copyWith(mode: mode);
    final themeData =
        AppTheme.getTheme(previewState, coverColor: themeState.extractedColor);

    return MediaQuery(
      data: const MediaQueryData(
        size: Size(420, 840),
        padding: EdgeInsets.only(top: 32, bottom: 8),
        devicePixelRatio: 1.0,
      ),
      child: AnimatedTheme(
        data: themeData,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        child: Builder(builder: (context) {
          return Scaffold(
            backgroundColor: themeData.scaffoldBackgroundColor,
            // Removed AppBar/ScrollViews for absolute static performance
            body: Column(
              children: [
                // Mock AppBar
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Text('Wispie',
                            style: TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 18)),
                        const Spacer(),
                        const Icon(Icons.shuffle, size: 20),
                        const SizedBox(width: 16),
                        const Icon(Icons.search, size: 20),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                          child: Text(
                            'Recommended',
                            style: themeData.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: themeData.colorScheme.primary,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 140,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            physics: const NeverScrollableScrollPhysics(),
                            children: [
                              _buildMockAlbumCard(context, AppTokens.info,
                                  "Chill Mix", "Various Artists"),
                              _buildMockAlbumCard(context, AppTokens.info,
                                  "Top Hits", "Gru's Picks"),
                              _buildMockAlbumCard(context, AppTokens.warning,
                                  "Energy", "Workout"),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'All Songs',
                                style:
                                    themeData.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: themeData.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildMockSongTile(
                            context, "Despicable Me", "Pharrell Williams"),
                        _buildMockSongTile(
                            context, "Happy", "Pharrell Williams"),
                        _buildMockSongTile(
                            context, "Double Life", "Pharrell Williams"),
                        _buildMockSongTile(context, "YMCA", "Minions"),
                        _buildMockSongTile(context, "Banana Song", "Minions"),
                      ],
                    ),
                  ),
                ),
                // Mock Now Playing Bar
                Container(
                  margin: const EdgeInsets.all(8),
                  height: 60,
                  decoration: BoxDecoration(
                    color:
                        themeData.colorScheme.surface.withValues(alpha: 0.95),
                    borderRadius: AppTokens.brMd,
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTokens.fgTertiary,
                          borderRadius: AppTokens.brSm,
                        ),
                        child: const Icon(Icons.music_note,
                            color: AppTokens.fgSecondary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Double Life",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 12)),
                            Text("Pharrell Williams",
                                style: TextStyle(
                                    color: AppTokens.fgTertiary, fontSize: 10)),
                          ],
                        ),
                      ),
                      const Icon(Icons.play_arrow, size: 28),
                      const SizedBox(width: 16),
                    ],
                  ),
                ),
                // Mock Nav Bar
                NavigationBar(
                  selectedIndex: 0,
                  height: 60,
                  destinations: const [
                    NavigationDestination(
                        icon: Icon(Icons.home), label: 'Home'),
                    NavigationDestination(
                        icon: Icon(Icons.library_music), label: 'Library'),
                    NavigationDestination(
                        icon: Icon(Icons.person), label: 'Profile'),
                  ],
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildMockAlbumCard(
      BuildContext context, Color color, String title, String subtitle) {
    return Container(
      width: 100,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: AppTokens.brSm,
              ),
              child: const Center(
                  child:
                      Icon(Icons.album, color: AppTokens.fgTertiary, size: 32)),
            ),
          ),
          const SizedBox(height: 6),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(color: AppTokens.fgTertiary, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildMockSongTile(BuildContext context, String title, String artist) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTokens.fgTertiary.withValues(alpha: 0.1),
              borderRadius: AppTokens.brPill,
            ),
            child: const Icon(Icons.music_note, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
                Text(artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTokens.fgTertiary, fontSize: 11)),
              ],
            ),
          ),
          const Icon(Icons.more_vert, size: 18, color: AppTokens.fgTertiary),
        ],
      ),
    );
  }
}
