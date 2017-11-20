//
//  VideoMergeManager.swift
//  Video merger manager
//
//  Created by Vyacheslav Khorkov on 23/08/16.
//  Copyright © 2016 Vyacheslav Khorkov. All rights reserved.
//

import Foundation
import AVFoundation

public let VideoMergeManagerVerbose: Bool = false // TODO: implement
public let VideoMergeManagerPrintPts: Bool = false
public let VideoMergeManagerDomain: String = "videoMergeManager"

public enum VideoMergeManagerErrorCode: Int {
  case WrongInputParameters = -10000
  case CannotFindVideoDescriptionInSourceFile = -10001
  case CannotCreateAssetVideoWriter = -10002
  case CannotCreateVideoInput = -10003
}

class VideoMergeManager
{
  static func mergeMultipleVideos(destinationPath: String, filePaths: [String], finished: @escaping ((NSError?, NSURL?) -> Void))
  {
    DispatchQueue.global().async {
      // Check input parametes
      if filePaths.count < 1 {
        let error = NSError(domain: VideoMergeManagerDomain,
                            code: VideoMergeManagerErrorCode.WrongInputParameters.rawValue,
                            userInfo: [NSLocalizedDescriptionKey: "Please, check [filePaths]."])
        DispatchQueue.main.async {
          finished(error, nil)
        }
        return
      }
      
      // Get audio and video format description
      let formatDescriptionTuple: (videoFormatHint: CMFormatDescription?,
        audioFormatHint: CMFormatDescription?) = findFormatDescription(filePath:filePaths.first!)
      
      if formatDescriptionTuple.videoFormatHint == nil {
        let error = NSError(domain: VideoMergeManagerDomain,
                            code: VideoMergeManagerErrorCode.CannotFindVideoDescriptionInSourceFile.rawValue,
                            userInfo: [NSLocalizedDescriptionKey: "Can't find video format description in source file."])
        DispatchQueue.main.async {
          finished(error, nil)
        }
        return
      }
      
      let videoFormatHint: CMFormatDescription = formatDescriptionTuple.videoFormatHint!
      let audioFormatHint: CMFormatDescription? = formatDescriptionTuple.audioFormatHint
      
      // Prepare asset writer
      var assetWriter: AVAssetWriter
      var videoInput: AVAssetWriterInput
      var audioInput: AVAssetWriterInput? // optional
      
      let assetWriterTuple: (writer: AVAssetWriter?,
        videoInput: AVAssetWriterInput?,
        audioInput:AVAssetWriterInput?) = prepareAssetWriter(destinationPath: destinationPath,
                                                             videoFormatHint: videoFormatHint,
                                                             audioFormatHint: audioFormatHint)
      if let test = assetWriterTuple.writer {
        assetWriter = test
      }
      else {
        let error = NSError(domain: VideoMergeManagerDomain,
                            code: VideoMergeManagerErrorCode.CannotCreateAssetVideoWriter.rawValue,
                            userInfo: [NSLocalizedDescriptionKey: "Can't create asset video writer"])
        DispatchQueue.main.async {
          finished(error, nil)
        }
        return
      }
      
      if let test = assetWriterTuple.videoInput {
        videoInput = test
      }
      else {
        let error = NSError(domain: VideoMergeManagerDomain,
                            code: VideoMergeManagerErrorCode.CannotCreateVideoInput.rawValue,
                            userInfo: [NSLocalizedDescriptionKey: "Can't create video input"])
        DispatchQueue.main.async {
          finished(error, nil)
        }
        return
      }
      
      if let test = assetWriterTuple.audioInput {
        audioInput = test
      }
      else {
        print("Can't create audio input")
      }
      
      // Start writing
      assetWriter.startWriting()
      assetWriter.startSession(atSourceTime: kCMTimeZero)
      
      var index = 0
      var isLastFilePath = false
      var audioSampleBuffer: CMSampleBuffer
      var videoSampleBuffer: CMSampleBuffer
      var audioBasePts: CMTime = kCMTimeZero
      var videoBasePts: CMTime = kCMTimeZero
      var lastAudioPts: CMTime = kCMTimeZero
      var lastVideoPts: CMTime = kCMTimeZero
      var lastAudioDuration: CMTime = kCMTimeZero
      
      //
      for filePath in filePaths
      {
        isLastFilePath = index == (filePaths.count - 1)
        
        // Prepare asset reader
        var assetReader: AVAssetReader
        var videoOutput: AVAssetReaderTrackOutput
        var audioOutput: AVAssetReaderTrackOutput? // optional
        
        let assetReaderTuple: (reader: AVAssetReader?,
          videoOutput: AVAssetReaderTrackOutput?,
          audioOutput: AVAssetReaderTrackOutput?) = prepareAssetReader(filePath: filePath)
        
        if let test = assetReaderTuple.reader {
          assetReader = test
        }
        else {
          print("Can't create asset reader for this path: \(filePath)")
          continue;
        }
        
        if let test = assetReaderTuple.videoOutput {
          videoOutput = test
        }
        else {
          print("Can't create video output for this path: \(filePath)")
          continue;
        }
        
        if let test = assetReaderTuple.audioOutput {
          audioOutput = test
        }
        else {
          print("Can't create audio output for this path: \(filePath)")
        }
        
        // Start reading
        assetReader.startReading()
        
        var audioBuffers = 0
        var videoBuffers = 0
        while assetReader.status == .reading
        {
          // Video
          if let test = videoOutput.copyNextSampleBuffer() {
            videoSampleBuffer = test
            
            while !videoInput.isReadyForMoreMediaData {
              usleep(100) // TODO: add limit
            }
            
            if videoBasePts.value != 0 {
              let newPts: CMTime = CMTimeAdd(CMSampleBufferGetPresentationTimeStamp(videoSampleBuffer), videoBasePts)
              let changedSampleBuffer:CMSampleBuffer? = copySampleBufferWithPresentationTime(sampleBuffer: videoSampleBuffer,
                                                                                             pts: newPts)
              if let test = changedSampleBuffer {
                videoSampleBuffer = test
              }
            }
            
            videoInput.append(videoSampleBuffer)
            videoBuffers += 1
            lastVideoPts = CMSampleBufferGetPresentationTimeStamp(videoSampleBuffer)
            
            if VideoMergeManagerPrintPts {
              print("v: \(String(format: "%.4f", CMTimeGetSeconds(lastVideoPts)))")
            }
          }
          else {
            assetReader.cancelReading()
            break
          }
          
          // Audio
          if audioInput == nil || audioOutput == nil {
            continue
          }
          
          if let test = audioOutput!.copyNextSampleBuffer() {
            audioSampleBuffer = test
            
            while !audioInput!.isReadyForMoreMediaData {
              usleep(100) // TODO: add limit
            }
            
            if audioBasePts.value != 0 {
              let newPts: CMTime = CMTimeAdd(CMSampleBufferGetPresentationTimeStamp(audioSampleBuffer), audioBasePts)
              let changedSampleBuffer:CMSampleBuffer? = copySampleBufferWithPresentationTime(sampleBuffer: audioSampleBuffer,
                                                                                             pts: newPts)
              if let test = changedSampleBuffer {
                audioSampleBuffer = test
              }
            }
            
            let currentPts = CMSampleBufferGetPresentationTimeStamp(audioSampleBuffer)
            let duration = CMSampleBufferGetDuration(audioSampleBuffer)
            
            if CMTIME_IS_VALID(currentPts) && duration.value > 0 {
              
              if index > 0 {
                // TODO: Probably in different audio tracks need to select attachments for deletion
                CMRemoveAllAttachments(audioSampleBuffer)
              }
              
              audioInput!.append(audioSampleBuffer)
              audioBuffers += 1
              lastAudioPts = currentPts
              lastAudioDuration = duration
              
              if VideoMergeManagerPrintPts {
                print("a: \(String(format: "%.4f", CMTimeGetSeconds(lastAudioPts)))")
              }
            }
          }
          
          if VideoMergeManagerPrintPts {
            print("")
          }
        }
        
        if !isLastFilePath {
          if VideoMergeManagerPrintPts {
            print("--")
          }
          
          let url = NSURL.fileURL(withPath: filePath)
          let asset = AVAsset(url: url)
          let videoTrack = asset.tracks(withMediaType: AVMediaTypeVideo).first!
          let fps = videoTrack.nominalFrameRate
          
          audioBasePts = CMTimeAdd(lastAudioPts, lastAudioDuration)
          videoBasePts = CMTimeAdd(lastVideoPts, CMTimeMake(100, Int32(fps * 100))) // If fps like a 29.xx
          
          let compareResult = CMTimeCompare(audioBasePts, videoBasePts)
          if compareResult >= 0 {
            videoBasePts = audioBasePts
          }
          else {
            if let test = audioFormatHint {
              let diff = CMTimeSubtract(videoBasePts, audioBasePts)
              let sampleRate = CMAudioFormatDescriptionGetStreamBasicDescription(test)?.pointee.mSampleRate
              let scaledDiff = CMTimeConvertScale(diff, Int32(sampleRate!), .roundHalfAwayFromZero)
              let silentAudioSampleBuffer = self.createSilentAudioSampleBufferWithFormatDescription(formatDescription: test,
                                                                                                    numSamples: Int(scaledDiff.value),
                                                                                                    presentationTime: audioBasePts)
              audioInput!.append(silentAudioSampleBuffer!)
            }
            audioBasePts = videoBasePts
          }
          
          if VideoMergeManagerPrintPts {
            print("vc: \(videoBuffers)");
            print("ac: \(audioBuffers)");
            print("vb: \(String(format: "%.4f", CMTimeGetSeconds(videoBasePts)))")
            print("ab: \(String(format: "%.4f", CMTimeGetSeconds(audioBasePts)))")
            print("")
          }
        }
        
        index += 1
      }
      
      assetWriter.finishWriting {
        switch assetWriter.status {
        case .cancelled:
          print("Cancelled")
          break
          
        case .completed:
          print("Completed")
          break
          
        case .failed:
          print("Failed")
          break
          
        case .unknown:
          print("Unknown")
          break
          
        case .writing:
          print("Writing")
          break
        }
        
        print(destinationPath)
        DispatchQueue.main.async {
          finished(nil, NSURL(fileURLWithPath: destinationPath))
        }
      }
    }
  }
  
