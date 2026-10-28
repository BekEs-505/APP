#!/usr/bin/env bash
# ============================================================
#   APPS BEKES Panel v3.2
#   لوحة تحكم رفع التطبيقات - متوافقة مع iOS NewTerm
#   © B6_7E | بيكاس
# ============================================================

# ---------- إعدادات ----------
AUTO_PUSH=1

# ---------- التحقق من bash ----------
if [ -z "${BASH_VERSION:-}" ]; then
    printf "\033[0;31m✗ هذا السكربت يتطلب bash\033[0m\n"
    printf "  جرّب: bash %s\n" "$0"
    exit 1
fi

# ---------- الألوان ----------
BOLD=$'\033[1m';  DIM=$'\033[2m'
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; MAGENTA=$'\033[0;35m'
NC=$'\033[0m'

N_PINK=$'\033[1;38;5;207m'
N_HOT=$'\033[1;38;5;198m'
N_PURPLE=$'\033[1;38;5;141m'
N_CYAN=$'\033[1;38;5;51m'
N_TEAL=$'\033[1;38;5;45m'
N_GOLD=$'\033[1;38;5;226m'
N_ORANGE=$'\033[1;38;5;214m'
N_LIME=$'\033[1;38;5;46m'
N_BLUE=$'\033[1;38;5;39m'
N_RED=$'\033[1;38;5;196m'
N_GREY=$'\033[0;38;5;245m'

# ---------- المسارات ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
cd "$SCRIPT_DIR" || { printf "%s✗ تعذر الدخول إلى %s%s\n" "$RED" "$SCRIPT_DIR" "$NC"; exit 1; }
HTML_FILE="index.html"
ICONS_DIR="icons"
TMP_FILE=""

# ---------- كشف البيئة ----------
is_ios() {
    [ -d "/var/mobile" ] && [ "$(uname -s 2>/dev/null)" = "Darwin" ]
}

# ---------- mktemp آمن ----------
safe_mktemp() {
    local f
    f=$(mktemp 2>/dev/null) && [ -f "$f" ] && { printf '%s' "$f"; return 0; }
    f=$(mktemp -t iosdump.XXXXXX 2>/dev/null) && [ -f "$f" ] && { printf '%s' "$f"; return 0; }
    f="${TMPDIR:-/tmp}/iosdump.$$.$(date +%s)"
    : > "$f" 2>/dev/null && { printf '%s' "$f"; return 0; }
    return 1
}

# ---------- تنظيف ----------
cleanup() {
    [ -n "$TMP_FILE" ] && [ -f "$TMP_FILE" ] && rm -f "$TMP_FILE" 2>/dev/null
    TMP_FILE=""
}
trap cleanup EXIT
trap 'echo; exit 130' INT

