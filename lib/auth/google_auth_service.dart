import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

const String youtubeReadonlyScope =
    'https://www.googleapis.com/auth/youtube.readonly';
const String youtubeForceSslScope =
    'https://www.googleapis.com/auth/youtube.force-ssl';
const List<String> youtubeScopes = [
  youtubeReadonlyScope,
  youtubeForceSslScope,
];

// Web OAuth client ID (Google Cloud -> Credentials -> OAuth 2.0 Client IDs -> Web).
// Recommended to pass via --dart-define=GOOGLE_SERVER_CLIENT_ID=xxx
const String kServerClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
  // Local app: default to the web client ID in youtube-summarize/client_secret.json
  defaultValue:
      '295055986238-m1t516s6a77s1q0c0nl6ll0mu40dsc8a.apps.googleusercontent.com',
);

class GoogleAuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _initialized = false;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  bool get _isSupported => kIsWeb || _isAndroid || _isIOS;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    if (_isAndroid && kServerClientId.isEmpty) {
      throw StateError(
        'Missing serverClientId. Set --dart-define=GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID',
      );
    }
    await _googleSignIn.initialize(
      serverClientId: _isAndroid ? kServerClientId : null,
    );
    _initialized = true;
  }

  Future<GoogleSignInAccount> signIn() async {
    if (!_isSupported) {
      throw StateError(
        'Google Sign-In no está disponible en Windows. Usa Android.',
      );
    }
    await _ensureInitialized();
    return _googleSignIn.authenticate(
      scopeHint: youtubeScopes,
    );
  }

  Future<GoogleSignInAccount?> tryRestoreSignIn() async {
    if (!_isSupported) return null;
    await _ensureInitialized();
    final attempt = _googleSignIn.attemptLightweightAuthentication();
    if (attempt == null) {
      return null;
    }
    return attempt;
  }

  Future<String> getAccessToken(GoogleSignInAccount user) async {
    final client = user.authorizationClient;
    final existing = await client.authorizationForScopes(
      youtubeScopes,
    );
    if (existing != null) {
      return existing.accessToken;
    }
    final granted = await client.authorizeScopes(
      youtubeScopes,
    );
    return granted.accessToken;
  }

  Future<String?> getAccessTokenSilently(GoogleSignInAccount user) async {
    final client = user.authorizationClient;
    final existing = await client.authorizationForScopes(
      youtubeScopes,
    );
    return existing?.accessToken;
  }

  Future<void> signOut() async {
    if (!_isSupported) return;
    await _ensureInitialized();
    await _googleSignIn.signOut();
  }
}
