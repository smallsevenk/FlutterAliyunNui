class AliyunConfig {
  static const appKey = 'K2W2xXRFH90s93gz';
  static const token = 'ae361a480ede4e38ab37b5be8b9c90ea';
}

class NuiConfig {
  String appKey;
  String token;
  String? deviceId;
  String? url;
  String? format;
  String? voice;
  int? sampleRate;
  int? speechRate;
  int? pitchRate;
  int? volume;

  NuiConfig(
      {required this.appKey,
      required this.token,
      this.deviceId,
      this.url,
      this.format,
      this.voice,
      this.sampleRate,
      this.speechRate,
      this.pitchRate,
      this.volume});
  Map<String, dynamic> toRecognizeJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['app_key'] = appKey;
    data['token'] = token;
    data['device_id'] = deviceId ?? '';
    data['url'] = url ?? 'wss://nls-gateway-cn-beijing.aliyuncs.com/ws/v1';
    return data;
  }

  Map<String, dynamic> toStreamTtsJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['app_key'] = appKey;
    data['token'] = token;
    data['device_id'] = deviceId ?? '';
    data['url'] = url ?? 'wss://nls-gateway-cn-beijing.aliyuncs.com/ws/v1';
    data['format'] = format ?? 'pcm';
    data['voice'] = voice ?? 'xiaoyun';
    data['sample_rate'] = sampleRate ?? 16000;
    data['speech_rate'] = speechRate ?? 0;
    data['pitch_rate'] = pitchRate ?? 0;
    data['volume'] = volume ?? 50;
    return data;
  }
}