  static func copySampleBufferWithPresentationTime(sampleBuffer: CMSampleBuffer, pts: CMTime) -> CMSampleBuffer?
  {
    var count: CMItemCount = 0
    CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, 0, nil, &count)
    let rawBytes = malloc(MemoryLayout<CMSampleTimingInfo>.size * count)
    let pInfo = rawBytes!.assumingMemoryBound(to: CMSampleTimingInfo.self)

    //let pInfo = UnsafeMutablePointer<CMSampleTimingInfo>()
    CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, count, pInfo, &count)
    
    for i in 0..<count {
      pInfo[i].decodeTimeStamp = kCMTimeInvalid;
      pInfo[i].presentationTimeStamp = pts;
    }
    
    var newSampleBuffer: CMSampleBuffer?
    CMSampleBufferCreateCopyWithNewTiming(kCFAllocatorDefault, sampleBuffer, count, pInfo, &newSampleBuffer);
    free(pInfo);
    
    return newSampleBuffer
  }
  
  static func prepareAssetWriter(destinationPath : String,
                                 videoFormatHint: CMAudioFormatDescription,
                                 audioFormatHint: CMAudioFormatDescription?) ->
    (writer: AVAssetWriter?,
    videoInput: AVAssetWriterInput?,
    audioInput:AVAssetWriterInput?)
  {
    var assetWriter: AVAssetWriter?
    do {
      assetWriter = try AVAssetWriter(outputURL: NSURL(fileURLWithPath: destinationPath) as URL, fileType: AVFileTypeMPEG4)
    }
    catch {
      print("Can't create asset writer. Check destinationPath: \(destinationPath).")
      return (nil, nil, nil)
    }
    assetWriter?.shouldOptimizeForNetworkUse = true
    
    // Video input
    let videoDimensions: CMVideoDimensions = CMVideoFormatDescriptionGetDimensions(videoFormatHint as CMVideoFormatDescription)
    let videoSettings: [String : AnyObject] = [AVVideoCodecKey: AVVideoCodecH264 as AnyObject,
                                               AVVideoWidthKey: Int(videoDimensions.width) as AnyObject,
                                               AVVideoHeightKey: Int(videoDimensions.height) as AnyObject]
    let videoInput: AVAssetWriterInput? = AVAssetWriterInput(mediaType: AVMediaTypeVideo,
                                                             outputSettings: videoSettings)
    videoInput?.expectsMediaDataInRealTime = true
    
    if assetWriter!.canAdd(videoInput!) {
      assetWriter!.add(videoInput!)
    }
    else {
      print("Can't add video input")
      return (nil, nil, nil)
    }
    
    let audioSettings: [String : AnyObject] = [AVFormatIDKey: Int(kAudioFormatMPEG4AAC) as AnyObject,
                                               AVNumberOfChannelsKey: 2 as AnyObject]
    let audioInput: AVAssetWriterInput? = AVAssetWriterInput(mediaType: AVMediaTypeAudio,
                                                             outputSettings: audioSettings,
                                                             sourceFormatHint: audioFormatHint)
    audioInput?.expectsMediaDataInRealTime = true
    
    if assetWriter!.canAdd(audioInput!) {
      assetWriter!.add(audioInput!)
    }
    else {
      print("Can't add audio input.")
      return (assetWriter, videoInput, nil)
    }
    
    return (assetWriter, videoInput, audioInput)
  }
  
  static func prepareAssetReader(filePath: String) ->
    (reader: AVAssetReader?,
    videoOutput: AVAssetReaderTrackOutput?,
    audioOutput: AVAssetReaderTrackOutput?)
  {
    var assetReader: AVAssetReader?
    var videoOutput: AVAssetReaderTrackOutput?
    var audioOutput: AVAssetReaderTrackOutput?
    var newfilePath = filePath
    if filePath.range(of:"file://") != nil {
      let index = filePath.index(filePath.startIndex, offsetBy: 7)
      newfilePath = filePath.substring(from: index)
    }
    
    let url = NSURL.fileURL(withPath: newfilePath)
    let asset = AVAsset(url: url)
    
    do {
      assetReader = try AVAssetReader(asset: asset)
    }
    catch {
      print("Can't create asset reader.")
      return (nil, nil, nil)
    }
    
    // Video output
    let videoTracks = asset.tracks(withMediaType: AVMediaTypeVideo)
    if videoTracks.count > 0 {
      let outputVideoSetting: [String: AnyObject] =
        [String(kCVPixelBufferPixelFormatTypeKey): NSNumber(value:kCVPixelFormatType_32ARGB),String(kCVPixelBufferIOSurfacePropertiesKey): [NSNumber:String]() as AnyObject]
      videoOutput = AVAssetReaderTrackOutput(track: videoTracks.first!, outputSettings: outputVideoSetting)
      
      if assetReader!.canAdd(videoOutput!) {
        assetReader!.add(videoOutput!)
      }
      else {
        print("Can't add video ouput.")
        return (nil, nil, nil)
      }
    }
    
    // Audio output
    let audioTracks = asset.tracks(withMediaType: AVMediaTypeAudio)
    if audioTracks.count > 0 {
      let audioSettings: [String : AnyObject] = [AVFormatIDKey: Int(kAudioFormatLinearPCM) as AnyObject,
                                                 AVNumberOfChannelsKey: 2 as AnyObject]
      audioOutput = AVAssetReaderTrackOutput(track: audioTracks.first!, outputSettings: audioSettings)
      if assetReader!.canAdd(audioOutput!) {
        assetReader!.add(audioOutput!)
      }
      else {
        print("Can't add audio ouput.")
        return (assetReader, videoOutput, nil)
      }
    }
    
    return (assetReader, videoOutput, audioOutput)
  }
  
  static func findFormatDescription(filePath: String) ->
    (videoFormatHint: CMFormatDescription?,
    audioFormatHint: CMFormatDescription?)
  {
    let tuple: (reader: AVAssetReader?,
      videoOutput: AVAssetReaderTrackOutput?,
      audioOutput: AVAssetReaderTrackOutput?) = prepareAssetReader(filePath: filePath)
    
    var assetReader: AVAssetReader
    if let test = tuple.reader {
      assetReader = test
    }
    else {
      print("Can't create asset reader.")
      return (nil, nil)
    }
    
    var videoOutput: AVAssetReaderTrackOutput
    if let test = tuple.videoOutput {
      videoOutput = test
    }
    else {
      print("Can't create video output")
      return (nil, nil)
    }
    
    let audioOutput: AVAssetReaderTrackOutput? = tuple.audioOutput
    
    if !assetReader.startReading() {
      print("Can't start reading.")
      return (nil, nil)
    }
    
    var videoFormatHint: CMFormatDescription?
    var audioFormatHint: CMFormatDescription?
    while assetReader.status == .reading
    {
      if let sampleBuffer = videoOutput.copyNextSampleBuffer() {
        videoFormatHint = CMSampleBufferGetFormatDescription(sampleBuffer)
      }
      
      if let sampleBuffer = audioOutput?.copyNextSampleBuffer() {
        audioFormatHint = CMSampleBufferGetFormatDescription(sampleBuffer)
      }
      
      return (videoFormatHint, audioFormatHint)
    }
    
    return (nil, nil)
  }
  
  static func createSilentAudioSampleBufferWithFormatDescription(formatDescription:CMAudioFormatDescription,
                                                                 numSamples: Int,
                                                                 presentationTime: CMTime) -> CMSampleBuffer?
  {
    let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee
    let blockSize: size_t = numSamples * Int(audioStreamBasicDescription!.mBytesPerFrame); // TODO: Probably need to calc in another way
    var blockPointer: CMBlockBuffer? = nil
    CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                                       nil,
                                       blockSize,
                                       nil,
                                       nil,
                                       0,
                                       blockSize,
                                       0,
                                       &blockPointer);
    
    guard let block = blockPointer else {
      return nil
    }
    
    CMBlockBufferFillDataBytes(0, block, 0, blockSize);
    
    var sampleBuffer: CMSampleBuffer? = nil;
    CMAudioSampleBufferCreateReadyWithPacketDescriptions(kCFAllocatorDefault,
                                                         block,
                                                         formatDescription,
                                                         numSamples,
                                                         presentationTime,
                                                         nil,
                                                         &sampleBuffer);
    return sampleBuffer;
  }
}
