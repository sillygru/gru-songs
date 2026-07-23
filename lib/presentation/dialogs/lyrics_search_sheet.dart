import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/lrclib_result.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../components/app_sheet.dart';
import '../tokens/app_tokens.dart';

/// Opens the LRCLIB lyrics picker for [song].
///
/// Returns the chosen lyrics text, or null if the user backed out. Callers
/// decide what to do with it — the player writes it straight to the file, the
/// lyrics editor drops it into its text field so it can be edited first.
Future<String?> showLyricsSearchSheet(
  BuildContext context, {
  required Song song,
}) {
  return showAppSheet<String>(
    context,
    title: 'Find lyrics',
    builder: (context) => _LyricsSearchSheet(song: song),
  );
}

class _LyricsSearchSheet extends ConsumerStatefulWidget {
  final Song song;

  const _LyricsSearchSheet({required this.song});

  @override
  ConsumerState<_LyricsSearchSheet> createState() => _LyricsSearchSheetState();
}

class _LyricsSearchSheetState extends ConsumerState<_LyricsSearchSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;

  List<LrclibResult>? _results;
  bool _searching = false;
  bool _preferPlain = false;
  String? _error;

  /// Drops results from a query the user has already moved on from.
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.song.title);
    _artistController = TextEditingController(text: widget.song.artist);
    // The song's own tags are the best first guess, so search immediately
    // rather than making the user press a button to see the obvious query.
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final token = ++_searchToken;
    setState(() {
      _searching = true;
      _error = null;
    });

    final results = await ref.read(lrclibServiceProvider).findFor(
          widget.song,
          titleOverride: _titleController.text,
          artistOverride: _artistController.text,
        );

    if (!mounted || token != _searchToken) return;

    setState(() {
      _searching = false;
      _results = results;
      _error = results.isEmpty
          ? 'No lyrics found. Try a different title or artist, or check your '
              'connection.'
          : null;
    });
  }

  Future<void> _preview(LrclibResult result) async {
    final lyrics = result.lyricsFor(preferPlain: _preferPlain);
    if (lyrics == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(result.trackName),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              result.instrumental
                  ? 'Marked as instrumental. Applying this clears any lyrics '
                      'stored on the file.'
                  : _previewText(lyrics),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('APPLY'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      Navigator.pop(context, lyrics);
    }
  }

  /// First few lines only — enough to tell two versions apart without turning
  /// the dialog into a full lyric sheet.
  static String _previewText(String lyrics) {
    final lines = lyrics.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.length <= 8) return lines.join('\n');
    return '${lines.take(8).join('\n')}\n…';
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTokens.accentOf(context, ref);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.s5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: _queryField(_titleController, 'Title')),
                    const SizedBox(width: AppTokens.s3),
                    Expanded(child: _queryField(_artistController, 'Artist')),
                  ],
                ),
                const SizedBox(height: AppTokens.s3),
                Row(
                  children: [
                    Expanded(
                      child: _PlainToggle(
                        value: _preferPlain,
                        accent: accent,
                        onChanged: (value) =>
                            setState(() => _preferPlain = value),
                      ),
                    ),
                    const SizedBox(width: AppTokens.s3),
                    FilledButton.icon(
                      onPressed: _searching ? null : _search,
                      icon: const Icon(Icons.search_rounded, size: 18),
                      label: const Text('Search'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.s3),
          Flexible(child: _buildBody(accent)),
        ],
      ),
    );
  }

  Widget _queryField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _search(),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: AppTokens.brSm),
      ),
    );
  }

  Widget _buildBody(Color accent) {
    if (_searching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppTokens.s6),
        child: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }

    final error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTokens.s5,
          AppTokens.s4,
          AppTokens.s5,
          AppTokens.s6,
        ),
        child: Text(
          error,
          textAlign: TextAlign.center,
          style: AppTokens.rowSubtitle(context),
        ),
      );
    }

    final results = _results ?? const <LrclibResult>[];
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: AppTokens.s4),
      itemCount: results.length,
      itemBuilder: (context, index) => _ResultRow(
        result: results[index],
        localDuration: widget.song.duration,
        preferPlain: _preferPlain,
        accent: accent,
        onTap: () => _preview(results[index]),
      ),
    );
  }
}

/// Switches the whole list between synced and plain, rather than asking per
/// result — the choice is a preference, not a per-track decision.
class _PlainToggle extends StatelessWidget {
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  const _PlainToggle({
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppTokens.brSm,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.s1),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                activeColor: accent,
                onChanged: (v) => onChanged(v ?? false),
              ),
            ),
            const SizedBox(width: AppTokens.s2),
            Flexible(
              child: Text(
                'Plain text',
                style: AppTokens.rowSubtitle(context),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final LrclibResult result;
  final Duration? localDuration;
  final bool preferPlain;
  final Color accent;
  final VoidCallback onTap;

  const _ResultRow({
    required this.result,
    required this.localDuration,
    required this.preferPlain,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final available = result.lyricsFor(preferPlain: preferPlain) != null;

    return Opacity(
      opacity: available ? 1 : 0.4,
      child: InkWell(
        onTap: available ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.s5,
            vertical: AppTokens.s3,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      result.trackName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTokens.rowTitle(context),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTokens.rowSubtitle(context),
                    ),
                    const SizedBox(height: 2),
                    Text(_durationLine(), style: AppTokens.meta(context)),
                  ],
                ),
              ),
              const SizedBox(width: AppTokens.s3),
              _badge(context),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    final artist = result.artistName.trim();
    final album = result.albumName.trim();
    if (artist.isEmpty) return album;
    if (album.isEmpty) return artist;
    return '$artist · $album';
  }

  /// The remote length plus how far it is from the local file — the clearest
  /// signal that a result is a different recording rather than a bad tag.
  String _durationLine() {
    final remote = result.duration;
    if (remote == null) return 'Unknown length';

    final formatted = _format(remote);
    final local = localDuration;
    if (local == null) return formatted;

    final deltaSeconds = (remote - local).inSeconds;
    if (deltaSeconds == 0) return '$formatted · exact match';

    final sign = deltaSeconds > 0 ? '+' : '−';
    return '$formatted · $sign${deltaSeconds.abs()}s';
  }

  static String _format(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _badge(BuildContext context) {
    final (label, color) = switch (result) {
      final r when r.instrumental => ('INSTRUMENTAL', AppTokens.fgTertiary),
      final r when r.hasSynced && !preferPlain => ('SYNCED', accent),
      _ => ('PLAIN', AppTokens.fgTertiary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.s2,
        vertical: AppTokens.s1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: AppTokens.brPill,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: color,
        ),
      ),
    );
  }
}
