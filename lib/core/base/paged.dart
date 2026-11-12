import 'package:get/get.dart';

import '../errors/app_failure.dart';
import '../widgets/app_toast.dart';
import 'base_controller.dart';

/// Offset/limit paging for a list screen. [fetch] returns one page; a page shorter than [pageSize] is the last.
///
/// A [reload] started while an older request is still running wins: late answers of the older request are dropped.
class Paged<T> {
  Paged({required this.fetch, this.pageSize = 20});

  final Future<List<T>> Function(int offset, int limit) fetch;
  final int pageSize;

  final RxList<T> items = <T>[].obs;
  final Rx<ViewStatus> status = ViewStatus.loading.obs;
  final Rxn<AppFailure> failure = Rxn<AppFailure>();
  final RxBool loadingMore = false.obs;
  final RxBool hasMore = true.obs;

  int _generation = 0;

  /// First page. With [silent] the current items stay on screen while refreshing.
  Future<void> reload({bool silent = false}) async {
    final int gen = ++_generation;
    if (!silent || status.value != ViewStatus.ready) status.value = ViewStatus.loading;
    failure.value = null;
    loadingMore.value = false;
    try {
      final List<T> page = await fetch(0, pageSize);
      if (gen != _generation) return;
      items.assignAll(page);
      hasMore.value = page.length >= pageSize;
      status.value = items.isEmpty ? ViewStatus.empty : ViewStatus.ready;
    } catch (e) {
      if (gen != _generation) return;
      final AppFailure f = AppFailure.from(e);
      if (silent && items.isNotEmpty) {
        AppToast.error(failureText(f));
        status.value = ViewStatus.ready;
        return;
      }
      failure.value = f;
      status.value = ViewStatus.error;
    }
  }

  /// Next page, appended. No-op while loading, when everything is loaded or before the first page arrived.
  Future<void> loadMore() async {
    if (loadingMore.value || !hasMore.value || status.value != ViewStatus.ready) return;
    final int gen = _generation;
    loadingMore.value = true;
    try {
      final List<T> page = await fetch(items.length, pageSize);
      if (gen != _generation) return;
      items.addAll(page);
      hasMore.value = page.length >= pageSize;
    } catch (e) {
      if (gen != _generation) return;
      AppToast.error(failureText(AppFailure.from(e)));
    } finally {
      if (gen == _generation) loadingMore.value = false;
    }
  }

  /// Replaces one loaded item (e.g. after an order changed state) without refetching the page.
  void replaceWhere(bool Function(T) test, T replacement) {
    final int i = items.indexWhere(test);
    if (i >= 0) items[i] = replacement;
  }
}
