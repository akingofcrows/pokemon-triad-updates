// Scratch dev harness — renders BedroomScreen with a fake profile so it can
// be screenshotted without a live backend or login flow. Not part of the app.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/player_profile_controller.dart';
import 'screens/bedroom_screen.dart';
import 'services/api_client.dart';
import 'services/card_repository.dart';
import 'services/deck_service.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient()
      : super(tokenProvider: () async => 'fake', baseUrlProvider: () async => 'http://localhost');

  @override
  Future<Map<String, dynamic>> getMe() async => {
        'playerName': 'Ash',
        'ownedCardIds': <String>[],
        'wins': 0,
        'losses': 0,
        'draws': 0,
        'money': 100,
        'joinedAt': null,
        'trainerName': 'Ash',
        'gender': 'boy',
        'skinTone': 'trainers/male/base/medium.png',
        'hairPath': 'trainers/male/hair/hair_1__black.png',
        'topPath': 'trainers/male/tops/beach_top__blue.png',
        'bottomPath': 'trainers/male/bottoms/beach_bottom__blue.png',
        'hatPath': null,
        'friendCode': '000000000000',
        'location': 'Your Bedroom',
      };

  @override
  Future<List<dynamic>> getDecks() async => [];

  @override
  Future<List<dynamic>> getCardGrowth() async => [];

  @override
  Future<void> updateLocation(String location) async {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CardRepository.instance.load();

  final apiClient = _FakeApiClient();
  final controller = PlayerProfileController(apiClient, DeckService(apiClient));
  await controller.loadFromServer();
  controller.initNewPlayerQuests();

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: apiClient),
        ChangeNotifierProvider<PlayerProfileController>.value(value: controller),
      ],
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: BedroomScreen(),
      ),
    ),
  );
}
