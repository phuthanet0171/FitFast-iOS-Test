import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../widgets/brand_backdrop.dart';
import 'auth_screen.dart';
import 'authenticated_home_screen.dart';

/// Shown after signing up while the email address is not yet confirmed.
///
/// Opening the link on this phone signs the user in through the
/// `fitfast://login-callback` deep link, and this screen moves on by itself.
/// When the link was opened on another device there is no session here, so
/// the user signs in with the confirmed address instead.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, required this.email});

  final String email;

  /// Supabase allows one confirmation email about every 60 seconds.
  static const resendWait = Duration(seconds: 60);

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _cooldown;
  int _secondsLeft = VerifyEmailScreen.resendWait.inSeconds;
  bool _checking = false;
  bool _resending = false;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _startCooldown();
    try {
      _authSubscription =
          Supabase.instance.client.auth.onAuthStateChange.listen((state) {
        if (state.session?.user.emailConfirmedAt != null) _openHome();
      }, onError: (Object _, StackTrace __) {});
    } catch (_) {
      // Supabase is not available (e.g. in widget tests); buttons still work.
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _cooldown?.cancel();
    super.dispose();
  }

  /// Called from initState too, so the first value is set without setState.
  void _startCooldown() {
    _cooldown?.cancel();
    _secondsLeft = VerifyEmailScreen.resendWait.inSeconds;
    _cooldown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  void _openHome() {
    if (_opened || !mounted) return;
    _opened = true;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthenticatedHomeScreen()),
      (_) => false,
    );
  }

  void _openSignIn() => Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => EmailAuthScreen(
            registering: false,
            initialEmail: widget.email,
          ),
        ),
        (route) => route.isFirst,
      );

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final auth = Supabase.instance.client.auth;
      if (auth.currentSession == null) {
        // Confirmed on another device: sign in with the confirmed address.
        _openSignIn();
        return;
      }
      await auth.refreshSession();
      if (auth.currentUser?.emailConfirmedAt != null) {
        _openHome();
      } else {
        _show('ยังไม่พบการยืนยัน กรุณากดลิงก์ในอีเมลก่อน');
      }
    } catch (_) {
      _show('ตรวจสอบไม่สำเร็จ กรุณาตรวจอินเทอร์เน็ตแล้วลองอีกครั้ง');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: widget.email,
        emailRedirectTo: 'fitfast://login-callback',
      );
      _show('ส่งอีเมลยืนยันอีกครั้งแล้ว');
      _startCooldown();
    } on AuthException catch (error) {
      _show(error.message.toLowerCase().contains('rate limit') ||
              error.statusCode == '429'
          ? 'ส่งบ่อยเกินไป กรุณารอสักครู่แล้วลองใหม่'
          : error.message);
    } catch (_) {
      _show('ส่งอีเมลไม่สำเร็จ กรุณาตรวจอินเทอร์เน็ต');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final canResend = _secondsLeft <= 0 && !_resending;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: BrandBackdrop.middle,
        body: BrandBackdrop(
          arc: false,
          child: Column(children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 24, 22),
                child: Row(children: [
                  IconButton(
                    tooltip: 'ย้อนกลับ',
                    onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const AuthScreen()),
                      (_) => false,
                    ),
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'ยืนยันอีเมล',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ]),
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                      24, 32, 24, 24 + MediaQuery.paddingOf(context).bottom),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 88,
                              height: 88,
                              decoration: const BoxDecoration(
                                color: AppColors.mint,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.mark_email_unread_rounded,
                                  size: 44, color: AppColors.tealDark),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'เช็กอีเมลของคุณ',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.navy,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'เราส่งลิงก์ยืนยันไปที่',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.muted),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.email,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.tealDark,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'กดลิงก์ในอีเมลบนมือถือเครื่องนี้\n'
                            'แอปจะพาเข้าสู่ระบบให้อัตโนมัติ',
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: AppColors.navy, height: 1.5),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.amber.withValues(alpha: .14),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Row(children: [
                              Icon(Icons.lightbulb_outline_rounded,
                                  color: Color(0xFFB7791F), size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'ไม่เจออีเมล? ลองดูในโฟลเดอร์จดหมายขยะ (Spam)',
                                  style: TextStyle(
                                      color: AppColors.navy, fontSize: 13),
                                ),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 28),
                          FilledButton(
                            onPressed: _checking ? null : _check,
                            child: Text(_checking
                                ? 'กำลังตรวจสอบ...'
                                : 'ยืนยันอีเมลแล้ว'),
                          ),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: canResend ? _resend : null,
                            child: Text(_resending
                                ? 'กำลังส่ง...'
                                : _secondsLeft > 0
                                    ? 'ส่งอีเมลอีกครั้งได้ใน $_secondsLeft วินาที'
                                    : 'ส่งอีเมลยืนยันอีกครั้ง'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
