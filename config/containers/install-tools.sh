#!/usr/bin/env bash
set -euo pipefail

source /tmp/opencode-tool-versions.conf

arch() {
  dpkg --print-architecture
}

github_release_json() {
  local repo="$1" tag="$2"
  curl -fsSL "https://api.github.com/repos/$repo/releases/tags/$tag"
}

github_asset_url() {
  local repo="$1" tag="$2" asset_name="$3"
  github_release_json "$repo" "$tag" | jq -r --arg asset_name "$asset_name" '.assets[] | select(.name == $asset_name) | .browser_download_url'
}

github_asset_digest_sha256() {
  local repo="$1" tag="$2" asset_name="$3"
  github_release_json "$repo" "$tag" | jq -r --arg asset_name "$asset_name" '.assets[] | select(.name == $asset_name) | .digest' | sed 's/^sha256://'
}

download_with_sha256() {
  local url="$1" sha256="$2" output_path="$3"
  curl -fsSL "$url" -o "$output_path"
  printf '%s  %s\n' "$sha256" "$output_path" | sha256sum -c - >/dev/null
}

download_github_asset_with_digest() {
  local repo="$1" tag="$2" asset_name="$3" output_path="$4"
  local url sha256
  url="$(github_asset_url "$repo" "$tag" "$asset_name")"
  sha256="$(github_asset_digest_sha256 "$repo" "$tag" "$asset_name")"
  [[ -n "$url" && -n "$sha256" ]] || {
    printf 'failed to resolve GitHub asset url or sha256 for %s %s %s\n' "$repo" "$tag" "$asset_name" >&2
    exit 1
  }
  download_with_sha256 "$url" "$sha256" "$output_path"
}

download_github_asset_with_checksums_file() {
  local repo="$1" tag="$2" asset_name="$3" checksums_asset="$4" output_path="$5"
  local url checksums_url checksums_path
  local sha256

  url="$(github_asset_url "$repo" "$tag" "$asset_name")"
  checksums_url="$(github_asset_url "$repo" "$tag" "$checksums_asset")"
  [[ -n "$url" && -n "$checksums_url" ]] || {
    printf 'failed to resolve GitHub asset url or checksum file for %s %s %s\n' "$repo" "$tag" "$asset_name" >&2
    exit 1
  }

  checksums_path="$(mktemp)"
  curl -fsSL "$checksums_url" -o "$checksums_path"
  sha256="$(grep -F "  $asset_name" "$checksums_path" | awk '{print $1}' | head -n 1)"
  rm -f "$checksums_path"
  [[ -n "$sha256" ]] || {
    printf 'failed to resolve sha256 from checksum file for %s\n' "$asset_name" >&2
    exit 1
  }

  download_with_sha256 "$url" "$sha256" "$output_path"
}

install_direct_binary() {
  local binary_path="$1" target_name="$2"
  install -m 755 "$binary_path" "/usr/local/bin/$target_name"
}

install_from_tar_archive() {
  local archive_path="$1" asset_name="$2" binary_name="$3" target_name="$4"
  local tmpdir extracted_path
  tmpdir="$(mktemp -d)"
  case "$asset_name" in
    *.tar.gz|*.tgz) tar -xzf "$archive_path" -C "$tmpdir" ;;
    *.tar.xz) tar -xJf "$archive_path" -C "$tmpdir" ;;
    *) printf 'unsupported archive format: %s\n' "$asset_name" >&2; exit 1 ;;
  esac
  extracted_path="$(find "$tmpdir" -type f -name "$binary_name" | head -n 1)"
  [[ -n "$extracted_path" ]] || {
    printf 'failed to locate %s in %s\n' "$binary_name" "$archive_path" >&2
    exit 1
  }
  install -m 755 "$extracted_path" "/usr/local/bin/$target_name"
  rm -rf "$tmpdir"
}

ubuntu_packages=()

