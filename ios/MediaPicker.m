//
//  ImageManager.m
//
//  Created by Ivan Pusic on 5/4/16.
//  Copyright © 2016 Facebook. All rights reserved.
//

#import "MediaPicker.h"

#define ERROR_VIDEO_PICKER_UNAUTHORIZED_KEY @"E_VIDEO_PICKER_UNAUTHORIZED"
#define ERROR_VIDEO_PICKER_UNAUTHORIZED_MSG @"Cannot access images. Please allow access if you want to be able to select images."

#define ERROR_MUSIC_PICKER_UNAUTHORIZED_KEY @"E_MUSIC_PICKER_UNAUTHORIZED"
#define ERROR_MUSIC_PICKER_UNAUTHORIZED_MSG @"Cannot access music library. Please allow access if you want to be able to preview music."

#define ERROR_VIDEO_PICKER_CANCEL_KEY @"E_VIDEO_PICKER_CANCELLED"
#define ERROR_VIDEO_PICKER_CANCEL_MSG @"User cancelled video selection"

#define ERROR_MUSIC_PICKER_CANCEL_KEY @"E_MUSIC_PICKER_CANCELLED"
#define ERROR_MUSIC_PICKER_CANCEL_MSG @"User cancelled music selection"

#define ERROR_PICKER_NO_DATA_KEY @"ERROR_PICKER_NO_DATA"
#define ERROR_PICKER_NO_DATA_MSG @"Cannot find video data"

#define ERROR_CLEANUP_ERROR_KEY @"E_ERROR_WHILE_CLEANING_FILES"
#define ERROR_CLEANUP_ERROR_MSG @"Error while cleaning up tmp files"

#define ERROR_CANNOT_PROCESS_VIDEO_KEY @"E_CANNOT_PROCESS_VIDEO"
#define ERROR_CANNOT_PROCESS_VIDEO_MSG @"Cannot process video data"

@implementation MediaPicker

RCT_EXPORT_MODULE();

@synthesize bridge = _bridge;

- (instancetype)init
{
    if (self = [super init]) {
        self.defaultOptions = @{
                                @"multiple": @NO,
                                @"maxFiles": @5,
                                @"includeThumbnailBase64": @NO,
                                @"waitAnimationEnd": @YES,
                                @"thumbnailHeight": @200,
                                @"thumbnailWidth": @200,
                                @"loadingLabelText": @"Processing assets...",
                                @"showsSelectedCount": @YES,
                                @"showsCloudItems": @NO
                                };
    }

    return self;
}

- (void (^ __nullable)(void))waitAnimationEnd:(void (^ __nullable)(void))completion {
    if ([[self.options objectForKey:@"waitAnimationEnd"] boolValue]) {
        return completion;
    }

    if (completion != nil) {
        completion();
    }

    return nil;
}

- (void)checkCameraPermissions:(void(^)(BOOL granted))callback
{
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusAuthorized) {
        callback(YES);
        return;
    } else if (status == AVAuthorizationStatusNotDetermined){
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            callback(granted);
            return;
        }];
    } else {
        callback(NO);
    }
}

- (void) setConfiguration:(NSDictionary *)options
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject {

    self.resolve = resolve;
    self.reject = reject;
    self.options = [NSMutableDictionary dictionaryWithDictionary:self.defaultOptions];
    for (NSString *key in options.keyEnumerator) {
        [self.options setValue:options[key] forKey:key];
    }
}

- (UIViewController*) getRootVC {
    UIViewController *root = [[[[UIApplication sharedApplication] delegate] window] rootViewController];
    while (root.presentedViewController != nil) {
        root = root.presentedViewController;
    }

    return root;
}

