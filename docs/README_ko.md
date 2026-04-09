# Claude Code Airgap

[English](../README.md)

Claude Code를 위한 오프라인 stage 및 deploy 도구다.

Phase 1 지원 플랫폼:
- Windows x64
- glibc 기반 Linux x64

Phase 1 범위에서 제외되는 항목:
- ARM64
- musl/Alpine
- TUI

이 도구는 두 가지 운영 단계로 나뉜다.
- `stage`: 공식 Claude release bucket에 접근할 수 있는 온라인 머신에서 실행
- `deploy`: 준비된 번들을 사용해 오프라인 또는 제한된 머신에서 실행

## 이 저장소가 하는 일

이 저장소는 다음을 제공한다.
- Claude Code release bucket에서 공식 배포 파일 다운로드
- 공식 `manifest.json` 기준 checksum 및 size 검증
- 오프라인 번들 준비
- 복사된 번들을 이용한 오프라인 배포
- 설치된 `claude` 명령을 위한 PATH 설정
- 공식 `settings.json` 생성
- 보수적인 `settings.json` 처리 정책
- 설치 후 헬스체크

이 저장소는 다음을 하지 않는다.
- 별도의 커스텀 패키지 포맷 구현
- Claude 바이너리 재배포 호스팅
- 벤더 installer 우회
- 설치 후 런타임 모델 endpoint 도달 가능성 보장

## 저장소 파일 구성

핵심 스크립트:
- `stage-claude-airgap.ps1`
- `stage-claude-airgap.sh`
- `deploy-claude-airgap.ps1`
- `deploy-claude-airgap.sh`

설정 템플릿:
- `settings/settings.json.template`

생성되는 번들 디렉토리:
- `downloads/`

문서:
- `docs/README_ko.md`
- `docs/versioning.md`
- `docs/versioning_ko.md`
- `docs/runbooks/2026-04-10-offline-deployment-rehearsal.md`

## 저장소 배포 정책

이 저장소는 Eldrun 스타일의 private/public 분리 모델을 따른다.

저장소 역할:
- `claude-code-airgap`: offense360 private source repo
- `claude-code-airgap-public`: offense360 public 배포 repo
- `claude-code-airgap-kangwonland`: Kangwonland public 배포 repo

public 저장소에는 `.publish-manifest`에 정의된 화이트리스트만 들어간다.

public 저장소에 포함되는 항목:
- stage 및 deploy 스크립트
- settings 템플릿
- 운영자 대상 문서

public 저장소에서 제외되는 항목:
- `downloads/`
- 내부 계획 자료
- private 전용 repo 유지보수 도구
- `.publish-manifest`에 없는 기타 내부 작업 자료

두 public 배포 저장소는 동일한 내용이 되도록 유지하는 것이 목적이다.

public 저장소 동기화는 private source 저장소에서 관리한다.

## 지원 매트릭스

### Windows

- 지원 셸: PowerShell 5.1 또는 PowerShell 7+
- 지원 artifact: `win32-x64`
- Windows에서 Claude Code 런타임 동작을 위해 Git for Windows가 여전히 중요하다

### Linux

- 지원 셸: `bash`
- 필요 명령: `curl`, `sha256sum`, `ldd`, `grep`, `sed`, `awk`
- 지원 artifact: `linux-x64`
- glibc 기반 시스템만 지원한다

### 설계상 거부되는 환경

- ARM64 Windows
- ARM64 Linux
- Alpine 같은 musl/uClibc 계열 시스템

## 번들 구조

이 도구는 배포 가능한 번들을 `downloads/` 아래에 기록한다.

예시:

```text
downloads/
├── VERSION.json
├── manifest.json
├── claude-2.1.97-win32-x64.exe
└── claude-2.1.97-linux-x64
```

deploy 스크립트는 다음 두 가지 배치를 모두 찾을 수 있다.
- 번들 파일이 deploy 스크립트 바로 옆에 있는 경우
- 번들 파일이 deploy 스크립트 옆의 `downloads/` 하위에 있는 경우

## 메타데이터 파일

### `manifest.json`

- 공식 Claude Code release bucket에서 다운로드된다
- checksum 및 size의 기준 데이터로 사용된다
- deploy 단계에서 다시 검증된다

