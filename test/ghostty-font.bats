#!/usr/bin/env bats

setup() {
  BIN="$BATS_TEST_DIRNAME/../bin/ghostty-font"
  export GHOSTTY_FONT_FILE="$BATS_TEST_TMPDIR/font"
  # Fake pkill records its arguments; fake ghostty knows only Geist and Iosevka.
  export GHOSTTY_FONT_PKILL="$BATS_TEST_TMPDIR/pkill"
  export GHOSTTY_FONT_GHOSTTY="$BATS_TEST_TMPDIR/ghostty"
  printf '#!/bin/sh\necho "$@" >> "%s/pkill.log"\n' "$BATS_TEST_TMPDIR" > "$GHOSTTY_FONT_PKILL"
  cat > "$GHOSTTY_FONT_GHOSTTY" <<'EOF'
#!/bin/sh
case "$2" in
  --family="GeistMono Nerd Font" | --family="IosevkaTerm Nerd Font") echo "${2#--family=}" ;;
esac
EOF
  chmod +x "$GHOSTTY_FONT_PKILL" "$GHOSTTY_FONT_GHOSTTY"
}

@test "setting a font writes the family and reloads Ghostty" {
  run "$BIN" geist
  [ "$status" -eq 0 ]
  [ "$output" = "Ghostty font: geist regular" ]
  grep -qx 'font-family = "GeistMono Nerd Font"' "$GHOSTTY_FONT_FILE"
  [ -z "$(grep 'font-style' "$GHOSTTY_FONT_FILE")" ]
  [ "$(cat "$BATS_TEST_TMPDIR/pkill.log")" = "-USR2 -x ghostty" ]
}

@test "a weight sets the regular and italic styles" {
  run "$BIN" iosevka light
  [ "$status" -eq 0 ]
  grep -qx 'font-style = Light' "$GHOSTTY_FONT_FILE"
  grep -qx 'font-family-italic = "IosevkaTerm Nerd Font"' "$GHOSTTY_FONT_FILE"
  grep -qx 'font-style-italic = Light Italic' "$GHOSTTY_FONT_FILE"
  [ -z "$(grep 'bold' "$GHOSTTY_FONT_FILE")" ]
}

@test "semibold and up moves bold text to the font's heaviest weight" {
  run "$BIN" geist semibold
  [ "$status" -eq 0 ]
  grep -qx 'font-style = SemiBold' "$GHOSTTY_FONT_FILE"
  grep -qx 'font-family-bold = "GeistMono Nerd Font"' "$GHOSTTY_FONT_FILE"
  grep -qx 'font-style-bold = Black' "$GHOSTTY_FONT_FILE"
  grep -qx 'font-style-bold-italic = Black Italic' "$GHOSTTY_FONT_FILE"
  "$BIN" iosevka bold
  grep -qx 'font-style-bold = Heavy' "$GHOSTTY_FONT_FILE"
}

@test "each font accepts only the weights it ships" {
  run "$BIN" iosevka heavy
  [ "$status" -eq 0 ]
  run "$BIN" geist heavy
  [ "$status" -eq 1 ]
  [[ "$output" == *"geist has no 'heavy' weight (try: thin "*" black)"* ]]
  run "$BIN" victor black
  [ "$status" -eq 1 ]
  [[ "$output" == *"victor has no 'black' weight"* ]]
}

@test "the built-in font clears the family and ignores weight" {
  "$BIN" geist light
  run "$BIN" default light
  [ "$status" -eq 0 ]
  [[ "$output" == *"ignores weight"* ]]
  [ -z "$(grep '^font-' "$GHOSTTY_FONT_FILE")" ]
  run "$BIN" list
  [[ "$output" == *"Current: default regular"* ]]
}

@test "list marks the current font" {
  "$BIN" iosevka extralight
  run "$BIN" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"* iosevka"* ]]
  [[ "$output" == *"thin extralight light regular medium semibold bold extrabold heavy"* ]]
  [[ "$output" == *"Current: iosevka extralight"* ]]
}

@test "list with no font file reports the built-in default" {
  run "$BIN" list
  [[ "$output" == *"* default"* ]]
  [[ "$output" == *"Current: default regular"* ]]
}

@test "a missing font is still written, with a brew hint" {
  run "$BIN" victor
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew install --cask font-victor-mono-nerd-font"* ]]
  grep -qx 'font-family = "VictorMono Nerd Font"' "$GHOSTTY_FONT_FILE"
}

@test "unknown font or weight exits 1 without touching the file" {
  run "$BIN" comic
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown font 'comic'"* ]]
  run "$BIN" geist chunky
  [ "$status" -eq 1 ]
  [[ "$output" == *"geist has no 'chunky' weight"* ]]
  [ ! -e "$GHOSTTY_FONT_FILE" ]
}
