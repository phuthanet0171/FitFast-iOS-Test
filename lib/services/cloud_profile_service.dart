import 'package:supabase_flutter/supabase_flutter.dart';

class CloudProfileService {
  CloudProfileService._();

  static final instance = CloudProfileService._();
  SupabaseClient get _client => Supabase.instance.client;

  Future<String?> loadUsername() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final row = await _client
        .from('profiles')
        .select('username')
        .eq('id', user.id)
        .maybeSingle();
    return row?['username'] as String?;
  }

  Future<void> saveUsername(String username) async {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('User is not signed in');
    await _client.from('profiles').upsert({
      'id': user.id,
      'username': username,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  /// The name shown on the profile. Google accounts bring their name in
  /// `full_name`; a name edited in the app is kept in `display_name`, which
  /// a later Google sign-in does not overwrite.
  static String? displayName(User? user) {
    final metadata = user?.userMetadata ?? const {};
    for (final key in ['display_name', 'full_name', 'name', 'username']) {
      final value = (metadata[key] as String?)?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static const maxDisplayNameLength = 40;

  Future<void> saveDisplayName(String name) async {
    await _client.auth
        .updateUser(UserAttributes(data: {'display_name': name.trim()}));
  }

  /// Makes sure the account has a username. Email sign-ups chose one;
  /// Google sign-ups get one made from their email address, e.g.
  /// "somchai.j". Usernames may be shared by several accounts.
  Future<void> syncUsernameFromMetadata() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final existing = await loadUsername();
    if (existing != null && existing.isNotEmpty) return;
    final chosen = (user.userMetadata?['username'] as String?)?.trim();
    final username = chosen != null && chosen.isNotEmpty
        ? chosen
        : usernameFromEmail(user.email);
    if (username == null) return;
    try {
      await saveUsername(username);
    } on PostgrestException {
      // Databases that still require unique usernames reject a taken name;
      // the profile then shows the display name or email instead.
    }
  }

  /// "Som.Chai+fit@gmail.com" becomes "som.chai"; null when too little of
  /// the address is usable (Thai letters, for example).
  static String? usernameFromEmail(String? email) {
    final local = (email ?? '').split('@').first.split('+').first;
    var name = local.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]'), '');
    if (name.length > 20) name = name.substring(0, 20);
    if (name.length < 3) return null;
    return name;
  }

  bool isDuplicateUsername(PostgrestException error) =>
      error.code == '23505' ||
      error.message.toLowerCase().contains('profiles_username_unique');
}