# ---------- أدوات ----------
hr() { printf "%s\n" "${N_PINK}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

count_apps_in() {
    local file="$1" section="$2" upper
    upper=$(echo "$section" | tr '[:lower:]' '[:upper:]')
    awk -v ms="<!-- ${upper}_APPS_START -->" -v me="<!-- ${upper}_APPS_END -->" '
        index($0, ms) { in_s = 1; next }
        index($0, me) { in_s = 0; next }
        in_s && /class="app-item"/ { c++ }
        END { print c + 0 }
    ' "$file" 2>/dev/null
}

count_apps() { count_apps_in "$HTML_FILE" "$1"; }

# ---------- إدخال ----------
ask() {
    local prompt="$1" default="${2:-}" value
    if [ -n "$default" ]; then
        printf "%s➤%s %s %s[%s]%s: " "$N_CYAN" "$NC" "$prompt" "$DIM" "$default" "$NC" >&2
    else
        printf "%s➤%s %s: " "$N_CYAN" "$NC" "$prompt" >&2
    fi
    if ! IFS= read -r value; then printf "\n"; exit 0; fi
    printf '%s' "${value:-$default}"
}

ask_required() {
    local prompt="$1" value="" tries=0
    while [ -z "$value" ] && [ "$tries" -lt 5 ]; do
        value=$(ask "$prompt")
        [ -z "$value" ] && printf "%s✗ مطلوب%s\n" "$N_RED" "$NC" >&2
        tries=$((tries + 1))
    done
    printf '%s' "$value"
}

confirm() {
    local prompt="$1" default="${2:-y}" value
    printf "%s?%s %s %s[y/n]%s [%s]: " "$N_GOLD" "$NC" "$prompt" "$DIM" "$NC" "$default" >&2
    if ! IFS= read -r value; then printf "\n"; exit 0; fi
    value="${value:-$default}"
    case "$value" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# ←─ إدخال مع الإبقاء على القيمة الحالية عند تركه فارغاً ─→
prompt_keep() {
    local label="$1" current="$2"
    local display="$current"
    if [ ${#display} -gt 45 ]; then display="${display:0:42}..."; fi

    if [ -n "$current" ]; then
        printf "%s➤%s %s\n" "$N_CYAN" "$NC" "$label" >&2
        printf "   %s↳ الحالي: %s%s%s\n" "$DIM" "$N_GOLD" "$display" "$NC" >&2
    else
        printf "%s➤%s %s %s(فارغ حالياً)%s\n" "$N_CYAN" "$NC" "$label" "$DIM" "$NC" >&2
    fi
    printf "   %s↳ Enter فارغ = إبقاء الحالي، أو اكتب قيمة جديدة:%s " "$DIM" "$NC" >&2

    local value
    if ! IFS= read -r value; then printf "\n"; exit 0; fi
    if [ -z "$value" ]; then
        printf '%s' "$current"
    else
        printf '%s' "$value"
    fi
}

# ---------- HTML ----------
html_escape() {
    local s="$1"
    s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"
    s="${s//\"/&quot;}"; s="${s//\'/&#39;}"
    printf '%s' "$s"
}

# ←─ فكّ الترميز (scan أحادي المسار = صحيح 100%) ─→
html_unescape() {
    printf '%s' "$1" | awk '{
        s = $0; out = ""; n = length(s); i = 1
        while (i <= n) {
            c = substr(s, i, 1)
            if (c == "&") {
                r = substr(s, i, 6)
                if (substr(r, 1, 5) == "&amp;")  { out = out "&";  i += 5; continue }
                if (substr(r, 1, 4) == "&lt;")   { out = out "<";  i += 4; continue }
                if (substr(r, 1, 4) == "&gt;")   { out = out ">";  i += 4; continue }
                if (substr(r, 1, 6) == "&quot;") { out = out "\""; i += 6; continue }
                if (substr(r, 1, 5) == "&#39;")  { out = out "\047"; i += 5; continue }
            }
            out = out c; i++
        }
        printf "%s", out
    }'
}

backup_html() { cp "$HTML_FILE" "${HTML_FILE}.bak" 2>/dev/null; }

# ---------- أيقونة ----------
handle_icon() {
    local input="$1" section="$2" name="$3"
    local default="https://raw.githubusercontent.com/iosdumpzzz/MyIcon/refs/heads/main/Apps/default.png"
    [ -z "$input" ] && { printf '%s' "$default"; return; }
    case "$input" in
        http://*|https://*) printf '%s' "$input"; return ;;
    esac
    if [ -f "$input" ]; then
        local safe ext dest_dir dest
        safe=$(echo "$name" | tr -cs 'a-zA-Z0-9._-' '-' | tr 'A-Z' 'a-z' | sed 's/^-*//; s/-*$//')
        [ ${#safe} -lt 2 ] && safe="app_$(date +%s)"
        ext="${input##*.}"; ext=$(echo "$ext" | tr 'A-Z' 'a-z')
        dest_dir="$ICONS_DIR/$section"
        mkdir -p "$dest_dir" 2>/dev/null
        dest="$dest_dir/${safe}.${ext}"
        if cp "$input" "$dest" 2>/dev/null; then printf '%s' "$dest"; else printf '%s' "$default"; fi
        return
    fi
    printf '%s' "$default"
}

# ---------- توليد HTML ----------
generate_entry() {
    local name="$1" version="$2" desc="$3" icon="$4" link="$5"
    local e_name e_version e_desc e_icon e_link
    e_name=$(html_escape "$name"); e_version=$(html_escape "$version")
    e_desc=$(html_escape "$desc"); e_icon=$(html_escape "$icon"); e_link=$(html_escape "$link")

    echo "                    <div class=\"app-item\">"
    echo "                        <div class=\"app-meta-box\">"
    echo "                            <a href=\"$e_icon\" target=\"_blank\" class=\"app-icon-link\">"
    echo "                                <img src=\"$e_icon\" class=\"app-icon\" alt=\"Icon\">"
    echo "                            </a>"
    echo "                            <div class=\"app-info\">"
    echo "                                <div class=\"app-name\">$e_name</div>"
    [ -n "$e_version" ] && echo "                                <div class=\"app-version\">$e_version</div>"
    [ -n "$e_desc" ] && echo "                                <div class=\"app-desc\">$e_desc</div>"
    echo "                            </div>"
    echo "                        </div>"
    echo "                        <a href=\"$e_link\" class=\"download-btn\">تنزيل</a>"
    echo "                    </div>"
}

insert_entry() {
    local section="$1" entry="$2"
    local upper ms me entry_file
    upper=$(echo "$section" | tr '[:lower:]' '[:upper:]')
    ms="<!-- ${upper}_APPS_START -->"
    me="<!-- ${upper}_APPS_END -->"

    if ! grep -qF "$me" "$HTML_FILE"; then
        printf "%s✗ علامة الإدراج غير موجودة: %s%s\n" "$N_RED" "$me" "$NC" >&2
        return 1
    fi

    entry_file=$(safe_mktemp) || { printf "%s✗ فشل إنشاء ملف مؤقت%s\n" "$N_RED" "$NC" >&2; return 1; }
    TMP_FILE=$(safe_mktemp) || { rm -f "$entry_file"; TMP_FILE=""; return 1; }

    printf '%s\n' "$entry" > "$entry_file"
    awk -v ms="$ms" -v me="$me" -v ef="$entry_file" '
        index($0, ms) { in_s = 1; print; next }
        index($0, me) {
            if (in_s) { while ((getline l < ef) > 0) print l; close(ef) }
            in_s = 0; print; next
        }
        { print }
    ' "$HTML_FILE" > "$TMP_FILE" 2>/dev/null || {
        rm -f "$entry_file" "$TMP_FILE"; TMP_FILE=""
        return 1
    }

    if [ ! -s "$TMP_FILE" ]; then rm -f "$entry_file" "$TMP_FILE"; TMP_FILE=""; return 1; fi
    mv "$TMP_FILE" "$HTML_FILE"; TMP_FILE=""
    rm -f "$entry_file"
    return 0
}

# ---------- عرض قائمة التطبيقات ----------
list_apps() {
    local section="$1" upper
    upper=$(echo "$section" | tr '[:lower:]' '[:upper:]')
    awk -v ms="<!-- ${upper}_APPS_START -->" -v me="<!-- ${upper}_APPS_END -->" '
        BEGIN { in_s=0; idx=0; depth=0; name=""; ver="" }
        index($0, ms) { in_s=1; next }
        index($0, me) { in_s=0; next }
        !in_s { next }
        {
            line=$0
            n_o = gsub(/<div[ >]/, "<div ", line)
            n_c = gsub(/<\/div>/, "</div>", line)
            if (depth == 0 && $0 ~ /class="app-item"/) { idx++; name=""; ver="" }
            depth += n_o - n_c
            if ($0 ~ /class="app-name">/) { l=$0; sub(/^[^>]*>/, "", l); sub(/<.*/, "", l); name=l }
            if ($0 ~ /class="app-version">/) { l=$0; sub(/^[^>]*>/, "", l); sub(/<.*/, "", l); ver=l }
            if (depth == 0 && idx > 0 && name != "") {
                printf "  %d) %s", idx, name
                if (ver != "") printf " (%s)", ver
                printf "\n"
                name=""; ver=""
            }
        }
    ' "$HTML_FILE" 2>/dev/null
}

# ←─ تحديد نطاق أسطر تطبيق معيّن (start end) ─→
get_app_range() {
    local file="$1" section="$2" target="$3"
    local upper ms me
    upper=$(echo "$section" | tr '[:lower:]' '[:upper:]')
    ms="<!-- ${upper}_APPS_START -->"
    me="<!-- ${upper}_APPS_END -->"
    awk -v ms="$ms" -v me="$me" -v target="$target" '
        BEGIN { in_s=0; idx=0; depth=0; start=0 }
        index($0, ms) { in_s=1; next }
        index($0, me) { in_s=0; next }
        !in_s { next }
        {
            line=$0
            n_o = gsub(/<div[ >]/, "<div ", line)
            n_c = gsub(/<\/div>/, "</div>", line)
            if (depth == 0 && $0 ~ /class="app-item"/) {
                idx++
                if (idx == target) start=NR
            }
            depth += n_o - n_c
            if (start > 0 && depth == 0) {
                print start, NR
                exit
            }
        }
    ' "$file" 2>/dev/null
}

# ←─ استخراج نص عنصر بـ class ─→
extract_by_class() {
    local file="$1" start="$2" end="$3" cls="$4"
    sed -n "${start},${end}p" "$file" | awk -v pat="class=\"$cls\"" '
        index($0, pat) {
            l=$0
            sub(/^[^>]*>/, "", l)
            sub(/<.*/, "", l)
            gsub(/^[ \t]+|[ \t]+$/, "", l)
            print l
            exit
        }
    '
}

# ←─ استخراج href من عنصر بـ class ─→
extract_href_by_class() {
    local file="$1" start="$2" end="$3" cls="$4"
    sed -n "${start},${end}p" "$file" | awk -v pat="class=\"$cls\"" '
        index($0, pat) {
            l=$0
            if (match(l, /href="[^"]*"/)) {
                v = substr(l, RSTART+6, RLENGTH-7)
                print v
                exit
            }
        }
    '
}

# ============================================================
#   الرفع التلقائي
# ============================================================
auto_push() {
    [ "${AUTO_PUSH:-1}" = "1" ] || return 0
    [ -d ".git" ] || return 0
    command -v git >/dev/null 2>&1 || return 0

    if [ ! -f .gitignore ] || ! grep -qxF '*.bak' .gitignore 2>/dev/null; then
        printf "*.bak\n" >> .gitignore 2>/dev/null
    fi

    echo ""
    printf "%s⟳ جاري الرفع التلقائي إلى GitHub...%s\n" "$N_TEAL" "$NC"

    git add --all 2>/dev/null

    local has_changes=0
    if git rev-parse HEAD >/dev/null 2>&1; then
        git diff --cached --quiet 2>/dev/null || has_changes=1
    else
        has_changes=1
    fi

    if [ "$has_changes" -eq 0 ]; then
        printf "%s⚠ لا توجد تغييرات جديدة للرفع%s\n" "$YELLOW" "$NC"
        return 0
    fi

    local msg="Auto update: $(date '+%Y-%m-%d %H:%M:%S')"
    if ! git commit -q -m "$msg" 2>/dev/null; then
        printf "%s⚠ فشل الـ commit التلقائي%s\n" "$YELLOW" "$NC"
        return 1
    fi

    local branch push_ok=0
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo main)

    if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
        git push -q 2>/dev/null && push_ok=1
    else
        git push -q -u origin "$branch" 2>/dev/null && push_ok=1
    fi

    if [ "$push_ok" -eq 1 ]; then
        printf "%s✓%s تم الرفع التلقائي بنجاح\n" "$N_LIME" "$NC"
        local url; url=$(git remote get-url origin 2>/dev/null || true)
        if [[ "$url" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
            printf "%s🌐 %shttps://%s.github.io/%s/%s\n" \
                "$N_GREY" "$BOLD" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "$NC"
        fi
    else
        printf "%s⚠ فشل الرفع التلقائي - استخدم الخيار 5%s\n" "$YELLOW" "$NC"
        return 1
    fi
    return 0
}

# ============================================================
#   ✎ تعديل تطبيق (جديد)
# ============================================================
edit_app() {
    echo ""
    printf "%s╭─────────────────────────────────────╮%s\n" "$N_ORANGE" "$NC"
    printf "%s│      ✎  تعديل تطبيق موجود           │%s\n" "$N_ORANGE" "$NC"
    printf "%s╰─────────────────────────────────────╯%s\n" "$N_ORANGE" "$NC"
    echo ""
    printf "  %s[1]%s iOS\n" "$N_CYAN" "$NC"
    printf "  %s[2]%s Android\n" "$N_CYAN" "$NC"
    printf "  %s[3]%s Android TV\n" "$N_CYAN" "$NC"
    echo ""
    printf "%s➤%s اختر القسم: " "$N_CYAN" "$NC" >&2
    local c; IFS= read -r c || { echo; exit 0; }
    local section
    case "$c" in
        1) section="ios" ;; 2) section="android" ;; 3) section="tv" ;;
        *) printf "%s✗ اختيار غير صالح%s\n" "$N_RED" "$NC" >&2; return 1 ;;
    esac

    local total; total=$(count_apps "$section")
    if [ "$total" -eq 0 ]; then
        printf "%s⚠ لا توجد تطبيقات في هذا القسم%s\n" "$YELLOW" "$NC"
        return 1
    fi

    echo ""
    printf "%sالتطبيقات الحالية:%s\n" "$BOLD" "$NC"
    list_apps "$section" | while IFS= read -r l; do printf "%s%s%s\n" "$N_PURPLE" "$l" "$NC"; done
    echo ""

    local num
    num=$(ask_required "رقم التطبيق للتعديل")
    case "$num" in ''|*[!0-9]*) printf "%s✗ رقم غير صالح%s\n" "$N_RED" "$NC" >&2; return 1 ;; esac
    if [ "$num" -lt 1 ] || [ "$num" -gt "$total" ]; then
        printf "%s✗ الرقم خارج النطاق%s\n" "$N_RED" "$NC" >&2; return 1
    fi

    # تحديد نطاق الأسطر
    local range; range=$(get_app_range "$HTML_FILE" "$section" "$num")
    if [ -z "$range" ]; then
        printf "%s✗ فشل تحديد موقع التطبيق%s\n" "$N_RED" "$NC" >&2
        return 1
    fi
    local start end
    start=$(echo "$range" | awk '{print $1}')
    end=$(echo "$range" | awk '{print $2}')

    # استخراج القيم الحالية
    local cur_name cur_version cur_desc cur_icon cur_link
    cur_name=$(extract_by_class "$HTML_FILE" "$start" "$end" "app-name")
    cur_version=$(extract_by_class "$HTML_FILE" "$start" "$end" "app-version")
    cur_desc=$(extract_by_class "$HTML_FILE" "$start" "$end" "app-desc")
    cur_icon=$(extract_href_by_class "$HTML_FILE" "$start" "$end" "app-icon-link")
    cur_link=$(extract_href_by_class "$HTML_FILE" "$start" "$end" "download-btn")

    # فكّ الترميز
    cur_name=$(html_unescape "$cur_name")
    cur_version=$(html_unescape "$cur_version")
    cur_desc=$(html_unescape "$cur_desc")
    cur_icon=$(html_unescape "$cur_icon")
    cur_link=$(html_unescape "$cur_link")

    echo ""
    printf "%s╭──────────────────────────────────────────────────────╮%s\n" "$N_ORANGE" "$NC"
    printf "%s│   ✎ تعديل الحقول — Enter فارغ = إبقاء القيمة الحالية │%s\n" "$N_ORANGE" "$NC"
    printf "%s╰──────────────────────────────────────────────────────╯%s\n" "$N_ORANGE" "$NC"
    echo ""

    local new_name new_version new_desc new_icon_input new_link
    new_name=$(prompt_keep "اسم التطبيق" "$cur_name")
    new_version=$(prompt_keep "الإصدار (مثال: v1.0 · ipa)" "$cur_version")
    new_desc=$(prompt_keep "الوصف" "$cur_desc")
    new_icon_input=$(prompt_keep "الأيقونة (رابط أو مسار محلي)" "$cur_icon")
    new_link=$(prompt_keep "رابط التنزيل" "$cur_link")

    # تحقق من الحقول الإلزامية
    if [ -z "$new_name" ]; then
        printf "%s✗ اسم التطبيق لا يمكن أن يكون فارغاً%s\n" "$N_RED" "$NC" >&2
        return 1
    fi
    if [ -z "$new_link" ]; then
        printf "%s✗ رابط التنزيل لا يمكن أن يكون فارغاً%s\n" "$N_RED" "$NC" >&2
        return 1
    fi

    # معالجة الأيقونة: إذا لم تتغيّر نستخدمها كما هي (تفادي copy لنفس الملف)
    local new_icon
    if [ "$new_icon_input" = "$cur_icon" ]; then
        new_icon="$cur_icon"
    else
        new_icon=$(handle_icon "$new_icon_input" "$section" "$new_name")
    fi
    [ -z "$new_icon" ] && new_icon="$cur_icon"
    [ -z "$new_icon" ] && new_icon="https://raw.githubusercontent.com/iosdumpzzz/MyIcon/refs/heads/main/Apps/default.png"

    # بناء الإدخال الجديد
    local entry; entry=$(generate_entry "$new_name" "$new_version" "$new_desc" "$new_icon" "$new_link")

    # معاينة
    echo ""
    printf "%s━━━ معاينة التعديل ━━━%s\n" "$N_TEAL" "$NC"
    printf "  %sالاسم:%s     %s%s%s\n" "$N_GREY" "$NC" "$BOLD" "$new_name" "$NC"
    [ -n "$new_version" ] && printf "  %sالإصدار:%s  %s\n" "$N_GREY" "$NC" "$new_version"
    [ -n "$new_desc" ]    && printf "  %sالوصف:%s    %s\n" "$N_GREY" "$NC" "$new_desc"
    printf "  %sالأيقونة:%s  %s%s%s\n" "$N_GREY" "$NC" "$DIM" "$new_icon" "$NC"
    printf "  %sالرابط:%s    %s%s%s\n" "$N_GREY" "$NC" "$DIM" "$new_link" "$NC"
    echo ""

    if ! confirm "حفظ التعديلات على التطبيق رقم $num ؟" "y"; then
        echo "${DIM}تم الإلغاء${NC}"; return 0
    fi

    backup_html

    local entry_file
    entry_file=$(safe_mktemp) || return 1
    TMP_FILE=$(safe_mktemp) || { rm -f "$entry_file"; TMP_FILE=""; return 1; }

    printf '%s\n' "$entry" > "$entry_file"

    awk -v s="$start" -v e="$end" -v ef="$entry_file" '
        NR < s { print; next }
        NR == s { while ((getline l < ef) > 0) print l; close(ef); next }
        NR <= e { next }
        { print }
    ' "$HTML_FILE" > "$TMP_FILE" 2>/dev/null || {
        rm -f "$entry_file" "$TMP_FILE"; TMP_FILE=""
        printf "%s✗ فشل التعديل%s\n" "$N_RED" "$NC" >&2
        return 1
    }

    if [ ! -s "$TMP_FILE" ]; then
        rm -f "$entry_file" "$TMP_FILE"; TMP_FILE=""
        printf "%s✗ فشل: الملف المؤقت فارغ%s\n" "$N_RED" "$NC" >&2
        return 1
    fi

    # التحقق: عدد التطبيقات يجب أن يبقى كما هو
    local after; after=$(count_apps_in "$TMP_FILE" "$section")
    if [ "$after" -ne "$total" ]; then
        rm -f "$entry_file" "$TMP_FILE"; TMP_FILE=""
        printf "%s✗ فشل: عدد التطبيقات تغيّر (كان %s أصبح %s)%s\n" "$N_RED" "$total" "$after" "$NC" >&2
        return 1
    fi

    mv "$TMP_FILE" "$HTML_FILE"; TMP_FILE=""
    rm -f "$entry_file"

    printf "%s✓%s تم تعديل %s%s%s بنجاح\n" "$N_LIME" "$NC" "$BOLD" "$new_name" "$NC"

    auto_push
}

