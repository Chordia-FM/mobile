import '../hub.dart';
import '../json.dart';
import '../models.g.dart';
import 'decode.dart';

/// Plans and subscriptions.
///
/// Money never moves through these calls: [startCheckout] and [billingPortal] hand back a URL to
/// open, and the provider owns everything after that. The account's real state arrives later by
/// webhook, so [billingAccount] is the source of truth rather than whatever the checkout flow
/// appeared to do.
extension BillingEndpoints on HubClient {
  /// The pricing table. Public — it has to render for someone deciding whether to sign up at all.
  Future<PlansResponse> billingPlans() => get(
    '/v1/billing/plans',
    (json) => PlansResponse.fromJson(asObject(json)),
    authenticated: false,
  );

  Future<BillingMe> billingAccount() =>
      get('/v1/billing/me', (json) => BillingMe.fromJson(asObject(json)));

  /// Begins a hosted checkout, answering with the URL to send the user to.
  Future<CheckoutResponse> startCheckout(CheckoutRequest request) => post(
    '/v1/billing/checkout',
    (json) => CheckoutResponse.fromJson(asObject(json)),
    body: request.toJson(),
  );

  /// Moves to another tier or interval. Accepted (202), not applied: the change lands when the
  /// provider confirms it.
  Future<void> changePlan(ChangePlanRequest request) =>
      post<void>('/v1/billing/change', discard, body: request.toJson());

  /// A link into the provider's customer portal, for cards and cancellation.
  Future<PortalResponse> billingPortal() => post(
    '/v1/billing/portal',
    (json) => PortalResponse.fromJson(asObject(json)),
  );
}
