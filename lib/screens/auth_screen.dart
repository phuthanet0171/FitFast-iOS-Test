import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/cloud_profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_backdrop.dart';
import '../widgets/fitfast_logo.dart';
import 'authenticated_home_screen.dart';
import 'verify_email_screen.dart';

/// The first screen for people who are not signed in: what FitFast does,
/// then sign up, sign in or continue with Google.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _googleLoading = false;

  Future<void> _continueWithGoogle() async {
    if (_googleLoading) return;
    setState(() => _googleLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'fitfast://login-callback',
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.message), backgroundColor: AppColors.orange),
      );
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  void _openEmail(bool registering) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EmailAuthScreen(registering: registering),
    ));
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: BrandBackdrop.middle,
          body: BrandBackdrop(
            arc: false,
            child: Column(children: [
              const Expanded(child: SafeArea(bottom: false, child: _Hero())),
              _BottomPanel(children: [
                const Text(
                  'เริ่มดูแลสุขภาพวันนี้',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.3,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'บันทึกอาหาร จับเวลา IF และติดตามน้ำหนักในแอปเดียว',
                  style: TextStyle(color: AppColors.muted, height: 1.4),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => _openEmail(true),
                  child: const Text('สมัครสมาชิก'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => _openEmail(false),
                  style: _outlinedStyle,
                  child: const Text('เข้าสู่ระบบ'),
                ),
                const _OrDivider(),
                OutlinedButton.icon(
                  onPressed: _googleLoading ? null : _continueWithGoogle,
                  style: _outlinedStyle.copyWith(
                    foregroundColor:
                        const WidgetStatePropertyAll(AppColors.navy),
                  ),
                  icon: _googleLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const _GoogleMark(),
                  label: Text(_googleLoading
                      ? 'กำลังเปิด...'
                      : 'ดำเนินการต่อด้วย Google'),
                ),
              ]),
            ]),
          ),
        ),
      );
}

final _outlinedStyle = OutlinedButton.styleFrom(
  minimumSize: const Size.fromHeight(54),
  foregroundColor: AppColors.tealDark,
  side: const BorderSide(color: AppColors.border, width: 1.2),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
);

/// The brand area: the full logo in a soft halo, with small tags that
/// preview what the app does.
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: 330,
              height: 310,
              child: Stack(alignment: Alignment.center, children: [
                const SizedBox(
                  width: 236,
                  height: 236,
                  child: CustomPaint(painter: _HaloPainter()),
                ),
                Container(
                  width: 170,
                  height: 170,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: .07),
                  ),
                ),
                const _FadeIn(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    FitFastLogo(size: 104, shadow: true),
                    SizedBox(height: 16),
                    Text(
                      'FitFast',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.8,
                      ),
                    ),
                    Text(
                      'กินดี อดเป็น สุขภาพดี',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ]),
                ),
                const Positioned(
                  top: 14,
                  left: 0,
                  child: _FloatingTag(
                    delay: Duration(milliseconds: 250),
                    icon: Icons.egg_alt_rounded,
                    color: AppColors.amber,
                    label: 'ไข่ดาว 2 ฟอง',
                  ),
                ),
                const Positioned(
                  top: 72,
                  right: 0,
                  child: _FloatingTag(
                    delay: Duration(milliseconds: 400),
                    icon: Icons.timer_rounded,
                    color: AppColors.teal,
                    label: 'IF 16:8',
                  ),
                ),
                const Positioned(
                  bottom: 0,
                  left: 12,
                  child: _FloatingTag(
                    delay: Duration(milliseconds: 550),
                    icon: Icons.local_fire_department_rounded,
                    color: AppColors.orange,
                    label: '1,450 kcal วันนี้',
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
}

/// A faint ring with a short orange arc, like a fasting timer that has
/// just started.
class _HaloPainter extends CustomPainter {
  const _HaloPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawCircle(
      rect.center,
      size.width / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: .16),
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * .28,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = AppColors.orange,
    );
  }

  @override
  bool shouldRepaint(_HaloPainter oldDelegate) => false;
}

class _FloatingTag extends StatelessWidget {
  const _FloatingTag({
    required this.icon,
    required this.color,
    required this.label,
    this.delay = Duration.zero,
  });

  final IconData icon;
  final Color color;
  final String label;
  final Duration delay;

  @override
  Widget build(BuildContext context) => _FadeIn(
        delay: delay,
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: Colors.white.withValues(alpha: .28)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}

/// The white sheet that holds the actions, rising over the brand colour.
class _BottomPanel extends StatelessWidget {
  const _BottomPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 28, 24, 16 + MediaQuery.paddingOf(context).bottom),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      );
}

/// Sign in or create an account with email and password.
class EmailAuthScreen extends StatefulWidget {
  const EmailAuthScreen({
    super.key,
    required this.registering,
    this.initialEmail,
  });

  final bool registering;

