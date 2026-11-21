import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/l10n_ext.dart';
import 'kanade_dialog.dart';

/// 选一个不透明颜色（ARGB），取消时返回 null。
Future<int?> showColorPicker(
  BuildContext context, {
  required String title,
  required int initial,
}) => showKanadeDialog<int>(
  context,
  builder: (context) => _ColorPickerDialog(title: title, initial: initial),
);

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.title, required this.initial});

  final String title;
  final int initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(Color(widget.initial));
  late final _hex = TextEditingController(text: _hexOf(_hsv));

  static String _hexOf(HSVColor hsv) => (hsv.toColor().toARGB32() & 0xFFFFFF)
      .toRadixString(16)
      .padLeft(6, '0')
      .toUpperCase();

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _slide(HSVColor hsv) {
    setState(() => _hsv = hsv);
    _hex.text = _hexOf(hsv);
  }

  void _typed(String text) {
    if (text.length != 6) return;
    final rgb = int.tryParse(text, radix: 16);
    if (rgb == null) return;
    setState(() => _hsv = HSVColor.fromColor(Color(0xFF000000 | rgb)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final color = _hsv.toColor();
    void submit() => Navigator.of(context).pop(color.toARGB32());
    return KanadeDialog(
      icon: Icons.palette_outlined,
      title: widget.title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _hex,
                  maxLength: 6,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
                  ],
                  decoration: kanadeFieldDecoration(context)
                      .copyWith(prefixText: '#', counterText: ''),
                  onChanged: _typed,
                  onSubmitted: (_) => submit(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _GradientSlider(
            label: l.colorHue,
            value: _hsv.hue / 360,
            colors: [
              for (var h = 0; h <= 360; h += 60)
                HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
            ],
            onChanged: (v) => _slide(_hsv.withHue(v * 360)),
          ),
          const SizedBox(height: 12),
          _GradientSlider(
            label: l.colorSaturation,
            value: _hsv.saturation,
            colors: [
              _hsv.withSaturation(0).toColor(),
              _hsv.withSaturation(1).toColor(),
            ],
            onChanged: (v) => _slide(_hsv.withSaturation(v)),
          ),
          const SizedBox(height: 12),
          _GradientSlider(
            label: l.colorBrightness,
            value: _hsv.value,
            colors: [Colors.black, _hsv.withValue(1).toColor()],
            onChanged: (v) => _slide(_hsv.withValue(v)),
          ),
        ],
      ),
      actions: [
        KanadeDialogAction(label: l.ok, primary: true, onPressed: submit),
        KanadeDialogAction(
          label: l.cancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// 轨道画成渐变，让人一眼看出往哪边拖会变成什么颜色。
class _GradientSlider extends StatelessWidget {
  const _GradientSlider({
    required this.label,
    required this.value,
    required this.colors,
    required this.onChanged,
  });

  static const _thumb = 13.0;
  static const _track = 18.0;

  final String label;
  final double value;
  final List<Color> colors;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _thumb),
            child: Container(
              height: _track,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: colors),
                borderRadius: BorderRadius.circular(_track / 2),
              ),
            ),
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: _track,
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: Colors.white,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: _thumb,
                elevation: 2,
              ),
            ),
            child: Slider(
              value: value.clamp(0, 1),
              padding: const EdgeInsets.symmetric(horizontal: _thumb),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
