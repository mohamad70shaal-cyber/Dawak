import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/theme/app_colors.dart';
import '../base/base_controller.dart';
import '../errors/app_failure.dart';
import 'app_button.dart';

/// Centered illustration + text (+ optional action) for "nothing here".
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.icon = Icons.inbox_rounded,
    this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String? title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return _CenteredMessage(
      icon: icon,
      iconColor: context.palette.primaryText,
      title: title ?? 'empty_title'.tr,
      message: message ?? 'empty_message'.tr,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}

/// Failure with a retry button. The wording comes from the failure code, never from raw server text.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.failure, this.onRetry});

  final AppFailure? failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final AppFailure f = failure ?? const AppFailure('unknown');
    return _CenteredMessage(
      icon: f.isNetwork ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
      iconColor: AppColors.error,
      title: 'error_title'.tr,
      message: failureText(f),
      actionLabel: onRetry == null ? null : 'retry'.tr,
      onAction: onRetry,
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: 56, color: iconColor),
                  const SizedBox(height: 16),
                  Text(title, style: t.titleMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(message, style: t.bodyMedium?.copyWith(color: context.palette.textSecondary), textAlign: TextAlign.center),
                  if (actionLabel != null && onAction != null) ...<Widget>[
                    const SizedBox(height: 20),
                    AppButton(label: actionLabel!, onPressed: onAction, expand: false, variant: AppButtonVariant.secondary),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders the four states of a loading screen from a controller's `status` / `failure`:
/// spinner, error with retry, empty message, or [builder] content. Read reactive values inside [builder].
class AsyncStateView extends StatelessWidget {
  const AsyncStateView({
    super.key,
    required this.status,
    required this.failure,
    required this.onRetry,
    required this.builder,
    this.empty,
  });

  /// Convenience for a [BaseController].
  AsyncStateView.of(
    BaseController c, {
    Key? key,
    required Widget Function(BuildContext) builder,
    Widget? empty,
    VoidCallback? onRetry,
  }) : this(key: key, status: c.status, failure: c.failure, onRetry: onRetry ?? () {}, builder: builder, empty: empty);

  final Rx<ViewStatus> status;
  final Rxn<AppFailure> failure;
  final VoidCallback onRetry;
  final Widget Function(BuildContext) builder;

  /// Shown for [ViewStatus.empty]; defaults to a generic [EmptyState].
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      switch (status.value) {
        case ViewStatus.loading:
          return const Center(child: CircularProgressIndicator());
        case ViewStatus.error:
          return ErrorState(failure: failure.value, onRetry: onRetry);
        case ViewStatus.empty:
          return empty ?? const EmptyState();
        case ViewStatus.ready:
          return builder(context);
      }
    });
  }
}
