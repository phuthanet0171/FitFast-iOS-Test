import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns any error into one short Thai sentence that says what happened and
/// what to do, instead of showing Supabase's English or JSON text.
///
/// [fallback] describes the action that failed, e.g. "บันทึกไม่สำเร็จ", and
/// is used when the error is not one of the known cases.
String friendlyError(
  Object error, {
  String fallback = 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง',
}) {
  if (isNetworkError(error)) return offlineMessage;
  if (error is AuthException) return _auth(error) ?? fallback;
  if (error is PostgrestException) return _database(error) ?? fallback;
  if (error is FunctionException) {
    return error.status >= 500
        ? 'ระบบขัดข้องชั่วคราว กรุณาลองใหม่ในอีกสักครู่'
        : fallback;
  }
  return fallback;
}

const offlineMessage =
    'ไม่มีการเชื่อมต่ออินเทอร์เน็ต กรุณาตรวจสอบสัญญาณแล้วลองใหม่';

bool isNetworkError(Object error) {
  if (error is SocketException ||
      error is TimeoutException ||
      error is HttpException ||
      error is AuthRetryableFetchException) {
    return true;
  }
  final text = error.toString().toLowerCase();
  return text.contains('clientexception') ||
      text.contains('failed host lookup') ||
      text.contains('connection refused') ||
      text.contains('connection closed') ||
      text.contains('network is unreachable');
}

String? _auth(AuthException error) {
  final code = (error.code ?? '').toLowerCase();
  final message = error.message.toLowerCase();
  bool has(String text) => code.contains(text) || message.contains(text);

  if (has('invalid_credentials') || has('invalid login credentials')) {
    return 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
  }
  if (has('user_already_exists') ||
      has('email_exists') ||
      has('already registered')) {
    return 'อีเมลนี้สมัครสมาชิกแล้ว ลองเข้าสู่ระบบแทน';
  }
  if (has('email_not_confirmed') || has('email not confirmed')) {
    return 'กรุณายืนยันอีเมลก่อนเข้าสู่ระบบ';
  }
  if (has('over_email_send_rate_limit') || has('email rate limit')) {
    return 'ส่งอีเมลครบจำนวนต่อชั่วโมงแล้ว กรุณารอประมาณ 1 ชั่วโมงแล้วลองใหม่';
  }
  if (has('error sending')) {
    return 'ส่งอีเมลไม่สำเร็จ ระบบอีเมลของแอปมีปัญหา กรุณาลองใหม่ภายหลัง';
  }
  if (has('rate_limit') || has('rate limit') || error.statusCode == '429') {
    return 'ลองบ่อยเกินไป กรุณารอสักครู่แล้วลองใหม่';
  }
  if (has('same_password') || has('should be different')) {
    return 'รหัสผ่านใหม่ต้องไม่ซ้ำกับรหัสผ่านเดิม';
  }
  if (has('weak_password') || has('password should be')) {
    return 'รหัสผ่านง่ายเกินไป ใช้อย่างน้อย 8 ตัวอักษร ผสมตัวอักษรและตัวเลข';
  }
  if (has('email_address_invalid') ||
      has('invalid email') ||
      has('unable to validate email')) {
    return 'รูปแบบอีเมลไม่ถูกต้อง';
  }
  if (has('otp_expired') || has('expired') || has('invalid or has expired')) {
    return 'ลิงก์หมดอายุแล้ว กรุณาขอลิงก์ใหม่';
  }
  if (has('session_not_found') ||
      has('session missing') ||
      has('refresh_token') ||
      has('jwt')) {
    return 'การเข้าสู่ระบบหมดอายุ กรุณาเข้าสู่ระบบใหม่';
  }
  if (has('user_not_found') || has('user not found')) {
    return 'ไม่พบบัญชีนี้ในระบบ';
  }
  if (has('signup_disabled') || has('signups not allowed')) {
    return 'ขณะนี้ปิดรับสมัครสมาชิกชั่วคราว';
  }
  if (has('provider') && has('not enabled')) {
    return 'ยังไม่เปิดให้เข้าสู่ระบบด้วยวิธีนี้';
  }
  return null;
}

String? _database(PostgrestException error) {
  final message = error.message.toLowerCase();
  if (error.code == '23505') return 'ข้อมูลนี้มีอยู่ในระบบแล้ว';
  if (error.code == '42501' || message.contains('row-level security')) {
    return 'ไม่มีสิทธิ์บันทึกข้อมูลนี้ กรุณาเข้าสู่ระบบใหม่';
  }
  if (error.code == 'PGRST301' || message.contains('jwt')) {
    return 'การเข้าสู่ระบบหมดอายุ กรุณาเข้าสู่ระบบใหม่';
  }
  return null;
}
