#!/usr/bin/env bash
# ============================================================
#   iosdump Panel v2.2
#   - إصلاح مشكلة ظهور ? عند الكتابة (locale/stty)
#   - رفع تلقائي إلى GitHub بعد إضافة كل تطبيق
#   - متوافق مع iOS NewTerm + Linux + macOS
# ============================================================

# ---------- إصلاح مشكلة ? (locale UTF-8) ----------
export LANG="${LANG:-en_US.UTF-8}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export LC_CTYPE="${LC_CTYPE:-en_US.UTF-8}"
export TERM="${TERM:-xterm-256color}"

# fallback إذا لم تكن en_US.UTF-8 متوفرة
if ! locale -a 2>/dev/null | grep -qi 'utf'; then
    for loc in C.UTF-8 C.utf8 en_US.utf8; do
        if locale -a 2>/dev/null | grep -qx "$loc"; then
            export LANG="$loc" LC_ALL="$loc" LC_CTYPE="$loc"
            break
        fi
    done
fi

# ---------- إصلاح إعدادات الطرفية (NewTerm) ----------
if command -v stty >/dev/null 2>&1; then
    stty sane 2>/dev/null || true
    stty iutf8 2>/dev/null || true
    stty echo icanon 2>/dev/null || true
fi

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

# ---------- الإعدادات ----------
AUTO_PUSH=true           # رفع تلقائي بعد كل إضافة
AUTO_PUSH_MSG_PREFIX="Add"  # بادئة رسالة الـ commit

# ---------- المسارات ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
cd "$SCRIPT_DIR" || { printf "%s✗ تعذر الدخول إلى %s%s\n" "$RED" "$SCRIPT_DIR" "$NC"; exit 1; }
HTML_FILE="index.html"
ICONS_DIR="icons"
TMP_FILE=""

# ---------- كشف البيئة ----------
is_ios() { [ -d "/var/mobile" ] && [ "$(uname -s 2>/dev/null)" = "Darwin" ]; }

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
hr() { printf "%s\n" "${DIM}──────────────────────────────────────────────${NC}"; }

count_apps() {
    local upper; upper=$(echo "$1" | tr '[:lower:]' '[:upper:]')
    awk -v ms="<!-- ${upper}_APPS_START -->" -v me="<!-- ${upper}_APPS_END -->" '
        index($0, ms) { in_s = 1; next }
        index($0, me) { in_s = 0; next }
        in_s && /class="app-item"/ { c++ }
        END { print c + 0 }
    ' "$HTML_FILE" 2>/dev/null
}

