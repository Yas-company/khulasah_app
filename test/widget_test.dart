import 'package:flutter_test/flutter_test.dart';
import 'package:khulasah_app/app.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const KhulasahApp());
    await tester.pump();

    // Verify that the app renders
    expect(find.byType(KhulasahApp), findsOneWidget);
  });
}