install_apt_packages() {
  printf '#!/bin/sh\nexit 101\n' >/usr/sbin/policy-rc.d
  chmod 755 /usr/sbin/policy-rc.d
  apt-get update
  apt-get install -y --no-install-recommends \
    age \
    bash \
    bat \
    buildah \
    ca-certificates \
    caddy \
    curl \
    direnv \
    duf \
    eza \
    fd-find \
    gh \
    git \
    git-delta \
    hyperfine \
    jq \
    just \
    less \
    lnav \
    miller \
    podman \
    procps \
    python-is-python3 \
    python3 \
    ripgrep \
    shellcheck \
    shfmt \
    skopeo \
    strace \
    tar \
    tini \
    yq \
    xz-utils \
    zoxide \
  && rm -rf /var/lib/apt/lists/*

  rm -f /usr/sbin/policy-rc.d

  ln -sf /usr/bin/fdfind /usr/local/bin/fd || true
  ln -sf /usr/bin/batcat /usr/local/bin/bat || true
}

install_uv() {
  local asset_name tmpfile tmpdir
  case "$(arch)" in
    amd64) asset_name='uv-x86_64-unknown-linux-gnu.tar.gz' ;;
    arm64) asset_name='uv-aarch64-unknown-linux-gnu.tar.gz' ;;
    *) printf 'unsupported architecture for uv\n' >&2; exit 1 ;;
  esac
  tmpfile="$(mktemp)"
  download_github_asset_with_digest 'astral-sh/uv' "$OPENCODE_TOOL_UV_VERSION" "$asset_name" "$tmpfile"
  tmpdir="$(mktemp -d)"
  tar -xzf "$tmpfile" -C "$tmpdir"
  install -m 755 "$(find "$tmpdir" -type f -name uv | head -n 1)" /usr/local/bin/uv
  if find "$tmpdir" -type f -name uvx | grep -q .; then
    install -m 755 "$(find "$tmpdir" -type f -name uvx | head -n 1)" /usr/local/bin/uvx
  fi
  rm -rf "$tmpdir" "$tmpfile"
}

install_watchexec() {
  local asset_name tmpfile
  case "$(arch)" in
    amd64) asset_name="watchexec-${OPENCODE_TOOL_WATCHEXEC_VERSION#v}-x86_64-unknown-linux-gnu.tar.xz" ;;
    arm64) asset_name="watchexec-${OPENCODE_TOOL_WATCHEXEC_VERSION#v}-aarch64-unknown-linux-gnu.tar.xz" ;;
    *) printf 'unsupported architecture for watchexec\n' >&2; exit 1 ;;
  esac
  tmpfile="$(mktemp)"
  download_github_asset_with_digest 'watchexec/watchexec' "$OPENCODE_TOOL_WATCHEXEC_VERSION" "$asset_name" "$tmpfile"
  install_from_tar_archive "$tmpfile" "$asset_name" watchexec watchexec
  rm -f "$tmpfile"
}

install_xh() {
  local asset_name tmpfile
  case "$(arch)" in
    amd64) asset_name="xh_${OPENCODE_TOOL_XH_VERSION#v}_amd64.deb" ;;
    arm64) asset_name="xh-v${OPENCODE_TOOL_XH_VERSION#v}-aarch64-unknown-linux-musl.tar.gz" ;;
    *) printf 'unsupported architecture for xh\n' >&2; exit 1 ;;
  esac
  tmpfile="$(mktemp)"
  download_github_asset_with_digest 'ducaale/xh' "$OPENCODE_TOOL_XH_VERSION" "$asset_name" "$tmpfile"
  case "$asset_name" in
    *.deb)
      apt-get update
      apt-get install -y --no-install-recommends "$tmpfile"
      rm -rf /var/lib/apt/lists/*
      ;;
    *)
      install_from_tar_archive "$tmpfile" "$asset_name" xh xh
      ;;
  esac
  rm -f "$tmpfile"
}

install_jj() {
  local asset_name tmpfile
  case "$(arch)" in
    amd64) asset_name="jj-${OPENCODE_TOOL_JJ_VERSION}-x86_64-unknown-linux-musl.tar.gz" ;;
    arm64) asset_name="jj-${OPENCODE_TOOL_JJ_VERSION}-aarch64-unknown-linux-musl.tar.gz" ;;
    *) printf 'unsupported architecture for jj\n' >&2; exit 1 ;;
  esac
  tmpfile="$(mktemp)"
  download_github_asset_with_digest 'jj-vcs/jj' "$OPENCODE_TOOL_JJ_VERSION" "$asset_name" "$tmpfile"
  install_from_tar_archive "$tmpfile" "$asset_name" jj jj
  rm -f "$tmpfile"
}

install_worktrunk() {
  local asset_name tmpfile
  case "$(arch)" in
    amd64) asset_name='worktrunk-x86_64-unknown-linux-musl.tar.xz' ;;
    arm64) asset_name='worktrunk-aarch64-unknown-linux-musl.tar.xz' ;;
    *) printf 'unsupported architecture for worktrunk\n' >&2; exit 1 ;;
  esac
  tmpfile="$(mktemp)"
  download_github_asset_with_digest 'max-sixty/worktrunk' "$OPENCODE_TOOL_WORKTRUNK_VERSION" "$asset_name" "$tmpfile"
  install_from_tar_archive "$tmpfile" "$asset_name" wt wt
  ln -sf /usr/local/bin/wt /usr/local/bin/worktrunk
  rm -f "$tmpfile"
}

install_dive() {
  local asset_name tmpfile
  case "$(arch)" in
    amd64) asset_name="dive_${OPENCODE_TOOL_DIVE_VERSION#v}_linux_amd64.deb" ;;
    arm64) asset_name="dive_${OPENCODE_TOOL_DIVE_VERSION#v}_linux_arm64.deb" ;;
    *) printf 'unsupported architecture for dive\n' >&2; exit 1 ;;
  esac
  tmpfile="$(mktemp)"
  download_github_asset_with_checksums_file 'wagoodman/dive' "$OPENCODE_TOOL_DIVE_VERSION" "$asset_name" "dive_${OPENCODE_TOOL_DIVE_VERSION#v}_checksums.txt" "$tmpfile"
  apt-get update
  apt-get install -y --no-install-recommends "$tmpfile"
  rm -rf /var/lib/apt/lists/*
  rm -f "$tmpfile"
}

install_sops() {
  local asset_name tmpfile
  case "$(arch)" in
    amd64) asset_name="sops-${OPENCODE_TOOL_SOPS_VERSION}.linux.amd64" ;;
    arm64) asset_name="sops-${OPENCODE_TOOL_SOPS_VERSION}.linux.arm64" ;;
    *) printf 'unsupported architecture for sops\n' >&2; exit 1 ;;
  esac
  tmpfile="$(mktemp)"
  download_github_asset_with_digest 'getsops/sops' "$OPENCODE_TOOL_SOPS_VERSION" "$asset_name" "$tmpfile"
  install_direct_binary "$tmpfile" sops
  rm -f "$tmpfile"
}

install_doggo() {
  local asset_name tmpfile
  case "$(arch)" in
    amd64) asset_name="doggo_${OPENCODE_TOOL_DOGGO_VERSION#v}_Linux_x86_64.tar.gz" ;;
    arm64) asset_name="doggo_${OPENCODE_TOOL_DOGGO_VERSION#v}_Linux_arm64.tar.gz" ;;
    *) printf 'unsupported architecture for doggo\n' >&2; exit 1 ;;
  esac
  tmpfile="$(mktemp)"
  download_github_asset_with_digest 'mr-karan/doggo' "$OPENCODE_TOOL_DOGGO_VERSION" "$asset_name" "$tmpfile"
  install_from_tar_archive "$tmpfile" "$asset_name" doggo doggo
  rm -f "$tmpfile"
}

install_grpcurl() {
  local asset_name tmpfile
  case "$(arch)" in
    amd64) asset_name="grpcurl_${OPENCODE_TOOL_GRPCURL_VERSION#v}_linux_x86_64.tar.gz" ;;
    arm64) asset_name="grpcurl_${OPENCODE_TOOL_GRPCURL_VERSION#v}_linux_arm64.tar.gz" ;;
    *) printf 'unsupported architecture for grpcurl\n' >&2; exit 1 ;;
  esac
  tmpfile="$(mktemp)"
  download_github_asset_with_checksums_file 'fullstorydev/grpcurl' "$OPENCODE_TOOL_GRPCURL_VERSION" "$asset_name" "grpcurl_${OPENCODE_TOOL_GRPCURL_VERSION#v}_checksums.txt" "$tmpfile"
  install_from_tar_archive "$tmpfile" "$asset_name" grpcurl grpcurl
  rm -f "$tmpfile"
}

install_websocat() {
  local asset_name tmpfile
  case "$(arch)" in
    amd64) asset_name='websocat.x86_64-unknown-linux-musl' ;;
    arm64) asset_name='websocat.aarch64-unknown-linux-musl' ;;
    *) printf 'unsupported architecture for websocat\n' >&2; exit 1 ;;
  esac
  tmpfile="$(mktemp)"
  download_github_asset_with_digest 'vi/websocat' "$OPENCODE_TOOL_WEBSOCAT_VERSION" "$asset_name" "$tmpfile"
  install_direct_binary "$tmpfile" websocat
  rm -f "$tmpfile"
}

install_csvlens() {
  local asset_name tmpfile
  case "$(arch)" in
    amd64) asset_name='csvlens-x86_64-unknown-linux-gnu.tar.xz' ;;
    arm64) asset_name='csvlens-aarch64-unknown-linux-gnu.tar.xz' ;;
    *) printf 'unsupported architecture for csvlens\n' >&2; exit 1 ;;
  esac
  tmpfile="$(mktemp)"
  download_github_asset_with_digest 'YS-L/csvlens' "$OPENCODE_TOOL_CSVLENS_VERSION" "$asset_name" "$tmpfile"
  install_from_tar_archive "$tmpfile" "$asset_name" csvlens csvlens
  rm -f "$tmpfile"
}

install_tlrc() {
  local asset_name tmpfile
  case "$(arch)" in
    amd64) asset_name="tlrc-${OPENCODE_TOOL_TLRC_VERSION}-x86_64-unknown-linux-gnu.deb" ;;
    arm64) asset_name="tlrc-${OPENCODE_TOOL_TLRC_VERSION}-aarch64-unknown-linux-gnu.tar.gz" ;;
    *) printf 'unsupported architecture for tlrc\n' >&2; exit 1 ;;
  esac
  tmpfile="$(mktemp)"
  download_github_asset_with_digest 'tldr-pages/tlrc' "$OPENCODE_TOOL_TLRC_VERSION" "$asset_name" "$tmpfile"
  case "$asset_name" in
    *.deb)
      apt-get update
      apt-get install -y --no-install-recommends "$tmpfile"
      rm -rf /var/lib/apt/lists/*
      ;;
    *)
      install_from_tar_archive "$tmpfile" "$asset_name" tlrc tlrc
      ;;
  esac
  rm -f "$tmpfile"
}

install_uv_tools() {
  export UV_TOOL_DIR=/opt/uv/tools
  export UV_TOOL_BIN_DIR=/usr/local/bin
  uv tool install "basedpyright==$OPENCODE_TOOL_BASEDPYRIGHT_VERSION"
  uv tool install "pytest==$OPENCODE_TOOL_PYTEST_VERSION"
  uv tool install "ruff==$OPENCODE_TOOL_RUFF_VERSION"
  uv tool install "podman-compose==$OPENCODE_TOOL_PODMAN_COMPOSE_VERSION"
}

install_apt_packages
install_uv
install_watchexec
install_xh
install_jj
install_worktrunk
install_dive
install_sops
install_doggo
install_grpcurl
install_websocat
install_csvlens
install_tlrc
install_uv_tools
