import 'package:biometric_storage_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A smoke test: it only asserts that the example builds and renders. The
  // storage sections appear once `init` has been tapped, and tapping it goes to
  // the platform, so this stops at the first frame on purpose.
  testWidgets('renders the example UI', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Plugin example app'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'init'), findsOneWidget);
  });
}
