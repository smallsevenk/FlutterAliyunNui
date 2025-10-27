//
//  AudioController.m
//  ConvDemo
//
//  Created by shichen.fsc on 2024/01/03.
//  Copyright © 2024 Alibaba MIT. All rights reserved.
//

#import "AudioController.h"

#import <AudioToolbox/AudioToolbox.h>
#import <UIKit/UIApplication.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import "NLSRingBuffer.h"

/// 录音状态
typedef enum {
    RECORDER_STATE_IDLE = 0,
    RECORDER_STATE_INIT,
    RECORDER_STATE_START,
    RECORDER_STATE_STOP
} AudioRecorderState;

/// 播放器状态
typedef enum {
    PLAYER_STATE_IDLE = 0,
    PLAYER_STATE_INIT,
    PLAYER_STATE_STARTING,
    PLAYER_STATE_PLAYING,
    PLAYER_STATE_PAUSED,
    PLAYER_STATE_STOPPED = 5,
    PLAYER_STATE_DRAINING,
} AudioPlayerState;

/// 回调指定的线程队列
static dispatch_queue_t gCallbackQueue;
/// ref数据及状态回调线程队列
static dispatch_queue_t gCallbackRefQueue;
/// fadeout线程
static dispatch_queue_t gFadeOutQueue;

#pragma mark - AudioController Implementation

@interface AudioController(){
    /// 录音AudioUnit实例
    AudioUnit mRecordUnit;
    /// 播放器AudioUnit实例
    AudioUnit mPlayUnit;
    /// mixer实例，挂到mPlayUnit之前
    AudioUnit mMixerUnit;
    /// ringbuffer实例
    NlsRingBuffer* ring_buf;
    /// 采样率
    UInt32 sample_rate;
    /// 录音格式
    AudioStreamBasicDescription mRecordFormat;
    /// 播放格式
    AudioStreamBasicDescription mPlayFormat;
    /// 是否在后台
    BOOL _inBackground;
    //TODO: 状态变化要保证多线程安全
    /// 录音状态
    AudioRecorderState recorder_state;
    /// 播放器
    AudioPlayerState player_state;
    BOOL recorder_mute_flag;
    BOOL is_paused_flag;
    
    /// 缓冲区
    unsigned char* cal_buffer;
    /// 缓冲长度
    UInt32 cal_buffer_len;
    /// 缓冲偏移量
    UInt32 cal_buffer_offset;
}

@end

@implementation AudioController


-(void) _handleVoiceFrame:(const char*)buffer Length:(int)len {
    if (_delegate && recorder_mute_flag == false) {
        [_delegate voiceRecorded:(unsigned char*)buffer Length:(int)len];
    }
}

static OSStatus RecordCallback(
    void *inRefCon,
    AudioUnitRenderActionFlags *ioActionFlags,
    const AudioTimeStamp *inTimeStamp,
    UInt32 inBusNumber,
    UInt32 inNumberFrames,
    AudioBufferList *ioData) {

    OSStatus status = noErr;
    if (inNumberFrames > 0) {
        AudioController *record = (__bridge AudioController *)inRefCon;
        AudioBufferList bufferList;
        UInt16 numSamples = inNumberFrames * 1;
        UInt16 samples[numSamples]; // just for 16bit sample
        memset(&samples, 0, sizeof(samples));
        bufferList.mNumberBuffers = 1;
        bufferList.mBuffers[0].mData = samples;
        bufferList.mBuffers[0].mNumberChannels = record->mRecordFormat.mChannelsPerFrame;
        bufferList.mBuffers[0].mDataByteSize = numSamples * sizeof(UInt16);

        status = AudioUnitRender(record->mRecordUnit,
                                 ioActionFlags,
                                 inTimeStamp,
                                 inBusNumber,
                                 inNumberFrames,
                                 &bufferList);
        if (bufferList.mBuffers[0].mDataByteSize > 0) {
            [record _handleVoiceFrame:(const char *)bufferList.mBuffers[0].mData Length:bufferList.mBuffers[0].mDataByteSize];
        }
    } else {
        NSLog(@"inNumberFrames is %u", (unsigned int)inNumberFrames);
    }
    return noErr;
}

