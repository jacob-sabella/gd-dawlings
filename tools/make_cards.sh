#!/usr/bin/env bash
# Draws the playing cards' faces and back, and writes assets/textures/card_faces.png (an atlas:
# thirteen ranks across, A to K, four suits down, spades hearts diamonds clubs) and
# assets/textures/card_back.png.
#
#     tools/make_cards.sh
#
# The suits are drawn here, in DejaVu, because the game's own font has no suit signs: a card is a
# picture, not text (CardsItem).
set -euo pipefail
cd "$(dirname "$0")/.."
W=160
H=224
FONT=/usr/share/fonts/TTF/DejaVuSans-Bold.ttf
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ranks=(A 2 3 4 5 6 7 8 9 10 J Q K)
suits=(♠ ♥ ♦ ♣)
colours=("#151515" "#c21a1f" "#c21a1f" "#151515")
for s in 0 1 2 3; do
	row=()
	for r in "${!ranks[@]}"; do
		rank=${ranks[$r]}
		corner="$tmp/c_${s}_$r.png"
		# A corner: the rank over its suit.
		magick -background none -fill "${colours[$s]}" -font "$FONT" \
			\( -pointsize 34 label:"$rank" \) \( -pointsize 30 label:"${suits[$s]}" \) \
			-gravity center -append "$corner"
		face="$tmp/f_${s}_$r.png"
		pip="$tmp/p_${s}_$r.png"
		magick -background none -fill "${colours[$s]}" -font "$FONT" -pointsize 96 label:"${suits[$s]}" "$pip"
		magick -size ${W}x${H} xc:"#f6f3ea" \
			-fill none -stroke "#d8d2c2" -strokewidth 3 -draw "roundrectangle 6,6 $((W-7)),$((H-7)) 10,10" \
			"$pip" -gravity center -geometry +0+0 -composite \
			"$corner" -gravity northwest -geometry +10+8 -composite \
			\( "$corner" -rotate 180 \) -gravity southeast -geometry +10+8 -composite "$face"
		row+=("$face")
	done
	magick "${row[@]}" +append "$tmp/row_$s.png"
done
magick "$tmp/row_0.png" "$tmp/row_1.png" "$tmp/row_2.png" "$tmp/row_3.png" -append assets/textures/card_faces.png
# The back: a deep red with a white border and a lattice of diamonds.
magick -size ${W}x${H} xc:"#f6f3ea" \
	\( -size $((W*3))x$((H*3)) pattern:checkerboard -scale 140% -auto-level +level-colors "#7a101b,#b32834" -background "#7a101b" \
		-rotate 45 -gravity center -crop $((W-20))x$((H-20))+0+0 +repage \) -gravity center -composite \
	-fill none -stroke "#f6f3ea" -strokewidth 3 -draw "roundrectangle 16,16 $((W-17)),$((H-17)) 8,8" \
	assets/textures/card_back.png
echo wrote assets/textures/card_faces.png assets/textures/card_back.png
