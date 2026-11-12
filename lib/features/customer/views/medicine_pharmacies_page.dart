import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/medicine.dart';
import '../controllers/medicine_details_controller.dart';
import '../widgets/cart_actions.dart';
import '../widgets/customer_widgets.dart';
import '../widgets/location_notice.dart';
import '../widgets/pharmacy_answer_card.dart';

/// Pharmacies that say they have a medicine (C-14): nearest first when the position is known, each with its price, how
/// recently it confirmed, directions, a call button and "reserve". Below it: "ask the pharmacies nearby" for a live answer.
class MedicinePharmaciesPage extends StatefulWidget {
  const MedicinePharmaciesPage({super.key, required this.id});

  final String id;

  @override
  State<MedicinePharmaciesPage> createState() => _MedicinePharmaciesPageState();
}

class _MedicinePharmaciesPageState extends State<MedicinePharmaciesPage> {
  late final MedicineDetailsController c;

  @override
  void initState() {
    super.initState();
    final String targetId = widget.id.isNotEmpty ? widget.id : (Get.parameters['id'] ?? '');
    c = Get.isRegistered<MedicineDetailsController>(tag: targetId)
        ? Get.find<MedicineDetailsController>(tag: targetId)
        : Get.put<MedicineDetailsController>(MedicineDetailsController(targetId), tag: targetId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (c.medicine.value == null) c.reload();
        c.ensureOffers();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final String id = widget.id;
    final TextTheme t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('c_pharmacies_title'.tr)),
      body: PagedListView<MedicineOffer>(
        paged: c.offers,
        header: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Obx(() {
            final Medicine? m = c.medicine.value;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (m != null) Text(m.displayName(isArabicNow()), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                InlineNotice('c_availability_note'.tr),
                const SizedBox(height: 8),
                LocationNotice(
                  location: c.where,
                  located: c.located,
                  onUseLocation: c.useMyLocation,
                  sortedKey: 'c_sorted_nearest',
                  unlocatedKey: 'c_offers_unlocated',
                ),
                const SizedBox(height: 12),
                AppButton(
                  label: 'c_ask_nearby'.tr,
                  icon: Icons.radar_rounded,
                  variant: c.offers.items.isEmpty ? AppButtonVariant.primary : AppButtonVariant.secondary,
                  loading: c.starting,
                  onPressed: c.askNearby,
                ),
                const SizedBox(height: 4),
                Text('c_ask_nearby_hint'.tr, style: t.bodySmall?.copyWith(color: context.palette.textSecondary)),
              ],
            );
          }),
        ),
        empty: EmptyState(icon: Icons.local_pharmacy_outlined, title: 'c_no_pharmacies'.tr, message: 'c_no_pharmacies_hint'.tr),
        itemBuilder: (BuildContext context, MedicineOffer o) => PharmacyAnswerCard(
          pharmacy: o.pharmacy,
          price: o.price,
          currency: o.currency,
          freshness: o.freshness,
          confirmedAt: o.confirmedAt,
          onReserve: () => reserveOffer(c.cart, c.targetForOffer(o), c.lineForOffer(o)),
          onOpenPharmacy: () => Get.toNamed<dynamic>(
            Uri(path: AppRoutes.pharmacy(o.pharmacy.id), queryParameters: <String, String>{'medicineId': id}).toString(),
          ),
        ),
      ),
    );
  }
}
