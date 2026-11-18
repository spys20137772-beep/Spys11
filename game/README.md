# 등불지기 (Lanternbound)

어두운 숲에서 10분을 버티고 공허의 왕을 쓰러뜨리는 생존 액션 로그라이트.

## 실행
- 웹: `npm install` → `npm run serve` → http://localhost:8080
- 데스크톱(개발): `npm start`
- 윈도우 빌드: `npm run dist:win` → `dist/Lanternbound-win32-x64/Lanternbound.exe`

## 조작
- 이동: WASD / 방향키 / 게임패드 스틱·십자키
- 메뉴: 방향키 + Enter (게임패드 A), 뒤로 Esc (B)
- 일시정지: Esc / P / 게임패드 Start
- F3: FPS 표시, F11: 전체 화면(데스크톱)

## 구성
- `src/content.js` 무기 8 · 패시브 9 · 적 6종 + 분열체 + 보스 · 상점 · 이벤트 타임라인
- `src/game.js` 시뮬레이션과 렌더링 (그리드 충돌, 300+ 적)
- `src/audio.js` 효과음·배경음악 실시간 합성 (음원 파일 없음)
- `src/ui.js` 메뉴, HUD, 키보드/게임패드 내비게이션
- `tests/full.cjs` 자동 플레이 검수 (타이틀→레벨업→일시정지→보스→승리→패배→상점→저장)
