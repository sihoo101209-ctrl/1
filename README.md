# 📱 폰에 리눅스 설치 + 지역 바꾸는 VPN

안드로이드 폰 하나로 두 가지를 합니다. **루팅은 필요 없어요.**

1. **리눅스 설치**: Termux 안에 Ubuntu를 설치하고, 원하면 데스크톱 화면까지 띄웁니다.
2. **지역 변경 VPN**: 원하는 나라(도쿄, LA, 런던 등)에 **나만 쓰는 WireGuard VPN 서버**를 명령 하나로 만들고, 지역도 명령 하나로 바꿉니다.

---

## 0. 준비물 (앱 설치)

| 앱 | 용도 | 받는 곳 |
|---|---|---|
| **Termux** | 리눅스 명령 실행 | F-Droid 또는 GitHub (`termux/termux-app`). ⚠️ 플레이스토어 버전은 오래돼서 안 됩니다 |
| **WireGuard** | VPN 연결 | 플레이스토어 |
| Termux:X11 (선택) | 리눅스 데스크톱 화면 | GitHub `termux/termux-x11` Releases의 APK |

Termux를 열고 이 저장소를 받습니다.

```bash
pkg install -y git
git clone https://github.com/sihoo101209-ctrl/1.git
cd 1
```

---

## 1. 리눅스 설치

```bash
bash linux/install.sh              # Ubuntu (터미널)
bash linux/install.sh --desktop    # Ubuntu + XFCE 데스크톱
bash linux/install.sh --distro=debian   # 다른 배포판 (debian, archlinux, fedora ...)
```

설치가 끝나면 이렇게 씁니다.

```bash
linux            # Ubuntu 접속 (나가기: exit)
linux-desktop    # 데스크톱 실행 → Termux:X11 앱에 화면이 뜸 (--desktop으로 설치한 경우)
```

삭제: `proot-distro remove ubuntu`

> proot 방식이라 루팅 없이 돌아가지만, 커널 기능(Docker, systemd 등)은 쓸 수 없습니다.

---

## 2. 지역 바꾸는 VPN

### 어떻게 동작하나요?

```
[폰: WireGuard 앱] ══암호화══▶ [내 서버 @ 도쿄] ──▶ 인터넷 (사이트에는 "일본"으로 보임)
```

`vpn.sh`가 클라우드(Vultr)에 원하는 나라의 작은 서버를 자동으로 만들고, WireGuard를 설치한 뒤
폰에서 가져올 **설정 파일(.conf)** 을 만들어 줍니다. 무료 VPN과 달리 **나만 쓰는 서버**라 기록이 남지 않습니다.

### 비용

- Vultr 서버는 **시간당 요금**입니다. 월 $3.5~$6 정도이고, 쓴 시간만큼만 냅니다.
  예를 들어 2시간 쓰고 삭제하면 1센트 정도예요.
- **삭제할 때까지 요금이 나갑니다.** 다 쓰면 꼭 `down`을 실행하세요.

### 최초 1회 설정

1. https://www.vultr.com 에 가입하고 결제수단을 등록합니다.
2. **Account → API → Enable API**에서 키를 복사합니다.
   Access Control에서 "Allow all IPv4"를 추가하세요. 폰 IP는 자주 바뀌기 때문이에요.
3. Termux에서 아래를 실행합니다.

```bash
bash vpn/vpn.sh setup
```

도구를 설치하고, 저장소 접근 권한을 허용하고, API 키를 저장합니다. 키는 `~/.config/region-vpn/config`에 본인만 읽을 수 있게 저장됩니다.

### 사용법

```bash
bash vpn/vpn.sh up tokyo        # 도쿄에 VPN 서버 생성
bash vpn/vpn.sh switch london   # 런던 서버를 만들고, 기존 서버는 자동 삭제 (지역 변경)
bash vpn/vpn.sh list            # 켜져 있는 서버 확인
bash vpn/vpn.sh down london     # 서버 삭제 (요금 중단)
bash vpn/vpn.sh down all        # 전부 삭제
bash vpn/vpn.sh regions         # 가능한 지역 전체 목록
```

`up`이나 `switch`가 끝나면 이렇게 연결합니다.

1. **WireGuard 앱 → ➕ → "파일 또는 압축파일에서 가져오기"**
2. `Download/rvpn-tokyo.conf`를 선택합니다.
3. 스위치를 켜면 연결됩니다 ✅

> 서버가 켜진 뒤 WireGuard 설치에 **1~2분**이 더 걸립니다. 바로 안 되면 잠깐 기다렸다 다시 켜세요.
> 확인은 브라우저에서 `ipinfo.io`를 열어 국가가 바뀌었는지 보면 됩니다.

#### 쓸 수 있는 지역 이름

| 아시아 | 미주 | 유럽·기타 |
|---|---|---|
| `seoul` `tokyo` `osaka` `singapore` `mumbai` `delhi` `sydney` `melbourne` | `la` `newyork` `seattle` `sf` `chicago` `dallas` `miami` `atlanta` `hawaii` `toronto` `mexico` `saopaulo` `santiago` | `london` `frankfurt` `paris` `amsterdam` `madrid` `stockholm` `warsaw` `telaviv` `johannesburg` |

Vultr 지역 코드(`nrt`, `lax` 등)를 직접 넣어도 됩니다.

### 이미 서버가 있다면 (예: 오라클 클라우드 무료 서버)

```bash
bash vpn/vpn.sh manual ubuntu@서버IP 이름
```

SSH로 접속해서 WireGuard를 설치하고 설정 파일을 만듭니다. 이 경우 클라우드 콘솔의 방화벽(보안 목록)에서 **UDP 51820** 포트를 직접 열어야 합니다.

---

## 파일 구조

```
linux/install.sh   Termux에서 Ubuntu/데스크톱 설치
vpn/vpn.sh         지역별 WireGuard VPN 서버 생성·변경·삭제
```

## 참고

- VPN은 서버에서 IPv4만 쓰고, 폰의 IPv6 트래픽도 터널로 막아 실제 위치가 새지 않게 했습니다.
- 각 지역 서버마다 새 키를 만들고, 키는 폰에서만 생성됩니다.
- 사용하는 서비스의 이용약관과 현지 법을 지켜서 사용하세요.
