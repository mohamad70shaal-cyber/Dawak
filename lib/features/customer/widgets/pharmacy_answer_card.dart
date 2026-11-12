import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/pharmacy.dart';
import 'customer_launch.dart';

/// A pharmacy that says it has the medicine: name, price, how far it is, how recently it said so, and the three things a
/// customer does next — get directions, call, reserve. Used on the "pharmacies with this medicine" screen and on the
/// answers of an "ask nearby" request.
///
/// The pharmacy's word is all there is (no stock is counted), so the card always says when it was given: either
/// [confirmedAt] with its [freshness] (a pharmacy's list) or [answeredAt] (a live answer to a request).
class PharmacyAnswerCard extends StatelessWidget {
  const PharmacyAnswerCard({
    super.key,
    required this.pharmacy,
    required this.price,
    required this.currency,
    this.freshness,
    this.confirmedAt,
    this.answeredAt,
    this.onReserve,
    this.onOpenPharmacy,
  });

  final PublicPharmacy pharmacy;
  final double price;
  final String currency;

  /// A pharmacy's list entry: [freshness] and, when known, [confirmedAt] ("confirmed 3 days ago").
  final Freshness? freshness;
  final DateTime? confirmedAt;

  /// A live answer to a request: "answered 2 minutes ago".
  final DateTime? answeredAt;

  /// Null hides the reserve button (for example when the pharmacy's list row no longer exists).
  final VoidCallback? onReserve;

  /// Tapping the name opens the pharmacy's page.
  final VoidCallback? onOpenPharmacy;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final String distance = Fmt.distance(pharmacy.distanceKm);
    final String phone = (pharmacy.phone ?? '').trim();
    final bool canDirect = pharmacy.location != null;
    return AppCard(
      onTap: onOpenPharmacy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(pharmacy.name, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              LtrText(Fmt.money(price, currency), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          if (distance.isNotEmpty || pharmacy.fullAddress.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (distance.isNotEmpty) ...<Widget>[
                    Icon(Icons.near_me_rounded, size: 16, color: p.primaryText),
                    const SizedBox(width: 4),
                    Text(distance, style: t.labelLarge?.copyWith(color: p.primaryText, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      pharmacy.fullAddress,
                      style: t.bodySmall?.copyWith(color: p.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          if (answeredAt != null)
            StatusChip(
              label: 'c_answered_ago'.trParams(<String, String>{'when': Fmt.ago(answeredAt)}),
              color: AppColors.success,
              icon: Icons.check_circle_rounded,
            )
          else if (freshness != null)
            FreshnessChip(freshness!, confirmedAt: confirmedAt),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (canDirect)
                AppButton(
                  label: 'c_directions_btn'.tr,
                  icon: Icons.directions_rounded,
                  variant: AppButtonVariant.secondary,
                  expand: false,
                  onPressed: () => openDirections(pharmacy.location!),
                ),
              if (phone.isNotEmpty)
                AppButton(
                  label: 'call'.tr,
                  icon: Icons.call_rounded,
                  variant: AppButtonVariant.secondary,
                  expand: false,
                  onPressed: () => callPhone(phone),
                ),
              if (onReserve != null)
                AppButton(
                  label: 'c_reserve'.tr,
                  icon: Icons.bookmark_add_rounded,
                  expand: false,
                  onPressed: onReserve,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