### `VERSION.json`

- `stage`가 생성한다
- 다음 정보를 저장한다:
  - tool version
  - Claude version
  - 다운로드 시각
  - stage된 플랫폼 목록
  - source URL 목록

중요한 동작:
- 같은 Claude 버전에 대해 다른 플랫폼을 추가 stage하면 `downloaded_platforms`가 갱신된다
- 같은 `downloads/` 디렉토리 안에 다른 Claude 버전을 stage하려고 하면 거부된다
- 다른 Claude 버전을 준비하려면 먼저 `downloads/`를 비워야 한다

## 운영 모델

### 온라인 머신

다음에 접근할 수 있는 머신에서 `stage`를 실행한다.
- `https://storage.googleapis.com`
- 공식 Claude Code release bucket

### 오프라인 머신

저장소 전체 또는 번들 파일만 오프라인 머신으로 복사한 뒤 `deploy`를 실행한다.

deploy 스크립트는 다음을 수행한다.
- 번들 메타데이터 검증
- 바이너리 size 및 SHA256 재검증
- PATH 준비
- 공식 `settings.json` 생성 또는 수정
- 검증된 native installer 실행
- 설치 후 헬스체크 실행

## Stage 사용법

### Windows

도움말:

```powershell
.\stage-claude-airgap.ps1 -h
```

도구 버전 출력:

```powershell
.\stage-claude-airgap.ps1 -V
```

현재 기본 플랫폼 stage:

```powershell
.\stage-claude-airgap.ps1
```

Windows x64만 stage:

```powershell
.\stage-claude-airgap.ps1 -p win32-x64
```

Windows와 Linux artifact를 함께 stage:

```powershell
.\stage-claude-airgap.ps1 -p win32-x64,linux-x64
```

명시 버전 stage:

```powershell
.\stage-claude-airgap.ps1 -v 2.1.97 -p win32-x64,linux-x64
```

### Linux

도움말:

```bash
./stage-claude-airgap.sh -h
```

도구 버전 출력:

```bash
./stage-claude-airgap.sh -V
```

현재 기본 플랫폼 stage:

```bash
./stage-claude-airgap.sh
```

Linux x64만 stage:

```bash
./stage-claude-airgap.sh -p linux-x64
```

Linux와 Windows artifact를 함께 stage:

```bash
./stage-claude-airgap.sh -p linux-x64,win32-x64
```

명시 버전 stage:

```bash
./stage-claude-airgap.sh -v 2.1.97 -p linux-x64,win32-x64
```

### Stage 동작

`stage`는 다음 단계를 수행한다.
1. 인자 검증
2. Claude 버전 결정
3. `manifest.json` 다운로드
4. 요청된 플랫폼 바이너리 다운로드
5. 다운로드된 파일의 size 검증
6. `manifest.json` 기준 SHA256 검증
7. `VERSION.json` 기록 또는 갱신

파일이 이미 존재하고 기대하는 size와 checksum이 일치하면:
- 기존 파일을 재사용한다
- 다시 다운로드하지 않는다

파일이 존재하지만 일치하지 않으면:
- 기존 파일을 삭제한다
- 다시 다운로드한다

다운로드한 파일이 무결성 검증에 실패하면:
- 부분 파일을 제거한다
- 명령은 오류와 함께 종료된다

## Deploy 사용법

### Windows

도움말:

```powershell
.\deploy-claude-airgap.ps1 -h
```

도구 버전 출력:

```powershell
.\deploy-claude-airgap.ps1 -V
```

배포 실행:

```powershell
.\deploy-claude-airgap.ps1
```

### Linux

도움말:

```bash
./deploy-claude-airgap.sh -h
```

도구 버전 출력:

```bash
./deploy-claude-airgap.sh -V
```

배포 실행:

```bash
./deploy-claude-airgap.sh
```

### Deploy 동작

`deploy`는 다음 단계를 수행한다.
1. 현재 플랫폼 감지
2. `VERSION.json`과 `manifest.json` 위치 확인
3. 현재 플랫폼이 번들에 포함되어 있는지 확인
4. stage된 Claude 버전과 manifest 버전이 일치하는지 확인
5. 현재 플랫폼 바이너리의 SHA256과 size를 다시 계산
6. 검증된 바이너리를 도구가 관리하는 임시 작업 디렉토리로 복사
7. 검증된 installer 실행
8. PATH 구성
9. `settings.json` 구성
10. 헬스체크 실행

