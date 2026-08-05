import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import '../app/player_profile_controller.dart';
import '../app/routes.dart';
import '../app/story_progress_controller.dart';
import 'trainer_card_screen.dart';
import 'character_customization_sheet.dart';
import '../models/card_growth.dart';
import '../models/deck.dart';
import '../models/player_profile.dart';
import '../models/trainer_appearance.dart';
import '../models/triad_card.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/card_repository.dart';
import '../services/update_service.dart';
import '../widgets/trainer_sprite_stack.dart';
import '../widgets/triad_card_view.dart';
import '../widgets/update_dialog.dart';
import '../widgets/battery_indicator.dart';
import 'battle_menu_screen.dart';

/// One edge-hugging gradient band used to fake a debossed/inset-shadow
/// look on the active-deck box (Flutter has no native inset BoxShadow).
class _DebossEdge {
  const _DebossEdge(this.begin, this.end, this.color, this.stops);
  final Alignment begin;
  final Alignment end;
  final Color color;
  final List<double> stops;
}

final _debossEdges = [
  _DebossEdge(Alignment.topCenter, Alignment.bottomCenter, Colors.black.withValues(alpha: 0.5), const [0.0, 0.05]),
  _DebossEdge(Alignment.centerLeft, Alignment.centerRight, Colors.black.withValues(alpha: 0.38), const [0.0, 0.035]),
  _DebossEdge(Alignment.bottomCenter, Alignment.topCenter, Colors.white.withValues(alpha: 0.18), const [0.0, 0.035]),
  _DebossEdge(Alignment.centerRight, Alignment.centerLeft, Colors.white.withValues(alpha: 0.11), const [0.0, 0.025]),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  int _currentTab = 0;
  bool _battleVisible = false;
  bool _battleSoloOpen = false;
  bool _trainerCardOpen = false;
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;
  List<CardGrowth> _topCards = [];
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  late final PlayerProfileController _controller;
  bool _hasStarterDeckLocal = false;
  final _chatController = TextEditingController();
  final _chatScroll = ScrollController();
  final _chatMessages = <_ChatMsg>[];
  bool _chatOpen = false;
  final _chatFocus = FocusNode();
  Timer? _disconnectTimer;
  bool _connectionLost = false;
  Timer? _chatPollTimer;
  int _unreadChatCount = 0;
  Timer? _giftPollTimer;
  int _liveGiftCount = 0;
  bool _busy = false;
  IO.Socket? _socket;
  String? _chatotPath;

  /// Dismiss battle panels. If Solo is open, both animate down — Solo slides
  /// first (350ms) followed by the Battle panel (400ms) — giving the two-step feel.
  void _dismissBattlePanel() {
    if (_battleSoloOpen) {
      setState(() { _battleSoloOpen = false; });
      // Wait for Solo to finish sliding down, then dismiss Battle panel
      Future.delayed(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        setState(() { _battleVisible = false; });
      });
    } else {
      setState(() { _battleVisible = false; _battleSoloOpen = false; });
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = context.read<PlayerProfileController>();
    _loadChatotPath();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker((elapsed) {
      if (mounted) setState(() => _elapsed = elapsed);
    })..start();
    _topCards = _computeTopCards();
    _controller.addListener(_onProfileChanged);
    _loadStarterFlag();
    _loadChat();
    // Poll for new chat messages every 5 seconds
    _chatPollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollChat());
    _giftPollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _pollGifts());
    _connectWebSocket();
    // Collapse chat and defocus when returning to home
    _chatOpen = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _chatFocus.unfocus());
  }

  Future<void> _loadChat() async {
    try {
      final api = context.read<ApiClient>();
      final msgs = await api.getChat();
      if (!mounted) return;
      setState(() {
        _chatMessages.clear();
        for (final m in msgs) {
          _chatMessages.add(_ChatMsg(
            sender: (m['sender'] as String?) ?? '???',
            text: (m['text'] as String?) ?? '',
          ));
        }
      });
      _scrollChatToBottom();
    } catch (_) {}
  }

  Future<void> _pollChat() async {
    if (!mounted) return;
    try {
      final api = context.read<ApiClient>();
      final msgs = await api.getChat();
      if (!mounted || _chatOpen) return;
      final serverList = msgs as List<dynamic>;
      if (serverList.length > _chatMessages.length) {
        final newCount = serverList.length - _chatMessages.length;
        setState(() {
          // Sync messages so count doesn't keep growing
          _chatMessages.clear();
          for (final m in serverList) {
            _chatMessages.add(_ChatMsg(
              sender: (m['sender'] as String?) ?? '???',
              text: (m['text'] as String?) ?? '',
            ));
          }
          _unreadChatCount += newCount;
        });
      }
    } catch (_) {}
  }

  Future<void> _pollGifts() async {
    try {
      final api = context.read<ApiClient>();
      final data = await api.getGifts();
      if (!mounted) return;
      final count = (data['count'] as int?) ?? 0;
      if (count != _liveGiftCount) {
        setState(() => _liveGiftCount = count);
      }
    } catch (_) {}
  }

  Future<void> _loadStarterFlag() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _hasStarterDeckLocal = prefs.getBool('hasStarterDeck') ?? false);
  }

  Future<void> _connectWebSocket() async {
    if (_socket != null) return;
    try {
      final token = (await AuthService(context.read<ApiClient>()).currentToken) ?? '';
      _socket = IO.io(
        'http://100.65.103.71:3001',
        <String, dynamic>{
          'transports': ['websocket', 'polling'],
          'autoConnect': true,
          'extraHeaders': {'ngrok-skip-browser-warning': '1'},
        },
      );
      _socket!.on('chat_message', (data) {
        if (!mounted) return;
        try {
          final msg = data as Map<String, dynamic>;
          if (msg['text'] != null && msg['sender'] != null) {
            setState(() {
              _chatMessages.add(_ChatMsg(
                sender: msg['sender'] as String,
                text: msg['text'] as String,
              ));
              if (!_chatOpen) _unreadChatCount++;
            });
            if (_chatOpen) _scrollChatToBottom();
          }
        } catch (_) {}
      });
      _socket!.onDisconnect((_) {
        if (mounted) {
          _socket?.dispose();
          _socket = null;
          Future.delayed(const Duration(seconds: 3), _connectWebSocket);
        }
      });
    } catch (_) {}
  }

  void _onProfileChanged() {
    if (mounted) {
      setState(() {
        _topCards = _computeTopCards();
        _liveGiftCount = _controller.profile.giftCount;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _disconnectTimer?.cancel();
      _disconnectTimer = Timer(const Duration(seconds: 60), () {
        if (mounted) {
          setState(() => _connectionLost = true);
          _startReconnectPolling();
        }
      });
    } else if (state == AppLifecycleState.resumed) {
      _disconnectTimer?.cancel();
      if (_connectionLost) {
        _startReconnectPolling();
      }
    }
  }

  void _startReconnectPolling() {
    Timer.periodic(const Duration(seconds: 5), (t) async {
      try {
        final api = context.read<ApiClient>();
        await api.getChat();
        if (mounted) {
          t.cancel();
          setState(() => _connectionLost = false);
          _controller.loadFromServer();
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chatPollTimer?.cancel();
    _giftPollTimer?.cancel();
    _socket?.dispose();
    _controller.removeListener(_onProfileChanged);
    _chatController.dispose();
    _chatScroll.dispose();
    _chatFocus.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _ticker.dispose();
    super.dispose();
  }

  List<CardGrowth> _computeTopCards() {
    final controller = context.read<PlayerProfileController>();
    // Use favorites if set, otherwise top XP cards
    final favs = controller.favoriteInstances;
    if (favs.isNotEmpty) return favs;
    final growth = controller.cardGrowth;
    if (growth.isEmpty) return [];
    final sorted = growth.values.toList()
      ..sort((a, b) => b.xp.compareTo(a.xp));
    return sorted.take(3).toList();
  }

  TrainerAppearance _buildAppearance(PlayerProfile profile) {
    return TrainerAppearance(
      trainerName: profile.trainerName ?? profile.playerName,
      gender: profile.gender ?? 'boy',
      skinTone: profile.skinTone ?? '',
      hairPath: profile.hairPath ?? '',
      topPath: profile.topPath ?? '',
      bottomPath: profile.bottomPath ?? '',
      hatPath: profile.hatPath,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PlayerProfileController>();
    final profile = ctrl.profile;
    final appearance = _buildAppearance(profile);

    // Current location = latest unlocked story location
    final storyCtrl = context.watch<StoryProgressController>();
    final currentLocationName = _currentLocationName(storyCtrl);
    final bgAsset = _locationBg(currentLocationName);

    // Keep profile.location in sync for display elsewhere
    if (profile.location != currentLocationName) {
      profile.location = currentLocationName;
    }

    // Oak tutorial should NOT show if player already has a starter deck
    final hasStarterDeck = _hasStarterDeckLocal || profile.decks.isNotEmpty ||
        (ctrl.activeQuest?.objectives.any((o) => o.description == 'Receive your starter deck' && o.completed) ?? false);

    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      extendBody: true,
      drawer: _buildDrawer(context, appearance, profile),
      body: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Image.asset(bgAsset, fit: BoxFit.cover,
                  color: Colors.black.withValues(alpha: 0.40),
                  colorBlendMode: BlendMode.darken),
              ),
            ),
          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFF1E1E1E),
                        border: Border(
                          bottom: BorderSide(color: Color(0xFF444444), width: 1),
                        ),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Row(
                            children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          const Text('FAVES',
                            style: TextStyle(color: Colors.white, fontSize: 9, fontFamily: 'PowerGreen')),
                          const SizedBox(height: 2),
                          _buildFavoritesButton(context),
                        ],
                      ),
                      const Spacer(),
                      Transform.translate(
                        offset: const Offset(-80, 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                          ),
                          child: Text('₽ ${profile.money}',
                            style: const TextStyle(fontFamily: 'PowerGreen', fontSize: 13, color: Color(0xFFC9A44C))),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _topIcon(Icons.notifications_none, () {}),
                      const SizedBox(width: 16),
                      _topIcon(Icons.mail_outline, () {}),
                      const SizedBox(width: 16),
                      _topIcon(Icons.card_giftcard, () => _showGiftList(), badge: _liveGiftCount),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      // Shadow gradient below top bar
      Container(
        height: 12,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.55),
              Colors.transparent,
            ],
          ),
        ),
      ),
    ],
  ),
),
          SafeArea(
            bottom: false,
            child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 260,
                  child: _OrbitingTrainer(
                    elapsed: _elapsed,
                    appearance: appearance,
                    cards: _topCards,
                  ),
                ),
                const SizedBox(height: 2),
                // Trainer Card button
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => setState(() => _trainerCardOpen = true),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset('assets/ui/trainercard.png', width: 20, height: 20),
                        const SizedBox(width: 8),
                        const Text('Trainer Card',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              shadows: [Shadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0)],
                            )),
                      ],
                    ),
                  ),
                  ),
                ),
                const SizedBox(height: 6),
                _buildActiveDeckButton(profile.defaultDeck),
              ],
            ),
          ),
          ),
          // Version number — bottom right
          Positioned(
            bottom: 40,
            right: 8,
            child: _VersionLabel(),
          ),
          // Battle menu overlay — slides up over everything
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_battleVisible,
              child: BattleMenuContent(
                visible: _battleVisible,
                soloVisible: _battleSoloOpen,
                onSoloStateChanged: (v) => setState(() => _battleSoloOpen = v),
                onDismiss: () => setState(() => _currentTab = 0),
                onBackgroundTap: () => _dismissBattlePanel(),
              ),
            ),
          ),
          // Missions icon — top right below top bar
          Positioned(
            top: kToolbarHeight + MediaQuery.of(context).padding.top + 14,
            right: 8,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
              onTap: () => Navigator.pushNamed(context, AppRoutes.missions),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.assignment, color: Colors.white70, size: 20),
                    const SizedBox(width: 6),
                    const Text('Missions', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              ),
            ),
          ),
          // Battery indicator — top left
          const Positioned(
            top: 8,
            left: 12,
            child: BatteryIndicator(),
          ),
          // Oak tutorial for new players without a deck
          if (!hasStarterDeck)
            Positioned(
              left: 0,
              right: 0,
              bottom: 56, // just above bottom nav
              child: _OakTutorial(
                onChooseDeck: () => Navigator.pushNamed(context, AppRoutes.oaksLab),
              ),
            ),
          // Connection Lost overlay
          if (_connectionLost)
            const Positioned.fill(child: _ConnectionLostOverlay()),
          // Trainer Card overlay — nav bars stay clear, content blurred
          if (_trainerCardOpen)
            Positioned.fill(
              child: _TrainerCardOverlay(onClose: () => setState(() => _trainerCardOpen = false)),
            ),
          // XP circle — on top of everything (higher z-index)
          if (!_connectionLost)
            Positioned(
              top: MediaQuery.of(context).padding.top + kToolbarHeight - 36,
              left: 0,
              right: 0,
              child: Center(
                child: Transform.translate(
                  offset: const Offset(2, 0),
                  child: _TrainerXpCircle(appearance: appearance),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              border: Border(
                top: BorderSide(color: Color(0xFF444444), width: 1),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _bottomNavIcon(Icons.home, 'Home', 0),
                    _bottomNavImage('assets/ui/collection.png', 'Collection', 1),
                    _bottomNavImage('assets/ui/deck.png', 'Decks', 2),
                    _bottomNavIcon(Icons.people, 'Social', 3),
                    _bottomNavIcon(Icons.sports_esports, 'Battle', 4),
                    _bottomNavIcon(Icons.menu, 'Menu', 5),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomNavIcon(IconData icon, String label, int index) {
    final active = _currentTab == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onNavTap(index),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                shadows: const [Shadow(color: Colors.black87, blurRadius: 2, offset: Offset(2, 2))],
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomNavImage(String asset, String label, int index) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onNavTap(index),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(asset, width: 22, height: 22),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                shadows: [Shadow(color: Colors.black87, blurRadius: 2, offset: Offset(2, 2))],
              )),
            ],
          ),
        ),
      ),
    );
  }

  void _onNavTap(int i) {
    if (i == 5) {
      _scaffoldKey.currentState?.openDrawer();
      return;
    }
    if (i == 4) {
      if (_battleVisible) {
        _dismissBattlePanel();
      } else {
        setState(() { _battleVisible = true; _battleSoloOpen = false; _currentTab = 4; });
      }
      return;
    }
    setState(() => _currentTab = i);
    if (i == 0) { _battleVisible = false; _battleSoloOpen = false; _busy = false; return; }
    if (_battleVisible) { setState(() { _battleVisible = false; _battleSoloOpen = false; }); }
    if (_busy) return;
    switch (i) {
      case 1: _busy = true; Navigator.pushNamed(context, AppRoutes.collection).then((_) => _busy = false);
      case 2: _busy = true; Navigator.pushNamed(context, AppRoutes.deckBuilder).then((_) => _busy = false);
      case 3: _busy = true; setState(() => _trainerCardOpen = true); _busy = false;
    }
  }

  Widget _buildFavoritesButton(BuildContext context) {
    final ctrl = context.read<PlayerProfileController>();
    final favInsts = ctrl.favoriteInstances;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
      onTap: () => _showFavorites(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 38,
        padding: favInsts.isNotEmpty
            ? const EdgeInsets.symmetric(horizontal: 6)
            : const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06), width: 1),
        ),
        clipBehavior: Clip.none,
        child: Center(
          child: SizedBox(
            width: favInsts.isEmpty ? null : 28 + (favInsts.length - 1) * 32.0,
            height: 28,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < favInsts.length; i++)
                  Builder(builder: (_) {
                    final inst = favInsts[i];
                    final card = CardRepository.instance.cardById(inst.cardId);
                    if (card == null) return const SizedBox.shrink();
                    return Positioned(
                      left: i * 32.0,
                      child: SizedBox(
                        width: 28, height: 28,
                        child: TriadCardView(card: card, size: 28, growth: inst),
                      ),
                    );
                  }),
                if (favInsts.isEmpty)
                  const Positioned.fill(
                    child: Center(
                      child: Icon(Icons.star_border, color: Color(0xFFC9A44C), size: 18),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _topIcon(IconData icon, VoidCallback onTap, {int badge = 0}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, color: Colors.white70, size: 24),
          if (badge > 0)
            Positioned(
              right: -6,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 14),
                child: Text(
                  '$badge',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
          ),
        ),
      ),
    );
  }

  void _showFavorites(BuildContext context) {
    if (_busy) return;
    _busy = true;
    final favInstances = context.read<PlayerProfileController>().favoriteInstances;
    if (favInstances.isEmpty) {
      _busy = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No favorite cards yet! Tap ★ in Collection.')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (_) => _FavoritesDialog(instances: favInstances),
    ).then((_) => _busy = false);
  }

  void _showBattleMenu() {
    if (_busy) return;
    _busy = true;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text('BATTLE',
                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 4)),
            const SizedBox(height: 24),
            // Free Battle (greyed out for now)
            _BattleOption(
              icon: Icons.sports_esports,
              label: 'Free Battle',
              subtitle: 'Coming soon',
              color: Colors.grey,
              greyedOut: true,
              onTap: null,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ).then((_) {
      if (_busy) _busy = false;
    });
  }

  Future<void> _showGiftList() async {
    if (_busy) return;
    _busy = true;
    try {
      final api = context.read<ApiClient>();
      final ctrl = context.read<PlayerProfileController>();
      final data = await api.getGifts();
      final gifts = (data['gifts'] as List<dynamic>?) ?? [];
      if (!mounted) {
        _busy = false;
        return;
      }

      showDialog(
        context: context,
        builder: (_) => _GiftListDialog(
          gifts: gifts.cast<Map<String, dynamic>>(),
          scaffoldMessengerKey: _scaffoldMessengerKey,
          apiClient: api,
          profileController: ctrl,
        ),
      ).then((_) {
        _busy = false;
        ctrl.loadFromServer();
      });
    } catch (_) {
      _busy = false;
    }
  }

  Widget _buildActiveDeckButton(Deck? deck) {
    final ctrl = context.read<PlayerProfileController>();
    final growth = ctrl.cardGrowth;
    final boxImg = deck?.boxImage ?? 'field_deck';
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRoutes.deckBuilder),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            deck != null ? 'ACTIVE DECK' : 'No Active Deck',
            style: const TextStyle(
              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800,
              letterSpacing: 2, fontFamily: 'PowerGreen',
              shadows: [Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(1, 2))],
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -16),
            child: SizedBox(
            width: 220,
            height: 150,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 20,
                  bottom: 0,
                  child: Image.asset('assets/images/Booster Pack/$boxImg.png', width: 170, height: 120, fit: BoxFit.contain),
                ),
                if (deck != null && deck.cardIds.isNotEmpty)
                  _buildFeaturedCard(deck, ctrl, growth),
                if (deck != null)
                  Positioned(
                    top: 44,
                    left: 30,
                    right: 50,
                    child: Center(
                      child: Text(deck.name,
                        style: TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'PowerGreen', shadows: [Shadow(color: boxImg == 'field_deck' ? const Color(0xFF169A3D) : Colors.black87, blurRadius: 3, offset: const Offset(1, 1))])),
                    ),
                  ),
              ],
            ),
          ),
            ),
        ],
      ),
    );
  }

  Widget _buildFeaturedCard(Deck deck, PlayerProfileController ctrl, Map<String, CardGrowth> growth) {
    final idx = (deck.featuredCardIndex ?? 0).clamp(0, deck.cardIds.length - 1);
    final id = deck.cardIds[idx];
    final card = CardRepository.instance.cardById(id);
    if (card == null) return const SizedBox.shrink();

    CardGrowth? g;
    final instId = deck.instanceIds != null && idx < deck.instanceIds!.length
        ? deck.instanceIds![idx]
        : null;
    if (instId != null && instId > 0) {
      g = ctrl.allCardInstances.where((inst) => inst.instanceId == instId).firstOrNull;
    }
    // Only use instance-specific; don't fall back to general pool

    return Positioned(
      left: 68,
      top: 72,
      child: Transform.rotate(
        angle: -0.08,
        child: SizedBox(
          width: 64, height: 64,
          child: TriadCardView(card: card, size: 64, growth: g),
        ),
      ),
    );
  }

  void _showCustomization(BuildContext ctx, TrainerAppearance appearance) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CharacterCustomizationSheet(appearance: appearance),
    );
  }

  Widget _buildDrawer(BuildContext context, TrainerAppearance appearance, PlayerProfile profile) {
    final storyCtrl = context.watch<StoryProgressController>();
    final profileCtrl = context.watch<PlayerProfileController>();
    final trainerLevel = profileCtrl.trainerLevel;
    final trainerXp = profileCtrl.trainerXpInLevel;
    final trainerXpMax = profileCtrl.trainerXpForNextLevel;
    return Drawer(
      backgroundColor: Colors.transparent,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            borderRadius: BorderRadius.horizontal(right: Radius.circular(16)),
            border: Border(
              right: BorderSide(color: Color(0xFF444444), width: 1),
            ),
          ),
          child: SafeArea(
        child: Column(
          children: [
            // Trainer header
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () => _showCustomization(context, appearance),
                    child: TrainerSpriteStack(appearance: appearance, size: 100),
                  ),
                  const SizedBox(height: 12),
                  // Debossed name + friend code card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${profile.trainerName ?? profile.playerName} — Lv. $trainerLevel',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        // Trainer XP bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: trainerXpMax > 0 ? trainerXp / trainerXpMax : 0,
                            minHeight: 4,
                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              appearance.gender == 'girl'
                                  ? const Color(0xFFF472B6)
                                  : Colors.cyan,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$trainerXp / $trainerXpMax XP',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.35),
                            fontFamily: 'Tiny5',
                          ),
                        ),
                        if (profile.friendCode != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            'FRIEND CODE',
                            style: TextStyle(
                              fontFamily: 'Tiny5',
                              fontSize: 10,
                              color: Colors.white.withValues(alpha: 0.2),
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _formatFriendCode(profile.friendCode!),
                                  style: const TextStyle(color: Colors.white38, fontSize: 12, letterSpacing: 0.5),
                                ),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () {
                                  final formatted = _formatFriendCode(profile.friendCode!);
                                  Clipboard.setData(ClipboardData(text: formatted));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Friend code copied!'),
                                      duration: Duration(seconds: 1),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                },
                                child: Icon(Icons.copy, size: 14, color: Colors.white.withValues(alpha: 0.25)),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Menu items
            _drawerItem(Icons.store, 'Shop', () {
              Navigator.pop(context);
              Navigator.pushNamed(context, AppRoutes.shop);
            }),
            _drawerItem(Icons.backpack, 'Items', () {
              Navigator.pop(context);
              Navigator.pushNamed(context, AppRoutes.items);
            }),
            _drawerImgItem('assets/ui/carddex.png', 'Card Dex', () {
              Navigator.pop(context);
              Navigator.pushNamed(context, AppRoutes.cardDex);
            }),
            _drawerItem(Icons.newspaper, 'News', () {}),
            _drawerItem(Icons.card_giftcard, 'Gifts', () {}, badge: _liveGiftCount),
            _drawerItem(Icons.lightbulb, 'Tips', () {}),
            _drawerItem(Icons.history, 'Changelogs', () {
              Navigator.pop(context);
              _showChangelogs(context);
            }),
            const Spacer(),
            _drawerItem(Icons.settings, 'Settings', () {
              Navigator.pop(context);
              _showSettings(context);
            }),
            _drawerItem(Icons.logout, 'Log Out', () async {
              Navigator.pop(context);
              await context.read<AuthService>().logout();
              if (context.mounted) {
                Navigator.pushNamedAndRemoveUntil(context, AppRoutes.title, (_) => false);
              }
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  ),
    );
  }

  Widget _drawerItem(IconData icon, String label, VoidCallback onTap, {int badge = 0}) {
    return ListTile(
      leading: badge > 0
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: Colors.white),
                Positioned(
                  right: -6, top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: const BoxDecoration(color: Colors.red, borderRadius: BorderRadius.all(Radius.circular(8))),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 14),
                    child: Text('$badge', textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            )
          : Icon(icon, color: Colors.white),
      title: Text(label, style: const TextStyle(
        color: Colors.white,
        shadows: [Shadow(color: Colors.black87, blurRadius: 2, offset: Offset(2, 2))],
      )),
      onTap: onTap,
    );
  }

  Widget _drawerImgItem(String assetPath, String label, VoidCallback onTap) {
    return ListTile(
      leading: Image.asset(assetPath, width: 24, height: 24),
      title: Text(label, style: const TextStyle(
        color: Colors.white,
        shadows: [Shadow(color: Colors.black87, blurRadius: 2, offset: Offset(2, 2))],
      )),
      onTap: onTap,
    );
  }

  Future<void> _loadChatotPath() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final path = '${appDir.path}/tt_sprites/front/CHATOT.png';
      if (File(path).existsSync() && mounted) {
        setState(() => _chatotPath = path);
      }
    } catch (_) {}
  }

  String _formatFriendCode(String code) {
    if (code.length >= 12) {
      return '${code.substring(0, 4)}-${code.substring(4, 8)}-${code.substring(8, 12)}';
    }
    return code;
  }

  /// Returns the name of the player's current story location — the latest
  /// unlocked location in the route progression.
  static String _currentLocationName(StoryProgressController ctrl) {
    final locations = ctrl.locations;
    final unlocked = ctrl.unlockedLocations;
    // Walk locations in order; the last unlocked one is the current location.
    String? current;
    for (final loc in locations) {
      if (unlocked.contains(loc.id)) current = loc.name;
    }
    return current ?? 'Pallet Town';
  }

  static String _locationBg(String location) {
    // Named locations with dedicated artwork
    const named = <String, String>{
      'Your Bedroom': 'assets/locations/playerhouse1.png',
      "Player's House": 'assets/locations/playerhouse2.png',
      "Oak's Lab": 'assets/locations/oakslab.png',
      'Pallet Town': 'assets/locations/oakslab.png',
      'Viridian City': 'assets/locations/viridian.png',
      'Viridian Forest': 'assets/locations/viridianforest.png',
      'Pewter City': 'assets/locations/oakslab.png',
      'Mt. Moon': 'assets/locations/mtmoon.png',
      'Cerulean City': 'assets/locations/oakslab.png',
      'Vermilion City': 'assets/locations/oakslab.png',
      'Lavender Town': 'assets/locations/oakslab.png',
      'Celadon City': 'assets/locations/oakslab.png',
      'Fuchsia City': 'assets/locations/oakslab.png',
      'Saffron City': 'assets/locations/oakslab.png',
      'Cinnabar Island': 'assets/locations/oakslab.png',
      'Indigo Plateau': 'assets/locations/oakslab.png',
      'Rock Tunnel': 'assets/locations/rocktunnel.png',
      'Seafoam Islands': 'assets/locations/seafoam.png',
      'Pokémon Mansion': 'assets/locations/mansion.png',
      'Victory Road': 'assets/locations/victoryroad.png',
    };
    if (named.containsKey(location)) return named[location]!;

    // Route pattern: "Route 1" → assets/locations/route1.png
    final routeMatch = RegExp(r'^Route (\d+)$').firstMatch(location);
    if (routeMatch != null) {
      return 'assets/locations/route${routeMatch.group(1)}.png';
    }

    return 'assets/locations/kanto.png';
  }

  void _showMissionsDialog(BuildContext context) {
    final ctrl = context.read<PlayerProfileController>();
    final quest = ctrl.activeQuest;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.assignment, color: Color(0xFFC9A44C), size: 22),
            const SizedBox(width: 8),
            const Text('Missions', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54, size: 20),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: quest != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(quest.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    quest.completed ? 'COMPLETED' : '${quest.doneCount}/${quest.objectives.length} objectives',
                    style: TextStyle(
                      color: quest.completed ? Colors.green : Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...quest.objectives.map((obj) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          obj.completed ? Icons.check_circle : Icons.circle_outlined,
                          color: obj.completed ? Colors.green : Colors.white38,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            obj.description,
                            style: TextStyle(
                              color: obj.completed ? Colors.white54 : Colors.white70,
                              fontSize: 14,
                              decoration: obj.completed ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
                  if (quest.completed && quest.rewardMoney > 0) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('₽', style: TextStyle(color: Color(0xFFC9A44C), fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 4),
                        Text(
                          '+${quest.rewardMoney} ${quest.rewardDescription}',
                          style: const TextStyle(color: Color(0xFFC9A44C), fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ],
              )
            : const Text('No active missions.', style: TextStyle(color: Colors.white54, fontSize: 14)),
      ),
    );
  }

  void _showChangelogs(BuildContext context) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Changelogs', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<List<Map<String, String>>>(
            future: _fetchChangelogs(),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snap.data ?? [];
              if (items.isEmpty) {
                return const Text('No changelogs available.',
                    style: TextStyle(color: Colors.white54));
              }
              return ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(color: Colors.white12),
                itemBuilder: (_, i) {
                  final item = items[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item['version']!,
                            style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(item['body']!,
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, String>>> _fetchChangelogs() async {
    try {
      final uri = Uri.parse(
          'https://api.github.com/repos/akingofcrows/pokemon-triad-updates/releases?per_page=10');
      final response = await http.get(uri, headers: {
        'User-Agent': 'PokemonTriad/1.0',
        'Accept': 'application/vnd.github+json',
      }).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as List<dynamic>;
      return data.take(10).map((r) {
        final tag = (r['tag_name'] as String?) ?? '';
        final body = (r['body'] as String?) ?? '';
        return {'version': tag, 'body': body};
      }).toList();
    } catch (_) {
      return [];
    }
  }

  void _showSettings(BuildContext context) {
    final updateService = UpdateService.instance;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final version = _getVersion();
        return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Settings', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.white54),
                title: FutureBuilder<String>(
                  future: version,
                  builder: (_, snap) => Text(
                    'Version: ${snap.data ?? '...'}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.system_update, color: Colors.white70),
                title: const Text('Check for Updates', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final update = await updateService.checkForUpdate();
                  if (!context.mounted) return;
                  if (update != null) {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => UpdateDialog(info: update),
                    );
                  } else {
                    _scaffoldMessengerKey.currentState?.showSnackBar(
                      SnackBar(
                        content: Text(updateService.lastError.isNotEmpty &&
                                !updateService.lastError.startsWith('Up to date')
                            ? 'Update check failed: ${updateService.lastError}'
                            : '✓ You\'re on the latest version!'),
                        duration: const Duration(seconds: 4),
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                title: const Text('Delete Character', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showDeleteDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.white70),
                title: const Text('Log Out', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await context.read<AuthService>().logout();
                  if (context.mounted) {
                    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.title, (_) => false);
                  }
                },
              ),
            ],
          ),
        ),
      );
      },
    );
  }

  Future<String> _getVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return 'unknown';
    }
  }

  void _showDeleteDialog(BuildContext context) {
    final trainerName = context.read<PlayerProfileController>().profile?.trainerName ?? '';
    final nameController = TextEditingController();
    String? error;
    bool deleting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Delete Character', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This will permanently delete your character and all cards. Type your trainer name to confirm:',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Text(
                trainerName,
                style: const TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  hintText: 'Type your trainer name',
                  errorText: error,
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: deleting ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: deleting
                  ? null
                  : () async {
                      final typed = nameController.text.trim();
                      if (typed.toLowerCase() != trainerName.toLowerCase()) {
                        setDialogState(() => error = 'Name does not match.');
                        return;
                      }
                      setDialogState(() => deleting = true);
                      try {
                        await context.read<ApiClient>().deleteCharacter(trainerName);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        await context.read<AuthService>().logout();
                        if (context.mounted) {
                          Navigator.pushNamedAndRemoveUntil(context, AppRoutes.title, (_) => false);
                        }
                      } catch (e) {
                        setDialogState(() {
                          deleting = false;
                          error = e is ApiException ? e.message : 'Failed to delete. Try again.';
                        });
                      }
                    },
              child: deleting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('DELETE', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Glass navigation icon ──────────────────────────────────────────────
class _NavIcon extends StatelessWidget {
  const _NavIcon({required this.image, required this.tooltip, required this.onTap});
  final String image;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 48,
          height: 48,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.2),
          ),
          child: Image.asset(image, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

// ─── Glass navigation button ────────────────────────────────────────────
class _GlassNavButton extends StatelessWidget {
  const _GlassNavButton({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.white.withValues(alpha: 0.12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.2),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ─── Oak tutorial overlay for deckless new players ────────────────────
class _OakTutorial extends StatelessWidget {
  const _OakTutorial({required this.onChooseDeck});
  final VoidCallback onChooseDeck;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChooseDeck,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Dialogue box
          Container(
            width: 220,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF083048),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF8F0E0), width: 1.5),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Oh! You haven't chosen\nyour first deck yet!",
                  style: TextStyle(color: Color(0xFFF8F0E0), fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC9A44C),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Choose a Deck →',
                    style: TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // Oak sprite
          Image.asset('assets/trainers/intro/introOak.png', height: 170),
        ],
      ),
    );
  }
}

