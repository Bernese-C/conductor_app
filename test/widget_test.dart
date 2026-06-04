import 'package:flutter_test/flutter_test.dart';
import 'package:conductor_app/main.dart';

void main() {
  testWidgets('App renders with title', (WidgetTester tester) async {
    await tester.pumpWidget(const ConductorApp());
    // Verify the app bar title is present.
    expect(find.text('指挥家'), findsOneWidget);
  });
}
