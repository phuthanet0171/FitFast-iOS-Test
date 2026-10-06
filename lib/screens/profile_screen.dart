import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/fasting_settings.dart';
import '../models/health_profile.dart';
import '../services/app_settings_service.dart';
import '../services/cloud_profile_service.dart';
import '../services/food_preference_service.dart';
import '../services/fasting_settings_service.dart';
import '../services/health_profile_service.dart';
import '../services/meal_history_service.dart';
import '../services/notification_service.dart';
import '../services/nutrition_history_service.dart';
import '../services/weight_history_service.dart';
import '../theme/app_theme.dart';
import 'auth_screen.dart';
import 'health_onboarding_screen.dart';
import '../widgets/app_snackbar.dart';
import '../services/error_messages.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.fastingSettings,
  });

  final FastingSettings? fastingSettings;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  HealthProfile? _profile;
  bool _notificationsEnabled = true;
  bool _loading = true;
  String? _accountUsername;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await HealthProfileService.instance.load();
    final notifications =
        await AppSettingsService.instance.notificationsEnabled();
    String? accountUsername;
    try {
      accountUsername = await CloudProfileService.instance.loadUsername();
    } catch (_) {
      // Offline: the profile still opens, without the account username.
    }
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _notificationsEnabled = notifications;
      _accountUsername = accountUsername;
      _loading = false;
    });
  }

  Future<void> _toggleNotifications(bool value) async {
    if (value) {
      final granted = await NotificationService.instance.requestPermission();
      if (!granted) {
        if (!mounted) return;
        showAppSnackBar(
          context,
          'FitFast ยังไม่ได้รับอนุญาตให้แจ้งเตือน '
          'เปิดได้ที่ ตั้งค่าเครื่อง > การแจ้งเตือน > FitFast',
          type: AppMessageType.warning,
          duration: const Duration(seconds: 5),
        );
        return;
      }
      await AppSettingsService.instance.setNotificationsEnabled(true);
      final settings = widget.fastingSettings;
      if (settings != null && settings.notificationsEnabled) {
        await NotificationService.instance.scheduleFastingReminders(settings);
      }
    } else {
      await AppSettingsService.instance.setNotificationsEnabled(false);
      await NotificationService.instance.cancelFastingReminders();
    }
    if (!mounted) return;
    setState(() => _notificationsEnabled = value);
  }

  void _editHealthData() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HealthOnboardingScreen()),
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ออกจากระบบ?'),
        content: const Text('ข้อมูลที่บันทึกอยู่ในเครื่องจะยังไม่ถูกลบ'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ออกจากระบบ'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // Reminders belong to this account's fasting plan; they are scheduled
    // again when someone signs in.
    try {
      await NotificationService.instance.cancelFastingReminders();
    } catch (_) {
      // Signing out must still work if the notification plugin fails.
    }
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  Future<void> _changePassword() async {
    final formKey = GlobalKey<FormState>();
    final currentPassword = TextEditingController();
    final password = TextEditingController();
    final confirmation = TextEditingController();
    bool obscure = true;
    final values = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('เปลี่ยนรหัสผ่าน'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: currentPassword,
                  obscureText: obscure,
                  autofocus: true,
                  validator: (value) => (value ?? '').isEmpty
                      ? 'กรุณากรอกรหัสผ่านปัจจุบัน'
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'รหัสผ่านปัจจุบัน',
                    prefixIcon: Icon(Icons.lock_person_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: password,
                  obscureText: obscure,
                  validator: (value) => (value ?? '').length < 8
                      ? 'ต้องมีอย่างน้อย 8 ตัวอักษร'
                      : null,
                  decoration: InputDecoration(
                    labelText: 'รหัสผ่านใหม่',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      onPressed: () => setDialogState(() => obscure = !obscure),
                      icon: Icon(obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmation,
                  obscureText: obscure,
                  validator: (value) => value != password.text
                      ? 'รหัสผ่านทั้งสองช่องไม่ตรงกัน'
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'ยืนยันรหัสผ่านใหม่',
                    prefixIcon: Icon(Icons.lock_reset_rounded),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(
                      dialogContext, [currentPassword.text, password.text]);
                }
              },
              child: const Text('เปลี่ยนรหัสผ่าน'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    currentPassword.dispose();
    password.dispose();
    confirmation.dispose();
    if (values == null) return;
    try {
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email == null) {
        throw const AuthException('user not found');
      }
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: values[0],
      );
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: values[1]),
      );
      if (!mounted) return;
      showAppSnackBar(context, 'เปลี่ยนรหัสผ่านเรียบร้อยแล้ว',
          type: AppMessageType.success);
    } catch (error) {
      if (!mounted) return;
      final wrongPassword = error is AuthException &&
          (error.code == 'invalid_credentials' ||
              error.message.toLowerCase().contains('invalid login'));
      showAppSnackBar(
        context,
        wrongPassword
            ? 'รหัสผ่านปัจจุบันไม่ถูกต้อง'
            : friendlyError(error,
                fallback: 'เปลี่ยนรหัสผ่านไม่สำเร็จ กรุณาลองใหม่'),
        type: AppMessageType.error,
      );
    }
  }

  /// Edited name, then the Google name, then the username or email.
  String get _profileName {
    final user = Supabase.instance.client.auth.currentUser;
    return CloudProfileService.displayName(user) ??
        _accountUsername ??
        user?.email ??
        'ผู้ใช้ FitFast';
  }

  Future<void> _editName() async {
    final current = _profileName;
    final controller = TextEditingController(text: current);
    String? errorText;
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('แก้ไขชื่อโปรไฟล์'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: CloudProfileService.maxDisplayNameLength,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'ชื่อที่แสดง',
              helperText: 'ใช้ภาษาไทยหรืออังกฤษได้',
              prefixIcon: const Icon(Icons.badge_outlined),
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () {
                final value =
                    controller.text.trim().replaceAll(RegExp(r'\s+'), ' ');
                if (value.isEmpty) {
                  setDialogState(() => errorText = 'กรุณากรอกชื่อ');
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    controller.dispose();
    if (name == null || name == current) return;
    try {
      await CloudProfileService.instance.saveDisplayName(name);
      if (!mounted) return;
      setState(() {});
      showAppSnackBar(context, 'บันทึกชื่อโปรไฟล์แล้ว',
          type: AppMessageType.success);
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        friendlyError(error, fallback: 'บันทึกชื่อไม่สำเร็จ กรุณาลองใหม่'),
        type: AppMessageType.error,
      );
    }
  }

  Future<void> _changeEmail() async {
    final currentEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    final controller = TextEditingController(text: currentEmail);
    String? errorText;
    final newEmail = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('เปลี่ยนอีเมล'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'อีเมลใหม่',
              prefixIcon: const Icon(Icons.email_outlined),
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim().toLowerCase();
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
                  setDialogState(() => errorText = 'รูปแบบอีเมลไม่ถูกต้อง');
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    controller.dispose();
    if (newEmail == null || newEmail == currentEmail.toLowerCase()) return;
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(email: newEmail),
        emailRedirectTo: 'fitfast://login-callback',
      );
      if (!mounted) return;
      setState(() {});
      showAppSnackBar(
        context,
        'ส่งลิงก์ยืนยันไปที่ $newEmail แล้ว '
        'กดลิงก์ในอีเมลเพื่อเปลี่ยนอีเมลให้เสร็จ',
        type: AppMessageType.success,
        duration: const Duration(seconds: 5),
      );
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        friendlyError(error, fallback: 'เปลี่ยนอีเมลไม่สำเร็จ กรุณาลองใหม่'),
        type: AppMessageType.error,
      );
    }
  }

  Future<void> _deleteAccount() async {
    final confirmation = TextEditingController();
    bool canDelete = false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded,
              color: AppColors.orange, size: 42),
          title: const Text('ลบบัญชีถาวร?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'บัญชีและข้อมูลสุขภาพทั้งหมดจะถูกลบและไม่สามารถกู้คืนได้',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmation,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'พิมพ์ DELETE เพื่อยืนยัน',
                  prefixIcon: Icon(Icons.delete_forever_outlined),
                ),
                onChanged: (value) => setDialogState(
                  () => canDelete = value.trim().toUpperCase() == 'DELETE',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed:
                  canDelete ? () => Navigator.pop(dialogContext, true) : null,
              style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
              child: const Text('ลบบัญชีถาวร'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));
    confirmation.dispose();
    if (confirmed != true) return;

    try {
      await Supabase.instance.client.functions.invoke('delete-account');
      await NotificationService.instance.cancelFastingReminders();
      await FastingSettingsService.instance.clear();
      await HealthProfileService.instance.clear();
      await WeightHistoryService.instance.clear();
      await MealHistoryService.instance.clear();
      await NutritionHistoryService.instance.clear();
      await FoodPreferenceService.instance.clear();
      await AppSettingsService.instance.clear();
      // The account no longer exists on the server, so only the session
      // saved on this device is removed.
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (_) => false,
      );
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        friendlyError(error,
            fallback: 'ลบบัญชีไม่สำเร็จ ข้อมูลของคุณยังอยู่ครบ กรุณาลองใหม่'),
        type: AppMessageType.error,
      );
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SettingsScreen(
          notificationsEnabled: _notificationsEnabled,
          profileName: () => _profileName,
          onEditName: _editName,
          onChangePassword: _changePassword,
          onChangeEmail: _changeEmail,
          onToggleNotifications: _toggleNotifications,
          onDeleteAccount: _deleteAccount,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SafeArea(child: Center(child: CircularProgressIndicator()));
    }
    final profile = _profile;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
          children: [
            Text('โปรไฟล์', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.teal, AppColors.tealDark],
                ),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Row(children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.person_rounded,
                      color: AppColors.tealDark, size: 36),
                ),
                const SizedBox(width: 16),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(_profileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900)),
                      if (_accountUsername != null &&
                          _accountUsername != _profileName)
                        Text('@$_accountUsername',
                            style: const TextStyle(
                                color: Color(0xFFD7F5ED), fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(
                          profile == null
                              ? 'ยังไม่ได้ตั้งค่าข้อมูลสุขภาพ'
                              : '${profile.age} ปี · ${profile.genderLabel} · ${profile.goalLabel}',
                          style: const TextStyle(
                              color: Color(0xFFD7F5ED), fontSize: 12)),
                    ])),
              ]),
            ),
            const SizedBox(height: 18),
            if (profile != null) ...[
              Text('ข้อมูลสุขภาพ',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Card(
                  child: Column(children: [
                _InfoTile(
                    icon: Icons.cake_outlined,
                    label: 'อายุ',
                    value: '${profile.age} ปี'),
                const Divider(height: 1, indent: 60),
                _InfoTile(
                    icon: Icons.person_outline_rounded,
                    label: 'เพศ',
                    value: profile.genderLabel),
                const Divider(height: 1, indent: 60),
                _InfoTile(
                    icon: Icons.flag_outlined,
                    label: 'เป้าหมาย',
                    value: profile.goalLabel),
                const Divider(height: 1, indent: 60),
                _InfoTile(
                    icon: Icons.height_rounded,
                    label: 'ส่วนสูง',
                    value: '${profile.height.round()} ซม.'),
                const Divider(height: 1, indent: 60),
                _InfoTile(
                    icon: Icons.monitor_weight_outlined,
                    label: 'น้ำหนักปัจจุบัน',
                    value: '${profile.currentWeight.toStringAsFixed(1)} กก.'),
                const Divider(height: 1, indent: 60),
                _InfoTile(
                    icon: Icons.track_changes_rounded,
                    label: 'น้ำหนักเป้าหมาย',
                    value: '${profile.targetWeight.toStringAsFixed(1)} กก.'),
                const Divider(height: 1, indent: 60),
                _InfoTile(
                    icon: Icons.directions_walk_rounded,
                    label: 'ระดับกิจกรรม',
                    value: profile.activityLabel),
              ])),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                  onPressed: _editHealthData,
                  icon: const Icon(Icons.tune_rounded),
                  label: const Text('แก้ไขข้อมูลและเป้าหมายสุขภาพ')),
              const SizedBox(height: 22),
            ],
            Card(
              child: ListTile(
                onTap: _openSettings,
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.mint,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.settings_outlined,
                      color: AppColors.tealDark),
                ),
                title: const Text('ตั้งค่า',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('บัญชี การแจ้งเตือน และข้อมูลแอป'),
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
                'ค่าที่แสดงเป็นการประมาณเพื่อการติดตามทั่วไป ไม่ใช่คำแนะนำทางการแพทย์',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 11)),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('ออกจากระบบ'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.orange,
                side: const BorderSide(color: AppColors.orange),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsScreen extends StatefulWidget {
  const _SettingsScreen({
    required this.notificationsEnabled,
    required this.profileName,
    required this.onEditName,
    required this.onChangePassword,
    required this.onChangeEmail,
    required this.onToggleNotifications,
    required this.onDeleteAccount,
  });

  final bool notificationsEnabled;

  /// Read again after editing so the tile shows the new name.
  final String Function() profileName;
  final Future<void> Function() onEditName;
  final Future<void> Function() onChangePassword;
  final Future<void> Function() onChangeEmail;
  final Future<void> Function(bool) onToggleNotifications;
  final Future<void> Function() onDeleteAccount;

  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen> {
  late bool _notificationsEnabled = widget.notificationsEnabled;
  bool _changingNotification = false;

  Future<void> _toggleNotification(bool value) async {
    if (_changingNotification) return;
    setState(() => _changingNotification = true);
    await widget.onToggleNotifications(value);
    if (!mounted) return;
    final actual = await AppSettingsService.instance.notificationsEnabled();
    setState(() {
      _notificationsEnabled = actual;
      _changingNotification = false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ตั้งค่า')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
            children: [
              Text('บัญชี', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Card(
                child: Column(
                  children: [
                    _SettingsTile(
                      icon: Icons.badge_outlined,
                      title: 'ชื่อโปรไฟล์',
                      subtitle: widget.profileName(),
                      onTap: () async {
                        await widget.onEditName();
                        if (mounted) setState(() {});
                      },
                    ),
                    const Divider(height: 1, indent: 62),
                    _SettingsTile(
                      icon: Icons.password_rounded,
                      title: 'เปลี่ยนรหัสผ่าน',
                      subtitle: 'ยืนยันรหัสเดิมก่อนตั้งรหัสใหม่',
                      onTap: widget.onChangePassword,
                    ),
                    const Divider(height: 1, indent: 62),
                    _SettingsTile(
                      icon: Icons.alternate_email_rounded,
                      title: 'เปลี่ยนอีเมล',
                      subtitle:
                          Supabase.instance.client.auth.currentUser?.email ??
                              'ยังไม่มีอีเมล',
                      onTap: widget.onChangeEmail,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Text('การใช้งาน', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _notificationsEnabled,
                      onChanged:
                          _changingNotification ? null : _toggleNotification,
                      secondary: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.mint,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(Icons.notifications_outlined,
                            color: AppColors.tealDark),
                      ),
                      title: const Text('อนุญาตการแจ้งเตือน',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle:
                          const Text('ควบคุมการแจ้งเตือนทั้งหมดของ FitFast'),
                    ),
                    const Divider(height: 1, indent: 62),
                    _SettingsTile(
                      icon: Icons.info_outline_rounded,
                      title: 'เกี่ยวกับ FitFast',
                      subtitle: 'เวอร์ชันและข้อมูลการใช้งาน',
                      onTap: () async => showAboutDialog(
                        context: context,
                        applicationName: 'FitFast',
                        applicationVersion: '0.1.0',
                        applicationLegalese:
                            'เครื่องมือช่วยติดตามสุขภาพทั่วไป ไม่ใช่คำวินิจฉัยทางการแพทย์',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Text('ความปลอดภัย',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Card(
                child: _SettingsTile(
                  icon: Icons.delete_forever_outlined,
                  title: 'ลบบัญชีถาวร',
                  subtitle: 'ลบบัญชีและข้อมูลทั้งหมดอย่างถาวร',
                  color: AppColors.orange,
                  onTap: widget.onDeleteAccount,
                ),
              ),
            ],
          ),
        ),
      );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color = AppColors.tealDark,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(title,
            style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      );
}

class _InfoTile extends StatelessWidget {
  const _InfoTile(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: AppColors.tealDark),
        title: Text(label),
        trailing:
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      );
}
