# 버전 및 저장소 배포 규칙

이 프로젝트는 서로 다른 종류의 진실을 서로 다른 문서에 둔다.

## 릴리스 기준

- 현재 저장소는 아직 `CHANGELOG.md`를 사용하지 않는다.
- 정식 릴리스가 시작되면 Git tag가 정식 릴리스 식별자다.
- `README.md`는 현재 main 브랜치의 운영 방법을 설명하며, 릴리스 이력을 대신하지 않는다.

태그가 없다면 정식 릴리스 이력처럼 설명하면 안 된다.

## 내부 추적 문서

- `docs/superpowers/specs/`: 로컬 설계 문서
- `docs/superpowers/plans/`: 로컬 구현 계획 문서

이 문서들은 내부 작업 기록이다. 공개 배포 대상이 아니다.

## 공개 배포 정책

이 저장소는 Eldrun 프로젝트와 같은 private/public 분리 정책을 따른다.

저장소 역할:
- private 원본 저장소: 전체 작업 트리와 내부 문서 포함
- offense360 public 저장소: 공개 배포 화이트리스트만 포함
- Kangwonland public 저장소: offense360 public 저장소와 동일한 공개 세트

공개 배포 범위는 오직 `.publish-manifest`로만 정의한다.

`.publish-manifest`에 없는 파일은 기본적으로 비공개로 간주한다.

## 문서 경계

공개 문서:
- `README.md`
- `docs/runbooks/2026-04-10-offline-deployment-rehearsal.md`
- `docs/versioning.md`
- `docs/versioning_ko.md`

내부 전용 문서:
- `docs/superpowers/specs/`
- `docs/superpowers/plans/`

내부 설계 및 계획 문서를 공개 저장소로 복사하면 안 된다.

## 갱신 규칙

공개 저장소로 배포할 때는 다음 순서를 따른다.

1. private 원본 저장소에서 먼저 수정한다.
2. 운영자에게 보이는 동작이 바뀐 경우에만 공개 문서를 갱신한다.
3. 내부 설계/계획 문서는 private 저장소에만 둔다.
4. `tools/sync-repos.sh`로 공개 화이트리스트를 동기화한다.

## 로컬 미러 경로

기본 로컬 미러 경로는 다음을 가정한다.
- `../claude-code-airgap-public`
- `../claude-code-airgap-kangwonland`