static OSStatus PlayCallback(
    void *inRefCon,
    AudioUnitRenderActionFlags *ioActionFlags,
    const AudioTimeStamp *inTimeStamp,
    UInt32 inBusNumber,
    UInt32 inNumberFrames,
    AudioBufferList *ioData) {

    AudioController *play = (__bridge AudioController *)inRefCon;
//    if (play->is_paused_flag) {
//        return noErr;
//    }

    int ret = 0;
    unsigned char* tmp = (unsigned char*)malloc(ioData->mBuffers[0].mDataByteSize);
    if (play->is_paused_flag) {
        int read_size = [play->ring_buf ringbuffer_get_read_index];
        ret = read_size > ioData->mBuffers[0].mDataByteSize ? ioData->mBuffers[0].mDataByteSize : read_size;
        memset(tmp, 0, ret);
    } else {
        ret = [play->ring_buf ringbuffer_read:tmp Length:ioData->mBuffers[0].mDataByteSize];
//        TLog(@"ringbuf read data %d; state:%d", ret, play->player_state);
    }
    if (ret > 0) {
        if (play->is_paused_flag) {
            memcpy((char *)ioData->mBuffers[0].mData, tmp, ret);
        } else {
            if ([play->_delegate respondsToSelector:@selector(playData:Length:)]) {
                unsigned char *send_data = (unsigned char *)malloc(ret);
                memcpy(send_data, tmp, ret);
                dispatch_async(gCallbackRefQueue, ^{
                    [play->_delegate playData:(unsigned char*)send_data Length:(int)ret];
                });
            }
            memcpy((char *)ioData->mBuffers[0].mData, tmp, ret);
            //        TLog(@"ringbuf read data %dbytes",  ret);
            
            int level = [play calculateVolumeFromPCMData:play->cal_buffer Size:(unsigned int)play->cal_buffer_len Offset:(unsigned int)play->cal_buffer_offset Add:(unsigned char*)tmp Length:(unsigned int)ret];
            if (level < 0) {
                play->cal_buffer_offset += ret;
            } else {
                play->cal_buffer_offset = 0;
                if ([play->_delegate respondsToSelector:@selector(playSoundLevel:)]) {
                    dispatch_async(gCallbackQueue, ^{
                        [play->_delegate playSoundLevel:level];
                    });
                }
            }
        }
    } else {
//        TLog(@"audioplayer: no more data with state %d", play->player_state);
        memset((char *)ioData->mBuffers[0].mData, 0, ioData->mBuffers[0].mDataByteSize);
        if (play->player_state == PLAYER_STATE_DRAINING) {
            TLog(@"audioplayer: draining ...");
            // will trigger stopPlayer in playerDrainDataFinish
            if ([play->_delegate respondsToSelector:@selector(playerDrainDataFinish)]) {
                dispatch_sync(gCallbackQueue, ^{
                    play->player_state = PLAYER_STATE_STOPPED;
                    @try {
                        AudioOutputUnitStop(play->mPlayUnit);
                    } @catch (NSException *exception) {
                        // mPlayUnit 为 NULL，构造错误回调但不崩溃
                        NSDictionary *userInfo = @{ NSLocalizedDescriptionKey: exception.description };
                        NSError *err = [NSError errorWithDomain:@"AudioController" code:-1 userInfo:userInfo];
                        if ([play->_delegate respondsToSelector:@selector(onError:)]) {
                            dispatch_async(gCallbackQueue, ^{
                                [play->_delegate onError:err];
                            });
                        }
                    }
                AudioOutputUnitStop(play->mPlayUnit);
                        
                    [play->_delegate playerDrainDataFinish];
                });
            }
        }

    }
    free(tmp);

    return 0;
}
      
-(id)init:(AudioControlType)type {
    NSLog(@"audiocontroller: init with type:%d(0:all_open,1:only_player,2:only_recorder)", type);

    self = [super init];
    if (self) {
        // 1.init AudioSession
        NSError *error = nil;
        player_state = PLAYER_STATE_IDLE;
        recorder_state = RECORDER_STATE_IDLE;

        sample_rate = 48000; // for tts
        cal_buffer_len = 5760;  // for tts
        if (cal_buffer) {
            free(cal_buffer);
            cal_buffer = NULL;
        }
        cal_buffer = (unsigned char*)malloc(cal_buffer_len * 2); // for tts
        cal_buffer_offset = 0;

        ring_buf = [[NlsRingBuffer alloc] init:sample_rate];

        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        if (type == all_open) {
            [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionAllowBluetooth | AVAudioSessionCategoryOptionMixWithOthers error:nil];
            if (error) NSLog(@"AVAudioSessionCategoryPlayAndRecord failed! error:%@", error);
        } else if (type == only_player) {
            [audioSession setCategory:AVAudioSessionCategoryPlayback withOptions: AVAudioSessionCategoryOptionAllowBluetooth | AVAudioSessionCategoryOptionMixWithOthers error:nil];
            if (error) NSLog(@"AVAudioSessionCategoryPlayback failed! error:%@", error);
        } else if (type == only_recorder) {
            [audioSession setCategory:AVAudioSessionCategoryRecord withOptions:AVAudioSessionCategoryOptionAllowBluetooth | AVAudioSessionCategoryOptionMixWithOthers error:nil];
            if (error) NSLog(@"AVAudioSessionCategoryRecord failed! error:%@", error);
        }

        [audioSession setPreferredIOBufferDuration:0.04 error:&error];
        if (error) NSLog(@"setPreferredIOBufferDuration failed! error:%@", error);

        [self _registerForBackgroundNotifications];
        gCallbackQueue = dispatch_queue_create("ConvAudioCallback", DISPATCH_QUEUE_CONCURRENT);
        gCallbackRefQueue = dispatch_queue_create("ConvAudioRefCallback", DISPATCH_QUEUE_CONCURRENT);
        gFadeOutQueue = dispatch_queue_create("AudioControllerFadeOutQueue", DISPATCH_QUEUE_CONCURRENT);
        
        if (type == all_open || type == only_recorder) {
            [self _initRecorder];
        }
        if (type == all_open || type == only_player) {
            [self _initPlayer];
        }
    }
    return self;
}

