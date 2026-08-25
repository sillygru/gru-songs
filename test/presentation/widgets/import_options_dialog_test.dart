import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wispie/presentation/widgets/import_options_dialog.dart';
import 'package:wispie/services/import_options.dart';

void main() {
  testWidgets(
      'ImportOptionsDialog only shows available categories and no additive mode',
      (tester) async {
    ImportOptions? selectedOptions;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                selectedOptions = await showDialog<ImportOptions>(
                  context: context,
                  builder: (_) => const ImportOptionsDialog(
                    availableCategories: {
                      ImportDataCategory.favorites,
                      ImportDataCategory.playlists,
                    },
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Database section header exists
    expect(find.text('Database'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);

    // Unavailable database categories are NOT present
    expect(find.text('Suggest-less'), findsNothing);
    expect(find.text('Hidden'), findsNothing);

    // Empty sections are NOT present
    expect(find.text('Storage'), findsNothing);
    expect(find.text('Settings'), findsNothing);
    expect(find.text('Cache'), findsNothing);
    expect(find.text('Cover Cache'), findsNothing);

    // "Import Mode" and "Merge" do not exist
    expect(find.text('Import Mode'), findsNothing);
    expect(find.text('Merge'), findsNothing);

    // Tap Restore button
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(selectedOptions, isNotNull);
    expect(selectedOptions!.additive, isFalse);
    expect(selectedOptions!.categories, {
      ImportDataCategory.favorites,
      ImportDataCategory.playlists,
    });
  });

  testWidgets(
      'ImportOptionsDialog includes Cache section only when coverCache is available',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                await showDialog<ImportOptions>(
                  context: context,
                  builder: (_) => const ImportOptionsDialog(
                    availableCategories: {
                      ImportDataCategory.coverCache,
                    },
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Cache'), findsOneWidget);
    expect(find.text('Cover Cache'), findsOneWidget);
    expect(find.text('Library Cache'), findsNothing);
    expect(find.text('Waveform Cache'), findsNothing);
  });
}
