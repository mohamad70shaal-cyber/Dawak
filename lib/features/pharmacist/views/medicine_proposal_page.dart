import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/notice_banner.dart';
import '../../../data/models/medicine.dart';
import '../controllers/medicine_proposal_controller.dart';
import '../widgets/pharmacist_widgets.dart';

/// Propose a medicine that is not in the catalogue yet (P-26).
class MedicineProposalPage extends StatelessWidget {
  const MedicineProposalPage({super.key});

  @override
  Widget build(BuildContext context) {
    final MedicineProposalController c = Get.find<MedicineProposalController>();
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text('p_propose_title'.tr)),
      body: Obx(() {
        if (c.sentForReview.value) {
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.mark_email_read_rounded, size: 64, color: AppColors.success),
                  const SizedBox(height: 16),
                  Text('p_propose_sent_title'.tr, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text('p_propose_sent_body'.tr, style: t.bodyMedium?.copyWith(color: p.textSecondary), textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  AppButton(label: 'done'.tr, onPressed: c.done),
                ],
              ),
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Form(
            key: c.form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                NoticeBanner('p_propose_intro'.tr, kind: NoticeKind.info),
                const SizedBox(height: 16),
                AppTextField(label: 'p_propose_name_ar'.tr, controller: c.nameAr, maxLength: 160, textInputAction: TextInputAction.next, validator: c.nameRule),
                const SizedBox(height: 16),
                AppTextField(label: 'p_propose_name_en'.tr, controller: c.nameEn, ltr: true, maxLength: 160, textInputAction: TextInputAction.next, validator: c.nameRule),
                const SizedBox(height: 16),
                AppTextField(label: 'p_propose_brand'.tr, controller: c.brand, maxLength: 160, textInputAction: TextInputAction.next),
                const SizedBox(height: 16),
                AppTextField(label: 'p_propose_ingredient'.tr, controller: c.ingredient, maxLength: 200, textInputAction: TextInputAction.next),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: AppTextField(label: 'p_propose_strength'.tr, hint: '500mg', controller: c.strength, ltr: true, maxLength: 60, textInputAction: TextInputAction.next)),
                    const SizedBox(width: 12),
                    Expanded(child: AppTextField(label: 'p_propose_form'.tr, controller: c.dosageForm, maxLength: 60, textInputAction: TextInputAction.next)),
                  ],
                ),
                const SizedBox(height: 16),
                AppTextField(label: 'p_propose_package'.tr, controller: c.packageDescription, maxLength: 200, textInputAction: TextInputAction.done),
                const SizedBox(height: 16),
                Obx(() => c.categories.isEmpty
                    ? const SizedBox.shrink()
                    : DropdownButtonFormField<String>(
                        value: c.categoryId.value,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: 'p_propose_category'.tr),
                        items: <DropdownMenuItem<String>>[
                          for (final MedicineCategory cat in c.categories)
                            DropdownMenuItem<String>(value: cat.id, child: Text(cat.name(isArabicNow()))),
                        ],
                        onChanged: (String? v) => c.categoryId.value = v,
                      )),
                const SizedBox(height: 24),
                Obx(() => AppButton(label: 'p_propose_send'.tr, icon: Icons.send_rounded, loading: c.submitting.value, onPressed: c.send)),
              ],
            ),
          ),
        );
      }),
    );
  }
}
