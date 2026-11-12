import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/pharmacy.dart';
import '../controllers/pharmacy_details_controller.dart';
import '../widgets/customer_launch.dart';
import '../widgets/customer_widgets.dart';

/// Pharmacy contact and opening hours (C-16).
class PharmacyContactPage extends StatelessWidget {
  const PharmacyContactPage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final PharmacyDetailsController c = Get.find<PharmacyDetailsController>(tag: id);
    return Scaffold(
      appBar: AppBar(title: Text('c_pharmacy_contact'.tr)),
      body: AsyncStateView.of(
        c,
        onRetry: c.reload,
        builder: (BuildContext context) {
          final PublicPharmacy? ph = c.pharmacy.value;
          if (ph == null) return const SizedBox.shrink();
          final String phone = (ph.phone ?? '').trim();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              SectionCard(
                title: ph.name,
                icon: Icons.local_pharmacy_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    InfoRow(label: 'c_address'.tr, value: ph.fullAddress),
                    if (ph.directions.trim().isNotEmpty) InfoRow(label: 'c_directions'.tr, value: ph.directions),
                    if (phone.isNotEmpty) InfoRow(label: 'c_phone'.tr, value: phone, ltr: true),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (phone.isNotEmpty)
                AppButton(label: 'call'.tr, icon: Icons.call_rounded, onPressed: () => callPhone(phone))
              else
                InlineNotice('c_phone_hidden'.tr),
              const SizedBox(height: 8),
              if (ph.location != null) ...<Widget>[
                AppButton(
                  label: 'c_directions_btn'.tr,
                  icon: Icons.directions_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => openDirections(ph.location!),
                ),
                const SizedBox(height: 8),
              ],
              if (ph.fullAddress.isNotEmpty)
                AppButton(label: 'c_copy_address'.tr, icon: Icons.copy_rounded, variant: AppButtonVariant.secondary, onPressed: () => copyText(ph.fullAddress)),
              if (ph.hours != null) ...<Widget>[
                const SizedBox(height: 16),
                SectionCard(
                  title: 'c_hours'.tr,
                  icon: Icons.schedule_rounded,
                  child: Column(
                    children: <Widget>[
                      for (final DayHours d in ph.hours!.days)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: <Widget>[
                              Expanded(child: Text('c_day_${d.day}'.tr)),
                              if (d.open) LtrText('${d.from} - ${d.to}') else Text('c_closed'.tr),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
