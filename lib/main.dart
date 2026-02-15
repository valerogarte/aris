import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth/google_auth_service.dart';
import 'screens/history_screen.dart';
import 'screens/login_screen.dart';
import 'screens/lists_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/search_screen.dart';
import 'screens/explore_screen.dart';
import 'screens/videos_screen.dart';
import 'services/ai_cost_tracker.dart';
import 'services/quota_tracker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ArisApp());
}

class ArisApp extends StatefulWidget {
  const ArisApp({super.key});

  @override
  State<ArisApp> createState() => _ArisAppState();
}

class _ArisAppState extends State<ArisApp> {
  final GoogleAuthService _authService = GoogleAuthService();
  GoogleSignInAccount? _user;
  String? _accessToken;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = await _refreshAccessToken(interactive: false);
      if (!mounted || token == null || token.isEmpty) return;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo restaurar la sesión.\n$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<String?> _refreshAccessToken({bool interactive = false}) async {
    try {
      final user = _user ?? await _authService.tryRestoreSignIn();
      if (user == null) return null;

      final silentToken = await _authService.getAccessTokenSilently(user);
      if (silentToken != null && silentToken.isNotEmpty) {
        if (silentToken != _accessToken) {
          setState(() {
            _user = user;
            _accessToken = silentToken;
          });
        }
        return silentToken;
      }

      if (!interactive) return null;

      final token = await _authService.getAccessToken(user);
      if (token.isEmpty) return null;
      setState(() {
        _user = user;
        _accessToken = token;
      });
      return token;
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleSignIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = await _authService.signIn();
      final token = await _authService.getAccessToken(user);

      if (!mounted) return;
      setState(() {
        _user = user;
        _accessToken = token;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo iniciar sesión.\n$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _handleSignOut() async {
    await _authService.signOut();
    if (!mounted) return;
    setState(() {
      _user = null;
      _accessToken = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ARIS',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F0F0F),
          foregroundColor: Colors.white,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFF0F0F0F),
          indicatorColor: Color(0xFF1F1F1F),
        ),
      ),
      home: (_user == null || _accessToken == null)
          ? LoginScreen(
              onSignIn: _handleSignIn,
              loading: _loading,
              error: _error,
            )
          : HomeScreen(
              accessToken: _accessToken!,
              onSignOut: _handleSignOut,
              onRefreshToken: _refreshAccessToken,
            ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.accessToken,
    required this.onSignOut,
    required this.onRefreshToken,
  });

  final String accessToken;
  final VoidCallback onSignOut;
  final Future<String?> Function({bool interactive}) onRefreshToken;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  late final QuotaTracker _quotaTracker;
  late final AiCostTracker _aiCostTracker;
  final ValueNotifier<int> _listsVersion = ValueNotifier<int>(0);
  final ValueNotifier<int> _tabIndexNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _quotaTracker = QuotaTracker(
      dailyLimit: kDefaultYouTubeDailyQuota,
    );
    _quotaTracker.load();
    _aiCostTracker = AiCostTracker();
    _aiCostTracker.load();
  }

  @override
  void dispose() {
    _quotaTracker.dispose();
    _aiCostTracker.dispose();
    _listsVersion.dispose();
    _tabIndexNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (
        title: 'Suscripciones',
        icon: Icons.subscriptions,
        body: VideosScreen(
          accessToken: widget.accessToken,
          quotaTracker: _quotaTracker,
          onRefreshToken: widget.onRefreshToken,
          listsVersion: _listsVersion,
          aiCostTracker: _aiCostTracker,
        ),
      ),
      (
        title: 'Explorar',
        icon: Icons.explore,
        body: ExploreScreen(
          listsVersion: _listsVersion,
        ),
      ),
      (
        title: 'Historial',
        icon: Icons.history,
        body: HistoryScreen(
          accessToken: widget.accessToken,
          quotaTracker: _quotaTracker,
          aiCostTracker: _aiCostTracker,
          tabIndexListenable: _tabIndexNotifier,
          tabIndex: 2,
        ),
      ),
      (
        title: 'Canales',
        icon: Icons.playlist_add_check,
        body: ListsScreen(
          accessToken: widget.accessToken,
          quotaTracker: _quotaTracker,
          onRefreshToken: widget.onRefreshToken,
          listsVersion: _listsVersion,
          onListsChanged: () {
            _listsVersion.value += 1;
          },
        ),
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: null,
        leadingWidth: 48,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Image.asset(
            'logo/aris.png',
            width: 24,
            height: 24,
            fit: BoxFit.contain,
          ),
        ),
        actions: [
          _AiCostChip(tracker: _aiCostTracker),
          _QuotaChip(tracker: _quotaTracker),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SearchScreen(
                    accessToken: widget.accessToken,
                    quotaTracker: _quotaTracker,
                    aiCostTracker: _aiCostTracker,
                    onRefreshToken: widget.onRefreshToken,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.search),
            tooltip: 'Buscar',
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(
                    onSignOut: widget.onSignOut,
                    onListsChanged: () {
                      _listsVersion.value += 1;
                    },
                    aiCostTracker: _aiCostTracker,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.account_circle),
            tooltip: 'Perfil',
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: tabs.map((tab) => tab.body).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
            _tabIndexNotifier.value = index;
          });
        },
        destinations: [
          for (final tab in tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              label: tab.title,
            ),
        ],
      ),
    );
  }
}