## PATH 처리

### Windows

대상 PATH 항목:

```text
%USERPROFILE%\.local\bin
```

동작:
- User PATH에 이 항목이 없으면 deploy가 추가한다
- 현재 프로세스 PATH도 함께 갱신해 현재 셸에서 바로 `claude`를 찾을 수 있게 한다

### Linux

대상 PATH 항목:

```text
$HOME/.local/bin
```

동작:
- deploy는 현재 프로세스를 위해 PATH를 export한다
- 이후 셸을 위해 작은 관리용 PATH 블록을 다음 파일에 추가한다:
  - `~/.bashrc`
  - `~/.profile`

## `settings.json` 처리

이 도구는 공식 Claude Code 사용자 설정 파일을 사용한다.

- Windows: `%USERPROFILE%\.claude\settings.json`
- Linux: `$HOME/.claude/settings.json`

이 도구는 `claude.json`을 만들거나 사용하지 않는다.

### 기본 관리 키

생성되는 템플릿에는 현재 다음 값이 들어간다.

```json
{
  "env": {
    "DISABLE_AUTOUPDATER": "1",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "DISABLE_NON_ESSENTIAL_MODEL_CALLS": "1",
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:4000",
    "ANTHROPIC_AUTH_TOKEN": "no-token"
  }
}
```

의미:
- `DISABLE_AUTOUPDATER=1`
  - 기본 자동 업데이트 동작을 비활성화한다
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`
  - telemetry 성격의 비필수 트래픽을 비활성화한다
- `DISABLE_NON_ESSENTIAL_MODEL_CALLS=1`
  - 비필수 모델 호출을 줄인다
- `ANTHROPIC_BASE_URL=http://127.0.0.1:4000`
  - Claude Code가 로컬 또는 프록시된 Anthropic 호환 gateway를 바라보게 한다
- `ANTHROPIC_AUTH_TOKEN=no-token`
  - 실제 토큰이 필요 없는 gateway를 위한 placeholder 값이다

### Windows settings 정책

Windows는 보수적으로 동작하지만 제한된 병합은 허용한다.

`%USERPROFILE%\.claude\settings.json`이 없으면:
- deploy가 템플릿 기반으로 새 파일을 만든다

파일이 이미 있으면:
- 표준 JSON으로 파싱한다
- 파일이 invalid JSON이면 실패한다
- `env`가 존재하지만 객체가 아니면 실패한다
- `env` 아래의 관리 키만 병합한다
- 관련 없는 기존 키는 유지한다
- 쓰기 전에 timestamped backup을 만든다

### Linux settings 정책

Linux는 기본적으로 fail-closed다.

`$HOME/.claude/settings.json`이 없으면:
- deploy가 템플릿 기반으로 새 파일을 만든다

파일이 이미 있으면:
- 수정하지 않고 중단한다
- 의도적으로 교체하려면 다음을 설정한다:

```bash
export CLAUDE_CODE_AIRGAP_REPLACE_SETTINGS=1
```

- 교체가 허용되면 먼저 timestamped backup을 만든다

## Gateway 템플릿 동작

기본 gateway placeholder는 의도적으로 단순하게 유지한다.

로컬 gateway가 다른 주소를 사용하면:
- `ANTHROPIC_BASE_URL`을 바꾼다

로컬 gateway가 인증을 요구하면:
- `ANTHROPIC_AUTH_TOKEN=no-token`을 실제 토큰으로 바꾼다

로컬 gateway가 인증을 요구하지 않으면:
- gateway가 무시하는 경우 `no-token`을 그대로 placeholder로 둘 수 있다

## 헬스체크

설치 후 deploy는 다음을 실행한다.

- `claude --version`
  - 필수 헬스체크다
  - 이 단계가 실패하면 deploy도 실패한다

- `claude doctor`
  - best-effort 헬스체크다
  - non-zero 종료는 경고로만 표시된다
  - `doctor`가 non-zero를 반환했다는 이유만으로 deploy를 실패 처리하지는 않는다

