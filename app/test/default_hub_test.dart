import 'package:chordia_api/chordia_api.dart';
import 'package:chordia_mobile/app/config.dart';
import 'package:chordia_mobile/app/providers.dart';
import 'package:chordia_mobile/data/hub_probe.dart';
import 'package:chordia_mobile/data/hub_registry.dart';
import 'package:chordia_mobile/data/secret_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The instance document the real Hub serves, shape for shape.
InstanceInfo instance() => const InstanceInfo(
  discordOauth: true,
  frontendUrl: 'https://chordia.dev',
  name: 'chordia.dev',
  socialEnabled: true,
  version: '0.1.0',
);

ProviderContainer containerWith({
  required SecretStore secrets,
  required Future<InstanceInfo> Function(Uri) fetch,
  String defaultHub = 'https://api.chordia.dev',
}) {
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        AppConfig(
          flavor: 'test',
          defaultHubUrl: defaultHub,
          allowInsecureHubs: false,
        ),
      ),
      secretStoreProvider.overrideWithValue(secrets),
      hubProbeProvider.overrideWithValue(
        HubProbe(allowInsecureHubs: false, fetch: fetch),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('the default hub', () {
    test('is seeded on a first launch, with everything a hub needs', () async {
      // The bug this pins: a hub seeded as a bare URL looks present in the picker and then cannot
      // do half of what the picker implies. Browser sign-in needs the website address, and the
      // Discord button needs to know the server offers it — neither is in the URL.
      final container = containerWith(
        secrets: MemorySecretStore(),
        fetch: (_) async => instance(),
      );

      final snapshot = await container.read(hubsProvider.future);
      final hub = snapshot.active;

      expect(hub, isNotNull);
      expect(
        hub!.frontendUrl,
        Uri.parse('https://chordia.dev'),
        reason:
            'browser sign-in sends people here; without it the button refuses',
      );
      expect(
        hub.name,
        'chordia.dev',
        reason: 'the name the server reports, not the host that was dialled',
      );
      expect(hub.discordOauth, isTrue);
    });

    test('is not seeded when the probe cannot reach it', () async {
      // Better an empty picker than a half-formed record: the empty one invites the single action
      // that fixes it, and a stored husk would never learn the rest.
      final secrets = MemorySecretStore();
      final container = containerWith(
        secrets: secrets,
        fetch: (_) async => throw const ApiException(
          status: 0,
          title: 'offline',
          method: 'GET',
          path: '/v1/instance',
        ),
      );

      final snapshot = await container.read(hubsProvider.future);

      expect(snapshot.hubs, isEmpty);
      expect(
        await SecretsHubRegistry(secrets).isPristine(),
        isTrue,
        reason: 'nothing written, so the next launch tries again',
      );
    });

    test('is not put back after somebody removes it', () async {
      var probes = 0;
      final secrets = MemorySecretStore();
      final first = containerWith(
        secrets: secrets,
        fetch: (_) async {
          probes++;
          return instance();
        },
      );
      final seeded = await first.read(hubsProvider.future);
      await SecretsHubRegistry(secrets).remove(seeded.active!.id);

      // A second launch against the same storage.
      final second = containerWith(
        secrets: secrets,
        fetch: (_) async {
          probes++;
          return instance();
        },
      );
      final snapshot = await second.read(hubsProvider.future);

      expect(snapshot.hubs, isEmpty);
      expect(probes, 1, reason: 'the second launch did not even ask');
    });

    test('a build with no default configured seeds nothing', () async {
      final container = containerWith(
        secrets: MemorySecretStore(),
        defaultHub: '',
        fetch: (_) async => fail('nothing should be probed'),
      );

      expect((await container.read(hubsProvider.future)).hubs, isEmpty);
    });
  });
}