# ============================================================
#   حذف تطبيق
# ============================================================
delete_app() {
    echo ""
    printf "%s╭─────────────────────────────────────╮%s\n" "$N_HOT" "$NC"
    printf "%s│      🗑  حذف تطبيق من القائمة       │%s\n" "$N_HOT" "$NC"
    printf "%s╰─────────────────────────────────────╯%s\n" "$N_HOT" "$NC"
    echo ""
    printf "  %s[1]%s iOS\n" "$N_CYAN" "$NC"
    printf "  %s[2]%s Android\n" "$N_CYAN" "$NC"
    printf "  %s[3]%s Android TV\n" "$N_CYAN" "$NC"
    echo ""
    printf "%s➤%s اختر القسم: " "$N_CYAN" "$NC" >&2
    local c; IFS= read -r c || { echo; exit 0; }
    local section
    case "$c" in
        1) section="ios" ;; 2) section="android" ;; 3) section="tv" ;;
        *) printf "%s✗ اختيار غير صالح%s\n" "$N_RED" "$NC" >&2; return 1 ;;
    esac

    local before; before=$(count_apps "$section")
    if [ "$before" -eq 0 ]; then
        printf "%s⚠ لا توجد تطبيقات في هذا القسم%s\n" "$YELLOW" "$NC"
        return 1
    fi

    echo ""
    printf "%sالتطبيقات الحالية:%s\n" "$BOLD" "$NC"
    list_apps "$section" | while IFS= read -r l; do printf "%s%s%s\n" "$N_PURPLE" "$l" "$NC"; done
    echo ""

    local num
    num=$(ask_required "رقم التطبيق للحذف")
    case "$num" in ''|*[!0-9]*) printf "%s✗ رقم غير صالح%s\n" "$N_RED" "$NC" >&2; return 1 ;; esac
    if [ "$num" -lt 1 ] || [ "$num" -gt "$before" ]; then
        printf "%s✗ الرقم خارج النطاق%s\n" "$N_RED" "$NC" >&2; return 1
    fi

    if ! confirm "متأكد من حذف التطبيق رقم $num ؟" "n"; then
        echo "${DIM}تم الإلغاء${NC}"; return 0
    fi

    backup_html

    local upper ms me
    upper=$(echo "$section" | tr '[:lower:]' '[:upper:]')
    ms="<!-- ${upper}_APPS_START -->"; me="<!-- ${upper}_APPS_END -->"
    TMP_FILE=$(safe_mktemp) || return 1

    awk -v ms="$ms" -v me="$me" -v target="$num" '
        BEGIN { in_s=0; idx=0; depth=0; skip=0 }
        index($0, ms) { in_s=1; print; next }
        index($0, me) { in_s=0; print; next }
        !in_s { print; next }
        {
            line=$0
            n_o = gsub(/<div[ >]/, "<div ", line)
            n_c = gsub(/<\/div>/, "</div>", line)
            if (depth == 0 && $0 ~ /class="app-item"/) {
                idx++
                if (idx == target) skip=1
            }
            depth += n_o - n_c
            if (skip) {
                if (depth == 0) skip=0
                next
            }
            print
        }
    ' "$HTML_FILE" > "$TMP_FILE" 2>/dev/null || {
        rm -f "$TMP_FILE"; TMP_FILE=""
        printf "%s✗ فشل تنفيذ AWK%s\n" "$N_RED" "$NC" >&2
        return 1
    }

    if [ ! -s "$TMP_FILE" ]; then
        rm -f "$TMP_FILE"; TMP_FILE=""
        printf "%s✗ فشل: الملف المؤقت فارغ%s\n" "$N_RED" "$NC" >&2
        return 1
    fi

    local after; after=$(count_apps_in "$TMP_FILE" "$section")

    if [ "$after" -ge "$before" ]; then
        rm -f "$TMP_FILE"; TMP_FILE=""
        printf "%s✗ فشل الحذف: لم يتم العثور على التطبيق المطلوب%s\n" "$N_RED" "$NC" >&2
        return 1
    fi

    mv "$TMP_FILE" "$HTML_FILE"; TMP_FILE=""
    printf "%s✓%s تم الحذف بنجاح (العدد الآن: %s%s%s)\n" \
        "$N_LIME" "$NC" "$N_GOLD" "$after" "$NC"

    auto_push
}

