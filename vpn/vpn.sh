#!/usr/bin/env bash
# 무료 지역 변경 VPN (VPN Gate 공개 서버 사용, 가입·결제 없음)
#
#   bash vpn/vpn.sh setup            최초 1회: 필요한 도구 설치 + 다운로드 폴더 권한
#   bash vpn/vpn.sh countries        지금 쓸 수 있는 나라 목록
#   bash vpn/vpn.sh get japan        일본 서버 중 가장 좋은 1개 → Download/vpn-JP-1.ovpn
#   bash vpn/vpn.sh get us 3         미국 서버 상위 3개 (하나가 안 되면 다음 것 사용)
#   bash vpn/vpn.sh import 파일      브라우저로 받은 서버 목록 파일 사용
#
# 받은 .ovpn 파일은 'OpenVPN for Android' 앱에서 가져오기 하면 됩니다.
set -euo pipefail

# 차례로 시도할 주소 (RVPN_LIST_URL 로 직접 지정 가능)
read -ra LIST_URLS <<<"${RVPN_LIST_URL:-https://www.vpngate.net/api/iphone/ http://www.vpngate.net/api/iphone/ https://vpngate.net/api/iphone/ http://vpngate.net/api/iphone/}"
CACHE="${RVPN_CACHE:-$HOME/.cache/region-vpn/servers.csv}"
OUT_DIR="${RVPN_OUT_DIR:-$HOME/region-vpn}"
DL_DIR="${RVPN_DL_DIR:-$HOME/storage/downloads}"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m오류:\033[0m %s\n' "$*" >&2; exit 1; }

# 나라 이름 → 2글자 국가 코드 (코드를 직접 넣어도 됨: JP, US, KR ...)
country_code() {
  case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
    korea|seoul)                 echo KR ;;
    japan|tokyo|osaka)           echo JP ;;
    usa|us|america|la|newyork)   echo US ;;
    china)                       echo CN ;;
    taiwan)                      echo TW ;;
    hongkong|hk)                 echo HK ;;
    thailand)                    echo TH ;;
    vietnam)                     echo VN ;;
    singapore)                   echo SG ;;
    indonesia)                   echo ID ;;
    philippines)                 echo PH ;;
    india)                       echo IN ;;
    russia)                      echo RU ;;
    uk|england|london)           echo GB ;;
    germany)                     echo DE ;;
    france)                      echo FR ;;
    canada)                      echo CA ;;
    australia)                   echo AU ;;
    brazil)                      echo BR ;;
    *)                           printf '%s\n' "$1" | tr 'a-z' 'A-Z' ;;
  esac
}

# 서버 목록 받기 (10분간 캐시)
fetch_list() {
  if [[ -f "$CACHE" && -n "$(find "$CACHE" -mmin -10 2>/dev/null)" ]]; then return; fi
  # 브라우저로 받아 둔 목록이 다운로드 폴더에 있으면 그걸 사용
  local f
  for f in "$DL_DIR"/iphone* "$DL_DIR"/vpngate*.csv; do
    [[ -f "$f" ]] && grep -q '^\*vpn_servers' "$f" 2>/dev/null && { cmd_import "$f"; return; }
  done
  command -v curl >/dev/null || die "curl 이 없습니다. 먼저 'bash vpn/vpn.sh setup' 을 실행하세요."
  mkdir -p "$(dirname "$CACHE")"
  local url
  for url in "${LIST_URLS[@]}"; do
    say "무료 서버 목록 받는 중 ... ($url)"
    if curl -fsSL -4 --connect-timeout 15 -m 120 --retry 1 "$url" 2>/dev/null | tr -d '\r' > "$CACHE.tmp" \
       && grep -q '^\*vpn_servers' "$CACHE.tmp"; then
      mv "$CACHE.tmp" "$CACHE"; return
    fi
    warn "실패. 다음 주소로 다시 시도합니다."
  done
  rm -f -- "${CACHE:?}.tmp"
  cat >&2 <<'MSG'

서버 목록 사이트(vpngate.net)에 연결되지 않습니다. 지금 쓰는 네트워크가 막고 있을 수 있어요.
  1) 와이파이 ↔ 모바일 데이터를 바꿔서 다시: bash vpn/vpn.sh get japan
  2) 그래도 안 되면 폰 브라우저(크롬)로 아래 주소를 열어 '다운로드'로 저장한 뒤 다시 get 하세요:
       https://www.vpngate.net/api/iphone/
     (크롬: 주소 열기 → ⋮ → 다운로드 버튼. 다운로드 폴더에 저장되면 자동으로 찾아 씁니다)
