import 'checkout.dart';

final RegExp _linkCode = RegExp(r'^[A-Za-z0-9_-]{8,64}$');
final RegExp _priceId = RegExp(r'^price_[0-9a-z]{20,32}$');

/// The address of a subscription link, where a customer picks a plan and pays
/// its first period. Open it with [PaymentsLkCheckout.openPage].
///
/// [code] is the last part of the link's address, as the dashboard shows it.
/// [plan] is a price id to choose first, [email] fills the customer's email
/// in, and [lang] opens the page in Sinhala (`si`) or Tamil (`ta`). [site]
/// is `https://payments.lk` unless you test against a staging site. Throws
/// [PaymentsLkCheckoutException] for a code or plan that is not shaped like
/// one.
String subscriptionLinkUrl({
  required String code,
  String? plan,
  String? email,
  String? lang,
  String site = 'https://payments.lk',
}) {
  if (!_linkCode.hasMatch(code)) {
    throw const PaymentsLkCheckoutException(
      PaymentsLkErrorCode.invalidLink,
      "A subscription link's code is the last part of its address, such as the dashboard shows it.",
    );
  }
  if (plan != null && !_priceId.hasMatch(plan)) {
    throw const PaymentsLkCheckoutException(
      PaymentsLkErrorCode.invalidLink,
      'A plan is a price id, such as price_0123456789abcdefghij.',
    );
  }
  final String origin = site.replaceFirst(RegExp(r'/+$'), '');
  if (!isAllowedCheckoutUrl(origin) ||
      origin.contains('?') ||
      origin.contains('#')) {
    throw const PaymentsLkCheckoutException(
      PaymentsLkErrorCode.insecureCheckoutUrl,
      'The site must be an https origin.',
    );
  }
  final String prefix = lang == 'si' || lang == 'ta' ? '/$lang' : '';
  final List<String> query = <String>[
    if (plan != null) 'plan=$plan',
    if (email != null && email.length <= 254 && email.indexOf('@') > 0)
      'email=${Uri.encodeComponent(email)}',
  ];
  return '$origin$prefix/s/$code${query.isEmpty ? '' : '?${query.join('&')}'}';
}
