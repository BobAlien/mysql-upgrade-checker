#!/usr/bin/env bash
# precheck.sh - MySQL 8.0 -> 8.4 pre-upgrade checker
#
# Usage: precheck.sh [path/to/mysqld]
#
# Exit codes: 0 = OK, 1 = NO-GO (blocking issue), 2 = usage / environment error

set -u

MYSQLD="${1:-mysqld}"

# version_ge A B -> true if A >= B (version sort)
version_ge() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]; }

if ! command -v "$MYSQLD" >/dev/null 2>&1; then
    echo "ERROR: mysqld binary not found: $MYSQLD" >&2
    exit 2
fi

# --- 1. Host glibc -----------------------------------------------------------
glibc_version="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}')"
[ -z "$glibc_version" ] && glibc_version="$(ldd --version 2>&1 | head -n1 | grep -o '[0-9]\+\.[0-9]\+$')"
if [ -z "$glibc_version" ]; then
    echo "ERROR: cannot detect glibc version" >&2
    exit 2
fi
echo "mysqld binary : $MYSQLD"
echo "host glibc    : $glibc_version"

# Highest GLIBCXX symbol version provided by the host libstdc++ (empty if not found)
cxx_lib="$(ldconfig -p 2>/dev/null | awk '/libstdc\+\+\.so\.6/ {print $NF; exit}')"
[ -z "$cxx_lib" ] && for f in /usr/lib64/libstdc++.so.6 /usr/lib/x86_64-linux-gnu/libstdc++.so.6 /usr/lib/libstdc++.so.6; do
    [ -r "$f" ] && cxx_lib="$f" && break
done
host_cxx=""
[ -r "$cxx_lib" ] && host_cxx="$(grep -a -o 'GLIBCXX_[0-9.]*' "$cxx_lib" | sed 's/GLIBCXX_//' | sort -Vu | tail -n1)"

# gcc_for_glibcxx X -> first GCC release shipping GLIBCXX_X (approximate: nearest known level at or below X)
gcc_for_glibcxx() {
    local v="$1" best="?" k
    for k in 3.4.19:4.8 3.4.20:4.9 3.4.21:5.1 3.4.22:6.1 3.4.23:7.1 3.4.24:7.2 3.4.25:8.1 3.4.26:9.1 3.4.27:10.1 3.4.28:11.1 3.4.29:12.1 3.4.30:13.1 3.4.32:14.1; do
        version_ge "$v" "${k%%:*}" && best="${k##*:}"
    done
    echo "$best"
}

# --- 2. Binary version -------------------------------------------------------
version_line="$("$MYSQLD" --version 2>&1)"
rc=$?
mysql_version="$(printf '%s\n' "$version_line" | sed -n 's/.*Ver \([0-9][0-9.]*\).*/\1/p' | head -n1)"

if [ $rc -ne 0 ] || [ -z "$mysql_version" ]; then
    # The binary cannot run here: summarize the missing libraries instead of dumping the loader errors
    need_glibc="$(printf '%s\n' "$version_line" | grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -Vu | tail -n1)"
    need_cxx="$(printf '%s\n' "$version_line" | grep -o 'GLIBCXX_[0-9.]*' | sed 's/GLIBCXX_//' | sort -Vu | tail -n1)"
    # Best effort: version from the install directory name (mysql-8.4.11-linux-...)
    path_version="$(printf '%s\n' "$MYSQLD" | sed -n 's/.*mysql-\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p' | head -n1)"
    [ -n "$path_version" ] && echo "mysqld version: $path_version (from path)"
    if [ -n "$need_glibc" ] || [ -n "$need_cxx" ]; then
        echo "[FAIL]  mysqld cannot run on this host"
        [ -n "$need_glibc" ] && echo "        requires glibc >= $need_glibc (host: $glibc_version)"
        if [ -n "$need_cxx" ]; then
            echo "        requires libstdc++ GLIBCXX_$need_cxx (GCC >= $(gcc_for_glibcxx "$need_cxx")), host has GLIBCXX_${host_cxx:-unknown}${host_cxx:+ (GCC $(gcc_for_glibcxx "$host_cxx"))}"
        fi
        exit 1
    fi
    echo "ERROR: cannot get version from: $(printf '%s\n' "$version_line" | head -n1)" >&2
    exit 2
fi
echo "mysqld version: $mysql_version"

# --- 3. Verdict --------------------------------------------------------------
# Highest MySQL version supported by the glibc (LATEST = no limit)
if ! version_ge "$glibc_version" 2.17; then
    MYSQL_MAX=8.0.40
elif ! version_ge "$glibc_version" 2.28; then
    MYSQL_MAX=8.4.10
else
    MYSQL_MAX=LATEST
fi
echo "max MySQL     : $MYSQL_MAX"

if [ "$MYSQL_MAX" = "LATEST" ] || version_ge "$MYSQL_MAX" "$mysql_version"; then
    echo "[OK]    MySQL $mysql_version is supported on glibc $glibc_version"
    exit 0
fi
echo "[FAIL]  MySQL $mysql_version > $MYSQL_MAX: target binaries may not run on glibc $glibc_version"
exit 1