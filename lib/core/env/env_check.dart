import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Verify required and optional environment variables and
/// print warnings or throw for missing required keys.
Future<void> verifyEnv() async {
  final requiredKeys = <String>['API_BASE_URL'];
  final optionalKeys = <String>[
    'AGORA_APP_ID',
    'GOOGLE_MAPS_API_KEY',
    'SENTRY_DSN',
  ];

  final missingRequired = requiredKeys
      .where((k) => (dotenv.env[k] ?? '').trim().isEmpty)
      .toList();
  final missingOptional = optionalKeys
      .where((k) => (dotenv.env[k] ?? '').trim().isEmpty)
      .toList();

  if (missingRequired.isNotEmpty) {
    final msg = 'Missing required .env keys: ${missingRequired.join(', ')}';
    // Fail-fast so developers notice immediately when a critical value is missing.
    throw Exception(msg);
  }

  if (missingOptional.isNotEmpty) {
    // Log a friendly warning to remind developers to fill optional integrations.
    // Using print here keeps it visible in debug/console output.
    print('Warning: Missing optional .env keys: ${missingOptional.join(', ')}');
  }
}
