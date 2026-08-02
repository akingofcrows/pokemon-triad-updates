import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'app/app.dart';
import 'app/routes.dart';
import 'screens/loading_screen.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/card_repository.dart';
import 'services/sprite_downloader.dart';
import 'services/trainer_parts_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const _AppShell());
}

/// Minimal MaterialApp that shows the loading screen, then swaps in the
/// real [PokemonTriadApp] once services are initialised.
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  Widget? _app;
  String _message = 'Shuffling cards into a deck…';
  double? _progress;

  static const _loadingMessages = [
    'Shuffling cards into a deck…',
    'Extracting data from Porygon…',
    'Polishing Poké Balls…',
    'Battling Gym Leaders…',
    'Feeding rare candies…',
    'Consulting Professor Oak…',
    'Organising the PC boxes…',
    'Healing at the Pokémon Center…',
    'Teaching new moves…',
    'Almost ready, Trainer!',
  ];

  String _themedMessage(double p) {
    final idx = (p * (_loadingMessages.length - 1)).round().clamp(0, _loadingMessages.length - 1);
    return _loadingMessages[idx];
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 1. Download / extract sprites to device storage.
    await SpriteDownloader.instance.download(
      onProgress: (p, _) {
        if (!mounted) return;
        setState(() {
          _progress = p;
          _message = _themedMessage(p);
        });
      },
    );

    if (!mounted) return;
    setState(() {
      _progress = null;
      _message = 'Loading card database…';
    });
    await CardRepository.instance.load();

    if (!mounted) return;
    setState(() => _message = 'Preparing your adventure…');
    await TrainerPartsRepository.instance.load();

    if (!mounted) return;
    late final AuthService authService;
    final apiClient = ApiClient(
      tokenProvider: () => authService.currentToken,
      baseUrlProvider: () async {
        // Try Cloudflare Tunnel first (works from any network, rarely blocked
        // by ISPs since it rides on Cloudflare's shared edge IPs), then fall
        // back to ngrok, then to Tailscale (same LAN / VPN only).
        const cloudflareUrl = 'https://api.playfablewood.com/api';
        const ngrokUrl = 'https://unaggravated-dispersively-grayce.ngrok-free.dev/api';
        const tailscaleUrl = 'http://100.65.103.71:3001/api';
        try {
          final r = await http
              .get(Uri.parse('$cloudflareUrl/me'))
              .timeout(const Duration(seconds: 3));
          if (r.statusCode == 200 || r.statusCode == 401) return cloudflareUrl;
        } catch (_) {}
        try {
          final r = await http.get(Uri.parse('$ngrokUrl/me'),
            headers: {'ngrok-skip-browser-warning': 'true'},
          ).timeout(const Duration(seconds: 3));
          if (r.statusCode == 200 || r.statusCode == 401) return ngrokUrl;
        } catch (_) {}
        return tailscaleUrl;
      },
    );
    authService = AuthService(apiClient);

    final isLoggedIn = await authService.isLoggedIn;

    setState(() {
      _app = PokemonTriadApp(
        authService: authService,
        apiClient: apiClient,
        initialRoute: isLoggedIn ? AppRoutes.sessionLoader : AppRoutes.title,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _app ?? LoadingScreen(message: _message, progress: _progress),
    );
  }
}
