import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../catalog/widgets/list_row.dart';
import 'data/settings_messages.dart';
import 'data/settings_providers.dart';
import 'data/settings_values.dart';
import 'widgets/settings_list.dart';

/// What this account's plan is, and what it includes.
///
/// **Nothing is bought here.** Every path that costs money hands off to the Hub's own hosted
/// checkout in the system browser: card details never touch this app, and the plan only changes
/// when the provider's signed webhook says it did — which is why the state below is re-read from
/// the Hub rather than assumed from whatever the checkout appeared to do.
class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final plan = ref.watch(planStateProvider);

    return SettingsScaffold(
      title: t(SettingsKeys.planTitle),
      onRefresh: () async => ref.invalidate(planStateProvider),
      children: [
        SettingsBody<(BillingMe, PlansResponse)>(
          value: plan,
          onRetry: () => ref.invalidate(planStateProvider),
          builder: (context, value) {
            final (account, plans) = value;
            // A Hub with no payment provider says so and shows nothing else. A self-hoster must
            // never meet a pricing table on their own machine.
            if (account.entitlements.billingEnabled == false) {
              return SettingsSection(
                title: t(SettingsKeys.planTitle),
                children: [SettingsNote(t(SettingsKeys.planSelfHosted))],
              );
            }
            return Column(
              children: [
                _CurrentPlan(account: account),
                _Entitlements(entitlements: account.entitlements),
                _PlanTable(account: account, plans: plans),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CurrentPlan extends ConsumerWidget {
  const _CurrentPlan({required this.account});

  final BillingMe account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final locale = ref.watch(translationsProvider).locale;
    final entitlements = account.entitlements;
    final tier = entitlements.tier ?? PlanTier.free;

    String? date(int? epochMillis) => epochMillis == null
        ? null
        : DateFormat.yMMMd(
            locale,
          ).format(DateTime.fromMillisecondsSinceEpoch(epochMillis));

    final periodEnd = date(account.currentPeriodEnd);
    final since = date(entitlements.premiumSince);

    // "Cancelled" is not "expired": a cancelled subscription keeps everything until the period
    // already paid for runs out, and saying so is the difference between "I turned off renewal"
    // and "I have lost this".
    final body = switch (tier) {
      PlanTier.free => t(BillingKeys.planFreeBody),
      _ when account.cancelAtPeriodEnd == true && periodEnd != null => t(
        BillingKeys.planCancellingBody,
        {'date': periodEnd},
      ),
      _ when periodEnd != null => t(BillingKeys.planRenewsBody, {
        'date': periodEnd,
      }),
      _ => t(BillingKeys.planComplimentary),
    };

    return SettingsSection(
      title: t(SettingsKeys.planCurrent),
      children: [
        ListRow(
          gutter: 0,
          subtitleMaxLines: 3,
          leading: Icon(
            PhosphorIconsFill.crown,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(tierName(tier)),
          subtitle: Text(
            [
              body,
              if (since != null) t(BillingKeys.planSince, {'date': since}),
              if (entitlements.complimentary == true)
                t(BillingKeys.planComplimentary),
            ].join('\n'),
          ),
        ),
        if (account.hasCustomer == true)
          SettingsDisclosureRow(
            icon: PhosphorIconsRegular.receipt,
            label: t(BillingKeys.planManage),
            description: t(BillingKeys.planManageHint),
            onTap: () => _openPortal(context, ref),
          ),
      ],
    );
  }

  Future<void> _openPortal(BuildContext context, WidgetRef ref) async {
    final api = ref.read(planApiProvider);
    if (api == null) return;
    final t = ref.read(translationsProvider).call;
    try {
      final portal = await api.portal();
      if (!context.mounted) return;
      await _openExternally(context, Uri.parse(portal.url), t);
    } on Object catch (error) {
      if (!context.mounted) return;
      showSettingsMessage(context, describeSettingsError(error, t));
    }
  }
}

class _Entitlements extends ConsumerWidget {
  const _Entitlements({required this.entitlements});

  final Entitlements entitlements;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final features = entitlements.features ?? const <Feature>[];
    final retention = entitlements.retentionDays;
    return SettingsSection(
      title: t(SettingsKeys.planIncludes),
      children: [
        for (final feature in features)
          ListRow(
            gutter: 0,
            leading: Icon(
              PhosphorIconsBold.check,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(t(featureNameKey(feature))),
          ),
        ListRow(
          gutter: 0,
          leading: const Icon(
            PhosphorIconsRegular.clockCounterClockwise,
            size: 20,
          ),
          title: Text(t(BillingKeys.featuresRetentionName)),
          // No limit is the perk, so it is named rather than left blank. Rounded to years exactly
          // as the web's plan table rounds it, so the same account is not told two different
          // things by two Chordia clients.
          trailing: Text(
            retention == null
                ? t(BillingKeys.plansForever)
                : t(BillingKeys.plansYears, {
                    'count': (retention / 365).round(),
                  }),
          ),
        ),
      ],
    );
  }
}

class _PlanTable extends ConsumerStatefulWidget {
  const _PlanTable({required this.account, required this.plans});

  final BillingMe account;
  final PlansResponse plans;

  @override
  ConsumerState<_PlanTable> createState() => _PlanTableState();
}

class _PlanTableState extends ConsumerState<_PlanTable> {
  BillingInterval _interval = BillingInterval.monthly;
  bool _busy = false;

  /// Sends the browser to a hosted checkout.
  ///
  /// Deliberately not an in-app purchase flow: the Hub's provider owns the payment, and the app
  /// never sees a card number or a price it could get wrong.
  Future<void> _checkout(PlanTier tier) async {
    final api = ref.read(planApiProvider);
    if (api == null || tier == PlanTier.free) return;
    final t = ref.read(translationsProvider).call;
    setState(() => _busy = true);
    try {
      final session = await api.startCheckout(
        CheckoutRequest(tier: tier, interval: _interval),
      );
      if (!mounted) return;
      await _openExternally(context, Uri.parse(session.checkoutUrl), t);
    } on Object catch (error) {
      if (!mounted) return;
      showSettingsMessage(context, describeSettingsError(error, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final current = widget.account.entitlements.tier ?? PlanTier.free;
    return SettingsSection(
      title: t(BillingKeys.plansTitle),
      description: t(SettingsKeys.planOpensInBrowser),
      children: [
        SettingsChoiceRow<BillingInterval>(
          label: t(BillingKeys.plansIntervalLabel),
          value: _interval,
          options: [
            (BillingInterval.monthly, t(BillingKeys.plansMonthly)),
            (BillingInterval.yearly, t(BillingKeys.plansYearly)),
          ],
          onChanged: (interval) => setState(() => _interval = interval),
        ),
        for (final plan in widget.plans.plans)
          _PlanRow(
            plan: plan,
            interval: _interval,
            current: plan.tier == current,
            // An interval the operator never configured a product for is one the Hub cannot
            // start a checkout on, and the absence of the product id is how a client knows.
            onChoose:
                _busy ||
                    plan.tier == current ||
                    _productFor(plan, _interval) == null
                ? null
                : () => _checkout(plan.tier),
          ),
      ],
    );
  }
}

String? _productFor(PlanInfo plan, BillingInterval interval) =>
    interval == BillingInterval.monthly
    ? plan.monthlyProductId
    : plan.yearlyProductId;

class _PlanRow extends ConsumerWidget {
  const _PlanRow({
    required this.plan,
    required this.interval,
    required this.current,
    required this.onChoose,
  });

  final PlanInfo plan;
  final BillingInterval interval;
  final bool current;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final locale = ref.watch(translationsProvider).locale;
    // Minor units, so no float ever touches a price.
    final cents = interval == BillingInterval.monthly
        ? plan.monthlyPriceCents
        : plan.yearlyPriceCents;
    final amount = NumberFormat.simpleCurrency(
      locale: locale,
      name: plan.currency,
    ).format(cents / 100);

    return ListRow(
      gutter: 0,
      title: Text(tierName(plan.tier)),
      subtitle: Text(
        t(
          interval == BillingInterval.monthly
              ? BillingKeys.plansPerMonth
              : BillingKeys.plansPerYear,
          {'amount': amount},
        ),
      ),
      trailing: current
          ? Text(t(BillingKeys.plansCurrent))
          : FilledButton(
              onPressed: onChoose,
              child: Text(t(BillingKeys.plansUpgrade)),
            ),
    );
  }
}

/// Opens a payment-provider URL in the system browser, saying so if nothing will take it.
Future<void> _openExternally(BuildContext context, Uri url, Translate t) async {
  final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
  if (opened || !context.mounted) return;
  showSettingsMessage(context, t(AuthKeys.desktopCannotOpenBrowser));
}
