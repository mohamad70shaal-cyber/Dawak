import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/search_field.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/medicine.dart';
import '../controllers/medicine_search_controller.dart';
import '../widgets/customer_widgets.dart';
import '../widgets/search_filter_widgets.dart';

/// Search tab: search box with live suggestions; "show all" opens the paged results. Tab content only.
class SearchTab extends StatelessWidget {
  const SearchTab({super.key});

  @override
  Widget build(BuildContext context) {
    final MedicineSearchController c = Get.find<MedicineSearchController>();
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: SearchField(
                  controller: c.text,
                  hint: 'c_search_hint'.tr,
                  onChanged: c.onTyping,
                  onSubmitted: (String v) {
                    c.query.value = v;
                    if (!c.hasQuery) {
                      c.onTyping(v);
                      return;
                    }
                    c.runSearch(v);
                    Get.toNamed<dynamic>(AppRoutes.searchResults);
                  },
                ),
              ),
              const SizedBox(width: 8),
              FilterButton(controller: c),
            ],
          ),
        ),
        ActiveFilterChips(controller: c),
        Expanded(
          child: Obx(() {
            if (!c.hasQuery) return _Idle(controller: c);
            if (c.suggesting.value && c.suggestions.isEmpty) return const Center(child: CircularProgressIndicator());
            final AppFailure? failure = c.suggestFailure.value;
            if (failure != null) return ErrorState(failure: failure, onRetry: () => c.onTyping(c.query.value));
            if (c.suggestions.isEmpty) {
              return EmptyState(icon: Icons.search_off_rounded, title: 'c_no_results'.tr, message: 'c_no_results_hint'.tr);
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                for (final Medicine m in c.suggestions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: MedicineTile(medicine: m, onTap: () => Get.toNamed<dynamic>(AppRoutes.medicine(m.id))),
                  ),
                AppButton(
                  label: 'c_show_all_results'.tr,
                  icon: Icons.list_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: () {
                    c.runSearch(c.query.value);
                    Get.toNamed<dynamic>(AppRoutes.searchResults);
                  },
                ),
              ],
            );
          }),
        ),
      ],
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle({required this.controller});

  final MedicineSearchController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Obx(() {
      final bool hasCategory = controller.categoryId.value != null;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          InlineNotice(hasCategory ? 'c_search_in_category'.tr : 'c_search_min_hint'.tr),
          if (controller.recent.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            SectionTitle('c_recent_searches'.tr),
            for (final String r in controller.recent)
              ListTile(
                leading: const Icon(Icons.history_rounded),
                title: Text(r, style: t.bodyLarge),
                onTap: () {
                  controller.runSearch(r);
                  Get.toNamed<dynamic>(AppRoutes.searchResults);
                },
              ),
          ],
        ],
      );
    });
  }
}
