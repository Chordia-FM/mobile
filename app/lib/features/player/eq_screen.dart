import 'dart:async';

import 'package:chordia_api/chordia_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/playback/eq.dart';
import '../settings/data/settings_providers.dart';
import '../../i18n/keys.g.dart';
import '../../i18n/translations_provider.dart';

/// Opens the equalizer over everything, the way the full player opens.
void openEqualizer(BuildContext context) => Navigator.of(
  context,
  rootNavigator: true,
).push(MaterialPageRoute<void>(builder: (_) => const EqScreen()));

/// The ten-band equalizer.
///
/// The controls are exact parity with the web client — same frequencies, same Q, same presets, same
/// stored document — and the screen says plainly that what reaches the speakers is not. See
/// `data/playback/eq.dart` for why the applied response is an approximation, and
/// [PlayerKeys.equalizerDeviceApproximation] for what the listener is told about it.
class EqScreen extends ConsumerStatefulWidget {
  const EqScreen({super.key});

  @override
  ConsumerState<EqScreen> createState() => _EqScreenState();
}

class _EqScreenState extends ConsumerState<EqScreen> {
  /// The curve being edited. Local, because a slider has to move at sixty frames a second and the
  /// Hub is not going to keep up with that.
  EqConfig? _draft;

  Timer? _save;

  /// Long enough that dragging a slider across its travel is one write, short enough that leaving
  /// the screen straight after a change has already saved.
  static const _debounce = Duration(milliseconds: 600);

  @override
  void dispose() {
    _save?.cancel();
    super.dispose();
  }

  EqConfig get _config => _draft ?? defaultEq;

  void _edit(EqConfig next) {
    setState(() => _draft = next);
    // Heard immediately; stored on a delay. The two are separate because a listener dragging a
    // slider expects the sound to move under their finger, not after the network settles.
    unawaited(ref.read(eqSinkProvider)(next));
    _save?.cancel();
    _save = Timer(_debounce, _persist);
  }

  Future<void> _persist() async {
    final api = ref.read(settingsApiProvider);
    final base = ref.read(userSettingsProvider).value;
    if (api == null || base == null) return;
    try {
      // Through JSON rather than a field-by-field copy, for the reason `SettingsPatch` gives: the
      // Hub owns this shape, and a field this build has never heard of has to survive the round
      // trip rather than be dropped by a copy constructor that predates it.
      await api.write(
        UserSettings.fromJson({...base.toJson(), 'eq': _config.toJson()}),
      );
      ref.invalidate(userSettingsProvider);
    } on ApiException {
      // A curve that failed to store is still the curve being heard. Losing the edit on screen
      // would be a worse answer than a setting that syncs on the next change.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.t;
    final settings = ref.watch(userSettingsProvider);

    // Adopted once, from the first settled read. Re-adopting on every rebuild would fight the
    // finger currently on a slider, because the debounced write has not landed yet.
    if (_draft == null && settings.hasValue) {
      _draft = settings.value?.eq ?? defaultEq;
    }

    return Scaffold(
      backgroundColor: context.surfaces.pane,
      appBar: AppBar(title: Text(t(PlayerKeys.equalizerTitle))),
      body: settings.isLoading && _draft == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                _CurveCard(config: _config),
                const SizedBox(height: 12),
                _Caveat(
                  text: eqAppliesHere
                      ? t(PlayerKeys.equalizerDeviceApproximation)
                      : t(PlayerKeys.equalizerNotApplied),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t(PlayerKeys.equalizerEnable)),
                  value: enabledOf(_config),
                  onChanged: (on) => _edit(
                    EqConfig(
                      enabled: on,
                      preamp: preampOf(_config),
                      bands: bandsOf(_config),
                    ),
                  ),
                ),
                _PresetPicker(
                  config: _config,
                  onPick: (preset) => _edit(
                    EqConfig(
                      enabled: enabledOf(_config),
                      preamp: preset.preamp,
                      bands: preset.bands,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _PreampSlider(
                  value: preampOf(_config),
                  onChanged: (value) => _edit(
                    EqConfig(
                      enabled: enabledOf(_config),
                      preamp: value,
                      bands: bandsOf(_config),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _Bands(
                  bands: bandsOf(_config),
                  onChanged: (index, gain) {
                    final bands = [...bandsOf(_config)];
                    bands[index] = EqBand(
                      freq: bands[index].freq,
                      gain: gain,
                      q: bands[index].q,
                    );
                    _edit(
                      EqConfig(
                        enabled: enabledOf(_config),
                        preamp: preampOf(_config),
                        bands: bands,
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }
}

/// The combined response, drawn from the same analytic function that decides what the device
/// equalizer is asked for.
class _CurveCard extends StatelessWidget {
  const _CurveCard({required this.config});

  final EqConfig config;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: ColoredBox(
      color: context.surfaces.paneRaised,
      child: SizedBox(
        height: 160,
        width: double.infinity,
        child: CustomPaint(
          painter: _CurvePainter(
            bands: bandsOf(config),
            preamp: preampOf(config),
            dimmed: !enabledOf(config),
            // A painter has no context of its own, so the two accent-derived colours are handed
            // in — and compared in `shouldRepaint`, or the curve keeps the old accent after a
            // colour change until something else invalidates it.
            accent: context.surfaces.accent,
            line: context.surfaces.line,
          ),
        ),
      ),
    ),
  );
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.bands,
    required this.preamp,
    required this.dimmed,
    required this.accent,
    required this.line,
  });

  final List<EqBand> bands;
  final double preamp;
  final bool dimmed;
  final Color accent;
  final Color line;

  /// Half-height of the plot in dB. Wider than the ±12 the sliders reach, so a stack of boosted
  /// neighbours has somewhere to go instead of being clipped flat at the top.
  static const double _range = 18;

  static final _freqs = logFreqs(120);

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final zero = Paint()
      ..color = line
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), zero);

    final curve = eqCurveDb(bands, preamp, _freqs);
    final path = Path();
    for (var i = 0; i < curve.length; i++) {
      final x = size.width * i / (curve.length - 1);
      final y = mid - (curve[i].clamp(-_range, _range) / _range) * (mid - 8);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..color = accent.withValues(alpha: dimmed ? 0.3 : 1),
    );
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) =>
      old.preamp != preamp ||
      old.dimmed != dimmed ||
      old.accent != accent ||
      old.line != line ||
      !eqMatches(old.bands, old.preamp, bands, preamp);
}

class _Caveat extends StatelessWidget {
  const _Caveat({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 2, right: 8),
        child: Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: ChordiaColors.mutedForeground,
        ),
      ),
      Expanded(
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: ChordiaColors.mutedForeground),
        ),
      ),
    ],
  );
}

