import 'dart:math';

import 'package:audio_wave/audio_wave.dart';
import 'package:flutter/material.dart';
import 'package:flutter_aliyun_nui/flutter_aliyun_nui.dart';
import 'dart:async';
import 'dart:math';

class VoiceRecognitionPage extends StatefulWidget {
  const VoiceRecognitionPage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _VoiceRecognitionPageState createState() => _VoiceRecognitionPageState();
}

class _VoiceRecognitionPageState extends State<VoiceRecognitionPage> {
  String _recognizedText = '';
  int _waveCount = 44;
  double _minDecay = 0.4;
  bool _stopped = true;
  List<double> _amplitudes = [];
  final GlobalKey _btnKey = GlobalKey();
  bool _willCancel = false;
  @override
  void initState() {
    super.initState();
    _amplitudes = List.filled(_waveCount, _minDecay);
    ALNui.setSlog((x) {
      debugPrint(x);
    });
  }

  Future<void> _initRecognize() async {
    // if ((await PermissionUtil.checkMicAndSpeeh(context)) == false) {
    //   return;
    // }
    NuiConfig config = NuiConfig(
      appKey: AliyunConfig.appKey,
      deviceId: '660668cf0c874c848fbb467603927ebd',
      token: AliyunConfig.token,
    );

    await ALNui.initRecognize(config);
    ALNui.setMethodCallHandler(
      recognizeResultHandler: (result) {
        setState(() {
          _recognizedText = result.result;
          if (result.isLast) {
            debugPrint('识别完毕,内容为:${result.result}');
          }
        });
      },
      errorHandler: (error) {
        debugPrint(error.errorMessage);
        _rmsChanged();
      },
      rmsChangedHandler: _rmsOnChange,
    );
  }

  Future<void> _startRecognition() async {
    setState(() {
      _stopped = false;
      _recognizedText = '';
    });
    await ALNui.startRecognize(AliyunConfig.token);
  }

  Future<void> _stopRecognition() async {
    await ALNui.stopRecognize();
    _willCancel = false;
    _rmsChanged();
  }

  Future<void> _startStreamInputTts() async {
    NuiConfig config = NuiConfig(
      appKey: AliyunConfig.appKey,
      deviceId: '660668cf0c874c848fbb467603927ebd',
      token: AliyunConfig.token,
      format: 'pcm',
      voice: 'xiaoyun',
      sampleRate: 16000,
      speechRate: 0,
      pitchRate: 0,
      volume: 80,
    );
    await ALNui.startStreamInputTts(config);
  }

  Future<void> _sendStreamInputTts() async {
    // 使用示例
    final chunks = [
      "唧唧复唧唧，木兰当户织。不闻机杼声，唯闻女叹息。",
      // "问女何所思，问女何所忆。女亦无所思，女亦无所忆。",
      // "昨夜见军帖，可汗大点兵，军书十二卷，卷卷有爷名。",
      // "阿爷无大儿，木兰无长兄，愿为市鞍马，从此替爷征。",
      // "东市买骏马，西市买鞍鞯，南市买辔头，北市买长鞭。旦辞爷娘去，暮宿黄河边，不闻爷娘唤女声，但闻黄河流水鸣溅溅。",
      // "旦辞黄河去，暮至黑山头，不闻爷娘唤女声，但闻燕山胡骑鸣啾啾。万里赴戎机",
      // "关山度若飞。朔气传金柝，寒光照铁衣。将军百战死，壮士十年归。",
      // "归来见天子，天子坐明堂。策勋十二转，赏赐百千强。可汗问所欲，木兰不用尚书郎",
      // "愿驰千里足，送儿还故乡。爷娘闻女来，出郭相扶将；阿姊闻妹来，当户理红妆；小弟闻姊来，磨刀霍霍向猪羊。",
      // "开我东阁门，坐我西阁床。脱我战时袍，著我旧时裳。当窗理云鬓，对镜帖花黄",
      // "出门看火伴，火伴皆惊忙：同行十二年，不知木兰是女郎。",
      // "雄兔脚扑朔，雌兔眼迷离；双兔傍地走，安能辨我是雄雌？",
    ];
    await simulateStreamTTS(chunks);
  }

  Future<void> simulateStreamTTS(List<String> textChunks, {int intervalMs = 10}) async {
    for (final chunk in textChunks) {
      await ALNui.sendStreamInputTts(chunk);
      await Future.delayed(Duration(milliseconds: intervalMs));
    }
  }

  Future<void> _stopStreamInputTts() async {
    ALNui.stopStreamInputTts();
  }

  Future<void> _cancelStreamInputTts() async {
    ALNui.cancelStreamInputTts();
  }

