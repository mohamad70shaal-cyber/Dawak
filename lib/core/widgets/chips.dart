import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../app/theme/app_colors.dart';
import '../../data/models/enums.dart';
import '../utils/formatters.dart';

/// A small status label. Colour is only decoration: the text and the icon always carry the meaning.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color, required this.icon});

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.tint(color, alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: context.palette.text, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip(this.status, {super.key});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color, IconData) s = style(status);
    return StatusChip(label: status.labelKey.tr, color: s.$1, icon: s.$2);
  }

  static (Color, IconData) style(OrderStatus s) {
    switch (s) {
      case OrderStatus.pending:
        return (AppColors.warning, Icons.hourglass_top_rounded);
      case OrderStatus.accepted:
        return (AppColors.primary, Icons.thumb_up_alt_rounded);
      case OrderStatus.readyForPickup:
        return (AppColors.success, Icons.shopping_bag_rounded);
      case OrderStatus.completed:
        return (AppColors.success, Icons.task_alt_rounded);
      case OrderStatus.rejected:
        return (AppColors.error, Icons.cancel_rounded);
      case OrderStatus.cancelled:
        return (AppColors.textSecondary, Icons.block_rounded);
      case OrderStatus.expired:
        return (AppColors.warning, Icons.timer_off_rounded);
    }
  }
}

/// "Confirmed 3 days ago" / "Not confirmed for a while": how much the pharmacy's word can be trusted today.
class FreshnessChip extends StatelessWidget {
  const FreshnessChip(this.freshness, {super.key, this.confirmedAt});

  final Freshness freshness;

  /// When given, the chip says how long ago ("confirmed 3 days ago") instead of the generic label.
  final DateTime? confirmedAt;

  @override
  Widget build(BuildContext context) {
    final (Color, IconData) s = style(freshness);
    final DateTime? at = confirmedAt;
    final String label =
        at == null ? freshness.labelKey.tr : 'fresh_confirmed_at'.trParams(<String, String>{'when': Fmt.ago(at)});
    return StatusChip(label: label, color: s.$1, icon: s.$2);
  }

  static (Color, IconData) style(Freshness f) =>
      f == Freshness.recent ? (AppColors.success, Icons.check_circle_rounded) : (AppColors.warning, Icons.schedule_rounded);
}

/// Open / closed / expired state of an availability request.
class RequestStatusChip extends StatelessWidget {
  const RequestStatusChip(this.status, {super.key});

  final RequestStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color, IconData) s = style(status);
    return StatusChip(label: status.labelKey.tr, color: s.$1, icon: s.$2);
  }

  static (Color, IconData) style(RequestStatus s) {
    switch (s) {
      case RequestStatus.open:
        return (AppColors.primary, Icons.radar_rounded);
      case RequestStatus.closed:
        return (AppColors.textSecondary, Icons.block_rounded);
      case RequestStatus.expired:
        return (AppColors.warning, Icons.timer_off_rounded);
    }
  }
}

class ApprovalChip extends StatelessWidget {
  const ApprovalChip(this.status, {super.key});

  final ApprovalStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case ApprovalStatus.pending:
        return StatusChip(label: 'approval_pending'.tr, color: AppColors.warning, icon: Icons.hourglass_top_rounded);
      case ApprovalStatus.approved:
        return StatusChip(label: 'approval_approved'.tr, color: AppColors.success, icon: Icons.verified_rounded);
      case ApprovalStatus.rejected:
        return StatusChip(label: 'approval_rejected'.tr, color: AppColors.error, icon: Icons.cancel_rounded);
      case ApprovalStatus.suspended:
        return StatusChip(label: 'approval_suspended'.tr, color: AppColors.error, icon: Icons.pause_circle_rounded);
    }
  }
}
