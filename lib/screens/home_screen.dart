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
import '../services/audio_service.dart';
import '../widgets/pressable_button.dart';
import 'package:audioplayers/audioplayers.dart';
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
  bool _battleClosing = false;
  bool _trainerCardOpen = false;
  bool _showCaptureInfo = false;
  late final Ticker _ticker;
  int _lastTickMs = 0;
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
    _battleClosing = true;
    setState(() { _battleVisible = false; _battleSoloOpen = false; });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() { _battleClosing = false; });
    });
  }

  @override
  void initState() {
    super.initState();
    _controller = context.read<PlayerProfileController>();
    _loadChatotPath();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker((elapsed) {
      if (mounted) {
        final ms = elapsed.inMilliseconds;
        if (ms - _lastTickMs >= 50) {
          _lastTickMs = ms;
          setState(() => _elapsed = elapsed);
        }
      }
    })..start();
    _topCards = _computeTopCards();
    _controller.addListener(_onProfileChanged);
    _loadStarterFlag();
    _loadChat();
    // Poll for new chat messages every 5 seconds
    _chatPollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _pollChat());
    _giftPollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _pollGifts());
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
      _ticker?.stop();
      _disconnectTimer?.cancel();
      _disconnectTimer = Timer(const Duration(seconds: 60), () {
        if (mounted) {
          setState(() => _connectionLost = true);
          _startReconnectPolling();
        }
      });
    } else if (state == AppLifecycleState.resumed) {
      _ticker?.start();
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

    // Current location = latest unlocked story location (for background only)
    final storyCtrl = context.watch<StoryProgressController>();
    final currentLocationName = profile.location ?? _currentLocationName(storyCtrl);

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
            child: Container(color: const Color(0xFF2D2E35)),
          ),
          // Top bar
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, top: 6, bottom: 6, right: 22),
                child: Row(
                  children: [
                Transform.translate(
                  offset: const Offset(-12, 0),
                  child: _buildFavoritesButton(context),
                ),
                const Spacer(),
                const SizedBox(width: 12),
                PressableButton(
                  onTap: () {}, // TODO: notifications
                  child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Gradient shadow layer
                    Positioned(
                      left: 0, right: 0, top: -4, bottom: -4,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFF42454D), Color(0xFF1A1C20)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Circle container
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFF282A30),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF1A1C20), width: 1),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.notifications_none, color: Colors.white.withValues(alpha: 0.4), size: 18),
                    ),
                  ],
                ),
                ),
                const SizedBox(width: 16),
                PressableButton(
                  onTap: () {}, // TODO: messages
                  child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0, right: 0, top: -4, bottom: -4,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFF42454D), Color(0xFF1A1C20)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFF282A30),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF1A1C20), width: 1),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.mail_outline, color: Colors.white.withValues(alpha: 0.4), size: 18),
                    ),
                  ],
                ),
                ),
                const SizedBox(width: 16),
                PressableButton(
                  onTap: () => _showGiftList(),
                  child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0, right: 0, top: -4, bottom: -4,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFF42454D), Color(0xFF1A1C20)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFF282A30),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF1A1C20), width: 1),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.card_giftcard, color: Colors.white.withValues(alpha: 0.4), size: 18),
                    ),
                    if (_liveGiftCount > 0)
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
                            '$_liveGiftCount',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
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
          SafeArea(
            bottom: false,
            child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.translate(
                  offset: const Offset(0, -60),
                  child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: -4, right: -4, top: -4, bottom: -4,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF2D2E35), Color(0xFF1F2027)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF282A30),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1A1C20), width: 1),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          // Diagonal cut with darkened, blurred location image
                          Positioned(
                            left: 0, right: 0, top: 0, bottom: 0,
                            child: ClipPath(
                              clipper: _DiagonalTopClipper(),
                              child: ColorFiltered(
                                colorFilter: const ColorFilter.mode(Colors.black38, BlendMode.darken),
                                child: ImageFiltered(
                                  imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                                  child: Image.asset(
                                    _locationBg(currentLocationName),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Shadow along diagonal cut — below orbiting cards
                          Positioned(
                            left: 0, right: 0, top: 0, bottom: 0,
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _DiagonalShadowPainter(),
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 220,
                            child: _OrbitingTrainer(
                              elapsed: _elapsed,
                              appearance: appearance,
                              cards: _topCards,
                            ),
                          ),
                          // Inner shadow — 2px light edge on top and left, follows rounded corners
                          Positioned(
                            left: 0, right: 0, top: 0, bottom: 0,
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _InnerShadowPainter(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                ),
                ),
                const SizedBox(height: 3),
                Transform.translate(
                  offset: const Offset(0, -57),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildActiveDeckButton(profile.defaultDeck, diagonalColors: _deckBoxGradient(profile.defaultDeck?.boxImage), badgeTitle: true),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _ShopSpritePeek(),
                              _buildActiveDeckButton(profile.defaultDeck, customImage: 'assets/ui/shop.png', badgeTitle: true, badgeText: 'SHOP', contentHeight: 152, diagonalColors: _deckBoxGradient('shop'), onTapRoute: AppRoutes.shop, showCountdown: true),
                              _ShopNewBadge(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          ),
          // Version number — bottom right
          Positioned(
            bottom: 60,
            right: 8,
            child: _VersionLabel(),
          ),
          // Battle menu — slides up from behind bottom nav
          if (_battleVisible || _battleSoloOpen || _battleClosing)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_battleVisible,
                child: BattleMenuContent(
                  visible: _battleVisible,
                  soloVisible: _battleSoloOpen,
                  onSoloStateChanged: (v) => setState(() => _battleSoloOpen = v),
                  onDismiss: () => setState(() { _battleVisible = false; _battleSoloOpen = false; _currentTab = 0; }),
                ),
              ),
            ),
          // Missions icon — top right below top bar
          Positioned(
            top: kToolbarHeight + MediaQuery.of(context).padding.top + 14,
            right: 8,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0, right: 0, top: -4, bottom: -4,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF42454D), Color(0xFF1A1C20)],
                        ),
                      ),
                    ),
                  ),
                ),
                PressableButton(
                  onTap: () => Navigator.pushNamed(context, AppRoutes.missions),
                  child: Container(
                      height: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF282A30),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1A1C20), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.assignment, color: Colors.white.withValues(alpha: 0.4), size: 14),
                          const SizedBox(width: 4),
                          Text('Missions',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            )),
                        ],
                      ),
                    ),
                ),
              ],
            ),
          ),
          // Trainer Card button — below favs, same Y as missions
          Positioned(
            top: kToolbarHeight + MediaQuery.of(context).padding.top + 14,
            left: 12,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0, right: 0, top: -4, bottom: -4,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF42454D), Color(0xFF1A1C20)],
                        ),
                      ),
                    ),
                  ),
                ),
                PressableButton(
                  onTap: () => setState(() => _trainerCardOpen = true),
                  child: Container(
                      height: 24,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF282A30),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1A1C20), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset('assets/ui/trainercard.png', width: 14, height: 14, color: Colors.white.withValues(alpha: 0.4), colorBlendMode: BlendMode.srcIn),
                          const SizedBox(width: 6),
                          Text('Trainer Card',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            )),
                        ],
                      ),
                    ),
                ),
              ],
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
          // XP circle
          if (!_connectionLost)
            Positioned(
              top: MediaQuery.of(context).padding.top + kToolbarHeight - 36,
              left: 0,
              right: 0,
              child: Center(
                child: Transform.translate(
                  offset: const Offset(5, -8),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _showCaptureInfo = !_showCaptureInfo);
                      if (_showCaptureInfo) {
                        Future.delayed(const Duration(seconds: 5), () {
                          if (mounted) setState(() => _showCaptureInfo = false);
                        });
                      }
                    },
                    child: _TrainerXpCircle(appearance: appearance),
                  ),
                ),
              ),
            ),
          // Trainer level badge — above XP circle
          if (!_connectionLost)
            Positioned(
              top: MediaQuery.of(context).padding.top + kToolbarHeight + 14,
              left: 0,
              right: 0,
              child: Align(
                alignment: const Alignment(0.22, 0),
                child: IntrinsicWidth(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0, right: 0, top: -4, bottom: -4,
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xFF42454D), Color(0xFF1A1C20)],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        height: 24,
                        padding: const EdgeInsets.only(left: 7, right: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF282A30),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF1A1C20), width: 1),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Lvl ${ctrl.trainerLevel}',
                          style: TextStyle(
                            fontFamily: 'PowerGreen',
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // PokéDollars — top-right, above XP circle
          if (!_connectionLost)
            Positioned(
              top: MediaQuery.of(context).padding.top + kToolbarHeight + 14,
              left: 0,
              right: 0,
              child: Align(
                alignment: const Alignment(-0.19, 0),
                child: IntrinsicWidth(
                  child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0, right: 0, top: -4, bottom: -4,
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFF42454D), Color(0xFF1A1C20)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    height: 24,
                    padding: const EdgeInsets.only(left: 7, right: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF282A30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF1A1C20), width: 1),
                    ),
                    alignment: Alignment.centerLeft,
                    child: Text('₽ ${profile.money}',
                      style: TextStyle(fontFamily: 'PowerGreen', fontSize: 12, color: Colors.white.withValues(alpha: 0.4), fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            ),
          ),
          // Capture rate sliding panel
          if (_showCaptureInfo)
            Positioned(
              top: MediaQuery.of(context).padding.top + kToolbarHeight + 10,
              left: 20,
              right: 20,
              child: _CaptureRatePanel(),
            ),
          // Trainer Card overlay — on top of everything
          if (_trainerCardOpen)
            Positioned.fill(
              child: _TrainerCardOverlay(onClose: () => setState(() => _trainerCardOpen = false)),
            ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Shadow cast upward from nav bar
          Container(
            height: 16,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xFF3B3E46), Color(0x003B3E46)],
              ),
            ),
          ),
          ClipRect(
        child: Container(
            decoration: const BoxDecoration(
              color: Color(0xEE2D2E35),
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
      ],
    ),
    );
  }

  static const _navGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF999CA6), Color(0xFF9395A2)],
  );

  Widget _bottomNavIcon(IconData icon, String label, int index) {
    return PressableButton(
      onTap: () => _onNavTap(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Drop shadow — outside ShaderMask so it stays dark
            Padding(
              padding: const EdgeInsets.only(left: 1, top: 2),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                child: Opacity(
                  opacity: 0.7,
                  child: Icon(icon, color: Color(0xFF212329), size: 24),
                ),
              ),
            ),
            // Icon with gradient tint
            ShaderMask(
              shaderCallback: (bounds) => _navGradient.createShader(bounds),
              blendMode: BlendMode.srcIn,
              child: Icon(icon, color: Colors.white, size: 24),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomNavImage(String asset, String label, int index) {
    return PressableButton(
      onTap: () => _onNavTap(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Drop shadow — outside ShaderMask so it stays dark
            Padding(
              padding: const EdgeInsets.only(left: 1, top: 2),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                child: Opacity(
                  opacity: 0.7,
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.mode(Color(0xFF212329), BlendMode.srcIn),
                    child: Image.asset(asset, width: 24, height: 24),
                  ),
                ),
              ),
            ),
            // Image with gradient tint
            ShaderMask(
              shaderCallback: (bounds) => _navGradient.createShader(bounds),
              blendMode: BlendMode.srcIn,
              child: Image.asset(asset, width: 24, height: 24),
            ),
          ],
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
      if (_battleVisible && _battleSoloOpen) {
        // Solo is open — close it, bring Battle back
        setState(() => _battleSoloOpen = false);
      } else if (_battleVisible) {
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
    return PressableButton(
      onTap: () => _showFavorites(context),
      child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Gradient shadow layer
          Positioned(
            left: 0, right: 0, top: -4, bottom: -4,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.horizontal(left: Radius.zero, right: Radius.circular(12)),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF42454D), Color(0xFF1A1C20)],
                  ),
                ),
              ),
            ),
          ),
          // Main container
          Container(
            height: 24,
            padding: const EdgeInsets.only(left: 12, right: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF282A30),
              borderRadius: const BorderRadius.horizontal(left: Radius.zero, right: Radius.circular(12)),
              border: Border.all(color: const Color(0xFF1A1C20), width: 1),
            ),
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: (favInsts.isEmpty ? 33 : 32 + (favInsts.length - 1) * 36.0) + 25,
            height: 32,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < favInsts.length; i++)
                  Builder(builder: (_) {
                    final inst = favInsts[i];
                    final card = CardRepository.instance.cardById(inst.cardId);
                    if (card == null) return const SizedBox.shrink();
                    return Positioned(
                      left: i * 36.0,
                      top: -5,
                      child: SizedBox(
                        width: 32, height: 32,
                        child: TriadCardView(card: card, size: 32, growth: inst),
                      ),
                    );
                  }),
                if (favInsts.isEmpty)
                  const Positioned.fill(
                    child: Center(
                      child: Icon(Icons.star_border, color: Color(0xFF282A30), size: 18),
                    ),
                  ),
                // Home icon with star
                if (favInsts.isNotEmpty)
                  Positioned(
                    right: -5,
                    top: 0,
                    bottom: 0,
                    child: SizedBox(
                      width: 29,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            left: 0,
                            child: SizedBox(
                              width: 22,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Icon(Icons.home, color: Colors.white.withValues(alpha: 0.4), size: 18),
                                  const Icon(Icons.star, color: Color(0xFF282A30), size: 8),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 17,
                            child: Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.4), size: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
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
      backgroundColor: const Color(0xFF33343C),
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
    final api = context.read<ApiClient>();
    final ctrl = context.read<PlayerProfileController>();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _GiftListDialog(
        apiClient: api,
        profileController: ctrl,
        scaffoldMessengerKey: _scaffoldMessengerKey,
      ),
    );
    _busy = false;
    if (mounted) ctrl.loadFromServer();

    if (result != null && mounted) {
      final name = result['name'] as String? ?? '';
      final qty = result['qty'] as int? ?? 1;
      final toastImg = result['image'] as String?;
      final isConsumable = result['isConsumable'] as bool? ?? false;
      if (toastImg != null) {
        precacheImage(AssetImage(toastImg), context);
      }
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              if (toastImg != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 36, height: 36,
                    child: isConsumable
                        ? Stack(alignment: Alignment.center, children: [
                            Image.asset('assets/ui/item_bg.png', width: 36, height: 36, fit: BoxFit.cover),
                            Padding(padding: const EdgeInsets.all(7), child: Image.asset(toastImg, fit: BoxFit.contain)),
                          ])
                        : Image.asset(toastImg, width: 36, height: 36, fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(Icons.card_giftcard, color: Color(0xFFC9A44C), size: 28)),
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(child: Text('$name ×$qty added to your inventory', style: const TextStyle(color: Colors.white, fontSize: 14))),
            ],
          ),
          backgroundColor: const Color(0xCC0D0D1A),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  static const _deckBoxGradientMap = <String, List<Color>>{
    'field_deck': [Color(0xFF282A30), Color(0xFF5CBF60)],
    'safari_deck': [Color(0xFF282A30), Color(0xFFE07030)],
    'urban_deck': [Color(0xFF282A30), Color(0xFF4A8ABC)],
    'shop': [Color(0xFF636178), Color(0xFF526170)],
  };

  static List<Color> _deckBoxGradient(String? boxImg) {
    return _deckBoxGradientMap[boxImg] ?? _deckBoxGradientMap['shop']!;
  }

  Widget _buildActiveDeckButton(Deck? deck, {List<Color>? diagonalColors, bool badgeTitle = false, bool showContent = true, String? customImage, String? badgeText, double contentHeight = 150, String? onTapRoute, bool showCountdown = false}) {
    final ctrl = context.read<PlayerProfileController>();
    final growth = ctrl.cardGrowth;
    final boxImg = deck?.boxImage ?? 'field_deck';
    final gradColors = diagonalColors ?? const [Color(0xFF282A30), Color(0xFF526170)];
    return PressableButton(
      onTap: () => Navigator.pushNamed(context, onTapRoute ?? AppRoutes.deckBuilder),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Gradient shadow
          Positioned(
            left: -4, right: -4, top: -4, bottom: -4,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2D2E35), Color(0xFF1F2027)],
                  ),
                ),
              ),
            ),
          ),
          // Outer border
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF74777F), width: 2),
              ),
            ),
          ),
          // Main container
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF282A30),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1A1C20), width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // Diagonal cut with color gradient
                Positioned(
                  left: 0, right: 0, top: 0, bottom: 0,
                  child: ClipPath(
                    clipper: _DiagonalTopClipper(),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.topRight,
                          colors: gradColors,
                        ),
                      ),
                    ),
                  ),
                ),
                // Deck box icon watermark in the diagonal cut — same
                // treatment as a shop card's type icon watermark.
                if (customImage == null && deckBoxIconAsset(boxImg) != null)
                  Positioned(
                    top: 0,
                    left: 4,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: 0.22,
                        child: ColorFiltered(
                          colorFilter: const ColorFilter.mode(
                            Color(0xFFB0B0B8),
                            BlendMode.srcIn,
                          ),
                          child: Image.asset(
                            deckBoxIconAsset(boxImg)!,
                            width: 56,
                            height: 56,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  ),
                // Content
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!badgeTitle)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          badgeText ?? (deck != null ? 'ACTIVE DECK' : 'No Active Deck'),
                          style: const TextStyle(
                            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800,
                            letterSpacing: 2, fontFamily: 'PowerGreen',
                          ),
                        ),
                      ),
                    if (showContent)
                      SizedBox(
                        width: 220,
                        height: contentHeight,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Align(
                              alignment: Alignment.center,
                              child: customImage != null
                              ? Image.asset(customImage, width: 80, height: 60, fit: BoxFit.contain, color: const Color(0xFF959FB3), colorBlendMode: BlendMode.srcIn)
                              : Image.asset('assets/images/Booster Pack/$boxImg.png', width: 170, height: 120, fit: BoxFit.contain),
                            ),
                            if (customImage == null && deck != null && deck.cardIds.isNotEmpty)
                              Transform.translate(
                                offset: const Offset(-4, 28),
                                child: Center(
                                  child: SizedBox(
                                    width: 48, height: 48,
                                    child: _buildFeaturedCardInline(deck, ctrl, growth),
                                  ),
                                ),
                              ),
                            if (customImage == null && deck != null)
                              Positioned(
                                bottom: 4,
                                left: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0x60000000),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(deck.name,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Color(0xFF9C9DA3), fontSize: 11, fontWeight: FontWeight.w800, fontFamily: 'PowerGreen')),
                                ),
                              ),
                            if (showCountdown)
                              const Positioned(
                                bottom: 4, left: 0, right: 0,
                                child: _ShopCountdown(),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
                // Inner shadow
                Positioned(
                  left: 0, right: 0, top: 0, bottom: 0,
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _InnerShadowPainter(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Badge on top — highest z-index
          if (badgeTitle)
            Positioned(
              left: 0, right: 0, top: 0,
              child: Center(
                child: Transform.translate(
                  offset: const Offset(0, -12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0x60000000),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badgeText ?? (deck != null ? 'ACTIVE DECK' : 'No Active Deck'),
                      style: const TextStyle(
                        color: Color(0xFF9C9DA3), fontSize: 11, fontWeight: FontWeight.w800,
                        letterSpacing: 2, fontFamily: 'PowerGreen',
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
      left: 78,
      top: 43,
      child: SizedBox(
        width: 64, height: 64,
        child: TriadCardView(card: card, size: 64, growth: g),
      ),
    );
  }

  Widget _buildFeaturedCardInline(Deck deck, PlayerProfileController ctrl, Map<String, CardGrowth> growth) {
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

    return TriadCardView(card: card, size: 48, growth: g);
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
            color: Color(0xFF33343C),
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
                      color: const Color(0xFF33343C),
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
            // Scrollable menu items
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
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
                ],
              ),
            ),
            // Fixed bottom items
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
      'Pallet Town': 'assets/locations/pallet.png',
      'Viridian City': 'assets/locations/viridian.png',
      'Viridian Forest': 'assets/locations/viridianforest.png',
      'Pewter City': 'assets/locations/pewter.png',
      'Mt. Moon': 'assets/locations/mtmoon.png',
      'Cerulean City': 'assets/locations/cerulean.png',
      'Vermilion City': 'assets/locations/vermillion.png',
      'Lavender Town': 'assets/locations/lavender.png',
      'Celadon City': 'assets/locations/celadon.png',
      'Fuchsia City': 'assets/locations/fuschia.png',
      'Saffron City': 'assets/locations/saffron.png',
      'Cinnabar Island': 'assets/locations/cinnabar.png',
      'Indigo Plateau': 'assets/locations/oakslab.png',
      'Rock Tunnel': 'assets/locations/rocktunnel.png',
      'Seafoam Islands': 'assets/locations/seafoam.png',
      'Pokémon Mansion': 'assets/locations/mansion.png',
      'Victory Road': 'assets/locations/victoryroad.png',
    };
    if (named.containsKey(location)) return named[location]!;
    // Fallback for any unknown location
    return 'assets/locations/kanto.png';
  }

  void _showMissionsDialog(BuildContext context) {
    final ctrl = context.read<PlayerProfileController>();
    final quest = ctrl.activeQuest;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF33343C),
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
        backgroundColor: const Color(0xFF33343C),
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
              const SizedBox(height: 4),
              _VolumeSlider(icon: Icons.music_note, label: 'BGM', initialValue: AudioService().bgmVolume, onChanged: (v) => AudioService().setBgmVolume(v)),
              _VolumeSlider(icon: Icons.volume_up, label: 'SFX', initialValue: AudioService().sfxVolume, onChanged: (v) => AudioService().setSfxVolume(v)),
              const SizedBox(height: 4),
              ListTile(
                leading: const Icon(Icons.system_update, color: Colors.white70),
                title: const Text('Check for Updates', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  final nav = Navigator.of(context, rootNavigator: true);
                  Future.delayed(const Duration(milliseconds: 400), () async {
                    final update = await updateService.checkForUpdate();
                    if (update != null) {
                      showDialog(
                        context: nav.context,
                        barrierDismissible: false,
                        builder: (_) => UpdateDialog(info: update),
                      );
                    } else {
                      showDialog(
                        context: nav.context,
                        builder: (_) => AlertDialog(
                          backgroundColor: const Color(0xFF33343C),
                          title: const Text('Update Check', style: TextStyle(color: Colors.white)),
                          content: Text(
                            updateService.lastError.isNotEmpty && !updateService.lastError.startsWith('Up to date')
                                ? 'Update check failed:\n${updateService.lastError}'
                                : '\u2713 You\'re on the latest version!',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          actions: [TextButton(onPressed: () => nav.pop(), child: const Text('OK'))],
                        ),
                      );
                    }
                  });
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
                    style: TextStyle(color: Color(0xFF212329), fontSize: 13, fontWeight: FontWeight.bold),
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
      backgroundColor: const Color(0xFF33343C),
      appBar: AppBar(
        title: const Text('Favorite Cards'),
        backgroundColor: const Color(0xFF33343C),
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
                key: ValueKey(inst.instanceId ?? inst.cardId),
                left: x,
                top: y,
                child: Transform.scale(
                  scale: 1.05,
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [BoxShadow(color: Color(0x60000000), blurRadius: 8, offset: Offset(3, 4), spreadRadius: 2)],
                    ),
                    child: TriadCardView(card: card, size: 60, growth: inst, dimUnusable: false),
                  ),
                ),
              );

              if (sin(angle) < -0.05) {
                behind.add(cardWidget);
              } else {
                inFront.add(cardWidget);
              }
            }

            return RepaintBoundary(
              child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Base platform — always behind everything
                Positioned(
                  left: cx - 80,
                  top: cy - 10,
                  child: SizedBox(
                    width: 160,
                    height: 160,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 3,
                          top: 4,
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                            child: ColorFiltered(
                              colorFilter: const ColorFilter.mode(Colors.black38, BlendMode.srcIn),
                              child: Image.asset(
                                'assets/ui/elite3_base1.png',
                                width: 160,
                                filterQuality: FilterQuality.none,
                              ),
                            ),
                          ),
                        ),
                        Image.asset(
                          'assets/ui/elite3_base1.png',
                          width: 160,
                          filterQuality: FilterQuality.none,
                        ),
                      ],
                    ),
                  ),
                ),
                // Cards behind trainer (but in front of base)
                ...behind,
                // Trainer sprite
                Positioned(
                  left: cx - 60,
                  top: cy - 84,
                  child: SizedBox(
                    width: 120,
                    height: 120,
                    child: Stack(
                      children: [
                        // Shadow layer — offset, black, blurred,
                        Positioned(
                          left: 3,
                          top: 4,
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                            child: ColorFiltered(
                              colorFilter: const ColorFilter.mode(Colors.black38, BlendMode.srcIn),
                              child: TrainerSpriteStack(appearance: appearance, size: 120),
                            ),
                          ),
                        ),
                        // Actual sprite
                        TrainerSpriteStack(appearance: appearance, size: 120),
                      ],
                    ),
                  ),
                ),
                // Cards in front of trainer
                ...inFront,
              ],
            ),
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