// ─── Favorites full-screen swiper ──────────────────────────────────────
class _FavoritesDialog extends StatelessWidget {
  const _FavoritesDialog({required this.instances});
  final List<CardGrowth> instances;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF252525),
      appBar: AppBar(
        title: const Text('Favorite Cards'),
        backgroundColor: const Color(0xFF252525),
      ),
      body: PageView.builder(
        itemCount: instances.length,
        controller: PageController(viewportFraction: 0.85),
        itemBuilder: (_, i) {
          final inst = instances[i];
          final card = CardRepository.instance.cardById(inst.cardId);
          if (card == null) return const SizedBox.shrink();
          return Center(
            child: TriadCardView(card: card, size: 300, growth: inst),
          );
        },
      ),
    );
  }
}

// ─── Trainer sprite + orbiting cards ───────────────────────────────────
class _OrbitingTrainer extends StatelessWidget {
  const _OrbitingTrainer({
    required this.elapsed,
    required this.appearance,
    required this.cards,
  });

  final Duration elapsed;
  final TrainerAppearance appearance;
  final List<CardGrowth> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final cx = constraints.maxWidth / 2;
        final cy = constraints.maxHeight / 2;
        final orbitR = min(cx, cy) * 0.65;

        // Continuous angle from elapsed time — never resets
        final t = elapsed.inMilliseconds / 12000.0; // one full orbit per 12s per speed unit
        final behind = <Widget>[];
        final inFront = <Widget>[];