RCT_EXPORT_METHOD(openMusicPicker:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {

    [self setConfiguration:options resolver:resolve rejecter:reject];

    [self checkForMusicLibraryAccess:^(BOOL granted) {
        if (!granted) {
            self.reject(ERROR_MUSIC_PICKER_UNAUTHORIZED_KEY, ERROR_MUSIC_PICKER_UNAUTHORIZED_MSG, nil);
            return;
        }
        
        MPMediaPickerController* picker = [[MPMediaPickerController alloc] initWithMediaTypes:MPMediaTypeMusic];
        picker.showsCloudItems = [[self.options objectForKey:@"showsCloudItems"] boolValue];
        picker.delegate = self;
        picker.allowsPickingMultipleItems = [[self.options objectForKey:@"multiple"] boolValue];
        picker.modalPresentationStyle = UIModalPresentationFullScreen;
        dispatch_async(dispatch_get_main_queue(), ^{
            [[self getRootVC] presentViewController:picker animated:YES completion:nil];
        });
    }];
}

- (void) checkForMusicLibraryAccess:(void (^)(BOOL granted))completionHandler {
    switch ([MPMediaLibrary authorizationStatus]) {
        case MPMediaLibraryAuthorizationStatusAuthorized:{
            dispatch_async(dispatch_get_main_queue(), ^{
                completionHandler(YES);
            });
        }
            break;
            
        case MPMediaLibraryAuthorizationStatusNotDetermined: {
            [MPMediaLibrary requestAuthorization:^(MPMediaLibraryAuthorizationStatus status){
                if (status == MPMediaLibraryAuthorizationStatusAuthorized) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completionHandler(YES);
                    });
                } else{
                    completionHandler(NO);
                }
            }];
            break;
        }
            
        case MPMediaLibraryAuthorizationStatusRestricted:
            // do nothing
            completionHandler(NO);
            break;
        case MPMediaLibraryAuthorizationStatusDenied:
            // do nothing, or beg the user to authorize us in Settings
            completionHandler(NO);
            break;
    }
}

- (void)mediaPicker:(MPMediaPickerController *)picker didPickMediaItems:(MPMediaItemCollection *)mediaItemCollection{
    if ([[[self options] objectForKey:@"multiple"] boolValue]) {
        NSMutableArray *selections = [[NSMutableArray alloc] init];
        
        [self showActivityIndicator:^(UIActivityIndicatorView *indicatorView, UIView *overlayView) {
            NSLock *lock = [[NSLock alloc] init];
            __block int processed = 0;
            
            for (MPMediaItem *mediaItem in mediaItemCollection.items) {
                NSDictionary* music = [self createMusicItemResponse: mediaItem
                                                 withThumbanilWidth:[self.options objectForKey:@"width"]withThumbnailHeight:[self.options objectForKey:@"height"]
            includeThumbnailDataBase64: [[self.options objectForKey:@"includeThumbnailBase64"] boolValue]];
                    [lock lock];
                    [selections addObject:music];
                    processed++;
                    [lock unlock];
                
                    if (processed == [mediaItemCollection.items count]) {
                        [indicatorView stopAnimating];
                        [overlayView removeFromSuperview];
                        [picker dismissViewControllerAnimated:YES completion:[self waitAnimationEnd:^{
                            self.resolve(selections);
                        }]];
                        return;
                    }
            }
        }];
    } else {

        [self showActivityIndicator:^(UIActivityIndicatorView *indicatorView, UIView *overlayView) {
            MPMediaItem *mediaItem = [mediaItemCollection.items objectAtIndex:0];
            NSDictionary* music = [self createMusicItemResponse:mediaItem withThumbanilWidth:
                                            [self.options objectForKey:@"width"]
                                            withThumbnailHeight:[self.options objectForKey:@"height"]includeThumbnailDataBase64: [[self.options objectForKey:@"includeThumbnailBase64"] boolValue]];
            [picker dismissViewControllerAnimated:YES completion:[self waitAnimationEnd:^{
                self.resolve(music);
            }]];
        }];
    }
}

- (void)mediaPickerDidCancel:(MPMediaPickerController *)picker{
    [picker dismissViewControllerAnimated:YES completion:[self waitAnimationEnd:^{
        self.reject(ERROR_MUSIC_PICKER_CANCEL_KEY, ERROR_MUSIC_PICKER_CANCEL_MSG, nil);
    }]];
}


