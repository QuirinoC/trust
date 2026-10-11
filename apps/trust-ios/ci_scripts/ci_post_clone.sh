#!/bin/sh
# Xcode Cloud runs this hook before resolving packages or building the project.
set -eu

SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd)"
if [ -n "${CI_PRIMARY_REPOSITORY_PATH:-}" ]; then
    CHECKOUT_ROOT="$CI_PRIMARY_REPOSITORY_PATH"
else
    CHECKOUT_ROOT="$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)"
fi

if [ -d "$CHECKOUT_ROOT/apps/trust-ios/Trust.xcodeproj" ]; then
    IOS_ROOT="$CHECKOUT_ROOT/apps/trust-ios"
elif [ -d "$CHECKOUT_ROOT/Trust.xcodeproj" ]; then
    IOS_ROOT="$CHECKOUT_ROOT"
else
    echo "Could not locate Trust.xcodeproj from CI_PRIMARY_REPOSITORY_PATH or ci_scripts." >&2
    exit 1
fi

if [ -n "${CI_XCODE_SCHEME:-}" ] && [ "$CI_XCODE_SCHEME" != "Trust" ]; then
    echo "Xcode Cloud selected scheme '$CI_XCODE_SCHEME'; expected Trust." >&2
    exit 1
fi

if [ -n "${CI_PROJECT_FILE_PATH:-}" ]; then
    case "$CI_PROJECT_FILE_PATH" in
        /*) PROJECT_CANDIDATE="$CI_PROJECT_FILE_PATH" ;;
        *)
            if [ -e "$CHECKOUT_ROOT/$CI_PROJECT_FILE_PATH" ]; then
                PROJECT_CANDIDATE="$CHECKOUT_ROOT/$CI_PROJECT_FILE_PATH"
            elif [ -e "$IOS_ROOT/$CI_PROJECT_FILE_PATH" ]; then
                PROJECT_CANDIDATE="$IOS_ROOT/$CI_PROJECT_FILE_PATH"
            else
                echo "Xcode Cloud project path '$CI_PROJECT_FILE_PATH' does not resolve to Trust.xcodeproj." >&2
                exit 1
            fi
            ;;
    esac

    if [ -f "$PROJECT_CANDIDATE" ] && [ "${PROJECT_CANDIDATE##*/}" = "project.pbxproj" ]; then
        PROJECT_CANDIDATE="${PROJECT_CANDIDATE%/*}"
    fi
    if [ ! -d "$PROJECT_CANDIDATE" ]; then
        echo "Xcode Cloud project path '$CI_PROJECT_FILE_PATH' does not resolve to an Xcode project directory." >&2
        exit 1
    fi
    PROJECT_CANDIDATE="$(CDPATH= cd "$PROJECT_CANDIDATE" && pwd)"
    EXPECTED_PROJECT="$(CDPATH= cd "$IOS_ROOT/Trust.xcodeproj" && pwd)"
    if [ "$PROJECT_CANDIDATE" != "$EXPECTED_PROJECT" ]; then
        echo "Xcode Cloud selected project '$CI_PROJECT_FILE_PATH'; expected Trust.xcodeproj." >&2
        exit 1
    fi
fi

exec python3 "$IOS_ROOT/Scripts/validate_cloud_build.py" "$IOS_ROOT"
