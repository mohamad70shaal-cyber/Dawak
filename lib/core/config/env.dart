/// Build-time configuration, injected with `--dart-define` (see `.env.example`).
///
/// Only the public URL and the anon key ever reach the app. The service-role key must never be used here.
class Env {
  const Env._();

  static const String supabaseUrl = 'https://ifdvumqnwbpvxqlhdhln.supabase.co';
  static const String supabaseAnonKey =
      'sb_publishable_a6BiKjrQD-PEhMwJpjNQlQ_djowd6XJ';

  /// Whether the project requires e-mail confirmation (mirrors `[auth.email] enable_confirmations`).
  static const bool requireEmailConfirmation = bool.fromEnvironment(
      'AUTH_REQUIRE_EMAIL_CONFIRMATION',
      defaultValue: true);

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Support contact shown on the help screen (replace before release).
  static const String supportEmail = String.fromEnvironment('SUPPORT_EMAIL',
      defaultValue: 'support@dawak.app');
}