-(void) _initRecorder {
    NSLog(@"audiorecorder: init");

    // 3.init Audio Component
    AudioComponentDescription recordDesc;
    memset(&recordDesc, 0, sizeof(AudioComponentDescription));
    recordDesc.componentType = kAudioUnitType_Output;
    recordDesc.componentSubType = kAudioUnitSubType_RemoteIO;
    recordDesc.componentFlags = 0;
    recordDesc.componentFlagsMask = 0;
    recordDesc.componentManufacturer = kAudioUnitManufacturer_Apple;

    AudioComponent inputComponent = AudioComponentFindNext(NULL, &recordDesc);
    OSStatus status = AudioComponentInstanceNew(inputComponent, &mRecordUnit);
    if (status) NSLog(@"AudioComponentInstanceNew inputComponent failed(%d)", (int)status);
    
    memset(&mRecordFormat, 0, sizeof(mRecordFormat));
    mRecordFormat.mFormatID = kAudioFormatLinearPCM;
    mRecordFormat.mSampleRate = 16000;
    mRecordFormat.mChannelsPerFrame = 1;  // 单声道
    mRecordFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    mRecordFormat.mBitsPerChannel = 16;
    mRecordFormat.mBytesPerPacket =  (mRecordFormat.mBitsPerChannel >> 3) * mRecordFormat.mChannelsPerFrame;  // 单声道，16 位，每帧2字节
    mRecordFormat.mBytesPerFrame = mRecordFormat.mBytesPerPacket;
    mRecordFormat.mFramesPerPacket = 1;
    
    // 4.init Format
    // 对Input Scope的Bus0设置StreamFormat属性
    // Set format for output (bus 0) on the RemoteIO's input scope
    status = AudioUnitSetProperty(mRecordUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,  // 开启输入
                                  0,  // kOutputBus
                                  &mRecordFormat,
                                  sizeof(mRecordFormat));
    
    // 对Output Scope的Bus1设置StreamFormat属性
    // Set format for mic input (bus 1) on RemoteIO's output scope
    status = AudioUnitSetProperty(mRecordUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  1,  // kInputBus
                                  &mRecordFormat,
                                  sizeof(mRecordFormat));
    if (status) {
      NSLog(@"kAudioUnitProperty_StreamFormat set output failed(%d)",
          (int)status);
    }
    
    // 5.init Audio Property
    // mic采集的声音数据从Input Scope的Bus1输入
    UInt32 enableFlag = 1;
    status = AudioUnitSetProperty(mRecordUnit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input,  // 开启输入
                                  1,  // kInputBus
                                  &enableFlag,
                                  sizeof(enableFlag));
    if (status) {
      NSLog(@"kAudioOutputUnitProperty_EnableIO set input failed(%d)",
          (int)status);
    }
    
    //设置录音的agc增益，这个用的是ios自带agc
//        UInt32 enable_agc = 1;
//        status = AudioUnitSetProperty(mRecordUnit,
//                                      kAUVoiceIOProperty_VoiceProcessingEnableAGC,
//                                      kAudioUnitScope_Global,
//                                      1,  // kInputBus
//                                      &enable_agc,
//                                      sizeof(enable_agc));
//        if (status) {
//            NSLog(@"kAUVoiceIOProperty_VoiceProcessingEnableAGC set failed(%d)",
//                (int)status);
//        }
    
    // 6.init RecordCallback
    // 在Output Scope的Bus1设置InputCallBack，
    // 在该CallBack中我们需要获取到音频数据
    AURenderCallbackStruct recordCallback;
    recordCallback.inputProc = RecordCallback;
    recordCallback.inputProcRefCon = (__bridge void *)self;
    status = AudioUnitSetProperty(mRecordUnit,
                                  kAudioOutputUnitProperty_SetInputCallback,
                                  kAudioUnitScope_Global,
                                  1,  // kInputBus
                                  &recordCallback,
                                  sizeof(recordCallback));
    
    // 9.init AudioUnit
    status = AudioUnitInitialize(mRecordUnit);
    if (status) {
      NSLog(@"AudioUnitInitialize mRecordUnit failed(%d)", (int)status);
    } else {
        recorder_state = RECORDER_STATE_INIT;
        recorder_mute_flag = false;
    }
}

