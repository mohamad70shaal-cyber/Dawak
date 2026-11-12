import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/states.dart';
import '../controllers/order_details_controller.dart';

/// Order status tracking (C-22): a timeline built from the order's timestamps.
class OrderTrackingPage extends StatelessWidget {
  const OrderTrackingPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final OrderDetailsController c = Get.find<OrderDetailsController>(tag: id);
    return Scaffold(
      appBar: AppBar(title: Text('c_track_title'.tr)),
      body: AsyncStateView.of(
        c,
        onRetry: c.reload,
        builder: (BuildContext context) => RefreshIndicator(
          onRefresh: c.refreshSilently,
          child: Obx(() {
            final List<TrackStep> steps = c.timeline;
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              itemCount: steps.length,
              itemBuilder: (BuildContext context, int i) => _StepRow(step: steps[i], isLast: i == steps.length - 1),
            );
          }),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.isLast});

  final TrackStep step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final Color color = step.negative ? AppColors.error : (step.done ? AppColors.success : p.border);
    final IconData icon = step.negative ? Icons.cancel_rounded : (step.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded);
    return Semantics(
      label: '${step.labelKey.tr}${step.done ? '' : ' (${'c_track_pending'.tr})'}',
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: 32,
              child: Column(
                children: <Widget>[
                  Icon(icon, color: color, size: 28),
                  if (!isLast) Expanded(child: Container(width: 2, color: p.border)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      step.labelKey.tr,
                      style: t.titleSmall?.copyWith(
                        fontWeight: step.current ? FontWeight.w800 : FontWeight.w600,
                        color: step.done ? p.text : p.textSecondary,
                      ),
                    ),
                    if (step.time != null) LtrText(Fmt.dateTime(step.time), style: t.bodySmall?.copyWith(color: p.textSecondary)),
                    if (step.time == null) Text('c_track_pending'.tr, style: t.bodySmall?.copyWith(color: p.textSecondary)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