RCT_EXPORT_METHOD(openVideoPicker:(NSDictionary *)options
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {

    [self setConfiguration:options resolver:resolve rejecter:reject];

    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized) {
            self.reject(ERROR_VIDEO_PICKER_UNAUTHORIZED_KEY, ERROR_VIDEO_PICKER_UNAUTHORIZED_MSG, nil);
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            // init picker
            QBImagePickerController *imagePickerController = [QBImagePickerController new];
            imagePickerController.delegate = self;
            imagePickerController.allowsMultipleSelection = [[self.options objectForKey:@"multiple"] boolValue];
            imagePickerController.maximumNumberOfSelection = [[self.options objectForKey:@"maxFiles"] intValue];
            imagePickerController.showsNumberOfSelectedAssets = [[self.options objectForKey:@"showsSelectedCount"] boolValue];

            if ([self.options objectForKey:@"smartAlbums"] != nil) {
                NSDictionary *smartAlbums = @{
                                          @"UserLibrary" : @(PHAssetCollectionSubtypeSmartAlbumUserLibrary),
                                          @"PhotoStream" : @(PHAssetCollectionSubtypeAlbumMyPhotoStream),
                                          @"Panoramas" : @(PHAssetCollectionSubtypeSmartAlbumPanoramas),
                                          @"Videos" : @(PHAssetCollectionSubtypeSmartAlbumVideos),
                                          @"Bursts" : @(PHAssetCollectionSubtypeSmartAlbumBursts),
                                          };
                NSMutableArray *albumsToShow = [NSMutableArray arrayWithCapacity:5];
                for (NSString* album in [self.options objectForKey:@"smartAlbums"]) {
                    if ([smartAlbums objectForKey:album] != nil) {
                        [albumsToShow addObject:[smartAlbums objectForKey:album]];
                    }
                }
                imagePickerController.assetCollectionSubtypes = albumsToShow;
            }

            imagePickerController.mediaType = QBImagePickerMediaTypeVideo;

            [[self getRootVC] presentViewController:imagePickerController animated:YES completion:nil];
        });
    }];
}


- (void)showActivityIndicator:(void (^)(UIActivityIndicatorView*, UIView*))handler {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *mainView = [[self getRootVC] view];

        // create overlay
        UIView *loadingView = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
        loadingView.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.5];
        loadingView.clipsToBounds = YES;

        // create loading spinner
        UIActivityIndicatorView *activityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        activityView.frame = CGRectMake(65, 40, activityView.bounds.size.width, activityView.bounds.size.height);
        activityView.center = loadingView.center;
        [loadingView addSubview:activityView];

        // create message
        UILabel *loadingLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 115, 130, 22)];
        loadingLabel.backgroundColor = [UIColor clearColor];
        loadingLabel.textColor = [UIColor whiteColor];
        loadingLabel.adjustsFontSizeToFitWidth = YES;
        CGPoint loadingLabelLocation = loadingView.center;
        loadingLabelLocation.y += [activityView bounds].size.height;
        loadingLabel.center = loadingLabelLocation;
        loadingLabel.textAlignment = UITextAlignmentCenter;
        loadingLabel.text = [self.options objectForKey:@"loadingLabelText"];
        [loadingLabel setFont:[UIFont boldSystemFontOfSize:18]];
        [loadingView addSubview:loadingLabel];

        // show all
        [mainView addSubview:loadingView];
        [activityView startAnimating];

        handler(activityView, loadingView);
    });
}


- (void)getVideoAsset:(PHAsset*)forAsset completion:(void (^)(NSDictionary* image))completion {
    PHImageManager *manager = [PHImageManager defaultManager];
    PHVideoRequestOptions *options = [[PHVideoRequestOptions alloc] init];
    options.version = PHVideoRequestOptionsVersionOriginal;

    [manager
     requestAVAssetForVideo:forAsset
     options:options
     resultHandler:^(AVAsset * asset, AVAudioMix * audioMix,
                     NSDictionary *info) {
         NSURL *sourceURL = [(AVURLAsset *)asset URL];

         AVAssetTrack *track = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
         NSNumber *fileSizeValue = nil;
         [sourceURL getResourceValue:&fileSizeValue
                              forKey:NSURLFileSizeKey
                               error:nil];
         Float64 durationSeconds = CMTimeGetSeconds(asset.duration);
         AVAssetImageGenerator *generateImg = [[AVAssetImageGenerator alloc] initWithAsset:asset];
         NSError *error = NULL;
         // CMTime time = CMTimeMake(1, 1);
         CMTime time = CMTimeMakeWithSeconds(durationSeconds/3.0, 600);
         CGImageRef refImg = [generateImg copyCGImageAtTime:time actualTime:NULL error:&error];
         NSLog(@"error==%@, Refimage==%@", error, refImg);
         
         NSString *thumbnailFilePath;
         NSNumber *thumbnailSize;
         NSNumber *thumbnailWidth;
         NSNumber *thumbnailHeight;
         NSString *dataBas64;
         
         if (refImg) {
             UIImage *image = [[UIImage alloc] initWithCGImage:refImg];
             thumbnailWidth = [NSNumber numberWithUnsignedInteger:image.size.width];
             thumbnailHeight = [NSNumber numberWithUnsignedInteger:image.size.height];
             NSData *data = UIImageJPEGRepresentation(image, 1);
             thumbnailSize = [NSNumber numberWithUnsignedInteger:data.length];
             thumbnailFilePath = [self persistFile:data];
             if ([[self.options objectForKey:@"includeThumbnailBase64"] boolValue]) {
                 dataBas64 = [data base64EncodedStringWithOptions:0];
             }
           CGImageRelease(refImg);
         }
         
         completion([self  createVideoItemResponse:[sourceURL absoluteString]
                                          withWidth:[NSNumber numberWithFloat:track.naturalSize.width]
                                         withHeight:[NSNumber numberWithFloat:track.naturalSize.height]
                                           withSize:fileSizeValue
                                       withDuration:[NSNumber numberWithFloat:durationSeconds]
                                  withThumbnailPath:thumbnailFilePath
                                 withThumbnailWidth:thumbnailWidth
                                withThumbnailHeight:thumbnailHeight
                                  withThumbnailSize:thumbnailSize
                                  withThumbnailData:dataBas64
                      ]
                     );

     }];
}


