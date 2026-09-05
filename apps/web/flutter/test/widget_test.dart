import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/main.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  testWidgets('shows the Chez Yasmine brand on the login page when signed out', (WidgetTester tester) async {
    await tester.pumpWidget(const ChezYasmineApp());
    await tester.pump();

    expect(find.text('Chez Yasmine'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
  });
}
