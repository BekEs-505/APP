#!/usr/bin/env bash
# ============================================================
#   iosdump Panel v2.1
#   لوحة تحكم رفع التطبيقات - متوافقة مع iOS NewTerm
#   المتطلبات: bash 3.2+ ، git
#
#   التشغيل على iOS:
#     cd /var/mobile/iosdump.repo
#     bash panel.sh
#
#   التشغيل على Linux/macOS:
#     chmod +x panel.sh && ./panel.sh
# ============================================================

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

# ---------- mktemp آمن (iOS BSD) ----------
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
hr() { printf "%s\n" "${DIM}──────────────────────────────────────────────${NC}"; }

count_apps() {
    local upper
    upper=$(echo "$1" | tr '[:lower:]' '[:upper:]')
    awk -v ms="<!-- ${upper}_APPS_START -->" -v me="<!-- ${upper}_APPS_END -->" '
        index($0, ms) { in_s = 1; next }
        index($0, me) { in_s = 0; next }
        in_s && /class="app-item"/ { c++ }
        END { print c + 0 }
    ' "$HTML_FILE" 2>/dev/null
}

# ---------- إدخال ----------
ask() {
    local prompt="$1" default="${2:-}" value
    if [ -n "$default" ]; then
        printf "%s➤%s %s %s[%s]%s: " "$CYAN" "$NC" "$prompt" "$DIM" "$default" "$NC" >&2
    else
        printf "%s➤%s %s: " "$CYAN" "$NC" "$prompt" >&2
    fi
    if ! IFS= read -r value; then
        printf "\n"
        exit 0
    fi
    printf '%s' "${value:-$default}"
}

ask_required() {
    local prompt="$1" value="" tries=0
    while [ -z "$value" ] && [ "$tries" -lt 5 ]; do
        value=$(ask "$prompt")
        [ -z "$value" ] && printf "%s✗ مطلوب%s\n" "$RED" "$NC" >&2
        tries=$((tries + 1))
    done
    printf '%s' "$value"
}

confirm() {
    local prompt="$1" default="${2:-y}" value
    printf "%s?%s %s %s[y/n]%s [%s]: " "$YELLOW" "$NC" "$prompt" "$DIM" "$NC" "$default" >&2
    if ! IFS= read -r value; then
        printf "\n"; exit 0
    fi
    value="${value:-$default}"
    case "$value" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# ---------- HTML ----------
html_escape() {
    local s="$1"
    s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"
    s="${s//\"/&quot;}"; s="${s//\'/&#39;}"
    printf '%s' "$s"
}

backup_html() {
    cp "$HTML_FILE" "${HTML_FILE}.bak" 2>/dev/null
}

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
        if cp "$input" "$dest" 2>/dev/null; then
            printf '%s' "$dest"
        else
            printf '%s' "$default"
        fi
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
        printf "%s✗ علامة الإدراج غير موجودة: %s%s\n" "$RED" "$me" "$NC" >&2
        return 1
    fi

    entry_file=$(safe_mktemp) || { printf "%s✗ فشل إنشاء ملف مؤقت%s\n" "$RED" "$NC" >&2; return 1; }
    TMP_FILE=$(safe_mktemp) || { rm -f "$entry_file"; return 1; }

    printf '%s\n' "$entry" > "$entry_file"
    awk -v ms="$ms" -v me="$me" -v ef="$entry_file" '
        index($0, ms) { in_s = 1; print; next }
        index($0, me) {
            if (in_s) { while ((getline l < ef) > 0) print l; close(ef) }
            in_s = 0; print; next
        }
        { print }
    ' "$HTML_FILE" > "$TMP_FILE" || { rm -f "$entry_file"; return 1; }

    if [ ! -s "$TMP_FILE" ]; then rm -f "$entry_file"; return 1; fi
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
            if ($0 ~ /class="app-name">/) { l=$0; sub(/.*class="app-name">/, "", l); sub(/<.*/, "", l); name=l }
            if ($0 ~ /class="app-version">/) { l=$0; sub(/.*class="app-version">/, "", l); sub(/<.*/, "", l); ver=l }
            if (depth == 0 && idx > 0 && name != "") {
                printf "  %d) %s", idx, name
                if (ver != "") printf " (%s)", ver
                printf "\n"
                name=""; ver=""
            }
        }
    ' "$HTML_FILE" 2>/dev/null
}

