import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/config/env.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/ltr_text.dart';
import '../controllers/support_controller.dart';
import '../widgets/customer_launch.dart';
import '../widgets/customer_widgets.dart';

/// Help and report an issue (C-27).
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final SupportController c = Get.find<SupportController>();
    final TextTheme t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('c_help_title'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SectionCard(
            title: 'c_support_email'.tr,
            icon: Icons.mail_outline_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                LtrText(Env.supportEmail, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    AppButton(label: 'copy'.tr, icon: Icons.copy_rounded, expand: false, variant: AppButtonVariant.secondary, onPressed: () => copyText(Env.supportEmail)),
                    AppButton(label: 'c_write_email'.tr, icon: Icons.send_rounded, expand: false, variant: AppButtonVariant.secondary, onPressed: () => writeEmail(Env.supportEmail)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Obx(() {
            if (c.sent.value) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  InlineNotice('c_help_sent'.tr, tone: NoticeTone.success),
                  const SizedBox(height: 12),
                  AppButton(label: 'c_report_another'.tr, variant: AppButtonVariant.secondary, onPressed: c.writeAnother),
                ],
              );
            }
            return Form(
              key: c.form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SectionTitle('c_report_title'.tr),
                  Text('c_report_hint'.tr, style: t.bodyMedium?.copyWith(color: context.palette.textSecondary)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final ReportCategory cat in SupportController.categories)
                        ChoiceChip(label: Text(cat.labelKey.tr), selected: c.category.value.code == cat.code, onSelected: (_) => c.selectCategory(cat)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'c_report_description'.tr,
                    controller: c.description,
                    maxLines: 6,
                    minLines: 4,
                    maxLength: SupportController.descriptionMax,
                    validator: Validators.length(min: SupportController.descriptionMin, max: SupportController.descriptionMax),
                  ),
                  const SizedBox(height: 16),
                  AppButton(label: 'c_report_send'.tr, icon: Icons.send_rounded, loading: c.submitting.value, onPressed: c.send),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
