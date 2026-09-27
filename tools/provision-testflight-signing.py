import os
import subprocess
import sys
import time
import base64
import jwt
import requests
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization, hashes
from cryptography import x509
from cryptography.x509.oid import NameOID

KEY_ID = "VMMAK69ZDV"
ISSUER_ID = "59aa37d6-2ee3-402c-ab08-262ccaf7ffa7"
PRIVATE_KEY_PATH = r"C:\Users\saulp\Downloads\AuthKey_VMMAK69ZDV.p8"
TEAM_ID = "Z25PQY5FWY"
BUNDLE_ID = "app.aperture.mobile"
BUNDLE_ID_RESOURCE_ID = "L579T39S9Y"
ENVIRONMENT_NAME = "internal-testflight"

print("--- 1. Authenticating with App Store Connect API ---")
with open(PRIVATE_KEY_PATH, "r") as f:
    api_private_key = f.read()

now = int(time.time())
payload = {
    "iss": ISSUER_ID,
    "iat": now,
    "exp": now + 1200,
    "aud": "appstoreconnect-v1"
}
headers_jwt = {"kid": KEY_ID, "typ": "JWT"}
token = jwt.encode(payload, api_private_key, algorithm="ES256", headers=headers_jwt)
auth_headers = {
    "Authorization": f"Bearer {token}",
    "Content-Type": "application/json"
}

# Check existing distribution certificates
print("--- 2. Checking existing distribution certificates ---")
r = requests.get("https://api.appstoreconnect.apple.com/v1/certificates?filter[certificateType]=DISTRIBUTION", headers=auth_headers)
if r.status_code == 200:
    existing_certs = r.json().get("data", [])
    for c in existing_certs:
        c_id = c.get("id")
        print(f"Deleting stale distribution certificate: {c_id}")
        requests.delete(f"https://api.appstoreconnect.apple.com/v1/certificates/{c_id}", headers=auth_headers)

# Generate private key for Apple Distribution
print("--- 3. Generating RSA 2048 key pair & CSR ---")
dist_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
key_pem = dist_key.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.NoEncryption()
).decode("utf-8")

csr = (
    x509.CertificateSigningRequestBuilder()
    .subject_name(
        x509.Name([
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Saul Patino"),
            x509.NameAttribute(NameOID.COMMON_NAME, f"Apple Distribution: Saul Patino ({TEAM_ID})"),
        ])
    )
    .sign(dist_key, hashes.SHA256())
)
csr_pem = csr.public_bytes(serialization.Encoding.PEM).decode("utf-8")

# Create certificate via API
print("--- 4. Creating Apple Distribution Certificate via API ---")
body_cert = {
    "data": {
        "type": "certificates",
        "attributes": {
            "certificateType": "DISTRIBUTION",
            "csrContent": csr_pem
        }
    }
}
r = requests.post("https://api.appstoreconnect.apple.com/v1/certificates", headers=auth_headers, json=body_cert)
if r.status_code != 201:
    print(f"Failed to create certificate: {r.status_code} {r.text}")
    sys.exit(1)

cert_data = r.json()["data"]
cert_id = cert_data["id"]
cert_content_b64 = cert_data["attributes"]["certificateContent"]
print(f"Certificate created successfully! ID: {cert_id}")

# Check and remove stale profiles for app.aperture.mobile
print("--- 5. Checking existing profiles ---")
r = requests.get("https://api.appstoreconnect.apple.com/v1/profiles", headers=auth_headers)
if r.status_code == 200:
    for p in r.json().get("data", []):
        if p.get("attributes", {}).get("name") == "LaPluma AppStore Distribution Profile":
            p_id = p.get("id")
            print(f"Deleting stale profile: {p_id}")
            requests.delete(f"https://api.appstoreconnect.apple.com/v1/profiles/{p_id}", headers=auth_headers)

# Create App Store Provisioning Profile
print("--- 6. Creating App Store Provisioning Profile ---")
body_profile = {
    "data": {
        "type": "profiles",
        "attributes": {
            "name": "LaPluma AppStore Distribution Profile",
            "profileType": "IOS_APP_STORE"
        },
        "relationships": {
            "bundleId": {
                "data": {
                    "id": BUNDLE_ID_RESOURCE_ID,
                    "type": "bundleIds"
                }
            },
            "certificates": {
                "data": [
                    {
                        "id": cert_id,
                        "type": "certificates"
                    }
                ]
            }
        }
    }
}
r = requests.post("https://api.appstoreconnect.apple.com/v1/profiles", headers=auth_headers, json=body_profile)
if r.status_code != 201:
    print(f"Failed to create profile: {r.status_code} {r.text}")
    sys.exit(1)

profile_data = r.json()["data"]
profile_id = profile_data["id"]
profile_content_b64 = profile_data["attributes"]["profileContent"]
print(f"App Store Provisioning Profile created successfully! ID: {profile_id}")

# Prepare base64 secrets
key_pem_b64 = base64.b64encode(key_pem.encode("utf-8")).decode("utf-8")

# Set secrets in GitHub environment
print("--- 7. Injecting secrets into GitHub Environment ---")
def set_gh_secret(name: str, value: str):
    cmd = ["gh", "secret", "set", name, "--env", ENVIRONMENT_NAME]
    proc = subprocess.run(cmd, input=value, text=True, capture_output=True)
    if proc.returncode != 0:
        print(f"Error setting {name}: {proc.stderr}")
        sys.exit(1)
    print(f"[OK] Injected secret: {name}")

set_gh_secret("APPLE_DISTRIBUTION_CERT_BASE64", cert_content_b64)
set_gh_secret("APPLE_DISTRIBUTION_KEY_BASE64", key_pem_b64)
set_gh_secret("APPLE_PROVISIONING_PROFILE_BASE64", profile_content_b64)

print("\n=== SUCCESS: Apple Distribution signing assets provisioned and injected! ===")
