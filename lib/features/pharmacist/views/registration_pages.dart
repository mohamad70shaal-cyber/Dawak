import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/ltr_text.dart';
import '../../../core/widgets/notice_banner.dart';
import '../../../data/models/pharmacy.dart';
import '../controllers/pharmacy_registration_controller.dart';
import '../services/license_picker.dart';
import '../widgets/hours_editor.dart';
import '../widgets/location_picker.dart';
import '../widgets/wizard_scaffold.dart';

String _sizeText(int bytes) {
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).ceil()} KB';
}

/// P-03: introduction and licence document.
class RegistrationLicensePage extends StatelessWidget {
  const RegistrationLicensePage({super.key});

  @override
  Widget build(BuildContext context) {
    final PharmacyRegistrationController c = Get.find<PharmacyRegistrationController>();
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return WizardScaffold(
      step: 1,
      title: c.isResubmission ? 'p_reg_title_resubmit'.tr : 'p_reg_title'.tr,
      canGoBack: false,
      actions: <Widget>[
        IconButton(tooltip: 'auth_sign_out'.tr, onPressed: c.signOut, icon: const Icon(Icons.logout_rounded)),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('p_reg_license_heading'.tr, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('p_reg_license_intro'.tr, style: t.bodyMedium?.copyWith(color: p.textSecondary)),
          const SizedBox(height: 16),
          NoticeBanner('p_reg_review_note'.tr, kind: NoticeKind.info),
          const SizedBox(height: 16),
          Obx(() {
            final PickedLicense? f = c.picked.value;
            final bool hasOld = (c.existingLicensePath.value ?? '').isNotEmpty;
            return AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(f != null || hasOld ? Icons.description_rounded : Icons.upload_file_rounded, color: p.primaryText, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: f != null
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  LtrText(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                                  Text(_sizeText(f.size), style: t.bodySmall?.copyWith(color: p.textSecondary)),
                                ],
                              )
                            : Text(hasOld ? 'p_reg_license_kept'.tr : 'p_reg_license_none'.tr, style: t.bodyMedium),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: AppButton(
                          label: f != null || hasOld ? 'p_reg_license_replace'.tr : 'p_reg_license_choose'.tr,
                          icon: Icons.folder_open_rounded,
                          variant: AppButtonVariant.secondary,
                          onPressed: c.pickLicense,
                        ),
                      ),
                      if (f != null) ...<Widget>[
                        const SizedBox(width: 8),
                        IconButton(tooltip: 'remove'.tr, onPressed: c.removeLicense, icon: const Icon(Icons.delete_outline_rounded)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('p_reg_license_formats'.tr, style: t.bodySmall?.copyWith(color: p.textSecondary)),
                ],
              ),
            );
          }),
          Obx(() {
            final String? e = c.licenseError.value;
            return e == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: 12), child: NoticeBanner(e));
          }),
        ],
      ),
      bottom: AppButton(label: 'next'.tr, icon: Icons.arrow_forward_rounded, onPressed: c.continueFromLicense),
    );
  }
}

/// P-04: name, phone, visibility of the phone, currency.
class RegistrationInfoPage extends StatelessWidget {
  const RegistrationInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final PharmacyRegistrationController c = Get.find<PharmacyRegistrationController>();
    final TextTheme t = Theme.of(context).textTheme;
    final AppPalette p = context.palette;
    return WizardScaffold(
      step: 2,
      title: 'p_reg_info_title'.tr,
      body: Form(
        key: c.infoForm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppTextField(
              label: 'p_reg_name'.tr,
              controller: c.name,
              prefixIcon: Icons.local_pharmacy_rounded,
              textInputAction: TextInputAction.next,
              maxLength: 120,
              validator: Validators.length(min: 2, max: 120),
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'p_reg_phone'.tr,
              controller: c.phone,
              ltr: true,
              prefixIcon: Icons.phone_rounded,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              validator: Validators.phone,
            ),
            Obx(() => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: c.showPhonePublicly.value,
                  onChanged: (bool v) => c.showPhonePublicly.value = v,
                  title: Text('p_reg_show_phone'.tr),
                  subtitle: Text('p_reg_show_phone_hint'.tr),
                )),
            const SizedBox(height: 8),
            Text('p_reg_currency'.tr, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Obx(() {
              final String cur = c.currency.value;
              return SegmentedButton<String>(
                showSelectedIcon: true,
                segments: <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'SYP', label: Text('currency_syp_name'.tr)),
                  ButtonSegment<String>(value: 'USD', label: Text('currency_usd_name'.tr)),
                ],
                selected: <String>{cur},
                onSelectionChanged: c.isResubmission ? null : (Set<String> s) => c.setCurrency(s.first),
              );
            }),
            const SizedBox(height: 6),
            Text(
              c.isResubmission ? 'p_reg_currency_locked'.tr : 'p_reg_currency_hint'.tr,
              style: t.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      ),
      bottom: AppButton(label: 'next'.tr, icon: Icons.arrow_forward_rounded, onPressed: c.continueFromInfo),
    );
  }
}

