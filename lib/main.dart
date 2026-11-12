import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/bindings/dependencies.dart';
import 'core/config/env.dart';
import 'data/datasources/supabase_api_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.isConfigured) {
    runApp(const _ConfigErrorApp());
    return;
  }

  await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey);
  final SupabaseClient client = Supabase.instance.client;
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  registerCoreDependencies(
    api: SupabaseApiClient(client),
    auth: SupabaseAuthGateway(client),
    files: SupabaseFileStore(client),
    prefs: prefs,
  );

  runApp(const DawakApp());
}

/// Developer-facing screen shown when the app was built without `--dart-define=SUPABASE_URL/SUPABASE_ANON_KEY`.
/// Deliberately bilingual and independent of the translation system (which is not set up yet at this point).
class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Missing configuration: run with --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...\n'
                'إعدادات ناقصة: شغّل التطبيق مع تحديد SUPABASE_URL و SUPABASE_ANON_KEY.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
