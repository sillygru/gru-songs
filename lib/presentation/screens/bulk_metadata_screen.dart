import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/song.dart';
import '../../providers/providers.dart';
import '../../services/bulk_metadata_service.dart';

class BulkMetadataScreen extends ConsumerStatefulWidget {
  final List<Song> songs;

  const BulkMetadataScreen({
    super.key,
    required this.songs,
  });

  @override
  ConsumerState<BulkMetadataScreen> createState() => _BulkMetadataScreenState();
}

class _BulkMetadataScreenState extends ConsumerState<BulkMetadataScreen> {
  final TextEditingController _artistValueController = TextEditingController();
  final TextEditingController _artistFindController = TextEditingController();
  final TextEditingController _artistReplaceController =
      TextEditingController();
  final TextEditingController _titleFindController = TextEditingController();
  final TextEditingController _titleReplaceController = TextEditingController();
  final TextEditingController _albumController = TextEditingController();

  ArtistBulkMode _artistMode = ArtistBulkMode.set;
  bool _artistEnabled = false;
  bool _titleEnabled = false;
  bool _albumEnabled = false;
  bool _titleCaseSensitive = false;
  String _artistJoiner = ' / ';
  bool _saving = false;

  BulkMetadataPlan get _plan {
    return BulkMetadataPlan(
      artistMode: _artistEnabled ? _artistMode : null,
      artistValue: _artistValueController.text,
      artistFind: _artistFindController.text,
      artistReplace: _artistReplaceController.text,
      artistJoiner: _artistJoiner,
      titleMode: _titleEnabled ? TitleBulkMode.replace : null,
      titleFind: _titleFindController.text,
      titleReplace: _titleReplaceController.text,
      titleCaseSensitive: _titleCaseSensitive,
      albumValue: _albumEnabled ? _albumController.text : '',
    );
  }

  @override
  void dispose() {
    _artistValueController.dispose();
    _artistFindController.dispose();
    _artistReplaceController.dispose();
    _titleFindController.dispose();
    _titleReplaceController.dispose();
    _albumController.dispose();
    super.dispose();
  }

  Future<void> _applyChanges() async {
    final plan = _plan;
    if (plan.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add at least one edit to continue.')),
        );
      }
      return;
    }

    setState(() {
      _saving = true;
    });

    final result = await ref
        .read(songsProvider.notifier)
        .updateSongsMetadataBulk(widget.songs, plan);

    if (!mounted) return;

    setState(() {
      _saving = false;
    });

    final failed = result.failedFilenames.length;
    final summary = failed == 0
        ? 'Updated ${result.updated} songs'
        : 'Updated ${result.updated}, failed $failed';

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(summary)));

    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = _plan;
    final changes = plan.countChanges(widget.songs);
    final preview = plan.buildPreview(widget.songs, limit: 3);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bulk Metadata'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primary.withValues(alpha: 0.35),
                theme.colorScheme.surface,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
            children: [
              _HeaderCard(changes: changes, total: widget.songs.length),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Artist',
                subtitle: 'Add, append, or rename artist values',
                icon: Icons.person,
                enabled: _artistEnabled,
                onToggle: (value) => setState(() => _artistEnabled = value),
                child: Column(
                  children: [
                    _ModeSelector(
                      value: _artistMode,
                      onChanged: (value) => setState(() => _artistMode = value),
                    ),
                    const SizedBox(height: 12),
                    if (_artistMode == ArtistBulkMode.replace) ...[
                      _LabeledField(
                        label: 'Find',
                        controller: _artistFindController,
                        hint: 'Old artist name',
                      ),
                      const SizedBox(height: 12),
                      _LabeledField(
                        label: 'Replace',
                        controller: _artistReplaceController,
                        hint: 'New artist name',
                      ),
                    ] else ...[
                      _LabeledField(
                        label: _artistMode == ArtistBulkMode.append
                            ? 'Append Artist'
                            : 'Set Artist',
                        controller: _artistValueController,
                        hint: 'Type an artist name',
                      ),
                      const SizedBox(height: 12),
                      if (_artistMode == ArtistBulkMode.append)
                        _JoinerSelector(
                          value: _artistJoiner,
                          onChanged: (value) =>
                              setState(() => _artistJoiner = value),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Title',
                subtitle: 'Replace words or phrases in song titles',
                icon: Icons.text_fields,
                enabled: _titleEnabled,
                onToggle: (value) => setState(() => _titleEnabled = value),
                child: Column(
                  children: [
                    _LabeledField(
                      label: 'Find',
                      controller: _titleFindController,
                      hint: 'Text to replace',
                    ),
                    const SizedBox(height: 12),
                    _LabeledField(
                      label: 'Replace',
                      controller: _titleReplaceController,
                      hint: 'Replacement text',
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _titleCaseSensitive,
                      onChanged: (value) =>
                          setState(() => _titleCaseSensitive = value),
                      title: const Text('Case sensitive'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Album',
                subtitle: 'Set a shared album for the selection',
                icon: Icons.album,
                enabled: _albumEnabled,
                onToggle: (value) => setState(() => _albumEnabled = value),
                child: _LabeledField(
                  label: 'Album',
                  controller: _albumController,
                  hint: 'Album name',
                ),
              ),
              const SizedBox(height: 16),
              _PreviewCard(preview: preview),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              minimum: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _applyChanges,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _saving
                      ? 'Applying changes...'
                      : 'Apply to ${widget.songs.length} songs',
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final int changes;
  final int total;

  const _HeaderCard({required this.changes, required this.total});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.2),
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary.withValues(alpha: 0.2),
            ),
            child: Icon(Icons.auto_fix_high, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$total songs selected',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  changes == 0
                      ? 'Add edits to preview changes'
                      : '$changes songs will change',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.enabled,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: enabled
              ? theme.colorScheme.primary.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.05),
        ),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                ),
                child: Icon(icon, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                onChanged: onToggle,
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 16),
            child,
          ],
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;

  const _LabeledField({
    required this.label,
    required this.controller,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.4),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

class _ModeSelector extends StatelessWidget {
  final ArtistBulkMode value;
  final ValueChanged<ArtistBulkMode> onChanged;

  const _ModeSelector({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ArtistBulkMode>(
      segments: const [
        ButtonSegment(
            value: ArtistBulkMode.set,
            label: Text('Set'),
            icon: Icon(Icons.edit)),
        ButtonSegment(
            value: ArtistBulkMode.append,
            label: Text('Append'),
            icon: Icon(Icons.add)),
        ButtonSegment(
            value: ArtistBulkMode.replace,
            label: Text('Replace'),
            icon: Icon(Icons.sync_alt)),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class _JoinerSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _JoinerSelector({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final joiners = [' / ', ', ', ' & '];
    return Wrap(
      spacing: 8,
      children: [
        for (final joiner in joiners)
          ChoiceChip(
            label: Text(joiner.trim()),
            selected: value == joiner,
            onSelected: (_) => onChanged(joiner),
          ),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final List<BulkMetadataPreview> preview;

  const _PreviewCard({required this.preview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preview',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          if (preview.isEmpty)
            Text(
              'No changes to preview yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final item in preview)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.original.title,
                        style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(
                      '${item.original.artist} → ${item.updated.artist}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '${item.original.title} → ${item.updated.title}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '${item.original.album} → ${item.updated.album}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
