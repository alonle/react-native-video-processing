package com.shahenlibrary.Merger;

import android.content.Context;
import android.util.Log;
import com.facebook.react.bridge.*;
import com.github.hiteshsondhi88.libffmpeg.FFmpeg;
import com.github.hiteshsondhi88.libffmpeg.FFmpegExecuteResponseHandler;


import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;

/**
 * Created by alon on 17/11/2017.
 */
public class Merger {
    private static final String LOG_TAG = "RNTrimmerManager";

    public static void merge(List<String> paths, ReadableMap options, final Promise promise, ReactApplicationContext reactContext){
        final File tempFile = createTempFile("mp4", promise, reactContext);
        ArrayList<String> cmd = new ArrayList<String>();
        for(String path: paths){
            cmd.add("-i");
            cmd.add(path);
        }

        String[] params = {"-strict", "-2","-movflags" ,"faststart","-filter_complex","concat=n="+paths.size()+":v=1:a=1:unsafe=1 [v] [a]", "-map", "[v]", "-map","[a]"};

        cmd.addAll(Arrays.asList(params));

        cmd.add(tempFile.getPath());


        final String[] cmdToExec = cmd.toArray( new String[0] );

        Log.d(LOG_TAG, Arrays.toString(cmdToExec));

        try {
            FFmpeg.getInstance(reactContext).execute(cmdToExec, new FFmpegExecuteResponseHandler() {

                @Override
                public void onStart() {
                    Log.d(LOG_TAG, "merge: onStart");
                }

                @Override
                public void onProgress(String message) {
                    Log.d(LOG_TAG, "merge: onProgress");
                }

                @Override
                public void onFailure(String message) {
                    Log.d(LOG_TAG, "merge: onFailure");
                    promise.reject("merge error: failed.", message);
                }

                @Override
                public void onSuccess(String message) {
                    Log.d(LOG_TAG, "merge: onSuccess");
                    Log.d(LOG_TAG, message);

                    WritableMap event = Arguments.createMap();
                    event.putString("source", "file://" + tempFile.getPath());
                    promise.resolve(event);
                }

                @Override
                public void onFinish() {
                    Log.d(LOG_TAG, "merge: onFinish");
                }
            });
        } catch (Exception e) {
            promise.reject("Merge error", e.toString());
        }

    }

    static File createTempFile(String extension, final Promise promise, Context ctx) {
        UUID uuid = UUID.randomUUID();
        String imageName = uuid.toString() + "-merged";

        File cacheDir = ctx.getCacheDir();
        File tempFile = null;
        try {
            tempFile = File.createTempFile(imageName, "." + extension, cacheDir);
        } catch( IOException e ) {
            promise.reject("Failed to create temp file", e.toString());
            return null;
        }

        if (tempFile.exists()) {
            tempFile.delete();
        }

        return tempFile;
    }

}
