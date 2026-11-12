import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/chips.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/paged_list_view.dart';
import '../../../core/widgets/search_field.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/enums.dart';
import '../../../data/models/pharmacy.dart';
import '../../../data/models/platform.dart';
import '../controllers/admin_pharmacies_controller.dart';
import '../widgets/admin_widgets.dart';

/// Pharmacies tab (A-03, A-06): applications waiting for review first, every other status one chip away.
class AdminPharmaciesTab extends StatelessWidget {
  const AdminPharmaciesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final AdminPharmaciesController c = Get.find<AdminPharmaciesController>();
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SearchField(hint: 'a_pharmacies_search_hint'.tr, onChanged: c.search, onSubmitted: c.search),
        ),
        FilterChipBar<PharmacyFilter>(
          values: PharmacyFilter.values,
          selected: c.filter,
          label: (PharmacyFilter f) => 'a_ph_filter_${f.name}'.tr,
          onSelected: c.setFilter,
        ),
        Expanded(
          child: PagedListView<PharmacyApplication>(
            paged: c.paged,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            empty: Obx(() => EmptyState(
                  icon: Icons.local_pharmacy_outlined,
                  title: 'a_pharmacies_empty'.tr,
                  message: 'a_pharmacies_empty_${c.filter.value.name}'.tr,
                )),
            itemBuilder: (BuildContext context, PharmacyApplication a) => _ApplicationTile(app: a, onTap: () => c.openDetails(a)),
          ),
        ),
      ],
    );
  }
}

class _ApplicationTile extends StatelessWidget {
  const _ApplicationTile({required this.app, required this.onTap});

  final PharmacyApplication app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    final Pharmacy ph = app.pharmacy;
    final String place = <String>[ph.neighborhood, ph.city].where((String s) => s.trim().isNotEmpty).join('، ');
    return Semantics(
      button: true,
      label: '${ph.name}, $place',
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: Text(ph.name, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                ApprovalChip(ph.status),
              ],
            ),
            if (place.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Icon(Icons.place_outlined, size: 16, color: p.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(child: Text(place, style: t.bodySmall?.copyWith(color: p.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                Icon(Icons.person_outline_rounded, size: 16, color: p.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    app.ownerName.isEmpty ? '—' : app.ownerName,
                    style: t.bodySmall?.copyWith(color: p.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                LtrText(Fmt.date(ph.submittedAt ?? ph.createdAt), style: t.labelSmall?.copyWith(color: p.textSecondary)),
              ],
            ),
            if (ph.status == ApprovalStatus.pending && ph.licensePath == null) ...<Widget>[
              const SizedBox(height: 6),
              StatusChip(label: 'a_ph_no_license'.tr, color: AppColors.warning, icon: Icons.warning_amber_rounded),
            ],
          ],
        ),
      ),
    );
  }
}
