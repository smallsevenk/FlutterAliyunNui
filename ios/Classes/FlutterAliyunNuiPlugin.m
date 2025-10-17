#import "FlutterAliyunNuiPlugin.h"
#import "FlutterAliyunNui.h"

@implementation FlutterAliyunNuiPlugin {
    FlutterMethodChannel *_channel;
    FlutterAliyunNui *_nui;
}

// 懒加载获取 FlutterAliyunNui 实例，确保每次都能拿到
- (FlutterAliyunNui *)nui {
    if (!_nui) {
        _nui = [[FlutterAliyunNui alloc] initWithChannel:_channel];
    }
    return _nui;
}

// 插件注册入口，初始化 MethodChannel 并绑定插件实例
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    FlutterMethodChannel* channel = [FlutterMethodChannel
        methodChannelWithName:@"flutter_aliyun_nui"
              binaryMessenger:[registrar messenger]];
    FlutterAliyunNuiPlugin* instance = [[FlutterAliyunNuiPlugin alloc] init];
    instance->_channel = channel;
    [registrar addMethodCallDelegate:instance channel:channel];
}

// 处理 Dart 层调用的所有方法
- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"initRecognize" isEqualToString:call.method]) {
        // 初始化识别
        result([self.nui nuiSdkInit:call.arguments]);
    } else if ([@"startRecognize" isEqualToString:call.method]) {
        // 开始识别
        NSString *token = [call.arguments objectForKey:@"token"];
        [self.nui startRecognizeWithToken:token result:result];
        result(nil);
    } else if ([@"stopRecognize" isEqualToString:call.method]) {
        // 停止识别
        [self.nui stopRecognize];
        result(nil);
    } else if ([@"release" isEqualToString:call.method]) {
        // 释放资源
        [self.nui nuiRelase];
        _nui = nil;
        result(nil);
    } else if ([@"startStreamInputTts" isEqualToString:call.method]) {
        // 开始流式TTS
        [self.nui startStreamInputTts:call.arguments result:result];
    } else if ([@"sendStreamInputTts" isEqualToString:call.method]) {
        // 发送流式TTS文本
        [self.nui sendStreamInputTts:call.arguments];
        result(nil);
    } else if ([@"stopStreamInputTts" isEqualToString:call.method]) {
        // 正常结束流式TTS
        [self.nui stopStreamInputTts];
        result(nil);
    } else if ([@"cancelStreamInputTts" isEqualToString:call.method]) {
        // 取消流式TTS
        [self.nui cancelStreamInputTts];
        result(nil);
//    } else if ([@"isPlaying" isEqualToString:call.method]) {
//        result(@([self.nui isPlaying]));
//    } else if ([@"isPaused" isEqualToString:call.method]) {
//        result(@([self.nui isPaused]));
   } else if ([@"isStopped" isEqualToString:call.method]) {
       result(@([self.nui isStopped]));
//    } else if ([@"play" isEqualToString:call.method]) {
//        result(@([self.nui pa]));
//    } else if ([@"pause" isEqualToString:call.method]) {
//        result(@([self.nui pausePlayer]));
//    } else if ([@"resume" isEqualToString:call.method]) {
//        result(@([self.nui resumePlayer]));
    } else {
        // 未实现的方法
        result(FlutterMethodNotImplemented);
    }
}

@end
