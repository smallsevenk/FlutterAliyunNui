library flutter_aliyun_nui;

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_aliyun_nui/flutter_aliyun_nui.dart';
import 'package:flutter_aliyun_nui/method_channel_ext.dart';

export 'src/nui_config.dart';
export 'src/nui_event.dart';

class ALNui {
  static const MethodChannel _channel = MethodChannel('flutter_aliyun_nui');
  static bool recognizeOnReady = false;
  static bool ttsOnReady = false;
  static Function(String text)? slog;

  static void setSlog(Function(String text) slongFunction) {
    slog = slongFunction;
  }

  static void log(String method, [dynamic args]) {
    debugPrint('NBSDK ======> $method:${args.toString()}');
    slog?.call('NBSDK ======> $method:${args.toString()}}');
  }

  static void setMethodCallHandler({
    Function(NuiRecognizeResult)? recognizeResultHandler,
    Function? playerDrainFinishHandler,
    Function(double)? rmsChangedHandler,
    Function(NuiError)? errorHandler,
    Function(String)? toastHandler,
  }) {
    if (isSimulator) {
      return;
    }
    _channel.setMethodCallHandler((call) async {
      try {
        switch (call.method) {
          case 'onRecognizeResult':
            log('onRecognizeResult', call.arguments);

            if (!recognizeOnReady) {
              debugPrint('NBSDK ======> recognize not ready');
              return;
            }
            recognizeResultHandler?.call((NuiRecognizeResult.fromMap(call.arguments)));
            break;
          case 'onPlayerDrainFinish':
            playerDrainFinishHandler?.call();
            List data = call.arguments ?? [];
            log('playerDrainFinishHandler', data.join(''));
            break;
          case 'onRmsChanged':
            rmsChangedHandler?.call(call.arguments);
            break;
          case 'onError':
            log('onError', call.arguments);
            final error = NuiError.fromMap(call.arguments);
            // 240068 token 无效/过期 清空 token 重新启动
            if (error.errorCode == 240068) {
              recognizeOnReady = false;
            }

            errorHandler?.call(error);
            break;
          case 'onToast':
            log('onToast', call.arguments);
            break;
        }
      } catch (e) {
        slog?.call('NBSDK ======> Error in method call handler: $e');
      }
    });
  }

  static Future<void> initRecognize(NuiConfig config) async {
    var initResult = await _channel.invoke('initRecognize', config.toRecognizeJson());
    recognizeOnReady = [0, 240012].contains(initResult); // 0 表示成功，240012 表示已初始化
    slog?.call('NBSDK ======> initRecognize initResult:$initResult, is $recognizeOnReady');
  }

  static Future<void> startRecognize(String token) async {
    await _channel.invoke('startRecognize', {'token': token});
  }

  static Future<void> stopRecognize() async {
    await _channel.invoke('stopRecognize');
  }

  static Future<void> startStreamInputTts(NuiConfig config, {bool retry = false}) async {
    try {
      var ret = await _channel.invoke('startStreamInputTts', config.toStreamTtsJson());
      ttsOnReady = ret == 0;
      log('startStreamInputTts is $ttsOnReady');
    } catch (e) {
      log('startStreamInputTts', e);
    }
  }

  static Future<void> sendStreamInputTts(String text) async {
    if (!ttsOnReady) {
      debugPrint('NBSDK ======>send fialed, tts not ready');
      return;
    } else if (text.isEmpty) {
      debugPrint('NBSDK ======>send fialed, text is null');
      return;
    }

    await _channel.invoke('sendStreamInputTts', {'text': text});
  }

  static Future<void> stopStreamInputTts() async {
    if (!ttsOnReady) {
      debugPrint('NBSDK ======>stop failed, tts not ready');
      return;
    }
    await _channel.invoke('stopStreamInputTts');
    ttsOnReady = false;
  }

  static Future<void> cancelStreamInputTts() async {
    await _channel.invoke('cancelStreamInputTts');
    ttsOnReady = false;
  }

  static Future<bool> isPlaying() async {
    return await _channel.invoke('isPlaying');
  }

  static Future<bool> isPaused() async {
    return await _channel.invoke('isPaused');
  }

  static Future<bool> isStopped() async {
    return await _channel.invoke('isStopped');
  }

  static Future<void> release() async {
    recognizeOnReady = false;
    ttsOnReady = false;
    await _channel.invoke('release');
  }

  static bool get isSimulator {
    if (!Platform.isIOS) return false;
    // iOS 模拟器的设备型号一般以 "x86_64" 或 "arm64" 开头
    return !Platform.isMacOS && (Platform.environment['SIMULATOR_DEVICE_NAME'] != null);
  }
}
