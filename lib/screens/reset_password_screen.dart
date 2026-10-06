import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import 'authenticated_home_screen.dart';
import '../widgets/app_snackbar.dart';
import '../services/error_messages.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _password.text),
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthenticatedHomeScreen()),
        (_) => false,
      );
    } catch (error) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        friendlyError(error,
            fallback: 'ตั้งรหัสผ่านใหม่ไม่สำเร็จ กรุณาลองใหม่'),
        type: AppMessageType.error,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ตั้งรหัสผ่านใหม่')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(children: [
                  const Icon(Icons.lock_reset_rounded,
                      size: 76, color: AppColors.teal),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    validator: (value) => (value ?? '').length < 8
                        ? 'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร'
                        : null,
                    decoration: InputDecoration(
                      labelText: 'รหัสผ่านใหม่',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _confirmation,
                    obscureText: _obscure,
                    validator: (value) => value != _password.text
                        ? 'รหัสผ่านทั้งสองช่องไม่ตรงกัน'
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'ยืนยันรหัสผ่านใหม่',
                      prefixIcon: Icon(Icons.lock_reset_rounded),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _save,
                    child: Text(
                        _loading ? 'กำลังบันทึก...' : 'บันทึกรหัสผ่านใหม่'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}