/// P-05: address.
class RegistrationAddressPage extends StatelessWidget {
  const RegistrationAddressPage({super.key});

  @override
  Widget build(BuildContext context) {
    final PharmacyRegistrationController c = Get.find<PharmacyRegistrationController>();
    return WizardScaffold(
      step: 3,
      title: 'p_reg_address_title'.tr,
      body: Form(
        key: c.addressForm,
        child: Column(
          children: <Widget>[
            AppTextField(
              label: 'p_reg_city'.tr,
              controller: c.city,
              prefixIcon: Icons.location_city_rounded,
              textInputAction: TextInputAction.next,
              maxLength: 100,
              validator: Validators.length(min: 2, max: 100),
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'p_reg_neighborhood'.tr,
              controller: c.neighborhood,
              prefixIcon: Icons.map_outlined,
              textInputAction: TextInputAction.next,
              maxLength: 100,
              validator: Validators.length(max: 100),
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'p_reg_address_line'.tr,
              controller: c.addressLine,
              prefixIcon: Icons.place_rounded,
              textInputAction: TextInputAction.next,
              maxLength: 250,
              validator: Validators.length(min: 3, max: 250),
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'p_reg_directions'.tr,
              hint: 'p_reg_directions_hint'.tr,
              controller: c.directions,
              prefixIcon: Icons.directions_rounded,
              maxLines: 3,
              minLines: 2,
              maxLength: 500,
              validator: Validators.length(max: 500),
            ),
            const SizedBox(height: 16),
            LocationPickerCard(input: c.location, onChanged: () => c.locationError.value = null),
            Obx(() {
              final String? e = c.locationError.value;
              return e == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: 12), child: NoticeBanner(e));
            }),
          ],
        ),
      ),
      bottom: AppButton(label: 'next'.tr, icon: Icons.arrow_forward_rounded, onPressed: c.continueFromAddress),
    );
  }
}

/// P-06: opening hours, a summary of everything entered, and the submit button.
class RegistrationHoursPage extends StatelessWidget {
  const RegistrationHoursPage({super.key});

  @override
  Widget build(BuildContext context) {
    final PharmacyRegistrationController c = Get.find<PharmacyRegistrationController>();
    final TextTheme t = Theme.of(context).textTheme;
    return WizardScaffold(
      step: 4,
      title: 'p_reg_hours_title'.tr,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('p_reg_hours_intro'.tr, style: t.bodyMedium?.copyWith(color: context.palette.textSecondary)),
          const SizedBox(height: 12),
          HoursEditor(hours: c.hours, onToggle: c.setDayOpen, onTime: c.setDayTime),
          Obx(() {
            final String? e = c.hoursError.value;
            return e == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(bottom: 12), child: NoticeBanner(e));
          }),
          const SizedBox(height: 8),
          _ReviewCard(c: c),
        ],
      ),
      bottom: Obx(() => AppButton(
            label: c.isResubmission ? 'p_reg_resubmit'.tr : 'p_reg_submit'.tr,
            icon: Icons.send_rounded,
            loading: c.submitting.value,
            onPressed: c.submitApplication,
          )),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.c});

  final PharmacyRegistrationController c;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'p_reg_review'.tr,
      icon: Icons.fact_check_rounded,
      child: Obx(() {
        final PharmacyDraft d = c.buildDraft();
        final int open = d.hours.days.where((DayHours h) => h.open).length;
        final PickedLicense? f = c.picked.value;
        return Column(
          children: <Widget>[
            InfoRow(label: 'p_reg_name'.tr, value: d.name),
            InfoRow(label: 'p_reg_phone'.tr, value: d.phone, ltr: true),
            InfoRow(label: 'p_reg_currency'.tr, value: d.currency == 'USD' ? 'currency_usd_name'.tr : 'currency_syp_name'.tr),
            InfoRow(label: 'p_reg_city'.tr, value: d.city),
            InfoRow(label: 'p_reg_address_line'.tr, value: d.addressLine),
            InfoRow(label: 'p_loc_title'.tr, value: d.location?.label ?? '—', ltr: true),
            InfoRow(label: 'p_reg_review_days'.tr, value: '$open'),
            InfoRow(label: 'p_reg_license_heading'.tr, value: f?.name ?? 'p_reg_license_kept'.tr, ltr: f != null),
          ],
        );
      }),
    );
  }
}
