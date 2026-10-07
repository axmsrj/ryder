//
//  RWModelLoader.h
//  Ryder
//
//  Created by Alex Marcelle on 07/10/26.
//

#import <Foundation/Foundation.h>
#import <SceneKit/SceneKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RWDFFInfo : NSObject

@property (nonatomic, readonly) NSUInteger chunkLength;
@property (nonatomic, readonly) NSUInteger version;
@property (nonatomic, readonly) NSUInteger build;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface RWTextureDictionary : NSObject

@property (nonatomic, readonly) NSUInteger textureCount;
@property (nonatomic, readonly) NSArray<NSString *> *textureNames;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface RWModelLoader : NSObject

- (nullable RWDFFInfo *)inspectDFFData:(NSData *)data
                                 error:(NSError * _Nullable * _Nullable)error;

- (nullable SCNNode *)loadDFFData:(NSData *)data
                            error:(NSError * _Nullable * _Nullable)error;

- (nullable SCNNode *)loadDFFData:(NSData *)data
                textureDictionary:(nullable RWTextureDictionary *)textureDictionary
                            error:(NSError * _Nullable * _Nullable)error;

- (nullable RWTextureDictionary *)loadTXDData:(NSData *)data
                                         error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
