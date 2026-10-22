# A2 리서치 나노 결과 (pi deepseek-v4.1-flash-ultrafast · 읽기·추론만 · 공식문서/추정 표시는 나노 자기보고 — 검증 전)
질문 3개로 쪼갬(한 번에 묻자 70초 천장에서 rc=143).

## Q1 원문
- `enable-oslogin=TRUE`를 인스턴스/프로젝트에 켜면 그 인스턴스에서 메타데이터 `ssh-keys` 기반 로그인은 인증에 사용되지 않음 «공식문서»; 기존 세션은 유지될 수 있으나 재접속은 OS Login 필요 «추정».
- 기존 사람 사용자 유지: 각 사용자에게 `roles/compute.osLogin`(sudo 필요 시 `roles/compute.osAdminLogin`) 부여 + OS Login 키 등록/동기화 «공식문서»; 메타데이터 키를 그대로 쓰려면 해당 인스턴스는 OS Login 비활성 유지 «공식문서».
- 같은 인스턴스에서 “메타데이터 키 사람 로그인 + SA OS Login”을 동시에 쓰기는 어려움 «공식문서/추정» → 사람은 OS Login으로 이관하거나 별도 bastion/VM 분리 «추정».
- SA가 IAP TCP로 VM 22에 접속하려면 SA에 `roles/iap.tunnelResourceAccessor`와 `compute.instances.get` 필요 «공식문서/추정».
- VM 로그인 주체가 SA라면 SA에 `roles/compute.osLogin`(sudo 없음) 부여 «공식문서»; 단 이 역할은 셸 로그인을 허용하므로 “셸 불가”는 별도 sshd 제한 필요 «추정».
- 사람이 SA를 `--impersonate-service-account`로 빌려 쓰면 그 사람에게 SA의 `roles/iam.serviceAccountTokenCreator` 필요 «공식문서»; VM/리소스에 SA를 붙이거나 actAs 하는 운영에는 `roles/iam.serviceAccountUser` 필요 «공식문서».
- 외부 호스트가 SA 키로 직접 인증하면 보통 `iam.serviceAccountUser`는 불필요(SA 자신이 주체) «추정»; 대신 SA 키 최소권한·키 보관이 핵심.
- 포워딩 목적지를 DB 하나로 제한하는 IAM 권한은 없음 «공식문서/추정»; sshd `Match User/Group` + `PermitOpen <CloudSQL-private-IP>:5432`, `AllowTcpForwarding local`, `PermitTTY no` 등으로 제한 «공식문서(OpenSSH)/추정».
- Cloud SQL 사설 IP 5432 도달성, DB 방화벽/private path, DB 계정 권한은 별도 «공식문서».
- 최소권한 조합: SA에 `compute.osLogin` + `iap.tunnelResourceAccessor`(+`compute.instances.get`), 필요 시 impersonation용 `serviceAccountTokenCreator`; `serviceAccountUser`는 actAs/리소스 연결 시만 «공식문서/추정».

## Q2 원문
1. OpenSSH의 `Match User`, `PermitOpen`, `AllowTcpForwarding local`, `ForceCommand`/`PermitTTY no` 조합은 문법상 가능(공식 OpenSSH).
2. COS는 읽기 전용 루트/불변 이미지(공식)라 `/etc/ssh/sshd_config` 수동 수정의 재부팅 영구 유지는 보장되지 않음(추정).
3. guest agent 비관리 로컬 계정은 `useradd` 등으로 생성 가능할 수 있으나 COS SSH 키/계정 관리와 비충돌은 보장 안 됨(추정).
4. `startup-script`는 매 부팅 root로 실행되므로 계정·authorized_keys·sshd_config를 매번 재적용하는 방식은 가능(공식: boot 시 실행).
5. 다만 이는 파일 영구 저장이 아니라 부팅 시 재구성이며, sshd 재시작/guest agent 덮어쓰기와 순서 경쟁이 있음(추정).
6. `ForceCommand`는 셸 차단에는 유효하나 TCP 포워딩 제어는 `PermitOpen`/`AllowTcpForwarding`이 담당(공식 OpenSSH).
7. 전용 계정을 no-sudo, `PermitOpen DB:5432`, `AllowTcpForwarding local`, `PermitTTY no`로 두면 목표 제한은 가능(추정/공식 OpenSSH).
8. 기존 사람 사용자는 해당 `Match User`만 제한하면 유지되나 sshd reload/restart는 전체에 순간 영향(추정).
9. 결론: COS에서 “로컬 계정+Match User 제한”은 startup-script 재적용 전제로 조건부 가능성은 있으나 취약·비권장(추정); 영구 설정 파일 방식은 불가/비보장(공식+추정).

## Q3 원문
- GCP 공식 문서의 metadata `ssh-keys`는 `user:ssh-rsa ...` 형식만 안내하며 authorized_keys 옵션 지원을 문서화하지 않음 «공식문서».
- 따라서 `user:restrict,permitopen=... ssh-rsa ...`를 넣을 수는 있어도 guest agent가 재동기화 시 보존/해석한다는 보장은 없음 «추정»(버전 의존, 비권장).
- OpenSSH `restrict`는 port forwarding 자체를 끄므로 `restrict,permitopen=...`는 `ssh -L`을 막음; 허용하려면 `no-pty,no-agent-forwarding,no-X11-forwarding,no-user-rc,permitopen="DB_IP:5432"`처럼 `no-port-forwarding`을 빼야 함 «공식(OpenSSH)».
- 대안으로 VM에서 Cloud SQL Auth Proxy(또는 TCP 포워더)를 단일 DB 대상·전용 포트로 서비스하고 IAP TCP로 그 포트만 열면 DB 접근에 SSH는 불필요 «공식문서/추정».
- Cloud SQL Auth Proxy는 `--address 0.0.0.0 --port <전용포트>`로 IAP가 닿게 해야 하고, 방화벽은 IAP 범위 `35.235.240.0/20`에서 해당 포트만 허용 «공식문서».
- IAP IAM 조건 `destination.port`로 포트를 제한할 수 있음 «공식문서»; 다만 그 포트에 도달한 클라이언트를 프록시가 별도 인증하지 않으므로 IAM·방화벽·DB 인증으로 제한 «추정».
- 기존 사람 SSH는 metadata ssh-keys와 IAP 22를 그대로 유지 가능 «공식문서».
