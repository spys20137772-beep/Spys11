# 💰 드로퍼 타이쿤 (Roblox)

빈 Baseplate에 넣으면 바로 돌아가는 타이쿤 게임. 맵, 컨베이어, 드로퍼, UI까지 전부 코드로 생성돼서 따로 모델을 만들 필요가 없음.

## 기능

| 기능 | 설명 |
|---|---|
| 부지 6개 자동 생성 | 가운데 도로를 사이에 두고 마주보는 배치. 접속하면 빈 부지가 자동 배정되고 그곳에서 스폰 |
| 드로퍼 6종 | 광석이 컨베이어를 타고 판매기로 들어가면 돈이 들어옴 |
| 업그레이더 3종 | 컨베이어 위 게이트를 지나면 광석 가치 x1.5 / x2 / x3 |
| 구매 버튼 | 앞 단계를 사야 다음 버튼이 나타남. 돈이 충분하면 초록, 부족하면 빨강 |
| 장식 | 벽, 가로등, 고급 바닥, 정원수, 분수대, 고속 컨베이어 |
| 환생 | 돈과 아이템은 초기화, 수입은 환생 1회당 +50% (영구) |
| 저장 | DataStore 자동 저장 (60초마다, 나갈 때, 서버 종료 시, 환생 직후) |
| 게임패스 | 수입 2배 |
| 개발자 상품 | 돈 구매 3종 (중복 지급 방지 포함) |
| UI | 돈 표시, `+$` 팝업, 상점, 환생 진행도, 알림. 모바일에서는 자동으로 축소 |

## 설치 방법

### 가장 쉬운 방법: 파일 하나로 실행
`TycoonGame.rbxlx`를 다운받아서 더블클릭 (또는 Studio → 파일 → 열기) → ▶ 플레이. 끝.

> 코드를 수정한 뒤 이 파일을 다시 만들려면: `python3 tools/build_place.py`

### 방법 A: Rojo (추천)
1. [Rokit](https://github.com/rojo-rbx/rokit) 설치 후 이 폴더에서 `rokit install` (또는 Rojo를 직접 설치)
2. Studio에 Rojo 플러그인 설치
3. 터미널에서 `rojo serve` → Studio의 Rojo 플러그인에서 **Connect**

### 방법 B: 직접 복붙
Studio에서 아래처럼 만들고 파일 내용을 붙여넣기. **이름이 정확히 같아야 함**.

```
ReplicatedStorage
└─ Shared (Folder)
   ├─ Config        (ModuleScript) ← src/shared/Config.luau
   └─ Format        (ModuleScript) ← src/shared/Format.luau

ServerScriptService
└─ Server (Folder)
   ├─ Main          (Script)       ← src/server/Main.server.luau
   ├─ Tycoon        (ModuleScript) ← src/server/Tycoon.luau
   ├─ ItemBuilders  (ModuleScript) ← src/server/ItemBuilders.luau
   ├─ DataService   (ModuleScript) ← src/server/DataService.luau
   └─ Monetization  (ModuleScript) ← src/server/Monetization.luau

StarterPlayer
└─ StarterPlayerScripts
   └─ HUD           (LocalScript)  ← src/client/HUD.client.luau
```

## 꼭 해야 할 설정

1. **저장 기능 켜기**: 게임을 한 번 퍼블리시한 뒤 `게임 설정 → 보안 → API 서비스에 대한 Studio 접근 허용`을 켜기. 안 켜면 Studio에서 저장이 안 된다는 경고가 뜸 (게임은 정상 작동).
2. **결제 ID 넣기** (선택): Creator Dashboard에서 게임패스와 개발자 상품을 만든 뒤 `src/shared/Config.luau`에 ID 입력
   - `Config.GAMEPASS_2X_CASH = 게임패스ID`
   - `Config.CASH_PRODUCTS`의 각 `Id = 상품ID`
   - ID가 0이면 상점에 "ID 설정 필요"로 표시됨

## 커스터마이징

전부 `src/shared/Config.luau`에서 바꾸면 됨.

- **가격, 밸런스**: `Config.Items`의 `Price`, `Value`, `Interval`, `Multiplier`
- **새 드로퍼 추가**: `Config.Items`에 `Type = "Dropper"` 항목 추가. `X`는 -42 ~ 18 사이의 빈 자리 (기존: -36, -26, -16, -6, 4, 14)
- **새 업그레이더 추가**: `Type = "Upgrader"`, `X`는 18 ~ 33 사이 (기존: 20, 25, 30)
- **환생**: `REBIRTH_BASE_COST`, `REBIRTH_COST_GROWTH`, `REBIRTH_BONUS`
- **새 장식 타입**: `src/server/ItemBuilders.luau`에 `function Builders.이름(model, base, def)`를 추가하고 Config에서 `Type = "이름"`으로 사용

> ⚠ 이미 출시한 뒤에 아이템 `Id`를 바꾸면 기존 유저의 구매 기록이 사라짐. 이름(`Name`)은 마음대로 바꿔도 됨.

## 진행 밸런스 (기본값)

첫 환생($150K)까지 대략 10~12분. 기본 드로퍼(무료)부터 시작해서 퀀텀 업그레이더($40K)까지 사면 초당 약 $1,400.
