/// Dart twin of the SQL function `private.normalize_search`. Both must stay in sync: the same test vectors are
/// checked in `supabase/tests/40_tests_public_dashboard.sql` (t_pub_01) and `test/core/search_normalizer_test.dart`.
///
/// Rules: strip tashkeel and tatweel; fold أ إ آ ٱ → ا, ى → ي, ة → ه, ؤ → و, ئ → ي, Persian ک → ك and ی → ي;
/// map Arabic-Indic and Persian digits to ASCII; lower-case; collapse whitespace; trim.
String normalizeSearch(String? input) {
  if (input == null || input.isEmpty) return '';
  final StringBuffer out = StringBuffer();
  for (final int rune in input.runes) {
    // Tashkeel (U+064B–U+065F), superscript alef (U+0670) and tatweel (U+0640) are removed. The range must stop at
    // U+065F: U+0660–U+0669 are the Arabic-Indic digits, which are mapped, not dropped (same class as the SQL).
    if ((rune >= 0x064B && rune <= 0x065F) || rune == 0x0670 || rune == 0x0640) continue;
    final String? mapped = _fold[rune];
    if (mapped != null) {
      out.write(mapped);
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString().toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

const Map<int, String> _fold = <int, String>{
  0x0623: 'ا', // أ
  0x0625: 'ا', // إ
  0x0622: 'ا', // آ
  0x0671: 'ا', // ٱ
  0x0649: 'ي', // ى
  0x0629: 'ه', // ة
  0x0624: 'و', // ؤ
  0x0626: 'ي', // ئ
  0x06A9: 'ك', // ک
  0x06CC: 'ي', // ی
  0x0660: '0', 0x0661: '1', 0x0662: '2', 0x0663: '3', 0x0664: '4',
  0x0665: '5', 0x0666: '6', 0x0667: '7', 0x0668: '8', 0x0669: '9',
  0x06F0: '0', 0x06F1: '1', 0x06F2: '2', 0x06F3: '3', 0x06F4: '4',
  0x06F5: '5', 0x06F6: '6', 0x06F7: '7', 0x06F8: '8', 0x06F9: '9',
};