# ============================================================
#   إضافة تطبيق
# ============================================================
add_app() {
    echo ""
    printf "%s╭─────────────────────────────────────╮%s\n" "$N_LIME" "$NC"
    printf "%s│      ➕  إضافة تطبيق جديد           │%s\n" "$N_LIME" "$NC"
    printf "%s╰─────────────────────────────────────╯%s\n" "$N_LIME" "$NC"
    echo ""
    printf "  %s[1]%s iOS\n" "$N_CYAN" "$NC"
    printf "  %s[2]%s Android\n" "$N_CYAN" "$NC"
    printf "  %s[3]%s Android TV\n" "$N_CYAN" "$NC"
    echo ""
    printf "%s➤%s اختر القسم: " "$N_CYAN" "$NC" >&2
    local c; IFS= read -r c || { echo; exit 0; }
    local section
    case "$c" in
        1) section="ios" ;; 2) section="android" ;; 3) section="tv" ;;
        *) printf "%s✗ اختيار غير صالح%s\n" "$N_RED" "$NC" >&2; return 1 ;;
    esac

    echo ""
    local name version desc icon link
    name=$(ask_required "اسم التطبيق")
    version=$(ask "الإصدار (مثال: v1.0 · ipa)")
    desc=$(ask "الوصف")
    icon=$(ask "رابط صورة أو مسار محلي")
    link=$(ask_required "رابط التنزيل")

    backup_html
    local icon_path; icon_path=$(handle_icon "$icon" "$section" "$name")
    [ -z "$icon_path" ] && icon_path="https://raw.githubusercontent.com/iosdumpzzz/MyIcon/refs/heads/main/Apps/default.png"

    local entry; entry=$(generate_entry "$name" "$version" "$desc" "$icon_path" "$link")
    local before; before=$(count_apps "$section")

    if insert_entry "$section" "$entry"; then
        local after; after=$(count_apps "$section")
        if [ "$after" -le "$before" ]; then
            printf "%s✗ فشل: لم تتم الإضافة%s\n" "$N_RED" "$NC" >&2
            return 1
        fi
        printf "%s✓%s أُضيف %s%s%s إلى %s%s%s\n" \
            "$N_LIME" "$NC" "$BOLD" "$name" "$NC" "$N_PURPLE" "$section" "$NC"
        auto_push
    else
        printf "%s✗ فشلت الإضافة%s\n" "$N_RED" "$NC" >&2
        return 1
    fi
}

