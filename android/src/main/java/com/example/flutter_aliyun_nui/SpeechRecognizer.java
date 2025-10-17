package com.example.flutter_aliyun_nui;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.util.Log;

import com.alibaba.fastjson.JSON;
import com.alibaba.fastjson.JSONException;
import com.alibaba.fastjson.JSONObject;
import com.alibaba.idst.nui.AsrResult;
import com.alibaba.idst.nui.Constants;
import com.alibaba.idst.nui.INativeNuiCallback;
import com.alibaba.idst.nui.KwsResult;
import com.alibaba.idst.nui.NativeNui;

import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.LinkedBlockingQueue;

import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * 阿里云语音识别 Flutter 插件核心实现
 */
public class SpeechRecognizer implements INativeNuiCallback {
    private static final String TAG = "SpeechRecognizer";

    private final MethodChannel channel;
    private final Context context;

    private final NativeNui nui_instance = new NativeNui();
    private final static int SAMPLE_RATE = 16000;
    private final static int WAVE_FRAM_SIZE = 20 * 2 * 1 * SAMPLE_RATE / 1000; // 20ms audio for 16k/16bit/mono
    private AudioRecord mAudioRecorder = null;

    private boolean mInit = false;
    private boolean mStopping = false;
    private String mDebugPath = "";
    private String curTaskId = "";
    private final LinkedBlockingQueue<byte[]> tmpAudioQueue = new LinkedBlockingQueue<>();
    private String mRecordingAudioFilePath = "";
    private OutputStream mRecordingAudioFile = null;
    private Handler mHandler;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final String[] permissions = {Manifest.permission.RECORD_AUDIO};

    public SpeechRecognizer(Context context, MethodChannel channel) {
        this.context = context;
        this.channel = channel; 
    }

    /**
     * Flutter MethodChannel 入口
     */
    public void handleMethodCall(MethodCall call, MethodChannel.Result result) {
        Map<String, Object> params = call.arguments();
        switch (call.method) {
            case "initRecognize":
                initNui(params, result);
                break;
            case "startRecognize":
                startRecognize(params, result);
                break;
            case "stopRecognize":
                stopRecognize(result);
                break;
            case "release":
                release(result);
                result.success(null); 
                break;
            default:
                result.notImplemented();
        }
    }

    /**
     * 初始化 SDK
     */
    private void initNui(Map<String, Object> params, MethodChannel.Result result) {
        if (mHandler == null) {
            HandlerThread handlerThread = new HandlerThread("process_thread");
            handlerThread.start();
            mHandler = new Handler(handlerThread.getLooper());

            mDebugPath = context.getExternalCacheDir().getAbsolutePath() + "/debug";
            Utils.createDir(mDebugPath);
        }
        JSONObject json = new JSONObject(params); 

        int ret = nui_instance.initialize(this, genInitParams("", mDebugPath, json),
                Constants.LogLevel.LOG_LEVEL_ERROR, true);
        Log.i(TAG, "NUI init result = " + ret);
        if (ret == Constants.NuiResultCode.SUCCESS) {
            mInit = true;
            Log.i(TAG, "NUI init success");
        } else {
            Log.e(TAG, "NUI init failed: " + ret);
        }
        result.success(ret);
    }

    /**
     * 开始识别
     */
    private void startRecognize(Map<String, Object> params, MethodChannel.Result result) {
        JSONObject json = new JSONObject(params);
        Log.i(TAG, "startRecognize json = " + json.toString());

        // 动态权限申请
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            int i = ContextCompat.checkSelfPermission(context, permissions[0]);
            if (i != PackageManager.PERMISSION_GRANTED && context instanceof Activity) {
                ((Activity) context).requestPermissions(permissions, 321);
            }
        }
        if (ActivityCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            if (mAudioRecorder == null) {
                mAudioRecorder = new AudioRecord(MediaRecorder.AudioSource.DEFAULT,
                        SAMPLE_RATE,
                        AudioFormat.CHANNEL_IN_MONO,
                        AudioFormat.ENCODING_PCM_16BIT,
                        WAVE_FRAM_SIZE * 4);
                Log.d(TAG, "AudioRecorder new ...");
            } else {
                Log.w(TAG, "AudioRecord has been new ...");
            }
        } else {
            Log.e(TAG, "donnot get RECORD_AUDIO permission!");
            result.success("-1");
            return;
        }

