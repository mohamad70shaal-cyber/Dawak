/// Mirrors `private.clean_phone` in SQL: ASCII digits with an optional leading '+', 7–15 digits.
/// Arabic-Indic digits, spaces, dashes and parentheses are accepted on input.
String? cleanPhone(String? input) {
  if (input == null) return null;
  final StringBuffer b = StringBuffer();
  for (final int r in input.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + (r - 0x0660));
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + (r - 0x06F0));
    } else if ((r >= 0x30 && r <= 0x39) || r == 0x2B) {
      b.writeCharCode(r);
    } else if (r == 0x20 || r == 0x2D || r == 0x28 || r == 0x29 || r == 0xA0) {
      continue;
    } else {
      return null;
    }
  }
  final String s = b.toString();
  return RegExp(r'^\+?[0-9]{7,15}$').hasMatch(s) ? s : null;
}