        for (var i = 0; i < cards.length; i++) {
          final inst = cards[i];
          final card = CardRepository.instance.cardById(inst.cardId);
          if (card == null) continue;
          final phase = (i / max(cards.length, 1)) * 2 * pi;
          // Speed based on card power: trainer cards = 1.5, Pokémon = values.total / 10
          final cardSpeed = card.cardType == TriadCardType.trainer
              ? 1.5
              : (card.values.total / 10.0).clamp(0.8, 3.0);
          final angle = phase + t * 2 * pi * cardSpeed;
          final rx = orbitR * (0.85 + 0.15 * sin(t * 3 * pi + i));
          final ry = orbitR * 0.7;
          final x = cx + rx * cos(angle) - 36;
          final y = cy + ry * sin(angle) - 36;

              final cardWidget = Positioned(
                left: x,
                top: y,
                child: Transform.scale(
                  scale: 1.05,
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: TriadCardView(card: card, size: 72, growth: inst),
                  ),
                ),
              );

              if (sin(angle) < -0.05) {
                behind.add(cardWidget);
              } else {
                inFront.add(cardWidget);
              }
            }

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Base platform — always behind everything
                Positioned(
                  left: cx - 80,
                  top: cy - 10,
                  child: Image.asset(
                    'assets/ui/elite3_base1.png',
                    width: 160,
                    filterQuality: FilterQuality.none,
                  ),
                ),
                // Cards behind trainer (but in front of base)
                ...behind,
                // Trainer sprite
                Positioned(
                  left: cx - 60,
                  top: cy - 84,
                  child: TrainerSpriteStack(appearance: appearance, size: 120),
                ),
                // Cards in front of trainer
                ...inFront,
              ],
            );
      },
    );
  }
}

