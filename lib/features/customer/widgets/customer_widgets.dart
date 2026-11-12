import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../data/models/availability.dart';
import '../../../data/models/medicine.dart';
import '../../../data/models/order.dart';

/// True unless the app currently runs in English.
bool isArabicNow() => Get.locale?.languageCode != 'en';

/// Remaining reservation time as "2 h 15 m".
String remainingText(Duration d) =>
    Fmt.remaining(d, hoursUnit: 'unit_hours'.tr, minutesUnit: 'unit_minutes'.tr);

enum NoticeTone { info, warning, error, success }

/// Message with icon and text (state never depends on colour alone).
class InlineNotice extends StatelessWidget {
  const InlineNotice(this.message, {super.key, this.tone = NoticeTone.info, this.action});

  final String message;
  final NoticeTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final AppPalette p = context.palette;
    final (Color, IconData) s = switch (tone) {
      NoticeTone.info => (AppColors.primary, Icons.info_outline_rounded),
      NoticeTone.warning => (AppColors.warning, Icons.warning_amber_rounded),
      NoticeTone.error => (AppColors.error, Icons.error_outline_rounded),
      NoticeTone.success => (AppColors.success, Icons.check_circle_outline_rounded),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.tint(s.$1, alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: s.$1.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(s.$2, color: s.$1, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: p.text))),
            ],
          ),
          if (action != null) ...<Widget>[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A medicine in a list (search suggestions and results).
class MedicineTile extends StatelessWidget {
  const MedicineTile({super.key, required this.medicine, required this.onTap, this.showPharmacyCount = true});

  final Medicine medicine;
  final VoidCallback onTap;
  final bool showPharmacyCount;

  @override
  Widget build(BuildContext context) {
    final bool ar = isArabicNow();
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final String second = medicine.secondaryName(ar);
    final String spec = medicine.specLine;
    return Semantics(
      button: true,
      label: medicine.displayName(ar),
      child: AppCard(
        onTap: onTap,
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: p.softPrimary, borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.medication_rounded, color: p.primaryText),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(medicine.displayName(ar), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (second.isNotEmpty) Text(second, style: t.bodySmall?.copyWith(color: p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (spec.isNotEmpty) Text(spec, style: t.bodySmall?.copyWith(color: p.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (showPharmacyCount && medicine.pharmacyCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'c_in_pharmacies'.trParams(<String, String>{'n': '${medicine.pharmacyCount}'}),
                        style: t.labelMedium?.copyWith(color: p.primaryText, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: p.textSecondary, textDirection: TextDirection.ltr),
          ],
        ),
      ),
    );
  }
}

/// An order in a list: reference, status, pharmacy, total.
class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order, required this.onTap});

  final Order order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: LtrText(order.publicRef, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Flexible(child: OrderStatusChip(order.status)),
            ],
          ),
          const SizedBox(height: 6),
          Text(order.pharmacyName, style: t.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'c_items_count'.trParams(<String, String>{'n': '${order.itemCount}'}),
                  style: t.bodySmall?.copyWith(color: p.textSecondary),
                ),
              ),
              LtrText(Fmt.money(order.subtotal, order.currency), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 2),
          Text(Fmt.dateTime(order.createdAt), style: t.bodySmall?.copyWith(color: p.textSecondary)),
        ],
      ),
    );
  }
}

/// A request in a list ("ask nearby" history, open requests on the home tab): medicine, state, how many pharmacies said yes.
class RequestTile extends StatelessWidget {
  const RequestTile({super.key, required this.request, required this.onTap});

  final AvailabilityRequestSummary request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool ar = isArabicNow();
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final String spec = request.medicine.specLine;
    final String offers = request.offersCount > 0
        ? 'c_req_offers_count'.trParams(<String, String>{'n': '${request.offersCount}'})
        : (request.status.isOpen ? 'c_req_no_answer_yet'.tr : 'c_req_no_offers'.tr);
    return Semantics(
      button: true,
      label: request.medicine.displayName(ar),
      child: AppCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    request.medicine.displayName(ar),
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(child: RequestStatusChip(request.status)),
              ],
            ),
            if (spec.isNotEmpty) Text(spec, style: t.bodySmall?.copyWith(color: p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    offers,
                    style: t.bodyMedium?.copyWith(
                      color: request.offersCount > 0 ? p.primaryText : p.textSecondary,
                      fontWeight: request.offersCount > 0 ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
                Text(Fmt.ago(request.createdAt), style: t.bodySmall?.copyWith(color: p.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