String? _consumableImageFor(String itemId) {
  const map = {
    'pokeball': 'assets/images/icons/items/item267.png',
    'great_ball': 'assets/images/icons/items/item268.png',
    'ultra_ball': 'assets/images/icons/items/item269.png',
    'master_ball': 'assets/images/icons/items/item270.png',
    'potion': 'assets/images/icons/items/potion.png',
  };
  return map[itemId];
}

String? _consumableNameFor(String itemId) {
  const map = {
    'pokeball': 'Poké Ball',
    'great_ball': 'Great Ball',
    'ultra_ball': 'Ultra Ball',
    'master_ball': 'Master Ball',
    'potion': 'Potion',
  };
  return map[itemId];
}

class _GiftListDialog extends StatefulWidget {
  const _GiftListDialog({
    required this.scaffoldMessengerKey,
    required this.apiClient,
    required this.profileController,
  });
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;
  final ApiClient apiClient;
  final PlayerProfileController profileController;

  @override
  State<_GiftListDialog> createState() => _GiftListDialogState();
}

class _GiftListDialogState extends State<_GiftListDialog> {
  final Set<int> _claiming = {};
  List<Map<String, dynamic>> _gifts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadGifts();
  }

  Future<void> _loadGifts() async {
    try {
      final data = await widget.apiClient.getGifts();
      if (mounted) setState(() {
        _gifts = ((data['gifts'] as List<dynamic>?) ?? []).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _claimAll() async {
    final ids = _gifts.map((g) => g['id'] as int).toList();
    Map<String, dynamic>? lastResult;
    for (final id in ids) {
      if (!mounted) return;
      lastResult = await _claim(id);
    }
    if (lastResult != null && mounted) {
      Navigator.pop(context, lastResult);
    }
  }

  Future<Map<String, dynamic>?> _claim(int giftId, {bool popAfter = false}) async {
    setState(() => _claiming.add(giftId));
    final gift = _gifts.firstWhere((g) => g['id'] == giftId);
    final itemId = gift['item_id'] as String? ?? '';
    final card = itemId.isNotEmpty ? CardRepository.instance.cardById(itemId) : null;
    final cardName = card?.name ?? _boosterNameFor(itemId) ?? _consumableNameFor(itemId) ?? itemId;
    try {
      await widget.apiClient.claimGift(giftId);
      final isBooster = card == null && _boosterImageFor(itemId) != null;
      final isConsumable = card == null && _consumableImageFor(itemId) != null;
      final qty = gift['quantity'] as int? ?? 1;
      if (isBooster) {
        widget.profileController.addBoosterToInventory(itemId, qty);
      } else if (isConsumable) {
        widget.profileController.addConsumable(itemId, qty);
      } else {
        await widget.profileController.loadFromServer();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _claiming.remove(giftId);
          _loading = true;
        });
        widget.scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('Claim failed: ${e.toString().replaceFirst('Exception: ', '')}',
                style: const TextStyle(color: Colors.white, fontSize: 14)),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return null;
    }
    if (!mounted) return null;

    final qty = gift['quantity'] as int? ?? 1;
    final boosterImg = _boosterImageFor(itemId);
    final consumableImg = _consumableImageFor(itemId);
    final isConsumable = consumableImg != null;

    String? toastImg;
    if (card != null) {
      toastImg = card.image.replaceFirst('assets/pokemon/', 'assets/sprites/front/');
    } else if (boosterImg != null) {
      toastImg = boosterImg;
    } else if (consumableImg != null) {
      toastImg = consumableImg;
    }

    setState(() {
      _claiming.remove(giftId);
      _gifts.removeWhere((g) => g['id'] == giftId);
    });

    final result = <String, dynamic>{
      'name': cardName, 'qty': qty,
      'image': toastImg, 'isConsumable': isConsumable,
    };

    if (popAfter) {
      Navigator.pop(context, result);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          constraints: const BoxConstraints(maxHeight: 400),
          decoration: BoxDecoration(
            color: const Color(0xFF282A30),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1A1C20)),
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
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator(color: Color(0xFFC9A44C))))
                    : _gifts.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No gifts!', style: TextStyle(color: Color(0x8AFFFFFF))))
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _gifts.length,
                        separatorBuilder: (_, __) => const Divider(color: Colors.white12),
                        itemBuilder: (_, i) {
                          final g = _gifts[i];
                          final giftId = g['id'] as int;
                          final msg = g['message'] as String? ?? 'A gift!';
                          final itemId = g['item_id'] as String? ?? '';
                          final qty = g['quantity'] as int? ?? 1;
                          final card = itemId.isNotEmpty ? CardRepository.instance.cardById(itemId) : null;
                          final boosterImg = _boosterImageFor(itemId);
                          final consumableImg = _consumableImageFor(itemId);
                          final name = card?.name ?? _boosterNameFor(itemId) ?? _consumableNameFor(itemId) ?? itemId;
                          final claiming = _claiming.contains(giftId);

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: card != null
                                ? SizedBox(width: 40, height: 40, child: TriadCardView(card: card, size: 40))
                                : boosterImg != null
                                    ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.asset(boosterImg, width: 40, height: 55, fit: BoxFit.cover))
                                    : consumableImg != null
                                        ? Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              Image.asset('assets/ui/item_bg.png', width: 40, height: 40, fit: BoxFit.cover),
                                              Padding(
                                                padding: const EdgeInsets.all(8),
                                                child: Image.asset(consumableImg, width: 24, height: 24, fit: BoxFit.contain),
                                              ),
                                            ],
                                          )
                                        : const Icon(Icons.card_giftcard, color: Colors.white54),
                            title: Text('$name x$qty', style: const TextStyle(color: Colors.white, fontSize: 14)),
                            subtitle: Text(msg, style: const TextStyle(color: Colors.white54, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: claiming
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))
                                : GestureDetector(
                                    onTap: () => _claim(giftId, popAfter: true),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFC9A44C).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: const Color(0xFFC9A44C).withValues(alpha: 0.4),
                                          width: 1,
                                        ),
                                      ),
                                      child: const Text(
                                        'CLAIM',
                                        style: TextStyle(
                                          color: Color(0xFFC9A44C),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                          );
                        },
                      ),
              ),
              if (_gifts.length > 1) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: _claimAll,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFC9A44C).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFC9A44C).withValues(alpha: 0.5),
                            width: 1.2,
                          ),
                        ),
                        child: Text(
                          'CLAIM ALL (${_gifts.length})',
                          style: const TextStyle(
                            color: Color(0xFFC9A44C),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: PressableButton(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: const Text('CLOSE', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ),
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

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            final p = AudioPlayer();
            p.setVolume(AudioService().sfxVolume);
            p.play(AssetSource('sound/pop-ui.mp3'));
            widget.onClose();
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(color: Colors.black.withValues(alpha: 0.3)),
              ),
              SafeArea(
                child: Center(
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
              ),
            ],
          ),
        ),
      ),
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
      minWidth: 82,
      maxWidth: 82,
      minHeight: 82,
      maxHeight: 82,
      alignment: Alignment.topCenter,
      child: Transform.translate(
        offset: const Offset(0, 16),
        child: TrainerSpriteStack(appearance: appearance, size: 82),
      ),
    );

    // Bottom portion behind ring — clip at ring's inner bottom
    final spriteBottom = ClipRect(
      clipper: _BottomHalfClipper(),
      child: ClipRect(
        clipper: _RingBottomClipper(),
        child: SizedBox(width: 72, height: 72, child: _sprite()),
      ),
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
              color: Color(0xFF2D2E35),
            ),
          ),
          // Layer 1: bottom half of sprite behind ring
          spriteBottom,
          // Layer 2: top half of sprite (under the ring)
          spriteTop,
          // Layer 3: outer grey ring + progress ring (on top of sprite)
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              border: Border.fromBorderSide(BorderSide(color: Color(0xFF2D2E35), width: 10)),
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

