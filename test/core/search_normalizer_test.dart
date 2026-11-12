import 'package:dawak/core/utils/search_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

/// The same vectors as `supabase/tests/40_tests_public_dashboard.sql` (t_pub_01): the Dart and SQL
/// normalisers must agree, otherwise client-side filtering and server-side search would disagree.
void main() {
  const Map<String, String> vectors = <String, String>{
    'بَنَادُول': 'بنادول',
    'أوميبرازول': 'اوميبرازول',
    'إيبوبروفين': 'ايبوبروفين',
    'آسبرين': 'اسبرين',
    'كبسولة': 'كبسوله',
    'مستشفى': 'مستشفي',
    'مؤشر': 'موشر',
    'ـبـنـادول': 'بنادول',
    '٥٠٠ ملغ': '500 ملغ',
    '۵۰۰': '500',
    'PANADOL   Extra ': 'panadol extra',
  };

  vectors.forEach((String input, String expected) {
    test('normalizeSearch("$input") == "$expected"', () {
      expect(normalizeSearch(input), expected);
    });
  });

  test('null and empty give empty string', () {
    expect(normalizeSearch(null), '');
    expect(normalizeSearch(''), '');
  });

  test('digits are mapped, never stripped as tashkeel', () {
    for (int i = 0; i < 10; i++) {
      expect(normalizeSearch(String.fromCharCode(0x0660 + i)), '$i');
      expect(normalizeSearch(String.fromCharCode(0x06F0 + i)), '$i');
    }
  });
}
