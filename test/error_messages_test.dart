import 'dart:async';
import 'dart:io';

import 'package:fitfast/services/error_messages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('sign-in and sign-up errors become plain Thai', () {
    expect(
        friendlyError(const AuthException('Invalid login credentials',
            code: 'invalid_credentials')),
        'อีเมลหรือรหัสผ่านไม่ถูกต้อง');
    expect(friendlyError(const AuthException('User already registered')),
        'อีเมลนี้สมัครสมาชิกแล้ว ลองเข้าสู่ระบบแทน');
    expect(friendlyError(const AuthException('Email not confirmed')),
        'กรุณายืนยันอีเมลก่อนเข้าสู่ระบบ');
    expect(friendlyError(const AuthException('email rate limit exceeded')),
        contains('1 ชั่วโมง'));
    expect(
        friendlyError(const AuthException(
            '{"code":"unexpected_failure","message":"Error sending confirmation email"}')),
        startsWith('ส่งอีเมลไม่สำเร็จ'));
    expect(
        friendlyError(const AuthException(
            'New password should be different from the old password.')),
        'รหัสผ่านใหม่ต้องไม่ซ้ำกับรหัสผ่านเดิม');
    expect(
        friendlyError(const AuthException(
            'Email link is invalid or has expired',
            code: 'otp_expired')),
        'ลิงก์หมดอายุแล้ว กรุณาขอลิงก์ใหม่');
  });

  test('no connection is explained the same way everywhere', () {
    expect(friendlyError(const SocketException('Failed host lookup')),
        offlineMessage);
    expect(friendlyError(TimeoutException('slow')), offlineMessage);
    expect(friendlyError(AuthRetryableFetchException()), offlineMessage);
  });

  test('unknown errors use the action-specific fallback, never raw text', () {
    expect(
        friendlyError(const AuthException('Something odd happened'),
            fallback: 'บันทึกไม่สำเร็จ'),
        'บันทึกไม่สำเร็จ');
    expect(friendlyError(StateError('boom')),
        'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง');
    expect(
        friendlyError(const PostgrestException(
            message: 'new row violates row-level security policy',
            code: '42501')),
        contains('ไม่มีสิทธิ์'));
  });
}