# ---------- حذف تطبيق ----------
delete_app() {
    echo ""
    echo "${BOLD}=== حذف تطبيق ===${NC}"
    echo ""
    echo "  1) iOS"; echo "  2) Android"; echo "  3) Android TV"; echo ""
    printf "%s➤%s اختر القسم: " "$CYAN" "$NC" >&2
    local c; IFS= read -r c || { echo; exit 0; }
    local section
    case "$c" in
        1) section="ios" ;; 2) section="android" ;; 3) section="tv" ;;
        *) printf "%s✗ اختيار غير صالح%s\n" "$RED" "$NC" >&2; return 1 ;;
    esac

    local before; before=$(count_apps "$section")
    if [ "$before" -eq 0 ]; then
        printf "%s⚠ لا توجد تطبيقات في هذا القسم%s\n" "$YELLOW" "$NC"
        return 1
    fi

    echo ""
    echo "${BOLD}التطبيقات الحالية:${NC}"
    list_apps "$section"
    echo ""

    local num
    num=$(ask_required "رقم التطبيق للحذف")
    case "$num" in ''|*[!0-9]*) printf "%s✗ رقم غير صالح%s\n" "$RED" "$NC" >&2; return 1 ;; esac
    if [ "$num" -lt 1 ] || [ "$num" -gt "$before" ]; then
        printf "%s✗ الرقم خارج النطاق%s\n" "$RED" "$NC" >&2; return 1
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
    ' "$HTML_FILE" > "$TMP_FILE" || return 1

    local after; after=$(count_apps "$section")
    if [ "$after" -ge "$before" ]; then
        rm -f "$TMP_FILE"; TMP_FILE=""
        printf "%s✗ فشل الحذف%s\n" "$RED" "$NC" >&2
        return 1
    fi

    mv "$TMP_FILE" "$HTML_FILE"; TMP_FILE=""
    printf "%s✓%s تم الحذف (العدد الآن: %s)\n" "$GREEN" "$NC" "$after"
}

# ---------- إضافة تطبيق ----------
add_app() {
    echo ""
    echo "${BOLD}=== إضافة تطبيق جديد ===${NC}"
    echo ""
    echo "  1) iOS"; echo "  2) Android"; echo "  3) Android TV"; echo ""
    printf "%s➤%s اختر القسم: " "$CYAN" "$NC" >&2
    local c; IFS= read -r c || { echo; exit 0; }
    local section
    case "$c" in
        1) section="ios" ;; 2) section="android" ;; 3) section="tv" ;;
        *) printf "%s✗ اختيار غير صالح%s\n" "$RED" "$NC" >&2; return 1 ;;
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

    if insert_entry "$section" "$entry"; then
        printf "%s✓%s أُضيف ${BOLD}%s${NC} إلى ${BOLD}%s${NC}\n" "$GREEN" "$NC" "$name" "$section"
    else
        printf "%s✗ فشلت الإضافة%s\n" "$RED" "$NC" >&2
        return 1
    fi
}

