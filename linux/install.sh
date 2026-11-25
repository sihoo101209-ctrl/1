#!/usr/bin/env bash
# 안드로이드 폰(Termux)에 리눅스(Ubuntu 등)를 설치합니다. 루팅 불필요.
#
# 사용법 (Termux 안에서):
#   bash linux/install.sh              # Ubuntu 설치 (터미널만)
#   bash linux/install.sh --desktop    # Ubuntu + XFCE 데스크톱 (Termux:X11 앱 필요)
#   bash linux/install.sh --distro=debian
set -euo pipefail

DISTRO="ubuntu"
DESKTOP=0

usage() {
  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    --desktop) DESKTOP=1 ;;
    --distro=*) DISTRO="${arg#*=}" ;;
    -h|--help) usage ;;
    *) echo "알 수 없는 옵션: $arg" >&2; exit 1 ;;
  esac
done

say() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31m오류: %s\033[0m\n' "$*" >&2; exit 1; }

[[ "${PREFIX:-}" == *com.termux* ]] || die "Termux 안에서 실행해 주세요. (F-Droid 또는 GitHub 버전 Termux 권장)"

say "Termux 패키지 업데이트"
pkg update -y
pkg upgrade -y -o Dpkg::Options::="--force-confnew"
pkg install -y proot-distro

if proot-distro login "$DISTRO" -- true >/dev/null 2>&1; then
  say "$DISTRO 이(가) 이미 설치되어 있습니다. 설치 단계를 건너뜁니다."
else
  say "$DISTRO 설치 (몇 분 걸립니다)"
  proot-distro install "$DISTRO"
fi

say "$DISTRO 기본 패키지 설치"
proot-distro login "$DISTRO" -- bash -c '
  set -e
  if command -v apt-get >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get upgrade -y
    apt-get install -y sudo nano vim curl wget git ca-certificates locales tzdata
    sed -i "s/^# *ko_KR.UTF-8/ko_KR.UTF-8/" /etc/locale.gen 2>/dev/null || true
    locale-gen ko_KR.UTF-8 >/dev/null 2>&1 || true
  else
    echo "apt 기반이 아닌 배포판이라 기본 패키지 설치를 건너뜁니다."
  fi
'

# 바로가기 명령: `linux`
cat > "$PREFIX/bin/linux" <<SH
#!/usr/bin/env bash
exec proot-distro login "$DISTRO" --shared-tmp "\$@"
SH
chmod +x "$PREFIX/bin/linux"

if [[ $DESKTOP -eq 1 ]]; then
  say "데스크톱(XFCE) 설치"
  pkg install -y x11-repo
  pkg install -y termux-x11-nightly pulseaudio
  proot-distro login "$DISTRO" -- bash -c '
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y xfce4 xfce4-terminal dbus-x11 fonts-noto-cjk
  '

  cat > "$PREFIX/bin/linux-desktop" <<SH
#!/usr/bin/env bash
# Termux:X11 앱 화면에 XFCE 데스크톱을 띄웁니다.
pkill -f termux-x11 >/dev/null 2>&1 || true
pulseaudio --start --exit-idle-time=-1 >/dev/null 2>&1 || true
termux-x11 :0 >/dev/null 2>&1 &
sleep 3
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity >/dev/null 2>&1 || true
exec proot-distro login "$DISTRO" --shared-tmp -- bash -c 'export DISPLAY=:0 PULSE_SERVER=127.0.0.1; dbus-launch --exit-with-session startxfce4'
SH
  chmod +x "$PREFIX/bin/linux-desktop"
fi

say "완료!"
echo "  linux            → $DISTRO 터미널 접속 (나가려면 exit)"
[[ $DESKTOP -eq 1 ]] && echo "  linux-desktop    → 데스크톱 실행 (Termux:X11 앱이 설치돼 있어야 함)"
echo "  proot-distro remove $DISTRO   → 삭제"
