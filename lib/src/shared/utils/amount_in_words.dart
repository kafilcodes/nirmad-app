import 'package:indian_currency_to_word/indian_currency_to_word.dart';

class AmountInWords {
  static final AmountToWords _converter = AmountToWords();

  /// Converts a numeric amount to Indian currency words using the package.
  /// Example: 1234.50 -> "One Thousand Two Hundred Thirty Four Rupees and Fifty Paise"
  /// If there are no paise, returns "... Rupees".
  static String toRupees(num amount) {
    final double v = amount.toDouble();
    // Use ignoreDecimal only when there is no fractional part
    final hasPaise = (v - v.truncate()) != 0.0;
    return _converter.convertAmountToWords(v, ignoreDecimal: !hasPaise);
  }
}