-(void) _initPlayer {
    NSLog(@"audioplayer: init");

    // 3.init Audio Component
    AudioComponentDescription playDesc;
    AudioComponentDescription mixerDesc;
    memset(&playDesc, 0, sizeof(AudioComponentDescription));
    memset(&mixerDesc, 0, sizeof(AudioComponentDescription));
    
    playDesc.componentType = kAudioUnitType_Output;
    playDesc.componentSubType = kAudioUnitSubType_RemoteIO;
    playDesc.componentFlags = 0;
    playDesc.componentFlagsMask = 0;
    playDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    mixerDesc.componentType = kAudioUnitType_Mixer;
    mixerDesc.componentSubType = kAudioUnitSubType_MultiChannelMixer;
    mixerDesc.componentManufacturer = kAudioUnitManufacturer_Apple;

    AudioComponent outputComponent = AudioComponentFindNext(NULL, &playDesc);
    OSStatus status = AudioComponentInstanceNew(outputComponent, &mPlayUnit);
    if (status) NSLog(@"AudioComponentInstanceNew outputComponent failed(%d)", (int)status);
    
    AudioComponent mixerComponent = AudioComponentFindNext(NULL, &mixerDesc);
    status = AudioComponentInstanceNew(mixerComponent, &mMixerUnit);
    if (status) NSLog(@"AudioComponentInstanceNew mixerComponent failed(%d)", (int)status);
    
    memset(&mPlayFormat, 0, sizeof(mPlayFormat));
    mPlayFormat.mFormatID = kAudioFormatLinearPCM;
    mPlayFormat.mSampleRate = sample_rate;
    mPlayFormat.mChannelsPerFrame = 1;
    mPlayFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    mPlayFormat.mBitsPerChannel = 16;
    mPlayFormat.mBytesPerPacket =  (mPlayFormat.mBitsPerChannel >> 3) * mPlayFormat.mChannelsPerFrame;
    mPlayFormat.mBytesPerFrame = mPlayFormat.mBytesPerPacket;
    mPlayFormat.mFramesPerPacket = 1;
    
    /// mixer播放格式
    AudioStreamBasicDescription mixerFormat;
    memset(&mixerFormat, 0, sizeof(mixerFormat));
    
    // 4.init Format
    // 对Input Scope的Bus0设置StreamFormat属性
    status = AudioUnitSetProperty(mPlayUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,  // 开启输入
                                  0,  // kOutputBus
                                  &mPlayFormat,
                                  sizeof(mPlayFormat));
    UInt32 maxFramesPerSlice = 4096;
    /*
    status = AudioUnitSetProperty(mPlayUnit,
                                 kAudioUnitProperty_MaximumFramesPerSlice,
                                 kAudioUnitScope_Global,
                                 0, // Element
                                 &maxFramesPerSlice,
                                 sizeof(maxFramesPerSlice));
    NSAssert(status == noErr, @"Error setting max frame per slice on play unit: %d", status);
    */

    UInt32 playFlag = 1;
    AudioUnitSetProperty(mPlayUnit,
                         kAudioOutputUnitProperty_EnableIO,
                         kAudioUnitScope_Output,
                         0,  // kOutputBus
                         &playFlag,
                         sizeof(playFlag));
    //设置mixer输入总线数
    UInt32 busCount = 1;
    status = AudioUnitSetProperty(mMixerUnit,
                                  kAudioUnitProperty_ElementCount,
                                  kAudioUnitScope_Input,
                                  0,
                                  &busCount,
                                  sizeof(busCount));
    NSAssert(status == noErr, @"Error setting bus count on Mixer unit: %d", status);
        
    AURenderCallbackStruct playCallback;
    playCallback.inputProc = PlayCallback;
    playCallback.inputProcRefCon = (__bridge void *)self;
    status = AudioUnitSetProperty(mMixerUnit,
                                  kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Global,
                                  0,  // kOutputBus
                                  &playCallback,
                                  sizeof(playCallback));
    //获取remoteIOUnit输出格式
    UInt32 mixerFormatSize = sizeof(mixerFormat);
    status = AudioUnitGetProperty(mPlayUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  0,
                                  &mixerFormat,
                                  &mixerFormatSize);
    NSAssert(status == noErr, @"Error getting ASBD from RemoteIO output: %d", status);
    
    //设置mixer输入格式
    status = AudioUnitSetProperty(mMixerUnit,
                                      kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Input,
                                      0, // 第一个输入总线
                                      &mPlayFormat,
                                      sizeof(mPlayFormat));
    NSAssert(status == noErr, @"Error setting format for Mixer input: %d", status);
    //设置mixer输出格式
    status = AudioUnitSetProperty(mMixerUnit,
                                      kAudioUnitProperty_StreamFormat,
                                      kAudioUnitScope_Output,
                                      0, // 第一个输入总线
                                      &mPlayFormat,
                                      sizeof(mPlayFormat));
    NSAssert(status == noErr, @"Error setting format for Mixer output: %d", status);
    
    status = AudioUnitSetProperty(mMixerUnit,
                                 kAudioUnitProperty_MaximumFramesPerSlice,
                                 kAudioUnitScope_Global,
                                 0, // Element
                                 &maxFramesPerSlice,
                                 sizeof(maxFramesPerSlice));
    NSAssert(status == noErr, @"Error setting max frame per slice on mixer unit: %d", status);
    //连接mixerUnit和remoteIOUnit
    AudioUnitConnection mixerConnection;
    mixerConnection.sourceAudioUnit = mMixerUnit;
    mixerConnection.sourceOutputNumber = 0;
    mixerConnection.destInputNumber = 0;
    status = AudioUnitSetProperty(mPlayUnit,
                                  kAudioUnitProperty_MakeConnection,
                                  kAudioUnitScope_Input,
                                  0,
                                  &mixerConnection,
                                  sizeof(mixerConnection));
    NSAssert(status == noErr, @"Error connecting Mixer to RemoteIO: %d", status);
             
    status = AudioUnitSetParameter(mMixerUnit,
                                   kMultiChannelMixerParam_Volume,
                                  kAudioUnitScope_Output,
                                  0,
                                  1.0f,
                                  0);
    if (status) {
        NSLog(@"AudioUnitSetParameter mMixerUnit failed(%d)", (int)status);
    } else {
        NSLog(@"AudioUnitSetParameter mMixerUnit success(%d)", (int)status);
    }
    status = AudioUnitInitialize(mMixerUnit);
    NSAssert(status == noErr, @"Cannot initialize Mixer unit: %d", status);
    // 9.init AudioUnit
    status = AudioUnitInitialize(mPlayUnit);
    if (status) {
        NSLog(@"AudioUnitInitialize mPlayUnit failed(%d)", (int)status);
    } else {
        player_state = PLAYER_STATE_INIT;
        is_paused_flag = false;
    }
}

