// Scratch repro test for the "card detail shows a big gray box" bug report.
// Not a permanent test — just reproduces the dialog with real card+growth
// data so the broken render can be captured as a golden PNG and inspected.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pokemon_triad/app/player_profile_controller.dart';
import 'package:pokemon_triad/screens/collection_screen.dart';
import 'package:pokemon_triad/services/api_client.dart';
import 'package:pokemon_triad/services/card_repository.dart';
import 'package:pokemon_triad/services/deck_service.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient()
      : super(tokenProvider: () async => 'fake', baseUrlProvider: () async => 'http://localhost');

  @override
  Future<Map<String, dynamic>> getMe() async => {
        'playerName': 'Ash',
        'ownedCardIds': <String>['card_bulbasaur_1', 'card_oak_1'],
        'wins': 0,
        'losses': 0,
        'draws': 0,
        'money': 100,
        'joinedAt': null,
        'trainerName': 'Ash',
        'gender': 'boy',
        'skinTone': '',
        'hairPath': '',
        'topPath': '',
        'bottomPath': '',
        'hatPath': null,
        'friendCode': '000000000000',
        'location': 'Pallet Town',
      };

  @override
  Future<List<dynamic>> getDecks() async => [];

  @override
  Future<List<dynamic>> getCardGrowth() async => [
        {
          'cardId': 'card_bulbasaur_1',
          'xp': 400,
          'level': 16,
          'bonusNorth': 1,
          'bonusSouth': 0,
          'bonusEast': 0,
          'bonusWest': 0,
          'source': 'wild_battle',
          'shiny': false,
        },
      ];
}

void main() {
  testWidgets(
    'reproduce card detail dialog for an evolvable card',
    (tester) async {
    await CardRepository.instance.load();

    final apiClient = _FakeApiClient();
    final controller = PlayerProfileController(apiClient, DeckService(apiClient));
    await controller.loadFromServer();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: apiClient),
          ChangeNotifierProvider<PlayerProfileController>.value(value: controller),
        ],
        child: const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: CollectionScreen(),
        ),
      ),
    );
    // Bounded pumps instead of pumpAndSettle — a holo/shiny card's periodic
    // Timer.periodic never "settles" (it's real-time, not tied to the test
    // clock), so pumpAndSettle would hang forever.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Tap the first owned card in the grid.
    await tester.tap(find.byType(GestureDetector).first);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('card_detail_repro.png'),
    );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
