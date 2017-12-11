

import Foundation
import AVFoundation


class VideoMergeManager
{
  static func mergeMultipleVideos(destinationPath: String, assetsArray:[AVAsset], finished: @escaping ((String?, NSURL?) -> Void)){
    
    
    let composition = AVMutableComposition()
    
    let videoTrack = composition.addMutableTrack(
      withMediaType: AVMediaTypeVideo,
      preferredTrackID: kCMPersistentTrackID_Invalid
    )
    
    let audioTrack = composition.addMutableTrack(
      withMediaType: AVMediaTypeAudio,
      preferredTrackID: kCMPersistentTrackID_Invalid
    )
    
    var totalDuration = kCMTimeZero
    var index = 0;
    assetsArray.forEach { (asset) in
      do {
        try videoTrack.insertTimeRange(CMTimeRangeMake(kCMTimeZero, asset.duration),
                                       of: asset.tracks(withMediaType: AVMediaTypeVideo)[0],
                                       at: totalDuration)
       

        
        try audioTrack.insertTimeRange(CMTimeRangeMake(kCMTimeZero, asset.duration),
                                       of: asset.tracks(withMediaType: AVMediaTypeAudio)[0] ,
                                       at: totalDuration)
        
        totalDuration = CMTimeAdd(totalDuration, asset.duration)
        index = index+1;
      } catch let error {
        finished("Failed: \(String(describing: error))", nil)
      }
    }
    
    //let mainComposition = AVMutableVideoComposition()
    //mainComposition.renderSize = CGSize(width: 1280.0, height: 720.0)
    
    let url = NSURL(fileURLWithPath: destinationPath)
    
    
    guard let assetExporter = AVAssetExportSession(asset: composition,presetName: AVAssetExportPreset640x480) else { return }
    
    assetExporter.outputURL = url as URL
    assetExporter.outputFileType = AVFileTypeMPEG4
    assetExporter.shouldOptimizeForNetworkUse = true
    //assetExporter.videoComposition = mainComposition;
    
    
    
    assetExporter.exportAsynchronously(completionHandler: {
      switch assetExporter.status {
      case .completed:
        finished(nil, NSURL(fileURLWithPath: destinationPath))
      case .failed:
        finished("Failed: \(String(describing: assetExporter.error))", nil)
      default: break
      }
    })
  }
}