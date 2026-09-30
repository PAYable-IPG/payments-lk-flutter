import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:payments_lk/payments_lk.dart';

const String checkoutUrl =
    'https://payments.lk/checkout/chk_0123456789abcdefghijklmn';
const String returnBase = 'myshop://payments-lk/return';

/// A browser that answers with [answer], or throws it, and records what it was asked to open.
class FakeBrowser {
  FakeBrowser(this.answer);
  final Object? answer;
  final List<String> opened = <String>[];
  final List<String> schemes = <String>[];
  final List<bool> ephemeral = <bool>[];

  Future<String> call(
      {required String url,
      required String callbackUrlScheme,
      required bool preferEphemeral}) async {
    opened.add(url);
    schemes.add(callbackUrlScheme);
    ephemeral.add(preferEphemeral);
    final Object? value = answer;
    if (value is String) return value;
    throw value!;
  }
}

Matcher throwsCode(PaymentsLkErrorCode code) =>
    throwsA(isA<PaymentsLkCheckoutException>()
        .having((PaymentsLkCheckoutException e) => e.code, 'code', code));

void main() {
  group('isAllowedCheckoutUrl', () {
    test(
        'takes https, and plain http only on this machine or the Android emulator host',
        () {
      expect(isAllowedCheckoutUrl(checkoutUrl), isTrue);
      expect(
          isAllowedCheckoutUrl('HTTPS://payments.lk/checkout/chk_1'), isTrue);
      expect(
          isAllowedCheckoutUrl('http://localhost:3311/checkout/chk_1'), isTrue);
      expect(
          isAllowedCheckoutUrl('http://127.0.0.1:3311/checkout/chk_1'), isTrue);
      expect(
          isAllowedCheckoutUrl('http://10.0.2.2:3311/checkout/chk_1'), isTrue);
    });

    test(
        'refuses plain http elsewhere, credentials, other schemes, spaces and backslashes',
        () {
      for (final String url in <String>[
        'http://payments.lk/checkout/chk_1',
        'https://user:pass@payments.lk/checkout/chk_1',
        'https://@payments.lk/',
        'javascript:alert(1)',
        'myshop://payments-lk/return',
        'https:///no-host',
        'https://payments.lk/check out',
        r'https://payments.lk\@evil.lk/',
        'https://payments.lk/\u0000',
        '',
      ]) {
        expect(isAllowedCheckoutUrl(url), isFalse, reason: url);
      }
    });
  });

  group('isValidCallbackScheme', () {
    test("takes an app's own lower case scheme", () {
      for (final String scheme in <String>[
        'myshop',
        'lk.shop',
        'my-shop',
        'shop+app'
      ]) {
        expect(isValidCallbackScheme(scheme), isTrue, reason: scheme);
      }
    });

    test('refuses web and script schemes, upper case, and the wrong length',
        () {
      for (final String scheme in <String>[
        'https',
        'http',
        'javascript',
        'intent',
        'file',
        'MyShop',
        'ab',
        '1shop',
        'my shop',
        'a' * 41,
        ''
      ]) {
        expect(isValidCallbackScheme(scheme), isFalse, reason: scheme);
      }
    });
  });

  group('parseCheckoutReturn', () {
    test('reads each outcome and the checkout id', () {
      for (final CheckoutStatus status in <CheckoutStatus>[
        CheckoutStatus.succeeded,
        CheckoutStatus.failed,
        CheckoutStatus.canceled,
        CheckoutStatus.expired
      ]) {
        expect(
          parseCheckoutReturn(
              '$returnBase?checkout=chk_abc123&status=${status.name}',
              'myshop'),
          CheckoutResult(status: status, checkoutId: 'chk_abc123'),
        );
      }
    });

    test(
        'matches the scheme without case, and ignores other parameters and a fragment',
        () {
      expect(
        parseCheckoutReturn(
            'MyShop://payments-lk/return?order=8891&checkout=chk_abc123&status=succeeded#top',
            'myshop'),
        const CheckoutResult(
            status: CheckoutStatus.succeeded, checkoutId: 'chk_abc123'),
      );
    });

    test('refuses anything that is not one well formed outcome in this scheme',
        () {
      for (final String url in <String>[
        'othershop://payments-lk/return?checkout=chk_abc123&status=succeeded',
        'https://payments.lk/return?checkout=chk_abc123&status=succeeded',
        returnBase,
        '$returnBase?status=succeeded',
        '$returnBase?checkout=chk_abc123',
        '$returnBase?checkout=chk_abc123&status=paid',
        '$returnBase?checkout=chk_abc123&status=dismissed',
        '$returnBase?checkout=pay_abc123&status=succeeded',
        '$returnBase?checkout=chk_ABC&status=succeeded',
        '$returnBase?checkout=chk_abc123&checkout=chk_def456&status=succeeded',
        '$returnBase?checkout=chk_abc123&status=succeeded&status=failed',
        '$returnBase?checkout=chk_abc%zz&status=succeeded',
        '$returnBase#?checkout=chk_abc123&status=succeeded',
      ]) {
        expect(parseCheckoutReturn(url, 'myshop'), isNull, reason: url);
      }
    });
  });

  group('PaymentsLkCheckout.open', () {
    test('opens the checkout for the scheme and answers the outcome', () async {
      final FakeBrowser browser =
          FakeBrowser('$returnBase?checkout=chk_abc123&status=succeeded');
      final CheckoutResult result =
          await PaymentsLkCheckout(authenticate: browser.call)
              .open(checkoutUrl: checkoutUrl, callbackScheme: 'myshop');
      expect(
          result,
          const CheckoutResult(
              status: CheckoutStatus.succeeded, checkoutId: 'chk_abc123'));
      expect(browser.opened, <String>[checkoutUrl]);
      expect(browser.schemes, <String>['myshop']);
      expect(browser.ephemeral, <bool>[false]);
    });

    test('passes preferEphemeral through', () async {
      final FakeBrowser browser =
          FakeBrowser('$returnBase?checkout=chk_abc123&status=canceled');
      await PaymentsLkCheckout(authenticate: browser.call).open(
          checkoutUrl: checkoutUrl,
          callbackScheme: 'myshop',
          preferEphemeral: true);
      expect(browser.ephemeral, <bool>[true]);
    });

    test('calls a closed browser dismissed', () async {
      final FakeBrowser browser =
          FakeBrowser(PlatformException(code: 'CANCELED'));
      expect(
        await PaymentsLkCheckout(authenticate: browser.call)
            .open(checkoutUrl: checkoutUrl, callbackScheme: 'myshop'),
        const CheckoutResult(status: CheckoutStatus.dismissed),
      );
    });

    test('refuses a return without an outcome', () {
      final FakeBrowser browser =
          FakeBrowser('$returnBase?checkout=chk_abc123');
      expect(
          PaymentsLkCheckout(authenticate: browser.call)
              .open(checkoutUrl: checkoutUrl, callbackScheme: 'myshop'),
          throwsCode(PaymentsLkErrorCode.unexpectedReturn));
    });

    test('reports a browser that cannot open, keeping the platform error',
        () async {
      final FakeBrowser browser =
          FakeBrowser(PlatformException(code: 'UNAVAILABLE'));
      final Future<CheckoutResult> opening =
          PaymentsLkCheckout(authenticate: browser.call)
              .open(checkoutUrl: checkoutUrl, callbackScheme: 'myshop');
      await expectLater(
        opening,
        throwsA(isA<PaymentsLkCheckoutException>()
            .having((PaymentsLkCheckoutException e) => e.code, 'code',
                PaymentsLkErrorCode.couldNotOpen)
            .having((PaymentsLkCheckoutException e) => e.cause, 'cause',
                isA<PlatformException>())),
      );
    });

    test('refuses an insecure URL or a web scheme before opening anything', () {
      final FakeBrowser browser =
          FakeBrowser('$returnBase?checkout=chk_abc123&status=succeeded');
      final PaymentsLkCheckout checkout =
          PaymentsLkCheckout(authenticate: browser.call);
      expect(
          checkout.open(
              checkoutUrl: 'http://payments.lk/checkout/chk_1',
              callbackScheme: 'myshop'),
          throwsCode(PaymentsLkErrorCode.insecureCheckoutUrl));
      expect(checkout.open(checkoutUrl: checkoutUrl, callbackScheme: 'https'),
          throwsCode(PaymentsLkErrorCode.invalidCallbackScheme));
      expect(browser.opened, isEmpty);
    });

    test('refuses a second checkout while one is open, and opens again after',
        () async {
      final Completer<String> first = Completer<String>();
      final PaymentsLkCheckout checkout = PaymentsLkCheckout(
        authenticate: (
                {required String url,
                required String callbackUrlScheme,
                required bool preferEphemeral}) =>
            first.future,
      );
      final Future<CheckoutResult> opening =
          checkout.open(checkoutUrl: checkoutUrl, callbackScheme: 'myshop');
      await expectLater(
          checkout.open(checkoutUrl: checkoutUrl, callbackScheme: 'myshop'),
          throwsCode(PaymentsLkErrorCode.alreadyOpen));
      first.complete('$returnBase?checkout=chk_abc123&status=failed');
      expect((await opening).status, CheckoutStatus.failed);
      final FakeBrowser browser =
          FakeBrowser('$returnBase?checkout=chk_def456&status=succeeded');
      expect(
          (await PaymentsLkCheckout(authenticate: browser.call)
                  .open(checkoutUrl: checkoutUrl, callbackScheme: 'myshop'))
              .checkoutId,
          'chk_def456');
    });
  });

  group('PaymentsLkCheckout.openPage', () {
    const String link = 'https://payments.lk/s/Gold_Plan-2026';

    test('answers the URL the page returned to', () async {
      final FakeBrowser browser = FakeBrowser('myshop://subscribed?plan=gold');
      expect(
        await PaymentsLkCheckout(authenticate: browser.call)
            .openPage(url: link, callbackScheme: 'myshop'),
        const PageResult(
            status: PageStatus.returned, url: 'myshop://subscribed?plan=gold'),
      );
    });

    test(
        'calls a closed browser dismissed, and refuses a return on another scheme',
        () async {
      expect(
        await PaymentsLkCheckout(
                authenticate:
                    FakeBrowser(PlatformException(code: 'CANCELED')).call)
            .openPage(url: link, callbackScheme: 'myshop'),
        const PageResult(status: PageStatus.dismissed),
      );
      expect(
        PaymentsLkCheckout(authenticate: FakeBrowser('othershop://x').call)
            .openPage(url: link, callbackScheme: 'myshop'),
        throwsCode(PaymentsLkErrorCode.unexpectedReturn),
      );
    });
  });
}