# ---------- رفع إلى GitHub ----------
git_push() {
    echo ""
    echo "${BOLD}=== رفع التغييرات إلى GitHub ===${NC}"
    echo ""

    if ! command -v git >/dev/null 2>&1; then
        printf "%s✗ git غير مثبت%s\n" "$RED" "$NC"
        if is_ios; then
            printf "  على iOS (NewTerm):\n"
            printf "    ${CYAN}apt install git${NC}\n"
            printf "  أو افتح ${BOLD}Sileo/Zebra${NC} وابحث عن 'git'\n"
        else
            printf "  Linux: ${CYAN}sudo apt install git${NC}\n"
            printf "  macOS: ${CYAN}brew install git${NC}\n"
        fi
        return 1
    fi

    if [ ! -d ".git" ]; then
        echo "${YELLOW}⚠ هذا ليس مستودع Git${NC}"
        confirm "هل تريد تهيئته الآن؟" "y" || return 1
        local remote; remote=$(ask_required "رابط المستودع (https://github.com/user/repo.git)")
        git init -q
        git branch -M main 2>/dev/null || true
        git remote add origin "$remote" 2>/dev/null || true
        printf "%s✓%s تمت التهيئة\n" "$GREEN" "$NC"
    fi

    local msg; msg=$(ask "رسالة الـ commit" "Init")
    [ -z "$msg" ] && msg="Init"

    echo ""
    echo "${DIM}$ git add --all${NC}"
    git add --all

    local has_changes=0
    if git rev-parse HEAD >/dev/null 2>&1; then
        git diff --cached --quiet || has_changes=1
    else
        has_changes=1
    fi

    if [ "$has_changes" -eq 1 ]; then
        echo "${DIM}$ git commit -m \"$msg\"${NC}"
        git commit -m "$msg"
    else
        echo "${YELLOW}⚠ لا توجد تغييرات جديدة${NC}"
    fi

    echo ""
    echo "${DIM}$ git push${NC}"
    local branch push_ok=0
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo main)
    if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
        git push && push_ok=1
    else
        git push -u origin "$branch" && push_ok=1
    fi

    if [ "$push_ok" -eq 1 ]; then
        printf "%s✓ تم الرفع بنجاح%s\n" "$GREEN" "$NC"
        local url; url=$(git remote get-url origin 2>/dev/null || true)
        if [[ "$url" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
            echo ""
            echo "🌐 ${BOLD}GitHub Pages:${NC} https://${BASH_REMATCH[1]}.github.io/${BASH_REMATCH[2]}/"
        fi
    else
        printf "%s✗ فشل الـ push%s\n" "$RED" "$NC" >&2
        return 1
    fi
}

# ---------- شعار ----------
banner() {
    echo ""
    printf "%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n" "$CYAN$BOLD" "$NC"
    printf "%s   🚀 iosdump Panel %s - لوحة تحكم التطبيقات%s\n" "$MAGENTA$BOLD" "$DIM" "$NC"
    printf "%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n" "$CYAN$BOLD" "$NC"
    if is_ios; then printf "  ${DIM}البيئة: iOS (NewTerm)${NC}\n"; fi
    printf "  ${DIM}iOS:${NC} ${BOLD}%s${NC}   ${DIM}Android:${NC} ${BOLD}%s${NC}   ${DIM}TV:${NC} ${BOLD}%s${NC}\n" \
        "$(count_apps ios)" "$(count_apps android)" "$(count_apps tv)"
    hr
    echo ""
}

# ---------- البرنامج الرئيسي ----------
main() {
    banner

    if [ ! -f "$HTML_FILE" ]; then
        printf "%s✗ لم يتم العثور على %s%s\n" "$RED" "$HTML_FILE" "$NC" >&2
        exit 1
    fi

    # كشف CRLF
    if grep -q $'\r' "$HTML_FILE" 2>/dev/null; then
        printf "%s⚠ الملف بأسطر Windows (CRLF) - قد يفشل الإدراج/الحذف%s\n" "$YELLOW" "$NC"
        printf "  ${DIM}الحل: tr -d '\\\\r' < index.html > t && mv t index.html${NC}\n\n"
    fi

    while true; do
        echo "${BOLD}القائمة:${NC}"
        echo "  1) إضافة تطبيق"
        echo "  2) حذف تطبيق"
        echo "  3) عرض التطبيقات"
        echo "  4) رفع إلى GitHub"
        echo "  5) خروج"
        echo ""
        printf "%s➤%s اختر: " "$CYAN" "$NC" >&2
        local choice; IFS= read -r choice || { echo; exit 0; }
        echo ""

        case "$choice" in
            1) add_app ;;
            2) delete_app ;;
            3)
                for s in ios android tv; do
                    echo "${BOLD}── $s ($(count_apps $s)) ──${NC}"
                    local out; out=$(list_apps "$s")
                    if [ -n "$out" ]; then echo "$out"; else echo "  ${DIM}لا يوجد${NC}"; fi
                    echo ""
                done
                ;;
            4) git_push ;;
            5|q|Q|exit) break ;;
            *) printf "%s✗ خيار غير معروف%s\n" "$RED" "$NC" >&2 ;;
        esac
    done

    if [ -d ".git" ] && [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        echo ""
        if confirm "توجد تغييرات غير مرفوعة. رفعها الآن إلى GitHub؟" "y"; then
            git_push
        fi
    fi

    echo ""
    printf "%s✓ شكراً لاستخدامك iosdump Panel%s\n\n" "$GREEN" "$NC"
}

main "$@"