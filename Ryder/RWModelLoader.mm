//
//  RWModelLoader.mm
//  Ryder
//
//  Created by Alex Marcelle on 07/10/26.
//

#import "RWModelLoader.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <mutex>
#include <vector>

#include <rw.h>

namespace {

NSString *const RWModelLoaderErrorDomain = @"com.axmsrj.Ryder.RWModelLoader";

enum class RWModelLoaderError : NSInteger {
    EmptyData = 1,
    DataTooLarge,
    InvalidRenderWareHeader,
    NotAClump,
    EngineInitializationFailed,
    ClumpReadFailed,
    UnsupportedNativeGeometry,
    EmptyClump,
    NotATextureDictionary,
    TextureDictionaryReadFailed,
    TextureConversionFailed
};

NSError *makeError(RWModelLoaderError code, NSString *description)
{
    return [NSError errorWithDomain:RWModelLoaderErrorDomain
                               code:static_cast<NSInteger>(code)
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

bool startRenderWare(void)
{
    static std::once_flag once;
    static bool started = false;

    std::call_once(once, [] {
        if (!rw::Engine::init()) {
            return;
        }

        rw::registerMeshPlugin();
        rw::registerNativeDataPlugin();
        rw::registerAtomicRightsPlugin();
        rw::registerMaterialRightsPlugin();
        rw::registerSkinPlugin();
        rw::registerUserDataPlugin();
        rw::registerHAnimPlugin();
        rw::registerMatFXPlugin();
        rw::registerUVAnimPlugin();

        if (!rw::Engine::open(nullptr) || !rw::Engine::start()) {
            return;
        }

        rw::Texture::setLoadTextures(true);
        rw::Texture::setCreateDummies(false);
        started = true;
    });

    return started;
}

struct Float3 { float x; float y; float z; };

rw::Texture *readTextureReference(const char *name, const char *mask)
{
    rw::Texture *texture = rw::Texture::create(nullptr);
    if (!texture) {
        return nullptr;
    }

    if (name) {
        std::strncpy(texture->name, name, sizeof(texture->name));
        texture->name[sizeof(texture->name) - 1] = '\0';
    }
    if (mask) {
        std::strncpy(texture->mask, mask, sizeof(texture->mask));
        texture->mask[sizeof(texture->mask) - 1] = '\0';
    }
    return texture;
}

Float3 transformPosition(const rw::V3d &position, const rw::Matrix &matrix)
{
    float x = matrix.right.x * position.x + matrix.up.x * position.y + matrix.at.x * position.z + matrix.pos.x;
    float y = matrix.right.y * position.x + matrix.up.y * position.y + matrix.at.y * position.z + matrix.pos.y;
    float z = matrix.right.z * position.x + matrix.up.z * position.y + matrix.at.z * position.z + matrix.pos.z;

    return { x, z, -y };
}

Float3 transformNormal(const rw::V3d &normal, const rw::Matrix &matrix)
{
    float x = matrix.right.x * normal.x + matrix.up.x * normal.y + matrix.at.x * normal.z;
    float y = matrix.right.y * normal.x + matrix.up.y * normal.y + matrix.at.y * normal.z;
    float z = matrix.right.z * normal.x + matrix.up.z * normal.y + matrix.at.z * normal.z;
    float length = std::sqrt(x * x + y * y + z * z);

    if (length > 0.0f) {
        x /= length;
        y /= length;
        z /= length;
    }

    return { x, z, -y };
}

SCNGeometrySource *sourceWithVectors(const void *bytes,
                                     NSUInteger byteLength,
                                     NSString *semantic,
                                     NSInteger vectorCount,
                                     NSInteger components,
                                     NSInteger stride)
{
    NSData *data = [NSData dataWithBytes:bytes length:byteLength];
    return [SCNGeometrySource geometrySourceWithData:data
                                            semantic:semantic
                                         vectorCount:vectorCount
                                     floatComponents:YES
                                 componentsPerVector:components
                                   bytesPerComponent:sizeof(float)
                                          dataOffset:0
                                          dataStride:stride];
}

NSString *normalizedTextureName(const char *name)
{
    if (!name) {
        return @"";
    }

    NSString *value = [NSString stringWithCString:name encoding:NSWindowsCP1252StringEncoding];
    if (!value) {
        value = [NSString stringWithCString:name encoding:NSISOLatin1StringEncoding];
    }
    return value.lowercaseString ?: @"";
}

SCNMaterial *sceneMaterial(rw::Material *material,
                           NSDictionary<NSString *, NSImage *> *textures)
{
    SCNMaterial *result = [SCNMaterial material];
    result.doubleSided = YES;
    result.lightingModelName = SCNLightingModelPhysicallyBased;
    result.roughness.contents = @0.8;
    result.metalness.contents = @0.0;

    if (material) {
        const CGFloat divisor = 255.0;
        rw::RGBA color = material->color;
        NSColor *materialColor = [NSColor colorWithSRGBRed:color.red / divisor
                                                    green:color.green / divisor
                                                     blue:color.blue / divisor
                                                    alpha:color.alpha / divisor];
        NSString *textureName = material->texture
            ? normalizedTextureName(material->texture->name)
            : @"";
        NSImage *image = textures[textureName];

        if (image) {
            result.diffuse.contents = image;
            result.diffuse.wrapS = SCNWrapModeRepeat;
            result.diffuse.wrapT = SCNWrapModeRepeat;
            result.multiply.contents = materialColor;
        } else {
            result.diffuse.contents = materialColor;
        }
        result.transparency = color.alpha / divisor;
    } else {
        result.diffuse.contents = NSColor.lightGrayColor;
    }

    return result;
}

SCNNode *nodeForAtomic(rw::Atomic *atomic,
                       NSDictionary<NSString *, NSImage *> *textures,
                       bool &sawNativeGeometry)
{
    rw::Geometry *geometry = atomic->geometry;
    if (!geometry || geometry->numVertices <= 0 || geometry->numTriangles <= 0 ||
        geometry->numMorphTargets <= 0) {
        return nil;
    }

    rw::MorphTarget &morphTarget = geometry->morphTargets[0];
    if (!morphTarget.vertices) {
        sawNativeGeometry = true;
        return nil;
    }

    rw::Matrix *matrix = atomic->getFrame()->getLTM();
    std::vector<Float3> positions(geometry->numVertices);
    for (int32_t index = 0; index < geometry->numVertices; index++) {
        positions[index] = transformPosition(morphTarget.vertices[index], *matrix);
    }

    NSMutableArray<SCNGeometrySource *> *sources = [NSMutableArray array];
    [sources addObject:sourceWithVectors(positions.data(),
                                         positions.size() * sizeof(Float3),
                                         SCNGeometrySourceSemanticVertex,
                                         geometry->numVertices,
                                         3,
                                         sizeof(Float3))];

    if (morphTarget.normals) {
        std::vector<Float3> normals(geometry->numVertices);
        for (int32_t index = 0; index < geometry->numVertices; index++) {
            normals[index] = transformNormal(morphTarget.normals[index], *matrix);
        }
        [sources addObject:sourceWithVectors(normals.data(),
                                             normals.size() * sizeof(Float3),
                                             SCNGeometrySourceSemanticNormal,
                                             geometry->numVertices,
                                             3,
                                             sizeof(Float3))];
    }

    struct TextureCoordinate { float u; float v; };
    if (geometry->numTexCoordSets > 0 && geometry->texCoords[0]) {
        std::vector<TextureCoordinate> coordinates(geometry->numVertices);
        for (int32_t index = 0; index < geometry->numVertices; index++) {
            coordinates[index] = { geometry->texCoords[0][index].u,
                                   1.0f - geometry->texCoords[0][index].v };
        }
        [sources addObject:sourceWithVectors(coordinates.data(),
                                             coordinates.size() * sizeof(TextureCoordinate),
                                             SCNGeometrySourceSemanticTexcoord,
                                             geometry->numVertices,
                                             2,
                                             sizeof(TextureCoordinate))];
    }

    int32_t materialCount = std::max(geometry->matList.numMaterials, 1);
    std::vector<std::vector<uint32_t>> indices(static_cast<size_t>(materialCount));
    for (int32_t triangleIndex = 0; triangleIndex < geometry->numTriangles; triangleIndex++) {
        const rw::Triangle &triangle = geometry->triangles[triangleIndex];
        int32_t materialIndex = triangle.matId < materialCount ? triangle.matId : 0;
        indices[materialIndex].push_back(triangle.v[0]);
        indices[materialIndex].push_back(triangle.v[1]);
        indices[materialIndex].push_back(triangle.v[2]);
    }

    NSMutableArray<SCNGeometryElement *> *elements = [NSMutableArray array];
    NSMutableArray<SCNMaterial *> *materials = [NSMutableArray array];
    for (int32_t materialIndex = 0; materialIndex < materialCount; materialIndex++) {
        std::vector<uint32_t> &materialIndices = indices[materialIndex];
        if (materialIndices.empty()) {
            continue;
        }

        NSData *indexData = [NSData dataWithBytes:materialIndices.data()
                                           length:materialIndices.size() * sizeof(uint32_t)];
        SCNGeometryElement *element = [SCNGeometryElement geometryElementWithData:indexData
                                                                    primitiveType:SCNGeometryPrimitiveTypeTriangles
                                                                   primitiveCount:materialIndices.size() / 3
                                                                    bytesPerIndex:sizeof(uint32_t)];
        [elements addObject:element];

        rw::Material *material = materialIndex < geometry->matList.numMaterials
            ? geometry->matList.materials[materialIndex]
            : nullptr;
        [materials addObject:sceneMaterial(material, textures)];
    }

    SCNGeometry *sceneGeometry = [SCNGeometry geometryWithSources:sources elements:elements];
    sceneGeometry.materials = materials;
    return [SCNNode nodeWithGeometry:sceneGeometry];
}

NSImage *sceneImage(rw::Raster *raster)
{
    if (!raster) {
        return nil;
    }

    rw::Image *image = raster->toImage();
    if (!image) {
        return nil;
    }

    image->convertTo32();
    NSBitmapImageRep *representation = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:nullptr
                      pixelsWide:image->width
                      pixelsHigh:image->height
                   bitsPerSample:8
                 samplesPerPixel:4
                        hasAlpha:YES
                        isPlanar:NO
                  colorSpaceName:NSDeviceRGBColorSpace
                    bitmapFormat:NSBitmapFormatAlphaNonpremultiplied
                     bytesPerRow:image->width * 4
                    bitsPerPixel:32];

    if (!representation) {
        image->destroy();
        return nil;
    }

    for (int32_t row = 0; row < image->height; row++) {
        std::memcpy(representation.bitmapData + row * representation.bytesPerRow,
                    image->pixels + row * image->stride,
                    image->width * 4);
    }

    NSImage *result = [[NSImage alloc]
        initWithSize:NSMakeSize(image->width, image->height)];
    [result addRepresentation:representation];
    image->destroy();
    return result;
}

}

@interface RWTextureDictionary ()

@property (nonatomic, readwrite) NSDictionary<NSString *, NSImage *> *images;

- (instancetype)initWithImages:(NSDictionary<NSString *, NSImage *> *)images;

@end

@implementation RWTextureDictionary

- (instancetype)initWithImages:(NSDictionary<NSString *, NSImage *> *)images
{
    self = [super init];
    if (self) {
        _images = [images copy];
    }
    return self;
}

- (NSUInteger)textureCount
{
    return self.images.count;
}

- (NSArray<NSString *> *)textureNames
{
    return [self.images.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

@end

@interface RWDFFInfo ()

@property (nonatomic, readwrite) NSUInteger chunkLength;
@property (nonatomic, readwrite) NSUInteger version;
@property (nonatomic, readwrite) NSUInteger build;

- (instancetype)initWithChunkLength:(NSUInteger)chunkLength
                             version:(NSUInteger)version
                               build:(NSUInteger)build;

@end


@implementation RWDFFInfo

- (instancetype)initWithChunkLength:(NSUInteger)chunkLength
                             version:(NSUInteger)version
                               build:(NSUInteger)build
{
    self = [super init];
    if (self) {
        _chunkLength = chunkLength;
        _version = version;
        _build = build;
    }
    return self;
}

@end


@implementation RWModelLoader

- (RWDFFInfo *)inspectDFFData:(NSData *)data error:(NSError **)error
{
    if (data.length < 12) {
        if (error) {
            *error = makeError(RWModelLoaderError::EmptyData,
                               @"The DFF data is too small to contain a RenderWare chunk header.");
        }
        return nil;
    }

    if (data.length > std::numeric_limits<rw::uint32>::max()) {
        if (error) {
            *error = makeError(RWModelLoaderError::DataTooLarge,
                               @"The DFF data is too large for librw's memory stream.");
        }
        return nil;
    }

    std::vector<rw::uint8> bytes(data.length);
    [data getBytes:bytes.data() length:data.length];

    rw::StreamMemory stream;
    stream.open(bytes.data(), static_cast<rw::uint32>(bytes.size()));

    rw::ChunkHeaderInfo header{};
    if (!rw::readChunkHeaderInfo(&stream, &header)) {
        if (error) {
            *error = makeError(RWModelLoaderError::InvalidRenderWareHeader,
                               @"librw could not read the RenderWare chunk header.");
        }
        return nil;
    }

    if (header.type != rw::ID_CLUMP) {
        if (error) {
            *error = makeError(RWModelLoaderError::NotAClump,
                               @"The selected data is not a RenderWare clump (DFF).");
        }
        return nil;
    }

    return [[RWDFFInfo alloc] initWithChunkLength:header.length
                                          version:header.version
                                            build:header.build];
}

- (SCNNode *)loadDFFData:(NSData *)data error:(NSError **)error
{
    return [self loadDFFData:data textureDictionary:nil error:error];
}

- (SCNNode *)loadDFFData:(NSData *)data
        textureDictionary:(RWTextureDictionary *)textureDictionary
                    error:(NSError **)error
{
    if (!startRenderWare()) {
        if (error) {
            *error = makeError(RWModelLoaderError::EngineInitializationFailed,
                               @"librw could not initialize its RenderWare engine.");
        }
        return nil;
    }

    RWDFFInfo *info = [self inspectDFFData:data error:error];
    if (!info) {
        return nil;
    }

    std::vector<rw::uint8> bytes(data.length);
    [data getBytes:bytes.data() length:data.length];

    rw::StreamMemory stream;
    stream.open(bytes.data(), static_cast<rw::uint32>(bytes.size()));

    rw::ChunkHeaderInfo header{};
    rw::readChunkHeaderInfo(&stream, &header);
    rw::version = header.version;
    rw::build = header.build;

    rw::Texture::readCB = readTextureReference;
    rw::Clump *clump = rw::Clump::streamRead(&stream);
    if (!clump) {
        if (error) {
            *error = makeError(RWModelLoaderError::ClumpReadFailed,
                               @"librw found a DFF header but could not read its clump.");
        }
        return nil;
    }

    SCNNode *root = [SCNNode node];
    bool sawNativeGeometry = false;
    FORLIST(link, clump->atomics) {
        rw::Atomic *atomic = rw::Atomic::fromClump(link);
        SCNNode *node = nodeForAtomic(atomic,
                                      textureDictionary.images ?: @{},
                                      sawNativeGeometry);
        if (node) {
            [root addChildNode:node];
        }
    }

    clump->destroy();

    if (root.childNodes.count == 0) {
        if (error) {
            NSString *message = sawNativeGeometry
                ? @"This DFF stores native platform geometry that this preview cannot convert yet."
                : @"The DFF clump does not contain renderable triangle geometry.";
            *error = makeError(sawNativeGeometry
                                   ? RWModelLoaderError::UnsupportedNativeGeometry
                                   : RWModelLoaderError::EmptyClump,
                               message);
        }
        return nil;
    }

    return root;
}

- (RWTextureDictionary *)loadTXDData:(NSData *)data error:(NSError **)error
{
    if (!startRenderWare()) {
        if (error) {
            *error = makeError(RWModelLoaderError::EngineInitializationFailed,
                               @"librw could not initialize its RenderWare engine.");
        }
        return nil;
    }

    if (data.length < 12 || data.length > std::numeric_limits<rw::uint32>::max()) {
        if (error) {
            *error = makeError(RWModelLoaderError::InvalidRenderWareHeader,
                               @"The TXD data does not contain a valid RenderWare header.");
        }
        return nil;
    }

    std::vector<rw::uint8> bytes(data.length);
    [data getBytes:bytes.data() length:data.length];

    rw::StreamMemory stream;
    stream.open(bytes.data(), static_cast<rw::uint32>(bytes.size()));

    rw::ChunkHeaderInfo header{};
    if (!rw::readChunkHeaderInfo(&stream, &header) || header.type != rw::ID_TEXDICTIONARY) {
        if (error) {
            *error = makeError(RWModelLoaderError::NotATextureDictionary,
                               @"The selected data is not a RenderWare texture dictionary (TXD).");
        }
        return nil;
    }

    rw::version = header.version;
    rw::build = header.build;
    rw::TexDictionary *dictionary = rw::TexDictionary::streamRead(&stream);
    if (!dictionary) {
        if (error) {
            *error = makeError(RWModelLoaderError::TextureDictionaryReadFailed,
                               @"librw could not read the texture dictionary.");
        }
        return nil;
    }

    NSMutableDictionary<NSString *, NSImage *> *images = [NSMutableDictionary dictionary];
    FORLIST(link, dictionary->textures) {
        rw::Texture *texture = rw::Texture::fromDict(link);
        NSImage *image = sceneImage(texture->raster);
        if (image) {
            images[normalizedTextureName(texture->name)] = image;
        }
    }

    dictionary->destroy();

    if (images.count == 0) {
        if (error) {
            *error = makeError(RWModelLoaderError::TextureConversionFailed,
                               @"The TXD does not contain textures that could be converted.");
        }
        return nil;
    }

    return [[RWTextureDictionary alloc] initWithImages:images];
}

@end
