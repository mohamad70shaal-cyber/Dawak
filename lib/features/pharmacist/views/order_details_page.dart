import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/notice_banner.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/order.dart';
import '../controllers/pharmacist_order_details_controller.dart';
import '../widgets/order_widgets.dart';

Future<void> _call(String phone) async {
  try {
    final bool ok = await launchUrl(Uri(scheme: 'tel', path: phone));
    if (!ok) AppToast.error('p_order_call_failed'.tr);
  } catch (_) {
    AppToast.error('p_order_call_failed'.tr);
  }
}

/// Order details for the pharmacy (P-56) with the actions of the current state.
class PharmacistOrderDetailsPage extends StatelessWidget {
  const PharmacistOrderDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final String id = Get.parameters['id'] ?? '';
    final PharmacistOrderDetailsController c = Get.find<PharmacistOrderDetailsController>(tag: id);
    return Scaffold(
      appBar: AppBar(title: Text('p_order_details'.tr)),
      body: AsyncStateView.of(
        c,
        onRetry: c.refresh,
        builder: (BuildContext context) => RefreshIndicator(
          onRefresh: () => c.refresh(silent: true),
          child: Obx(() {
            final Order? o = c.order.value;
            if (o == null) return const SizedBox.shrink();
            return _Body(c: c, o: o);
          }),
        ),
      ),
      bottomNavigationBar: Obx(() {
        final Order? o = c.order.value;
        if (o == null) return const SizedBox.shrink();
        final Widget? bar = _actions(c);
        return bar == null ? const SizedBox.shrink() : BottomActionBar(child: bar);
      }),
    );
  }

  Widget? _actions(PharmacistOrderDetailsController c) {
    final bool busy = c.submitting.value;
    if (c.canAccept) {
      return Row(
        children: <Widget>[
          Expanded(child: AppButton(label: 'p_order_reject'.tr, variant: AppButtonVariant.danger, onPressed: busy ? null : c.reject)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: AppButton(label: 'p_order_accept'.tr, icon: Icons.thumb_up_alt_rounded, loading: busy, onPressed: c.accept)),
        ],
      );
    }
    if (c.canMarkReady) {
      return Row(
        children: <Widget>[
          Expanded(child: AppButton(label: 'p_order_cancel'.tr, variant: AppButtonVariant.danger, onPressed: busy ? null : c.cancel)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: AppButton(label: 'p_order_mark_ready'.tr, icon: Icons.shopping_bag_rounded, loading: busy, onPressed: c.markReady)),
        ],
      );
    }
    if (c.canHandover) {
      return Row(
        children: <Widget>[
          Expanded(child: AppButton(label: 'p_order_cancel'.tr, variant: AppButtonVariant.danger, onPressed: busy ? null : c.cancel)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: AppButton(label: 'p_order_handover'.tr, icon: Icons.handshake_rounded, onPressed: busy ? null : c.openHandover)),
        ],
      );
    }
    if (c.canReactivate) {
      return AppButton(label: 'p_order_reactivate'.tr, icon: Icons.restart_alt_rounded, loading: busy, onPressed: c.reactivate);
    }
    return null;
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.c, required this.o});

  final PharmacistOrderDetailsController c;
  final Order o;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final Duration? left = c.remaining;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Obx(() => c.notice.value == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(bottom: 12), child: NoticeBanner(c.notice.value!, kind: NoticeKind.warning))),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: LtrText(o.publicRef, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                  OrderStatusChip(o.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(Fmt.dateTime(o.createdAt), style: t.bodySmall?.copyWith(color: p.textSecondary)),
              const Divider(height: 24),
              if (o.customerName.isNotEmpty) InfoRow(label: 'p_order_customer'.tr, value: o.customerName),
              if ((o.contactPhone ?? '').isNotEmpty)
                Row(
                  children: <Widget>[
                    Expanded(child: InfoRow(label: 'p_order_phone'.tr, value: o.contactPhone!, ltr: true)),
                    IconButton(tooltip: 'call'.tr, onPressed: () => _call(o.contactPhone!), icon: const Icon(Icons.call_rounded)),
                  ],
                ),
              if ((o.customerNotes ?? '').isNotEmpty) InfoRow(label: 'p_order_notes'.tr, value: o.customerNotes!),
              if ((o.rejectReason ?? '').isNotEmpty) InfoRow(label: 'p_order_reject_reason_label'.tr, value: o.rejectReason!),
              if ((o.cancelReason ?? '').isNotEmpty)
                InfoRow(
                  label: o.cancelledByRole == 'customer' ? 'p_order_cancelled_by_customer'.tr : 'p_order_cancel_reason_label'.tr,
                  value: o.cancelReason!,
                ),
            ],
          ),
        ),
        if (left != null) ...<Widget>[
          const SizedBox(height: 12),
          SectionCard(
            title: 'p_order_reservation'.tr,
            icon: Icons.lock_clock_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('p_order_reservation_note'.tr, style: t.bodyMedium),
                const SizedBox(height: 8),
                InfoRow(label: 'p_order_reserved_until'.tr, value: Fmt.dateTime(o.reservationExpiresAt)),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: StatusChip(
                    label: left.isNegative ? 'p_order_time_over'.tr : 'p_order_time_left'.trParams(<String, String>{'t': remainingText(left)}),
                    color: left.isNegative ? AppColors.error : (left.inHours < 3 ? AppColors.warning : AppColors.primary),
                    icon: Icons.timer_outlined,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (o.status == OrderStatus.expired) ...<Widget>[
          const SizedBox(height: 12),
          NoticeBanner('p_order_expired_note'.tr, kind: NoticeKind.warning),
        ],
        const SizedBox(height: 12),
        SectionCard(
          title: 'p_order_items'.tr,
          icon: Icons.medication_rounded,
          child: Column(
            children: <Widget>[
              for (final OrderItem i in o.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(i.name, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                            if ((i.strength ?? '').isNotEmpty || (i.dosageForm ?? '').isNotEmpty)
                              Text(<String?>[i.strength, i.dosageForm].where((String? s) => (s ?? '').isNotEmpty).join(' · '), style: t.bodySmall?.copyWith(color: p.textSecondary)),
                            LtrText('${Fmt.money(i.unitPrice, o.currency)} × ${i.quantity}', style: t.bodySmall?.copyWith(color: p.textSecondary)),
                          ],
                        ),
                      ),
                      LtrText(Fmt.money(i.lineTotal, o.currency), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              const Divider(height: 20),
              InfoRow(label: 'p_receipt_grand_total'.tr, value: Fmt.money(o.subtotal, o.currency), ltr: true, bold: true),
              Text('p_pos_cash_note'.tr, style: t.bodySmall?.copyWith(color: p.textSecondary)),
            ],
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }
}
