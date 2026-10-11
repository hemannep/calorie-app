import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/ui.dart';

const captureModes = ['Text', 'Photo', 'Voice', 'Barcode'];

double captureBarHeight(BuildContext context) =>
    68 +
    (MediaQuery.textScalerOf(context).scale(11) - 11).clamp(
          0,
          double.infinity,
        ) *
        1.25;

/// The same control stays mounted while the capture content changes.
class CaptureModeBar extends StatefulWidget {
  const CaptureModeBar({
    super.key,
    required this.selected,
    required this.onSelect,
  });
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  State<CaptureModeBar> createState() => _CaptureModeBarState();
}

class _CaptureModeBarState extends State<CaptureModeBar> {
  int? hovered, dragging;

  @override
  Widget build(BuildContext context) {
    final selected = captureModes.indexOf(widget.selected);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240);
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        onHorizontalDragStart: (details) => setState(() {
          dragging = (details.localPosition.dx / (constraints.maxWidth / 4))
              .floor()
              .clamp(0, 3);
        }),
        onHorizontalDragUpdate: (details) => setState(() {
          dragging = (details.localPosition.dx / (constraints.maxWidth / 4))
              .floor()
              .clamp(0, 3);
        }),
        onHorizontalDragCancel: () => setState(() => dragging = null),
        onHorizontalDragEnd: (_) {
          final next = dragging;
          setState(() => dragging = null);
          if (next != null) widget.onSelect(captureModes[next]);
        },
        child: Container(
          key: const Key('capture-mode-bar'),
          height: captureBarHeight(context),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .18),
                blurRadius: 28,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF12271F).withValues(
                    alpha: MediaQuery.highContrastOf(context) ? .95 : .58,
                  ),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .16),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: .12),
                      Colors.white.withValues(alpha: .035),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: AnimatedAlign(
                          duration: duration,
                          curve: Curves.easeOutCubic,
                          alignment: Alignment(
                            -1 + (dragging ?? selected) * 2 / 3,
                            0,
                          ),
                          child: FractionallySizedBox(
                            widthFactor: .25,
                            heightFactor: 1,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.white.withValues(alpha: .19),
                                    Colors.white.withValues(alpha: .08),
                                  ],
                                ),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: .2),
                                ),
                                borderRadius: BorderRadius.circular(21),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var index = 0; index < 4; index++)
                            Expanded(
                              child: Semantics(
                                key: index == 3
                                    ? const Key('camera-mode-barcode')
                                    : null,
                                button: true,
                                excludeSemantics: true,
                                onTap: () =>
                                    widget.onSelect(captureModes[index]),
                                selected: selected == index,
                                label: [
                                  'Type',
                                  'Camera',
                                  'Voice',
                                  'Barcode',
                                ][index],
                                child: InkWell(
                                  key: Key(
                                    'capture-mode-${captureModes[index]}',
                                  ),
                                  borderRadius: BorderRadius.circular(21),
                                  onTap: () =>
                                      widget.onSelect(captureModes[index]),
                                  onHover: (value) => setState(
                                    () => hovered = value ? index : null,
                                  ),
                                  onFocusChange: (value) => setState(
                                    () => hovered = value ? index : null,
                                  ),
                                  child: AnimatedContainer(
                                    duration: duration,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                      horizontal: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          hovered == index && selected != index
                                          ? Colors.white.withValues(alpha: .12)
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(21),
                                    ),
                                    child: AnimatedDefaultTextStyle(
                                      duration: duration,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall!
                                          .copyWith(
                                            color: selected == index
                                                ? Colors.white
                                                : Colors.white60,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            height: 1.25,
                                          ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            [
                                              Icons.edit_note_rounded,
                                              Icons.camera_alt_rounded,
                                              Icons.mic_none_rounded,
                                              Icons.qr_code_scanner_rounded,
                                            ][index],
                                            size: 20,
                                            color: selected == index
                                                ? lime
                                                : Colors.white60,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            [
                                              'Type',
                                              'Camera',
                                              'Voice',
                                              'Barcode',
                                            ][index],
                                            textAlign: TextAlign.center,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