- (void)qb_imagePickerController:
(QBImagePickerController *)imagePickerController
          didFinishPickingAssets:(NSArray *)assets {

    PHImageRequestOptions* options = [[PHImageRequestOptions alloc] init];
    options.synchronous = NO;
    options.networkAccessAllowed = YES;

    if ([[[self options] objectForKey:@"multiple"] boolValue]) {
        NSMutableArray *selections = [[NSMutableArray alloc] init];

        [self showActivityIndicator:^(UIActivityIndicatorView *indicatorView, UIView *overlayView) {
            NSLock *lock = [[NSLock alloc] init];
            __block int processed = 0;

            for (PHAsset *phAsset in assets) {

                if (phAsset.mediaType == PHAssetMediaTypeVideo) {
                    [self getVideoAsset:phAsset completion:^(NSDictionary* video) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [lock lock];

                            if (video == nil) {
                                [indicatorView stopAnimating];
                                [overlayView removeFromSuperview];
                                [imagePickerController dismissViewControllerAnimated:YES completion:[self waitAnimationEnd:^{
                                    self.reject(ERROR_CANNOT_PROCESS_VIDEO_KEY, ERROR_CANNOT_PROCESS_VIDEO_MSG, nil);
                                }]];
                                return;
                            }

                            [selections addObject:video];
                            processed++;
                            [lock unlock];

                            if (processed == [assets count]) {
                                [indicatorView stopAnimating];
                                [overlayView removeFromSuperview];
                                [imagePickerController dismissViewControllerAnimated:YES completion:[self waitAnimationEnd:^{
                                    self.resolve(selections);
                                }]];
                                return;
                            }
                        });
                    }];
                }
            }
        }];
    } else {
        PHAsset *phAsset = [assets objectAtIndex:0];

        [self showActivityIndicator:^(UIActivityIndicatorView *indicatorView, UIView *overlayView) {
            if (phAsset.mediaType == PHAssetMediaTypeVideo) {
                [self getVideoAsset:phAsset completion:^(NSDictionary* video) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [indicatorView stopAnimating];
                        [overlayView removeFromSuperview];
                        [imagePickerController dismissViewControllerAnimated:YES completion:[self waitAnimationEnd:^{
                            if (video != nil) {
                                self.resolve(video);
                            } else {
                                self.reject(ERROR_CANNOT_PROCESS_VIDEO_KEY, ERROR_CANNOT_PROCESS_VIDEO_MSG, nil);
                            }
                        }]];
                    });
                }];
            }
        }];
    }
}

- (void)qb_imagePickerControllerDidCancel:(QBImagePickerController *)imagePickerController {
    [imagePickerController dismissViewControllerAnimated:YES completion:[self waitAnimationEnd:^{
        self.reject(ERROR_VIDEO_PICKER_CANCEL_KEY, ERROR_VIDEO_PICKER_CANCEL_MSG, nil);
    }]];
}

- (NSDictionary*) createVideoItemResponse:(NSString*)filePath
                                withWidth:(NSNumber*)width
                               withHeight:(NSNumber*)height
                                 withSize:(NSNumber*)size
                             withDuration: (NSNumber*)duration
                       withThumbnailPath:(NSString*)thumbnailPath
                       withThumbnailWidth:(NSNumber*)thumbnailWidth
                      withThumbnailHeight:(NSNumber*)thumbnailHeight
                        withThumbnailSize:(NSNumber*)thumbnailSize
                        withThumbnailData:(NSString*) thumbnailData
    {
    return @{
             @"path": filePath,
             @"width": width,
             @"height": height,
             @"size": size,
             @"duration": duration,
             @"thumbnailPath": thumbnailPath,
             @"thumbnailMime": @"image/jpeg",
             @"thumbnailDataSize": thumbnailSize,
             @"thumbnailData": thumbnailData,
             @"thumbnailWidth": thumbnailWidth,
             @"thumbnailHeight": thumbnailHeight,
             };
}

