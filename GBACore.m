#import "GBACore.h"
#include <mgba/core/core.h>
#include <mgba/core/blip_buf.h>
#include <mgba/core/serialize.h>
#include <mgba/core/cheats.h>
#include <mgba-util/vfs.h>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

#define GBA_W 240
#define GBA_H 160
#define OUT_RATE 48000

@implementation GBACore {
    struct mCore *_core;
    uint32_t *_video;
    NSString *_path;
}

- (BOOL)loadROMAtPath:(NSString *)path error:(NSError **)error {
    [self shutdown];
    // Reject obviously wrong files before they reach the emulator core (GBA ROMs are 192 B .. 32 MB).
    unsigned long long size = [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileSize];
    if (size < 192 || size > 32ull * 1024 * 1024) {
        if (error) *error = [NSError errorWithDomain:@"GBA" code:3 userInfo:@{NSLocalizedDescriptionKey:@"That file isn't a valid GBA ROM size"}];
        return NO;
    }
    _core = mCoreFind(path.fileSystemRepresentation);
    if (!_core) { if (error) *error = [NSError errorWithDomain:@"GBA" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Not a GBA ROM"}]; return NO; }
    _core->init(_core);
    mCoreInitConfig(_core, NULL);
    _video = calloc(GBA_W * GBA_H, 4);
    _core->setVideoBuffer(_core, (mColor *)_video, GBA_W);
    if (!mCoreLoadFile(_core, path.fileSystemRepresentation)) {
        if (error) *error = [NSError errorWithDomain:@"GBA" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Could not load ROM"}];
        [self shutdown]; return NO;
    }
    mCoreAutoloadSave(_core);           // .sav next to the ROM
    _core->setAudioBufferSize(_core, 2048);
    blip_set_rates(_core->getAudioChannel(_core, 0), _core->frequency(_core), OUT_RATE);
    blip_set_rates(_core->getAudioChannel(_core, 1), _core->frequency(_core), OUT_RATE);
    _core->reset(_core);
    _path = path;
    return YES;
}

- (void)runFrame { if (_core) _core->runFrame(_core); }
- (void)setKeys:(GBAKey)keys { if (_core) _core->setKeys(_core, keys); }

- (void)copyVideoTo:(uint32_t *)dst { if (_video) memcpy(dst, _video, GBA_W * GBA_H * 4); }

- (CGImageRef)copyFrameImage {
    if (!_video) return NULL;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CFDataRef data = CFDataCreate(NULL, (const UInt8 *)_video, GBA_W * GBA_H * 4);
    CGDataProviderRef dp = CGDataProviderCreateWithCFData(data);
    // mGBA's default 32-bit mColor is bytes R,G,B,X on little-endian.
    CGImageRef img = CGImageCreate(GBA_W, GBA_H, 8, 32, GBA_W * 4, cs,
        kCGBitmapByteOrderDefault | kCGImageAlphaNoneSkipLast, dp, NULL, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(dp); CFRelease(data); CGColorSpaceRelease(cs);
    return img;
}

- (NSInteger)readAudio:(int16_t *)buffer frames:(NSInteger)frames {
    if (!_core) return 0;
    blip_t *l = _core->getAudioChannel(_core, 0), *r = _core->getAudioChannel(_core, 1);
    int avail = MIN(MIN(blip_samples_avail(l), blip_samples_avail(r)), (int)frames);   // keep L/R in lock-step
    blip_read_samples(l, buffer, avail, 1);
    blip_read_samples(r, buffer + 1, avail, 1);
    return avail;
}

- (NSData *)captureState {
    if (!_core) return nil;
    struct VFile *vf = VFileMemChunk(NULL, 0);
    if (!mCoreSaveStateNamed(_core, vf, 0)) { vf->close(vf); return nil; }
    size_t size = vf->size(vf);
    NSMutableData *d = [NSMutableData dataWithLength:size];
    vf->seek(vf, 0, SEEK_SET);
    vf->read(vf, d.mutableBytes, size);
    vf->close(vf);
    return d;
}

- (BOOL)restoreState:(NSData *)data {
    if (!_core || !data.length) return NO;
    struct VFile *vf = VFileFromConstMemory(data.bytes, data.length);
    BOOL ok = mCoreLoadStateNamed(_core, vf, 0);
    vf->close(vf);
    return ok;
}

- (void)applyCheats:(NSArray<NSString *> *)blocks {
    if (!_core) return;
    struct mCheatDevice *dev = _core->cheatDevice(_core);
    if (!dev) return;
    mCheatDeviceClear(dev);
    for (NSString *block in blocks) {
        struct mCheatSet *set = dev->createSet(dev, "cheat");
        for (NSString *line in [block componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
            NSString *t = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (t.length) mCheatAddLine(set, t.UTF8String, 0);   // 0 = autodetect code format
        }
        set->enabled = true;
        mCheatAddSet(dev, set);
    }
}

- (NSString *)statePath:(int)slot { return [[_path stringByDeletingPathExtension] stringByAppendingFormat:@".ss%d", slot]; }
- (void)saveStateToSlot:(int)slot {
    if (!_core) return;
    // Write to a temp file then rename, so a crash mid-write can't corrupt the previous save state.
    NSString *dest = [self statePath:slot];
    NSString *tmp = [dest stringByAppendingString:@".tmp"];
    struct VFile *vf = VFileOpen(tmp.fileSystemRepresentation, O_CREAT | O_TRUNC | O_RDWR);
    if (!vf) return;
    BOOL ok = mCoreSaveStateNamed(_core, vf, SAVESTATE_SAVEDATA | SAVESTATE_RTC);
    vf->close(vf);
    if (ok) rename(tmp.fileSystemRepresentation, dest.fileSystemRepresentation);
    else unlink(tmp.fileSystemRepresentation);
}
- (void)loadStateFromSlot:(int)slot {
    if (!_core) return;
    struct VFile *vf = VFileOpen([self statePath:slot].fileSystemRepresentation, O_RDONLY);
    if (vf) { mCoreLoadStateNamed(_core, vf, SAVESTATE_SAVEDATA | SAVESTATE_RTC); vf->close(vf); }
}

- (void)shutdown {
    if (_core) { mCoreConfigDeinit(&_core->config); _core->deinit(_core); _core = NULL; }
    free(_video); _video = NULL;
}
- (void)dealloc { [self shutdown]; }
@end
