# 📱 폰에 리눅스 설치 + 지역 바꾸는 VPN

안드로이드 폰 하나로 두 가지를 합니다. **루팅은 필요 없어요.**

1. **리눅스 설치**: Termux 안에 Ubuntu를 설치하고, 원하면 데스크톱 화면까지 띄웁니다.
2. **지역 변경 VPN (무료)**: 원하는 나라(일본, 미국, 한국 등)의 무료 VPN 서버에 명령 하나로 연결 파일을 받습니다. 가입이나 결제가 필요 없어요.

---

## 0. 준비물 (앱 설치)

| 앱 | 용도 | 받는 곳 |
|---|---|---|
| **Termux** | 리눅스 명령 실행 | F-Droid 또는 GitHub (`termux/termux-app`). ⚠️ 플레이스토어 버전은 오래돼서 안 됩니다 |
| **OpenVPN for Android** | VPN 연결 | 플레이스토어 |
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

## 2. 지역 바꾸는 VPN (무료)

### 어떻게 동작하나요?

```
[폰: OpenVPN 앱] ══암호화══▶ [VPN Gate 서버 @ 일본] ──▶ 인터넷 (사이트에는 "일본"으로 보임)
```

**VPN Gate**(일본 쓰쿠바대학 학술 프로젝트)의 무료 공개 서버를 씁니다. **가입, 결제, 카드 등록이 모두 없습니다.**
`vpn.sh`가 서버 목록을 받아서 원하는 나라의 가장 좋은 서버를 고르고, 폰에서 가져올 `.ovpn` 파일을 만들어 줍니다.

### 최초 1회 설정

1. 플레이스토어에서 **OpenVPN for Android** 앱을 설치합니다. 개발자는 Arne Schwabe입니다.
2. Termux에서 아래를 실행합니다.

```bash
bash vpn/vpn.sh setup
```

다운로드 폴더 접근 권한을 물으면 허용하세요.

### 사용법

```bash
bash vpn/vpn.sh countries      # 지금 쓸 수 있는 나라와 서버 수
bash vpn/vpn.sh get japan      # 일본 서버 1개 → Download/vpn-JP-1.ovpn
bash vpn/vpn.sh get us 3       # 미국 서버 3개 (vpn-US-1, 2, 3)
```

받은 파일로 이렇게 연결합니다.

1. **OpenVPN for Android 앱 → 오른쪽 위 가져오기(📥)**
2. `Download/vpn-JP-1.ovpn`을 선택하고 저장합니다.
3. 목록에서 눌러서 연결합니다 ✅
   사용자 이름과 비밀번호를 물으면 둘 다 `vpn`을 입력하세요.

**지역 바꾸기**: 다른 나라로 `get` 한 번 더 하고, 앱에서 새 파일을 가져와 연결하면 끝입니다.

> 확인은 브라우저에서 `ipinfo.io`를 열어 국가가 바뀌었는지 보면 됩니다.

#### 나라 이름

`korea` `japan` `us` `taiwan` `hongkong` `thailand` `vietnam` `singapore` `indonesia` `philippines` `india` `russia` `uk` `germany` `france` `canada` `australia` `brazil`

2글자 국가 코드(`JP`, `US`, `KR` 등)를 넣어도 됩니다. 서버는 자원봉사자가 운영해서
**나라별 서버 수가 수시로 바뀝니다.** 일본, 한국, 미국 서버가 가장 많습니다. `countries`로 확인하세요.

### 주의할 점 (무료라서)

- 자원봉사자가 운영하는 서버라 **속도가 느리거나 갑자기 끊길 수** 있습니다. 그럴 땐 다른 번호 파일을 쓰거나 다시 `get` 하세요.
- VPN Gate는 남용 방지를 위해 **접속 기록을 보관**합니다. 그리고 서버 운영자가 누군지 모릅니다.
  그러니 **은행이나 중요한 로그인은 VPN을 끄고** 하세요. 지역 변경 용도로만 쓰는 걸 추천합니다.

---

## 파일 구조

```
linux/install.sh   Termux에서 Ubuntu/데스크톱 설치
vpn/vpn.sh         나라별 무료 VPN 서버 설정 파일 받기
```

## 참고

- 사용하는 서비스의 이용약관과 현지 법을 지켜서 사용하세요.