-(void)dealloc {
    NSLog(@"audiocontroller: dealloc");

    [self _unregisterForBackgroundNotifications];

    if (recorder_state != RECORDER_STATE_IDLE) {
        [self stopRecorder:NO];

        AudioUnitUninitialize(mRecordUnit);
        AudioComponentInstanceDispose(mRecordUnit);
    }

    if (player_state != PLAYER_STATE_IDLE) {
        [self stopPlayer];

        AudioUnitUninitialize(mMixerUnit);
        AudioComponentInstanceDispose(mMixerUnit);
        
        AudioUnitUninitialize(mPlayUnit);
        AudioComponentInstanceDispose(mPlayUnit);
    }

    if (cal_buffer) {
        free(cal_buffer);
        cal_buffer = NULL;
    }
}

- (BOOL)setAudioCategoryWithOptions:(AVAudioSessionCategoryOptions)options
                              error:(NSError **)outError {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    AVAudioSessionCategory category = AVAudioSessionCategoryPlayAndRecord;
    if ([audioSession category] == AVAudioSessionCategoryPlayAndRecord) {
        AVAudioSessionCategoryOptions currentOptions = [audioSession categoryOptions];
        AVAudioSessionCategoryOptions missingOptions = options & ~currentOptions;
        if (missingOptions == 0) {
            NSLog(@"currentOptions包含了所有的options");
            return YES;
        } else {
            if (missingOptions & AVAudioSessionCategoryOptionDefaultToSpeaker) {
                NSLog(@"缺少AVAudioSessionCategoryOptionDefaultToSpeaker");
            }
//            if (missingOptions & AVAudioSessionCategoryOptionDuckOthers) {
//                AudioControllerLog(@"缺少AVAudioSessionCategoryOptionDuckOthers");
//            }
            if (missingOptions & AVAudioSessionCategoryOptionAllowBluetooth) {
                NSLog(@"缺少AVAudioSessionCategoryOptionAllowBluetooth");
            }
            currentOptions |= missingOptions;
            return [audioSession setCategory:category withOptions:currentOptions error:outError];
        }
    } else {
        return [audioSession setCategory:category withOptions:options error:outError];
    }
}