  /// Filled in when coming back from email verification.
  final String? initialEmail;

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _password = TextEditingController();
  final _passwordConfirmation = TextEditingController();
  late final bool _registering = widget.registering;
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _passwordConfirmation.dispose();
    super.dispose();
  }

  String? _emailError(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'กรุณากรอกอีเมล';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
      return 'รูปแบบอีเมลไม่ถูกต้อง';
    }
    return null;
  }

  String? _usernameError(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'กรุณากรอกชื่อผู้ใช้';
    if (text.length < 3 || text.length > 20) {
      return 'ชื่อผู้ใช้ต้องมี 3–20 ตัวอักษร';
    }
    if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(text)) {
      return 'ใช้ได้เฉพาะภาษาอังกฤษ ตัวเลข จุด ขีดล่าง และขีดกลาง';
    }
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate() || _loading) return;
    setState(() => _loading = true);
    try {
      final client = Supabase.instance.client;
      if (_registering) {
        if (client.auth.currentSession == null) {
          final response = await client.auth.signUp(
            email: _email.text.trim(),
            password: _password.text,
            emailRedirectTo: 'fitfast://login-callback',
            data: {'username': _username.text.trim()},
          );
          if (!mounted) return;
          if (response.session == null) {
            Navigator.of(context).pushReplacement(MaterialPageRoute(
              builder: (_) => VerifyEmailScreen(email: _email.text.trim()),
            ));
            return;
          }
        }
        await CloudProfileService.instance.saveUsername(_username.text.trim());
        await client.auth.updateUser(
          UserAttributes(data: {'username': _username.text.trim()}),
        );
      } else {
        await client.auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthenticatedHomeScreen()),
        (_) => false,
      );
    } on PostgrestException catch (error) {
      if (CloudProfileService.instance.isDuplicateUsername(error)) {
        _showError('ชื่อผู้ใช้นี้ถูกใช้แล้ว กรุณาเลือกชื่ออื่น');
      } else {
        _showError('บันทึกชื่อผู้ใช้ไม่สำเร็จ กรุณาลองใหม่');
      }
    } on AuthException catch (error) {
      if (!_registering &&
          error.message.toLowerCase().contains('email not confirmed')) {
        // Signed up but never opened the link: offer to send it again.
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VerifyEmailScreen(email: _email.text.trim()),
        ));
        return;
      }
      _showError(_friendly(error.message));
    } catch (_) {
      _showError('เชื่อมต่อระบบสมาชิกไม่สำเร็จ กรุณาตรวจอินเทอร์เน็ต');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendly(String message) {
    final value = message.toLowerCase();
    if (value.contains('invalid login credentials')) {
      return 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
    }
    if (value.contains('already registered')) {
      return 'อีเมลนี้สมัครสมาชิกแล้ว';
    }
    if (value.contains('email not confirmed')) {
      return 'กรุณายืนยันอีเมลก่อนเข้าสู่ระบบ';
    }
    // Supabase sends only a few confirmation emails per hour unless the
    // project has its own SMTP server.
    if (value.contains('email rate limit')) {
      return 'ระบบส่งอีเมลยืนยันครบจำนวนต่อชั่วโมงแล้ว กรุณารอประมาณ 1 ชั่วโมงแล้วลองใหม่';
    }
    if (value.contains('rate limit')) {
      return 'ลองหลายครั้งเกินไป กรุณารอสักครู่';
    }
    return message;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.orange),
    );
  }

  Future<void> _forgotPassword() async {
    final controller = TextEditingController(text: _email.text.trim());
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ลืมรหัสผ่าน'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('เราจะส่งลิงก์ตั้งรหัสผ่านใหม่ไปที่อีเมลของคุณ',
              style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            decoration: _fieldDecoration(
              label: 'อีเมล',
              icon: Icons.mail_outline_rounded,
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            child: const Text('ส่งลิงก์'),
          ),
        ],
      ),
    );
    // showDialog completes before its reverse transition has fully detached
    // the TextField, so defer disposal until that transition is complete.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    controller.dispose();
    if (result == null) return;
    if (_emailError(result) != null) {
      _showError('กรุณากรอกอีเมลให้ถูกต้อง');
      return;
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        result,
        redirectTo: 'fitfast://login-callback',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('ส่งลิงก์ตั้งรหัสผ่านใหม่แล้ว กรุณาตรวจอีเมล')),
      );
    } on AuthException catch (error) {
      _showError(_friendly(error.message));
    }
  }

  void _switchMode() => Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, animation, secondaryAnimation) =>
              EmailAuthScreen(registering: !_registering),
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );

  Widget _passwordToggle() => IconButton(
        tooltip: _obscure ? 'แสดงรหัสผ่าน' : 'ซ่อนรหัสผ่าน',
        onPressed: () => setState(() => _obscure = !_obscure),
        icon: Icon(_obscure
            ? Icons.visibility_outlined
            : Icons.visibility_off_outlined),
      );

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 14);
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
                padding: const EdgeInsets.fromLTRB(8, 4, 24, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      tooltip: 'ย้อนกลับ',
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 0, 0),
                      child: Row(children: [
                        const FitFastLogo(size: 52, shadow: true),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _registering
                                    ? 'สร้างบัญชีใหม่'
                                    : 'ยินดีต้อนรับกลับ',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _registering
                                    ? 'ใช้เวลาไม่ถึงนาที แล้วเริ่มได้เลย'
                                    : 'เข้าสู่ระบบเพื่อดูข้อมูลของคุณ',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ],
                ),
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
                      24, 30, 24, 24 + MediaQuery.paddingOf(context).bottom),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Form(
                        key: _formKey,
                        child: AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_registering) ...[
                                TextFormField(
                                  controller: _username,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.username],
                                  autocorrect: false,
                                  maxLength: 20,
                                  validator: _usernameError,
                                  decoration: _fieldDecoration(
                                    label: 'ชื่อผู้ใช้',
                                    hint: 'เช่น fitfast_user',
                                    icon: Icons.person_outline_rounded,
                                  ).copyWith(counterText: ''),
                                ),
                                gap,
                              ],
                              TextFormField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.email],
                                autocorrect: false,
                                validator: _emailError,
                                decoration: _fieldDecoration(
                                  label: 'อีเมล',
                                  hint: 'name@example.com',
                                  icon: Icons.mail_outline_rounded,
                                ),
                              ),
                              gap,
                              TextFormField(
                                controller: _password,
                                obscureText: _obscure,
                                textInputAction: _registering
                                    ? TextInputAction.next
                                    : TextInputAction.done,
                                autofillHints: [
                                  _registering
                                      ? AutofillHints.newPassword
                                      : AutofillHints.password,
                                ],
                                validator: (value) => (value ?? '').length < 8
                                    ? 'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร'
                                    : null,
                                onFieldSubmitted:
                                    _registering ? null : (_) => _submit(),
                                decoration: _fieldDecoration(
                                  label: 'รหัสผ่าน',
                                  helper: _registering
                                      ? 'อย่างน้อย 8 ตัวอักษร'
                                      : null,
                                  icon: Icons.lock_outline_rounded,
                                  suffix: _passwordToggle(),
                                ),
                              ),
                              if (_registering) ...[
                                gap,
                                TextFormField(
                                  controller: _passwordConfirmation,
                                  obscureText: _obscure,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [
                                    AutofillHints.newPassword
                                  ],
                                  validator: (value) => value != _password.text
                                      ? 'รหัสผ่านทั้งสองช่องไม่ตรงกัน'
                                      : null,
                                  onFieldSubmitted: (_) => _submit(),
                                  decoration: _fieldDecoration(
                                    label: 'ยืนยันรหัสผ่าน',
                                    icon: Icons.lock_reset_rounded,
                                  ),
                                ),
                                const SizedBox(height: 28),
                              ] else
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed:
                                        _loading ? null : _forgotPassword,
                                    child: const Text('ลืมรหัสผ่าน?'),
                                  ),
                                ),
                              if (!_registering) const SizedBox(height: 12),
                              FilledButton(
                                onPressed: _loading ? null : _submit,
                                child: _loading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(_registering
                                        ? 'สมัครสมาชิก'
                                        : 'เข้าสู่ระบบ'),
                              ),
                              const SizedBox(height: 18),
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    _registering
                                        ? 'มีบัญชีอยู่แล้ว?'
                                        : 'ยังไม่มีบัญชี?',
                                    style:
                                        const TextStyle(color: AppColors.muted),
                                  ),
                                  TextButton(
                                    onPressed: _loading ? null : _switchMode,
                                    child: Text(_registering
                                        ? 'เข้าสู่ระบบ'
                                        : 'สมัครสมาชิก'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
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

InputDecoration _fieldDecoration({
  required String label,
  required IconData icon,
  String? hint,
  String? helper,
  Widget? suffix,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    prefixIcon: Icon(icon, color: AppColors.muted),
    suffixIcon: suffix,
    filled: true,
    fillColor: AppColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: border(Colors.transparent),
    enabledBorder: border(Colors.transparent),
    focusedBorder: border(AppColors.teal, 1.6),
    errorBorder: border(AppColors.orange),
    focusedErrorBorder: border(AppColors.orange, 1.6),
  );
}

/// Content that fades and rises in once when the screen opens.
class _FadeIn extends StatelessWidget {
  const _FadeIn({required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 500) + delay,
        curve: Interval(
          delay.inMilliseconds / (500 + delay.inMilliseconds),
          1,
          curve: Curves.easeOutCubic,
        ),
        builder: (context, value, child) => Opacity(
          opacity: value,
          alwaysIncludeSemantics: true,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - value)),
            child: child,
          ),
        ),
        child: child,
      );
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [
          Expanded(child: Divider(color: AppColors.border)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('หรือ',
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ),
          Expanded(child: Divider(color: AppColors.border)),
        ]),
      );
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 20,
        height: 20,
        child: Center(
          child: Text('G',
              style: TextStyle(
                  color: Color(0xFF4285F4),
                  fontWeight: FontWeight.w900,
                  fontSize: 17)),
        ),
      );
}