# ---------- إدخال ----------
# محاولة readline أولاً، ثم read عادي
ask() {
    local prompt="$1" default="${2:-}" value="" p=""
    if [ -n "$default" ]; then
        p=$(printf "%s➤%s %s %s[%s]%s: " "$CYAN" "$NC" "$prompt" "$DIM" "$default" "$NC")
    else
        p=$(printf "%s➤%s %s: " "$CYAN" "$NC" "$prompt")
    fi

    # محاولة readline (يحل مشاكل many terminals)
    if printf '%s' "$p" >&2 && read -e -r value 2>/dev/null; then
        :
    else
        printf '%s' "$p" >&2
        if ! IFS= read -r value; then
            printf "\n"; exit 0
        fi
    fi

    # إزالة أي CR محتملة
    value="${value%$'\r'}"

    # عرض ما تم إدخاله (يساعد على اكتشاف مشكلة ?)
    if [ -n "$value" ] && is_ios; then
        printf "  ${DIM}↳ تم استلام: [%s]${NC}\n" "$value" >&2
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
        # LC_ALL=C لضمان تحويل آمن للأحرف غير اللاتينية
        safe=$(printf '%s' "$name" | LC_ALL=C tr -cs 'a-zA-Z0-9._-' '-' | LC_ALL=C tr 'A-Z' 'a-z' | sed 's/^-*//; s/-*$//')
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
    local section="$1" entry="$2" upper ms me entry_file
    upper=$(echo "$section" | tr '[:lower:]' '[:upper:]')
    ms="<!-- ${upper}_APPS_START -->"; me="<!-- ${upper}_APPS_END -->"

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
    rm -f "$entry_file"; return 0
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
    if [ "$before" -eq 0 ]; then printf "%s⚠ لا توجد تطبيقات%s\n" "$YELLOW" "$NC"; return 1; fi

    echo ""; echo "${BOLD}التطبيقات الحالية:${NC}"; list_apps "$section"; echo ""

    local num; num=$(ask_required "رقم التطبيق للحذف")
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
            if (depth == 0 && $0 ~ /class="app-item"/) { idx++; if (idx == target) skip=1 }
            depth += n_o - n_c
            if (skip) { if (depth == 0) skip=0; next }
            print
        }
    ' "$HTML_FILE" > "$TMP_FILE" || return 1

    local after; after=$(count_apps "$section")
    if [ "$after" -ge "$before" ]; then
        rm -f "$TMP_FILE"; TMP_FILE=""
        printf "%s✗ فشل الحذف%s\n" "$RED" "$NC" >&2; return 1
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

    # ---- معاينة قبل الإدراج ----
    echo ""
    echo "${BOLD}── معاينة ──${NC}"
    echo "  ${DIM}الاسم:${NC}     $name"
    echo "  ${DIM}الإصدار:${NC}  $version"
    echo "  ${DIM}الوصف:${NC}    $desc"
    echo "  ${DIM}الأيقونة:${NC} $icon"
    echo "  ${DIM}الرابط:${NC}   $link"
    echo "  ${DIM}القسم:${NC}    $section"
    echo ""
    if ! confirm "هل البيانات صحيحة؟" "y"; then
        echo "${DIM}تم الإلغاء${NC}"; return 0
    fi

    backup_html
    local icon_path; icon_path=$(handle_icon "$icon" "$section" "$name")
    [ -z "$icon_path" ] && icon_path="https://raw.githubusercontent.com/iosdumpzzz/MyIcon/refs/heads/main/Apps/default.png"

    local entry; entry=$(generate_entry "$name" "$version" "$desc" "$icon_path" "$link")

    if insert_entry "$section" "$entry"; then
        printf "%s✓%s أُضيف ${BOLD}%s${NC} إلى ${BOLD}%s${NC}\n" "$GREEN" "$NC" "$name" "$section"

        # ---- رفع تلقائي إلى GitHub ----
        if [ "$AUTO_PUSH" = "true" ]; then
            echo ""
            echo "${CYAN}${BOLD}── الرفع التلقائي إلى GitHub ──${NC}"
            git_push "${AUTO_PUSH_MSG_PREFIX} ${name}"
        else
            echo ""
            echo "${DIM}ⓘ الرفع التلقائي معطّل. استخدم الخيار 4 من القائمة الرئيسية للرفع يدوياً.${NC}"
        fi
    else
        printf "%s✗ فشلت الإضافة%s\n" "$RED" "$NC" >&2
        return 1
    fi
}

# ---------- رفع إلى GitHub ----------
git_push() {
    local auto_msg="${1:-}"
    echo ""
    if [ -z "$auto_msg" ]; then
        echo "${BOLD}=== رفع التغييرات إلى GitHub ===${NC}"
    fi
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
        if [ -z "$auto_msg" ]; then
            confirm "هل تريد تهيئته الآن؟" "y" || return 1
            local remote; remote=$(ask_required "رابط المستودع (https://github.com/user/repo.git)")
            git init -q
            git branch -M main 2>/dev/null || true
            git remote add origin "$remote" 2>/dev/null || true
            printf "%s✓%s تمت التهيئة\n" "$GREEN" "$NC"
        else
            printf "%s✗ لا يمكن الرفع التلقائي - المستودع غير مهيأ%s\n" "$RED" "$NC" >&2
            echo "${DIM}  عطّل الرفع التلقائي أو استخدم الخيار 4 للتهيئة اليدوية.${NC}"
            return 1
        fi
    fi

    local msg
    if [ -n "$auto_msg" ]; then
        msg="$auto_msg"
        echo "${DIM}رسالة commit: $msg${NC}"
    else
        msg=$(ask "رسالة الـ commit" "Init")
        [ -z "$msg" ] && msg="Init"
    fi

    echo ""
    echo "${DIM}\$ git add --all${NC}"
    git add --all

    local has_changes=0
    if git rev-parse HEAD >/dev/null 2>&1; then
        git diff --cached --quiet || has_changes=1
    else
        has_changes=1
    fi

    if [ "$has_changes" -eq 1 ]; then
        echo "${DIM}\$ git commit -m \"$msg\"${NC}"
        git commit -m "$msg"
    else
        echo "${YELLOW}⚠ لا توجد تغييرات جديدة${NC}"
    fi

    echo ""
    echo "${DIM}\$ git push${NC}"
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

# ---------- الإعدادات ----------
settings_menu() {
    while true; do
        echo ""
        echo "${BOLD}=== الإعدادات ===${NC}"
        echo ""
        if [ "$AUTO_PUSH" = "true" ]; then
            echo "  1) الرفع التلقائي: ${GREEN}مفعّل${NC}"
        else
            echo "  1) الرفع التلقائي: ${RED}معطّل${NC}"
        fi
        echo "  2) بادئة رسالة commit: ${CYAN}$AUTO_PUSH_MSG_PREFIX${NC}"
        echo "  3) رجوع"
        echo ""
        printf "%s➤%s اختر: " "$CYAN" "$NC" >&2
        local c; IFS= read -r c || { echo; return; }
        case "$c" in
            1)
                if [ "$AUTO_PUSH" = "true" ]; then AUTO_PUSH=false; else AUTO_PUSH=true; fi
                ;;
            2)
                AUTO_PUSH_MSG_PREFIX=$(ask "بادئة الرسالة" "$AUTO_PUSH_MSG_PREFIX")
                ;;
            3|*) return ;;
        esac
    done
}