-(void)startRecorder {
    NSLog(@"audiorecorder: startRecorder");
    if (recorder_state == RECORDER_STATE_START) {
        NSLog(@"in recorder _start, state has started!");
        return;
    }

    // perform the permission check
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    if ([audioSession respondsToSelector:@selector(requestRecordPermission:)]) {
        [audioSession performSelector:@selector(requestRecordPermission:) withObject:^(BOOL allow) {
            if (allow) {
                ;
            } else {
                // no permission
                NSLog(@"record no permission");
                return;
            }
        }];
    } else {
        ;
    }

    AVAudioSessionCategoryOptions options = AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionAllowBluetooth;
    [self setAudioCategoryWithOptions:options error:nil];

    // BOOL isHeadsetMic = false;
    // NSArray* inputs = [audioSession availableInputs];
    
    // AVAudioSessionPortDescription *preBuiltInMic = nil;
    // AVAudioSessionPortDescription *headSetMicPort = nil;
    
    // NSLog(@"audiorecorder: availableInputs: %@", [[AVAudioSession sharedInstance] availableInputs]);
    
    // for (AVAudioSessionPortDescription* port in inputs) {
    //     if ([port.portType isEqualToString:AVAudioSessionPortBuiltInMic]) {
    //         // Built-in microphone on an iOS device
    //         preBuiltInMic = port;
    //     } else if ([port.portType isEqualToString:AVAudioSessionPortHeadsetMic]) {
    //         // 耳机线中的麦克风
    //         isHeadsetMic = true;
    //         headSetMicPort = port;
    //     } else if ([port.portType isEqualToString:AVAudioSessionPortBluetoothHFP]) {
    //         // 在蓝牙免提上的input or output
    //         isHeadsetMic = true;
    //         headSetMicPort = port;
    //     } else if ([port.portType isEqualToString:AVAudioSessionPortHeadphones]) {
    //         // 耳机或者耳机式输出设备
    //     }
    // }

    // // 寻找期望的麦克风
    // AVAudioSessionPortDescription *builtInMic = nil;
    // if (!isHeadsetMic) {
    //     if (preBuiltInMic != nil)
    //         builtInMic = preBuiltInMic;
    //     for (AVAudioSessionDataSourceDescription* descriptions in builtInMic.dataSources) {
    //         if ([descriptions.orientation isEqual:AVAudioSessionOrientationFront]) {
    //             [builtInMic setPreferredDataSource:descriptions error:&error];
    //             if (error) NSLog(@"mic in device setPreferredDataSource failed! error:%@", error);
    //             [audioSession setPreferredInput:builtInMic error:&error];
    //             if (error) NSLog(@"mic in device setPreferredInput failed! error:%@", error);
    //             NSLog(@"mic in device type:%@ description:%@", builtInMic.portType, descriptions.description);
    //             break;
    //         }
    //     }
    // } else {
    //     BOOL didSet = [audioSession setPreferredInput:headSetMicPort error:&error];
    //     NSLog(@"mic isHeadsetMic type:%@ description:%@ didSet:%@", headSetMicPort.portType, headSetMicPort.description, didSet ? @"True" : @"False");
    //     if (error) {
    //         NSLog(@"use mic isHeadsetMic failed! error:%@", error);
    //         [audioSession setPreferredInput:nil error:&error]; // 重置到默认输入
    //     }
    // }

    NSLog(@"audiorecorder: current route = %@", [[AVAudioSession sharedInstance] currentRoute]);

    OSStatus status = AudioOutputUnitStart(mRecordUnit);
    if (status) {
        NSLog(@"AudioOutputUnitStart failed! status(%d)",
            (int)status);
    } else {
        recorder_state = RECORDER_STATE_START;
        recorder_mute_flag = false;
        if (_delegate && [_delegate respondsToSelector:@selector(recorderDidStart)]) {
            dispatch_async(gCallbackQueue, ^{
                [self->_delegate recorderDidStart];
            });
        }
    }
}

-(void)startPlayer {
    NSLog(@"audioplayer: startPlayer with state:%d(0:IDLE,1:INIT,2:STARING,3:PALYING,4:PAUSED,5:STOPPED,6:DRAINING)", player_state);
    player_state = PLAYER_STATE_STARTING;
    is_paused_flag = false;

    NSLog(@"audioplayer: current route = %@", [[AVAudioSession sharedInstance] currentRoute]);
    OSStatus status = -1;
    status = AudioUnitSetParameter(mMixerUnit,
                                   kMultiChannelMixerParam_Volume,
                                   kAudioUnitScope_Output,
                                   0,
                                   1.0f,
                                   0);
    if (status) {
        NSLog(@"AudioUnitSetProperty failed! status(%d)", status);
    }
    status = AudioOutputUnitStart(mPlayUnit);
    if (status) {
        NSLog(@"AudioOutputUnitStart failed! status(%d)",
            (int)status);
    } else {
        player_state = PLAYER_STATE_PLAYING;
        cal_buffer_offset = 0;
        
        if (_delegate && [_delegate respondsToSelector:@selector(playerDidStart)]) {
            dispatch_async(gCallbackQueue, ^{
                [self->_delegate playerDidStart];
            });
        }
    }
}


-(void)stopRecorder:(BOOL)shouldNotify {
    NSLog(@"audiorecorder: stop");
    is_paused_flag = false;
    if (recorder_state == RECORDER_STATE_STOP) {
        NSLog(@"in recorder stop, state has stopped!");
        return;
    }

    recorder_state = RECORDER_STATE_STOP;

    OSStatus status = -1;
    status = AudioOutputUnitStop(mRecordUnit);
    if (status) {
        NSLog(@"AudioUnit StopRecord(%d)", (int)status);
    }

    if (shouldNotify && _delegate) {
        dispatch_async(gCallbackQueue, ^{
            [self->_delegate recorderDidStop];
        });
    }
}