MSG
  exit 1
}

cmd_import() {  # 브라우저로 받은 목록 파일 등록
  local f=${1:-}; [[ -f "$f" ]] || die "파일을 찾을 수 없습니다: $f"
  grep -q '^\*vpn_servers' "$f" || die "VPN Gate 서버 목록 파일이 아닙니다: $f"
  mkdir -p "$(dirname "$CACHE")"
  tr -d '\r' < "$f" > "$CACHE"
  say "목록 파일 사용: $f"
}

# CSV 열: 1 HostName, 2 IP, 3 Score, 4 Ping, 5 Speed, 6 CountryLong, 7 CountryShort, ... 마지막 = OpenVPN 설정(base64)
servers() { awk -F, '!/^[*#]/ && NF >= 15 && $NF != ""' "$CACHE"; }

cmd_setup() {
  if [[ "${PREFIX:-}" == *com.termux* ]]; then
    pkg install -y curl coreutils findutils gawk
    [[ -d "$HOME/storage" ]] || termux-setup-storage || true
  fi
  say "준비 완료. 플레이스토어에서 'OpenVPN for Android' 앱을 설치하세요."
  say "예: bash vpn/vpn.sh get japan"
}

cmd_countries() {
  fetch_list
  printf '코드\t서버수\t나라\n'
  servers | awk -F, '{n[$7]++; name[$7]=$6} END {for (c in n) printf "%s\t%d\t%s\n", c, n[c], name[c]}' \
    | sort -t$'\t' -k2,2nr
}

cmd_get() {
  local want=${1:-} count=${2:-1}
  [[ -n "$want" ]] || die "나라를 입력하세요. 예: bash vpn/vpn.sh get japan"
  [[ "$count" =~ ^[0-9]+$ && "$count" -ge 1 ]] || die "개수는 1 이상의 숫자여야 합니다."
  local cc; cc=$(country_code "$want")
  fetch_list

  local picked
  picked=$(servers | awk -F, -v cc="$cc" '$7 == cc' | sort -t, -k3,3nr | head -n "$count")
  [[ -n "$picked" ]] || die "'$cc' 서버가 지금은 없습니다. 'bash vpn/vpn.sh countries' 로 가능한 나라를 확인하세요."

  mkdir -p "$OUT_DIR"
  local i=0 host ip ping speed country cfg file
  while IFS= read -r line; do
    i=$((i + 1))
    IFS=, read -r host ip _ ping speed country _ <<<"$line"
    cfg=${line##*,}
    file="$OUT_DIR/vpn-$cc-$i.ovpn"
    {
      printf '%s' "$cfg" | base64 -d 2>/dev/null | tr -d '\r'
      # 최신 OpenVPN 앱에서도 VPN Gate 서버의 예전 암호 방식을 허용
      printf '\ndata-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-128-CBC\n'
      printf 'data-ciphers-fallback AES-128-CBC\n'
    } > "$file"
    grep -q '^remote ' "$file" || { warn "$host 설정이 깨져 있어 건너뜁니다."; rm -f -- "$file"; i=$((i - 1)); continue; }
    if [[ -d "$DL_DIR" ]]; then cp "$file" "$DL_DIR/"; fi
    say "$i) $country  $ip  (핑 ${ping}ms, 속도 $((speed / 1000000))Mbps) → Download/vpn-$cc-$i.ovpn"
  done <<<"$picked"
  [[ $i -gt 0 ]] || die "쓸 수 있는 설정 파일이 없습니다. 다른 나라를 시도해 보세요."

  [[ -d "$DL_DIR" ]] || warn "다운로드 폴더 권한이 없어 $OUT_DIR 에만 저장했습니다. 'termux-setup-storage' 실행 후 다시 해보세요."
  echo
  echo "  [폰에 연결하는 법]"
  echo "  OpenVPN for Android 앱 → 오른쪽 위 가져오기(📥) → Download/vpn-$cc-1.ovpn → 눌러서 연결"
  echo "  사용자 이름/비밀번호를 물으면: vpn / vpn"
  echo "  연결이 안 되면 다음 번호 파일(vpn-$cc-2.ovpn ...)을 쓰거나 다시 get 하세요."
}

case "${1:-help}" in
  setup)     cmd_setup ;;
  countries) cmd_countries ;;
  import)    cmd_import "${2:-}" ;;
  get)       cmd_get "${2:-}" "${3:-1}" ;;
  *)         sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
