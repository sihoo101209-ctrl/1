#!/usr/bin/env bash
# region-vpn: 원하는 나라에 내 전용 WireGuard VPN 서버를 만들고 지역을 바꿉니다.
#
#   bash vpn/vpn.sh setup              최초 1회: 필요한 도구 설치 + Vultr API 키 저장
#   bash vpn/vpn.sh regions            사용 가능한 지역 목록
#   bash vpn/vpn.sh up tokyo           도쿄에 VPN 서버 생성 → 설정 파일(.conf) 생성
#   bash vpn/vpn.sh switch la          LA 서버를 만든 뒤, 기존 VPN 서버는 삭제 (지역 바꾸기)
#   bash vpn/vpn.sh list               현재 켜져 있는(요금이 나가는) VPN 서버 목록
#   bash vpn/vpn.sh down tokyo         도쿄 서버 삭제 (요금 중단)
#   bash vpn/vpn.sh down all           모든 VPN 서버 삭제
#   bash vpn/vpn.sh manual root@1.2.3.4 [이름]
#                                      이미 가진 리눅스 서버(오라클 무료 등)에 SSH로 설치
set -euo pipefail

API="${RVPN_API_BASE:-https://api.vultr.com/v2}"
CONF_DIR="${RVPN_CONF_DIR:-$HOME/.config/region-vpn}"
OUT_DIR="${RVPN_OUT_DIR:-$HOME/region-vpn}"
DL_DIR="${RVPN_DL_DIR:-$HOME/storage/downloads}"
TAG="region-vpn"
WG_PORT=51820

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m오류:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- 지역 별칭 → Vultr 지역 코드 ----------
region_code() {
  case "$1" in
    seoul|korea|kr)              echo icn ;;
    tokyo|japan|jp)              echo nrt ;;
    osaka)                       echo itm ;;
    singapore|sg)                echo sgp ;;
    mumbai|india|in)             echo bom ;;
    delhi)                       echo del ;;
    sydney|australia|au)         echo syd ;;
    melbourne)                   echo mel ;;
    la|losangeles|us)            echo lax ;;
    newyork|ny|newjersey)        echo ewr ;;
    seattle)                     echo sea ;;
    siliconvalley|sf)            echo sjc ;;
    chicago)                     echo ord ;;
    dallas)                      echo dfw ;;
    miami)                       echo mia ;;
    atlanta)                     echo atl ;;
    honolulu|hawaii)             echo hnl ;;
    toronto|canada|ca)           echo yto ;;
    mexico|mx)                   echo mex ;;
    saopaulo|brazil|br)          echo sao ;;
    santiago|chile)              echo scl ;;
    london|uk|gb)                echo lhr ;;
    frankfurt|germany|de)        echo fra ;;
    paris|france|fr)             echo cdg ;;
    amsterdam|netherlands|nl)    echo ams ;;
    madrid|spain|es)             echo mad ;;
    stockholm|sweden|se)         echo sto ;;
    warsaw|poland|pl)            echo waw ;;
    telaviv|israel|il)           echo tlv ;;
    johannesburg|southafrica|za) echo jnb ;;
    *)                           echo "$1" ;;  # Vultr 코드(nrt 등)를 직접 넣어도 됨
  esac
}

