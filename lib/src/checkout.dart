import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

/// How a checkout ended, as the customer's return to the app reports it.
enum CheckoutStatus {
  /// The payment went through. Show a confirming screen while your server
  /// confirms it.
  succeeded,

  /// The card was declined or the payment failed.
  failed,

  /// The customer cancelled on the hosted page.
  canceled,

  /// The checkout expired before the customer paid.
  expired,

  /// The customer closed the browser before the checkout finished. Never
  /// read from a return URL.
  dismissed,
}

/// The outcome of [PaymentsLkCheckout.open].
class CheckoutResult {
  /// An outcome, with the checkout's id when the checkout returned to the app.
  const CheckoutResult({required this.status, this.checkoutId});

  /// How the checkout ended.
  final CheckoutStatus status;

  /// The checkout's id (`chk_...`), or null when [status] is
  /// [CheckoutStatus.dismissed].
  final String? checkoutId;

  @override
  bool operator ==(Object other) =>
      other is CheckoutResult &&
      other.status == status &&
      other.checkoutId == checkoutId;

  @override
  int get hashCode => Object.hash(status, checkoutId);

  @override
  String toString() =>
      'CheckoutResult(status: ${status.name}, checkoutId: $checkoutId)';
}

/// Why a checkout or page could not be opened, or came back wrong.
enum PaymentsLkErrorCode {
  /// The checkout or page URL is not https, or carries credentials.
  insecureCheckoutUrl,

  /// The callback scheme is not an app's own scheme, such as `myshop`.
  invalidCallbackScheme,

  /// Another checkout or page is already open.
  alreadyOpen,

  /// The browser came back to the app without a well formed outcome.
  unexpectedReturn,

  /// The system browser could not be opened.
  couldNotOpen,

  /// A subscription link's code or plan is not shaped like one.
  invalidLink,
}

/// Thrown by [PaymentsLkCheckout] for a checkout it cannot open, or a return
/// it cannot read.
class PaymentsLkCheckoutException implements Exception {
  /// An error with its [code], a sentence for developers, and what caused it.
  const PaymentsLkCheckoutException(this.code, this.message, {this.cause});

  /// What went wrong, for code to branch on.
  final PaymentsLkErrorCode code;

  /// A sentence for developers. Not meant for customers.
  final String message;

  /// The platform error behind it, when there was one.
  final Object? cause;

  @override
  String toString() => 'PaymentsLkCheckoutException(${code.name}): $message';
}

/// Opens [url] in the system's authentication browser and completes with the
/// URL in [callbackUrlScheme] it returned to. The default is
/// `FlutterWebAuth2.authenticate`: `ASWebAuthenticationSession` on iOS and a
/// Custom Tab on Android. Pass another to [PaymentsLkCheckout] in tests.
typedef WebAuthenticate = Future<String> Function({
  required String url,
  required String callbackUrlScheme,
  required bool preferEphemeral,
});

Future<String> _flutterWebAuth2({
  required String url,
  required String callbackUrlScheme,
  required bool preferEphemeral,
}) {
  return FlutterWebAuth2.authenticate(
    url: url,
    callbackUrlScheme: callbackUrlScheme,
    options: FlutterWebAuth2Options(preferEphemeral: preferEphemeral),
  );
}

final RegExp _scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):');
final RegExp _appScheme = RegExp(r'^[a-z][a-z0-9+.-]{2,39}$');
const Set<String> _refusedSchemes = <String>{
  'http',
  'https',
  'javascript',
  'data',
  'vbscript',
  'file',
  'blob',
  'about',
  'intent',
};
final RegExp _checkoutId = RegExp(r'^chk_[0-9a-z]{1,64}$');
const Map<String, CheckoutStatus> _outcomes = <String, CheckoutStatus>{
  'succeeded': CheckoutStatus.succeeded,
  'failed': CheckoutStatus.failed,
  'canceled': CheckoutStatus.canceled,
  'expired': CheckoutStatus.expired,
};

String? _schemeOf(String url) =>
    _scheme.firstMatch(url)?.group(1)?.toLowerCase();