// ─── Gift list dialog ───────────────────────────────────────────────────
String? _boosterImageFor(String itemId) {
  const map = {
    'field_trip': 'assets/images/Booster Pack/field.png',
    'kanto': 'assets/images/Booster Pack/kanto.png',
    'johto': 'assets/images/Booster Pack/johto.png',
    'safari': 'assets/images/Booster Pack/safari.png',
    'urban': 'assets/images/Booster Pack/urban.png',
  };
  return map[itemId];
}

String? _boosterNameFor(String itemId) {
  const map = {
    'field_trip': 'Field Trip Booster',
    'kanto': 'Kanto Collection',
    'johto': 'Johto Collection',
    'safari': 'Safari Tour',
    'urban': 'Urban Life',
  };
  return map[itemId];
}

class _GiftListDialog extends StatefulWidget {
  const _GiftListDialog({
    required this.gifts,
    required this.scaffoldMessengerKey,
    required this.apiClient,
    required this.profileController,
  });
  final List<Map<String, dynamic>> gifts;
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;
  final ApiClient apiClient;
  final PlayerProfileController profileController;

  @override
  State<_GiftListDialog> createState() => _GiftListDialogState();
}

class _GiftListDialogState extends State<_GiftListDialog> {
  final Set<int> _claiming = {};
  bool _loadFailed = false;