/// Clips to only the visible inner portion of the ring (y=10 to y=62 within 72px space).
class _RingBottomClipper extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, size.height * 0.5, size.width, size.height * 0.86);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}

class _BottomPartialClipper extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, size.height * 0.58, size.width, size.height);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}

/// Paints inner shadow (transparent white) + solid #B6A2A0 border on top/left/corner.
class _InnerShadowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = 12.0;

    // Transparent white glow shadow
    final glowPaint = Paint()
      ..color = const Color(0x20FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    canvas.drawLine(Offset(r, 0), Offset(size.width, 0), glowPaint);
    canvas.drawArc(Rect.fromLTWH(0, 0, r * 2, r * 2), 3.14159, 1.5708, false, glowPaint);
    canvas.drawLine(Offset(0, r), Offset(0, size.height), glowPaint);

    // Solid #B6A2A0 border
    final borderPaint = Paint()
      ..color = const Color(0x99B6A2A0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawLine(Offset(r, 0), Offset(size.width, 0), borderPaint);
    canvas.drawArc(Rect.fromLTWH(0, 0, r * 2, r * 2), 3.14159, 1.5708, false, borderPaint);
    canvas.drawLine(Offset(0, r), Offset(0, size.height), borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Draws a 1px border along the diagonal cut line.
class _DiagonalShadowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x801A1C20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(0, size.height * 0.6),
      Offset(size.width, size.height * 0.25),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Clips the top portion diagonally: from ~60% on the left to ~25% on the right.

/// Clips the top portion diagonally: from ~60% on the left to ~25% on the right.
class _DiagonalTopClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, size.height * 0.6);
    path.lineTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height * 0.25);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

// ─── Capture Rate Panel ────────────────────────────────────────────────

class _CaptureRatePanel extends StatefulWidget {
  @override
  State<_CaptureRatePanel> createState() => _CaptureRatePanelState();
}

class _CaptureRatePanelState extends State<_CaptureRatePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PlayerProfileController>();
    final profile = ctrl.profile;
    final level = ctrl.trainerLevel;
    final xpInLevel = ctrl.trainerXpInLevel;
    final xpNext = ctrl.trainerXpForNextLevel;
    final isGirl = profile.gender == 'girl';
    final xpColor = isGirl ? const Color(0xFFF472B6) : const Color(0xFF4FC3F7);

    return SlideTransition(
      position: _slide,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF282A30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1A1C20), width: 1),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(profile.trainerName ?? profile.playerName,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'PowerGreen')),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC9A44C).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('Lv. $level', style: const TextStyle(color: Color(0xFFC9A44C), fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: xpNext > 0 ? xpInLevel / xpNext : 0,
                minHeight: 4,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(xpColor),
              ),
            ),
            const SizedBox(height: 2),
            Text('$xpInLevel / $xpNext XP',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
            const SizedBox(height: 10),
            _statRow('W - L - D', '${profile.wins} - ${profile.losses} - ${profile.draws}'),
            _statRow('Cards Owned', '${profile.ownedCardIds.length}'),
            _statRow('Decks', '${profile.decks.length}'),
            _statRow('PokeDollars', '₽ ${profile.money}'),
            if (profile.joinedAt != null) _statRow('Joined', profile.joinedAt!.substring(0, 10)),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _VolumeSlider extends StatefulWidget {
  const _VolumeSlider({required this.icon, required this.label, required this.initialValue, required this.onChanged});
  final IconData icon;
  final String label;
  final double initialValue;
  final ValueChanged<double> onChanged;

  @override
  State<_VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<_VolumeSlider> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(widget.icon, color: Colors.white54, size: 20),
          const SizedBox(width: 12),
          Text(widget.label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Expanded(
            child: Slider(
              value: _value,
              min: 0,
              max: 1,
              activeColor: const Color(0xFF4CAF50),
              inactiveColor: Colors.white24,
              thumbColor: Colors.white,
              onChanged: (v) {
                setState(() => _value = v);
                widget.onChanged(v);
              },
            ),
          ),
          SizedBox(
            width: 36,
            child: Text('${(_value * 100).round()}%', style: const TextStyle(color: Colors.white54, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

// ─── Shop Sprite Peek ──────────────────────────────────────────────────

class _ShopSpritePeek extends StatefulWidget {
  const _ShopSpritePeek();

  @override
  State<_ShopSpritePeek> createState() => _ShopSpritePeekState();
}

class _ShopSpritePeekState extends State<_ShopSpritePeek> with SingleTickerProviderStateMixin {
  String? _spritePath;
  List<String> _shopCardIds = [];
  int _spriteIndex = 0;
  String? _lastShopDate;
  bool _loading = false;
  late final AnimationController _ctrl;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _slide = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _checkForNewStock().then((_) => _schedule());
  }

  Future<void> _checkForNewStock() async {
    if (_loading) return;
    _loading = true;
    try {
      final client = context.read<ApiClient>();
      final result = await client.getDailyShop();
      final date = result['date'] as String;
      if (!mounted) { _loading = false; return; }
      if (_lastShopDate == date) { _loading = false; return; }
      _lastShopDate = date;
      final items = (result['items'] as List<dynamic>).cast<Map<String, dynamic>>();
      final newIds = items.map((i) => i['cardId'] as String).toList();
      if (!mounted) { _loading = false; return; }
      _shopCardIds = newIds;
      _spriteIndex = 0;
      _spritePath = null;
      if (mounted) _loading = false;
    } catch (e) {
      debugPrint('[ShopSpritePeek] failed to load shop singles: $e');
      if (mounted) _loading = false;
    }
  }

  void _schedule() {
    Future.delayed(Duration(seconds: 10 + DateTime.now().millisecond % 35), () async {
      if (!mounted) return;
      await _checkForNewStock();
      if (!mounted) return;
      if (_shopCardIds.isEmpty) { _schedule(); return; }
      _spriteIndex = (_spriteIndex + 1) % _shopCardIds.length;
      final id = _shopCardIds[_spriteIndex];
      final card = CardRepository.instance.cardById(id);
      if (card == null) { _schedule(); return; }
      setState(() => _spritePath = 'assets/sprites/front/${card.speciesId.toUpperCase()}.png');
      _ctrl.forward().then((_) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            _ctrl.reverse().then((_) {
              if (mounted) _schedule();
            });
          }
        });
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _checkForNewStock();
    if (_spritePath == null) return const SizedBox.shrink();
    return Positioned(
      top: 1,
      right: 4,
      child: AnimatedBuilder(
      animation: _slide,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, -65 * _slide.value),
          child: Opacity(
            opacity: _slide.value.clamp(0.0, 1.0),
            child: Image.asset(
              _spritePath!,
              width: 80,
              height: 80,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        );
      },
    ),
  );
  }
}

// ─── Shop New Badge ────────────────────────────────────────────────────

class _ShopNewBadge extends StatefulWidget {
  const _ShopNewBadge();

  @override
  State<_ShopNewBadge> createState() => _ShopNewBadgeState();
}

class _ShopNewBadgeState extends State<_ShopNewBadge> {
  bool _hasNew = false;
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final client = context.read<ApiClient>();
      final result = await client.getDailyShop();
      final date = result['date'] as String;
      final prefs = await SharedPreferences.getInstance();
      final lastSeen = prefs.getString('shop_last_seen_date');
      if (!mounted) return;
      if (lastSeen != date && !_hasNew) {
        setState(() => _hasNew = true);
      } else if (lastSeen == date && _hasNew) {
        setState(() => _hasNew = false);
      }
    } catch (_) {}
    if (mounted) _checking = false;
  }

  @override
  Widget build(BuildContext context) {
    _check();
    if (!_hasNew) return const SizedBox.shrink();
    return Positioned(
      top: -4,
      right: -4,
      child: Image.asset('assets/ui/new.png', width: 32, height: 32),
    );
  }
}

// ─── Shop Countdown Widget ────────────────────────────────────────────

class _ShopCountdown extends StatefulWidget {
  const _ShopCountdown();

  @override
  State<_ShopCountdown> createState() => _ShopCountdownState();
}

class _ShopCountdownState extends State<_ShopCountdown> {
  String _remaining = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _update());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _update() {
    if (!mounted) return;
    final now = DateTime.now();
    final reset = DateTime(now.year, now.month, now.day + 1);
    final diff = reset.difference(now);
    final h = diff.inHours;
    final m = diff.inMinutes.remainder(60);
    setState(() => _remaining = 'New Stock\n$h hours $m minutes');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0x60000000),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _remaining,
        style: const TextStyle(color: Color(0xFF959FB3), fontSize: 10, fontWeight: FontWeight.w700, height: 1.3),
        textAlign: TextAlign.center,
      ),
    );
  }
}
