import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/art/art_cache.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';
import '../../widgets/cover_art.dart';
import 'catalog_routes.dart';
import 'data/catalog_api.dart';
import 'data/catalog_providers.dart';
import 'widgets/catalog_state.dart';
import 'widgets/list_row.dart';

/// Browse by label.
class LabelsScreen extends ConsumerWidget {
  const LabelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final labels = ref.watch(labelsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t(CatalogKeys.labelsTitle))),
      body: CatalogBody<List<LabelSummary>>(
        value: labels,
        errorTitle: t(ErrorsKeys.catalogLabelsLoadFailed),
        onRetry: () => ref.invalidate(labelsProvider),
        skeleton: const CatalogDetailSkeleton(),
        builder: (context, value) => value.isEmpty
            ? CatalogEmpty(message: t(CatalogKeys.labelsEmpty))
            : ListView.builder(
                itemCount: value.length,
                itemBuilder: (context, index) {
                  final label = value[index];
                  return ListRow(
                    leading: CoverArt(
                      sha256: artHashOf(label.logoUrl),
                      size: 40,
                      fallbackIcon: Icons.sell_outlined,
                      semanticLabel: label.name,
                    ),
                    title: Text(label.name),
                    subtitle: Text(
                      t(CatalogKeys.albumCount, {'count': label.albumCount}),
                    ),
                    // The "Unlabeled" bucket has no id of its own; the synthetic segment is what
                    // routes it to the Hub's dedicated endpoint.
                    onTap: () =>
                        context.goToLabel(label.id ?? unlabeledLabelId),
                  );
                },
              ),
      ),
    );
  }
}
