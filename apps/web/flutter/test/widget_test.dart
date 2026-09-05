import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chez_yasmine/main.dart';

void main() {
  testWidgets('shows the Chez Yasmine brand in the app bar', (WidgetTester tester) async {
    await tester.pumpWidget(const ChezYasmineApp());

    expect(find.text('Chez Yasmine'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });
}
