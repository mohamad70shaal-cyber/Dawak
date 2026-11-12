import '../../../core/widgets/dialogs.dart';

/// Confirmation prompt. Controllers take it as a constructor parameter so unit tests can answer without a dialog.
typedef AdminConfirmFn = Future<bool> Function({
  required String title,
  required String message,
  String? confirmLabel,
  bool destructive,
});

/// Asks for a free-text reason or note. Returns null when the admin dismissed the dialog.
typedef AdminReasonFn = Future<String?> Function({
  required String title,
  required String label,
  String? message,
  String? confirmLabel,
  int minLength,
  bool destructive,
});

Future<bool> adminConfirm({required String title, required String message, String? confirmLabel, bool destructive = false}) =>
    confirmDialog(title: title, message: message, confirmLabel: confirmLabel, destructive: destructive);

Future<String?> adminReason({
  required String title,
  required String label,
  String? message,
  String? confirmLabel,
  int minLength = 3,
  bool destructive = true,
}) =>
    reasonDialog(
      title: title,
      label: label,
      message: message,
      confirmLabel: confirmLabel,
      minLength: minLength,
      destructive: destructive,
    );
