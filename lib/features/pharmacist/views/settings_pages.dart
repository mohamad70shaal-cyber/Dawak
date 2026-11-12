import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/notice_banner.dart';
import '../controllers/pharmacy_settings_controller.dart';
import '../widgets/hours_editor.dart';
import '../widgets/location_picker.dart';

Widget _ownerNote(PharmacySettingsController c) =>
    c.canEdit ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(bottom: 16), child: NoticeBanner('p_settings_owner_only'.tr, kind: NoticeKind.info));

Widget _saveButton(PharmacySettingsController c, Future<bool> Function() onSave) =>
    c.canEdit ? Obx(() => AppButton(label: 'save'.tr, icon: Icons.check_rounded, loading: c.submitting.value, onPressed: onSave)) : const SizedBox.shrink();

/// Pharmacy profile (P-67): name and whether customers can find the pharmacy.
class SettingsProfilePage extends StatelessWidget {
  const SettingsProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final PharmacySettingsController c = Get.find<PharmacySettingsController>();
    return Scaffold(
      appBar: AppBar(title: Text('p_settings_profile'.tr)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Form(
          key: c.profileForm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _ownerNote(c),
              AppTextField(
                label: 'p_reg_name'.tr,
                controller: c.name,
                prefixIcon: Icons.local_pharmacy_rounded,
                maxLength: 120,
                readOnly: !c.canEdit,
                validator: Validators.length(min: 2, max: 120),
              ),
              const SizedBox(height: 8),
              Obx(() => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: c.isListed.value,
                    onChanged: c.canEdit ? (bool v) => c.isListed.value = v : null,
                    title: Text('p_settings_list_title'.tr),
                    subtitle: Text('p_settings_list_hint'.tr),
                  )),
              const SizedBox(height: 24),
              _saveButton(c, c.saveProfile),
            ],
          ),
        ),
      ),
    );
  }
}

/// Address and phone (P-68).
class SettingsContactPage extends StatelessWidget {
  const SettingsContactPage({super.key});

  @override
  Widget build(BuildContext context) {
    final PharmacySettingsController c = Get.find<PharmacySettingsController>();
    return Scaffold(
      appBar: AppBar(title: Text('p_settings_contact'.tr)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Form(
          key: c.contactForm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _ownerNote(c),
              AppTextField(label: 'p_reg_phone'.tr, controller: c.phone, ltr: true, prefixIcon: Icons.phone_rounded, keyboardType: TextInputType.phone, readOnly: !c.canEdit, validator: Validators.phone),
              Obx(() => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: c.showPhonePublicly.value,
                    onChanged: c.canEdit ? (bool v) => c.showPhonePublicly.value = v : null,
                    title: Text('p_reg_show_phone'.tr),
                    subtitle: Text('p_reg_show_phone_hint'.tr),
                  )),
              const SizedBox(height: 8),
              AppTextField(label: 'p_reg_city'.tr, controller: c.city, prefixIcon: Icons.location_city_rounded, maxLength: 100, readOnly: !c.canEdit, validator: Validators.length(min: 2, max: 100)),
              const SizedBox(height: 16),
              AppTextField(label: 'p_reg_neighborhood'.tr, controller: c.neighborhood, prefixIcon: Icons.map_outlined, maxLength: 100, readOnly: !c.canEdit, validator: Validators.length(max: 100)),
              const SizedBox(height: 16),
              AppTextField(label: 'p_reg_address_line'.tr, controller: c.addressLine, prefixIcon: Icons.place_rounded, maxLength: 250, readOnly: !c.canEdit, validator: Validators.length(min: 3, max: 250)),
              const SizedBox(height: 16),
              AppTextField(label: 'p_reg_directions'.tr, controller: c.directions, prefixIcon: Icons.directions_rounded, maxLines: 3, minLines: 2, maxLength: 500, readOnly: !c.canEdit, validator: Validators.length(max: 500)),
              const SizedBox(height: 24),
              _saveButton(c, c.saveContact),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shop location (P-74): GPS or a pasted map link.
class SettingsLocationPage extends StatelessWidget {
  const SettingsLocationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final PharmacySettingsController c = Get.find<PharmacySettingsController>();
    return Scaffold(
      appBar: AppBar(title: Text('p_settings_location'.tr)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _ownerNote(c),
            LocationPickerCard(input: c.location, readOnly: !c.canEdit),
            const SizedBox(height: 24),
            if (c.canEdit)
              Obx(() => AppButton(
                    label: 'save'.tr,
                    icon: Icons.check_rounded,
                    loading: c.submitting.value,
                    onPressed: c.location.point.value == null ? null : c.saveLocation,
                  )),
          ],
        ),
      ),
    );
  }
}

/// Opening hours (P-69).
class SettingsHoursPage extends StatelessWidget {
  const SettingsHoursPage({super.key});

  @override
  Widget build(BuildContext context) {
    final PharmacySettingsController c = Get.find<PharmacySettingsController>();
    return Scaffold(
      appBar: AppBar(title: Text('p_settings_hours'.tr)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _ownerNote(c),
            IgnorePointer(
              ignoring: !c.canEdit,
              child: HoursEditor(hours: c.hours, onToggle: c.setDayOpen, onTime: c.setDayTime),
            ),
            Obx(() => c.hoursError.value == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(bottom: 12), child: NoticeBanner(c.hoursError.value!))),
            const SizedBox(height: 12),
            _saveButton(c, c.saveHours),
          ],
        ),
      ),
    );
  }
}

/// Account and security (P-70): who is signed in, change the password.
class SettingsSecurityPage extends StatelessWidget {
  const SettingsSecurityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final PharmacySettingsController c = Get.find<PharmacySettingsController>();
    final TextTheme t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text('p_settings_security'.tr)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Form(
          key: c.passwordForm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              InfoRow(label: 'auth_email'.tr, value: c.email, ltr: true),
              const SizedBox(height: 24),
              Text('p_security_change_password'.tr, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              AppTextField(label: 'p_security_new_password'.tr, controller: c.newPassword, obscure: true, ltr: true, textInputAction: TextInputAction.next, validator: Validators.password, autofillHints: const <String>[AutofillHints.newPassword]),
              const SizedBox(height: 16),
              AppTextField(
                label: 'p_security_confirm_password'.tr,
                controller: c.confirmPassword,
                obscure: true,
                ltr: true,
                textInputAction: TextInputAction.done,
                validator: Validators.confirmPassword(() => c.newPassword.text),
              ),
              const SizedBox(height: 24),
              Obx(() => AppButton(label: 'p_security_save'.tr, icon: Icons.lock_reset_rounded, loading: c.submitting.value, onPressed: c.changePassword)),
            ],
          ),
        ),
      ),
    );
  }
}
