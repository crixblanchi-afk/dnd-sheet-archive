import 'package:http/http.dart' as http;

class DesktopGoogleAuthCanceled implements Exception {
  const DesktopGoogleAuthCanceled();
}

class DesktopGoogleAuthException implements Exception {
  const DesktopGoogleAuthException(this.message);

  final String message;
}

class DesktopGoogleAuth {
  DesktopGoogleAuth({
    required this.clientId,
    required this.clientSecret,
    required this.scopes,
  });

  final String clientId;
  final String clientSecret;
  final List<String> scopes;

  bool get isConfigured => false;
  bool get isConnected => false;

  Future<void> restore() async {}

  Future<http.Client> authenticatedClient() => throw UnsupportedError(
    'OAuth desktop non è disponibile su questa piattaforma.',
  );

  Future<void> signOut() async {}

  void dispose() {}
}
