
#import <Foundation/Foundation.h>

#define DEBUG_MODE
#ifdef DEBUG_MODE
#define TLog( s, ... ) NSLog( s, ##__VA_ARGS__ )
#else
#define TLog( s, ... )
#endif

enum AudioControlType {
    all_open = 0,
    only_player = 1,
    only_recorder = 2,
};
typedef enum AudioControlType AudioControlType;

/**
 *@discuss AudioController 各种回调接口
 */
@protocol ConvVoiceRecorderDelegate <NSObject>

/**
 * @discuss Recorder启动回调，在主线程中调用
 */
-(void) recorderDidStart;

/**
 * @discuss Recorde停止回调，在主线程中调用
 */
-(void) recorderDidStop;

/**
 * @discuss Recorder收录到数据，通常涉及VAD及压缩等操作，为了避免阻塞主线，因此将在在AudioQueue的线程中调用，注意线程安全！！！
 */
-(void) voiceRecorded:(unsigned char*)buffer Length:(int)len;

/**
 *@discussion 录音机无法打开或其他错误的时候会回调
 */
-(void) voiceDidFail:(NSError*)error;


/**
 * @Player开始播放
 */
-(void) playerDidStart;

/**
 * @Player排出数据完成回调，同步调用
 */
-(void) playerDrainDataFinish;

/**
 * @Player数据完成播放回调
 */
-(void) playerDidFinish;

/**
 * @Player数据音量值回调  0-100
 */
-(void) playSoundLevel:(int)level;

/// 播放数据回调
-(void) playData:(unsigned char*)buffer Length:(int)len;

/**
 * @discuss 音频控制器错误回调
 * @param error 错误信息
 */
-(void) onError:(NSError*)error;

@end

/**
 *@discuss 封装了AudioUnit  C API的录音机和播放器程序
 */
@interface AudioController : NSObject

/// 录音事件代理
@property(nonatomic,assign) id<ConvVoiceRecorderDelegate> delegate;

/// 当前的音量值
@property(nonatomic,readonly) NSUInteger currentVoiceVolume;


/**
 * 初始化AudioController，若only_player为true，则只初始化播放器
 */
-(id)init:(AudioControlType)type;

/**
 * 开始录音
 */
-(void)startRecorder;

/**
 * 停止录音
 */
-(void)stopRecorder:(BOOL)shouldNotify;

/**
 *  录音机静音
 */
-(void)mute;

/**
 *  录音机取消静音
 */
-(void)unmute;

/**
 * 是否在录音
 */
-(BOOL)isRecorderStarted;

/**
 * 开始播放
 */
-(void)startPlayer;

/**
 * 停止播放
 */
-(void)stopPlayer;

/**
 * 暂停播放
 */
-(void)pausePlayer;

/**
 * 恢复播放
 */
-(void)resumePlayer;

/**
 * PCM音频数据写入播放器
 */
-(int)write:(const char*)buffer Length:(int)len;

/**
 * 设置播放器采样率
 */
-(void)setPlayerSampleRate :(int)sr;

/**
 * 判断是否处于draining阶段
 */
-(bool)checkPlayerFinish;

/**
 * 清空缓存和硬件播放器中的数据
 */
-(void)cleanPlayerBuffer;

/**
 * 通知播放器写完所有数据，后续就是等待播放器播放完毕
 */
-(void)drain;

/**
 * 是否正在播放
 */
-(BOOL)isPlaying;

/**
 * 是否暂停播放
 */
-(BOOL)isPaused;

/**
 * 是否播放已停止
 */
-(BOOL)isPlayerStopped;

/**
 *  音量计算
 */
-(int)calculateVolumeFromPCMData:(unsigned char*)cal_buffer Size:(unsigned int)size Offset:(unsigned int)offset Add:(unsigned char*)add_buffer Length:(unsigned int)len;


@end
