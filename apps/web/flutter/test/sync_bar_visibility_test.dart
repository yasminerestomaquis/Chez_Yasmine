import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/auth/me_repository.dart';
import 'package:chez_yasmine/auth/profile_cache.dart';
import 'package:chez_yasmine/auth/profile_loader.dart';
import 'package:chez_yasmine/main.dart';
import 'package:chez_yasmine/sync/global_sync_context.dart';
import 'package:chez_yasmine/sync/sync_status_bar.dart';

/// Régression du 2026-10-04 : la barre « En ligne / Hors ligne » (montée une
/// fois au-dessus de l'écran courant, voir `withSyncStatusBar`) disparaissait
/// parce que le tableau de bord écrivait l'établissement courant pendant son
/// propre build.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  MyProfile profile(List<MyEstablishment> establishments) =>
      MyProfile(id: 'user-1', email: 'a@b.c', fullName: 'Y', establishments: establishments);

  ProfileLoader loader() => ProfileLoader(
        fetch: () => Completer<MyProfile>().future,
        cache: ProfileCache(),
        currentUserId: () => 'user-1',
      );

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: GlobalSyncContext.navigatorKey,
      builder: withSyncStatusBar,
      home: HomePage(loader: loader()),
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GlobalSyncContext.establishmentId.value = null;
  });

  testWidgets('un seul établissement : la barre est visible sur le tableau de bord', (tester) async {
    await ProfileCache().save(profile([MyEstablishment(id: 'est-1', name: 'Chez Yasmine', role: 'Gérant')]));
    final hang = Completer<http.Response>();

    await http.runWithClient(() async {
      await pumpApp(tester);

      expect(tester.takeException(), isNull);
      expect(GlobalSyncContext.establishmentId.value, 'est-1');
      expect(find.byType(SyncStatusBar), findsOneWidget);
      expect(find.text('En ligne'), findsOneWidget);
    }, () => MockClient((_) => hang.future));
  });

  testWidgets('plusieurs établissements : pas de barre au sélecteur, puis barre une fois l\'un choisi', (tester) async {
    await ProfileCache().save(profile([
      MyEstablishment(id: 'est-1', name: 'Chez Yasmine', role: 'Gérant'),
      MyEstablishment(id: 'est-2', name: 'Annexe', role: 'Gérant'),
    ]));
    final hang = Completer<http.Response>();

    await http.runWithClient(() async {
      await pumpApp(tester);
      expect(find.byType(SyncStatusBar), findsNothing);

      await tester.tap(find.text('Annexe'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(GlobalSyncContext.establishmentId.value, 'est-2');
      expect(find.byType(SyncStatusBar), findsOneWidget);
    }, () => MockClient((_) => hang.future));
  });
}
