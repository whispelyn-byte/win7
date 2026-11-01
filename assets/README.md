# assets 폴더

## 제일 쉬운 방법

원글의 구글 드라이브 폴더를 통째로 받은 zip(`Windows (Vista-7)-2026....zip`)을 **압축 풀지 말고 그대로** 여기에 넣으세요.
스크립트의 `assets-unpack` 단계가 zip 안의 zip(Media, Network Activity Indicator, NTMU-Packs, Windows-11to7)까지
`assets\_unpacked\`에 자동으로 풀고, 필요한 파일을 이름 패턴으로 찾아요.

```
assets/
├─ README.md
└─ Windows (Vista-7)-20261031T133530Z-1-001.zip   ← 이것만 넣으면 됨
```

> ⚠️ **assets는 GitHub에 올리지 마세요.** 스크립트는 내 PC에서 돌기 때문에 PC의 assets 폴더에만 있으면 돼요.
> (`Windows-11to7`만 443MB라 GitHub 100MB 제한에 걸리고, 남의 파일을 공개 저장소에 재배포하는 문제도 있어요.)
> `.gitignore`에 `assets/*`를 넣어놔서 실수로 커밋되지 않아요.
>
> Windows 7 ISO도 여기 넣거나(`*.iso` 자동 탐지) `config.json`의 `win7IsoPath`에 경로를 적으세요.

## 따로 받은 파일을 넣을 때

하위 폴더까지 이름 패턴으로 뒤져서 찾기 때문에 구조가 아래와 꼭 같지 않아도 돼요.

```
assets/
├─ SecureUxTheme/            SecureUxTheme_x64.msi            (필수: 1단계)
├─ Aero11/                   테마 폴더 내용 그대로 (*.theme, *.msstyles 폴더 등)   (필수)
├─ OpenGlass/                OpenGlassSetup.Signed.exe, oglbasic.reg, oglfull.reg
├─ NTMU/                     NTMU 설치 파일 (*.exe / *.msi)  ← 없으면 사이트를 열어줌
├─ NTMU Packs/
│   ├─ explorer-frame-vista-1.0.0/pack.ini ...
│   ├─ cursor-7-1.0.1/
│   ├─ win7-ribbon-1.0.0/
│   ├─ briefcase-1.0.0/
│   ├─ pane7-1.3.0/
│   ├─ win7-tray-items-1.0.0/
│   └─ gameux-1.0.0/
├─ Explorer7/                ex7-m2_winmain_r4 폴더 내용 (ex7forw8.exe, explorer.exe, *.reg)
├─ ClassicApps/              win7games.com 설치 파일들 (계산기/메모장/그림판/워드패드/게임)
├─ OldNewExplorer/           OldNewExplorerCfg.exe (+ 같이 있는 dll들)
├─ OpenWithEx/               설치 파일
├─ AuthUx/                   설치 파일
├─ NetworkActivityIndicator/ 설치 파일 또는 zip
├─ Media/                    Win7 사운드 (없으면 ISO의 Windows\Media 사용)
├─ Gadgets/                  가젯 설치 파일 (없으면 gadgetsrevived.com 열어줌)
├─ FontChanger/              글꼴 변경 도구 (없으면 사이트 열어줌)
│
│  ── 아래는 없어도 자동으로 받아요 (오프라인이거나 버전 고정하고 싶을 때만) ──
├─ Aerexplorer/              aerexplorer11fork.cpp (+ 드라이브 이름 깨질 때 쓰는 다른 포크)
├─ firefox-native-controls/  xul.dll
├─ BeautyFox-main/           BeautyFox 저장소 zip 푼 것
├─ ep_setup.exe              ExplorerPatcher
├─ Firefox Setup 115.9.1esr.exe
└─ ResourceHacker.exe
```

ISO에서 자동으로 꺼내는 파일 (따로 안 넣어도 됨):
`imageres.dll`, `shell32.dll`, `AltTab.dll`, `AltTab.dll.mui`, `Windows\Media`,
`User Account Pictures`, `iexplore.exe`.
직접 넣으면(`AltTab.dll`, `AltTab.dll.mui`, `iexplore.exe`, `User Account Pictures/`) 그게 우선이에요.
