# The picture size the box picks at startup (screen-factor in the overlay):
# for the screen it has been seen on and for screens it hasn't.
S=$PROJECT/overlay/usr/local/lib/totalreplay/screen-factor
T=$SCRATCH/screen-factor
rm -rf "$T"
mkdir -p "$T"

# is W H FACTOR: that screen gets that factor.
is() { [ "$(sh "$S" "$1" "$2")" = "$3" ] || { echo "$1x$2 gave $(sh "$S" "$1" "$2"), not $3"; return 1; }; }
check "1280x720, the Apple TV's usual screen, gives 1.75 (980x672)" is 1280 720 1.75
check "1920x1080 gives 2.625 (1470x1008)" is 1920 1080 2.625
check "1366x768 gives 1.75, and 1024x768 is limited by its width to 1.625" sh -c "
    [ \"\$(sh '$S' 1366 768)\" = 1.75 ] && [ \"\$(sh '$S' 1024 768)\" = 1.625 ]"
check "480 and 576 lines give 1.125, or 1 when only 640 wide" sh -c "
    [ \"\$(sh '$S' 720 480)\" = 1.125 ] && [ \"\$(sh '$S' 720 576)\" = 1.125 ] &&
    [ \"\$(sh '$S' 640 480)\" = 1 ]"
check "a screen too small for the Apple II's own size still gets 1, a huge one stops at 8" sh -c "
    [ \"\$(sh '$S' 320 200)\" = 1 ] && [ \"\$(sh '$S' 100000 100000)\" = 8 ]"

# Every factor is a multiple of 1/8 and leaves the margin, on any screen big
# enough for factor 1 with it.
fits() {
    for size in 640x480 720x480 720x576 800x600 1024x768 1280x720 1280x1024 1366x768 \
        1440x900 1600x900 1920x1080 1920x1200 2560x1440 3840x2160; do
        w=${size%x*} h=${size#*x}
        f=$(sh "$S" "$w" "$h")
        awk -v f="$f" -v w="$w" -v h="$h" 'BEGIN {
            k = f * 8
            if (k != int(k)) { print w "x" h ": " f " is not a multiple of 1/8"; exit 1 }
            if (f > 1 && (384 * f > h * 0.935 || 560 * f > w * 0.935)) {
                print w "x" h ": " f " leaves no margin"; exit 1 }
            # The next step up must not fit, or the picture is smaller than it need be.
            g = f + 0.125
            if (384 * g <= h * 0.935 && 560 * g <= w * 0.935) {
                print w "x" h ": " g " would also fit"; exit 1 }
        }' || return 1
    done
}
check "on 14 common screen sizes the factor is the largest multiple of 1/8 that leaves the margin" fits

# Without arguments: the framebuffer's size, or the override file.
echo "1920,1080" > "$T/fb"
auto() { SCREEN_FACTOR_FB=$T/fb SCREEN_FACTOR_FILE=$T/override sh "$S" 2>"$T/err"; }
check "with no arguments it reads the framebuffer's size" sh -c "
    [ \"\$(SCREEN_FACTOR_FB='$T/fb' SCREEN_FACTOR_FILE='$T/none' sh '$S')\" = 2.625 ]"
check "with no framebuffer to read it assumes 1280x720" sh -c "
    [ \"\$(SCREEN_FACTOR_FB='$T/none' SCREEN_FACTOR_FILE='$T/none' sh '$S')\" = 1.75 ]"
override() {
    printf '%s\n' "$1" > "$T/override"
    [ "$(auto)" = "$2" ] || { echo "override '$1' gave $(auto), not $2"; return 1; }
}
check "an override file replaces the computed factor" override 1.875 1.875
check "spaces around the override don't matter" override ' 2 ' 2
bad() {
    for v in abc 0.5 9 1.2.3 '' -1 .5; do
        printf '%s\n' "$v" > "$T/override"
        [ "$(auto)" = 2.625 ] && [ -s "$T/err" ] || { echo "override '$v' gave $(auto)"; return 1; }
    done
}
check "an override that isn't a number from 1 to 8 is ignored, with a message" bad
rm -rf "$T"
