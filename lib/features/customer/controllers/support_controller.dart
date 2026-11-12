import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/repositories/support_repository.dart';

/// A report category: the code stored with the report, and the kind of thing it is about.
class ReportCategory {
  const ReportCategory(this.code, this.targetType);

  final String code;
  final String targetType;

  String get labelKey => 'c_report_$code';
}

/// Help and report an issue (C-27).
class SupportController extends BaseController {
  SupportController({SupportRepository? support}) : _support = support ?? Get.find<SupportRepository>();

  static const int descriptionMin = 5;
  static const int descriptionMax = 1000;

  static const List<ReportCategory> categories = <ReportCategory>[
    ReportCategory('pharmacy_problem', 'pharmacy'),
    ReportCategory('wrong_medicine_info', 'medicine'),
    ReportCategory('order_problem', 'order'),
    ReportCategory('app_problem', 'app'),
    ReportCategory('other', 'other'),
  ];

  final SupportRepository _support;

  final GlobalKey<FormState> form = GlobalKey<FormState>();
  final TextEditingController description = TextEditingController();
  final Rx<ReportCategory> category = categories.first.obs;

  /// True after a report was sent (the screen shows a confirmation until the user writes another).
  final RxBool sent = false.obs;

  @override
  void onInit() {
    super.onInit();
    status.value = ViewStatus.ready;
  }

  @override
  void onClose() {
    description.dispose();
    super.onClose();
  }

  void selectCategory(ReportCategory c) => category.value = c;

  void writeAnother() => sent.value = false;

  Future<bool> send() async {
    if (submitting.value) return false;
    if (!(form.currentState?.validate() ?? false)) return false;
    final ReportCategory c = category.value;
    final bool? ok = await submit<bool>(() async {
      await _support.submitReport(targetType: c.targetType, category: c.code, description: description.text);
      return true;
    });
    if (ok != true) return false;
    description.clear();
    sent.value = true;
    AppToast.success('c_help_sent'.tr);
    return true;
  }
}
