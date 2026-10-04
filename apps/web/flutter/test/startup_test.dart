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
import 'package:chez_yasmine/home/home_dashboard.dart';
import 'package:chez_yasmine/main.dart';

MyProfile profile({String id = 'user-1', String role = 'Gérant', String establishment = 'Chez Yasmine'}) => MyProfile(
      id: id,
      email: 'a@b.c',
      fullName: 'Yasmine',
      establishments: [MyEstablishment(id: 'est-1', name: establishment, role: role)],
    );

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('sameProfile', () {
    test('identique : vrai, et sensible au rôle, au nom d\'établissement et à la liste', () {
      expect(sameProfile(profile(), profile()), isTrue);
      expect(sameProfile(profile(), profile(role: 'Caissier')), isFalse);
      expect(sameProfile(profile(), profile(establishment: 'Autre')), isFalse);
      expect(sameProfile(profile(), profile(id: 'user-2')), isFalse);
      final two = MyProfile(
        id: 'user-1',
        email: 'a@b.c',
        fullName: 'Yasmine',
        establishments: [
          MyEstablishment(id: 'est-1', name: 'Chez Yasmine', role: 'Gérant'),
          MyEstablishment(id: 'est-2', name: 'Annexe', role: 'Gérant'),
        ],
      );
      expect(sameProfile(profile(), two), isFalse);
    });
  });

  group('ProfileLoader', () {
    ProfileLoader loader({String? userId = 'user-1', Future<MyProfile> Function()? fetch}) => ProfileLoader(
          fetch: fetch ?? () async => profile(role: 'Propriétaire'),
          cache: ProfileCache(),
          currentUserId: () => userId,
        );

    test('copie du même utilisateur : servie sans attendre le serveur', () async {
      await ProfileCache().save(profile());

      final cached = await loader().cachedForCurrentUser();

      expect(cached?.establishments.single.role, 'Gérant');
    });

    test('copie d\'un AUTRE compte (appareil partagé) : jamais servie', () async {
      await ProfileCache().save(profile(id: 'user-autre'));

      expect(await loader().cachedForCurrentUser(), isNull);
    });

    test('aucun utilisateur connecté ou aucune copie : rien', () async {
      await ProfileCache().save(profile());
      expect(await loader(userId: null).cachedForCurrentUser(), isNull);

      SharedPreferences.setMockInitialValues({});
      expect(await loader().cachedForCurrentUser(), isNull);
    });

    test('fetchAndCache garde une copie ; une erreur du serveur remonte telle quelle', () async {
      final fresh = await loader().fetchAndCache();
      expect(fresh.establishments.single.role, 'Propriétaire');
      expect((await ProfileCache().load())!.establishments.single.role, 'Propriétaire');

      await expectLater(
        loader(fetch: () async => throw http.ClientException('offline')).fetchAndCache(),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('refresh : profil frais et copie mise à jour ; serveur injoignable => null, copie intacte', () async {
      await ProfileCache().save(profile());

      final fresh = await loader().refresh();
      expect(fresh?.establishments.single.role, 'Propriétaire');

      await ProfileCache().save(profile());
      final failed = await loader(fetch: () async => throw http.ClientException('offline')).refresh();
      expect(failed, isNull);
      expect((await ProfileCache().load())!.establishments.single.role, 'Gérant');
    });

    test('ProfileCache.clear (déconnexion) efface la copie', () async {
      await ProfileCache().save(profile());

      await ProfileCache().clear();

      expect(await ProfileCache().load(), isNull);
    });
  });

  group('HomePage : ouverture sans attendre le serveur', () {
    testWidgets('copie locale + serveur qui ne répond pas : le tableau de bord s\'affiche tout de suite', (tester) async {
      await ProfileCache().save(profile());
      final neverAnswers = Completer<MyProfile>();
      final loader = ProfileLoader(
        fetch: () => neverAnswers.future,
        cache: ProfileCache(),
        currentUserId: () => 'user-1',
      );

      await tester.pumpWidget(MaterialApp(home: HomePage(loader: loader)));
      await tester.pump();
      await tester.pump();

      expect(find.byType(HomeDashboard), findsOneWidget);
      expect(find.text('Bonjour, Gérant'), findsOneWidget);
    });

    testWidgets('rafraîchissement en arrière-plan : un rôle modifié met l\'écran à jour', (tester) async {
      await ProfileCache().save(profile());
      final answer = Completer<MyProfile>();
      final loader = ProfileLoader(
        fetch: () => answer.future,
        cache: ProfileCache(),
        currentUserId: () => 'user-1',
      );
      await tester.pumpWidget(MaterialApp(home: HomePage(loader: loader)));
      await tester.pump();
      await tester.pump();
      expect(find.text('Bonjour, Gérant'), findsOneWidget);

      answer.complete(profile(role: 'Propriétaire'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Bonjour, Propriétaire'), findsOneWidget);
    });

    testWidgets('profil inchangé : le tableau de bord n\'est pas reconstruit (l\'utilisateur garde sa place)', (tester) async {
      await ProfileCache().save(profile());
      final answer = Completer<MyProfile>();
      final loader = ProfileLoader(
        fetch: () => answer.future,
        cache: ProfileCache(),
        currentUserId: () => 'user-1',
      );
      await tester.pumpWidget(MaterialApp(home: HomePage(loader: loader)));
      await tester.pump();
      await tester.pump();
      final before = tester.state(find.byType(HomeDashboard));

      answer.complete(profile());
      await tester.pump();
      await tester.pump();

      expect(tester.state(find.byType(HomeDashboard)), same(before));
    });

    testWidgets('aucune copie : cercle de chargement, puis message explicite si le serveur tarde', (tester) async {
      final neverAnswers = Completer<MyProfile>();
      final loader = ProfileLoader(
        fetch: () => neverAnswers.future,
        cache: ProfileCache(),
        currentUserId: () => 'user-1',
      );
      await tester.pumpWidget(MaterialApp(home: HomePage(loader: loader)));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('Connexion au serveur'), findsNothing);

      await tester.pump(const Duration(seconds: 6));

      expect(find.textContaining('Connexion au serveur en cours'), findsOneWidget);
      expect(find.textContaining('jusqu\'à une minute'), findsOneWidget);
    });

    testWidgets('aucune copie et serveur injoignable : message d\'erreur, et Réessayer relance le chargement', (tester) async {
      var attempts = 0;
      final loader = ProfileLoader(
        fetch: () async {
          attempts++;
          if (attempts == 1) throw http.ClientException('offline');
          return profile();
        },
        cache: ProfileCache(),
        currentUserId: () => 'user-1',
      );
      await tester.pumpWidget(MaterialApp(home: HomePage(loader: loader)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Impossible de joindre l\'API'), findsOneWidget);

      await tester.tap(find.text('Réessayer'));
      await tester.pump();
      await tester.pump();

      expect(attempts, 2);
      expect(find.byType(HomeDashboard), findsOneWidget);
    });
  });

  group('HomeDashboard : la grille ne dépend pas du serveur', () {
    testWidgets('les modules sont visibles pendant que les indicateurs chargent encore (serveur qui ne répond pas)', (tester) async {
      final hang = Completer<http.Response>();
      await http.runWithClient(() async {
        await tester.pumpWidget(
          const MaterialApp(
            home: HomeDashboard(establishmentId: 'est-1', establishmentName: 'Chez Yasmine', roleName: 'Gérant'),
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text('Tables'), findsWidgets);
        expect(find.text('Caisse'), findsWidgets);
        expect(find.byType(LinearProgressIndicator), findsOneWidget, reason: 'indicateurs encore en chargement');
      }, () => MockClient((_) => hang.future));
    });
  });
}