  Future<void> _claim(int giftId) async {
    setState(() {
      _claiming.add(giftId);
      _loadFailed = false;
    });
    final gift = widget.gifts.firstWhere((g) => g['id'] == giftId);
    final itemId = gift['item_id'] as String? ?? '';
    final card = itemId.isNotEmpty ? CardRepository.instance.cardById(itemId) : null;
    final cardName = card?.name ?? itemId;
    try {
      await widget.apiClient.claimGift(giftId);
      // If this is a booster gift, add to local inventory immediately
      final isBooster = card == null && _boosterImageFor(itemId) != null;
      if (isBooster) {
        final qty = gift['quantity'] as int? ?? 1;
        widget.profileController.addBoosterToInventory(itemId, qty);
      } else {
        // Refresh collection so card gifts show up immediately
        await widget.profileController.loadFromServer();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _claiming.remove(giftId);
          _loadFailed = true;
        });
        // Show error toast via the home screen's messenger
        widget.scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('Claim failed: ${e.toString().replaceFirst('Exception: ', '')}',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }
    if (mounted) {
      // Show success toast via the home screen's ScaffoldMessenger
      final spritePath = card != null
          ? card.image.replaceFirst('assets/pokemon/', 'assets/sprites/front/')
          : null;
      // Pre-cache the sprite so it renders immediately in the SnackBar
      if (spritePath != null) {
        precacheImage(AssetImage(spritePath), context);
      }
      widget.scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              if (spritePath != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.asset(
                    spritePath,
                    width: 32,
                    height: 32,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.card_giftcard,
                      color: Color(0xFFC9A44C),
                      size: 28,
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              Text('$cardName added to your collection!',
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
            ],
          ),
          backgroundColor: const Color(0xCC0D0D1A),
          duration: const Duration(seconds: 2),
        ),
      );
      setState(() {
        _claiming.remove(giftId);
        widget.gifts.removeWhere((g) => g['id'] == giftId);
      });
      if (widget.gifts.isEmpty) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          constraints: const BoxConstraints(maxHeight: 400),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF444444)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Row(children: [
                  Icon(Icons.card_giftcard, color: Color(0xFFC9A44C), size: 24),
                  SizedBox(width: 10),
                  Text('Gifts', style: TextStyle(color: Colors.white, fontSize: 18, fontFamily: 'PowerGreen', fontWeight: FontWeight.bold)),
                ]),
              ),
              Flexible(
                child: widget.gifts.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No gifts!', style: TextStyle(color: Color(0x8AFFFFFF))))
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: widget.gifts.length,
                        separatorBuilder: (_, __) => const Divider(color: Colors.white12),
                        itemBuilder: (_, i) {
                          final g = widget.gifts[i];
                          final giftId = g['id'] as int;
                          final msg = g['message'] as String? ?? 'A gift!';
                          final itemId = g['item_id'] as String? ?? '';
                          final qty = g['quantity'] as int? ?? 1;
                          final card = itemId.isNotEmpty ? CardRepository.instance.cardById(itemId) : null;
                          final boosterImg = _boosterImageFor(itemId);
                          final name = card?.name ?? _boosterNameFor(itemId) ?? itemId;
                          final claiming = _claiming.contains(giftId);

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: card != null
                                ? SizedBox(width: 40, height: 40, child: TriadCardView(card: card, size: 40))
                                : boosterImg != null
                                    ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.asset(boosterImg, width: 40, height: 55, fit: BoxFit.cover))
                                    : const Icon(Icons.card_giftcard, color: Colors.white54),
                            title: Text('$name x$qty', style: const TextStyle(color: Colors.white, fontSize: 14)),
                            subtitle: Text(msg, style: const TextStyle(color: Colors.white54, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: claiming
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))
                                : TextButton(
                                    onPressed: () => _claim(giftId),
                                    child: const Text('CLAIM', style: TextStyle(color: Color(0xFFC9A44C), fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CLOSE', style: TextStyle(color: Colors.white38)),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Chatot peek animation ───────────────────────────────────────────────
class _ChatotPeek extends StatefulWidget {
  const _ChatotPeek({required this.spritePath});
  final String spritePath;
  @override
  State<_ChatotPeek> createState() => _ChatotPeekState();
}

class _ChatotPeekState extends State<_ChatotPeek>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _slide = Tween(begin: 0.4, end: 0.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _slide,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, _slide.value * 45),
        child: child,
      ),
      child: Transform.flip(
        flipX: true,
        child: Image.file(File(widget.spritePath), width: 100, height: 100),
      ),
    );
  }
}

