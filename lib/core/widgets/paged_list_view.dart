import 'package:flutter/material.dart';

import '../base/paged.dart';
import 'states.dart';

/// A pull-to-refresh list over a [Paged] source with loading / error / empty states and infinite scroll.
class PagedListView<T> extends StatelessWidget {
  const PagedListView({
    super.key,
    required this.paged,
    required this.itemBuilder,
    this.empty,
    this.header,
    this.padding = const EdgeInsets.all(16),
  });

  final Paged<T> paged;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final Widget? empty;

  /// Scrolls with the list (filters, summary).
  final Widget? header;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return AsyncStateView(
      status: paged.status,
      failure: paged.failure,
      onRetry: paged.reload,
      empty: RefreshIndicator(
        onRefresh: () => paged.reload(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          children: <Widget>[
            if (header != null) header!,
            SizedBox(height: 320, child: empty ?? const EmptyState()),
          ],
        ),
      ),
      builder: (BuildContext context) {
        final int count = paged.items.length;
        final bool footer = paged.hasMore.value;
        final int headerCount = header == null ? 0 : 1;
        return RefreshIndicator(
          onRefresh: () => paged.reload(silent: true),
          child: NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification n) {
              if (n.metrics.extentAfter < 300) paged.loadMore();
              return false;
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: padding,
              itemCount: headerCount + count + (footer ? 1 : 0),
              itemBuilder: (BuildContext context, int i) {
                if (headerCount == 1 && i == 0) return header!;
                final int idx = i - headerCount;
                if (idx >= count) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: paged.loadingMore.value
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : const SizedBox.shrink(),
                    ),
                  );
                }
                return Padding(
                  padding: EdgeInsets.only(bottom: idx == count - 1 && !footer ? 0 : 12),
                  child: itemBuilder(context, paged.items[idx]),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
