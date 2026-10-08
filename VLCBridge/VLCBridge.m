#import "VLCBridge.h"
#import <VLCKit/VLCKit.h>

typedef struct libvlc_media_player_t libvlc_media_player_t;

// Exported by VLCKit; the declaring header is excluded from its module map.
extern void libvlc_video_set_textrenderer_int(libvlc_media_player_t *p_mi,
                                              unsigned option,
                                              int value);

// libvlc_video_textrenderer_option_t: font = 0, fontsize = 1, ...
static const unsigned kLibVLCTextRenderFontSize = 1;

// Declared locally because VLCKit ships this in PrivateHeaders, which are not
// part of the framework module.
@interface VLCMediaPlayer (IPTVInternal)
- (libvlc_media_player_t *)playerInstance;
@end

BOOL IPTVSubtitleFontSizeSupported(VLCMediaPlayer *player) {
    return player != nil && [player respondsToSelector:@selector(playerInstance)];
}

void IPTVSetSubtitleFontSize(VLCMediaPlayer *player, int relativeSize) {
    if (!IPTVSubtitleFontSizeSupported(player)) { return; }
    libvlc_media_player_t *mp = [player playerInstance];
    if (mp == NULL) { return; }
    libvlc_video_set_textrenderer_int(mp, kLibVLCTextRenderFontSize, relativeSize);
}
