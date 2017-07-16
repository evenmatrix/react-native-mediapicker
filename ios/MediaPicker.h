//
//  ImageManager.h
//
//  Created by Ivan Pusic on 5/4/16.
//  Copyright © 2016 Facebook. All rights reserved.
//

#ifndef RN_IMAGE_CROP_PICKER_h
#define RN_IMAGE_CROP_PICKER_h

#import <Foundation/Foundation.h>

#if __has_include("RCTBridgeModule.h")
#import "RCTBridgeModule.h"
#else
#import <React/RCTBridgeModule.h>
#endif

#if __has_include("QBImagePicker.h")
#import "QBImagePicker.h"
#else
#import "QBImagePicker/QBImagePicker.h"
#endif
#import <MediaPlayer/MediaPlayer.h>


@interface MediaPicker : NSObject<
  RCTBridgeModule,
  QBImagePickerControllerDelegate,
  MPMediaPickerControllerDelegate>

@property (nonatomic, strong) NSDictionary *defaultOptions;
@property (nonatomic, retain) NSMutableDictionary *options;
@property (nonatomic, strong) RCTPromiseResolveBlock resolve;
@property (nonatomic, strong) RCTPromiseRejectBlock reject;

@end

#endif
