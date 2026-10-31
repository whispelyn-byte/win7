# Win7Look: Windows 11을 Windows 7처럼 자동으로

[rg0님의 note 글](https://note.com/rg0/n/n077ba340cc72)에 나온 23단계를 PowerShell로 자동화한 스크립트예요.
GUI로만 할 수 있는 부분(Windhawk 모드 설치, NTMU 적용 버튼 등)은 **창을 열고 경로/이름을 클립보드에 넣은 다음 뭘 누르면 되는지 안내**해요.

> ⚠️ 시스템 파일, DWM, 탐색기를 건드려요. **VM에서 먼저 해보세요.** 스크립트가 시작할 때 복원 지점을 만들지만, 모든 건 자기 책임이에요.
> 원글 경고: 빌드 26200.8457 이상은 비추천, Windows Update 후 레지스트리가 깨질 수 있음, Electron 앱(Discord/Spotify 등)은 먼저 설치.

## 준비

1. 이 저장소를 받기 (`git clone` 또는 ZIP)
2. `assets\` 에 파일 넣기 → [assets/README.md](assets/README.md)
3. Windows 7 ISO 준비 (SP1 x64 권장, 가능하면 Windows 표시 언어와 같은 언어)
4. `config.example.json` 을 `config.json` 으로 복사하고 수정
   - `win7IsoPath`: ISO 경로 (필수)
   - `language`: `ko-KR`
   - `isLaptop`: 노트북이면 `true` (트레이에 배터리/모바일 센터 추가)
   - `steps`: 끄고 싶은 단계는 `false`

## 실행

`run.cmd` 를 더블클릭하거나, PowerShell에서:

```powershell
.\Install-Win7Look.ps1            # 안 끝난 단계부터 끝까지
.\Install-Win7Look.ps1 -List      # 단계 목록과 진행 상태
.\Install-Win7Look.ps1 -DryRun    # 실제로 안 바꾸고 할 일만 출력
.\Install-Win7Look.ps1 -Only firefox-ie,sounds
.\Install-Win7Look.ps1 -Skip openglass
.\Install-Win7Look.ps1 -Redo aero11-theme     # 완료 표시 지우고 다시
.\Install-Win7Look.ps1 -Reset                 # 진행 상태 전체 초기화
.\Install-Win7Look.ps1 -Rollback              # 레지스트리/파일 변경 되돌리기
```

- 관리자 권한이 없으면 알아서 UAC로 다시 실행해요.
- **재부팅/로그아웃이 필요한 단계**가 끝나면 다음 로그온 때 자동으로 이어서 실행되게 예약해요 (작업 스케줄러 `Win7Look-Resume`, 한 번 실행되면 지워져요).
- 단계가 실패하면 거기서 멈춰요. 문제를 고치고 다시 실행하면 그 단계부터 이어서 해요.
- 진행 상태, 로그, 백업: `C:\ProgramData\Win7Look\`

## 단계

| # | ID | 내용 | 방식 |
|---|---|---|---|
| 0 | `preflight` | 빌드/언어/에셋 점검, 복원 지점 | 자동 |
| 5 | `tools` | 7-Zip (winget) | 자동 |
| 8 | `win7-extract` | ISO의 install.wim에서 필요한 파일 추출 | 자동 |
| 10 | `secureuxtheme` | SecureUxTheme 설치 → **재부팅** | 자동 |
| 11 | `aero11-theme` | Aero11을 `C:\Windows\Resources\Themes`에 복사 + 적용 | 자동 |
| 12 | `openglass` | OpenGlass 설치 + oglbasic/oglfull.reg → **로그아웃** | 자동 |
| 20 | `windhawk` | Windhawk (winget) | 자동 |
| 21 | `windhawk-basic-mods` | Bring Back the Borders! / Force thick frames / Win7 UAC Dim | 반자동 |
| 30 | `classic-apps` | 앱 실행 별칭 끄기 + win7games 클래식 앱 | 반자동 |
| 40 | `ntmu` | NTMU 설치 | 반자동 |
| 41 | `explorer-frame` | NTMU: explorer-frame-vista | 반자동 |
| 42 | `cursor-7` | NTMU: cursor-7 + 커서 새로고침, 포인터 그림자 | 반자동 |
| 43 | `aerexplorer` | Windhawk 설정 + Aerexplorer 소스 (클립보드) | 반자동 |
| 44 | `win7-ribbon` | NTMU: win7-ribbon | 반자동 |
| 45 | `briefcase` | NTMU: briefcase | 반자동 |
| 46 | `pane7` | `C:\Windows\ko-KR` → `en-US` 복사 + NTMU: pane7 + 아이콘 캐시 정리 | 반자동 |
| 47 | `explorerpatcher` | ExplorerPatcher (GitHub 최신) + Alt+Tab을 Windows 10 방식으로 | 자동 |
| 48 | `win7-tray-items` | NTMU: win7-tray-items → **재부팅** | 반자동 |
| 49 | `alttab` | Win7 AltTab.dll / .mui → System32 + Windhawk 로더 | 반자동 |
| 50 | `explorer7` | Explorer7 reg 가져오기 + ex7forw8 → **로그아웃** | 반자동 |
| 51 | `explorer7-post` | EnableImmersive=1, ColorizationOptions=0, Aero Peek, 폴더 옵션 | 자동 |
| 52 | `gameux` | NTMU: gameux | 반자동 |
| 60 | `winaero-tweaks` | Winaero Tweaker 항목을 레지스트리로 직접 적용 → **로그아웃** | 자동 |
| 61 | `oldnewexplorer` | 라이브러리 표시 + OldNewExplorer | 반자동 |
| 62 | `taskbar-tweaker` | 7+ Taskbar Tweaker, show_desktop_button_size=15 | 자동 |
| 70 | `firefox-ie` | Firefox 115.9.1esr → IE (BeautyFox, xul.dll, 아이콘/이름, 업데이트 끄기) | 자동 |
| 80 | `openwithex` | OpenWithEx | 반자동 |
| 81 | `authux` | AuthUx | 반자동 |
| 82 | `this-pc-commands` | Windhawk: Old This PC Commands | 반자동 |
| 83 | `gadgets` | Windows 7 가젯 | 반자동 |
| 84 | `account-pictures` | Win7 사용자 계정 사진 | 자동 |
| 85 | `system-font` | 시스템 글꼴 | 수동 안내 |
| 86 | `recent-folders` | '최근 폴더' 바로가기 | 반자동 |
| 87 | `network-indicator` | 네트워크 활동 표시기 + 로그온 작업 | 자동 |
| 88 | `icon-redirect` | `C:\icons` + theme.ini + Windhawk Resource Redirect + 아이콘 캐시 | 반자동 |
| 89 | `windhawk-extras` | Aero Flyout Fix 등 추가 모드 | 반자동 |
| 90 | `sounds` | Win7 사운드로 교체 | 자동 |
| 91 | `remove-default-apps` | Win11 기본 앱 제거 (`removeApps`로 목록 변경 가능) | 자동 |

### Winaero Tweaker 대신 직접 적용하는 항목 (`winaero-tweaks`)
클래식 우클릭 메뉴, 백그라운드 앱 끄기, Copilot 끄기, Spotlight 바탕 화면 아이콘 제거, 광고/추천 끄기, '스토어에서 앱 찾기' 끄기,
우클릭 메뉴 항목 제거(Defender 검사, 사진으로 편집, Paint 3D, 공유, 터미널에서 열기, 메모장에서 편집, Clipchamp, Copilot에게 묻기),
Edge 잡동사니/바탕 화면 바로가기/업데이트 끄기, 제어판에 Windows Update 추가, Windows 사진 뷰어 활성화, 탐색 창에서 갤러리 제거.

## 원글과 다른 점

- **NSudo 안 씀.** System32/`C:\Windows\en-US`/`C:\Windows\Media`에 쓸 때 권한이 막히면 `takeown` + `icacls`로 처리해요.
- Winaero Tweaker는 설치하지 않고 같은 레지스트리 값을 직접 넣어요.
- Firefox 자동 업데이트는 `policies.json`으로 꺼요.
- 원글의 `theme.ini`에서 빠진 역슬래시를 고쳤어요 (`%SystemRoot%\System32\shell32.dll=...`).
- AltTab.dll.mui는 ISO에 해당 언어(ko-KR) 파일이 없으면 en-US 파일을 써요.

## 되돌리기

`-Rollback`은 `C:\ProgramData\Win7Look\backup\manifest.jsonl`에 기록된 **레지스트리 값/키, 덮어쓴 파일, 추가한 파일, 예약 작업**을 거꾸로 되돌려요.
설치한 프로그램(Windhawk, ExplorerPatcher, OpenGlass, Firefox 등)과 지운 기본 앱은 그대로 두니 직접 제거/재설치하세요.
NTMU 팩은 NTMU 안에서 되돌리세요. 제일 확실한 방법은 처음에 만든 **시스템 복원 지점**이에요.

## 참고

- Windhawk는 모드 설치용 공식 CLI가 없어서 모드 이름을 클립보드에 넣고 안내만 해요.
- 일부 우클릭 메뉴 CLSID와 ExplorerPatcher/7+TT 레지스트리 값은 커뮤니티에서 알려진 값이에요. Windows 업데이트로 바뀔 수 있어요.
