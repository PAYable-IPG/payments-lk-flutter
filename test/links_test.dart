import 'package:flutter_test/flutter_test.dart';
import 'package:payments_lk/payments_lk.dart';

void main() {
  test('builds a subscription link with the plan, the email and the language',
      () {
    expect(subscriptionLinkUrl(code: 'Gold_Plan-2026'),
        'https://payments.lk/s/Gold_Plan-2026');
    expect(
      subscriptionLinkUrl(
          code: 'Gold_Plan-2026',
          plan: 'price_0123456789abcdefghij',
          email: 'nimal+box@example.lk',
          lang: 'si'),
      'https://payments.lk/si/s/Gold_Plan-2026?plan=price_0123456789abcdefghij&email=nimal%2Bbox%40example.lk',
    );
    expect(subscriptionLinkUrl(code: 'Gold_Plan-2026', lang: 'fr'),
        'https://payments.lk/s/Gold_Plan-2026');
    expect(
        subscriptionLinkUrl(
            code: 'Gold_Plan-2026', site: 'https://staging.example.lk/'),
        'https://staging.example.lk/s/Gold_Plan-2026');
  });

  test('leaves out an email that is not one', () {
    expect(subscriptionLinkUrl(code: 'Gold_Plan-2026', email: 'nobody'),
        'https://payments.lk/s/Gold_Plan-2026');
    expect(subscriptionLinkUrl(code: 'Gold_Plan-2026', email: '@example.lk'),
        'https://payments.lk/s/Gold_Plan-2026');
  });

  test(
      'refuses a code or plan not shaped like one, and a site that is not an https origin',
      () {
    Matcher refuses(PaymentsLkErrorCode code) =>
        throwsA(isA<PaymentsLkCheckoutException>()
            .having((PaymentsLkCheckoutException e) => e.code, 'code', code));
    expect(() => subscriptionLinkUrl(code: 'short'),
        refuses(PaymentsLkErrorCode.invalidLink));
    expect(() => subscriptionLinkUrl(code: 'has space in'),
        refuses(PaymentsLkErrorCode.invalidLink));
    expect(() => subscriptionLinkUrl(code: 'Gold_Plan-2026', plan: 'gold'),
        refuses(PaymentsLkErrorCode.invalidLink));
    expect(
        () => subscriptionLinkUrl(
            code: 'Gold_Plan-2026', site: 'http://payments.lk'),
        refuses(PaymentsLkErrorCode.insecureCheckoutUrl));
    expect(
        () => subscriptionLinkUrl(
            code: 'Gold_Plan-2026', site: 'https://payments.lk/?x=1'),
        refuses(PaymentsLkErrorCode.insecureCheckoutUrl));
  });
}
