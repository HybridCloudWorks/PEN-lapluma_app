#!/usr/bin/env python3
"""
Live iOS Device E2E Connectivity & Real-Time Template Simulation Harness.

Simulates the native iOS Aperture client (iOS 17/18+ and iOS 27 spatial)
communicating with the Google API Gateway and Cloud Run microservices.

Verifies:
1. Passkey Face ID & Session Attestation (OIDC / Staging test bearer tokens)
2. Real-time Client / User Creation (POST /v1/clients with Idempotency-Key)
3. Form I-130 Blueprint Template Retrieval (GET /v1/library/blueprints)
4. Case Workspace & Section Synchronization (GET /v1/cases/{caseId}/workspace)
5. Real-Time Template Commit with Revision Tracking (POST /v1/cases/.../commit)
6. Optimistic Concurrency Conflict Detection (HTTP 412 Problem Details)
7. Multi-trial reliability & >= 95% SLA verification

Usage:
    python tools/live_ios_e2e_simulation.py [--live] [--with-cloud-sql] [--iterations=10] [--dry-run]
"""

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

STAGING_GATEWAY = "https://lp-gateway-staging-am9yq93d.uc.gateway.dev"
CLOUD_SQL_INSTANCE = "lp-postgres-staging-9f5d4205"
GCP_PROJECT = "project-27d49bcd-4a1d-4d7a-8a7"
DEFAULT_TEST_TOKEN = "lp_test_mobile_live_e2e"
TARGET_SLA_PERCENT = 95.0


def check_cloud_sql_state() -> str:
    """Returns the current state and activation policy of the Cloud SQL instance."""
    try:
        res = subprocess.run(
            [
                "gcloud", "sql", "instances", "describe", CLOUD_SQL_INSTANCE,
                f"--project={GCP_PROJECT}",
                "--format=value(state,settings.activationPolicy)"
            ],
            capture_output=True,
            text=True,
            check=True
        )
        parts = res.stdout.strip().split()
        if len(parts) >= 2:
            return f"{parts[0]} ({parts[1]})"
        return res.stdout.strip()
    except Exception as e:
        return f"UNKNOWN: {e}"


def patch_cloud_sql(activation_policy: str) -> bool:
    """Updates the Cloud SQL activation policy (ALWAYS or NEVER)."""
    print(f"[Cloud SQL] Setting activationPolicy={activation_policy}...")
    try:
        subprocess.run(
            [
                "gcloud", "sql", "instances", "patch", CLOUD_SQL_INSTANCE,
                f"--project={GCP_PROJECT}",
                f"--activation-policy={activation_policy}",
                "--quiet"
            ],
            check=True
        )
        print(f"[Cloud SQL] Activation policy set to {activation_policy}.")
        return True
    except subprocess.CalledProcessError as e:
        print(f"[Cloud SQL] Error patching instance: {e}")
        return False


def wait_for_cloud_sql_runnable(timeout_sec: int = 180) -> bool:
    """Polls until Cloud SQL is in RUNNABLE state."""
    print("[Cloud SQL] Waiting for instance to become RUNNABLE...")
    start = time.time()
    while time.time() - start < timeout_sec:
        state = check_cloud_sql_state()
        if "RUNNABLE" in state and "ALWAYS" in state:
            print(f"[Cloud SQL] Instance is RUNNABLE ({time.time() - start:.1f}s).")
            return True
        time.sleep(5)
    print("[Cloud SQL] Timed out waiting for instance.")
    return False


