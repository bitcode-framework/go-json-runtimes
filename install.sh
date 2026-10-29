#!/bin/sh
# go-json installer for Linux and macOS.
#
#   curl -fsSL https://raw.githubusercontent.com/bitcode-framework/go-json-runtimes/main/install.sh | sh
#
# Downloads a prebuilt binary from GitHub Releases. Go is NOT required.
# If no prebuilt binary matches your platform, the script falls back to
# `go install` when a Go toolchain is available.
#
# Environment:
#   GO_JSON_VERSION   release to install (default: latest), e.g. v0.1.0
#   GO_JSON_BIN_DIR   install directory (default: /usr/local/bin, else ~/.local/bin)
#   GO_JSON_LITE      set to 1 to install go-json-lite (no script runtimes)

set -eu

REPO="bitcode-framework/go-json-runtimes"
BINARY="go-json"
VERSION="${GO_JSON_VERSION:-latest}"
BIN_DIR="${GO_JSON_BIN_DIR:-}"

info()  { printf '  %s\n' "$*"; }
warn()  { printf '  warning: %s\n' "$*" >&2; }
error() { printf '  error: %s\n' "$*" >&2; exit 1; }

need() {
    command -v "$1" >/dev/null 2>&1 || error "required command not found: $1"
}

need uname
need mkdir
need rm
need mv

if command -v curl >/dev/null 2>&1; then
    fetch() { curl -fsSL "$1" -o "$2"; }
    fetch_stdout() { curl -fsSL "$1"; }
elif command -v wget >/dev/null 2>&1; then
    fetch() { wget -qO "$2" "$1"; }
    fetch_stdout() { wget -qO- "$1"; }
else
    error "need curl or wget to download go-json"
fi

# --- detect platform -------------------------------------------------------

os="$(uname -s)"
case "$os" in
    Linux)  os="linux" ;;
    Darwin) os="darwin" ;;
    # Git Bash / MSYS2 / Cygwin on Windows. Install the .exe so it works from
    # cmd.exe and PowerShell too, not just inside the POSIX layer.
    MINGW*|MSYS*|CYGWIN*) os="windows" ;;
    *) error "unsupported operating system: $os (this script covers Linux, macOS, and Windows via Git Bash)" ;;
esac

arch="$(uname -m)"
case "$arch" in
    x86_64|amd64)  arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) error "unsupported architecture: $arch" ;;
esac

suffix=""
[ "$os" = "windows" ] && suffix=".exe"

# --- pick install directory ------------------------------------------------

if [ -z "$BIN_DIR" ]; then
    if [ -w /usr/local/bin ] 2>/dev/null; then
        BIN_DIR="/usr/local/bin"
    else
        BIN_DIR="$HOME/.local/bin"
    fi
fi

# --- resolve version -------------------------------------------------------

if [ "$VERSION" = "latest" ]; then
    # Follow the redirect of /releases/latest to learn the tag.
    if command -v curl >/dev/null 2>&1; then
        VERSION="$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
            "https://github.com/${REPO}/releases/latest" 2>/dev/null | sed 's|.*/||')"
    else
        VERSION="$(fetch_stdout "https://api.github.com/repos/${REPO}/releases/latest" \
            | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    fi
    [ -n "$VERSION" ] || error "could not determine the latest release; set GO_JSON_VERSION explicitly"
fi

case "$VERSION" in
    v*) ;;
    *) VERSION="v$VERSION" ;;
esac

info "platform: ${os}/${arch}"
info "version:  ${VERSION}"

asset="${BINARY}-${os}-${arch}${suffix}"
base_url="${GO_JSON_BASE_URL:-https://github.com/${REPO}/releases/download}"
url="${base_url}/${VERSION}/${asset}"

# --- download --------------------------------------------------------------

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

info "downloading ${asset}"
if ! fetch "$url" "${tmp_dir}/${asset}" 2>/dev/null; then
    # No prebuilt binary: fall back to building from source.
    warn "no prebuilt binary for ${os}/${arch} at ${VERSION}"

    if command -v go >/dev/null 2>&1; then
        info "Go $(go version | awk '{print $3}') found, building from source"
        if [ "${GO_JSON_LITE:-0}" = "1" ]; then
            pkg="github.com/bitcode-framework/go-json/cmd/go-json-lite@${VERSION}"
            bin="go-json-lite"
        else
            pkg="github.com/${REPO}/cmd/go-json@${VERSION}"
            bin="go-json"
        fi
        GOBIN="$tmp_dir" go install "$pkg" || error "go install failed for $pkg"
        mv "${tmp_dir}/${bin}${suffix}" "${tmp_dir}/${asset}" 2>/dev/null \
            || mv "${tmp_dir}/${bin}" "${tmp_dir}/${asset}"
    else
        error "no prebuilt binary and no Go toolchain found.
  Install Go from https://go.dev/dl/ and re-run, or pick a supported platform."
    fi
else
    # Verify the checksum when the release ships one.
    if fetch "${url}.sha256" "${tmp_dir}/${asset}.sha256" 2>/dev/null; then
        expected="$(awk '{print $1}' "${tmp_dir}/${asset}.sha256")"
        if command -v sha256sum >/dev/null 2>&1; then
            actual="$(sha256sum "${tmp_dir}/${asset}" | awk '{print $1}')"
        elif command -v shasum >/dev/null 2>&1; then
            actual="$(shasum -a 256 "${tmp_dir}/${asset}" | awk '{print $1}')"
        else
            actual=""
        fi
        if [ -n "$actual" ] && [ "$expected" != "$actual" ]; then
            error "checksum mismatch for ${asset}
  expected: ${expected}
  actual:   ${actual}"
        fi
        info "checksum verified"
    fi
fi

# --- install ---------------------------------------------------------------

mkdir -p "$BIN_DIR"
target="${BIN_DIR}/${BINARY}${suffix}"

if [ -e "$target" ]; then
    info "replacing existing ${target}"
fi

chmod +x "${tmp_dir}/${asset}"
mv "${tmp_dir}/${asset}" "$target" 2>/dev/null || {
    warn "cannot write to ${BIN_DIR}, retrying with sudo"
    sudo mkdir -p "$BIN_DIR"
    sudo mv "${tmp_dir}/${asset}" "$target"
}

info "installed to ${target}"

# --- verify ----------------------------------------------------------------

if "${target}" version >/dev/null 2>&1; then
    info "verified: $("${target}" version)"
else
    warn "installed, but '${BINARY} version' did not run cleanly"
fi

case ":${PATH}:" in
    *":${BIN_DIR}:"*) ;;
    *)
        printf '\n  %s is not on your PATH. Add it with:\n\n' "$BIN_DIR"
        if [ "$os" = "windows" ]; then
            printf '    setx PATH "%%PATH%%;%s"\n\n' "$BIN_DIR"
        else
            printf '    export PATH="%s:$PATH"\n\n' "$BIN_DIR"
        fi
        ;;
esac

printf '\n  Done. Try it:\n\n'
printf '    go-json run program.json\n\n'
