// Drives linapple's VideoStretch over many cases and prints one checksum per
// case. tests/stretch.sh builds it against upstream's VideoStretch.cpp and
// against ours (patches/linapple-stretch-speedup.patch) and compares the
// output, so any pixel the patch changes shows up as a differing line.
// With "bands" it instead checks what the changed-rows patch relies on:
// stretching a band of whole row blocks gives exactly the full frame's rows.
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

#include "frontends/common/VideoStretch.h"
#include "frontends/common/VideoSurface.h"

auto video_destroy_surface(VideoSurface* /*s*/) -> void {}

namespace {

uint32_t rng = 12345;
auto next() -> uint32_t {
  rng = rng * 1103515245u + 12345u;
  return rng >> 8;
}

struct Buffer {
  std::vector<uint8_t> bytes;
  VideoSurfaceView view;
  Buffer(int w, int h, int bpp, const VideoColor* palette, int slack) {
    const int pitch = w * bpp + slack;
    bytes.resize(static_cast<size_t>(pitch) * h);
    for (auto& b : bytes) {
      b = static_cast<uint8_t>(next());
    }
    view = VideoSurfaceView(bytes.data(), w, h, pitch, bpp, palette);
  }
};

auto fnv(const std::vector<uint8_t>& v) -> uint32_t {
  uint32_t h = 2166136261u;
  for (uint8_t b : v) {
    h = (h ^ b) * 16777619u;
  }
  return h;
}

std::vector<VideoColor> palette(video_palette_size);

auto one_case(int n, int fn, int sbpp, int dbpp, VideoRect sr, VideoRect dr,
              int sw, int sh, int dw, int dh) -> void {
  Buffer src(sw, sh, sbpp, palette.data(), (n % 3) * 4);
  Buffer dst(dw, dh, dbpp, palette.data(), (n % 2) * 8);
  int rc = 0;
  switch (fn) {
    case 0: rc = video_soft_stretch(src.view, &sr, dst.view, &dr); break;
    case 1: rc = video_soft_stretch_or(src.view, &sr, dst.view, &dr); break;
    default:
      rc = video_soft_stretch_mono8(src.view, &sr, dst.view, &dr, 0x00ffeeddu,
                                    0x00112233u);
  }
  std::printf("%d fn%d %dbpp->%dbpp src %dx%d+%d+%d -> %dx%d%+d%+d rc %d %08x\n",
              n, fn, sbpp, dbpp, sr.w, sr.h, sr.x, sr.y, dr.w, dr.h, dr.x,
              dr.y, rc, fnv(dst.bytes));
}

auto cases() -> void {
  for (auto& c : palette) {
    c = VideoColor{static_cast<uint8_t>(next()), static_cast<uint8_t>(next()),
                   static_cast<uint8_t>(next()), 255};
  }
  // The Apple TV's real cases first: 560x384 to 2x, 1.875x, 1.75x, 1x.
  const int real_w[] = {1120, 1050, 980, 560};
  const int real_h[] = {768, 720, 672, 384};
  int n = 0;
  for (int i = 0; i < 4; ++i) {
    for (int dbpp : {4}) {
      one_case(n++, 0, 4, dbpp, {0, 0, 560, 384},
               {(1280 - real_w[i]) / 2, (800 - real_h[i]) / 2, real_w[i],
                real_h[i]},
               560, 384, 1280, 800);
    }
  }
  // Then every function and pixel format over random sizes and offsets,
  // including upscaling, downscaling and clipping at every edge.
  const int formats[][2] = {{1, 1}, {1, 4}, {2, 2}, {3, 3}, {3, 4}, {4, 4}};
  for (int k = 0; k < 600; ++k) {
    const int fn = k % 3;
    const int* f = formats[k % 6];
    int sbpp = f[0];
    int dbpp = f[1];
    if (fn == 2) {
      sbpp = 1;  // mono8 reads 8-bit sources
      dbpp = (k % 2) != 0 ? 4 : 1;
    }
    const int sw = 1 + static_cast<int>(next() % 300);
    const int sh = 1 + static_cast<int>(next() % 200);
    const int dw = 1 + static_cast<int>(next() % 700);
    const int dh = 1 + static_cast<int>(next() % 500);
    VideoRect sr{static_cast<int>(next() % sw), static_cast<int>(next() % sh), 0,
                 0};
    sr.w = 1 + static_cast<int>(next() % (sw - sr.x));
    sr.h = 1 + static_cast<int>(next() % (sh - sr.y));
    VideoRect dr{static_cast<int>(next() % (dw + 40)) - 20,
                 static_cast<int>(next() % (dh + 40)) - 20,
                 1 + static_cast<int>(next() % (dw + 60)),
                 1 + static_cast<int>(next() % (dh + 60))};
    one_case(n++, fn, sbpp, dbpp, sr, dr, sw, sh, dw, dh);
  }
}

// For each Apple TV scale, stretch the full 560x384 frame, then stretch bands
// of whole blocks (block source rows -> dst_block destination rows) the way
// Frame.cpp's narrow_to_changed_rows does, and compare those rows.
auto bands() -> int {
  const int heights[] = {768, 720, 672};
  int bad = 0;
  for (int dst_h : heights) {
    int a = dst_h;
    int b = 384;
    while (b != 0) {
      const int t = a % b;
      a = b;
      b = t;
    }
    const int block = 384 / a;
    const int dst_block = dst_h / a;
    const int dst_w = 560 * dst_h / 384;
    Buffer src(560, 384, 4, nullptr, 0);
    Buffer full(dst_w, dst_h, 4, nullptr, 0);
    VideoRect sr{0, 0, 560, 384};
    VideoRect dr{0, 0, dst_w, dst_h};
    video_soft_stretch(src.view, &sr, full.view, &dr);
    Buffer part(dst_w, dst_h, 4, nullptr, 0);
    for (int top = 0; top < 384; top += block) {
      for (int rows = block; top + rows <= 384; rows += block * 7) {
        std::memset(part.bytes.data(), 0, part.bytes.size());
        VideoRect bsr{0, top, 560, rows};
        VideoRect bdr{0, top / block * dst_block, dst_w,
                      rows / block * dst_block};
        video_soft_stretch(src.view, &bsr, part.view, &bdr);
        const size_t off = static_cast<size_t>(bdr.y) * full.view.pitch;
        const size_t len = static_cast<size_t>(bdr.h) * full.view.pitch;
        if (std::memcmp(full.bytes.data() + off, part.bytes.data() + off, len) !=
            0) {
          std::printf("band differs: %d lines, source rows %d+%d\n", dst_h, top,
                      rows);
          ++bad;
        }
      }
    }
    std::printf("bands at %d lines (block %d -> %d): %s\n", dst_h, block,
                dst_block, bad == 0 ? "identical" : "DIFFER");
  }
  return bad == 0 ? 0 : 1;
}

}  // namespace

auto main(int argc, char** argv) -> int {
  if (argc > 1 && std::strcmp(argv[1], "bands") == 0) {
    return bands();
  }
  cases();
  return 0;
}