class _AiCostChip extends StatelessWidget {
  const _AiCostChip({required this.tracker});

  final AiCostTracker tracker;

  DateTime? _parseDateKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  String _formatDateLabel(String key) {
    final date = _parseDateKey(key);
    if (date == null) return key;
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final yyyy = date.year.toString().padLeft(4, '0');
    return '$dd/$mm/$yyyy';
  }

  void _showCostDetails(BuildContext context) {
    var selectedDateKey = tracker.currentDateKey;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return StatefulBuilder(
          builder: (context, setModalState) {
            final entries = tracker
                .breakdownFor(selectedDateKey)
                .entries
                .toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final total = tracker.totalFor(selectedDateKey);
            final hasData = tracker.hasDataFor(selectedDateKey);
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Coste IA',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          _formatDateLabel(selectedDateKey),
                          style: theme.textTheme.titleSmall,
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () async {
                            final initialDate =
                                _parseDateKey(selectedDateKey) ??
                                    DateTime.now();
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: initialDate,
                              firstDate: DateTime(2024, 1, 1),
                              lastDate: DateTime.now(),
                            );
                            if (picked == null) return;
                            final key = [
                              picked.year.toString().padLeft(4, '0'),
                              picked.month.toString().padLeft(2, '0'),
                              picked.day.toString().padLeft(2, '0'),
                            ].join('-');
                            setModalState(() {
                              selectedDateKey = key;
                            });
                          },
                          icon: const Icon(Icons.calendar_today),
                          label: const Text('Calendario'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _QuotaMetric(
                            label: 'Total',
                            value:
                                '${tracker.currencySymbol}${total.toStringAsFixed(2)}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Detalle por modelo',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (!hasData)
                      const Text('No hay consumo registrado en esta fecha.')
                    else
                      Column(
                        children: [
                          for (final entry in entries) ...[
                            Row(
                              children: [
                                Expanded(child: Text(entry.key)),
                                Text(
                                  '${tracker.currencySymbol}${(entry.value / 1000000.0).toStringAsFixed(2)}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            const Divider(height: 1),
                            const SizedBox(height: 6),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: tracker,
      builder: (context, _) {
        final label = tracker.isLoaded ? tracker.formattedTotal : '...';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Tooltip(
            message: 'Coste IA estimado hoy',
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: tracker.isLoaded ? () => _showCostDetails(context) : null,
              child: Chip(
                label: Text(label),
                avatar: const Icon(
                  Icons.smart_toy,
                  size: 18,
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QuotaChip extends StatelessWidget {
  const _QuotaChip({required this.tracker});

  final QuotaTracker tracker;

  String _labelForKey(String key) {
    switch (key) {
      case 'subscriptions.list':
        return 'Suscripciones';
      case 'channels.list':
        return 'Canales';
      case 'playlistItems.list':
        return 'Ultimo video por canal';
      case 'videos.list':
        return 'Detalles de vídeos';
      case 'captions.list':
        return 'Pistas de subtitulos';
      case 'captions.download':
        return 'Descarga de subtitulos';
      default:
        return key;
    }
  }

  String _resetInfo() {
    final nowUtc = DateTime.now().toUtc();
    final offsetHours = _pacificOffsetHours(nowUtc);
    final ptNow = nowUtc.add(Duration(hours: offsetHours));
    final nextMidnight = DateTime(
      ptNow.year,
      ptNow.month,
      ptNow.day,
    ).add(const Duration(days: 1));
    final remaining = nextMidnight.difference(ptNow);
    final remainingLabel = _formatRemaining(remaining);
    return 'Se restablece a medianoche, hora del Pacifico (PT). '
        'Faltan $remainingLabel.';
  }

  String _formatRemaining(Duration duration) {
    final totalMinutes = duration.inMinutes;
    if (totalMinutes <= 0) return '0 min';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) return '$minutes min';
    return '$hours h $minutes min';
  }

  int _pacificOffsetHours(DateTime utcNow) {
    final year = utcNow.year;
    final dstStartLocal = _nthWeekdayOfMonth(
      year,
      3,
      DateTime.sunday,
      2,
    ).add(const Duration(hours: 2));
    final dstStartUtc = dstStartLocal.add(const Duration(hours: 8));
    final dstEndLocal = _nthWeekdayOfMonth(
      year,
      11,
      DateTime.sunday,
      1,
    ).add(const Duration(hours: 2));
    final dstEndUtc = dstEndLocal.add(const Duration(hours: 7));
    final isDst =
        utcNow.isAfter(dstStartUtc) && utcNow.isBefore(dstEndUtc);
    return isDst ? -7 : -8;
  }

  DateTime _nthWeekdayOfMonth(
    int year,
    int month,
    int weekday,
    int nth,
  ) {
    final firstDay = DateTime(year, month, 1);
    final delta = (weekday - firstDay.weekday + 7) % 7;
    final firstWeekday = firstDay.add(Duration(days: delta));
    return firstWeekday.add(Duration(days: 7 * (nth - 1)));
  }

  void _showQuotaDetails(BuildContext context) {
    final entries = tracker.breakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Cuota de YouTube',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _QuotaMetric(
                        label: 'Usado',
                        value: tracker.used.toString(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _QuotaMetric(
                        label: 'Restante',
                        value: tracker.remaining.toString(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _QuotaMetric(
                        label: 'Limite',
                        value: tracker.dailyLimit.toString(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Detalle del consumo',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (entries.isEmpty)
                  const Text('Aun no hay consumo registrado hoy.')
                else
                  Column(
                    children: [
                      for (final entry in entries) ...[
                        Row(
                          children: [
                            Expanded(child: Text(_labelForKey(entry.key))),
                            Text(entry.value.toString()),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Divider(height: 1),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
                const SizedBox(height: 12),
                Text(
                  _resetInfo(),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'Estimacion local: 1 unidad por llamada a YouTube Data API.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: tracker,
      builder: (context, _) {
        final label = tracker.isLoaded ? tracker.remaining.toString() : '...';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Tooltip(
            message: 'Cuota estimada restante',
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: tracker.isLoaded ? () => _showQuotaDetails(context) : null,
              child: Chip(
                label: Text(label),
                avatar: const Icon(
                  Icons.data_usage,
                  size: 18,
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QuotaMetric extends StatelessWidget {
  const _QuotaMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