-(void)pausePlayer {
    NSLog(@"audioplayer: pausePlayer with state:%d(0:IDLE,1:INIT,2:STARING,3:PALYING,4:PAUSED,5:STOPPED,6:DRAINING)", player_state);
    //FIXME: AudioUnitOutput do not support pause yet,
    //so we do it by flag.
    is_paused_flag = true;
}

-(void)resumePlayer {
    NSLog(@"audioplayer: resumePlayer with state:%d(0:IDLE,1:INIT,2:STARING,3:PALYING,4:PAUSED,5:STOPPED,6:DRAINING)", player_state);
    //FIXME: AudioUnitOutput do not support pause yet,
    //so we do it by flag.
    is_paused_flag = false;
}

- (void)fadeOutWithDuration:(NSTimeInterval)duration {
    // 获取当前音量
    CGFloat fadeOutStepTime = 0.005;
    // 最大音量
    CGFloat maxVolume = 1.0f;
    // 最小音量
    CGFloat minVolume = 0.0f;
    
    dispatch_async(gFadeOutQueue, ^{
        CGFloat currentVolume = maxVolume;
        // 步数
        CGFloat fadeOutSteps = duration/fadeOutStepTime;
        // 每步减小的音量
        CGFloat volumeDecrementPerStep = maxVolume / fadeOutSteps;
        for (CGFloat step = 0.0f; step < fadeOutSteps; step++) {
            currentVolume -= volumeDecrementPerStep;
            if (currentVolume < minVolume) currentVolume = minVolume;
            AudioUnitSetParameter(mMixerUnit,
                                  kMultiChannelMixerParam_Volume,
                                  kAudioUnitScope_Output,
                                  0,
                                  currentVolume,
                                  0);
            [NSThread sleepForTimeInterval:fadeOutStepTime];
            if (currentVolume == minVolume)
                break;
        }
        [self->ring_buf ringbuffer_reset];
        OSStatus status = -1;
        //已经淡出，可以立即执行
        status = AudioOutputUnitStop(mPlayUnit);
        if (status) {
            NSLog(@"AudioUnit StopPlayer(%d)", (int)status);
        }
        if ([self->_delegate respondsToSelector:@selector(playerDidFinish)]) {
            dispatch_async(gCallbackRefQueue, ^{
                [self->_delegate playerDidFinish];
            });
        }
    });
}

-(void)stopPlayer {
    //stopPlayer入口，语音打断或tap打断，期望App一致调用stopPlayer结束播放.
    NSLog(@"audioplayer: stop");
    if (player_state == PLAYER_STATE_STOPPED) {
        NSLog(@"in player stop, state has stopped!");
        return;
    }
    
    player_state = PLAYER_STATE_STOPPED;
//    [self fadeOutWithDuration:0.3];
    [self->ring_buf ringbuffer_reset];
    OSStatus status = -1;
    //已经淡出，可以立即执行
    status = AudioOutputUnitStop(mPlayUnit);
    if (status) {
        NSLog(@"AudioUnit StopPlayer(%d)", (int)status);
    }
    if ([self->_delegate respondsToSelector:@selector(playerDidFinish)]) {
        dispatch_async(gCallbackRefQueue, ^{
            [self->_delegate playerDidFinish];
        });
    }
}

-(void)mute {
    TLog(@"audiorecorder: mute");
    recorder_mute_flag = true;
}

-(void)unmute {
    TLog(@"audiorecorder: unmute");
    recorder_mute_flag = false;
}

-(void)drain {
    TLog(@"audioplayer: Audio Player Draining, state:%d", player_state);
    player_state = PLAYER_STATE_DRAINING;
}

/**
 * 是否正在播放
 */
-(BOOL)isPlaying {
    return player_state == PLAYER_STATE_PLAYING;
}

/**
 * 是否暂停播放
 */
-(BOOL)isPaused {
    return player_state == PLAYER_STATE_PAUSED;
}

-(BOOL)isPlayerStopped {
    return player_state == PLAYER_STATE_STOPPED;
}

-(bool)checkPlayerFinish {
    TLog(@"audioplayer: checkPlayerFinish with state:%d", player_state);
    return (player_state == PLAYER_STATE_DRAINING) ? true : false;
}

-(void)cleanPlayerBuffer {
    TLog(@"audioplayer: cleanbuffer with state:%d", player_state);
    [ring_buf ringbuffer_reset];
    [self stopPlayer];
}