        mHandler.post(() -> {
            String setParamsString = genParams();
            Log.i(TAG, "nui set params " + setParamsString);
            nui_instance.setParams(setParamsString);
            int ret = nui_instance.startDialog(Constants.VadMode.TYPE_P2T,
                    genDialogParams(json.getString("token")));
            Log.i(TAG, "start done with " + ret);
            if (ret != 0) {
                final String msg_text = Utils.getMsgWithErrorCode(ret, "start");
                Log.e(TAG, "startDialog failed: " + msg_text);
                result.success("-1");
            }
            else {
                result.success("0");
            }
        }); 
    }

    /**
     * 停止识别
     */
    private void stopRecognize(MethodChannel.Result result) {
        mHandler.post(() -> {
            mStopping = true;
            long ret = nui_instance.stopDialog();
            Log.i(TAG, "cancel dialog " + ret + " end");
        });
        result.success(null);
    }

    /**
     * 释放资源
     */
    private void release(MethodChannel.Result result) {
        nui_instance.release();
        result.success(null);
    }

    /**
     * 生成识别参数
     */
    private String genParams() {
        try {
            JSONObject nls_config = new JSONObject();
            nls_config.put("enable_intermediate_result", true);
            nls_config.put("enable_punctuation_prediction", true);
            nls_config.put("sample_rate", SAMPLE_RATE);
            nls_config.put("sr_format", "pcm");
            nls_config.put("enable_voice_detection", false);

            JSONObject parameters = new JSONObject();
            parameters.put("nls_config", nls_config);
            parameters.put("service_type", Constants.kServiceTypeASR);
            return parameters.toString();
        } catch (JSONException e) {
            e.printStackTrace();
            return "";
        }
    }

    /**
     * 生成初始化参数
     */
    private String genInitParams(String workpath, String debugpath, JSONObject json) {
        String g_appkey = json.getString("app_key");
        String g_token = json.getString("token");
        String device_id = json.getString("device_id");
        String url = json.getString("url");
        try {
            Auth.GetTicketMethod method = Auth.GetTicketMethod.GET_TOKEN_FROM_SERVER_FOR_ONLINE_FEATURES;
            if (!g_appkey.isEmpty()) Auth.setAppKey(g_appkey);
            if (!g_token.isEmpty()) Auth.setToken(g_token);

            if (!g_appkey.isEmpty() && !g_token.isEmpty()) {
                method = Auth.GetTicketMethod.GET_TOKEN_IN_CLIENT_FOR_ONLINE_FEATURES;
            }
            Log.i(TAG, "Use method:" + method);
            JSONObject object = Auth.getTicket(method);
            if (!object.containsKey("token")) {
                Log.e(TAG, "Cannot get token !!!");
            }
            object.put("device_id", device_id);
            object.put("url", url);
            object.put("save_wav", "true");
            object.put("debug_path", debugpath);
            object.put("log_track_level", String.valueOf(Constants.LogLevel.toInt(Constants.LogLevel.LOG_LEVEL_INFO)));
            object.put("service_mode", Constants.ModeAsrCloud);
            return object.toString();
        } catch (JSONException e) {
            e.printStackTrace();
            return "";
        }
    }

    /**
     * 生成对话参数
     */
    private String genDialogParams(String token) {
        try {
            JSONObject dialog_param = new JSONObject();
            long distance_expire_time_5m = 300;
            dialog_param = Auth.refreshTokenIfNeed(dialog_param, distance_expire_time_5m);
            dialog_param.put("token", token);
            return dialog_param.toString();
        } catch (JSONException e) {
            e.printStackTrace();
            return "";
        }
    }

    // ================== SDK 回调实现 ==================

    @Override
    public void onNuiEventCallback(Constants.NuiEvent event, final int resultCode,
                                   final int arg2, KwsResult kwsResult,
                                   AsrResult asrResult) {
        Log.i(TAG, "event=" + event + " resultCode=" + resultCode);

        if (event == Constants.NuiEvent.EVENT_ASR_STARTED) {
            JSONObject jsonObject = JSON.parseObject(asrResult.allResponse);
            JSONObject header = jsonObject.getJSONObject("header");
            curTaskId = header.getString("task_id");
        } else if (event == Constants.NuiEvent.EVENT_ASR_RESULT) {
            mStopping = false;
            JSONObject jsonObject = JSON.parseObject(asrResult.asrResult);
            JSONObject payload = jsonObject.getJSONObject("payload");
            String result = payload.getString("result");
            Log.i(TAG, "EVENT_ASR_RESULT " + result);
            Map<String, Object> arguments = new HashMap<>();
            arguments.put("result", result);
            arguments.put("isLast", 1);
            mainHandler.post(() -> channel.invokeMethod("onRecognizeResult", arguments));
        } else if (event == Constants.NuiEvent.EVENT_ASR_PARTIAL_RESULT) {
            JSONObject jsonObject = JSON.parseObject(asrResult.asrResult);
            JSONObject payload = jsonObject.getJSONObject("payload");
            String result = payload.getString("result");
            Log.i(TAG, "EVENT_ASR_PARTIAL_RESULT " + result);
            Map<String, Object> arguments = new HashMap<>();
            arguments.put("result", result);
            arguments.put("isLast", 0);
            mainHandler.post(() -> channel.invokeMethod("onRecognizeResult", arguments));
        } else if (event == Constants.NuiEvent.EVENT_ASR_ERROR) {
            final String msg_text = Utils.getMsgWithErrorCode(resultCode, "start");
            mStopping = false;
            Log.e(TAG, "EVENT_ASR_ERROR: " + msg_text); 
            Map<String, Object> arguments = new HashMap<>();
            arguments.put("errorCode", 1);
            arguments.put("errorMessage", msg_text);
            mainHandler.post(() -> channel.invokeMethod("onError", arguments));
        } else if (event == Constants.NuiEvent.EVENT_MIC_ERROR) {
            final String msg_text = Utils.getMsgWithErrorCode(resultCode, "start");
            mStopping = false;
            Log.e(TAG, "EVENT_MIC_ERROR: " + msg_text);
        } else if (event == Constants.NuiEvent.EVENT_DIALOG_EX) {
            Log.i(TAG, "dialog extra message = " + asrResult.asrResult);
        }
    }

    @Override
    public int onNuiNeedAudioData(byte[] buffer, int len) {
        if (mAudioRecorder == null || mAudioRecorder.getState() != AudioRecord.STATE_INITIALIZED) {
            Log.e(TAG, "audio recorder not init");
            return -1;
        }
        int audio_size = mAudioRecorder.read(buffer, 0, len);
        // 可选：音频数据存储到本地
        return audio_size;
    }

    @Override
    public void onNuiAudioStateChanged(Constants.AudioState state) {
        Log.i(TAG, "onNuiAudioStateChanged: " + state);
        try {
            if (state == Constants.AudioState.STATE_OPEN) {
                if (mAudioRecorder == null || mAudioRecorder.getState() != AudioRecord.STATE_INITIALIZED) {
                    // 重新初始化
                    mAudioRecorder = new AudioRecord(
                            MediaRecorder.AudioSource.DEFAULT,
                            SAMPLE_RATE,
                            AudioFormat.CHANNEL_IN_MONO,
                            AudioFormat.ENCODING_PCM_16BIT,
                            WAVE_FRAM_SIZE * 4
                    );
                    Log.i(TAG, "AudioRecorder re-initialized in onNuiAudioStateChanged");
                }
                if (mAudioRecorder.getState() == AudioRecord.STATE_INITIALIZED) {
                    mAudioRecorder.startRecording();
                } else {
                    Log.e(TAG, "AudioRecord still not initialized, cannot startRecording!");
                }
            } else if (state == Constants.AudioState.STATE_CLOSE || state == Constants.AudioState.STATE_PAUSE) {
                if (mAudioRecorder != null) {
                    if (state == Constants.AudioState.STATE_PAUSE) mAudioRecorder.stop();
                    else mAudioRecorder.release();
                }
                if (mRecordingAudioFile != null) {
                    mRecordingAudioFile.close();
                    mRecordingAudioFile = null;
                    Log.i(TAG, "存储录音音频到 " + mRecordingAudioFilePath);
                }
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    @Override
    public void onNuiAudioRMSChanged(float val) {
        mainHandler.post(() -> channel.invokeMethod("onRmsChanged", val));
    }

    @Override
    public void onNuiVprEventCallback(Constants.NuiVprEvent event) {
        Log.i(TAG, "onNuiVprEventCallback event " + event);
    }

    @Override
    public void onNuiLogTrackCallback(Constants.LogLevel level, String log) {
        // 可选：SDK日志回调
    }
}