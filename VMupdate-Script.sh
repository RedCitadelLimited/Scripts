#!/usr/bin/env bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

print_header() {
    echo
    echo -e "${CYAN}=== $1 ===${NC}"
}

print_ok() {
    echo -e "${GREEN}$1${NC}"
}

print_warn() {
    echo -e "${YELLOW}$1${NC}"
}

print_err() {
    echo -e "${RED}$1${NC}"
}

emit_triplet() {
    local name="$1"
    local cur_ver="$2"
    local latest_ver="$3"

    [ -z "$cur_ver" ] && cur_ver="unknown"
    [ -z "$latest_ver" ] && latest_ver="unknown"

    if [ "$cur_ver" = "$latest_ver" ] && [ "$cur_ver" != "unknown" ]; then
        print_ok "$name | $cur_ver -> $latest_ver"
    else
        print_warn "$name | $cur_ver -> $latest_ver"
    fi
}

audit_apt() {
    print_header "APT"

    if ! have_cmd apt || ! have_cmd dpkg-query; then
        print_err "apt or dpkg-query not found"
        return
    fi

    local found=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue

        pkg=$(awk -F/ '{print $1}' <<< "$line")
        new_ver=$(sed -n 's/.*upgradable from: \([^]]*\)].*/\1/p' <<< "$line")
        cur_ver=$(dpkg-query -W -f='${Version}\n' "$pkg" 2>/dev/null)

        if [ -n "$pkg" ] && [ -n "$cur_ver" ] && [ -n "$new_ver" ]; then
            print_warn "$pkg | $cur_ver -> $new_ver"
            found=1
        fi
    done < <(apt list --upgradable 2>/dev/null | tail -n +2)

    [ "$found" -eq 0 ] && print_ok "No APT upgrades available"
}

audit_snap() {
    print_header "SNAP"

    if ! have_cmd snap; then
        print_err "snap not found"
        return
    fi

    declare -A refreshes
    local listed=0

    while IFS='|' read -r name cur_ver new_ver; do
        [ -z "$name" ] && continue
        refreshes["$name"]="$new_ver"
    done < <(snap refresh --list 2>/dev/null | awk 'NR>1 {print $1 "|" $2 "|" $3}')

    while IFS='|' read -r name cur_ver; do
        [ -z "$name" ] && continue
        listed=1
        if [ -n "${refreshes[$name]}" ]; then
            print_warn "$name | $cur_ver -> ${refreshes[$name]}"
        else
            print_ok "$name | $cur_ver -> $cur_ver"
        fi
    done < <(snap list 2>/dev/null | awk 'NR>1 {print $1 "|" $2}')

    [ "$listed" -eq 0 ] && print_ok "No snaps found"
}

