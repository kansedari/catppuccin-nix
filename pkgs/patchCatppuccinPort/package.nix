{
  lib,
  pkgs,
  fetchCatppuccinPort,
}: {
  port,
  rev,
  hash,
  extraSubstitutions ? [],
}: let
  pristine = fetchCatppuccinPort {inherit port rev hash;};
  customPalette = ./palette.json;
  paletteModule = ./catppuccin-palette.js;
  skipPatch = [];

  # colour replacement tables [ [from to] ... ]
  mochaReplacements = [
    ["cdd6f4" "f4f4f4"] # text
    ["bac2de" "e0e0e0"] # subtext1
    ["a6adc8" "c6c6c6"] # subtext0
    ["9399b2" "a8a8a8"] # overlay2
    ["7f849c" "8d8d8d"] # overlay1
    ["6c7086" "6f6f6f"] # overlay0
    ["585b70" "525252"] # surface2
    ["45475a" "393939"] # surface1
    ["313244" "262626"] # surface0
    ["1e1e2e" "161616"] # base
    ["181825" "0b0b0b"] # mantle
    ["11111b" "000000"] # crust
  ];

  latteReplacements = [
    ["4c4f69" "000000"] # text
    ["5c5f77" "0b0b0b"] # subtext1
    ["6c6f85" "161616"] # subtext0
    ["7c7f93" "262626"] # overlay2
    ["8c8fa1" "393939"] # overlay1
    ["9ca0b0" "525252"] # overlay0
    ["acb0be" "6f6f6f"] # surface2
    ["bcc0cc" "8d8d8d"] # surface1
    ["ccd0da" "a8a8a8"] # surface0
    ["eff1f5" "c6c6c6"] # base
    ["e6e9ef" "e0e0e0"] # mantle
    ["dce0e8" "f4f4f4"] # crust
  ];

  allReplacements = mochaReplacements ++ latteReplacements ++ extraSubstitutions;

  sedScript = lib.concatStringsSep ";" (
    map (p: "s/${builtins.elemAt p 0}/${builtins.elemAt p 1}/gI") allReplacements
  );

  grepPattern = lib.concatStringsSep "\\|" (map (p: builtins.elemAt p 0) allReplacements);

  flavorConfig = {
    mocha = {
      target = "dark";
      rosewater = "f5e0dc";
      monochrome = "f4f4f4";
    };
    latte = {
      target = "light";
      rosewater = "dc8a78";
      monochrome = "000000";
    };
  };

  flavors = builtins.attrNames flavorConfig;
in
  if builtins.elem port skipPatch
  then pristine
  else
    pkgs.runCommandLocal "catppuccin-${port}-patched" {
      src = pristine;
      nativeBuildInputs = [pkgs.gnused pkgs.findutils];
    } ''
      cp -r --no-preserve=mode,ownership --dereference "$src/." "$out"

      replace_in_files() {
        local pattern="$1" script="$2"
        find "$out" -type f -print0 | xargs -0 grep -liZ "$pattern" 2>/dev/null | \
          while IFS= read -r -d $'\0' f; do sed -i "$script" "$f"; done || true
      }

      rename_items() {
        local type="$1" pattern="$2" from="$3" to="$4"
        find "$out" -depth -type "$type" -name "$pattern" 2>/dev/null | while read -r item; do
          mv "$item" "$(dirname "$item")/$(basename "$item" | sed "s/$from/$to/g")"
        done || true
      }

      remove_items() {
        for pattern in "$@"; do
          find "$out" -depth -name "$pattern" -exec rm -rf {} \; 2>/dev/null || true
        done
      }

      replace_in_files '${grepPattern}' '${sedScript}'

      # create monochrome accent variants from rosewater
      ${lib.concatStringsSep "\n" (map (
          flavor: let
            cfg = flavorConfig.${flavor};
          in ''
            # ${flavor} -> ${cfg.target}
            for dir in $(find "$out" -type d -name "*-${flavor}-rosewater" 2>/dev/null); do
              newdir="''${dir%-rosewater}-monochrome"
              cp -r "$dir" "$newdir"
              find "$newdir" -type f -name "*rosewater*" | while read -r f; do
                mv "$f" "''${f//rosewater/monochrome}"
              done
              find "$newdir" -type f -exec sed -i \
                "s/${cfg.rosewater}/${cfg.monochrome}/gI; s/rosewater/monochrome/g; s/Rosewater/Monochrome/g" {} \;
            done

            for file in $(find "$out" -type f -name "*-${flavor}-rosewater.*" 2>/dev/null); do
              newfile="$(echo "$file" | sed 's/-rosewater\./-monochrome./')"
              cp "$file" "$newfile"
              sed -i "s/${cfg.rosewater}/${cfg.monochrome}/gI; s/rosewater/monochrome/g; s/Rosewater/Monochrome/g" "$newfile"
            done
          ''
        )
        flavors)}

      ${lib.concatStringsSep "\n" (map (
          flavor: let
            target = flavorConfig.${flavor}.target;
            Target = lib.toUpper (lib.substring 0 1 target) + lib.substring 1 (-1) target;
            Flavor = lib.toUpper (lib.substring 0 1 flavor) + lib.substring 1 (-1) flavor;
          in ''
            rename_items d "*${flavor}*" "${flavor}" "${target}"
            rename_items f "*${flavor}*" "${flavor}" "${target}"
            replace_in_files '${flavor}\|${Flavor}' 's/${flavor}/${target}/g; s/${Flavor}/${Target}/g'
          ''
        )
        flavors)}

      remove_items "*frappe*" "*macchiato*" "*Frappe*" "*Macchiato*"

      # handle js-based ports using @catppuccin/palette
      if [ -f "$out/package.json" ] && grep -q "@catppuccin/palette" "$out/package.json"; then
        echo "Patching JS-based port: replacing @catppuccin/palette with local module"

        cp ${customPalette} "$out/palette.json"
        cp ${paletteModule} "$out/catppuccin-palette.js"

        find "$out" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.mjs" \) -exec sed -i \
          -e 's|from "@catppuccin/palette"|from "./catppuccin-palette.js"|g' \
          -e "s|from '@catppuccin/palette'|from './catppuccin-palette.js'|g" \
          -e 's|require("@catppuccin/palette")|require("./catppuccin-palette.js")|g' \
          -e "s|require('@catppuccin/palette')|require('./catppuccin-palette.js')|g" \
          -e 's/"lavender",/"lavender",\n    "monochrome",/g' \
          {} \;

        sed -i '/"@catppuccin\/palette"/d' "$out/package.json"
      fi
    ''