class _PresetPicker extends ConsumerWidget {
  const _PresetPicker({required this.config, required this.onPick});

  final EqConfig config;
  final void Function(BuiltInPreset) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    final active = matchingPreset(config);

    return DropdownButtonFormField<String>(
      initialValue: active?.name,
      decoration: InputDecoration(
        labelText: t(PlayerKeys.equalizerPresetSelect),
        border: const OutlineInputBorder(),
      ),
      // The listener's own curve is a real state, not a missing preset: without this entry the
      // field would sit empty the moment anyone touches a slider.
      hint: Text(t(PlayerKeys.equalizerPresetCustom)),
      items: [
        for (final preset in builtInPresets)
          DropdownMenuItem(value: preset.name, child: Text(t(preset.labelKey))),
      ],
      onChanged: (name) {
        final preset = builtInPresets.firstWhere((p) => p.name == name);
        onPick(preset);
      },
    );
  }
}

class _PreampSlider extends ConsumerWidget {
  const _PreampSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return Row(
      children: [
        SizedBox(width: 72, child: Text(t(PlayerKeys.equalizerPreamp))),
        Expanded(
          child: Slider(
            value: value.clamp(-eqGainRange, eqGainRange),
            min: -eqGainRange,
            max: eqGainRange,
            divisions: (eqGainRange * 4).round(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(
            t(PlayerKeys.equalizerPreampDisplay, {
              'value': value.toStringAsFixed(1),
            }),
            textAlign: TextAlign.end,
            style: const TextStyle(color: ChordiaColors.mutedForeground),
          ),
        ),
      ],
    );
  }
}

/// The ten sliders, scrolled sideways: ten vertical faders will not fit a phone at a usable width.
class _Bands extends ConsumerWidget {
  const _Bands({required this.bands, required this.onChanged});

  final List<EqBand> bands;
  final void Function(int index, double gain) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.t;
    return SizedBox(
      height: 240,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: bands.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, i) => SizedBox(
          width: 56,
          child: Column(
            children: [
              Text(
                t(PlayerKeys.equalizerPreampDisplay, {
                  'value': bands[i].gain.toStringAsFixed(1),
                }),
                style: const TextStyle(
                  fontSize: 11,
                  color: ChordiaColors.mutedForeground,
                ),
              ),
              Expanded(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Slider(
                    value: bands[i].gain.clamp(-eqGainRange, eqGainRange),
                    min: -eqGainRange,
                    max: eqGainRange,
                    divisions: (eqGainRange * 4).round(),
                    label: bands[i].gain.toStringAsFixed(1),
                    onChanged: (gain) => onChanged(i, gain),
                  ),
                ),
              ),
              Text(
                t(PlayerKeys.equalizerFreqDisplay, {
                  'freq': _shortHz(bands[i].freq),
                }),
                style: const TextStyle(
                  fontSize: 11,
                  color: ChordiaColors.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 16000 reads as "16k" under a fader; the full number does not fit and does not help.
String _shortHz(double freq) => freq >= 1000
    ? '${(freq / 1000).toStringAsFixed(0)}k'
    : freq.toStringAsFixed(0);
