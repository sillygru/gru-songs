import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../providers/theme_provider.dart';

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

  void _applyTheme() {
    final selectedMode = AppThemeMode.values[_currentIndex];
    ref.read(themeProvider.notifier).setTheme(selectedMode);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          "Theme set to ${selectedMode.toString().split('.').last.toUpperCase()}"),
      duration: const Duration(seconds: 1),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeProvider);
    final currentThemeMode = themeState.mode;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Theme'),
        centerTitle: true,
      ),
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
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                              if (isApplied)
                                BoxShadow(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.4),
                                  blurRadius: 15,
                                  spreadRadius: 2,
                                ),
                            ],
                          ),
                          foregroundDecoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: isApplied
                                ? Border.all(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    width: 3,
                                  )
                                : Border.all(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    width: 1,
                                  ),
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
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 4,
                                        )
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      color: Colors.white,
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
                    AppThemeMode.values[_currentIndex]
                        .toString()
                        .split('.')
                        .last
                        .toUpperCase(),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                  ),
                  const SizedBox(height: 24),
                  if (AppThemeMode.values[_currentIndex] ==
                      AppThemeMode.custom) ...[
                    _buildColorSection(
                      context,
                      "Primary Color",
                      Color(themeState.customPrimaryColor),
                      (color) => ref
                          .read(themeProvider.notifier)
                          .setCustomColors(primary: color.toARGB32()),
                    ),
                    const SizedBox(height: 16),
                    _buildColorSection(
                      context,
                      "Background color",
                      Color(themeState.customBackgroundColor),
                      (color) => ref
                          .read(themeProvider.notifier)
                          .setCustomColors(background: color.toARGB32()),
                    ),
                    const SizedBox(height: 24),
                  ],
                  SwitchListTile(
                    title:
                        const Text("Match buttons to currently playing cover"),
                    subtitle:
                        const Text("Dynamically extract colors from album art"),
                    value: themeState.useCoverColor,
                    onChanged: (val) => ref
                        .read(themeProvider.notifier)
                        .setCoverColorSettings(useCover: val),
                  ),
                  if (themeState.useCoverColor)
                    SwitchListTile(
                      title: const Text("Apply cover color to whole app"),
                      subtitle:
                          const Text("Updates all screens to match the cover"),
                      value: themeState.applyCoverColorToAll,
                      onChanged: (val) => ref
                          .read(themeProvider.notifier)
                          .setCoverColorSettings(applyAll: val),
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
                          borderRadius: BorderRadius.circular(16),
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

  Widget _buildColorSection(BuildContext context, String label,
      Color currentColor, Function(Color) onColorSelected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildColorOption(currentColor, isSelected: true),
              const VerticalDivider(),
              ...[
                Colors.red,
                Colors.pink,
                Colors.purple,
                Colors.deepPurple,
                Colors.indigo,
                Colors.blue,
                Colors.lightBlue,
                Colors.cyan,
                Colors.teal,
                Colors.green,
                Colors.lightGreen,
                Colors.lime,
                Colors.yellow,
                Colors.amber,
                Colors.orange,
                Colors.deepOrange,
                Colors.brown,
                Colors.grey,
                Colors.blueGrey,
                const Color(0xFF121212),
                const Color(0xFF000000),
                const Color(0xFF1A1A1A),
              ].map((color) => _buildColorOption(color,
                  onTap: () => onColorSelected(color))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildColorOption(Color color,
      {bool isSelected = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white24,
            width: isSelected ? 3 : 1,
          ),
        ),
        child: isSelected
            ? const Icon(Icons.check, size: 20, color: Colors.white)
            : null,
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
      child: Theme(
        data: themeData,
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
                              _buildMockAlbumCard(context, Colors.purple,
                                  "Chill Mix", "Various Artists"),
                              _buildMockAlbumCard(context, Colors.blue,
                                  "Top Hits", "Gru's Picks"),
                              _buildMockAlbumCard(
                                  context, Colors.orange, "Energy", "Workout"),
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
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.05),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.music_note,
                            color: Colors.white70, size: 20),
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
                                    color: Colors.grey, fontSize: 10)),
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
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                  child: Icon(Icons.album, color: Colors.white54, size: 32)),
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
              style: const TextStyle(color: Colors.grey, fontSize: 10)),
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
              color: Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
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
                    style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
          const Icon(Icons.more_vert, size: 18, color: Colors.grey),
        ],
      ),
    );
  }
}