# WireGuard 앱 터널 이름은 15자 이하 → "rvpn-" + 최대 10자
tunnel_name() {
  local n
  n=$(printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9')
  [[ -n "$n" ]] || die "이름이 비어 있습니다."
  echo "rvpn-${n:0:10}"
}

# ---------- 설정 ----------
load_key() {
  [[ -n "${VULTR_API_KEY:-}" ]] && return
  # shellcheck disable=SC1091
  [[ -f "$CONF_DIR/config" ]] && . "$CONF_DIR/config"
  [[ -n "${VULTR_API_KEY:-}" ]] || die "API 키가 없습니다. 먼저 'bash vpn/vpn.sh setup' 을 실행하세요."
}

need() { command -v "$1" >/dev/null 2>&1 || die "'$1' 이(가) 없습니다. 'bash vpn/vpn.sh setup' 을 먼저 실행하세요."; }

# ---------- Vultr API ----------
# api METHOD PATH [JSON]  → 본문 출력, HTTP 오류면 종료
api() {
  local method=$1 path=$2 body=${3:-} resp code
  local args=(-sS -X "$method" -H "Authorization: Bearer $VULTR_API_KEY" -w $'\n%{http_code}')
  [[ -n "$body" ]] && args+=(-H "Content-Type: application/json" --data "$body")
  resp=$(curl "${args[@]}" "$API$path") || die "네트워크 오류 ($method $path)"
  code=${resp##*$'\n'}
  resp=${resp%$'\n'*}
  if [[ "$code" -ge 400 ]]; then
    die "Vultr API 오류 $code ($method $path): $(jq -r '.error // .' <<<"$resp" 2>/dev/null || echo "$resp")"
  fi
  printf '%s' "$resp"
}

# ---------- WireGuard 키 ----------
genkey_pair() {  # 출력: "개인키 공개키"
  local priv pub
  if command -v wg >/dev/null 2>&1; then
    priv=$(wg genkey); pub=$(printf '%s' "$priv" | wg pubkey)
  else
    # wireguard-tools가 없으면 openssl로 X25519 키 생성 (wg 와 동일한 형식)
    local pem; pem=$(openssl genpkey -algorithm X25519)
    priv=$(printf '%s\n' "$pem" | openssl pkey -outform DER | tail -c 32 | base64)
    pub=$(printf '%s\n' "$pem" | openssl pkey -pubout -outform DER | tail -c 32 | base64)
  fi
  echo "$priv $pub"
}

# ---------- 서버에서 실행될 설치 스크립트 ----------
server_script() {  # $1=서버 개인키  $2=클라이언트 공개키
  cat <<SCRIPT
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
if command -v apt-get >/dev/null; then
  apt-get update -y && apt-get install -y wireguard iptables
elif command -v dnf >/dev/null; then
  dnf install -y epel-release || true
  dnf install -y wireguard-tools iptables
fi
IFACE=\$(ip -4 route show default | awk '{print \$5; exit}')
printf 'net.ipv4.ip_forward=1\n' > /etc/sysctl.d/99-region-vpn.conf
sysctl -p /etc/sysctl.d/99-region-vpn.conf
mkdir -p /etc/wireguard
umask 077
cat > /etc/wireguard/wg0.conf <<WG
[Interface]
Address = 10.66.66.1/24
ListenPort = $WG_PORT
PrivateKey = $1
PostUp = iptables -I INPUT 1 -p udp --dport $WG_PORT -j ACCEPT; iptables -I FORWARD 1 -i wg0 -j ACCEPT; iptables -I FORWARD 1 -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -s 10.66.66.0/24 -o \$IFACE -j MASQUERADE
PostDown = iptables -D INPUT -p udp --dport $WG_PORT -j ACCEPT; iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -s 10.66.66.0/24 -o \$IFACE -j MASQUERADE

[Peer]
PublicKey = $2
AllowedIPs = 10.66.66.2/32
WG
command -v ufw >/dev/null && ufw allow $WG_PORT/udp || true
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0
echo "region-vpn: WireGuard 준비 완료"
SCRIPT
}

# ---------- 클라이언트(폰) 설정 파일 ----------
write_client_conf() {  # $1=이름 $2=클라이언트 개인키 $3=서버 공개키 $4=서버 IP
  local name=$1 file
  mkdir -p "$OUT_DIR"
  file="$OUT_DIR/$name.conf"
  ( umask 077; cat > "$file" <<CONF
[Interface]
PrivateKey = $2
Address = 10.66.66.2/32
DNS = 1.1.1.1, 1.0.0.1
MTU = 1280

[Peer]
PublicKey = $3
Endpoint = $4:$WG_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
CONF
  )
  say "설정 파일: $file"

  # 폰의 '다운로드' 폴더에도 복사 → WireGuard 앱에서 '파일에서 가져오기'
  if [[ -d "$DL_DIR" ]]; then
    cp "$file" "$DL_DIR/$name.conf"
    say "다운로드 폴더에도 복사함: Download/$name.conf"
  fi

  echo
  echo "  [폰에 연결하는 법]"
  echo "  WireGuard 앱 → + → '파일 또는 압축파일에서 가져오기' → Download/$name.conf"
  echo "  (다른 기기로 연결하려면 아래 QR을 WireGuard 앱으로 스캔)"
  echo
  if command -v qrencode >/dev/null 2>&1; then
    qrencode -t ansiutf8 < "$file"
  fi
}

# ---------- 명령들 ----------
cmd_setup() {
  if [[ "${PREFIX:-}" == *com.termux* ]]; then
    pkg install -y curl jq openssl-tool qrencode openssh wireguard-tools \
      || pkg install -y curl jq openssl-tool qrencode openssh
    [[ -d "$HOME/storage" ]] || termux-setup-storage || true
  elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get install -y curl jq openssl qrencode openssh-client wireguard-tools
  fi

  echo
  echo "Vultr API 키가 필요합니다 (서버를 원하는 나라에 자동으로 만들기 위해)."
  echo "  1) https://www.vultr.com 가입 + 결제수단 등록"
  echo "  2) Account → API → Enable API → 키 복사"
  echo "     (Access Control 에서 'Allow all IPv4' 추가 또는 내 IP 허용)"
  echo
  local key
  read -rsp "API 키 붙여넣기 (입력은 화면에 안 보임, 건너뛰려면 Enter): " key; echo
  if [[ -n "$key" ]]; then
    mkdir -p "$CONF_DIR"
    ( umask 077; printf 'VULTR_API_KEY=%q\n' "$key" > "$CONF_DIR/config" )
    VULTR_API_KEY=$key
    api GET /account >/dev/null && say "API 키 확인 완료. 저장: $CONF_DIR/config"
  fi
  say "준비 완료. 예: bash vpn/vpn.sh up tokyo"
}

cmd_regions() {
  need curl; need jq
  echo "별칭 예시: seoul tokyo osaka singapore la newyork seattle toronto london"
  echo "           frankfurt paris amsterdam sydney mumbai saopaulo ... (또는 아래 코드 직접 사용)"
  echo
  curl -sS "$API/regions?per_page=500" \
    | jq -r '.regions[] | "\(.id)\t\(.country)\t\(.city)"' | sort -k2
}

vpn_labels() {  # 이 도구가 만든 서버들의 이름 목록
  api GET "/instances?per_page=500&tag=$TAG" \
    | jq -r --arg t "$TAG" '.instances[] | select(.tags|index($t)) | .label'
}

find_instance() {  # $1=label → 인스턴스 JSON (없으면 빈 문자열)
  api GET "/instances?per_page=500&label=$1" \
    | jq -c --arg l "$1" '[.instances[] | select(.label==$l)][0] // empty'
}

pick_plan() {  # $1=지역 코드
  local avail p
  avail=$(api GET "/regions/$1/availability" | jq -r '.available_plans[]?' 2>/dev/null || true)
  [[ -n "$avail" ]] || { echo vc2-1c-1gb; return; }
  for p in vc2-1c-0.5gb vc2-1c-1gb vhf-1c-1gb vc2-1c-2gb; do
    grep -qx "$p" <<<"$avail" && { echo "$p"; return; }
  done
  die "지역 '$1' 에 사용 가능한 저가 플랜이 없습니다."
}

pick_os() {
  local id
  id=$(api GET "/os?per_page=500" \
    | jq -r '[.os[] | select(.family=="ubuntu" and .arch=="x64" and (.name|test("24.04")))][0].id // empty')
  echo "${id:-2284}"
}

cmd_up() {
  local alias=${1:-}; [[ -n "$alias" ]] || die "지역을 입력하세요. 예: bash vpn/vpn.sh up tokyo"
  need curl; need jq; load_key
  local region name existing
  region=$(region_code "$alias")
  name=$(tunnel_name "$alias")

  existing=$(find_instance "$name")
  if [[ -n "$existing" ]]; then
    warn "'$name' 서버가 이미 있습니다 (IP $(jq -r .main_ip <<<"$existing"))."
    [[ -f "$OUT_DIR/$name.conf" ]] && say "기존 설정 파일: $OUT_DIR/$name.conf"
    return 0
  fi

  say "지역 확인: $alias → $region"
  local plan os spriv spub cpriv cpub user_data body id
  plan=$(pick_plan "$region")
  os=$(pick_os)

  read -r spriv spub <<<"$(genkey_pair)"
  read -r cpriv cpub <<<"$(genkey_pair)"
  user_data=$(server_script "$spriv" "$cpub" | base64 | tr -d '\n')

  say "서버 생성 중 ($region / $plan) ..."
  body=$(jq -nc --arg r "$region" --arg p "$plan" --argjson o "$os" --arg l "$name" \
               --arg t "$TAG" --arg u "$user_data" \
    '{region:$r, plan:$p, os_id:$o, label:$l, hostname:$l, tags:[$t], user_data:$u, backups:"disabled"}')
  id=$(api POST /instances "$body" | jq -r .instance.id)
  [[ -n "$id" && "$id" != null ]] || die "서버 생성 실패"

  local ip="" status="" inst _
  for _ in $(seq 1 90); do
    inst=$(api GET "/instances/$id")
    ip=$(jq -r .instance.main_ip <<<"$inst")
    status=$(jq -r .instance.status <<<"$inst")
    [[ "$status" == active && -n "$ip" && "$ip" != 0.0.0.0 ]] && break
    printf '.'; sleep "${RVPN_POLL_SEC:-5}"
  done
  echo
  [[ "$status" == active ]] || die "서버가 제시간에 켜지지 않았습니다. 'list'로 확인하거나 'down $alias'로 삭제하세요."

  say "서버 IP: $ip"
  write_client_conf "$name" "$cpriv" "$spub" "$ip"
  echo
  warn "서버 부팅 후 WireGuard 설치에 1~2분 더 걸립니다. 바로 안 되면 잠시 후 다시 연결하세요."
  warn "서버는 삭제할 때까지 시간당 요금이 나갑니다 → 다 쓰면: bash vpn/vpn.sh down $alias"
}

cmd_list() {
  need curl; need jq; load_key
  local out
  out=$(api GET "/instances?per_page=500&tag=$TAG" \
    | jq -r --arg t "$TAG" '.instances[] | select(.tags|index($t)) | "\(.label)\t\(.region)\t\(.main_ip)\t\(.status)"')
  if [[ -z "$out" ]]; then echo "켜져 있는 VPN 서버 없음"; else printf '이름\t지역\tIP\t상태\n%s\n' "$out"; fi
}

delete_by_label() {  # $1=label
  local label=${1:?} inst
  inst=$(find_instance "$label")
  if [[ -z "$inst" ]]; then warn "'$label' 서버가 없습니다."; return 0; fi
  api DELETE "/instances/$(jq -r .id <<<"$inst")" >/dev/null
  rm -f -- "${OUT_DIR:?}/${label:?}.conf" "${DL_DIR:?}/${label:?}.conf"
  say "삭제함: $label (WireGuard 앱에서 해당 터널도 지워 주세요)"
}

cmd_down() {
  local alias=${1:-}; [[ -n "$alias" ]] || die "예: bash vpn/vpn.sh down tokyo   또는   down all"
  need curl; need jq; load_key
  if [[ "$alias" == all ]]; then
    local l
    for l in $(vpn_labels); do delete_by_label "$l"; done
  else
    delete_by_label "$(tunnel_name "$alias")"
  fi
}

cmd_switch() {
  local alias=${1:-}; [[ -n "$alias" ]] || die "예: bash vpn/vpn.sh switch london"
  local keep l
  keep=$(tunnel_name "$alias")
  cmd_up "$alias"
  for l in $(vpn_labels); do
    [[ "$l" == "$keep" ]] || delete_by_label "$l"
  done
  say "지역 변경 완료 → WireGuard 앱에서 '$keep' 터널을 켜세요."
}

cmd_manual() {
  local target=${1:-}; [[ -n "$target" ]] || die "예: bash vpn/vpn.sh manual ubuntu@1.2.3.4 oracle"
  need ssh
  local host=${target#*@} name spriv spub cpriv cpub
  name=$(tunnel_name "${2:-$host}")
  read -r spriv spub <<<"$(genkey_pair)"
  read -r cpriv cpub <<<"$(genkey_pair)"
  say "$target 에 WireGuard 설치 중 (sudo 권한 필요) ..."
  server_script "$spriv" "$cpub" | ssh "$target" 'sudo bash -s'
  write_client_conf "$name" "$cpriv" "$spub" "$host"
  warn "클라우드 방화벽(보안 그룹)에서 UDP $WG_PORT 포트를 열어야 합니다."
}

case "${1:-help}" in
  setup)   cmd_setup ;;
  regions) cmd_regions ;;
  up)      cmd_up "${2:-}" ;;
  down)    cmd_down "${2:-}" ;;
  switch)  cmd_switch "${2:-}" ;;
  list|ls) cmd_list ;;
  manual)  cmd_manual "${2:-}" "${3:-}" ;;
  *)       sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
