import 'package:flutter/material.dart';

import '../screens/battle_menu_screen.dart';
import '../screens/battle_setup_screen.dart';
import '../screens/bedroom_screen.dart';
import '../screens/card_dex_screen.dart';
import '../screens/character_creator_screen.dart';
import '../screens/collection_screen.dart';
import '../screens/deck_builder_screen.dart';
import '../screens/home_screen.dart';
import '../screens/house_downstairs_screen.dart';
import '../screens/items_screen.dart';
import '../screens/login_screen.dart';
import '../screens/oaks_lab_screen.dart';
import '../screens/missions_screen.dart';
import '../screens/opening_narration_screen.dart';
import '../screens/pallet_town_screen.dart';
import '../screens/register_screen.dart';
import '../screens/session_loader_screen.dart';
import '../screens/shop_screen.dart';
import '../screens/story_mode_screen.dart';
import '../screens/title_screen.dart';
import '../screens/trainer_card_screen.dart';

class AppRoutes {
  AppRoutes._();

  static const String title = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String sessionLoader = '/session-loader';
  static const String characterCreator = '/character-creator';
  static const String home = '/home';
  static const String collection = '/collection';
  static const String deckBuilder = '/deck-builder';
  static const String battleMenu = '/battle-menu';
  static const String battleSetup = '/battle-setup';
  static const String trainerCard = '/trainer-card';
  static const String cardDex = '/card-dex';
  static const String openingNarration = '/opening-narration';
  static const String bedroom = '/bedroom';
  static const String houseDownstairs = '/house-downstairs';
  static const String palletTown = '/pallet-town';
  static const String oaksLab = '/oaks-lab';
  static const String storyMode = '/story-mode';
  static const String missions = '/missions';
  static const String shop = '/shop';
  static const String items = '/items';
}

/// Battle and Results aren't included here — they carry a [MatchState]/Deck
/// payload and are pushed directly with `MaterialPageRoute` instead.
final Map<String, WidgetBuilder> appRoutes = {
  AppRoutes.title: (_) => const TitleScreen(),
  AppRoutes.login: (_) => const LoginScreen(),
  AppRoutes.register: (_) => const RegisterScreen(),
  AppRoutes.sessionLoader: (_) => const SessionLoaderScreen(),
  AppRoutes.characterCreator: (_) => const CharacterCreatorScreen(),
  AppRoutes.home: (_) => const HomeScreen(),
  AppRoutes.collection: (_) => const CollectionScreen(),
  AppRoutes.deckBuilder: (_) => const DeckBuilderScreen(),
  AppRoutes.battleSetup: (_) => const BattleSetupScreen(),
  AppRoutes.trainerCard: (_) => const TrainerCardScreen(),
  AppRoutes.cardDex: (_) => const CardDexScreen(),
  AppRoutes.openingNarration: (_) => const OpeningNarrationScreen(),
  AppRoutes.bedroom: (_) => const BedroomScreen(),
  AppRoutes.houseDownstairs: (_) => const HouseDownstairsScreen(),
  AppRoutes.palletTown: (_) => const PalletTownScreen(),
  AppRoutes.oaksLab: (_) => const OaksLabScreen(),
  AppRoutes.storyMode: (_) => const StoryModeScreen(),
  AppRoutes.missions: (_) => const MissionsScreen(),
  AppRoutes.shop: (_) => const ShopScreen(),
  AppRoutes.items: (_) => const ItemsScreen(),
};
