import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'core/theme.dart';
import 'core/autofill_service.dart';
import 'core/services/notification_service.dart';
import 'core/workers/password_check_worker.dart';
import 'providers/auth_provider.dart';
import 'providers/vault_provider.dart';
import 'features/splash/splash_screen.dart';
import 'features/auth/setup_screen.dart';
import 'features/auth/unlock_screen.dart';
import 'features/vault/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: VoltTheme.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // ── Notifications & background work ────────────────────────────────────────
  await NotificationService.init();

  // Initialise WorkManager with the background callbackDispatcher.
  // This must be called before any task can be registered or run.
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  // If the user previously enabled password-age notifications, ensure the
  // periodic WorkManager task is (re-)registered.  WorkManager persists tasks
  // across reboots and app updates, but an explicit re-register on startup
  // guards against edge cases (e.g. WorkManager DB reset after force-stop).
  const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final notifEnabled = await _storage.read(key: kNotifEnabledKey);
  if (notifEnabled == 'true') {
    await PasswordCheckWorker.register();
  }
  // ── End notifications setup ────────────────────────────────────────────────

  runApp(const KmdVoltApp());
}

class KmdVoltApp extends StatelessWidget {
  const KmdVoltApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => VaultProvider()),
      ],
      child: MaterialApp(
        title: 'KMD Volt',
        debugShowCheckedModeBanner: false,
        theme: VoltTheme.theme,
        home: const AppRouter(),
      ),
    );
  }
}

class AppRouter extends StatefulWidget {
  const AppRouter({super.key});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> with WidgetsBindingObserver {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    context.read<AuthProvider>().initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final auth = context.read<AuthProvider>();
    final vault = context.read<VaultProvider>();

    if (state == AppLifecycleState.paused) {
      auth.onAppPaused();
      if (!auth.isAuthenticated) vault.clear();
    } else if (state == AppLifecycleState.resumed) {
      auth.onAppResumed();
      if (!auth.isAuthenticated) {
        vault.clear();
      } else {
        // Check for autofill save requests that arrived while the app was in
        // background (onNewIntent stores the data; we retrieve it here).
        AutofillService.checkPendingSave();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mostrar splash solo en el arranque inicial
    if (_showSplash) {
      return SplashScreen(
        onComplete: () => setState(() => _showSplash = false),
      );
    }

    final auth = context.watch<AuthProvider>();

    switch (auth.state) {
      case AuthState.initial:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case AuthState.needsSetup:
        return const SetupScreen();
      case AuthState.unauthenticated:
        return const UnlockScreen();
      case AuthState.authenticated:
        return const HomeScreen();
    }
  }
}
