import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ble/connection_manager.dart';
import '../ble/device_scanner.dart';
import '../core/app_error.dart';
import '../data/session_recorder.dart';
import '../settings/app_settings.dart';
import '../ui/screens/analysis_screen.dart';
import '../ui/screens/devices_screen.dart';
import '../ui/screens/home_screen.dart';
import '../ui/screens/live_screen.dart';
import '../ui/screens/logger_screen.dart';
import '../ui/theme.dart';
import '../ui/widgets/common.dart';
import '../ui/widgets/effects.dart';
import 'services.dart';

/// Selected tab, and session to open in the analysis tab.
class NavController extends ChangeNotifier {
  int index = 0;
  int? analysisSessionId;

  static const int devices = 1;
  static const int live = 2;
  static const int analysis = 3;
  static const int logger = 4;

  void go(int tab) {
    index = tab;
    notifyListeners();
  }

  void openAnalysis(int sessionId) {
    analysisSessionId = sessionId;
    go(analysis);
  }
}

class DinamixApp extends StatefulWidget {
  const DinamixApp({super.key, required this.services});

  final AppServices services;

  @override
  State<DinamixApp> createState() => _DinamixAppState();
}

class _DinamixAppState extends State<DinamixApp> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldMessengerState> _messenger = GlobalKey<ScaffoldMessengerState>();
  late final StreamSubscription<AppError> _errors;
  final NavController _nav = NavController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _errors = ErrorCenter.instance.errors.listen((error) {
      _messenger.currentState?.showSnackBar(SnackBar(content: Text(error.message)));
    });
    final recovered = widget.services.recoveredSessions;
    if (recovered > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _messenger.currentState?.showSnackBar(SnackBar(
          content: Text('$recovered sessione/i interrotta/e: dati recuperati nel Data Logger.'),
        ));
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final services = widget.services;
    final visible = state == AppLifecycleState.resumed;
    services.hub.setForeground(visible);
    // Nothing is left in memory if Android kills the process in background.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      services.recorder.flush();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _errors.cancel();
    _nav.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    return MultiProvider(
      providers: [
        Provider<AppServices>.value(value: services),
        ChangeNotifierProvider<AppSettings>.value(value: services.settings),
        ChangeNotifierProvider<ConnectionManager>.value(value: services.connection),
        ChangeNotifierProvider<DeviceScanner>.value(value: services.scanner),
        ChangeNotifierProvider<SessionRecorder>.value(value: services.recorder),
        ChangeNotifierProvider<NavController>.value(value: _nav),
      ],
      child: Consumer<AppSettings>(
        builder: (context, settings, _) => MaterialApp(
          title: 'DinamiX',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: _messenger,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: settings.themeMode,
          builder: (context, child) => Stack(
            fit: StackFit.expand,
            children: [
              const AuroraBackground(),
              if (child != null) child,
              const IntroOverlay(),
            ],
          ),
          home: const AppShell(),
        ),
      ),
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavController>();
    final simulation = context.select<AppSettings, bool>((s) => s.simulationMode);
    final phoneDemo = context.select<AppSettings, bool>((s) => s.phoneDemo);
    final banner = simulation || phoneDemo;
    return Scaffold(
      body: Column(
        children: [
          if (banner) SafeArea(bottom: false, child: SimulationBanner(phone: phoneDemo)),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: banner,
              child: TweenAnimationBuilder<double>(
                key: ValueKey(nav.index),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                child: IndexedStack(
                  index: nav.index,
                  children: const [
                    HomeScreen(),
                    DevicesScreen(),
                    LiveScreen(),
                    AnalysisScreen(),
                    LoggerScreen(),
                  ],
                ),
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(offset: Offset(0, 14 * (1 - value)), child: child),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: FloatingNavBar(index: nav.index, onSelect: nav.go),
    );
  }
}

/// Floating bar with a pill sliding under the selected tab.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({super.key, required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const List<(IconData, IconData, String)> _items = [
    (Icons.dashboard_outlined, Icons.dashboard_rounded, 'Home'),
    (Icons.bluetooth_searching_rounded, Icons.bluetooth_rounded, 'Sensori'),
    (Icons.show_chart_rounded, Icons.show_chart_rounded, 'Live'),
    (Icons.analytics_outlined, Icons.analytics_rounded, 'Analisi'),
    (Icons.radio_button_unchecked_rounded, Icons.radio_button_checked_rounded, 'Logger'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slot = constraints.maxWidth / _items.length;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeOutBack,
                  left: slot * index + 6,
                  top: 8,
                  bottom: 8,
                  width: slot - 12,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(17),
                      gradient: LinearGradient(colors: [
                        Palette.cyan.withValues(alpha: 0.26),
                        Palette.brand.withValues(alpha: 0.2),
                      ]),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: i == index,
                          label: _items[i].$3,
                          child: PressScale(
                            onTap: () => onSelect(i),
                            child: _NavItem(item: _items[i], selected: i == index),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.item, required this.selected});

  final (IconData, IconData, String) item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return ExcludeSemantics(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            scale: selected ? 1.12 : 1,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            child: Icon(selected ? item.$2 : item.$1, size: 23, color: color),
          ),
          const SizedBox(height: 3),
          Text(
            item.$3,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
