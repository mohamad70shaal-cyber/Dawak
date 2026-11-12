import 'package:get/get.dart';

import '../errors/app_failure.dart';
import '../services/session_service.dart';
import '../widgets/app_toast.dart';

enum ViewStatus { loading, ready, empty, error }

/// Translated, human wording for a failure. Falls back to the generic message when a code has no
/// translation, so raw codes or database text never reach the screen.
String failureText(AppFailure f) {
  final String key = f.messageKey;
  final String t = key.tr;
  return t == key ? 'err_unknown'.tr : t;
}

/// Common state handling for screens that load data and/or submit actions.
///
/// - [load] drives the loading / ready / empty / error states shown by `AsyncStateView`.
/// - [submit] wraps a write: sets [submitting] (so buttons disable and cannot double-submit), converts errors
///   into [failure] + a toast, and reports server codes that change the session (suspension, expiry).
abstract class BaseController extends GetxController {
  final Rx<ViewStatus> status = ViewStatus.loading.obs;
  final Rxn<AppFailure> failure = Rxn<AppFailure>();
  final RxBool submitting = false.obs;

  bool get isLoading => status.value == ViewStatus.loading;

  /// Runs [job] as the screen's main load. [isEmpty] decides between `ready` and `empty` afterwards.
  /// With [silent] the current content stays visible while refreshing (pull to refresh).
  Future<void> load(Future<void> Function() job, {bool Function()? isEmpty, bool silent = false}) async {
    if (!silent) status.value = ViewStatus.loading;
    failure.value = null;
    try {
      await job();
      status.value = (isEmpty != null && isEmpty()) ? ViewStatus.empty : ViewStatus.ready;
    } catch (e) {
      final AppFailure f = AppFailure.from(e);
      await _notifySession(f);
      if (silent && status.value == ViewStatus.ready) {
        AppToast.error(failureText(f));
        return;
      }
      failure.value = f;
      status.value = ViewStatus.error;
    }
  }

  /// Runs a write. Returns the result, or `null` when it failed (the failure is in [failure] and shown as a toast
  /// unless [toast] is false). While running, [submitting] is true and a second call is ignored.
  Future<T?> submit<T>(Future<T> Function() job, {bool toast = true}) async {
    if (submitting.value) return null;
    submitting.value = true;
    failure.value = null;
    try {
      return await job();
    } catch (e) {
      final AppFailure f = AppFailure.from(e);
      failure.value = f;
      if (toast) AppToast.error(failureText(f));
      await _notifySession(f);
      return null;
    } finally {
      submitting.value = false;
    }
  }

  /// For background work that does its own error handling (a poll): a suspended or signed-out account still ends the session.
  Future<void> reportToSession(AppFailure f) => _notifySession(f);

  Future<void> _notifySession(AppFailure f) async {
    if (!Get.isRegistered<SessionService>()) return;
    if (f.code == 'account_suspended' || f.code == 'not_authenticated') {
      await Get.find<SessionService>().handleFailure(f);
    }
  }
}
