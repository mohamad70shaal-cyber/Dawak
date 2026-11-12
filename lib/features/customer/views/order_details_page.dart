import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/order.dart';
import '../controllers/order_details_controller.dart';
import '../widgets/customer_launch.dart';
import '../widgets/customer_widgets.dart';

/// Order details (C-20).
class OrderDetailsPage extends StatelessWidget {
  const OrderDetailsPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final OrderDetailsController c = Get.find<OrderDetailsController>(tag: id);
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text('c_order_title'.tr)),
      body: AsyncStateView.of(
        c,
        onRetry: c.reload,
        builder: (BuildContext context) => RefreshIndicator(
          onRefresh: c.refreshSilently,
          child: Obx(() {
            final Order? o = c.order.value;
            if (o == null) return const SizedBox.shrink();
            final Duration? left = c.remaining;
            final String phone = (o.pharmacyPhone ?? '').trim();
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('c_order_ref'.tr, style: t.labelLarge?.copyWith(color: p.textSecondary)),
                      Row(
                        children: <Widget>[
                          Expanded(child: LtrText(o.publicRef, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                          IconButton(tooltip: 'copy'.tr, icon: const Icon(Icons.copy_rounded), onPressed: () => copyText(o.publicRef)),
                        ],
                      ),
                      OrderStatusChip(o.status),
                      const SizedBox(height: 8),
                      Text('c_hint_${o.status.wire}'.tr, style: t.bodyMedium?.copyWith(color: p.textSecondary)),
                    ],
                  ),
                ),
                if (left != null) ...<Widget>[
                  const SizedBox(height: 12),
                  InlineNotice(
                    left.isNegative ? 'c_reservation_ended'.tr : 'c_reservation_left'.trParams(<String, String>{'t': remainingText(left)}),
                    tone: left.isNegative ? NoticeTone.warning : NoticeTone.info,
                  ),
                ],
                if ((o.rejectReason ?? '').isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  InlineNotice('${'c_reject_reason'.tr}: ${o.rejectReason}', tone: NoticeTone.error),
                ],
                if (o.status == OrderStatus.cancelled) ...<Widget>[
                  const SizedBox(height: 12),
                  InlineNotice(
                    <String>[
                      o.cancelledByRole == 'pharmacy' ? 'c_cancelled_by_pharmacy'.tr : 'c_cancelled_by_you'.tr,
                      if ((o.cancelReason ?? '').isNotEmpty) '${'c_cancel_reason'.tr}: ${o.cancelReason}',
                    ].join('\n'),
                    tone: NoticeTone.warning,
                  ),
                ],
                const SizedBox(height: 12),
                SectionCard(
                  title: o.pharmacyName,
                  icon: Icons.local_pharmacy_rounded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if ((o.pharmacyAddress ?? '').isNotEmpty) InfoRow(label: 'c_address'.tr, value: o.pharmacyAddress!),
                      if (phone.isNotEmpty) InfoRow(label: 'c_phone'.tr, value: phone, ltr: true),
                      if (phone.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: AppButton(label: 'call'.tr, icon: Icons.call_rounded, variant: AppButtonVariant.secondary, onPressed: () => callPhone(phone)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  title: 'c_items'.tr,
                  icon: Icons.medication_rounded,
                  child: Column(
                    children: <Widget>[
                      for (final OrderItem i in o.items)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  '${<String>[i.name, if ((i.strength ?? '').isNotEmpty) i.strength!].join(' · ')} × ${i.quantity}',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              LtrText(Fmt.money(i.lineTotal, o.currency), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      const Divider(height: 24),
                      InfoRow(label: 'c_total'.tr, value: Fmt.money(o.subtotal, o.currency), ltr: true, bold: true),
                      InfoRow(label: 'c_placed_at'.tr, value: Fmt.dateTime(o.createdAt), ltr: true),
                      if ((o.contactPhone ?? '').isNotEmpty) InfoRow(label: 'c_contact_phone'.tr, value: o.contactPhone!, ltr: true),
                      if ((o.customerNotes ?? '').isNotEmpty) InfoRow(label: 'c_notes'.tr, value: o.customerNotes!),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                InlineNotice('c_cash_notice'.tr),
                const SizedBox(height: 16),
                AppButton(
                  label: 'c_track_order'.tr,
                  icon: Icons.timeline_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => Get.toNamed<dynamic>(AppRoutes.customerOrderTrack(id)),
                ),
                if (c.canCancel) ...<Widget>[
                  const SizedBox(height: 8),
                  AppButton(
                    label: 'c_cancel_order'.tr,
                    icon: Icons.cancel_outlined,
                    variant: AppButtonVariant.danger,
                    onPressed: () => Get.toNamed<dynamic>(AppRoutes.customerOrderCancelOf(id)),
                  ),
                ],
              ],
            );
          }),
        ),
      ),
    );
  }
}
