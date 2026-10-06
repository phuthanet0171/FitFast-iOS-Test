import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'screens/auth_screen.dart';
import 'screens/authenticated_home_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/splash_screen.dart';
import 'services/timeout_http_client.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!AppConfig.isValid) {
    runApp(const _ConfigurationErrorApp());
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabasePublishableKey,
    httpClient: TimeoutHttpClient(),
  );
  runApp(const FitFastApp());
}

class _ConfigurationErrorApp extends StatelessWidget {
  const _ConfigurationErrorApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Text(
                'การตั้งค่า Supabase ไม่ถูกต้อง\n\n'
                'กรุณาตรวจสอบไฟล์ lib/config/app_config.dart',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FitFastApp extends StatefulWidget {
  const FitFastApp({super.key, this.listenToAuthChanges = true});

  final bool listenToAuthChanges;

  @override
  State<FitFastApp> createState() => _FitFastAppState();
}

class _FitFastAppState extends State<FitFastApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    if (!widget.listenToAuthChanges) return;
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        _navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ResetPasswordScreen()),
          (_) => false,
        );
      } else if (state.event == AuthChangeEvent.signedIn &&
          state.session?.user.appMetadata['provider'] == 'google') {
        _navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthenticatedHomeScreen()),
          (_) => false,
        );
      }
    }, onError: (Object _, StackTrace __) {
      // Session refresh can fail temporarily while the device is offline.
      // Keep the current screen and let the next request retry naturally.
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'FitFast',
      theme: AppTheme.light,
      // Thai labels for Flutter's own dialogs, pickers and the copy/paste
      // menu (ตกลง, ยกเลิก, วาง ...).
      locale: const Locale('th'),
      supportedLocales: const [Locale('th'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: widget.listenToAuthChanges
          ? const SplashScreen()
          : const AuthScreen(),
    );
  }
}
