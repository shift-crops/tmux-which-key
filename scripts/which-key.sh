#!/usr/bin/env bash
# tmux-which-key - LazyVim-style which-key popup for tmux
# Usage: which-key.sh [--config <path>] [--table <name>] [--cache] <pane_id>
#        which-key.sh --clear-cache
#
# The menu is built from the live tmux key bindings (tmux list-keys) so it
# always reflects the user's real tmux configuration. An optional JSON file
# only overrides descriptions and grouping.

set -uo pipefail

CONFIG_FILE=""
KEY_TABLE="prefix"
PANE_ID=""
DUMP=0
CACHE=0
CLEAR_CACHE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --table)
            KEY_TABLE="$2"
            shift 2
            ;;
        --dump)
            DUMP=1
            shift
            ;;
        --cache)
            CACHE=1
            shift
            ;;
        --no-cache)
            CACHE=0
            shift
            ;;
        --clear-cache)
            CLEAR_CACHE=1
            shift
            ;;
        *)
            PANE_ID="$1"
            shift
            ;;
    esac
done

# Resolve override file: explicit > XDG > user home (no built-in default)
if [[ -z "$CONFIG_FILE" ]]; then
    xdg_override="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-which-key/config.json"
    home_override="$HOME/.tmux-which-key.json"
    if [[ -f "$xdg_override" ]]; then
        CONFIG_FILE="$xdg_override"
    elif [[ -f "$home_override" ]]; then
        CONFIG_FILE="$home_override"
    fi
fi

# Parsing the whole key table costs far more than asking tmux for it, so the
# result can be cached. which-key.tmux clears the cache every time it runs,
# which is on every tmux config reload.
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-which-key"
CACHE_FILE="$CACHE_DIR/${KEY_TABLE//[^A-Za-z0-9_-]/_}.cache"

