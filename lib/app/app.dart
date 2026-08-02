import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/deck_service.dart';
import 'player_profile_controller.dart';
import 'story_progress_controller.dart';
import 'routes.dart';
import 'theme.dart';

class PokemonTriadApp extends StatelessWidget {
  const PokemonTriadApp({
    super.key,
    required this.authService,
    required this.apiClient,
    required this.initialRoute,
  });

  final AuthService authService;
  final ApiClient apiClient;
  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>.value(value: authService),
        Provider<ApiClient>.value(value: apiClient),
        ChangeNotifierProvider<PlayerProfileController>(
          create: (_) => PlayerProfileController(apiClient, DeckService(apiClient)),
        ),
        ChangeNotifierProvider<StoryProgressController>(
          create: (_) => StoryProgressController(apiClient),
        ),
      ],
      child: MaterialApp(
        title: 'Pokémon Triple Triad',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        initialRoute: initialRoute,
        routes: appRoutes,
      ),
    );
  }
}