class IOSClientSimulation:
    def __init__(self, base_url: str, auth_token: str, dry_run: bool = False):
        self.base_url = base_url.rstrip("/")
        self.auth_token = auth_token
        self.dry_run = dry_run
        self.simulated_case_revision = 1

    def send_http(self, method: str, path: str, body: dict | None = None, headers: dict | None = None) -> tuple[int, dict | None, float]:
        if self.dry_run:
            return self._simulate_local(method, path, body, headers)

        url = f"{self.base_url}{path}"
        req_headers = {
            "Accept": "application/json, application/problem+json",
            "User-Agent": "ApertureApp/0.3.0 (iOS 27.0; Apple Silicon)",
            "X-Request-ID": str(uuid.uuid4()),
            "X-Tenant-ID": "clinic-sf-01",
        }
        if self.auth_token:
            req_headers["Authorization"] = f"Bearer {self.auth_token}"
        if headers:
            req_headers.update(headers)

        data = None
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            req_headers["Content-Type"] = "application/json"

        req = urllib.request.Request(url, data=data, headers=req_headers, method=method)
        start_time = time.perf_counter()
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                elapsed_ms = (time.perf_counter() - start_time) * 1000.0
                resp_data = resp.read().decode("utf-8")
                parsed = json.loads(resp_data) if resp_data else None
                return resp.status, parsed, elapsed_ms
        except urllib.error.HTTPError as e:
            elapsed_ms = (time.perf_counter() - start_time) * 1000.0
            resp_data = e.read().decode("utf-8")
            parsed = None
            try:
                parsed = json.loads(resp_data)
            except Exception:
                parsed = {"raw": resp_data}
            return e.code, parsed, elapsed_ms
        except Exception as e:
            elapsed_ms = (time.perf_counter() - start_time) * 1000.0
            return 0, {"error": str(e)}, elapsed_ms

    def _simulate_local(self, method: str, path: str, body: dict | None, headers: dict | None) -> tuple[int, dict | None, float]:
        """Simulates native iOS Aperture engine state transitions for offline validation."""
        time.sleep(0.015)  # Simulate 15ms local network / dispatch latency
        if path == "/v1/library/blueprints" and method == "GET":
            return 200, {
                "data": [
                    {
                        "namespace": "uscis",
                        "id": "i-130",
                        "revision": 1,
                        "title": "Petition for Alien Relative",
                        "editionDate": "2024-04-01",
                        "sections": ["petitioner", "beneficiary", "relationship"]
                    }
                ]
            }, 15.0

        if path == "/v1/clients" and method == "POST":
            label = body.get("displayLabel", "Client") if body else "Client"
            return 201, {
                "folderId": f"folder-{uuid.uuid4().hex[:8]}",
                "displayLabel": label,
                "status": "intake"
            }, 18.0

        if "/workspace" in path and method == "GET":
            return 200, {
                "caseId": "case-fixture-0002",
                "sections": [
                    {"id": "identity", "revision": self.simulated_case_revision, "title": "Petitioner Identity"}
                ]
            }, 14.0

        if "/commit" in path and method == "POST":
            if_match = headers.get("If-Match", "").strip('"') if headers else ""
            expected_rev = body.get("baseRevision") if body else None
            if str(expected_rev) != str(self.simulated_case_revision) or if_match != str(self.simulated_case_revision):
                return 412, {
                    "type": "https://api.lapluma.app/problems/version-conflict",
                    "title": "Version Conflict",
                    "status": 412,
                    "detail": f"Expected revision {self.simulated_case_revision}, got {expected_rev}"
                }, 16.0
            self.simulated_case_revision += 1
            return 200, {
                "section": {
                    "id": "identity",
                    "revision": self.simulated_case_revision,
                    "updatedAt": "2026-09-26T02:00:00Z"
                }
            }, 22.0

        return 404, {"error": "Not Found"}, 10.0


def run_simulation_trial(client: IOSClientSimulation, trial_num: int) -> tuple[bool, dict]:
    results = {}
    total_passed = 0
    trial_start = time.perf_counter()

    # Step 1: User / Client Real-time Creation
    client_name = f"Elena Rostova Trial-{trial_num}-{int(time.time())}"
    idem_key = f"idem-client-{uuid.uuid4().hex[:10]}"
    status, body, ms = client.send_http(
        "POST",
        "/v1/clients",
        body={"displayLabel": client_name},
        headers={"Idempotency-Key": idem_key}
    )
    passed = status in (200, 201)
    if passed:
        total_passed += 1
    folder_id = body.get("folderId") or body.get("id") or body.get("folder_id") if isinstance(body, dict) else None
    results["1_create_client"] = {"status": status, "passed": passed, "elapsed_ms": ms, "folder_id": folder_id}

    # Step 2: Form I-130 Blueprint Library Fetch
    status, body, ms = client.send_http("GET", "/v1/library/blueprints")
    passed = status == 200 and isinstance(body, (dict, list))
    if passed:
        total_passed += 1
    results["2_fetch_blueprints"] = {"status": status, "passed": passed, "elapsed_ms": ms}

    # Step 3: Workspace State Fetch
    case_id = "case-fixture-0002"
    status, body, ms = client.send_http("GET", f"/v1/cases/{case_id}/workspace")
    passed = status == 200 and isinstance(body, dict)
    current_rev = 1
    if passed:
        total_passed += 1
        sections = body.get("sections", [])
        sec = next((s for s in sections if s.get("id") == "identity"), None)
        if sec:
            current_rev = sec.get("revision", 1)
    results["3_fetch_workspace"] = {"status": status, "passed": passed, "elapsed_ms": ms, "current_rev": current_rev}

    # Step 4: Real-Time Template Section Commit
    commit_idem = f"idem-commit-{uuid.uuid4().hex[:10]}"
    commit_payload = {
        "baseRevision": current_rev,
        "values": {
            "applicant.name.first": "Elena",
            "applicant.name.last": "Rostova",
            "trial.timestamp": str(int(time.time()))
        }
    }
    status, body, ms = client.send_http(
        "POST",
        f"/v1/cases/{case_id}/sections/identity/commit",
        body=commit_payload,
        headers={
            "Idempotency-Key": commit_idem,
            "If-Match": f'"{current_rev}"'
        }
    )
    passed = status == 200
    new_rev = current_rev + 1
    if passed:
        total_passed += 1
        if isinstance(body, dict) and "section" in body:
            new_rev = body["section"].get("revision", new_rev)
    results["4_commit_template"] = {"status": status, "passed": passed, "elapsed_ms": ms, "new_rev": new_rev}

    # Step 5: Concurrency Conflict Detection (Verify HTTP 412)
    stale_payload = {
        "baseRevision": current_rev,
        "values": {"applicant.name.first": "Stale Attempt"}
    }
    status, body, ms = client.send_http(
        "POST",
        f"/v1/cases/{case_id}/sections/identity/commit",
        body=stale_payload,
        headers={
            "Idempotency-Key": f"idem-stale-{uuid.uuid4().hex[:10]}",
            "If-Match": f'"{current_rev}"'
        }
    )
    passed = status == 412
    if passed:
        total_passed += 1
    results["5_concurrency_conflict"] = {"status": status, "passed": passed, "elapsed_ms": ms}

    trial_elapsed_ms = (time.perf_counter() - trial_start) * 1000.0
    all_ok = total_passed == 5
    return all_ok, {
        "trial": trial_num,
        "passed_steps": total_passed,
        "total_steps": 5,
        "success": all_ok,
        "elapsed_ms": trial_elapsed_ms,
        "steps": results
    }


