import 'package:fitfast/services/cloud_profile_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

User _user(Map<String, dynamic> metadata) => User(
      id: 'u1',
      appMetadata: const {},
      userMetadata: metadata,
      aud: 'authenticated',
      createdAt: '2026-10-01T00:00:00Z',
    );

void main() {
  test('Google accounts show their name, and an edited name wins', () {
    expect(
        CloudProfileService.displayName(
            _user({'full_name': 'Phuthanet S.', 'name': 'Phuthanet'})),
        'Phuthanet S.');
    expect(
        CloudProfileService.displayName(_user({
          'display_name': 'ภูธเนศ',
          'full_name': 'Phuthanet S.',
        })),
        'ภูธเนศ');
    expect(CloudProfileService.displayName(_user({'username': 'fit_user'})),
        'fit_user');
    expect(CloudProfileService.displayName(_user({'full_name': '  '})), isNull);
    expect(CloudProfileService.displayName(null), isNull);
  });

  test('a username is made from the email address for Google sign-ups', () {
    expect(CloudProfileService.usernameFromEmail('Som.Chai+fit@gmail.com'),
        'som.chai');
    expect(
        CloudProfileService.usernameFromEmail(
            'averyveryveryverylongname@gmail.com'),
        'averyveryveryverylon');
    expect(CloudProfileService.usernameFromEmail('ab@gmail.com'), isNull);
    expect(CloudProfileService.usernameFromEmail(null), isNull);
  });
}
