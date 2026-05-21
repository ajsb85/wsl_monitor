import 'package:flutter_test/flutter_test.dart';
import 'package:wsl_monitor/main.dart';

void main() {
  testWidgets('WSL Monitor Smoke Test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const WslMonitorApp());

    // Verify that our loading screen shows up.
    expect(find.text('Analyzing WSL Environment...'), findsOneWidget);
  });
}