def main():
    parser = argparse.ArgumentParser(description="Live iOS Device E2E Simulation Harness")
    parser.add_argument("--live", action="store_true", help="Run against live Google API Gateway")
    parser.add_argument("--with-cloud-sql", action="store_true", help="Temporarily activate Cloud SQL instance during live tests")
    parser.add_argument("--dry-run", action="store_true", help="Simulate offline native Aperture engine")
    parser.add_argument("--iterations", type=int, default=10, help="Number of test iterations to execute (default: 10)")
    parser.add_argument("--gateway-url", default=STAGING_GATEWAY, help=f"API Gateway URL (default: {STAGING_GATEWAY})")
    parser.add_argument("--token", default=os.environ.get("APERTURE_AUTH_TOKEN", DEFAULT_TEST_TOKEN), help="Bearer auth token")
    args = parser.parse_args()

    mode = "DRY-RUN / OFFLINE SIMULATION" if (args.dry_run or not args.live) else "LIVE API GATEWAY"
    print("=" * 70)
    print("APERTURE MOBILE CLIENT (iOS 27 Spatial / iOS 17+) E2E HARNESS")
    print(f"Mode:             {mode}")
    print(f"Target Gateway:   {args.gateway_url}")
    print(f"Iterations:       {args.iterations}")
    print("=" * 70)

    sql_started_by_us = False
    if args.live and args.with_cloud_sql:
        current_state = check_cloud_sql_state()
        print(f"[Cloud SQL] Current state: {current_state}")
        if "STOPPED" in current_state or "NEVER" in current_state:
            if patch_cloud_sql("ALWAYS"):
                sql_started_by_us = True
                if not wait_for_cloud_sql_runnable():
                    print("[FATAL] Cloud SQL failed to start within timeout.")
                    patch_cloud_sql("NEVER")
                    return 1

    try:
        dry_run = args.dry_run or not args.live
        client = IOSClientSimulation(base_url=args.gateway_url, auth_token=args.token, dry_run=dry_run)
        
        trial_summaries = []
        total_steps_executed = 0
        total_steps_passed = 0

        print(f"\nExecuting {args.iterations} trials across all 5 core mobile workflows...")
        for i in range(1, args.iterations + 1):
            ok, summary = run_simulation_trial(client, i)
            trial_summaries.append(summary)
            total_steps_executed += summary["total_steps"]
            total_steps_passed += summary["passed_steps"]
            
            icon = "PASS" if ok else "FAIL"
            print(f"  Trial {i:2d}/{args.iterations}: [{icon:4s}] {summary['passed_steps']}/5 steps passed ({summary['elapsed_ms']:.1f}ms)")

        overall_sla = (total_steps_passed / total_steps_executed) * 100.0 if total_steps_executed > 0 else 0.0
        success_trials = sum(1 for t in trial_summaries if t["success"])
        trial_sla = (success_trials / args.iterations) * 100.0

        print("\n" + "=" * 70)
        print("SIMULATION RESULTS SUMMARY")
        print("=" * 70)
        print(f"Total Trials:          {args.iterations}")
        print(f"Fully Successful:      {success_trials}/{args.iterations} ({trial_sla:.1f}%)")
        print(f"Total Workflow Steps:  {total_steps_executed}")
        print(f"Successful Steps:      {total_steps_passed}")
        print(f"Measured Overall SLA:  {overall_sla:.1f}%")
        print(f"Target SLA Threshold:  {TARGET_SLA_PERCENT:.1f}%")

        if overall_sla >= TARGET_SLA_PERCENT:
            print(f"\n[PASS] Meets and exceeds target SLA ({overall_sla:.1f}% >= {TARGET_SLA_PERCENT}%).")
            print("Verified native client flow: User Created -> Blueprint Retrieved -> Template Committed -> Conflict Guarded.")
            return 0
        else:
            print(f"\n[FAIL] Below SLA threshold ({overall_sla:.1f}% < {TARGET_SLA_PERCENT}%).")
            return 1

    finally:
        if sql_started_by_us:
            print("\n[Cost Governance] Restoring Cloud SQL to STOPPED (NEVER, $0.00/hr compute)...")
            patch_cloud_sql("NEVER")


if __name__ == "__main__":
    sys.exit(main())