- (NSDictionary*) createMusicItemResponse: (MPMediaItem *)mediaItem withThumbanilWidth:(NSNumber*)width withThumbnailHeight:(NSNumber*)height includeThumbnailDataBase64: (BOOL) include {
    NSString* artworkFilePath = nil;
    NSString* artworkDataBas64 = nil;
    NSNumber* artworkDataSize;
    NSNumber* thumbnailWidth;
    NSNumber* thumbnailHeight;
    
    if (mediaItem.artwork) {
        MPMediaItemArtwork* mediaItemArtwork = mediaItem.artwork;
      
        CGSize maskSize = CGSizeMake([width intValue], [height intValue]);
        UIImage* image =  [mediaItemArtwork imageWithSize: maskSize];
        thumbnailWidth = [NSNumber numberWithUnsignedInteger:image.size.width];
        thumbnailHeight = [NSNumber numberWithUnsignedInteger:image.size.height];
        NSData* artworkData = UIImageJPEGRepresentation(image, 1);
        artworkDataSize = [NSNumber numberWithUnsignedInteger:artworkData.length];
        artworkFilePath = [self persistFile:artworkData];
        if (include) {
            artworkDataBas64 = [artworkData base64EncodedStringWithOptions:0];
        }
    }
    
    return @{
             @"path": mediaItem.assetURL,
             @"albumTitle": mediaItem.albumTitle,
             @"albumArtist": mediaItem.albumArtist,
             @"artist": mediaItem.artist,
             @"title": mediaItem.title,
             @"cloudItem": mediaItem.cloudItem? @"YES" : @"NO",
             @"duration": [NSNumber numberWithDouble:mediaItem.playbackDuration],
             @"thumbnailPath": artworkFilePath,
             @"thumbnailMime": @"image/jpeg",
             @"thumbnailDataSize": artworkDataSize,
             @"thumbnailData": artworkDataBas64,
             @"thumbnailWidth": thumbnailWidth,
             @"thumbnailHeight": thumbnailHeight,
             };
}


- (NSString*) getTmpDirectory {
    NSString *TMP_DIRECTORY = @"react-native-media-picker/";
    NSString *tmpFullPath = [NSTemporaryDirectory() stringByAppendingString:TMP_DIRECTORY];
    
    BOOL isDir;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:tmpFullPath isDirectory:&isDir];
    if (!exists) {
        [[NSFileManager defaultManager] createDirectoryAtPath: tmpFullPath
                                  withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    return tmpFullPath;
}

- (BOOL)cleanTmpDirectory {
    NSString* tmpDirectoryPath = [self getTmpDirectory];
    NSArray* tmpDirectory = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:tmpDirectoryPath error:NULL];
    
    for (NSString *file in tmpDirectory) {
        BOOL deleted = [[NSFileManager defaultManager] removeItemAtPath:[NSString stringWithFormat:@"%@%@", tmpDirectoryPath, file] error:NULL];
        
        if (!deleted) {
            return NO;
        }
    }
    
    return YES;
}

RCT_EXPORT_METHOD(cleanSingle:(NSString *) path
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    
    BOOL deleted = [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    
    if (!deleted) {
        reject(ERROR_CLEANUP_ERROR_KEY, ERROR_CLEANUP_ERROR_MSG, nil);
    } else {
        resolve(nil);
    }
}

RCT_REMAP_METHOD(clean, resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject) {
    if (![self cleanTmpDirectory]) {
        reject(ERROR_CLEANUP_ERROR_KEY, ERROR_CLEANUP_ERROR_MSG, nil);
    } else {
        resolve(nil);
    }
}

// at the moment it is not possible to upload image by reading PHAsset
// we are saving image and saving it to the tmp location where we are allowed to access image later
- (NSString*) persistFile:(NSData*)data {
    // create temp file
    NSString *tmpDirFullPath = [self getTmpDirectory];
    NSString *filePath = [tmpDirFullPath stringByAppendingString:[[NSUUID UUID] UUIDString]];
    filePath = [filePath stringByAppendingString:@".jpg"];
    
    // save cropped file
    BOOL status = [data writeToFile:filePath atomically:YES];
    if (!status) {
        return nil;
    }
    
    return filePath;
}

@end
