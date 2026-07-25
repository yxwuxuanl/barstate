#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
RESOURCE_DIR="$PROJECT_DIR/Sources/BarStateCore/Resources"
EN_DIR="$RESOURCE_DIR/en.lproj"
ZH_DIR="$RESOURCE_DIR/zh-Hans.lproj"

for file in \
    "$EN_DIR/Localizable.strings" \
    "$EN_DIR/Localizable.stringsdict" \
    "$ZH_DIR/Localizable.strings" \
    "$ZH_DIR/Localizable.stringsdict"
do
    plutil -lint "$file" >/dev/null
done

key_differences="$(comm -3 \
    <(grep -Eo '^"[^"]+"' "$EN_DIR/Localizable.strings" | sort) \
    <(grep -Eo '^"[^"]+"' "$ZH_DIR/Localizable.strings" | sort))"
if [[ -n "$key_differences" ]]; then
    print -u2 "Localizable.strings keys differ between en and zh-Hans:"
    print -u2 "$key_differences"
    exit 1
fi

referenced_keys=(
    "${(@f)$(grep -hEo \
        'L10n\.(string|format|plural)\("[^"]+"' \
        "$PROJECT_DIR"/Sources/**/*.swift \
        | sed -E 's/.*\("([^"]+)"/\1/' \
        | sort -u)}"
)

for locale_dir in "$EN_DIR" "$ZH_DIR"; do
    for key in "${referenced_keys[@]}"; do
        if ! grep -Fq '"'"$key"'"' "$locale_dir/Localizable.strings" \
            && ! grep -Fq '<key>'"$key"'</key>' "$locale_dir/Localizable.stringsdict"
        then
            print -u2 "Missing localization key in ${locale_dir:t}: $key"
            exit 1
        fi
    done
done

if /usr/bin/perl -CSDA -ne '
    if (/"[^"\n]*\p{Han}[^"\n]*"/) {
        print "$ARGV:$.:$_";
        $found = 1;
    }
    END { exit($found ? 0 : 1) }
' "$PROJECT_DIR"/Sources/**/*.swift
then
    print -u2 "Hard-coded Chinese string literals remain in production Swift sources."
    exit 1
fi

APP_RESOURCES="$PROJECT_DIR/.build/BarState.app/Contents/Resources"
if [[ -d "$PROJECT_DIR/.build/BarState.app" ]]; then
    for locale in en zh-Hans; do
        if [[ ! -f "$APP_RESOURCES/$locale.lproj/Localizable.strings" ]]; then
            print -u2 "Built app is missing $locale localization resources."
            exit 1
        fi
    done
fi

print "Localization checks passed"
