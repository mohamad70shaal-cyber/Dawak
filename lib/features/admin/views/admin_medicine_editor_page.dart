import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/notice_banner.dart';
import '../../../core/widgets/states.dart';
import '../../../data/models/medicine.dart';
import '../controllers/admin_medicine_editor_controller.dart';
import '../widgets/admin_widgets.dart';

/// Medicine editor and proposal review (A-08). `/admin/medicines/new` creates, `/admin/medicines/:id` edits and reviews.
class AdminMedicineEditorPage extends StatelessWidget {
  const AdminMedicineEditorPage({super.key});

  @override
  Widget build(BuildContext context) {
    final String id = Get.parameters['id'] ?? '';
    final AdminMedicineEditorController c = Get.find<AdminMedicineEditorController>(tag: id.isEmpty ? 'new' : id);
    return Scaffold(
      appBar: AppBar(title: Text((c.isNew ? 'a_medicine_new' : 'a_medicine_edit').tr)),
      body: AsyncStateView.of(c, onRetry: c.refresh, builder: (BuildContext context) => _Form(c: c)),
      bottomNavigationBar: BottomActionBar(
        child: Obx(() => AppButton(
              label: (c.isNew ? 'a_medicine_create' : 'save').tr,
              icon: Icons.check_rounded,
              loading: c.submitting.value,
              onPressed: c.save,
            )),
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({required this.c});

  final AdminMedicineEditorController c;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Obx(() => c.notice.value == null
              ? const SizedBox.shrink()
              : Padding(padding: const EdgeInsets.only(bottom: 12), child: NoticeBanner(c.notice.value!, kind: NoticeKind.error))),
          Obx(() {
            final Medicine? m = c.medicine.value;
            if (c.isNew || m == null) return const SizedBox.shrink();
            return Padding(padding: const EdgeInsets.only(bottom: 16), child: _ReviewCard(c: c, status: m.catalogStatus));
          }),
          Form(
            key: c.form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppTextField(label: 'a_med_name_ar'.tr, controller: c.nameAr, maxLength: 160, textInputAction: TextInputAction.next, validator: c.nameRule),
                const SizedBox(height: 16),
                AppTextField(label: 'a_med_name_en'.tr, controller: c.nameEn, ltr: true, maxLength: 160, textInputAction: TextInputAction.next, validator: c.nameRule),
                const SizedBox(height: 16),
                AppTextField(label: 'a_med_brand'.tr, controller: c.brand, maxLength: 160, textInputAction: TextInputAction.next),
                const SizedBox(height: 16),
                AppTextField(label: 'a_med_ingredient'.tr, controller: c.ingredient, maxLength: 200, textInputAction: TextInputAction.next),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: AppTextField(label: 'a_med_strength'.tr, hint: '500mg', controller: c.strength, ltr: true, maxLength: 60, textInputAction: TextInputAction.next)),
                    const SizedBox(width: 12),
                    Expanded(child: AppTextField(label: 'a_med_form'.tr, controller: c.dosageForm, maxLength: 60, textInputAction: TextInputAction.next)),
                  ],
                ),
                const SizedBox(height: 16),
                AppTextField(label: 'a_med_package'.tr, controller: c.packageDescription, maxLength: 200, textInputAction: TextInputAction.done),
                const SizedBox(height: 16),
                Obx(() {
                  if (c.categories.isEmpty) return const SizedBox.shrink();
                  final String? current = c.categoryId.value;
                  final bool known = current == null || c.categories.any((MedicineCategory cat) => cat.id == current);
                  return DropdownButtonFormField<String>(
                    value: known ? current : null,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: 'a_med_category'.tr),
                    items: <DropdownMenuItem<String>>[
                      for (final MedicineCategory cat in c.categories)
                        DropdownMenuItem<String>(
                          value: cat.id,
                          child: Text(cat.isActive ? cat.name(isArabicNow()) : '${cat.name(isArabicNow())} (${'a_category_off'.tr})'),
                        ),
                    ],
                    onChanged: (String? v) => c.categoryId.value = v,
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.c, required this.status});

  final AdminMedicineEditorController c;
  final String status;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return SectionCard(
      title: 'a_med_review'.tr,
      icon: Icons.fact_check_outlined,
      trailing: CatalogStatusChip(status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (c.canApprove) ...<Widget>[
            Text('a_med_review_hint'.tr, style: t.bodySmall?.copyWith(color: context.palette.textSecondary)),
            const SizedBox(height: 12),
            Obx(() => Row(
                  children: <Widget>[
                    Expanded(child: AppButton(label: 'a_medicine_reject'.tr, variant: AppButtonVariant.danger, onPressed: c.submitting.value ? null : c.reject)),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: AppButton(label: 'a_medicine_approve'.tr, icon: Icons.verified_rounded, loading: c.submitting.value, onPressed: c.approve)),
                  ],
                )),
          ],
          if (c.canArchive) ...<Widget>[
            if (c.canApprove) const SizedBox(height: 8),
            Obx(() => AppButton(
                  label: 'a_medicine_archive'.tr,
                  icon: Icons.inventory_2_outlined,
                  variant: AppButtonVariant.text,
                  onPressed: c.submitting.value ? null : c.archive,
                )),
          ],
          if (!c.canApprove && !c.canArchive) Text('a_med_review_final'.tr, style: t.bodySmall?.copyWith(color: context.palette.textSecondary)),
        ],
      ),
    );
  }
}