# ---------- تشخيص المدخلات ----------
diagnose_input() {
    echo ""
    echo "${BOLD}=== تشخيص المدخلات (لحل مشكلة ?) ===${NC}"
    echo ""
    echo "  ${DIM}LANG=${NC}$LANG"
    echo "  ${DIM}LC_ALL=${NC}$LC_ALL"
    echo "  ${DIM}LC_CTYPE=${NC}$LC_CTYPE"
    echo "  ${DIM}TERM=${NC}$TERM"
    echo ""
    echo "  اللغات المتوفرة (UTF-8):"
    locale -a 2>/dev/null | grep -i utf | head -5 | sed 's/^/    /'
    echo ""
    local test
    test=$(ask "اكتب جملة تجريبية (مسافات + عربي)")
    echo ""
    echo "  ${BOLD}ما تم استلامه:${NC} [$test]"
    echo "  ${BOLD}عدد الأحرف:${NC}  ${#test}"
    echo "  ${BOLD}Hex dump:${NC}"
    printf '%s' "$test" | od -An -tx1c | head -3 | sed 's/^/    /'
    echo ""
    echo "  ${DIM}إذا ظهر ? هنا أثناء الكتابة لكن Hex dump صحيح → مشكلة عرض فقط (حل: NewTerm Settings → Font)${NC}"
    echo "  ${DIM}إذا ظهر ? في Hex dump → مشكلة إدخال (حل: استخدم لوحة مفاتيح إنجليزية أو hardware keyboard)${NC}"
    echo ""
    confirm "هل تريد إعادة الاختبار؟" "n" && diagnose_input
}

# ---------- شعار ----------
banner() {
    echo ""
    printf "%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n" "$CYAN$BOLD" "$NC"
    printf "%s   🚀 iosdump Panel v2.2%s\n" "$MAGENTA$BOLD" "$NC"
    printf "%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n" "$CYAN$BOLD" "$NC"
    if is_ios; then printf "  ${DIM}البيئة: iOS (NewTerm)${NC}\n"; fi
    printf "  ${DIM}iOS:${NC} ${BOLD}%s${NC}   ${DIM}Android:${NC} ${BOLD}%s${NC}   ${DIM}TV:${NC} ${BOLD}%s${NC}\n" \
        "$(count_apps ios)" "$(count_apps android)" "$(count_apps tv)"
    if [ "$AUTO_PUSH" = "true" ]; then
        printf "  ${DIM}الرفع التلقائي:${NC} ${GREEN}مفعّل${NC}\n"
    else
        printf "  ${DIM}الرفع التلقائي:${NC} ${RED}معطّل${NC}\n"
    fi
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

    if grep -q $'\r' "$HTML_FILE" 2>/dev/null; then
        printf "%s⚠ الملف بأسطر Windows (CRLF)%s\n" "$YELLOW" "$NC"
        printf "  ${DIM}الحل: tr -d '\\\\r' < index.html > t && mv t index.html${NC}\n\n"
    fi

    while true; do
        echo "${BOLD}القائمة:${NC}"
        echo "  1) إضافة تطبيق"
        echo "  2) حذف تطبيق"
        echo "  3) عرض التطبيقات"
        echo "  4) رفع يدوي إلى GitHub"
        echo "  5) الإعدادات"
        echo "  6) تشخيص المدخلات (حل مشكلة ?)"
        echo "  7) خروج"
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
            5) settings_menu; banner ;;
            6) diagnose_input ;;
            7|q|Q|exit) break ;;
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