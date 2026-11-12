import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../utils/debouncer.dart';

/// Search box that reports typing after a short pause ([onChanged], debounced) and immediately on submit.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.onChanged,
    this.onSubmitted,
    this.hint,
    this.controller,
    this.autofocus = false,
    this.delay = const Duration(milliseconds: 350),
  });

  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? hint;
  final TextEditingController? controller;
  final bool autofocus;
  final Duration delay;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _c = widget.controller ?? TextEditingController();
  late final Debouncer _debounce = Debouncer(delay: widget.delay);

  @override
  void initState() {
    super.initState();
    _c.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _c.removeListener(_rebuild);
    _debounce.dispose();
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      autofocus: widget.autofocus,
      textInputAction: TextInputAction.search,
      onChanged: (String v) => _debounce.run(() => widget.onChanged(v)),
      onSubmitted: (String v) {
        _debounce.cancel();
        (widget.onSubmitted ?? widget.onChanged)(v);
      },
      decoration: InputDecoration(
        hintText: widget.hint ?? 'search'.tr,
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _c.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'clear'.tr,
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _c.clear();
                  _debounce.cancel();
                  widget.onChanged('');
                },
              ),
      ),
    );
  }
}
