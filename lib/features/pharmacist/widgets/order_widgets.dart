import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../data/models/order.dart';

/// "2 h 15 m" for a reservation countdown; "0 m" once it ran out.
String remainingText(Duration d) => Fmt.remaining(d, hoursUnit: 'unit_hours'.tr, minutesUnit: 'unit_minutes'.tr);

/// One order in a list (P-55): code, customer, status, total and, while the medicine is held for the customer, the time left.
class OrderTile extends StatelessWidget {
  const OrderTile({super.key, required this.order, required this.onTap, this.now});

  final Order order;
  final VoidCallback onTap;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final Duration? left = order.remaining(now: now);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        label: '${order.publicRef}, ${order.customerName}, ${order.status.labelKey.tr}',
        excludeSemantics: true,
        child: AppCard(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: LtrText(order.publicRef, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                  OrderStatusChip(order.status),
                ],
              ),
              const SizedBox(height: 6),
              if (order.customerName.isNotEmpty) Text(order.customerName, style: t.bodyMedium),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${'p_order_items_count'.trParams(<String, String>{'n': '${order.itemCount}'})} · ${Fmt.dateTime(order.createdAt)}',
                      style: t.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                  ),
                  LtrText(Fmt.money(order.subtotal, order.currency), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              if (left != null) ...<Widget>[
                const SizedBox(height: 8),
                StatusChip(
                  label: left.isNegative ? 'p_order_time_over'.tr : 'p_order_time_left'.trParams(<String, String>{'t': remainingText(left)}),
                  color: left.isNegative ? AppColors.error : (left.inHours < 3 ? AppColors.warning : AppColors.primary),
                  icon: Icons.timer_outlined,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