# ============================================================
#   رفع يدوي
# ============================================================
git_push() {
    echo ""
    printf "%s╭─────────────────────────────────────╮%s\n" "$N_BLUE" "$NC"
    printf "%s│      🚀  رفع التغييرات إلى GitHub   │%s\n" "$N_BLUE" "$NC"
    printf "%s╰─────────────────────────────────────╯%s\n" "$N_BLUE" "$NC"
    echo ""

    if ! command -v git >/dev/null 2>&1; then
        printf "%s✗ git غير مثبت%s\n" "$N_RED" "$NC"
        if is_ios; then
            printf "  على iOS: ${N_CYAN}apt install git${NC}\n"
        else
            printf "  Linux: ${N_CYAN}sudo apt install git${NC}\n"
            printf "  macOS: ${N_CYAN}brew install git${NC}\n"
        fi
        return 1
    fi

    if [ ! -f .gitignore ] || ! grep -qxF '*.bak' .gitignore 2>/dev/null; then
        printf "*.bak\n" >> .gitignore 2>/dev/null
    fi

    if [ ! -d ".git" ]; then
        printf "%s⚠ هذا ليس مستودع Git%s\n" "$YELLOW" "$NC"
        confirm "هل تريد تهيئته الآن؟" "y" || return 1
        local remote; remote=$(ask_required "رابط المستودع (https://github.com/user/repo.git)")
        git init -q
        git branch -M main 2>/dev/null || true
        git remote add origin "$remote" 2>/dev/null || true
        printf "%s✓%s تمت التهيئة\n" "$N_LIME" "$NC"
    fi

    local msg; msg=$(ask "رسالة الـ commit" "Init")
    [ -z "$msg" ] && msg="Init"

    echo ""
    printf "%s$ git add --all%s\n" "$N_GREY" "$NC"
    git add --all

    local has_changes=0
    if git rev-parse HEAD >/dev/null 2>&1; then
        git diff --cached --quiet || has_changes=1
    else
        has_changes=1
    fi

    if [ "$has_changes" -eq 1 ]; then
        printf "%s$ git commit -m \"%s\"%s\n" "$N_GREY" "$msg" "$NC"
        git commit -m "$msg"
    else
        printf "%s⚠ لا توجد تغييرات جديدة%s\n" "$YELLOW" "$NC"
    fi

    echo ""
    printf "%s$ git push%s\n" "$N_GREY" "$NC"
    local branch push_ok=0
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo main)
    if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
        git push && push_ok=1
    else
        git push -u origin "$branch" && push_ok=1
    fi

    if [ "$push_ok" -eq 1 ]; then
        printf "%s✓ تم الرفع بنجاح%s\n" "$N_LIME" "$NC"
        local url; url=$(git remote get-url origin 2>/dev/null || true)
        if [[ "$url" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
            echo ""
            printf "🌐 %sGitHub Pages:%s %shttps://%s.github.io/%s/%s\n" \
                "$BOLD" "$NC" "$N_CYAN" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "$NC"
        fi
    else
        printf "%s✗ فشل الـ push%s\n" "$N_RED" "$NC" >&2
        return 1
    fi
}

# ============================================================
#   الشعار
# ============================================================
banner() {
    echo ""
    printf "  %s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n" "$N_HOT" "$NC"
    echo ""
    printf "  %s╔═╗ ╔═╗ ╔═╗ ╔═╗  ╔╗  ╔═╗ ╦╔═ ╔═╗ ╔═╗%s\n" "$N_PINK" "$NC"
    printf "  %s╠═╣ ╠═╝ ╠═╝ ╚═╗  ╠╩╗ ║╣  ╠╩╗ ║╣  ╚═╗%s\n" "$N_GOLD" "$NC"
    printf "  %s╩ ╩ ╩   ╩   ╚═╝  ╚═╝ ╚═╝ ╩ ╩ ╚═╝ ╚═╝%s\n" "$N_CYAN" "$NC"
    echo ""
    printf "  %s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n" "$N_HOT" "$NC"
    echo ""
    printf "      %s◆%s  %sلوحة تحكم رفع التطبيقات%s  %s◆%s\n" \
        "$N_GOLD" "$NC" "$BOLD" "$NC" "$N_GOLD" "$NC"
    printf "      %s© B6_7E | بيكاس%s\n" "$N_TEAL" "$NC"
    echo ""
    if is_ios; then
        printf "  %sالبيئة:%s %siOS (NewTerm)%s\n" "$N_GREY" "$NC" "$N_PURPLE" "$NC"
    fi
    printf "  %siOS:%s %s%s%s   %sAndroid:%s %s%s%s   %sTV:%s %s%s%s\n" \
        "$N_GREY" "$NC" "$N_PINK" "$(count_apps ios)" "$NC" \
        "$N_GREY" "$NC" "$N_GOLD" "$(count_apps android)" "$NC" \
        "$N_GREY" "$NC" "$N_CYAN" "$(count_apps tv)" "$NC"
    echo ""
    hr
    echo ""
}

# ============================================================
#   القائمة
# ============================================================
show_menu() {
    printf "%s╭─────────────────────────────────────╮%s\n" "$N_PURPLE" "$NC"
    printf "%s│          %sالقائمة الرئيسية%s           │%s\n" "$N_PURPLE" "$BOLD" "$NC" "$NC"
    printf "%s╰─────────────────────────────────────╯%s\n" "$N_PURPLE" "$NC"
    printf "  %s[1]%s  ➕  %sإضافة تطبيق%s\n"    "$N_LIME"   "$NC" "$BOLD" "$NC"
    printf "  %s[2]%s  ✎   %sتعديل تطبيق%s\n"    "$N_ORANGE" "$NC" "$BOLD" "$NC"
    printf "  %s[3]%s  🗑   %sحذف تطبيق%s\n"     "$N_HOT"    "$NC" "$BOLD" "$NC"
    printf "  %s[4]%s  ☰   %sعرض التطبيقات%s\n" "$N_CYAN"   "$NC" "$BOLD" "$NC"
    printf "  %s[5]%s  🚀  %sرفع إلى GitHub%s\n" "$N_BLUE"   "$NC" "$BOLD" "$NC"
    printf "  %s[6]%s  ✕   %sخروج%s\n"          "$N_RED"    "$NC" "$BOLD" "$NC"
    echo ""
    printf "%s➤%s اختر: " "$N_CYAN" "$NC" >&2
}

# ---------- البرنامج الرئيسي ----------
main() {
    banner

    if [ ! -f "$HTML_FILE" ]; then
        printf "%s✗ لم يتم العثور على %s%s\n" "$N_RED" "$HTML_FILE" "$NC" >&2
        exit 1
    fi

    if grep -q $'\r' "$HTML_FILE" 2>/dev/null; then
        printf "%s⚠ الملف بأسطر Windows (CRLF)%s\n" "$YELLOW" "$NC"
        printf "  ${DIM}الحل: tr -d '\\\\r' < index.html > t && mv t index.html${NC}\n\n"
    fi

    while true; do
        show_menu
        local choice; IFS= read -r choice || { echo; exit 0; }
        echo ""

        case "$choice" in
            1) add_app ;;
            2) edit_app ;;
            3) delete_app ;;
            4)
                for s in ios android tv; do
                    local n; n=$(count_apps "$s")
                    printf "%s╭── %s%s%s (%s%s%s) %s────%s\n" \
                        "$N_PURPLE" "$BOLD" "$s" "$NC" "$N_GOLD" "$n" "$NC" "$N_PURPLE" "$NC"
                    local out; out=$(list_apps "$s")
                    if [ -n "$out" ]; then
                        printf "%s\n" "$out" | while IFS= read -r l; do
                            printf "%s%s%s\n" "$N_CYAN" "$l" "$NC"
                        done
                    else
                        printf "  %sلا يوجد%s\n" "$DIM" "$NC"
                    fi
                    echo ""
                done
                ;;
            5) git_push ;;
            6|q|Q|exit) break ;;
            *) printf "%s✗ خيار غير معروف%s\n" "$N_RED" "$NC" >&2 ;;
        esac
    done

    if [ -d ".git" ] && [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        echo ""
        if confirm "توجد تغييرات غير مرفوعة. رفعها الآن إلى GitHub؟" "y"; then
            git_push
        fi
    fi

    echo ""
    printf "%s╭─────────────────────────────────────╮%s\n" "$N_LIME" "$NC"
    printf "%s│  ✓ شكراً لاستخدامك APPS BEKES      │%s\n" "$N_LIME" "$NC"
    printf "%s│  © B6_7E | بيكاس                    │%s\n" "$N_TEAL" "$NC"
    printf "%s╰─────────────────────────────────────╯%s\n" "$N_LIME" "$NC"
    echo ""
}

main "$@"