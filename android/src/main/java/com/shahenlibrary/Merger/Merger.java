package com.shahenlibrary.Merger;

import android.content.Context;
import android.util.Log;
import com.facebook.react.bridge.*;
import com.shahenlibrary.Trimmer.Trimmer;


import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.UUID;

/**
 * Created by alon on 17/11/2017.
 */
//npm install --save https://github.com/alonle/react-native-video-processing/tarball/add-merge-files
public class Merger {
    private static final String LOG_TAG = "RNTrimmerManager";

    public static void merge(ReadableArray paths, final Promise promise, ReactApplicationContext reactContext){
        final File tempFile = createTempFile("mp4", promise, reactContext);
        ArrayList<String> cmd = new ArrayList<String>();
        for(int i=0; i< paths.size();i++){
            cmd.add("-i");
            cmd.add(paths.getString(i));
        }

        String[] params = {"-strict", "-2","-movflags" ,"faststart","-filter_complex","concat=n="+paths.size()+":v=1:a=1:unsafe=1 [v] [a];[0:v]setpts=1.5*PTS[v];[0:a]atempo=0.66[a];[v]scale=640:480[v2]", "-map", "[v2]", "-map","[a]"};

        cmd.addAll(Arrays.asList(params));

        cmd.add(tempFile.getPath());


        final String[] cmdToExec = cmd.toArray( new String[0] );

        Log.d(LOG_TAG, Arrays.toString(cmdToExec));

        Trimmer.executeFfmpegCommand(cmd, tempFile.getPath(), reactContext, promise, "Merge error", null);

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
