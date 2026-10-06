import 'package:fitfast/main.dart';
import 'package:fitfast/screens/auth_screen.dart';
import 'package:fitfast/screens/verify_email_screen.dart';
import 'package:fitfast/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FitFast dashboard smoke test', (tester) async {
    await tester.pumpWidget(const FitFastApp(listenToAuthChanges: false));

    expect(find.bySemanticsLabel('FitFast'), findsWidgets);
    expect(find.text('สมัครสมาชิก'), findsOneWidget);
    expect(find.text('เข้าสู่ระบบ'), findsWidgets);
  });

  testWidgets('authentication pages fit a small phone screen', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const AuthScreen()),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('สมัครสมาชิก'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const EmailAuthScreen(registering: true),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('ยืนยันรหัสผ่าน'), findsOneWidget);
  });

  testWidgets('email verification waits before offering a resend',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const VerifyEmailScreen(email: 'name@example.com'),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('name@example.com'), findsOneWidget);
    expect(find.text('ส่งอีเมลอีกครั้งได้ใน 60 วินาที'), findsOneWidget);

    await tester.pump(VerifyEmailScreen.resendWait);
    expect(find.text('ส่งอีเมลยืนยันอีกครั้ง'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
