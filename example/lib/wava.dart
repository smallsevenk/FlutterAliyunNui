import 'dart:math' as math;
import 'package:flutter/material.dart';

class AudioWaveAnimation extends StatefulWidget {
  final double rms; // 0-160范围的音量值
  final Color waveColor;
  final int waveCount;

  const AudioWaveAnimation({
    Key? key,
    required this.rms,
    this.waveColor = Colors.blue,
    this.waveCount = 30,
  }) : super(key: key);

  @override
  _AudioWaveAnimationState createState() => _AudioWaveAnimationState();
}

class _AudioWaveAnimationState extends State<AudioWaveAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int count = widget.waveCount;
    int part = count ~/ 3;
    int remain = count - part * 3; // 不能整除时补到最后一段

    // 三段的起止下标
    List<List<int>> segments = [
      [0, part - 1],
      [part, part * 2 - 1],
      [part * 2, count - 1],
    ];
    if (remain > 0) segments[2][1] += remain;

    return AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          double rmsNorm = (widget.rms / 160).clamp(0.1, 1.0);
          double baseHeight = rmsNorm * 100;

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(count, (index) {
              int seg = 0;
              for (int i = 0; i < 3; i++) {
                if (index >= segments[i][0] && index <= segments[i][1]) {
                  seg = i;
                  break;
                }
              }
              int segStart = segments[seg][0];
              int segEnd = segments[seg][1];
              int segCenter = (segStart + segEnd) ~/ 2;
              double dist = (index - segCenter).abs() / ((segEnd - segStart) / 2);
              double decay = 1 - dist * 0.7; // 0.3~1.0

              double waveFactor = math
                  .sin(_controller.value * 2 * math.pi + index * math.pi / 6 + seg * math.pi / 2);
              // 平滑过渡，波峰波谷都能出现
              double height = baseHeight * decay * (0.85 + 0.15 * waveFactor);

              return Align(
                alignment: Alignment.center,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: 4,
                  height: height,
                  decoration: BoxDecoration(
                    color: widget.waveColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          );
        });
  }
}
