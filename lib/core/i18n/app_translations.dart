import 'package:get/get.dart';

import '../../features/admin/i18n/admin_ar.dart';
import '../../features/admin/i18n/admin_en.dart';
import '../../features/auth/i18n/auth_ar.dart';
import '../../features/auth/i18n/auth_en.dart';
import '../../features/customer/i18n/customer_ar.dart';
import '../../features/customer/i18n/customer_en.dart';
import '../../features/pharmacist/i18n/pharmacist_ar.dart';
import '../../features/pharmacist/i18n/pharmacist_en.dart';
import '../../features/pharmacist/i18n/pharmacist_ops_ar.dart';
import '../../features/pharmacist/i18n/pharmacist_ops_en.dart';
import 'core_ar.dart';
import 'core_en.dart';

/// All translations. Prefix rule (checked by `tool/static_checks.py`): core = no prefix, `auth_`, `c_` customer,
/// `p_` pharmacist, `a_` admin; the same key may not appear in two files, and every key exists in ar and en.
class AppTranslations extends Translations {
  static final Map<String, String> ar = <String, String>{
    ...coreAr,
    ...authAr,
    ...customerAr,
    ...pharmacistAr,
    ...pharmacistOpsAr,
    ...adminAr,
  };

  static final Map<String, String> en = <String, String>{
    ...coreEn,
    ...authEn,
    ...customerEn,
    ...pharmacistEn,
    ...pharmacistOpsEn,
    ...adminEn,
  };

  @override
  Map<String, Map<String, String>> get keys => <String, Map<String, String>>{'ar': ar, 'en': en};
}