audit_pipx() {
    print_header "PIPX"

    if ! have_cmd pipx || ! have_cmd python3; then
        print_err "pipx or python3 not found"
        return
    fi

    local json
    json=$(pipx list --json 2>/dev/null)
    [ -z "$json" ] && {
        print_err "pipx list failed"
        return
    }

    mapfile -t pkgs < <(printf '%s\n' "$json" | python3 -c '
import json,sys
data=json.load(sys.stdin)
for name in sorted(data.get("venvs",{}).keys()):
    print(name)
' 2>/dev/null)

    [ "${#pkgs[@]}" -eq 0 ] && {
        print_ok "No pipx packages found"
        return
    }

    for pkg in "${pkgs[@]}"; do
        cur_ver=$(printf '%s\n' "$json" | python3 -c "
import json,sys
data=json.load(sys.stdin)
meta=data.get('venvs',{}).get('$pkg',{})
print(meta.get('metadata',{}).get('main_package',{}).get('package_version','unknown'))
" 2>/dev/null)

        latest_ver=$(python3 -m pip index versions "$pkg" 2>/dev/null | awk -F': ' '/Available versions:/ {print $2}' | cut -d',' -f1 | xargs)
        emit_triplet "$pkg" "$cur_ver" "$latest_ver"
    done
}

audit_pip() {
    print_header "PIP"

    if ! have_cmd python3; then
        print_err "python3 not found"
        return
    fi

    if ! python3 -m pip --version >/dev/null 2>&1; then
        print_err "python3 -m pip not found"
        return
    fi

    local found=0
    while IFS='|' read -r name cur_ver latest_ver; do
        [ -z "$name" ] && continue
        found=1
        emit_triplet "$name" "$cur_ver" "$latest_ver"
    done < <(
        python3 -m pip list --outdated --format=json 2>/dev/null | python3 -c '
import json,sys
try:
    data=json.load(sys.stdin)
except Exception:
    data=[]
for item in data:
    print(f"{item.get(\"name\",\"\")}|{item.get(\"version\",\"unknown\")}|{item.get(\"latest_version\",\"unknown\")}")
' 2>/dev/null
    )

    [ "$found" -eq 0 ] && print_ok "No outdated pip packages reported"
}

audit_npm_global() {
    print_header "NPM GLOBAL"

    if ! have_cmd npm || ! have_cmd python3; then
        print_err "npm or python3 not found"
        return
    fi

    local found=0
    while IFS='|' read -r name cur_ver latest_ver; do
        [ -z "$name" ] && continue
        found=1
        emit_triplet "$name" "$cur_ver" "$latest_ver"
    done < <(
        npm outdated -g --json 2>/dev/null | python3 -c '
import json,sys
try:
    data=json.load(sys.stdin)
except Exception:
    data={}
for name in sorted(data.keys()):
    item=data[name]
    print(f"{name}|{item.get(\"current\",\"unknown\")}|{item.get(\"latest\", item.get(\"wanted\",\"unknown\"))}")
' 2>/dev/null
    )

    [ "$found" -eq 0 ] && print_ok "No outdated npm global packages reported"
}

audit_pnpm_global() {
    print_header "PNPM GLOBAL"

    if ! have_cmd pnpm || ! have_cmd python3; then
        print_err "pnpm or python3 not found"
        return
    fi

    local found=0
    while IFS='|' read -r name cur_ver latest_ver; do
        [ -z "$name" ] && continue
        found=1
        emit_triplet "$name" "$cur_ver" "$latest_ver"
    done < <(
        pnpm outdated -g --format json 2>/dev/null | python3 -c '
import json,sys
try:
    data=json.load(sys.stdin)
except Exception:
    data=[]
for item in data:
    name=item.get("name","")
    if name:
        print(f"{name}|{item.get(\"current\",\"unknown\")}|{item.get(\"latest\",\"unknown\")}")
' 2>/dev/null
    )

    [ "$found" -eq 0 ] && print_ok "No outdated pnpm global packages reported"
}

audit_yarn_global() {
    print_header "YARN GLOBAL"

    if ! have_cmd yarn || ! have_cmd python3; then
        print_err "yarn or python3 not found"
        return
    fi

    local found=0
    while IFS='|' read -r name cur_ver latest_ver; do
        [ -z "$name" ] && continue
        found=1
        emit_triplet "$name" "$cur_ver" "$latest_ver"
    done < <(
        yarn global outdated --json 2>/dev/null | python3 -c '
import json,sys
for line in sys.stdin:
    try:
        obj=json.loads(line)
    except Exception:
        continue
    if obj.get("type") != "table":
        continue
    for row in obj.get("data",{}).get("body",[]):
        if len(row) >= 4:
            print(f"{row[0]}|{row[1]}|{row[3]}")
' 2>/dev/null
    )

    [ "$found" -eq 0 ] && print_ok "No outdated yarn global packages reported"
}

audit_cargo() {
    print_header "CARGO"

    if ! have_cmd cargo; then
        print_err "cargo not found"
        return
    fi

    if ! cargo install --list >/dev/null 2>&1; then
        print_err "cargo install --list failed"
        return
    fi

    local found=0
    while IFS='|' read -r name cur_ver; do
        [ -z "$name" ] && continue
        found=1
        latest_ver=$(cargo search "^${name}$" --limit 1 2>/dev/null | sed -n 's/^'"$name"' = "\(.*\)".*/\1/p' | head -n1)
        emit_triplet "$name" "$cur_ver" "$latest_ver"
    done < <(
        cargo install --list 2>/dev/null | awk -F' v' '/^[a-zA-Z0-9_.-]+ v[0-9]/ {print $1 "|" $2}'
    )

    [ "$found" -eq 0 ] && print_ok "No cargo-installed packages found"
}

audit_gem() {
    print_header "GEM"

    if ! have_cmd gem; then
        print_err "gem not found"
        return
    fi

    local found=0
    while IFS='|' read -r name cur_ver latest_ver; do
        [ -z "$name" ] && continue
        found=1
        emit_triplet "$name" "$cur_ver" "$latest_ver"
    done < <(
        gem outdated 2>/dev/null | sed -n 's/^\([^ ]*\) (\([^<]*\) < \(.*\))$/\1|\2|\3/p'
    )

    [ "$found" -eq 0 ] && print_ok "No outdated gems reported"
}

audit_flatpak() {
    print_header "FLATPAK"

    if ! have_cmd flatpak; then
        print_err "flatpak not found"
        return
    fi

    local found=0
    while IFS='|' read -r name cur_ver new_ver; do
        [ -z "$name" ] && continue
        found=1
        print_warn "$name | ${cur_ver:-installed} -> ${new_ver:-update available}"
    done < <(
        flatpak remote-ls --updates 2>/dev/null | awk '
            NF {
                name=$1
                cur=(NF>=2?$2:"installed")
                new=(NF>=3?$3:"update available")
                print name "|" cur "|" new
            }'
    )

    [ "$found" -eq 0 ] && print_ok "No flatpak updates reported"
}

audit_brew() {
    print_header "HOMEBREW"

    if ! have_cmd brew || ! have_cmd python3; then
        print_err "brew or python3 not found"
        return
    fi

    local json
    json=$(brew outdated --json=v2 2>/dev/null)
    if [ -z "$json" ]; then
        print_ok "No Homebrew updates reported"
        return
    fi

    local found=0
    while IFS='|' read -r name cur_ver latest_ver; do
        [ -z "$name" ] && continue
        found=1
        emit_triplet "$name" "$cur_ver" "$latest_ver"
    done < <(
        printf '%s\n' "$json" | python3 -c '
import json,sys
try:
    data=json.load(sys.stdin)
except Exception:
    data={}
for item in data.get("formulae",[]):
    cur=item.get("installed_versions",["unknown"])
    cur_ver=cur[-1] if cur else "unknown"
    latest=item.get("current_version","unknown")
    print(f"{item.get(\"name\",\"\")}|{cur_ver}|{latest}")
for item in data.get("casks",[]):
    cur=item.get("installed_versions",["unknown"])
    cur_ver=cur[-1] if cur else "unknown"
    latest=item.get("current_version","unknown")
    print(f"{item.get(\"name\",\"\")}|{cur_ver}|{latest}")
' 2>/dev/null
    )

    [ "$found" -eq 0 ] && print_ok "No Homebrew updates reported"
}

audit_git() {
    print_header "GIT"

    if ! have_cmd git; then
        print_err "git not found"
        return
    fi

    local tmpfile
    tmpfile=$(mktemp)

    find / -type d -name ".git" 2>/dev/null | while read -r gitdir; do
        repo=$(dirname "$gitdir")
        cd "$repo" || continue

        branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        [ -z "$branch" ] && continue

        git fetch -q 2>/dev/null

        local_commit=$(git rev-parse --short HEAD 2>/dev/null)
        remote_commit=$(git rev-parse --short @{u} 2>/dev/null)

        current_tag=$(git describe --tags --abbrev=0 2>/dev/null)
        latest_tag=$(git describe --tags "$(git rev-list --tags --max-count=1 2>/dev/null)" 2>/dev/null)

        current=${current_tag:-$local_commit}
        latest=${latest_tag:-$remote_commit}

        [ -z "$local_commit" ] && continue
        [ -z "$latest" ] && latest="unknown"

        if [ "$local_commit" = "$remote_commit" ] && [ -n "$remote_commit" ]; then
            echo -e "${GREEN}${repo} | ${current} -> ${latest}${NC}"
        else
            echo -e "${YELLOW}${repo} | ${current} -> ${latest}${NC}"
        fi

        echo 1 >> "$tmpfile"
    done

    if [ ! -s "$tmpfile" ]; then
        print_ok "No git repos found"
    fi

    rm -f "$tmpfile"
}

audit_apt
audit_snap
audit_pipx
audit_pip
audit_npm_global
audit_pnpm_global
audit_yarn_global
audit_cargo
audit_gem
audit_flatpak
audit_brew
audit_git