- (int)write:(const char*)buffer Length:(int)len {
    int wait_time_ms = 0;
    int ret = 0;
    
    if (player_state != PLAYER_STATE_PLAYING && player_state != PLAYER_STATE_STARTING) {
        [self startPlayer];
    }
    
    while (1) {
        if (wait_time_ms > 3000) {
            TLog(@"wait for 3s, player must not consuming pcm data. overrun...");
            break;
        }
//        TLog(@"ringbuf want write data %d",  len);
        int ret = [ring_buf ringbuffer_write:(unsigned char*)buffer Length:len];
//        TLog(@"ringbuf writed data %d",  ret);
        if (len != 0 && ret == 0) {
            int realloc_ret = [ring_buf try_realloc];
            if (realloc_ret == 0) {
                TLog(@"ringbuf try_realloc, size of buffer is: %d", [ring_buf ringbuffer_size]);
            }
        }
        if (player_state != PLAYER_STATE_PLAYING && player_state != PLAYER_STATE_STARTING) {
            TLog(@"ringbuf want state %d, break",  player_state);
            break;
        }
        if (ret <= 0) {
            usleep(10000);
            wait_time_ms += 10;
            continue;
        } else {
            wait_time_ms = 0;
            break;
        }
    }
    return ret;
}

- (void)setPlayerSampleRate:(int)sr {
    if (sr != sample_rate) {
        TLog(@"setsamplerate: set sample_rate %d", sample_rate);
        
        sample_rate = sr;
        
        [self stopPlayer];

        AudioUnitUninitialize(mPlayUnit);
        AudioComponentInstanceDispose(mPlayUnit);

        [self _initPlayer];
        TLog(@"setsamplerate: set sample_rate %d done.", sample_rate);
    }
}

-(int)calculateVolumeFromPCMData:(unsigned char*)cal_buffer Size:(unsigned int)size Offset:(unsigned int)offset Add:(unsigned char*)add_buffer Length:(unsigned int)len {
//    TLog(@"calculateVolumeFromPCMData buffer size:%d, offset:%d, add buffer len:%d", size, offset, len);
    float mVolume = 1;
    int level = -1;
    if (cal_buffer == NULL || add_buffer == NULL) {
        TLog(@"CalSoundLevelInDB buffer is nullptr!");
        return 0;
    }
    
    if (len > 0) {
        memcpy(cal_buffer + offset, add_buffer, len);
        int cur_offset = offset + len;
        if (cur_offset > size) {
            int count = cur_offset >> 1;
            short *short_array = (short *)malloc(count * sizeof(short));
            short short_value = 0;
            for (int i = 0; i < count; i++) {
                short_value = (short)((cal_buffer[2 * i + 1] << 8) | (cal_buffer[2 * i] & 0xff));
                mVolume += (float)abs(short_value);
            }
            mVolume /= count;
            free(short_array);
            
            // change 0~32767 to -160~0
            //    mVolume = 160 * mVolume * 5 / 32767 - 160;
            mVolume = 20.0 * log10(mVolume);
            mVolume = mVolume * 160 / 90 - 160;
            if (mVolume > 0) {
                mVolume = 0;
            } else if (mVolume < -160) {
                mVolume = -160;
            }
            level = (mVolume + 160) * 100 / 160;
        }
    }
    return level;
}


-(BOOL)isRecorderStarted {
    return recorder_state == RECORDER_STATE_START;
}

#pragma mark - Internal implementations

#pragma mark - Background Notifications
- (void)_registerForBackgroundNotifications {
    NSLog(@"audiorecorder: _registerForBackgroundNotifications");
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_appResignActive)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_appEnterForeground)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_observerApplicationWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
}

- (void)_unregisterForBackgroundNotifications {
    NSLog(@"audiorecorder: _unregisterForBackgroundNotifications");
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void)_observerApplicationWillResignActive:(NSNotification *)sender {
    NSLog(@"audiorecorder: _observerApplicationWillResignActive");
    if ([sender.name isEqualToString:UIApplicationWillResignActiveNotification]) {
        [self _registerNotificationForAudioSessionInterruption];
    }
}

-(void)_registerNotificationForAudioSessionInterruption {
    NSLog(@"audiorecorder: _registerNotificationForAudioSessionInterruption");
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(_audioSessionInterruptionHandle:) name:AVAudioSessionInterruptionNotification object:[AVAudioSession sharedInstance]];
}

-(void)_audioSessionInterruptionHandle:(NSNotification *)sender {
    NSLog(@"audiorecorder: _audioSessionInterruptionHandle");
    if ([sender.userInfo[AVAudioSessionInterruptionTypeKey] intValue] == AVAudioSessionInterruptionTypeBegan) {
        //pause session
    } else if ([sender.userInfo[AVAudioSessionInterruptionTypeKey] intValue] == AVAudioSessionInterruptionTypeEnded) {
        //Continue
    }
}

-(void)_observerApplicationBecomeActiveAction:(NSNotification *)sender {
    NSLog(@"audiorecorder: _observerApplicationBecomeActiveAction");
    if ([sender.name isEqualToString:UIApplicationWillEnterForegroundNotification]) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVAudioSessionInterruptionNotification object:[AVAudioSession sharedInstance]];
    }
}

- (void)_appResignActive {
    NSLog(@"audiorecorder: _appResignActive");
    _inBackground = true;
    AudioSessionSetActive(NO);
}

- (void)_appEnterForeground {
    NSLog(@"audiorecorder: _appEnterForeground");
    _inBackground = false;
}

@end
