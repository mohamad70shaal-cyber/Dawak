import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../data/models/medicine.dart';

/// True unless the app currently runs in English.
bool isArabicNow() => Get.locale?.languageCode != 'en';

/// Name of a medicine in the current language, with the strength / form line below it.
class MedicineTitle extends StatelessWidget {
  const MedicineTitle(this.medicine, {super.key, this.big = false});

  final Medicine medicine;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final bool ar = isArabicNow();
    final String second = medicine.secondaryName(ar);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          medicine.displayName(ar),
          style: (big ? t.titleLarge : t.titleSmall)?.copyWith(fontWeight: FontWeight.w700),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (second.isNotEmpty) LtrOrPlain(second, style: t.bodySmall?.copyWith(color: p.textSecondary)),
        if (medicine.specLine.isNotEmpty) Text(medicine.specLine, style: t.bodySmall?.copyWith(color: p.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

/// Text shown as is (used for secondary names that may be Latin script inside an Arabic screen).
class LtrOrPlain extends StatelessWidget {
  const LtrOrPlain(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
}

/// A row of the pharmacy's list: name, price, and whether customers are told it is available (and how fresh that is).
/// Managers get a switch to flip availability without opening the row.
class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product, required this.currency, required this.onTap, this.onToggleAvailable});

  final PharmacyProduct product;
  final String currency;
  final VoidCallback onTap;

  /// Shown as a switch when given (owners and managers only).
  final ValueChanged<bool>? onToggleAvailable;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final bool available = product.isAvailable;
    final String state = available ? 'p_state_available'.tr : 'p_state_unavailable'.tr;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        label: '${product.medicine.displayName(isArabicNow())}, ${Fmt.money(product.price, currency)}, $state',
        excludeSemantics: true,
        child: AppCard(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: MedicineTitle(product.medicine)),
                  if (onToggleAvailable != null)
                    Switch(value: available, onChanged: onToggleAvailable),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  LtrText(Fmt.money(product.price, currency), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: <Widget>[
                        if (available)
                          FreshnessChip(product.freshness(), confirmedAt: product.confirmedAt)
                        else
                          StatusChip(label: 'p_state_unavailable'.tr, color: AppColors.textSecondary, icon: Icons.remove_circle_outline_rounded),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