bool _hasSpaceOrControl(String value) =>
    value.codeUnits.any((int unit) => unit <= 0x20 || unit == 0x7f);

/// Whether [scheme] can be an app's callback scheme: 3 to 40 lower case
/// letters, digits, `+`, `.` or `-`, starting with a letter, and not a web
/// or script scheme. Android matches schemes in lower case only.
bool isValidCallbackScheme(String scheme) =>
    _appScheme.hasMatch(scheme) && !_refusedSchemes.contains(scheme);

/// Whether [url] can be opened as a hosted checkout: https without
/// credentials, or plain http on this machine or on the Android emulator's
/// host, for testing against a local server.
bool isAllowedCheckoutUrl(String url) {
  if (_hasSpaceOrControl(url) || url.contains(r'\')) return false;
  final RegExpMatch? match =
      RegExp(r'^(https?)://([^/?#]*)', caseSensitive: false).firstMatch(url);
  final String? scheme = match?.group(1)?.toLowerCase();
  final String? authority = match?.group(2);
  if (scheme == null || authority == null || authority.isEmpty) return false;
  if (authority.contains('@')) return false;
  if (scheme == 'https') return true;
  final String host =
      authority.replaceFirst(RegExp(r':[0-9]{1,5}$'), '').toLowerCase();
  return host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2';
}

/// The outcome in a return [url], or null for anything that is not a well
/// formed return in [callbackScheme]: exactly one `checkout` (`chk_...`) and
/// exactly one `status` (`succeeded`, `failed`, `canceled` or `expired`).
CheckoutResult? parseCheckoutReturn(String url, String callbackScheme) {
  if (_schemeOf(url) != callbackScheme.toLowerCase()) return null;
  // The query is what follows the first ?, up to a #. A ? after the # is part of the fragment, not a query.
  final int start = url.indexOf('?');
  final int hash = url.indexOf('#');
  if (start == -1 || (hash != -1 && hash < start)) return null;
  final int end = hash == -1 ? url.length : hash;
  final String query = url.substring(start + 1, end);

  final Map<String, List<String>> values = <String, List<String>>{};
  for (final String pair in query.split('&')) {
    if (pair.isEmpty) continue;
    final int eq = pair.indexOf('=');
    String key;
    String value;
    try {
      key = Uri.decodeQueryComponent(eq == -1 ? pair : pair.substring(0, eq));
      value = Uri.decodeQueryComponent(eq == -1 ? '' : pair.substring(eq + 1));
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
    values.putIfAbsent(key, () => <String>[]).add(value);
  }

  final List<String>? ids = values['checkout'];
  final List<String>? statuses = values['status'];
  if (ids == null ||
      ids.length != 1 ||
      statuses == null ||
      statuses.length != 1) {
    return null;
  }
  final CheckoutStatus? status = _outcomes[statuses.single];
  if (!_checkoutId.hasMatch(ids.single) || status == null) return null;
  return CheckoutResult(status: status, checkoutId: ids.single);
}

/// Whether a page came back to the app, from [PaymentsLkCheckout.openPage].
enum PageStatus {
  /// The page sent the browser back to the app's scheme.
  returned,

  /// The customer closed the browser instead.
  dismissed,
}

/// The outcome of [PaymentsLkCheckout.openPage].
class PageResult {
  /// An outcome, with the URL the page returned to.
  const PageResult({required this.status, this.url});

  /// Whether the page came back.
  final PageStatus status;

  /// The URL the page returned to, or null when dismissed. Its query is the
  /// page's own and never proof of anything.
  final String? url;

  @override
  bool operator ==(Object other) =>
      other is PageResult && other.status == status && other.url == url;

  @override
  int get hashCode => Object.hash(status, url);

  @override
  String toString() => 'PageResult(status: ${status.name}, url: $url)';
}

/// Opens Payments.lk hosted pages in the system's authentication browser.
class PaymentsLkCheckout {
  /// A checkout opener. [authenticate] replaces the system browser, for
  /// tests.
  PaymentsLkCheckout({WebAuthenticate? authenticate})
      : _authenticate = authenticate ?? _flutterWebAuth2;

  final WebAuthenticate _authenticate;

  // One sheet at a time across the whole app, as the system allows.
  static bool _presenting = false;

  /// Opens `checkout.url` from your server and completes with how the
  /// checkout ended.
  ///
  /// [callbackScheme] is your app's scheme, the one your server used in the
  /// checkout's `successUrl` and `cancelUrl`, such as `myshop` for
  /// `myshop://payments-lk/return`. On Android the app must declare it for
  /// `flutter_web_auth_2`'s `CallbackActivity`; the README shows how.
  ///
  /// Completes with [CheckoutStatus.dismissed] when the customer closes the
  /// browser. Throws [PaymentsLkCheckoutException] for a URL or scheme that
  /// is refused, a second checkout while one is open, a system browser that
  /// cannot open, or a return without an outcome.
  Future<CheckoutResult> open({
    required String checkoutUrl,
    required String callbackScheme,
    bool preferEphemeral = false,
  }) async {
    _check(checkoutUrl, callbackScheme);
    final String? returned =
        await _present(checkoutUrl, callbackScheme, preferEphemeral);
    if (returned == null) {
      return const CheckoutResult(status: CheckoutStatus.dismissed);
    }
    final CheckoutResult? result =
        parseCheckoutReturn(returned, callbackScheme);
    if (result == null) {
      throw const PaymentsLkCheckoutException(
        PaymentsLkErrorCode.unexpectedReturn,
        'The checkout returned to the app without an outcome.',
      );
    }
    return result;
  }

  /// Opens a hosted page that has no checkout of its own to report: a
  /// subscription link (see [subscriptionLinkUrl]) or a customer portal
  /// session's `url`. Completes when the page returns to [callbackScheme],
  /// or with [PageStatus.dismissed] when the customer closes the browser.
  Future<PageResult> openPage({
    required String url,
    required String callbackScheme,
    bool preferEphemeral = false,
  }) async {
    _check(url, callbackScheme);
    final String? returned =
        await _present(url, callbackScheme, preferEphemeral);
    if (returned == null) return const PageResult(status: PageStatus.dismissed);
    if (_schemeOf(returned) != callbackScheme.toLowerCase()) {
      throw const PaymentsLkCheckoutException(
        PaymentsLkErrorCode.unexpectedReturn,
        'The page returned to the app on another scheme.',
      );
    }
    return PageResult(status: PageStatus.returned, url: returned);
  }

  void _check(String url, String callbackScheme) {
    if (!isAllowedCheckoutUrl(url)) {
      throw const PaymentsLkCheckoutException(
        PaymentsLkErrorCode.insecureCheckoutUrl,
        'The URL must be https. Use checkout.url exactly as your server received it.',
      );
    }
    if (!isValidCallbackScheme(callbackScheme)) {
      throw const PaymentsLkCheckoutException(
        PaymentsLkErrorCode.invalidCallbackScheme,
        "The callback scheme must be your app's own, such as myshop for myshop://payments-lk/return.",
      );
    }
  }

  /// The URL the browser returned to, or null when the customer closed it.
  Future<String?> _present(
      String url, String callbackScheme, bool preferEphemeral) async {
    if (_presenting) {
      throw const PaymentsLkCheckoutException(
        PaymentsLkErrorCode.alreadyOpen,
        'A checkout is already open.',
      );
    }
    _presenting = true;
    try {
      return await _authenticate(
        url: url,
        callbackUrlScheme: callbackScheme,
        preferEphemeral: preferEphemeral,
      );
    } on PlatformException catch (error) {
      if (error.code == 'CANCELED') return null;
      throw PaymentsLkCheckoutException(
        PaymentsLkErrorCode.couldNotOpen,
        'The checkout could not be opened.',
        cause: error,
      );
    } on PaymentsLkCheckoutException {
      rethrow;
    } catch (error) {
      throw PaymentsLkCheckoutException(
        PaymentsLkErrorCode.couldNotOpen,
        'The checkout could not be opened.',
        cause: error,
      );
    } finally {
      _presenting = false;
    }
  }
}