  @override
  void dispose() {
    ALNui.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          children: [
            const SizedBox(height: 200),
            Text(_recognizedText, style: const TextStyle(color: Colors.red)),
            ElevatedButton(onPressed: _initRecognize, child: const Text('Init')),
            ElevatedButton(onPressed: _startRecognition, child: const Text('Start')),
            ElevatedButton(onPressed: _stopRecognition, child: const Text('Stop')),
            ElevatedButton(onPressed: _startStreamInputTts, child: const Text('startTts')),
            ElevatedButton(onPressed: _sendStreamInputTts, child: const Text('sendTts')),
            ElevatedButton(onPressed: _stopStreamInputTts, child: const Text('stopTts')),
            ElevatedButton(onPressed: _cancelStreamInputTts, child: const Text('cancelTts')),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Text(
                _willCancel ? '松手取消' : '松手发送,上移取消',
                style: TextStyle(color: _willCancel ? Colors.red : Colors.grey),
              ),
            ),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanDown: (details) async {
                    if (!ALNui.recognizeOnReady) {
                      await _initRecognize();
                    }
                    await _startRecognition();
                  },
                  onPanUpdate: (details) {
                    // 判断手指是否滑出按钮上方
                    RenderBox? box = _btnKey.currentContext?.findRenderObject() as RenderBox?;
                    if (box != null) {
                      Offset topLeft = box.localToGlobal(Offset.zero);
                      Size size = box.size;
                      Rect btnRect = topLeft & size;
                      if (!btnRect.contains(details.globalPosition)) {
                        // 手指已滑出按钮区域
                        _willCancel = true;
                        // 你可以 setState 显示“松手取消”提示
                      } else {
                        _willCancel = false;
                        // 你可以 setState 显示“松手发送”提示
                      }
                    }
                  },
                  onPanEnd: (details) {
                    _stopRecognition();
                  },
                  onPanCancel: () {
                    _stopRecognition();
                  },
                  child: Container(
                    key: _btnKey,
                    height: 60,
                    decoration: BoxDecoration(
                      color: const Color(0xff3D57F8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: _stopped
                        ? const Center(
                            child: Text(
                              '长按说话',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
                            ),
                          )
                        : VoiceWave(
                            amplitudes: _amplitudes,
                            backgroundColor: _willCancel ? Colors.red : const Color(0xff3D57F8),
                          ),
                  ),
                )),
          ],
        ),
      ),
    );
  }

  void _rmsChanged() {
    setState(() {
      _stopped = true;
      _amplitudes = List.filled(_waveCount, _minDecay);
    });
  }

  void _rmsOnChange(double rms) {
    var showRms = rms + 160;
    if (showRms < 110) {
      setState(() {
        _amplitudes = List.filled(_waveCount, _minDecay);
      });
      return;
    }
    setState(() {
      _amplitudes = VoiceWave.generateAmplitudes(rms, _waveCount);
      _stopped = false; // 新增字段
    });
  }
}

class VoiceWave extends StatelessWidget {
  final List<double> amplitudes;
  final double waveWidth;
  final double waveHeight;
  final double spacing;
  final Color waveColor;
  final Color backgroundColor;
  final Size backgroundSize;
  final EdgeInsets padding;

  const VoiceWave({
    super.key,
    required this.amplitudes,
    this.waveWidth = 3.0,
    this.waveHeight = 20.0,
    this.spacing = 2.0,
    this.waveColor = Colors.white,
    this.backgroundColor = const Color(0xff3D57F8),
    this.backgroundSize = const Size(double.infinity, double.infinity),
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: backgroundSize.width,
      height: backgroundSize.height,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(amplitudes.length, (index) {
            var h = amplitudes[index] * waveHeight.clamp(7.0, waveHeight);
            return AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin: EdgeInsets.symmetric(horizontal: spacing / 2),
              width: waveWidth,
              height: h,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: waveColor,
                borderRadius: BorderRadius.circular(waveWidth / 2),
              ),
            );
          }),
        ),
      ),
    );
  }

  static List<double> generateAmplitudes(double rms, int waveCount) {
    double norm = ((rms + 160) / 160).clamp(0.0, 1.0);
    final random = Random();

    // 1. 构造每段长度
    List<int> segLens = List.generate(11, (i) => i % 2 == 0 ? 3 : 5);
    // 2. 修正最后一段长度，保证总数等于_waveCount
    int total = segLens.reduce((a, b) => a + b);
    if (total != waveCount) {
      segLens[10] += (waveCount - total);
    }
    // 3. 计算每段起始下标
    List<int> segStartIdx = [];
    int acc = 0;
    for (int len in segLens) {
      segStartIdx.add(acc);
      acc += len;
    }

    return List.generate(waveCount, (i) {
      // 找到当前i属于哪个段
      int seg = 0;
      for (int s = 0; s < segStartIdx.length; s++) {
        int start = segStartIdx[s];
        int end = start + segLens[s] - 1;
        if (i >= start && i <= end) {
          seg = s;
          break;
        }
      }
      double decay = 1.0;
      if (seg % 2 == 1) {
        // 奇数段做中间高两边低
        int start = segStartIdx[seg];
        int end = start + segLens[seg] - 1;
        int center = (start + end) ~/ 2;
        double dist = (i - center).abs() / ((end - start) / 2);
        decay = 1 - dist * 0.25; // 0.75~1.0
      }
      double coef = (seg % 2 == 0) ? 0.4 : decay;

      var h = (norm * 1.2 + random.nextDouble() * 0.8) * coef;
      return h;
    });
  }
}