if [[ $CLEAR_CACHE -eq 1 ]]; then
    rm -f "$CACHE_DIR"/*.cache 2>/dev/null
    exit 0
fi

# Nord theme colors
C_KEY=$'\033[38;2;235;203;139m'       # #EBCB8B - yellow
C_GRP=$'\033[38;2;136;192;208m'       # #88C0D0 - cyan
C_DESC=$'\033[38;2;216;222;233m'      # #D8DEE9 - light gray
C_SEP=$'\033[38;2;76;86;106m'         # #4C566A - dark gray
C_HDR=$'\033[38;2;129;161;193m'       # #81A1C1 - blue
C_R=$'\033[0m'

if [[ -z "$PANE_ID" && $DUMP -eq 0 ]]; then
    echo "Usage: which-key.sh [--config <path>] [--table <name>] [--cache] <pane_id>"
    exit 1
fi

# Group ids in display order, with the key that opens them
GROUP_IDS=(window pane session layout buffer misc)
declare -A GROUP_KEYS=(
    [window]=w [pane]=p [session]=s [layout]=l [buffer]=b [misc]=m
)

# The group functions assign to GROUP_RESULT rather than echoing, so
# classifying a hundred bindings does not fork a subshell per word
GROUP_RESULT=""

# Map a tmux command to a group id
group_of_command() {
    case "$1" in
        new-window|next-window|previous-window|select-window|rename-window|\
kill-window|last-window|find-window|move-window|swap-window|link-window|\
unlink-window|respawn-window|list-windows)
            GROUP_RESULT=window ;;
        split-window|select-pane|resize-pane|kill-pane|swap-pane|break-pane|\
join-pane|move-pane|display-panes|last-pane|respawn-pane|pipe-pane|\
capture-pane|rotate-window)
            GROUP_RESULT=pane ;;
        new-session|attach-session|detach-client|kill-session|rename-session|\
switch-client|list-sessions|suspend-client|refresh-client|lock-client|\
lock-server|choose-client|choose-session|choose-tree|kill-server)
            GROUP_RESULT=session ;;
        select-layout|next-layout|previous-layout)
            GROUP_RESULT=layout ;;
        copy-mode|paste-buffer|list-buffers|delete-buffer|choose-buffer|\
show-buffer|set-buffer|save-buffer|load-buffer|clear-history)
            GROUP_RESULT=buffer ;;
        *)
            GROUP_RESULT="" ;;
    esac
}

# Pick the group for a whole command string. Wrappers such as confirm-before
# and command-prompt are skipped so the wrapped command decides the group.
group_of() {
    local cmd="$1"
    local word flags

    case "$cmd" in
        # A menu body mentions many commands, so classify it by what its
        # title formats refer to instead of by the commands it contains
        display-menu*)
            case "$cmd" in
                *'#{pane_'*) GROUP_RESULT=pane ;;
                *'#{window_'*) GROUP_RESULT=window ;;
                *'#{session_'*) GROUP_RESULT=session ;;
                *) GROUP_RESULT=misc ;;
            esac
            return
            ;;
        # choose-tree lists windows with -w, sessions otherwise
        choose-tree*)
            flags="${cmd#choose-tree}"
            flags="${flags# }"
            flags="${flags%% *}"
            if [[ "$flags" == -*w* ]]; then
                GROUP_RESULT=window
            else
                GROUP_RESULT=session
            fi
            return
            ;;
    esac

    for word in $cmd; do
        group_of_command "$word"
        [[ -n "$GROUP_RESULT" ]] && return
    done
    GROUP_RESULT=misc
}

declare -A NOTES=() OVR_DESC=() OVR_GROUP=() HIDDEN=()

load_overrides() {
    [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    local k v
    while IFS=$'\t' read -r k v; do
        [[ -n "$k" ]] && OVR_DESC["$k"]="$v"
    done < <(jq -r '(.descriptions // {}) | to_entries[] | [.key, .value] | @tsv' "$CONFIG_FILE" 2>/dev/null)

    while IFS=$'\t' read -r k v; do
        [[ -n "$k" ]] && OVR_GROUP["$k"]="$v"
    done < <(jq -r '(.groups // {}) | to_entries[] | [.key, .value] | @tsv' "$CONFIG_FILE" 2>/dev/null)

    while IFS= read -r k; do
        [[ -n "$k" ]] && HIDDEN["$k"]=1
    done < <(jq -r '(.hide // [])[]' "$CONFIG_FILE" 2>/dev/null)
}

# Parallel arrays of the bindings in the table, in tmux's own order
BIND_KEYS=() BIND_CMDS=() BIND_DESCS=() BIND_GROUPS=()

load_bindings() {
    local line key note
    while IFS= read -r line; do
        key="${line%%[[:space:]]*}"
        note="${line#*[[:space:]]}"
        note="${note#"${note%%[![:space:]]*}"}"
        # A line with no note at all leaves the key itself in note
        [[ "$note" == "$key" ]] && note=""
        [[ -n "$key" && -n "$note" ]] && NOTES["$key"]="$note"
    done < <(tmux list-keys -N -T "$KEY_TABLE" 2>/dev/null)

    local cmd desc group
    local re='^bind-key[[:space:]]+(-[a-zA-Z][[:space:]]+)*-T[[:space:]]+[^[:space:]]+[[:space:]]+([^[:space:]]+)[[:space:]]+(.*)$'
    while IFS= read -r line; do
        [[ "$line" =~ $re ]] || continue
        # tmux escapes key names such as \# and \; in list-keys output
        key="${BASH_REMATCH[2]#\\}"
        cmd="${BASH_REMATCH[3]}"

        [[ -n "${HIDDEN[$key]:-}" ]] && continue

        desc="${OVR_DESC[$key]:-${NOTES[$key]:-$cmd}}"
        if [[ -n "${OVR_GROUP[$key]:-}" ]]; then
            group="${OVR_GROUP[$key]}"
        else
            group_of "$cmd"
            group="$GROUP_RESULT"
        fi
        [[ -n "${GROUP_KEYS[$group]:-}" ]] || group=misc

        BIND_KEYS+=("$key")
        BIND_CMDS+=("$cmd")
        BIND_DESCS+=("$desc")
        BIND_GROUPS+=("$group")
    done < <(tmux list-keys -T "$KEY_TABLE" 2>/dev/null)
}

# Convert a tmux key name into the token read_key produces for it
KEY_TOKEN=""
key_to_token() {
    local key="$1"
    case "$key" in
        C-Space) printf -v KEY_TOKEN '\x00' ;;
        C-a) printf -v KEY_TOKEN '\x01' ;;
        C-b) printf -v KEY_TOKEN '\x02' ;;
        C-c) printf -v KEY_TOKEN '\x03' ;;
        C-d) printf -v KEY_TOKEN '\x04' ;;
        C-e) printf -v KEY_TOKEN '\x05' ;;
        C-f) printf -v KEY_TOKEN '\x06' ;;
        C-g) printf -v KEY_TOKEN '\x07' ;;
        C-h) printf -v KEY_TOKEN '\x08' ;;
        C-i) printf -v KEY_TOKEN '\x09' ;;
        C-j) printf -v KEY_TOKEN '\x0a' ;;
        C-k) printf -v KEY_TOKEN '\x0b' ;;
        C-l) printf -v KEY_TOKEN '\x0c' ;;
        C-m) printf -v KEY_TOKEN '\x0d' ;;
        C-n) printf -v KEY_TOKEN '\x0e' ;;
        C-o) printf -v KEY_TOKEN '\x0f' ;;
        C-p) printf -v KEY_TOKEN '\x10' ;;
        C-q) printf -v KEY_TOKEN '\x11' ;;
        C-r) printf -v KEY_TOKEN '\x12' ;;
        C-s) printf -v KEY_TOKEN '\x13' ;;
        C-t) printf -v KEY_TOKEN '\x14' ;;
        C-u) printf -v KEY_TOKEN '\x15' ;;
        C-v) printf -v KEY_TOKEN '\x16' ;;
        C-w) printf -v KEY_TOKEN '\x17' ;;
        C-x) printf -v KEY_TOKEN '\x18' ;;
        C-y) printf -v KEY_TOKEN '\x19' ;;
        C-z) printf -v KEY_TOKEN '\x1a' ;;
        Space) printf -v KEY_TOKEN ' ' ;;
        Tab) printf -v KEY_TOKEN '\x09' ;;
        Enter) printf -v KEY_TOKEN '\x0d' ;;
        BSpace) printf -v KEY_TOKEN '\x7f' ;;
        M-?) printf -v KEY_TOKEN 'M-%s' "${key#M-}" ;;
        *) printf -v KEY_TOKEN '%s' "$key" ;;
    esac
}

# Translate a CSI/SS3 sequence into the tmux name for that key
seq_to_name() {
    case "$1" in
        '[A'|'OA') echo Up ;;
        '[B'|'OB') echo Down ;;
        '[C'|'OC') echo Right ;;
        '[D'|'OD') echo Left ;;
        '[1;5A') echo C-Up ;;
        '[1;5B') echo C-Down ;;
        '[1;5C') echo C-Right ;;
        '[1;5D') echo C-Left ;;
        '[1;2A') echo S-Up ;;
        '[1;2B') echo S-Down ;;
        '[1;2C') echo S-Right ;;
        '[1;2D') echo S-Left ;;
        '[2~') echo IC ;;
        '[3~') echo DC ;;
        '[5~') echo PPage ;;
        '[6~') echo NPage ;;
        '[H'|'[1~'|'OH') echo Home ;;
        '[F'|'[4~'|'OF') echo End ;;
        '[Z') echo BTab ;;
        'OP') echo F1 ;;
        'OQ') echo F2 ;;
        'OR') echo F3 ;;
        'OS') echo F4 ;;
        '[15~') echo F5 ;;
        '[17~') echo F6 ;;
        '[18~') echo F7 ;;
        '[19~') echo F8 ;;
        '[20~') echo F9 ;;
        '[21~') echo F10 ;;
        '[23~') echo F11 ;;
        '[24~') echo F12 ;;
        *) echo "" ;;
    esac
}

# Read one keypress into KEY_TOKEN. Escape sequences become tmux key names,
# Alt combinations become "M-<char>", everything else stays a literal byte.
read_key() {
    local c c2 c3 seq
    IFS= read -rsn1 c || return 1

    if [[ "$c" != $'\x1b' ]]; then
        KEY_TOKEN="$c"
        return 0
    fi

    if ! IFS= read -rsn1 -t 0.05 c2 || [[ -z "$c2" ]]; then
        KEY_TOKEN="Escape"
        return 0
    fi

    if [[ "$c2" != '[' && "$c2" != 'O' ]]; then
        KEY_TOKEN="M-$c2"
        return 0
    fi

    seq="$c2"
    while IFS= read -rsn1 -t 0.05 c3 && [[ -n "$c3" ]]; do
        seq+="$c3"
        [[ "$c3" == [A-Za-z~] ]] && break
    done
    KEY_TOKEN=$(seq_to_name "$seq")
    return 0
}

term_width() {
    local cols
    cols=$(tput cols 2>/dev/null)
    [[ "$cols" =~ ^[0-9]+$ && "$cols" -gt 20 ]] || cols=100
    echo "$cols"
}

term_height() {
    local lines
    lines=$(tput lines 2>/dev/null)
    [[ "$lines" =~ ^[0-9]+$ && "$lines" -gt 6 ]] || lines=16
    echo "$lines"
}

# Current level: empty means the group menu, otherwise a group id
CURRENT_GROUP=""

# Paging state. TOTAL_PAGES is recomputed by render_menu, which is the only
# place that knows how many entries fit on screen.
PAGE=0
TOTAL_PAGES=1

# Emit the entries of the current level as key\tdescription\tis_group
current_entries() {
    local i group count
    if [[ -z "$CURRENT_GROUP" ]]; then
        for group in "${GROUP_IDS[@]}"; do
            count=0
            for i in "${!BIND_GROUPS[@]}"; do
                [[ "${BIND_GROUPS[$i]}" == "$group" ]] && ((count++))
            done
            [[ $count -gt 0 ]] || continue
            printf '%s\t%s (%d)\t1\n' "${GROUP_KEYS[$group]}" "$group" "$count"
        done
    else
        for i in "${!BIND_KEYS[@]}"; do
            [[ "${BIND_GROUPS[$i]}" == "$CURRENT_GROUP" ]] || continue
            printf '%s\t%s\t0\n' "${BIND_KEYS[$i]}" "${BIND_DESCS[$i]}"
        done
    fi
}

render_menu() {
    clear

    # Aim for roughly 32 column wide entries, within 1..6 columns
    local width num_cols col_width
    width=$(term_width)
    num_cols=$(( (width - 2) / 32 ))
    [[ $num_cols -lt 1 ]] && num_cols=1
    [[ $num_cols -gt 6 ]] && num_cols=6
    col_width=$(( (width - 2) / num_cols ))

    local breadcrumb="$KEY_TABLE"
    [[ -n "$CURRENT_GROUP" ]] && breadcrumb="$KEY_TABLE > $CURRENT_GROUP"

    printf "%s  Which Key%s  %s│%s  %s%s%s\n" "$C_HDR" "$C_R" "$C_SEP" "$C_R" "$C_DESC" "$breadcrumb" "$C_R"
    printf "%s%s%s\n" "$C_SEP" "$(printf '─%.0s' $(seq 1 $((width - 2))))" "$C_R"

    local keys=() descs=() groups=()
    local key desc is_group
    while IFS=$'\t' read -r key desc is_group; do
        keys+=("$key")
        descs+=("$desc")
        groups+=("$is_group")
    done < <(current_entries)

    local total=${#keys[@]}
    if [[ $total -eq 0 ]]; then
        TOTAL_PAGES=1
        PAGE=0
        printf "  %s(no bindings in %s)%s\n" "$C_DESC" "$KEY_TABLE" "$C_R"
        return
    fi

    # Two header lines and two footer lines frame the entries
    local max_rows=$(( $(term_height) - 4 ))
    [[ $max_rows -lt 1 ]] && max_rows=1

    local per_page=$((max_rows * num_cols))
    TOTAL_PAGES=$(( (total + per_page - 1) / per_page ))
    [[ $PAGE -ge $TOTAL_PAGES ]] && PAGE=$((TOTAL_PAGES - 1))
    [[ $PAGE -lt 0 ]] && PAGE=0

    local first=$((PAGE * per_page))
    local on_page=$((total - first))
    [[ $on_page -gt $per_page ]] && on_page=$per_page
    local num_rows=$(( (on_page + num_cols - 1) / num_cols ))

    local row col i k d prefix dc avail visible_len pad
    for ((row = 0; row < num_rows; row++)); do
        printf "  "
        for ((col = 0; col < num_cols; col++)); do
            i=$((col * num_rows + row))
            [[ $i -lt $on_page ]] || continue
            i=$((first + i))
            k="${keys[$i]}"
            d="${descs[$i]}"
            prefix=""
            dc="$C_DESC"
            if [[ "${groups[$i]}" == "1" ]]; then
                prefix="+"
                dc="$C_GRP"
            fi
            avail=$((col_width - ${#k} - 5 - ${#prefix}))
            [[ ${#d} -gt $avail && $avail -gt 1 ]] && d="${d:0:$((avail - 1))}…"
            visible_len=$(( ${#k} + 4 + ${#prefix} + ${#d} ))
            pad=$((col_width - visible_len))
            [[ $pad -lt 1 ]] && pad=1
            printf "%s%s%s  %s→%s %s%s%s%s" "$C_KEY" "$k" "$C_R" "$C_SEP" "$C_R" "$dc" "$prefix" "$d" "$C_R"
            printf '%*s' "$pad" ""
        done
        printf "\n"
    done

    printf "%s%s%s\n" "$C_SEP" "$(printf '─%.0s' $(seq 1 $((width - 2))))" "$C_R"
    local hint="esc  close"
    [[ -n "$CURRENT_GROUP" ]] && hint+="    ⌫  back"
    if [[ $TOTAL_PAGES -gt 1 ]]; then
        hint+="    ⇥ / ⇧⇥  page $((PAGE + 1))/$TOTAL_PAGES"
    fi
    printf "  %s%s%s\n" "$C_SEP" "$hint" "$C_R"
}

# Run a binding by feeding the original tmux command back to tmux, so the
# quoting tmux printed in list-keys is parsed by tmux itself.
run_binding() {
    local cmd="$1"
    local script
    script=$(mktemp "${TMPDIR:-/tmp}/which-key.XXXXXX") || return 1
    printf '%s\n' "$cmd" > "$script"

    # run-shell does not export TMUX_PANE, and a popup is not a pane, so the
    # target pane is passed explicitly for both paths
    case "$cmd" in
        choose-*|command-prompt*|customize-mode*|copy-mode*|display-popup*|confirm-before*)
            # Let the popup close first, these take over the client themselves
            tmux run-shell -b "sleep 0.1; TMUX_PANE='$PANE_ID' tmux source-file '$script'; rm -f '$script'"
            ;;
        *)
            TMUX_PANE="$PANE_ID" tmux source-file "$script"
            rm -f "$script"
            ;;
    esac
}

handle_key() {
    local token="$1"
    local i entry_token

    if [[ -z "$CURRENT_GROUP" ]]; then
        local group
        for group in "${GROUP_IDS[@]}"; do
            if [[ "${GROUP_KEYS[$group]}" == "$token" ]]; then
                for i in "${!BIND_GROUPS[@]}"; do
                    if [[ "${BIND_GROUPS[$i]}" == "$group" ]]; then
                        CURRENT_GROUP="$group"
                        PAGE=0
                        return 0
                    fi
                done
            fi
        done
        return 0
    fi

    for i in "${!BIND_KEYS[@]}"; do
        [[ "${BIND_GROUPS[$i]}" == "$CURRENT_GROUP" ]] || continue
        key_to_token "${BIND_KEYS[$i]}"
        entry_token="$KEY_TOKEN"
        if [[ "$entry_token" == "$token" ]]; then
            run_binding "${BIND_CMDS[$i]}"
            exit 0
        fi
    done
}

# Records are separated by \x1f: tmux prints one binding per line, but a
# command may well contain a tab.
load_cache() {
    [[ $CACHE -eq 1 && -s "$CACHE_FILE" ]] || return 1
    # An overrides file edited since the cache was written invalidates it
    [[ -n "$CONFIG_FILE" && "$CONFIG_FILE" -nt "$CACHE_FILE" ]] && return 1

    local key cmd desc group
    while IFS=$'\x1f' read -r key cmd desc group; do
        [[ -n "$key" && -n "$group" ]] || continue
        BIND_KEYS+=("$key")
        BIND_CMDS+=("$cmd")
        BIND_DESCS+=("$desc")
        BIND_GROUPS+=("$group")
    done < "$CACHE_FILE"

    [[ ${#BIND_KEYS[@]} -gt 0 ]]
}

save_cache() {
    [[ $CACHE -eq 1 && ${#BIND_KEYS[@]} -gt 0 ]] || return 0
    mkdir -p "$CACHE_DIR" 2>/dev/null || return 0

    # Written via a temporary file so a second popup never reads a half
    # written cache
    local tmp="$CACHE_FILE.$$"
    local i
    for i in "${!BIND_KEYS[@]}"; do
        printf '%s\x1f%s\x1f%s\x1f%s\n' \
            "${BIND_KEYS[$i]}" "${BIND_CMDS[$i]}" "${BIND_DESCS[$i]}" "${BIND_GROUPS[$i]}"
    done > "$tmp" 2>/dev/null && mv -f "$tmp" "$CACHE_FILE" 2>/dev/null
    rm -f "$tmp" 2>/dev/null
}

load_overrides
if ! load_cache; then
    load_bindings
    save_cache
fi

# --dump prints the parsed bindings and exits, for inspecting the grouping
if [[ $DUMP -eq 1 ]]; then
    for i in "${!BIND_KEYS[@]}"; do
        printf '%s\t%s\t%s\t%s\n' \
            "${BIND_GROUPS[$i]}" "${BIND_KEYS[$i]}" "${BIND_DESCS[$i]}" "${BIND_CMDS[$i]}"
    done
    exit 0
fi

while true; do
    render_menu

    read_key || exit 0

    case "$KEY_TOKEN" in
        Escape)
            exit 0
            ;;
        $'\x7f'|$'\x08')
            if [[ -n "$CURRENT_GROUP" ]]; then
                CURRENT_GROUP=""
                PAGE=0
            else
                exit 0
            fi
            continue
            ;;
        "")
            continue
            ;;
    esac

    # Tab and Shift-Tab page through a level that does not fit on screen. They
    # only page while there is more than one page, so a bound Tab still works.
    if [[ $TOTAL_PAGES -gt 1 ]]; then
        case "$KEY_TOKEN" in
            $'\t')
                PAGE=$(( (PAGE + 1) % TOTAL_PAGES ))
                continue
                ;;
            BTab)
                PAGE=$(( (PAGE + TOTAL_PAGES - 1) % TOTAL_PAGES ))
                continue
                ;;
        esac
    fi

    handle_key "$KEY_TOKEN"
done