이렇게 구분한 이유는 오프라인 또는 gateway 기반 환경에서는 native 설치가 정상이어도 `doctor`가 경고를 낼 수 있기 때문이다.

## 업데이트 워크플로

자동 업데이트는 의도적으로 비활성화되어 있다.

업데이트는 수동으로 수행한다.
1. 온라인 머신에서 새 Claude 버전으로 `stage`를 다시 실행한다
2. 갱신된 번들을 오프라인 머신으로 복사한다
3. 오프라인 머신에서 `deploy`를 다시 실행한다

동작상 주의점:
- 같은 Claude 버전에 대해 새 플랫폼을 stage하면 번들 메타데이터에 플랫폼이 누적된다
- 다른 Claude 버전으로 바꾸려면 stage 전에 `downloads/`를 비워야 한다

## 배너

스크립트는 시작 시 항상 짧은 텍스트 배너를 출력한다.

ASCII 아트 배너도 함께 보려면:

### Windows

```powershell
$env:CLAUDE_CODE_AIRGAP_BANNER='1'
.\stage-claude-airgap.ps1 -p win32-x64
```

### Linux

```bash
export CLAUDE_CODE_AIRGAP_BANNER=1
./stage-claude-airgap.sh -p linux-x64
```

## 안전 관련 참고사항

- deploy는 설치 전에 checksum과 size를 다시 검증한다
- 이 도구는 벤더의 최종 설치 경로를 직접 가정하지 않는다
- 검증된 바이너리는 도구가 관리하는 임시 작업 디렉토리로 복사한 뒤 그 위치에서 실행한다
- Linux는 glibc x64만 지원한다
- Windows와 Linux 모두 Phase 1에서 ARM64를 거부한다
- 잘못된 기존 settings 파일을 자동으로 고치지 않는다
- Linux에서는 기존 `settings.json`을 묵시적으로 덮어쓰지 않는다

## 문제 해결

### Stage에서 unsupported platform 오류가 나는 경우

원인:
- 지원하지 않는 플랫폼 토큰을 넘겼거나
- ARM64 환경에서 실행 중일 수 있다

조치:
- `win32-x64`와 `linux-x64`만 사용한다

### `downloads/`에 버전 충돌이 있어 stage가 실패하는 경우

원인:
- 기존 `downloads/` 디렉토리에 다른 Claude 버전이 들어 있다

조치:
- `downloads/`를 제거한다
- 원하는 버전으로 다시 stage한다

### Deploy가 bundle metadata를 찾지 못하는 경우

원인:
- `VERSION.json`과 `manifest.json`이 deploy 스크립트 옆에 없거나
- `downloads/` 아래에도 없다

조치:
- 지원되는 두 가지 레이아웃 중 하나로 번들 파일을 배치한다

### Windows deploy가 기존 settings 때문에 실패하는 경우

원인:
- `%USERPROFILE%\.claude\settings.json`이 invalid JSON이거나
- 그 안의 `env` 값이 객체가 아니다

조치:
- 파일 내용을 확인한다
- 수동으로 수정한 뒤 deploy를 다시 실행한다

### Linux deploy가 settings 덮어쓰기를 거부하는 경우

원인:
- `$HOME/.claude/settings.json`이 이미 존재한다

조치:
- 수동으로 백업 후 제거한다
- 또는 `CLAUDE_CODE_AIRGAP_REPLACE_SETTINGS=1`과 함께 실행한다

### Deploy 후 `claude doctor`가 경고를 내는 경우

원인:
- 오프라인 런타임
- gateway 연결 문제
- 인증 불일치

조치:
- gateway endpoint를 확인한다
- token 값을 확인한다
- `claude --version`이 여전히 성공하는지 확인한다

## 현재 상태

구현된 항목:
- Windows와 Linux용 stage
- Windows와 Linux용 deploy
- manifest 기반 checksum 검증
- 버전 및 플랫폼 검증
- 보수적인 settings 처리
- gateway placeholder 템플릿
- 설치 후 헬스체크
- 시작 배너 지원

아직 구현되지 않은 항목:
- TUI
- ARM64
- musl/Alpine 지원
- 고급 다중 버전 번들 관리
