import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/theme/app_colors.dart';
import 'app_text_field.dart';

/// Yes/no confirmation. Returns true only when the user confirmed. [destructive] colours the confirm button
/// red *and* the dialog always states the consequence in [message].
Future<bool> confirmDialog({
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final bool? r = await Get.dialog<bool>(
    AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        TextButton(onPressed: () => Get.back<bool>(result: false), child: Text(cancelLabel ?? 'cancel'.tr)),
        FilledButton(
          onPressed: () => Get.back<bool>(result: true),
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: AppColors.onPrimary) : null,
          child: Text(confirmLabel ?? 'confirm'.tr),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Asks for a free-text reason (reject, cancel, suspend). Returns the trimmed text, or null if dismissed.
/// [minLength] 0 makes the reason optional.
Future<String?> reasonDialog({
  required String title,
  required String label,
  String? message,
  String? confirmLabel,
  int minLength = 3,
  int maxLength = 300,
  bool destructive = true,
}) {
  return Get.dialog<String>(
    _ReasonDialog(
      title: title,
      label: label,
      message: message,
      confirmLabel: confirmLabel ?? 'confirm'.tr,
      minLength: minLength,
      maxLength: maxLength,
      destructive: destructive,
    ),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.label,
    required this.message,
    required this.confirmLabel,
    required this.minLength,
    required this.maxLength,
    required this.destructive,
  });

  final String title;
  final String label;
  final String? message;
  final String confirmLabel;
  final int minLength;
  final int maxLength;
  final bool destructive;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String? _validate(String? v) {
    final String s = (v ?? '').trim();
    if (s.isEmpty && widget.minLength > 0) return 'val_required'.tr;
    if (s.length < widget.minLength) return 'val_too_short'.trParams(<String, String>{'n': '${widget.minLength}'});
    if (s.length > widget.maxLength) return 'val_too_long'.trParams(<String, String>{'n': '${widget.maxLength}'});
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (widget.message != null) ...<Widget>[Text(widget.message!), const SizedBox(height: 12)],
            AppTextField(
              label: widget.label,
              controller: _c,
              maxLines: 3,
              minLines: 2,
              maxLength: widget.maxLength,
              autofocus: true,
              validator: _validate,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Get.back<String>(), child: Text('cancel'.tr)),
        FilledButton(
          style: widget.destructive ? FilledButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: AppColors.onPrimary) : null,
          onPressed: () {
            if (_form.currentState?.validate() ?? false) Get.back<String>(result: _c.text.trim());
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Bottom sheet with a list of choices; returns the picked value or null.
Future<T?> choiceSheet<T>({
  required String title,
  required List<({T value, String label, IconData? icon})> options,
  T? selected,
}) {
  return Get.bottomSheet<T>(
    SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(title, style: Theme.of(Get.context!).textTheme.titleMedium),
          ),
          for (final ({T value, String label, IconData? icon}) o in options)
            ListTile(
              leading: o.icon == null ? null : Icon(o.icon),
              title: Text(o.label),
              trailing: o.value == selected ? const Icon(Icons.check_rounded) : null,
              onTap: () => Get.back<T>(result: o.value),
            ),
        ],
      ),
    ),
    backgroundColor: Theme.of(Get.context!).colorScheme.surface,
    isScrollControlled: true,
  );
}