// ─── Connection Lost Overlay ────────────────────────────────────────────
class _ConnectionLostOverlay extends StatefulWidget {
  const _ConnectionLostOverlay();
  @override
  State<_ConnectionLostOverlay> createState() => _ConnectionLostOverlayState();
}

class _ConnectionLostOverlayState extends State<_ConnectionLostOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.92),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, (_ctrl.value - 0.5) * 30),
                child: child,
              ),
              child: Image.asset('assets/pokemon/PORYGON.png', width: 96, height: 96),
            ),
            const SizedBox(height: 16),
            const Text('Connection Lost',
                style: TextStyle(color: Colors.white, fontSize: 20,
                    fontWeight: FontWeight.bold, fontFamily: 'PowerGreen')),
            const SizedBox(height: 8),
            const Text('Trying to reconnect…',
                style: TextStyle(color: Colors.white54, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// ─── Version label ──────────────────────────────────────────────────────
class _VersionLabel extends StatefulWidget {
  @override
  State<_VersionLabel> createState() => _VersionLabelState();
}

class _VersionLabelState extends State<_VersionLabel> {
  String _ver = '';

  @override
  void initState() {
    super.initState();
    _loadVer();
  }

  Future<void> _loadVer() async {
    try {
      final p = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _ver = 'v${p.version}');
    } catch (_) {
      if (mounted) setState(() => _ver = 'v1.0.0');
    }
  }

  @override
  Widget build(BuildContext ctx) => Text(
        _ver,
        style: const TextStyle(color: Color(0x33FFFFFF), fontSize: 11),
      );
}

// ─── MMORPG-style chat ─────────────────────────────────────────────
class _ChatMsg {
  _ChatMsg({required this.sender, required this.text});
  final String sender;
  final String text;
}

extension _ChatBox on _HomeScreenState {
  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients) {
        _chatScroll.animateTo(_chatScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _sendChat(String text, String senderName) {
    if (text.trim().isEmpty) return;
    setState(() {
      _chatMessages.add(_ChatMsg(sender: senderName, text: text.trim()));
      if (_chatMessages.length > 100) _chatMessages.removeAt(0);
    });
    _chatController.clear();
    // Post to server
    try {
      context.read<ApiClient>().postChat(text.trim(), senderName);
    } catch (_) {}
    // Also send via WebSocket for real-time
    _sendChatWs(senderName, text.trim());
    _scrollChatToBottom();
  }

  void _sendChatWs(String sender, String text) async {
    try {
      final token = (await AuthService(context.read<ApiClient>()).currentToken) ?? '';
      _socket?.emit('chat_message', {
        'sender': sender,
        'text': text,
        'token': token,
      });
    } catch (_) {}
  }

  Widget _buildChatBox(BuildContext context, PlayerProfile profile) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => setState(() {
            _chatOpen = !_chatOpen;
            if (_chatOpen) {
              _unreadChatCount = 0;
              _loadChat();
            }
          }),
          child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: const Color(0xCC0D0D1A),
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
        ),
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: _chatOpen ? 140 : 32,
        child: ClipRect(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Collapsed bar / header
            SizedBox(
              height: 32,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                children: [
                  const Icon(Icons.chat_bubble_outline, color: Colors.white54, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    _chatOpen ? 'Chat' : 'Tap to chat...',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const Spacer(),
                  if (_chatOpen)
                    Icon(
                      _chatOpen ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                      color: Colors.white54,
                      size: 18,
                    ),
                ],
              ),
            ),
          ),
          // Expanded chat area
            if (_chatOpen)
              Expanded(
                child: Column(
                  children: [
                    // Messages
                    Expanded(
                      child: ListView.builder(
                        controller: _chatScroll,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _chatMessages.length,
                        itemBuilder: (_, i) {
                          final msg = _chatMessages[i];
                          final isMe = msg.sender == (profile.trainerName ?? profile.playerName);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: '[${msg.sender}] ',
                                    style: TextStyle(
                                      color: isMe ? const Color(0xFFC9A44C) : Colors.white38,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  TextSpan(
                                    text: msg.text,
                                    style: TextStyle(color: isMe ? Colors.white : Colors.white54, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    // Input row
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _chatController,
                              focusNode: _chatFocus,
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                              decoration: const InputDecoration(
                                hintText: 'Type a message...',
                                hintStyle: TextStyle(color: Colors.white30, fontSize: 12),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 4),
                              ),
                              onSubmitted: (text) => _sendChat(text, profile.trainerName ?? profile.playerName),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => _sendChat(_chatController.text, profile.trainerName ?? profile.playerName),
                            child: const Icon(Icons.send, color: Color(0xFFC9A44C), size: 20),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  ),
  ),
        // Chatot peeks out from behind minimized chat bar when unread messages
        if (!_chatOpen && _unreadChatCount > 0 && _chatotPath != null)
          Positioned(
            bottom: 5,
            left: 8,
            child: _ChatotPeek(spritePath: _chatotPath!),
          ),
      ],
    );
  }
}

class _BattleOption extends StatelessWidget {
  const _BattleOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.greyedOut = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;
  final bool greyedOut;

  @override
  Widget build(BuildContext context) {
    final alpha = greyedOut ? 0.03 : 0.06;
    return Material(
      color: Colors.white.withValues(alpha: alpha),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(color: greyedOut ? Colors.white.withValues(alpha: 0.3) : Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(color: Colors.white.withValues(alpha: greyedOut ? 0.15 : 0.5), fontSize: 12)),
                  ],
                ),
              ),
              if (!greyedOut)
                Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Trainer Card Overlay ─────────────────────────────────────────────

class _TrainerCardOverlay extends StatefulWidget {
  const _TrainerCardOverlay({required this.onClose});
  final VoidCallback onClose;

  @override
  State<_TrainerCardOverlay> createState() => _TrainerCardOverlayState();
}

class _TrainerCardOverlayState extends State<_TrainerCardOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _tiltController;
  late final Animation<double> _tiltAnimation;
  late final AnimationController _flipController;

  @override
  void initState() {
    super.initState();
    _tiltController = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);
    _tiltAnimation = Tween<double>(begin: -0.035, end: 0.035).animate(
      CurvedAnimation(parent: _tiltController, curve: Curves.easeInOut),
    );
    _flipController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
  }

  @override
  void dispose() {
    _tiltController.dispose();
    _flipController.dispose();
    super.dispose();
  }

  void _flip() {
    if (_flipController.isAnimating) return;
    if (_flipController.value == 0) {
      _flipController.forward();
    } else {
      _flipController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<PlayerProfileController>().profile;
    final isGirl = profile.gender == 'girl';
    final topH = MediaQuery.of(context).padding.top + 63;
    final botH = MediaQuery.of(context).padding.bottom - 3;

    return Column(
      children: [
        SizedBox(height: topH),
        Expanded(
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: widget.onClose,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(color: Colors.black.withValues(alpha: 0.3)),
                    ),
                    Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: GestureDetector(
                        onTap: _flip,
                        child: AnimatedBuilder(
                          animation: Listenable.merge([_tiltAnimation, _flipController]),
                          builder: (context, child) {
                            final flipAngle = _flipController.value * 3.1415926535;
                            final showingBack = _flipController.value >= 0.5;
                            final face = showingBack
                                ? Transform(
                                    alignment: Alignment.center,
                                    transform: Matrix4.identity()..rotateY(3.1415926535),
                                    child: CardBackWidget(isGirl: isGirl, profile: profile),
                                  )
                                : CardFrontWidget(isGirl: isGirl, profile: profile);
                            return Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.0015)
                                ..rotateZ(_tiltAnimation.value)
                                ..rotateY(flipAngle),
                              child: face,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
        SizedBox(height: botH),
      ],
    );
  }
}

// ─── Trainer XP circle in top nav ─────────────────────────────────────

class _TrainerXpCircle extends StatelessWidget {
  const _TrainerXpCircle({required this.appearance});
  final TrainerAppearance appearance;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PlayerProfileController>();
    final lv = ctrl.trainerLevel;
    final inLv = ctrl.trainerXpInLevel;
    final next = ctrl.trainerXpForNextLevel;
    final progress = next > 0 ? inLv / next : 0.0;
    final badgeColor = appearance.gender == 'girl'
        ? const Color(0xFFF472B6)
        : const Color(0xFF4FC3F7);

    // Bottom half of sprite clipped to oval inside the ring
    // Shared sprite builder helper
    Widget _sprite() => OverflowBox(
      minWidth: 64,
      maxWidth: 64,
      minHeight: 64,
      maxHeight: 64,
      alignment: Alignment.topCenter,
      child: Transform.translate(
        offset: const Offset(0, -6),
        child: TrainerSpriteStack(appearance: appearance, size: 64),
      ),
    );

    // Bottom half behind ring
    final spriteBottom = ClipRect(
      clipper: _BottomHalfClipper(),
      child: SizedBox(width: 72, height: 72, child: _sprite()),
    );

    // Top half overflows ring
    final spriteTop = ClipRect(
      clipper: _TopHalfClipper(),
      child: SizedBox(width: 72, height: 72, child: _sprite()),
    );

    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Layer 0: filled inner circle behind sprites
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF1E1E1E),
            ),
          ),
          // Layer 1: bottom half of sprite behind ring
          spriteBottom,
          // Layer 2: outer grey ring + progress ring
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              border: Border.fromBorderSide(BorderSide(color: Color(0xFF1E1E1E), width: 10)),
            ),
            child: Center(
              child: SizedBox(
                width: 52,
                height: 52,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 4,
                  strokeCap: StrokeCap.round,
                  valueColor: AlwaysStoppedAnimation<Color>(badgeColor),
                  backgroundColor: const Color(0xFF444444),
                ),
              ),
            ),
          ),
          // Layer 2.5: bottom partial 1px light grey border on outer ring
          ClipRect(
            clipper: _BottomPartialClipper(),
            child: Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                border: Border.fromBorderSide(BorderSide(color: Color(0xFF444444), width: 1)),
              ),
            ),
          ),
          // Layer 3: top half of sprite (over the ring)
          spriteTop,
          // Layer 4: level badge
          Positioned(
            left: 0,
            right: 0,
            bottom: -12,
            child: Center(
              child: Container(
                width: 36,
                height: 18,
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Center(
                  child: Text(
                    'Lvl $lv',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopHalfClipper extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, size.width, size.height / 2);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}

class _BottomHalfClipper extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, size.height / 2, size.width, size.height);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}

class _BottomPartialClipper extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, size.height * 0.58, size.width, size.height);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}
