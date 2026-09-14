import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crm_app/main.dart';

void main() {
  testWidgets('Document Scanner App Smoke Test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: DocumentScannerApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Verify that Document Scanner Dashboard title is rendered
    expect(find.text('RG_OCR • Extrator'), findsOneWidget);
    expect(find.text('✨ Auto-Detect'), findsOneWidget);
  });
}
