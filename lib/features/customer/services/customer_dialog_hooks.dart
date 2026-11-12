import '../../../core/widgets/dialogs.dart';

/// Confirmation prompt. Controllers take it as a constructor parameter so unit tests can answer without a dialog.
typedef CustomerConfirmFn = Future<bool> Function({
  required String title,
  required String message,
  String? confirmLabel,
  bool destructive,
});

Future<bool> defaultCustomerConfirm({required String title, required String message, String? confirmLabel, bool destructive = false}) =>
    confirmDialog(title: title, message: message, confirmLabel: confirmLabel, destructive: destructive);
