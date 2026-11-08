from __future__ import annotations
import hashlib
import html
import ipaddress
import hmac
import asyncio
import json
import logging
import os
import re
import secrets as token_secrets
import shutil
import smtplib
import subprocess
import time
import uuid
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import urlopen
from datetime import date, datetime, timedelta, timezone
from email.message import EmailMessage
from pathlib import Path

import jwt
import psycopg
from fastapi import BackgroundTasks, Depends, FastAPI, File, Form, HTTPException, Request, UploadFile, status
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from fastapi.middleware.cors import CORSMiddleware
from jwt import InvalidTokenError
from pydantic import BaseModel, Field
from psycopg.rows import dict_row

app = FastAPI(title="Nisa API", version="0.7.0")
bearer_scheme = HTTPBearer(auto_error=False)
_verification_cleanup_task = None
_video_validation_slots = asyncio.Semaphore(2)


class RequestBodySizeLimitMiddleware:
    """Cap request bodies before route handlers parse JSON or multipart data."""

    def __init__(self, app):
        self.app = app
        self.default_limit = 1024 * 1024
        self.route_limits = {
            ("POST", "/api/profiles/me/photo"): 9 * 1024 * 1024,
            ("POST", "/api/verification/submit"): 60 * 1024 * 1024,
        }

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        method = scope.get("method", "GET").upper()
        enforce_body_limit = method in {"POST", "PUT", "PATCH"}
        limit = self.route_limits.get((method, scope.get("path", "")), self.default_limit)
        headers = {key.lower(): value for key, value in scope.get("headers", [])}
        raw_length = headers.get(b"content-length")
        if enforce_body_limit and raw_length is not None:
            try:
                if int(raw_length) > limit:
                    await self._reject(send)
                    return
            except ValueError:
                await self._reject(send, status_code=400, detail="Invalid Content-Length")
                return

        total = 0
        exceeded = False
        response_started = False

        async def limited_receive():
            nonlocal total, exceeded
            message = await receive()
            if enforce_body_limit and message.get("type") == "http.request":
                total += len(message.get("body", b""))
                if total > limit:
                    exceeded = True
                    return {"type": "http.disconnect"}
            return message

        async def limited_send(message):
            nonlocal response_started
            if message.get("type") == "http.response.start":
                response_started = True
                if exceeded:
                    await self._reject(send)
                    return
                headers_out = list(message.get("headers", []))
                names = {key.lower() for key, _ in headers_out}
                for key, value in ((b"x-content-type-options", b"nosniff"),
                                   (b"referrer-policy", b"no-referrer"),
                                   (b"x-frame-options", b"DENY")):
                    if key not in names:
                        headers_out.append((key, value))
                if scope.get("path", "").startswith("/api/") and b"cache-control" not in names:
                    headers_out.append((b"cache-control", b"private, no-store"))
                message = {**message, "headers": headers_out}
            if not (exceeded and response_started):
                await send(message)

        try:
            await self.app(scope, limited_receive, limited_send)
        except Exception:
            if not exceeded:
                raise
            if not response_started:
                await self._reject(send)

    @staticmethod
    async def _reject(send, status_code=413, detail="Request body is too large"):
        body = json.dumps({"detail": detail}).encode()
        await send({"type": "http.response.start", "status": status_code,
                    "headers": [(b"content-type", b"application/json"),
                                (b"content-length", str(len(body)).encode()),
                                (b"cache-control", b"no-store")]})
        await send({"type": "http.response.body", "body": body})


app.add_middleware(RequestBodySizeLimitMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        origin.strip()
        for origin in os.getenv(
            "CORS_ALLOWED_ORIGINS",
            "https://nisaesakina.com,https://www.nisaesakina.com,http://localhost:3000,http://localhost:8080",
        ).split(",")
        if origin.strip()
    ],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept"],
)


def read_secret(path: str) -> str:
    return Path(path).read_text().strip()


def jwt_secret() -> str:
    return read_secret(
        os.getenv("JWT_SECRET_FILE", "/run/secrets/jwt_secret")
    )


def database_connection():
    password = read_secret(
        os.getenv(
            "DB_PASSWORD_FILE",
            "/run/secrets/postgres_password",
        )
    )
    return psycopg.connect(
        host=os.getenv("DB_HOST", "postgres"),
        port=int(os.getenv("DB_PORT", "5432")),
        dbname=os.getenv("DB_NAME", "nisa"),
        user=os.getenv("DB_USER", "nisa_app"),
        password=password,
        row_factory=dict_row,
    )


def users_are_blocked(connection, user_a: str, user_b: str) -> bool:
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT EXISTS (
                SELECT 1
                FROM blocks
                WHERE (blocker_id = %s AND blocked_id = %s)
                   OR (blocker_id = %s AND blocked_id = %s)
                UNION ALL
                SELECT 1
                FROM moderation_sanctions
                WHERE sanction_type = 'pair_interaction_restriction'
                  AND revoked_at IS NULL AND expires_at > NOW()
                  AND ((target_user_id = %s AND other_user_id = %s)
                    OR (target_user_id = %s AND other_user_id = %s))
            ) AS blocked
            """,
            (user_a, user_b, user_b, user_a, user_a, user_b, user_b, user_a),
        )
        return bool(cursor.fetchone()["blocked"])


def lock_user_pair(connection, user_a: str, user_b: str) -> None:
    """Serialize blocks against interest and message writes for this pair."""
    first, second = sorted((user_a, user_b))
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT pg_advisory_xact_lock(hashtext(%s), hashtext(%s))",
            (first, second),
        )


def require_active_account(user: dict) -> None:
    if user.get("account_status") != "active":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Complete registration before using this feature",
        )
    restriction_until = user.get("active_temporary_ban_until")
    if restriction_until is not None and restriction_until > datetime.now(timezone.utc):
        notice = user.get("active_temporary_ban_notice") or "Your account is temporarily restricted."
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"{notice} Restriction ends at {restriction_until.isoformat()}.",
        )

def normalize_email(email: str) -> str:
    return email.strip().lower()


def normalize_denylist_identifier(identifier_type: str, value: str) -> str:
    if identifier_type == "email":
        return normalize_email(value)
    if identifier_type == "phone":
        digits = "".join(character for character in value if character.isdigit())
        if not 8 <= len(digits) <= 15:
            raise HTTPException(status_code=400, detail="Enter a phone number with 8 to 15 digits")
        return f"+{digits}"
    raise HTTPException(status_code=400, detail="Choose email or phone")


def denylist_identifier_hmac(identifier_type: str, value: str) -> str:
    normalized = normalize_denylist_identifier(identifier_type, value)
    secret = os.getenv("REGISTRATION_DENYLIST_HMAC_KEY", "").strip()
    secret_file = os.getenv("REGISTRATION_DENYLIST_HMAC_KEY_FILE", "").strip()
    if secret_file:
        secret = read_secret(secret_file)
    if len(secret) < 32:
        # Stable fallback permits existing deployments to operate until a
        # dedicated key is configured; production guidance requires the key.
        secret = jwt_secret()
    return hmac.new(secret.encode(), f"{identifier_type}:{normalized}".encode(), hashlib.sha256).hexdigest()


def identifier_is_denied(cursor, identifier_type: str, value: str) -> bool:
    digest = denylist_identifier_hmac(identifier_type, value)
    cursor.execute(
        """SELECT EXISTS (SELECT 1 FROM registration_identifier_denylist
           WHERE identifier_type = %s AND identifier_hmac = %s) AS denied""",
        (identifier_type, digest),
    )
    return bool(cursor.fetchone()["denied"])


def hash_otp(code: str) -> str:
    return hmac.new(
        jwt_secret().encode(),
        code.encode(),
        hashlib.sha256,
    ).hexdigest()


PASSWORD_HASH_ITERATIONS = 310_000


def make_password_hash(password: str) -> tuple[str, str]:
    salt = token_secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, PASSWORD_HASH_ITERATIONS
    )
    return salt.hex(), digest.hex()


def verify_password_hash(password: str, salt_hex: str, digest_hex: str) -> bool:
    try:
        salt = bytes.fromhex(salt_hex)
        expected = bytes.fromhex(digest_hex)
    except (TypeError, ValueError):
        return False
    if len(salt) != 16 or len(expected) != 32:
        return False
    actual = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt, PASSWORD_HASH_ITERATIONS
    )
    return hmac.compare_digest(actual, expected)


def verified_google_identity(id_token: str) -> dict:
    client_id = os.getenv("GOOGLE_OAUTH_CLIENT_ID", "").strip()
    if not client_id:
        raise HTTPException(
            status_code=503,
            detail="Google sign-in is not configured. Contact support.",
        )
    query = urlencode({"id_token": id_token})
    try:
        with urlopen(
            f"https://oauth2.googleapis.com/tokeninfo?{query}", timeout=8
        ) as response:
            claims = json.loads(response.read().decode("utf-8"))
    except HTTPError:
        raise HTTPException(status_code=401, detail="Google sign-in failed. Please try again.")
    except (URLError, TimeoutError, OSError, json.JSONDecodeError):
        raise HTTPException(status_code=503, detail="Google sign-in failed. Please try again.")

    issuer = claims.get("iss")
    email = normalize_email(str(claims.get("email", "")))
    try:
        expires_at = int(claims.get("exp", "0"))
    except (TypeError, ValueError):
        expires_at = 0
    if (
        claims.get("aud") != client_id
        or issuer not in {"accounts.google.com", "https://accounts.google.com"}
        or claims.get("email_verified") not in {True, "true", "True"}
        or not claims.get("sub")
        or "@" not in email
        or expires_at <= int(time.time())
    ):
        raise HTTPException(status_code=401, detail="Google sign-in failed. Please try again.")
    return claims


def hash_refresh_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def client_address(request: Request) -> str:
    # Production compose exposes the API only on localhost and Cloudflare Tunnel
    # is the public ingress; Cloudflare replaces this header at the edge.
    raw = request.headers.get("cf-connecting-ip", "").strip()
    if not raw and request.client is not None:
        raw = request.client.host
    try:
        return ipaddress.ip_address(raw).compressed
    except ValueError:
        return "unknown-client"


def consume_rate_limit(cursor, scope: str, subject: str, maximum: int, window_seconds: int) -> None:
    subject_hash = hmac.new(
        jwt_secret().encode(),
        f"{scope}\0{subject}".encode(),
        hashlib.sha256,
    ).hexdigest()
    cursor.execute(
        "SELECT pg_advisory_xact_lock(hashtext(%s), hashtext(%s))",
        (scope, subject_hash),
    )
    cursor.execute(
        """SELECT COUNT(*) AS request_count FROM api_rate_limit_events
           WHERE scope = %s AND subject_hash = %s
             AND occurred_at > NOW() - (%s * INTERVAL '1 second')""",
        (scope, subject_hash, window_seconds),
    )
    if cursor.fetchone()["request_count"] >= maximum:
        raise HTTPException(status_code=429, detail="Too many requests. Try again later.")
    cursor.execute(
        "INSERT INTO api_rate_limit_events (scope, subject_hash) VALUES (%s, %s)",
        (scope, subject_hash),
    )


def send_otp_email(email: str, code: str) -> None:
    smtp_host = os.getenv("SMTP_HOST", "smtp.gmail.com")
    smtp_port = int(os.getenv("SMTP_PORT", "587"))
    smtp_username = os.getenv("SMTP_USERNAME")
    smtp_password_file = os.getenv(
        "SMTP_PASSWORD_FILE",
        "/run/secrets/smtp_password",
    )

    if not smtp_username:
        raise RuntimeError("SMTP_USERNAME is not configured")

    smtp_password = read_secret(smtp_password_file)

    message = EmailMessage()
    message["Subject"] = "Your Nisa verification code"
    message["From"] = smtp_username
    message["To"] = email
    message.set_content(
        f"""Assalamu alaikum,

Your Nisa verification code is:

{code}

This code expires in 10 minutes.

If you did not request this code, you can ignore this email.
"""
    )

    with smtplib.SMTP(smtp_host, smtp_port, timeout=30) as server:
        server.starttls()
        server.login(smtp_username, smtp_password)
        server.send_message(message)


def send_password_reset_email_safely(email: str, code: str) -> None:
    try:
        send_otp_email(email, code)
    except Exception:
        logging.exception("Unable to send password reset OTP")


def session_device_metadata(request: Request | None) -> tuple[str, str]:
    platform = "unknown"
    label = "Unknown device"
    if request is not None:
        raw_platform = request.headers.get("x-nisa-device-platform", "").strip().lower()
        if raw_platform in {"android", "ios", "windows", "macos", "linux", "web"}:
            platform = raw_platform
        raw_label = request.headers.get("x-nisa-device-label", "").strip()
        safe_label = re.sub(r"[\x00-\x1f\x7f<>]", "", raw_label)[:64].strip()
        if safe_label:
            label = safe_label
        elif platform != "unknown":
            label = f"{platform.title()} device"
    return label, platform


def issue_tokens(user_id: str, request: Request | None = None) -> dict:
    now = datetime.now(timezone.utc)
    access_expires = now + timedelta(minutes=30)
    refresh_expires = now + timedelta(days=30)
    session_id = uuid.uuid4()
    access_jti = uuid.uuid4().hex
    device_label, device_platform = session_device_metadata(request)

    access_token = jwt.encode(
        {
            "sub": user_id,
            "type": "access",
            "jti": access_jti,
            "sid": str(session_id),
            "iat": now,
            "exp": access_expires,
        },
        jwt_secret(),
        algorithm="HS256",
    )

    refresh_token = token_secrets.token_urlsafe(48)

    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO refresh_tokens (
                    user_id, token_hash, expires_at, session_id,
                    device_label, device_platform, session_created_at, last_used_at
                )
                VALUES (%s, %s, %s, %s, %s, %s, NOW(), NOW())
                """,
                (
                    user_id,
                    hash_refresh_token(refresh_token),
                    refresh_expires,
                    session_id,
                    device_label,
                    device_platform,
                ),
            )

    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "expires_in": 1800,
    }


def revoke_all_user_sessions(user_id: str) -> int:
    """Revoke every refresh chain and access token session for an account."""
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """SELECT COUNT(DISTINCT session_id) AS session_count
                   FROM refresh_tokens
                   WHERE user_id = %s AND revoked_at IS NULL AND expires_at > NOW()""",
                (user_id,),
            )
            session_count = cursor.fetchone()["session_count"]
            cursor.execute(
                """INSERT INTO revoked_auth_sessions (session_id, user_id)
                   SELECT DISTINCT session_id, user_id FROM refresh_tokens
                   WHERE user_id = %s AND revoked_at IS NULL
                   ON CONFLICT (session_id) DO NOTHING""",
                (user_id,),
            )
            cursor.execute(
                """UPDATE refresh_tokens SET revoked_at = NOW()
                   WHERE user_id = %s AND revoked_at IS NULL""",
                (user_id,),
            )
            return session_count


def current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(
        bearer_scheme
    ),
) -> dict:
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required",
        )

    try:
        payload = jwt.decode(
            credentials.credentials,
            jwt_secret(),
            algorithms=["HS256"],
        )
    except InvalidTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired access token",
        )

    if payload.get("type") != "access" or not payload.get("sub") or not payload.get("sid"):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Session token expired; refresh and retry",
        )
    try:
        session_id = str(uuid.UUID(str(payload["sid"]))) if payload.get("sid") else None
    except (ValueError, TypeError, AttributeError):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid session token")

    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """SELECT u.*,
                          EXISTS (SELECT 1 FROM revoked_access_tokens r
                                  WHERE r.jti = %s AND r.expires_at > NOW()) AS access_revoked,
                          EXISTS (SELECT 1 FROM revoked_auth_sessions rs
                                  WHERE rs.session_id = %s::UUID AND rs.user_id = u.id) AS session_revoked,
                          (SELECT s.expires_at FROM moderation_sanctions s
                           WHERE s.target_user_id = u.id
                             AND s.sanction_type = 'temporary_account_ban'
                             AND s.revoked_at IS NULL AND s.expires_at > NOW()
                           ORDER BY s.expires_at DESC LIMIT 1) AS active_temporary_ban_until,
                          (SELECT s.user_notice FROM moderation_sanctions s
                           WHERE s.target_user_id = u.id
                             AND s.sanction_type = 'temporary_account_ban'
                             AND s.revoked_at IS NULL AND s.expires_at > NOW()
                           ORDER BY s.expires_at DESC LIMIT 1) AS active_temporary_ban_notice
                   FROM users u WHERE u.id = %s""",
                (payload.get("jti", ""), session_id, payload["sub"]),
            )
            user = cursor.fetchone()

    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Account not found",
        )

    access_revoked = user.pop("access_revoked", False)
    session_revoked = user.pop("session_revoked", False)
    if access_revoked or session_revoked:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Access session has been signed out")
    user["_session_id"] = session_id
    user["_access_jti"] = payload.get("jti")
    user["_access_expires_at"] = payload.get("exp")

    if user["account_status"] in ("disabled", "deleted"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This account is no longer active",
        )

    return user


class EmailRequest(BaseModel):
    email: str = Field(min_length=3, max_length=320)


class OtpVerification(BaseModel):
    email: str = Field(min_length=3, max_length=320)
    code: str = Field(min_length=6, max_length=6)
    password: str = Field(min_length=10, max_length=128)


class PasswordLogin(BaseModel):
    email: str = Field(min_length=3, max_length=320)
    password: str = Field(min_length=1, max_length=128)


class PasswordReset(BaseModel):
    email: str = Field(min_length=3, max_length=320)
    code: str = Field(min_length=6, max_length=6)
    password: str = Field(min_length=10, max_length=128)


class GoogleTokenRequest(BaseModel):
    id_token: str = Field(min_length=100, max_length=8192)


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=32, max_length=256)


class ProfileUpdate(BaseModel):
    full_name: str = Field(min_length=2, max_length=160)
    date_of_birth: date | None = None
    gender: str | None = Field(default=None, max_length=16)
    country: str = Field(default="Pakistan", min_length=2, max_length=120)
    city: str = Field(default="Karachi", min_length=1, max_length=120)
    height_cm: int | None = Field(default=None, ge=120, le=230)
    marital_status: str = Field(default="Single (Never Married)", min_length=2, max_length=80)
    religion: str = Field(default="Islam", min_length=2, max_length=80)
    sect: str = Field(default="Sunni", min_length=2, max_length=80)
    caste: str | None = Field(default=None, max_length=120)
    education: str | None = Field(default=None, max_length=200)
    education_rank: int | None = Field(default=None, ge=0, le=20)
    profession: str | None = Field(default=None, max_length=200)
    primary_language: str = Field(default="Urdu", min_length=2, max_length=80)
    religious_practice: str = Field(default="Any", min_length=2, max_length=80)
    relocation_preference: str = Field(default="Maybe", min_length=2, max_length=80)


class ApproximateLocationUpdate(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class ReportCreate(BaseModel):
    reason: str = Field(min_length=1, max_length=80)
    details: str = Field(default="", max_length=2000)


class FamilyMemberCreate(BaseModel):
    name: str = Field(min_length=2, max_length=160)
    role: str = Field(min_length=2, max_length=80)
    email: str = Field(default="", max_length=320)
    phone: str = Field(default="", max_length=40)


class FamilyInvitationResponse(BaseModel):
    accept: bool


class VerificationReview(BaseModel):
    decision: str = Field(min_length=3, max_length=32)
    notes: str = Field(default="", max_length=2000)


class ReportModeration(BaseModel):
    decision: str = Field(min_length=1, max_length=24)
    notes: str = Field(default="", max_length=2000)
    outcome_code: str | None = Field(default=None, max_length=40)
    priority: int | None = None


class ReportAppeal(BaseModel):
    details: str = Field(min_length=10, max_length=1000)


class ReportAppealDecision(BaseModel):
    decision: str = Field(min_length=1, max_length=24)
    notes: str = Field(default="", max_length=2000)


class ModerationSanctionCreate(BaseModel):
    target_user_id: str = Field(min_length=1, max_length=160)
    sanction_type: str = Field(min_length=1, max_length=40)
    other_user_id: str | None = Field(default=None, max_length=160)
    report_id: str | None = Field(default=None, max_length=64)
    reason_code: str = Field(min_length=2, max_length=60)
    reason: str = Field(min_length=10, max_length=1000)
    user_notice: str = Field(min_length=10, max_length=500)
    private_note: str = Field(default="", max_length=2000)
    duration_days: int = Field(ge=1, le=30)


class PermanentBanProposalCreate(BaseModel):
    target_user_id: str = Field(min_length=1, max_length=160)
    proposal_id: str | None = Field(default=None, max_length=64)
    report_id: str | None = Field(default=None, max_length=64)
    witness_user_id: str | None = Field(default=None, max_length=160)
    reason: str = Field(min_length=20, max_length=2000)


class AdminModerationDecision(BaseModel):
    decision: str = Field(min_length=1, max_length=24)
    notes: str = Field(min_length=10, max_length=2000)
    deny_email: bool = False
    deny_phone: str | None = Field(default=None, max_length=32)


class AdminDirectBanCreate(BaseModel):
    reason: str = Field(min_length=10, max_length=1000)
    deny_email: bool = False
    deny_phone: str | None = Field(default=None, max_length=32)


class AdminModeratorRoleUpdate(BaseModel):
    reviewer_gender: str = Field(min_length=3, max_length=8)
    can_review_verification: bool = False
    can_review_reports: bool = False
    reason: str = Field(default="", max_length=1000)


class AdminAccountDeleteCreate(BaseModel):
    reason: str = Field(min_length=10, max_length=1000)
    deny_email: bool = False
    deny_phone: str | None = Field(default=None, max_length=32)


class AdminReasonCreate(BaseModel):
    reason: str = Field(min_length=10, max_length=1000)


class SanctionOverrideCreate(BaseModel):
    reason: str = Field(min_length=10, max_length=1000)


class ModeratorRecommendationCreate(BaseModel):
    category: str = Field(min_length=2, max_length=32)
    title: str = Field(min_length=5, max_length=140)
    details: str = Field(min_length=10, max_length=2000)


class ModeratorRecommendationDecision(BaseModel):
    status: str = Field(min_length=3, max_length=24)
    admin_note: str = Field(default="", max_length=2000)


class AdminIdentifierDenylistCreate(BaseModel):
    identifier_type: str = Field(min_length=1, max_length=16)
    value: str = Field(min_length=3, max_length=320)
    reason: str = Field(min_length=10, max_length=1000)


def verification_storage_dir() -> Path:
    path = Path(os.getenv("VERIFICATION_STORAGE_DIR", "/data/private/verification"))
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        path.chmod(0o700)
    except OSError:
        pass
    return path


def profile_photo_storage_dir() -> Path:
    path = Path(os.getenv("PROFILE_PHOTO_STORAGE_DIR", "/data/profile-photos"))
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        path.chmod(0o700)
    except OSError:
        pass
    return path


_PROFILE_PHOTO_NAME = re.compile(r"^[0-9a-f]{32}\.(?:jpg|jpeg|png|webp)$")


def _validate_profile_photo(path: Path) -> str:
    suffix = path.suffix.lower()
    signature = path.read_bytes()[:12]
    valid_signature = (
        (suffix in {".jpg", ".jpeg"} and signature.startswith(b"\xff\xd8\xff"))
        or (suffix == ".png" and signature.startswith(b"\x89PNG\r\n\x1a\n"))
        or (suffix == ".webp" and signature[:4] == b"RIFF" and signature[8:12] == b"WEBP")
    )
    if not valid_signature:
        raise HTTPException(status_code=400, detail="Upload a valid JPEG, PNG, or WebP image")

    ffprobe = shutil.which("ffprobe")
    ffmpeg = shutil.which("ffmpeg")
    if not ffprobe or not ffmpeg:
        raise HTTPException(status_code=503, detail="Image validation is not configured on the server")
    try:
        probe = subprocess.run(
            [ffprobe, "-v", "error", "-select_streams", "v:0",
             "-show_entries", "stream=width,height", "-of", "json", str(path)],
            capture_output=True, text=True, timeout=15, check=False,
        )
        if probe.returncode != 0:
            raise HTTPException(status_code=400, detail="The profile photo could not be read")
        metadata = json.loads(probe.stdout)
        streams = metadata.get("streams", [])
        if not streams:
            raise HTTPException(status_code=400, detail="Upload a readable profile photo")
        width = int(streams[0].get("width", 0))
        height = int(streams[0].get("height", 0))
        if width < 1 or height < 1 or width > 8000 or height > 8000 or width * height > 40_000_000:
            raise HTTPException(status_code=400, detail="The profile photo dimensions are too large")
        decoded = subprocess.run(
            [ffmpeg, "-nostdin", "-v", "error", "-i", str(path),
             "-frames:v", "1", "-vf", "scale=64:64", "-f", "null", "-"],
            capture_output=True, timeout=15, check=False,
        )
        if decoded.returncode != 0:
            raise HTTPException(status_code=400, detail="The profile photo could not be decoded")
        return {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png",
                ".webp": "image/webp"}[suffix]
    except HTTPException:
        raise
    except (OSError, subprocess.TimeoutExpired, ValueError, TypeError, KeyError, json.JSONDecodeError):
        raise HTTPException(status_code=400, detail="The profile photo could not be validated")


async def _save_profile_photo(upload: UploadFile) -> tuple[Path, str]:
    suffix = Path(upload.filename or "").suffix.lower()
    if suffix not in {".jpg", ".jpeg", ".png", ".webp"}:
        await upload.close()
        raise HTTPException(status_code=400, detail="Choose a JPEG, PNG, or WebP profile photo")
    root = profile_photo_storage_dir()
    path = root / f"{uuid.uuid4().hex}{suffix}"
    size = 0
    try:
        with path.open("xb") as destination:
            while chunk := await upload.read(1024 * 1024):
                size += len(chunk)
                if size > 8 * 1024 * 1024:
                    raise HTTPException(status_code=413, detail="Profile photos must be 8 MB or smaller")
                destination.write(chunk)
        if size == 0:
            raise HTTPException(status_code=400, detail="The selected profile photo is empty")
        content_type = _validate_profile_photo(path)
        path.chmod(0o600)
        return path, content_type
    except Exception:
        path.unlink(missing_ok=True)
        raise
    finally:
        await upload.close()


def require_verification_admin(connection, user: dict) -> None:
    require_active_account(user)
    with connection.cursor() as cursor:
        cursor.execute(
            """SELECT 1 FROM verification_admins va
               JOIN moderator_roles mr ON mr.user_id = va.user_id
               WHERE va.user_id = %s AND mr.active AND mr.can_review_verification""",
            (user["id"],),
        )
        if cursor.fetchone() is None:
            raise HTTPException(status_code=403, detail="Verification reviewer access required")


def require_report_moderator(connection, user: dict) -> None:
    require_active_account(user)
    with connection.cursor() as cursor:
        cursor.execute(
            """SELECT 1 FROM report_admins ra
               JOIN moderator_roles mr ON mr.user_id = ra.user_id
               WHERE ra.user_id = %s AND mr.active AND mr.can_review_reports""",
            (user["id"],),
        )
        if cursor.fetchone() is None:
            raise HTTPException(status_code=403, detail="Report moderator access required")


def require_platform_admin(connection, user: dict) -> None:
    require_active_account(user)
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT 1 FROM moderation_platform_admins WHERE user_id = %s",
            (user["id"],),
        )
        if cursor.fetchone() is None:
            raise HTTPException(status_code=403, detail="Platform administrator access required")


def _allowed_upload(filename: str, content_type: str | None, allowed: set[str]) -> str:
    suffix = Path(filename or "").suffix.lower()
    if suffix not in allowed:
        raise HTTPException(status_code=400, detail="Unsupported evidence file type")
    return suffix


async def _save_private_upload(upload: UploadFile, *, max_bytes: int, allowed: set[str], prefix: str) -> Path:
    suffix = _allowed_upload(upload.filename or "", upload.content_type, allowed)
    root = verification_storage_dir()
    path = root / f"{uuid.uuid4().hex}_{prefix}{suffix}"
    size = 0
    try:
        with path.open("xb") as destination:
            while chunk := await upload.read(1024 * 1024):
                size += len(chunk)
                if size > max_bytes:
                    raise HTTPException(status_code=413, detail="Evidence file is too large")
                destination.write(chunk)
        if size == 0:
            raise HTTPException(status_code=400, detail="Evidence file is empty")
        path.chmod(0o600)
        return path
    except Exception:
        path.unlink(missing_ok=True)
        raise
    finally:
        await upload.close()


def _video_duration_seconds(path: Path) -> float:
    ffprobe = shutil.which("ffprobe")
    ffmpeg = shutil.which("ffmpeg")
    if not ffprobe or not ffmpeg:
        raise HTTPException(status_code=503, detail="Video validation is not configured on the server")
    try:
        probe = subprocess.run(
            [ffprobe, "-v", "error", "-select_streams", "v:0",
             "-show_entries", "stream=codec_type", "-show_entries", "format=duration",
             "-of", "json", str(path)],
            capture_output=True, text=True, timeout=15, check=False,
        )
        if probe.returncode != 0:
            raise HTTPException(status_code=400, detail="The video file could not be read")
        metadata = json.loads(probe.stdout)
        streams = metadata.get("streams", [])
        if not any(stream.get("codec_type") == "video" for stream in streams):
            raise HTTPException(status_code=400, detail="Upload a video file with a video track")
        duration = float(metadata["format"]["duration"])
        if not 10 <= duration <= 30:
            raise HTTPException(status_code=400, detail="The confirmation video must be 10 to 30 seconds")
        decoded = subprocess.run(
            [ffmpeg, "-nostdin", "-v", "error", "-i", str(path),
             "-map", "0:v:0", "-frames:v", "1", "-vf", "scale=64:64",
             "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"],
            capture_output=True, timeout=15, check=False,
        )
        if decoded.returncode != 0 or len(decoded.stdout) != 64 * 64 * 3:
            raise HTTPException(status_code=400, detail="The video has no readable video frame")
        return duration
    except HTTPException:
        raise
    except (OSError, subprocess.TimeoutExpired, ValueError, TypeError, KeyError, json.JSONDecodeError):
        raise HTTPException(status_code=400, detail="The video file could not be validated")


def _validate_image_document(path: Path) -> None:
    signature = path.read_bytes()[:8]
    if not (signature.startswith(b"\xff\xd8\xff") or signature == b"\x89PNG\r\n\x1a\n"):
        raise HTTPException(status_code=400, detail="Upload a JPEG or PNG image document")


_PRIVATE_EVIDENCE_NAME = re.compile(
    r"^[0-9a-f]{32}_(?:id|authority|video)\.(?:jpg|jpeg|png|mp4|mov)$"
)


def _delete_private_evidence(filenames: list[str | None]) -> None:
    root = verification_storage_dir().resolve()
    for filename in filenames:
        if not filename or not _PRIVATE_EVIDENCE_NAME.fullmatch(filename):
            continue
        path = (root / filename).resolve()
        if path.parent != root:
            continue
        try:
            path.unlink(missing_ok=True)
        except OSError as error:
            logging.error("Could not remove reviewed verification evidence: %s", error)


def _purge_orphaned_private_evidence() -> None:
    root = verification_storage_dir().resolve()
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT guardian_id_file, authority_proof_file, confirmation_video_file FROM verification_requests"
            )
            referenced = {
                filename
                for row in cursor.fetchall()
                for filename in row.values()
                if filename
            }
    cutoff = time.time() - 24 * 60 * 60
    for path in root.iterdir():
        try:
            if (
                path.is_file()
                and _PRIVATE_EVIDENCE_NAME.fullmatch(path.name)
                and path.name not in referenced
                and path.stat().st_mtime < cutoff
            ):
                path.unlink()
        except OSError as error:
            logging.error("Could not purge orphaned verification evidence: %s", error)


def _purge_expired_security_records() -> None:
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("DELETE FROM api_rate_limit_events WHERE occurred_at < NOW() - INTERVAL '48 hours'")
            cursor.execute("DELETE FROM revoked_access_tokens WHERE expires_at <= NOW()")


def _purge_expired_report_evidence() -> None:
    """Erase report text 180 days after closure; keep minimal case metadata."""
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """WITH expired AS (
                       UPDATE reports
                       SET details = '', appeal_details = '', evidence_redacted_at = NOW(),
                           updated_at = NOW()
                       WHERE evidence_expires_at <= NOW()
                         AND evidence_redacted_at IS NULL
                         AND appeal_status <> 'pending'
                       RETURNING id, reporter_id, reported_user_id
                   ), redacted_notes AS (
                       UPDATE report_moderation_audit
                       SET notes = ''
                       WHERE report_id IN (SELECT id FROM expired) AND notes <> ''
                       RETURNING id
                   )
                   INSERT INTO report_moderation_audit
                       (admin_user_id, actor_type, report_id, reporter_id,
                        reported_user_id, action, metadata)
                   SELECT NULL, 'system', id, reporter_id, reported_user_id,
                          'retention_redact', '{\"retention_days\":180}'::jsonb
                   FROM expired"""
            )


async def _verification_cleanup_loop() -> None:
    while True:
        try:
            await asyncio.to_thread(_purge_orphaned_private_evidence)
        except Exception as error:
            logging.error("Private verification evidence cleanup failed: %s", error)
        try:
            await asyncio.to_thread(_purge_expired_security_records)
        except Exception as error:
            logging.error("Expired API security records cleanup failed: %s", error)
        try:
            await asyncio.to_thread(_purge_expired_report_evidence)
        except Exception as error:
            logging.error("Expired report evidence cleanup failed: %s", error)
        await asyncio.sleep(60 * 60)


@app.on_event("startup")
async def start_verification_cleanup() -> None:
    global _verification_cleanup_task
    _verification_cleanup_task = asyncio.create_task(_verification_cleanup_loop())


@app.on_event("shutdown")
async def stop_verification_cleanup() -> None:
    global _verification_cleanup_task
    if _verification_cleanup_task is not None:
        _verification_cleanup_task.cancel()
        _verification_cleanup_task = None


@app.get("/health")
def health():
    return {
        "ok": True,
        "service": "nisa-api",
        "version": "0.7.0",
    }


@app.get("/health/db")
def database_health():
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1 AS health_value")
            result = cursor.fetchone()["health_value"]

    return {
        "ok": result == 1,
        "database": "postgresql",
    }


@app.post("/api/auth/request-otp")
def request_otp(payload: EmailRequest, request: Request):
    email = normalize_email(payload.email)
    if "@" not in email:
        raise HTTPException(status_code=400, detail="Enter a valid email address")

    # Commit IP throttling separately so a per-email cooldown does not undo it.
    with database_connection() as connection:
        with connection.cursor() as cursor:
            consume_rate_limit(cursor, "otp_request_ip", client_address(request), 20, 60 * 60)

    code = f"{token_secrets.randbelow(1_000_000):06d}"
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=10)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            consume_rate_limit(cursor, "otp_request_email", email, 5, 60 * 60)
            if identifier_is_denied(cursor, "email", email):
                raise HTTPException(status_code=403, detail="This email address is not eligible to register.")
            cursor.execute(
                "SELECT id FROM users WHERE LOWER(BTRIM(email)) = %s LIMIT 1",
                (email,),
            )
            if cursor.fetchone() is not None:
                raise HTTPException(
                    status_code=409,
                    detail="Account already exists. Please sign in.",
                )
            cursor.execute(
                """SELECT COUNT(*) AS request_count FROM email_otps
                   WHERE email = %s AND purpose = 'registration'
                     AND created_at > NOW() - INTERVAL '60 seconds'""",
                (email,),
            )
            if cursor.fetchone()["request_count"] >= 1:
                raise HTTPException(status_code=429, detail="Please wait before requesting another code")
            cursor.execute(
                """INSERT INTO email_otps (email, code_hash, purpose, expires_at)
                   VALUES (%s, %s, 'registration', %s)""",
                (email, hash_otp(code), expires_at),
            )
    try:
        send_otp_email(email, code)
    except Exception:
        logging.exception("Unable to send registration OTP")
        raise HTTPException(status_code=502, detail="Could not send verification email. Try again shortly.")
    return {"ok": True, "message": "Verification code sent"}


@app.post("/api/auth/check-email")
def check_email(payload: EmailRequest, request: Request):
    email = normalize_email(payload.email)
    if "@" not in email:
        raise HTTPException(status_code=400, detail="Enter a valid email address")
    with database_connection() as connection:
        with connection.cursor() as cursor:
            consume_rate_limit(cursor, "email_lookup_ip", client_address(request), 30, 60 * 60)
            consume_rate_limit(cursor, "email_lookup_email", email, 15, 60 * 60)
            cursor.execute(
                "SELECT EXISTS (SELECT 1 FROM users WHERE LOWER(BTRIM(email)) = %s) AS exists",
                (email,),
            )
            exists = bool(cursor.fetchone()["exists"])
    return {"exists": exists}


@app.post("/api/auth/verify-otp")
def verify_otp(payload: OtpVerification, request: Request):
    email = normalize_email(payload.email)
    code = payload.code.strip()
    if len(code) != 6 or not code.isdigit():
        raise HTTPException(status_code=400, detail="Verification code must contain six digits")

    failure: tuple[int, str] | None = None
    user_id: str | None = None
    user = None
    with database_connection() as connection:
        with connection.cursor() as cursor:
            consume_rate_limit(cursor, "otp_verify_ip", client_address(request), 60, 60 * 60)
            consume_rate_limit(cursor, "otp_verify_email", email, 30, 60 * 60)
            if identifier_is_denied(cursor, "email", email):
                failure = (403, "This email address is not eligible to register.")
            if identifier_is_denied(cursor, "email", email):
                failure = (403, "This email address is not eligible to register.")
            cursor.execute(
                """SELECT * FROM email_otps
                   WHERE email = %s AND purpose = 'registration'
                     AND consumed_at IS NULL AND expires_at > NOW()
                   ORDER BY created_at DESC LIMIT 1 FOR UPDATE""",
                (email,),
            )
            otp = cursor.fetchone()
            if failure is not None:
                pass
            elif otp is None:
                failure = (400, "Code expired or not found")
            elif otp["attempts"] >= 5:
                failure = (429, "Too many attempts")
            elif not hmac.compare_digest(otp["code_hash"], hash_otp(code)):
                cursor.execute("UPDATE email_otps SET attempts = attempts + 1 WHERE id = %s", (otp["id"],))
                # Raise only after the transaction commits so the failed attempt is durable.
                failure = (400, "Incorrect verification code")
            else:
                cursor.execute("UPDATE email_otps SET consumed_at = NOW() WHERE id = %s", (otp["id"],))
                cursor.execute(
                    "SELECT * FROM users WHERE LOWER(BTRIM(email)) = %s FOR UPDATE",
                    (email,),
                )
                user = cursor.fetchone()
                if user is not None:
                    failure = (409, "Account already exists. Please sign in.")
                else:
                    user_id = f"email_{uuid.uuid4().hex}"
                    cursor.execute(
                        """INSERT INTO users (id, email, display_name, account_status, registration_step)
                           VALUES (%s, %s, %s, 'draft', 'basic_profile') RETURNING *""",
                        (user_id, email, email.split("@")[0]),
                    )
                    user = cursor.fetchone()
                    salt_hex, digest_hex = make_password_hash(payload.password)
                    cursor.execute(
                        """INSERT INTO api_password_credentials
                           (user_id, salt_hex, password_hash_hex)
                           VALUES (%s, %s, %s)""",
                        (user_id, salt_hex, digest_hex),
                    )
                    cursor.execute(
                        """INSERT INTO auth_identities (user_id, provider, provider_subject)
                           VALUES (%s, 'email', %s) ON CONFLICT DO NOTHING""",
                        (user_id, email),
                    )

    if failure is not None:
        raise HTTPException(status_code=failure[0], detail=failure[1])
    if user_id is None or user is None:
        raise HTTPException(status_code=500, detail="Could not complete sign-in")
    return {"ok": True, "user": user, "tokens": issue_tokens(user_id, request)}


@app.post("/api/auth/password-login")
def password_login(payload: PasswordLogin, request: Request):
    email = normalize_email(payload.email)
    if "@" not in email:
        raise HTTPException(status_code=400, detail="Enter a valid email address")
    with database_connection() as connection:
        with connection.cursor() as cursor:
            consume_rate_limit(cursor, "password_login_ip", client_address(request), 30, 60 * 60)
            consume_rate_limit(cursor, "password_login_email", email, 12, 60 * 60)
            if identifier_is_denied(cursor, "email", email):
                raise HTTPException(status_code=403, detail="This account is not available.")
            cursor.execute(
                """SELECT u.*, c.salt_hex, c.password_hash_hex
                   FROM users u LEFT JOIN api_password_credentials c ON c.user_id = u.id
                   WHERE LOWER(BTRIM(u.email)) = %s LIMIT 1""",
                (email,),
            )
            row = cursor.fetchone()
    password_login_failure(row, payload.password)
    if row["account_status"] in ("disabled", "deleted"):
        raise HTTPException(status_code=403, detail="This account is unavailable.")
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """SELECT user_notice, expires_at FROM moderation_sanctions
                   WHERE target_user_id = %s AND sanction_type = 'temporary_account_ban'
                     AND revoked_at IS NULL AND expires_at > NOW()
                   ORDER BY expires_at DESC LIMIT 1""",
                (row["id"],),
            )
            active_ban = cursor.fetchone()
    if active_ban is not None:
        raise HTTPException(status_code=403, detail=(
            f"{active_ban['user_notice']} Restriction ends at {active_ban['expires_at'].isoformat()}."
        ))
    user_id = row["id"]
    user = {key: value for key, value in row.items() if key not in {"salt_hex", "password_hash_hex"}}
    return {"ok": True, "user": user, "tokens": issue_tokens(user_id, request)}


def password_login_failure(row: dict | None, password: str) -> None:
    """Validate credentials, keeping wrong-password and unknown-user errors alike."""
    if row is None:
        verify_password_hash(password, "00" * 16, "00" * 32)
        raise HTTPException(status_code=401, detail="Email or password is incorrect.")

    salt_hex = row.get("salt_hex")
    digest_hex = row.get("password_hash_hex")
    if not salt_hex or not digest_hex:
        # Do equivalent PBKDF work before returning the migration-specific code.
        # This endpoint is still rate limited; no public account-check endpoint
        # is added. The client uses this code to offer the existing reset flow.
        verify_password_hash(password, "00" * 16, "00" * 32)
        raise HTTPException(
            status_code=409,
            detail={
                "code": "password_setup_required",
                "message": "Set or reset your password to finish setting up sign-in for this account.",
            },
        )
    if not verify_password_hash(password, salt_hex, digest_hex):
        raise HTTPException(status_code=401, detail="Email or password is incorrect.")


@app.post("/api/auth/request-password-reset")
def request_password_reset(
    payload: EmailRequest,
    request: Request,
    background_tasks: BackgroundTasks,
):
    email = normalize_email(payload.email)
    if "@" not in email:
        raise HTTPException(status_code=400, detail="Enter a valid email address")
    code = f"{token_secrets.randbelow(1_000_000):06d}"
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=10)
    account_exists = False
    with database_connection() as connection:
        with connection.cursor() as cursor:
            consume_rate_limit(cursor, "password_reset_ip", client_address(request), 20, 60 * 60)
            consume_rate_limit(cursor, "password_reset_email", email, 5, 60 * 60)
            cursor.execute(
                """SELECT id FROM users
                   WHERE LOWER(BTRIM(email)) = %s AND account_status = 'active'
                   LIMIT 1""",
                (email,),
            )
            account_exists = cursor.fetchone() is not None
            if account_exists:
                cursor.execute(
                    """INSERT INTO email_otps (email, code_hash, purpose, expires_at)
                       VALUES (%s, %s, 'password_reset', %s)""",
                    (email, hash_otp(code), expires_at),
                )
    if account_exists:
        # Deliver after sending the same response for known and unknown emails.
        background_tasks.add_task(send_password_reset_email_safely, email, code)
    return {"ok": True, "message": "If the account exists, a reset code has been sent."}


@app.post("/api/auth/reset-password")
def reset_password(payload: PasswordReset, request: Request):
    email = normalize_email(payload.email)
    code = payload.code.strip()
    if len(code) != 6 or not code.isdigit():
        raise HTTPException(status_code=400, detail="Verification code must contain six digits")
    failure: tuple[int, str] | None = None
    user_id: str | None = None
    user = None
    with database_connection() as connection:
        with connection.cursor() as cursor:
            consume_rate_limit(cursor, "password_reset_verify_ip", client_address(request), 30, 60 * 60)
            consume_rate_limit(cursor, "password_reset_verify_email", email, 10, 60 * 60)
            cursor.execute(
                """SELECT * FROM email_otps WHERE email = %s AND purpose = 'password_reset'
                   AND consumed_at IS NULL AND expires_at > NOW()
                   ORDER BY created_at DESC LIMIT 1 FOR UPDATE""",
                (email,),
            )
            otp = cursor.fetchone()
            if otp is None:
                failure = (400, "Reset code expired or not found.")
            elif otp["attempts"] >= 5:
                failure = (429, "Too many attempts. Try again later.")
            elif not hmac.compare_digest(otp["code_hash"], hash_otp(code)):
                cursor.execute("UPDATE email_otps SET attempts = attempts + 1 WHERE id = %s", (otp["id"],))
                failure = (400, "Incorrect verification code")
            else:
                cursor.execute("UPDATE email_otps SET consumed_at = NOW() WHERE id = %s", (otp["id"],))
                cursor.execute(
                    """SELECT * FROM users
                       WHERE LOWER(BTRIM(email)) = %s AND account_status = 'active'
                       FOR UPDATE""",
                    (email,),
                )
                user = cursor.fetchone()
                if user is None:
                    failure = (400, "Reset code expired or not found.")
                elif user["account_status"] in ("disabled", "deleted"):
                    failure = (403, "This account is unavailable.")
                else:
                    user_id = user["id"]
                    salt_hex, digest_hex = make_password_hash(payload.password)
                    cursor.execute(
                        """INSERT INTO api_password_credentials (user_id, salt_hex, password_hash_hex)
                           VALUES (%s, %s, %s)
                           ON CONFLICT (user_id) DO UPDATE SET
                             salt_hex = EXCLUDED.salt_hex,
                             password_hash_hex = EXCLUDED.password_hash_hex,
                             updated_at = NOW()""",
                        (user_id, salt_hex, digest_hex),
                    )
    if failure is not None:
        raise HTTPException(status_code=failure[0], detail=failure[1])
    if user_id is None or user is None:
        raise HTTPException(status_code=500, detail="Could not reset password")
    revoke_all_user_sessions(user_id)
    return {"ok": True, "user": user, "tokens": issue_tokens(user_id, request)}


@app.post("/api/auth/google")
def google_login(payload: GoogleTokenRequest, request: Request):
    # Apply an IP limit before the tokeninfo request so unauthenticated clients
    # cannot use this endpoint to generate unbounded Google verification calls.
    with database_connection() as connection:
        with connection.cursor() as cursor:
            consume_rate_limit(cursor, "google_login_ip", client_address(request), 30, 60 * 60)
    claims = verified_google_identity(payload.id_token)
    email = normalize_email(str(claims["email"]))
    subject = str(claims["sub"])
    display_name = str(claims.get("name") or email.split("@")[0])[:120]
    with database_connection() as connection:
        with connection.cursor() as cursor:
            consume_rate_limit(cursor, "google_login_email", email, 15, 60 * 60)
            if identifier_is_denied(cursor, "email", email):
                raise HTTPException(status_code=403, detail="This account is not available.")
            cursor.execute(
                """SELECT u.* FROM auth_identities i JOIN users u ON u.id = i.user_id
                   WHERE i.provider = 'google' AND i.provider_subject = %s LIMIT 1 FOR UPDATE OF u""",
                (subject,),
            )
            user = cursor.fetchone()
            if user is None:
                cursor.execute(
                    "SELECT * FROM users WHERE LOWER(BTRIM(email)) = %s LIMIT 1 FOR UPDATE",
                    (email,),
                )
                user = cursor.fetchone()
            if user is None:
                user_id = f"google_{uuid.uuid4().hex}"
                cursor.execute(
                    """INSERT INTO users (id, email, display_name, account_status, registration_step)
                       VALUES (%s, %s, %s, 'draft', 'basic_profile') RETURNING *""",
                    (user_id, email, display_name),
                )
                user = cursor.fetchone()
            if user["account_status"] in ("disabled", "deleted"):
                raise HTTPException(status_code=403, detail="This account is unavailable.")
            cursor.execute(
                """SELECT user_notice, expires_at FROM moderation_sanctions
                   WHERE target_user_id = %s AND sanction_type = 'temporary_account_ban'
                     AND revoked_at IS NULL AND expires_at > NOW()
                   ORDER BY expires_at DESC LIMIT 1""",
                (user["id"],),
            )
            active_ban = cursor.fetchone()
            if active_ban is not None:
                raise HTTPException(status_code=403, detail=(
                    f"{active_ban['user_notice']} Restriction ends at {active_ban['expires_at'].isoformat()}."
                ))
            cursor.execute(
                """INSERT INTO auth_identities (user_id, provider, provider_subject)
                   VALUES (%s, 'google', %s) ON CONFLICT DO NOTHING""",
                (user["id"], subject),
            )
            cursor.execute(
                """SELECT user_id FROM auth_identities
                   WHERE provider = 'google' AND provider_subject = %s""",
                (subject,),
            )
            identity = cursor.fetchone()
            if identity is None or identity["user_id"] != user["id"]:
                raise HTTPException(status_code=409, detail="This Google account is linked to another account.")
    return {"ok": True, "user": user, "tokens": issue_tokens(user["id"], request)}


@app.post("/api/auth/refresh")
def refresh_access_token(payload: RefreshRequest):
    token_hash = hash_refresh_token(payload.refresh_token)
    now = datetime.now(timezone.utc)
    access_expires = now + timedelta(minutes=30)
    refresh_expires = now + timedelta(days=30)
    new_refresh = token_secrets.token_urlsafe(48)
    reuse_detected = False
    invalid = False
    response = None

    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """SELECT rt.user_id, rt.revoked_at, rt.expires_at, rt.session_id,
                          rt.device_label, rt.device_platform, rt.session_created_at,
                          u.account_status,
                          EXISTS (SELECT 1 FROM revoked_auth_sessions rs
                                  WHERE rs.session_id = rt.session_id) AS session_revoked
                   FROM refresh_tokens rt JOIN users u ON u.id = rt.user_id
                   WHERE rt.token_hash = %s FOR UPDATE OF rt""",
                (token_hash,),
            )
            token = cursor.fetchone()
            if (token is None or token["expires_at"] <= now
                    or token["account_status"] in ("disabled", "deleted")
                    or token["session_revoked"]):
                invalid = True
            elif token["revoked_at"] is not None:
                # Reuse of a rotated token revokes any remaining refresh tokens for that account.
                cursor.execute(
                    """INSERT INTO revoked_auth_sessions (session_id, user_id)
                       SELECT DISTINCT session_id, user_id FROM refresh_tokens
                       WHERE user_id = %s AND revoked_at IS NULL
                       ON CONFLICT (session_id) DO NOTHING""",
                    (token["user_id"],),
                )
                cursor.execute(
                    "UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = %s AND revoked_at IS NULL",
                    (token["user_id"],),
                )
                reuse_detected = True
            else:
                access_jti = uuid.uuid4().hex
                access_token = jwt.encode(
                    {"sub": token["user_id"], "type": "access", "jti": access_jti,
                     "sid": str(token["session_id"]), "iat": now, "exp": access_expires},
                    jwt_secret(), algorithm="HS256",
                )
                cursor.execute(
                    "UPDATE refresh_tokens SET revoked_at = NOW(), last_used_at = NOW() WHERE token_hash = %s",
                    (token_hash,),
                )
                cursor.execute(
                    """INSERT INTO refresh_tokens (
                           user_id, token_hash, expires_at, session_id, device_label,
                           device_platform, session_created_at, last_used_at
                       ) VALUES (%s, %s, %s, %s, %s, %s,
                                 %s, NOW())""",
                    (token["user_id"], hash_refresh_token(new_refresh), refresh_expires,
                     token["session_id"], token["device_label"], token["device_platform"],
                     token["session_created_at"]),
                )
                response = {
                    "access_token": access_token,
                    "refresh_token": new_refresh,
                    "token_type": "bearer",
                    "expires_in": 1800,
                }

    if reuse_detected:
        raise HTTPException(status_code=401, detail="Refresh token reuse detected; sign in again")
    if invalid or response is None:
        raise HTTPException(status_code=401, detail="Invalid or expired refresh token")
    return response


@app.post("/api/auth/logout")
def logout(payload: RefreshRequest):
    # Possession of the high-entropy refresh token is sufficient to revoke only
    # its own device session. Keeping logout independent of the short-lived
    # access token also lets clients safely sign out after an access refresh.
    token_hash = hash_refresh_token(payload.refresh_token)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """SELECT user_id, session_id FROM refresh_tokens
                   WHERE token_hash = %s""",
                (token_hash,),
            )
            stored_session = cursor.fetchone()
            if stored_session is not None:
                session_id = stored_session["session_id"]
                cursor.execute(
                    """INSERT INTO revoked_auth_sessions (session_id, user_id)
                       VALUES (%s, %s) ON CONFLICT (session_id) DO NOTHING""",
                    (session_id, stored_session["user_id"]),
                )
                cursor.execute(
                    "UPDATE refresh_tokens SET revoked_at = NOW() WHERE user_id = %s AND session_id = %s",
                    (stored_session["user_id"], session_id),
                )
    return {"ok": True}


@app.get("/api/auth/sessions")
def list_auth_sessions(user: dict = Depends(current_user)):
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """SELECT rt.session_id::TEXT AS session_id,
                          MAX(rt.device_label) AS device_label,
                          MAX(rt.device_platform) AS device_platform,
                          MIN(rt.session_created_at) AS created_at,
                          MAX(rt.last_used_at) AS last_used_at
                   FROM refresh_tokens rt
                   WHERE rt.user_id = %s
                     AND rt.revoked_at IS NULL
                     AND rt.expires_at > NOW()
                     AND NOT EXISTS (
                         SELECT 1 FROM revoked_auth_sessions rs
                         WHERE rs.session_id = rt.session_id
                     )
                   GROUP BY rt.session_id
                   ORDER BY MAX(rt.last_used_at) DESC NULLS LAST""",
                (user["id"],),
            )
            sessions = cursor.fetchall()

    current_session_id = user.get("_session_id")
    # Before the first post-deployment refresh, old access tokens lack a session
    # claim. If only one active refresh chain exists, it is unambiguous.
    if current_session_id is None and len(sessions) == 1:
        current_session_id = sessions[0]["session_id"]
    return {
        "ok": True,
        "sessions": [
            {**session, "is_current": session["session_id"] == str(current_session_id)}
            for session in sessions
        ],
    }


@app.delete("/api/auth/sessions/{session_id}")
def revoke_auth_session(
    session_id: uuid.UUID,
    user: dict = Depends(current_user),
):
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """SELECT EXISTS (
                       SELECT 1 FROM refresh_tokens
                       WHERE user_id = %s AND session_id = %s
                   ) AS session_exists""",
                (user["id"], session_id),
            )
            if not cursor.fetchone()["session_exists"]:
                raise HTTPException(status_code=404, detail="Session not found")
            cursor.execute(
                """INSERT INTO revoked_auth_sessions (session_id, user_id)
                   VALUES (%s, %s) ON CONFLICT (session_id) DO NOTHING""",
                (session_id, user["id"]),
            )
            cursor.execute(
                """UPDATE refresh_tokens SET revoked_at = NOW()
                   WHERE user_id = %s AND session_id = %s AND revoked_at IS NULL""",
                (user["id"], session_id),
            )
    return {"ok": True}


@app.post("/api/auth/sessions/revoke-all")
def revoke_all_auth_sessions(user: dict = Depends(current_user)):
    count = revoke_all_user_sessions(user["id"])
    access_jti = user.get("_access_jti")
    expires_epoch = user.get("_access_expires_at")
    if access_jti and expires_epoch:
        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """INSERT INTO revoked_access_tokens (jti, expires_at)
                       VALUES (%s, %s) ON CONFLICT (jti) DO NOTHING""",
                    (access_jti, datetime.fromtimestamp(expires_epoch, tz=timezone.utc)),
                )
    return {"ok": True, "revoked_sessions": count}


@app.get("/api/me")
def get_current_account(user: dict = Depends(current_user)):
    return {key: value for key, value in user.items() if not key.startswith("_")}


@app.put("/api/profiles/me")
def save_profile(
    payload: ProfileUpdate,
    user: dict = Depends(current_user),
):
    if payload.gender is not None and payload.gender not in {"Male", "Female"}:
        raise HTTPException(status_code=400, detail="Gender must be Male or Female")
    if payload.date_of_birth is not None:
        today = date.today()
        age = today.year - payload.date_of_birth.year - (
            (today.month, today.day)
            < (payload.date_of_birth.month, payload.date_of_birth.day)
        )
        if age < 18 or age > 100:
            raise HTTPException(
                status_code=400,
                detail="Date of birth must represent an age between 18 and 100",
            )
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT date_of_birth, is_verified FROM profiles WHERE user_id = %s FOR UPDATE",
                (user["id"],),
            )
            current_profile = cursor.fetchone()
            if (
                current_profile is not None
                and current_profile["is_verified"]
                and payload.date_of_birth != current_profile["date_of_birth"]
            ):
                raise HTTPException(
                    status_code=400,
                    detail="Date of birth cannot be changed after Parent Verified approval",
                )
            cursor.execute(
                """
                INSERT INTO profiles (
                    user_id,
                    full_name,
                    date_of_birth,
                    gender,
                    country,
                    city,
                    height_cm,
                    marital_status,
                    religion,
                    sect,
                    caste,
                    education,
                    education_rank,
                    profession,
                    primary_language,
                    religious_practice,
                    relocation_preference
                )
                VALUES (
                    %s, %s, %s, %s, %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s, %s, %s, %s
                )
                ON CONFLICT (user_id) DO UPDATE SET
                    full_name = EXCLUDED.full_name,
                    date_of_birth = EXCLUDED.date_of_birth,
                    gender = EXCLUDED.gender,
                    country = EXCLUDED.country,
                    city = EXCLUDED.city,
                    height_cm = EXCLUDED.height_cm,
                    marital_status = EXCLUDED.marital_status,
                    religion = EXCLUDED.religion,
                    sect = EXCLUDED.sect,
                    caste = EXCLUDED.caste,
                    education = EXCLUDED.education,
                    education_rank = EXCLUDED.education_rank,
                    profession = EXCLUDED.profession,
                    primary_language = EXCLUDED.primary_language,
                    religious_practice = EXCLUDED.religious_practice,
                    relocation_preference = EXCLUDED.relocation_preference,
                    updated_at = NOW()
                RETURNING *
                """,
                (
                    user["id"],
                    payload.full_name,
                    payload.date_of_birth,
                    payload.gender,
                    payload.country,
                    payload.city,
                    payload.height_cm,
                    payload.marital_status,
                    payload.religion,
                    payload.sect,
                    payload.caste,
                    payload.education,
                    payload.education_rank,
                    payload.profession,
                    payload.primary_language,
                    payload.religious_practice,
                    payload.relocation_preference,
                ),
            )
            return cursor.fetchone()


@app.get("/api/location/me")
def get_my_location_sharing(user: dict = Depends(current_user)):
    require_active_account(user)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT updated_at FROM profile_locations WHERE user_id = %s",
                (user["id"],),
            )
            row = cursor.fetchone()
    return {"enabled": row is not None, "updated_at": row["updated_at"] if row else None}


@app.put("/api/location/me")
def update_my_approximate_location(
    payload: ApproximateLocationUpdate,
    user: dict = Depends(current_user),
):
    require_active_account(user)
    # Keep only city-scale coordinates. Raw device coordinates are never stored
    # or returned by this API.
    latitude = round(payload.latitude, 2)
    longitude = round(payload.longitude, 2)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO profile_locations (user_id, latitude, longitude, updated_at)
                VALUES (%s, %s, %s, NOW())
                ON CONFLICT (user_id) DO UPDATE SET
                    latitude = EXCLUDED.latitude,
                    longitude = EXCLUDED.longitude,
                    updated_at = NOW()
                """,
                (user["id"], latitude, longitude),
            )
    return {"ok": True, "enabled": True, "approximate": True}


@app.delete("/api/location/me")
def stop_my_location_sharing(user: dict = Depends(current_user)):
    require_active_account(user)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                "DELETE FROM profile_locations WHERE user_id = %s",
                (user["id"],),
            )
    return {"ok": True, "enabled": False}


@app.get("/api/profiles/me")
def get_current_profile(user: dict = Depends(current_user)):
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT u.*, p.*,
                       vr.status AS verification_status,
                       COALESCE(vr.status = 'pending', FALSE) AS verification_pending
                FROM users u
                LEFT JOIN profiles p ON p.user_id = u.id
                LEFT JOIN LATERAL (
                    SELECT status
                    FROM verification_requests
                    WHERE user_id = u.id
                    ORDER BY submitted_at DESC
                    LIMIT 1
                ) vr ON TRUE
                WHERE u.id = %s
                """,
                (user["id"],),
            )
            profile = cursor.fetchone()

    return profile


@app.get("/api/profiles/{profile_id}")
def get_public_profile(profile_id: str, user: dict = Depends(current_user)):
    require_active_account(user)
    with database_connection() as connection:
        if users_are_blocked(connection, user["id"], profile_id):
            raise HTTPException(status_code=404, detail="Profile not found")
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    u.id AS user_id,
                    p.full_name,
                    EXTRACT(YEAR FROM AGE(CURRENT_DATE, p.date_of_birth))::INTEGER AS age,
                    p.gender,
                    p.country,
                    p.city,
                    p.height_cm,
                    p.marital_status,
                    p.education,
                    p.profession,
                    p.religious_practice,
                    p.relocation_preference,
                    p.photo_url,
                    p.is_verified,
                    COALESCE(vr.status = 'pending', FALSE) AS verification_pending
                FROM users u
                INNER JOIN profiles p ON p.user_id = u.id
                LEFT JOIN LATERAL (
                    SELECT status
                    FROM verification_requests
                    WHERE user_id = u.id
                    ORDER BY submitted_at DESC
                    LIMIT 1
                ) vr ON TRUE
                WHERE u.id = %s
                  AND u.account_status = 'active'
                  AND NOT EXISTS (SELECT 1 FROM moderation_sanctions ms
                    WHERE ms.target_user_id = u.id AND ms.sanction_type = 'temporary_account_ban'
                      AND ms.revoked_at IS NULL AND ms.expires_at > NOW())
                  AND p.date_of_birth IS NOT NULL
                  AND EXTRACT(YEAR FROM AGE(CURRENT_DATE, p.date_of_birth)) >= 18
                """,
                (profile_id,),
            )
            profile = cursor.fetchone()
    if profile is None:
        raise HTTPException(status_code=404, detail="Profile not found")
    return profile
class PreferencesUpdate(BaseModel):
    min_age: int = Field(default=18, ge=18, le=100)
    max_age: int = Field(default=60, ge=18, le=100)
    min_height_cm: int | None = Field(default=None, ge=120, le=230)
    max_height_cm: int | None = Field(default=None, ge=120, le=230)
    preferred_country: str = Field(default="Pakistan", min_length=2, max_length=120)
    preferred_city: str = Field(default="Karachi", min_length=1, max_length=120)
    preferred_marital_status: str = Field(default="Single (Never Married)", min_length=2, max_length=80)
    minimum_education: str | None = Field(default=None, max_length=200)
    minimum_education_rank: int | None = Field(default=None, ge=0, le=20)
    preferred_religion: str = Field(default="Islam", min_length=2, max_length=80)
    preferred_religious_practice: str = Field(default="Any", min_length=2, max_length=80)
    relocation_preference: str = Field(default="Maybe", min_length=2, max_length=80)


@app.put("/api/preferences/me")
def save_preferences(
    payload: PreferencesUpdate,
    user: dict = Depends(current_user),
):
    if payload.min_age > payload.max_age:
        raise HTTPException(
            status_code=400,
            detail="Minimum age cannot exceed maximum age",
        )

    if (
        payload.min_height_cm is not None
        and payload.max_height_cm is not None
        and payload.min_height_cm > payload.max_height_cm
    ):
        raise HTTPException(
            status_code=400,
            detail="Minimum height cannot exceed maximum height",
        )

    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO matrimonial_preferences (
                    user_id,
                    min_age,
                    max_age,
                    min_height_cm,
                    max_height_cm,
                    preferred_country,
                    preferred_city,
                    preferred_marital_status,
                    minimum_education,
                    minimum_education_rank,
                    preferred_religion,
                    preferred_religious_practice,
                    relocation_preference
                )
                VALUES (
                    %s, %s, %s, %s, %s, %s, %s,
                    %s, %s, %s, %s, %s, %s
                )
                ON CONFLICT (user_id) DO UPDATE SET
                    min_age = EXCLUDED.min_age,
                    max_age = EXCLUDED.max_age,
                    min_height_cm = EXCLUDED.min_height_cm,
                    max_height_cm = EXCLUDED.max_height_cm,
                    preferred_country = EXCLUDED.preferred_country,
                    preferred_city = EXCLUDED.preferred_city,
                    preferred_marital_status =
                        EXCLUDED.preferred_marital_status,
                    minimum_education = EXCLUDED.minimum_education,
                    minimum_education_rank =
                        EXCLUDED.minimum_education_rank,
                    preferred_religion = EXCLUDED.preferred_religion,
                    preferred_religious_practice =
                        EXCLUDED.preferred_religious_practice,
                    relocation_preference =
                        EXCLUDED.relocation_preference,
                    updated_at = NOW()
                RETURNING *
                """,
                (
                    user["id"],
                    payload.min_age,
                    payload.max_age,
                    payload.min_height_cm,
                    payload.max_height_cm,
                    payload.preferred_country,
                    payload.preferred_city,
                    payload.preferred_marital_status,
                    payload.minimum_education,
                    payload.minimum_education_rank,
                    payload.preferred_religion,
                    payload.preferred_religious_practice,
                    payload.relocation_preference,
                ),
            )
            return cursor.fetchone()


@app.get("/api/preferences/me")
def get_preferences(user: dict = Depends(current_user)):
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT *
                FROM matrimonial_preferences
                WHERE user_id = %s
                """,
                (user["id"],),
            )
            preferences = cursor.fetchone()

    if preferences is None:
        return {
            "user_id": user["id"],
            "min_age": 18,
            "max_age": 60,
            "preferred_country": "Pakistan",
            "preferred_city": "Karachi",
            "preferred_marital_status": "Single (Never Married)",
            "preferred_religion": "Islam",
            "preferred_religious_practice": "Any",
            "relocation_preference": "Maybe",
        }

    return preferences


@app.post("/api/registration/complete")
def complete_registration(user: dict = Depends(current_user)):
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    full_name,
                    date_of_birth,
                    gender,
                    country,
                    city
                FROM profiles
                WHERE user_id = %s
                """,
                (user["id"],),
            )
            profile = cursor.fetchone()

            if profile is None:
                raise HTTPException(
                    status_code=400,
                    detail="Basic profile is incomplete",
                )

            missing_fields = [
                field
                for field in (
                    "full_name",
                    "date_of_birth",
                    "gender",
                    "country",
                    "city",
                )
                if not profile.get(field)
            ]

            if missing_fields:
                raise HTTPException(
                    status_code=400,
                    detail={
                        "message": "Complete the required profile fields",
                        "fields": missing_fields,
                    },
                )

            cursor.execute(
                """
                SELECT
                    date_of_birth <= CURRENT_DATE - INTERVAL '18 years'
                    AS is_adult
                FROM profiles
                WHERE user_id = %s
                """,
                (user["id"],),
            )
            age_check = cursor.fetchone()

            if not age_check["is_adult"]:
                raise HTTPException(
                    status_code=400,
                    detail="User must be at least 18 years old",
                )

            cursor.execute(
                """
                UPDATE users
                SET
                    account_status = 'active',
                    registration_step = 'complete',
                    updated_at = NOW()
                WHERE id = %s
                RETURNING *
                """,
                (user["id"],),
            )
            activated_user = cursor.fetchone()

    return {
        "ok": True,
        "message": "Registration completed",
        "user": activated_user,
    }
def normalize_phone(value: str) -> str:
    value = value.strip()
    prefix = "+" if value.startswith("+") else ""
    digits = "".join(character for character in value if character.isdigit())
    return prefix + digits


@app.get("/api/family/members")
def get_family_members(user: dict = Depends(current_user)):
    require_active_account(user)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    m.id,
                    m.name,
                    m.role,
                    m.email,
                    m.phone,
                    (m.linked_user_id IS NOT NULL) AS is_linked,
                    m.invitation_status,
                    m.created_at,
                    i.id AS invitation_id,
                    COALESCE(i.status, m.invitation_status) AS invitation_status
                FROM family_members m
                LEFT JOIN family_invitations i
                    ON i.family_member_id = m.id
                WHERE m.owner_user_id = %s
                ORDER BY LOWER(m.name), m.created_at
                """,
                (user["id"],),
            )
            return {"ok": True, "members": cursor.fetchall()}


@app.post("/api/family/members")
def create_family_invitation(
    payload: FamilyMemberCreate,
    user: dict = Depends(current_user),
):
    require_active_account(user)
    name = payload.name.strip()
    role = payload.role.strip().lower()
    email = normalize_email(payload.email) if payload.email.strip() else ""
    phone = normalize_phone(payload.phone)
    allowed_roles = {"father", "mother", "brother", "sister", "guardian", "other"}
    if not name or len(name) > 120:
        raise HTTPException(status_code=400, detail="Enter a valid family member name")
    if role not in allowed_roles:
        raise HTTPException(status_code=400, detail="Select a valid family role")
    email_parts = email.split("@") if email else []
    if email and (
        len(email) > 254
        or len(email_parts) != 2
        or not email_parts[0]
        or "." not in email_parts[1]
        or any(character.isspace() for character in email)
    ):
        raise HTTPException(status_code=400, detail="Enter a valid email address")
    phone_digits = sum(character.isdigit() for character in phone)
    if phone and (phone_digits < 7 or phone_digits > 15 or len(phone) > 32):
        raise HTTPException(status_code=400, detail="Enter a valid phone number")
    if not email and not phone:
        raise HTTPException(
            status_code=400,
            detail="Enter an email address or phone number",
        )
    if email and email == normalize_email(user.get("email") or ""):
        raise HTTPException(status_code=400, detail="You cannot invite your own account")

    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT full_name FROM profiles WHERE user_id = %s",
                (user["id"],),
            )
            profile = cursor.fetchone()
            owner_name = (
                profile["full_name"].strip()
                if profile and profile["full_name"]
                else (user.get("display_name") or "Nisa Member").strip()
            )
            cursor.execute(
                """
                INSERT INTO family_members (
                    owner_user_id, name, role, email, phone
                )
                VALUES (%s, %s, %s, %s, %s)
                RETURNING id
                """,
                (user["id"], name, role, email or None, phone or None),
            )
            member_id = cursor.fetchone()["id"]
            cursor.execute(
                """
                INSERT INTO family_invitations (
                    family_member_id, owner_user_id, owner_name,
                    member_name, role, invitee_email, invitee_phone
                )
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                RETURNING id, status, created_at
                """,
                (
                    member_id,
                    user["id"],
                    owner_name or "Nisa Member",
                    name,
                    role,
                    email or None,
                    phone or None,
                ),
            )
            invitation = cursor.fetchone()
            cursor.execute(
                """
                SELECT
                    m.id, m.name, m.role, m.email, m.phone,
                    (m.linked_user_id IS NOT NULL) AS is_linked, m.created_at,
                    %s::uuid AS invitation_id,
                    'pending'::text AS invitation_status
                FROM family_members m WHERE m.id = %s
                """,
                (invitation["id"], member_id),
            )
            member = cursor.fetchone()
    return {"ok": True, "member": member}


@app.delete("/api/family/members/{member_id}")
def remove_family_member(
    member_id: str,
    user: dict = Depends(current_user),
):
    require_active_account(user)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT id FROM family_invitations
                WHERE family_member_id = %s AND owner_user_id = %s
                FOR UPDATE
                """,
                (member_id, user["id"]),
            )
            cursor.execute(
                """
                SELECT id FROM family_members
                WHERE id = %s AND owner_user_id = %s
                """,
                (member_id, user["id"]),
            )
            member = cursor.fetchone()
            if member is None:
                raise HTTPException(status_code=404, detail="Family member not found")
            cursor.execute(
                """
                UPDATE family_invitations
                SET status = 'cancelled', responded_at = NOW()
                WHERE family_member_id = %s AND status <> 'cancelled'
                """,
                (member_id,),
            )
            cursor.execute("DELETE FROM family_members WHERE id = %s", (member_id,))


@app.post("/api/profiles/me/photo")
async def upload_my_profile_photo(
    photo: UploadFile = File(...),
    user: dict = Depends(current_user),
):
    saved_path, _content_type = await _save_profile_photo(photo)
    old_path: str | None = None
    try:
        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT id, file_path
                    FROM profile_photos
                    WHERE user_id = %s AND display_order = 0
                    ORDER BY created_at
                    LIMIT 1
                    FOR UPDATE
                    """,
                    (user["id"],),
                )
                existing = cursor.fetchone()
                if existing is None:
                    cursor.execute(
                        """
                        INSERT INTO profile_photos (user_id, file_path, display_order)
                        SELECT %s, %s, 0
                        WHERE EXISTS (SELECT 1 FROM profiles WHERE user_id = %s)
                        RETURNING id
                        """,
                        (user["id"], saved_path.name, user["id"]),
                    )
                    photo_row = cursor.fetchone()
                else:
                    photo_row = existing
                    old_path = existing["file_path"]
                    cursor.execute(
                        "UPDATE profile_photos SET file_path = %s WHERE id = %s",
                        (saved_path.name, existing["id"]),
                    )
                if photo_row is None:
                    raise HTTPException(status_code=400, detail="Save your basic profile before adding a photo")
                photo_url = f"/api/profile-photos/{photo_row['id']}"
                cursor.execute(
                    "UPDATE profiles SET photo_url = %s, updated_at = NOW() WHERE user_id = %s",
                    (photo_url, user["id"]),
                )
        if old_path and _PROFILE_PHOTO_NAME.fullmatch(old_path):
            try:
                (profile_photo_storage_dir() / old_path).unlink(missing_ok=True)
            except OSError as error:
                logging.error("Could not remove replaced profile photo: %s", error)
        return {"ok": True, "photo_url": photo_url}
    except Exception:
        saved_path.unlink(missing_ok=True)
        raise


@app.get("/api/profile-photos/{photo_id}")
def get_profile_photo(
    photo_id: uuid.UUID,
    user: dict = Depends(current_user),
):
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT ph.file_path, ph.user_id, u.account_status
                FROM profile_photos ph
                JOIN users u ON u.id = ph.user_id
                WHERE ph.id = %s
                """,
                (photo_id,),
            )
            photo = cursor.fetchone()
    if photo is None or not _PROFILE_PHOTO_NAME.fullmatch(photo["file_path"] or ""):
        raise HTTPException(status_code=404, detail="Profile photo not found")
    if photo["user_id"] != user["id"]:
        require_active_account(user)
        if photo["account_status"] != "active":
            raise HTTPException(status_code=404, detail="Profile photo not found")
        with database_connection() as connection:
            if users_are_blocked(connection, user["id"], photo["user_id"]):
                raise HTTPException(status_code=404, detail="Profile photo not found")

    path = profile_photo_storage_dir() / photo["file_path"]
    if not path.is_file():
        raise HTTPException(status_code=404, detail="Profile photo not found")
    media_type = {
        ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
        ".png": "image/png", ".webp": "image/webp",
    }.get(path.suffix.lower())
    return FileResponse(
        path,
        media_type=media_type,
        headers={
            "Cache-Control": "private, max-age=300",
            "X-Content-Type-Options": "nosniff",
        },
    )


@app.get("/api/verification/status")
def verification_status(user: dict = Depends(current_user)):
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT status
                FROM verification_requests
                WHERE user_id = %s
                ORDER BY submitted_at DESC
                LIMIT 1
                """,
                (user["id"],),
            )
            request = cursor.fetchone()
    if request is None:
        return {"status": "not_submitted", "request": None}
    return {"status": request["status"]}


@app.post("/api/verification/submit")
async def submit_verification(
    guardian_name: str = Form(..., min_length=1, max_length=120),
    guardian_relationship: str = Form(...),
    consent_confirmed: str = Form(...),
    reviewer_gender_preference: str = Form(default="any"),
    guardian_id: UploadFile = File(...),
    confirmation_video: UploadFile = File(...),
    authority_proof: UploadFile | None = File(default=None),
    user: dict = Depends(current_user),
):
    # Draft users may submit this optional step during onboarding. Completing
    # registration remains independent, and approval still rechecks eligibility.
    guardian_name = guardian_name.strip()
    relationship = guardian_relationship.strip().lower()
    reviewer_gender_preference = reviewer_gender_preference.strip().lower()
    if reviewer_gender_preference not in {"male", "female", "any"}:
        raise HTTPException(status_code=400, detail="Select male, female, or any reviewer")
    if not guardian_name:
        raise HTTPException(status_code=400, detail="Enter the parent or guardian name")
    if relationship not in {"mother", "father", "wali"}:
        raise HTTPException(status_code=400, detail="Select mother, father, or wali")
    if consent_confirmed.lower() != "true":
        raise HTTPException(status_code=400, detail="Confirm that the guardian consented to this submission")
    if relationship == "wali" and authority_proof is None:
        raise HTTPException(status_code=400, detail="Wali relationship or authority proof is required")
    if relationship != "wali" and authority_proof is not None:
        raise HTTPException(status_code=400, detail="Authority proof is accepted only for a wali")

    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT p.date_of_birth,
                       p.date_of_birth <= CURRENT_DATE - INTERVAL '18 years' AS is_adult,
                       p.full_name, p.gender, p.country, p.city, p.photo_url,
                       EXISTS (SELECT 1 FROM profile_photos ph WHERE ph.user_id = p.user_id) AS has_photo,
                       p.is_verified,
                       EXISTS (SELECT 1 FROM verification_requests vr
                               WHERE vr.user_id = p.user_id AND vr.status = 'pending') AS has_pending
                FROM profiles p WHERE p.user_id = %s
                """,
                (user["id"],),
            )
            profile = cursor.fetchone()
    if profile is None or any(
        not profile[field]
        for field in ("full_name", "date_of_birth", "gender", "country", "city")
    ):
        raise HTTPException(status_code=400, detail="Complete your basic profile first")
    if not profile["is_adult"]:
        raise HTTPException(status_code=400, detail="Verification is available to adults aged 18 and over")
    if not (profile["has_photo"] or profile["photo_url"]):
        raise HTTPException(status_code=400, detail="Add at least one profile photo before verification")
    if profile["is_verified"]:
        raise HTTPException(status_code=409, detail="This profile is already Parent Verified")
    if profile["has_pending"]:
        raise HTTPException(status_code=409, detail="A verification request is already under review")

    with database_connection() as connection:
        with connection.cursor() as cursor:
            consume_rate_limit(cursor, "verification_submit_user", user["id"], 3, 24 * 60 * 60)

    saved: list[Path] = []
    try:
        id_path = await _save_private_upload(
            guardian_id, max_bytes=8 * 1024 * 1024,
            allowed={".jpg", ".jpeg", ".png"}, prefix="id",
        )
        saved.append(id_path)
        _validate_image_document(id_path)
        proof_path = None
        if authority_proof is not None:
            proof_path = await _save_private_upload(
                authority_proof, max_bytes=8 * 1024 * 1024,
                allowed={".jpg", ".jpeg", ".png"}, prefix="authority",
            )
            saved.append(proof_path)
            _validate_image_document(proof_path)
        video_path = await _save_private_upload(
            confirmation_video, max_bytes=40 * 1024 * 1024,
            allowed={".mp4", ".mov"}, prefix="video",
        )
        saved.append(video_path)
        async with _video_validation_slots:
            duration = await asyncio.to_thread(_video_duration_seconds, video_path)
        with database_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    INSERT INTO verification_requests (
                        user_id, guardian_name, guardian_relationship,
                        guardian_id_file, authority_proof_file,
                        confirmation_video_file, video_duration_seconds,
                        consent_confirmed_at, status, reviewer_gender_preference
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, NOW(), 'pending', %s)
                    RETURNING id, status, submitted_at
                    """,
                    (user["id"], guardian_name, relationship, id_path.name,
                     proof_path.name if proof_path else None,
                     video_path.name, duration, reviewer_gender_preference),
                )
                request = cursor.fetchone()
    except psycopg.errors.UniqueViolation:
        for path in saved:
            path.unlink(missing_ok=True)
        raise HTTPException(status_code=409, detail="A verification request is already under review")
    except Exception:
        for path in saved:
            path.unlink(missing_ok=True)
        raise

    return {"ok": True, "request": request}


@app.get("/api/admin/verification/capability")
def verification_admin_capability(user: dict = Depends(current_user)):
    require_active_account(user)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """SELECT 1 FROM verification_admins va JOIN moderator_roles mr ON mr.user_id = va.user_id
                   WHERE va.user_id = %s AND mr.active AND mr.can_review_verification""",
                (user["id"],),
            )
            return {"is_admin": cursor.fetchone() is not None}


@app.get("/api/admin/verification/requests")
def verification_admin_requests(user: dict = Depends(current_user)):
    with database_connection() as connection:
        require_verification_admin(connection, user)
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT vr.id, vr.user_id, vr.guardian_name,
                       vr.guardian_relationship, vr.status, vr.submitted_at,
                       vr.reviewer_gender_preference,
                       vr.reviewed_at, vr.rejection_reason,
                       (vr.authority_proof_file IS NOT NULL) AS has_authority_proof,
                       p.full_name AS applicant_name, u.email AS applicant_email
                FROM verification_requests vr
                JOIN profiles p ON p.user_id = vr.user_id
                JOIN users u ON u.id = vr.user_id
                JOIN moderator_roles mr ON mr.user_id = %s
                WHERE vr.status = 'pending'
                  AND mr.active AND mr.can_review_verification
                  AND (vr.reviewer_gender_preference = 'any'
                       OR vr.reviewer_gender_preference = mr.reviewer_gender)
                ORDER BY vr.submitted_at ASC
                LIMIT 200
                """,
                (user["id"],),
            )
            requests = cursor.fetchall()
            cursor.execute(
                "INSERT INTO verification_admin_audit (admin_user_id, action) VALUES (%s, 'view_queue')",
                (user["id"],),
            )
            return {"requests": requests}


@app.get("/api/admin/verification/requests/{request_id}/evidence/{kind}")
def verification_admin_evidence(
    request_id: str,
    kind: str,
    user: dict = Depends(current_user),
):
    field = {
        "id": "guardian_id_file",
        "video": "confirmation_video_file",
        "authority": "authority_proof_file",
    }.get(kind)
    if field is None:
        raise HTTPException(status_code=404, detail="Evidence not found")
    with database_connection() as connection:
        require_verification_admin(connection, user)
        with connection.cursor() as cursor:
            cursor.execute(
                f"""SELECT vr.{field} AS filename, vr.user_id
                    FROM verification_requests vr
                    JOIN moderator_roles mr ON mr.user_id = %s
                    WHERE vr.id = %s AND mr.active AND mr.can_review_verification
                      AND (vr.reviewer_gender_preference = 'any'
                           OR vr.reviewer_gender_preference = mr.reviewer_gender)""",
                (user["id"], request_id),
            )
            row = cursor.fetchone()
            if row is None or not row["filename"]:
                raise HTTPException(status_code=404, detail="Evidence not found")
            cursor.execute(
                "INSERT INTO verification_admin_audit (admin_user_id, request_id, subject_user_id, action) VALUES (%s, %s, %s, %s)",
                (user["id"], request_id, row["user_id"], f"view_{kind}"),
            )
            _write_moderator_log(cursor, actor_id=user["id"],
                event_type=f"verification_view_{kind}", target_id=row["user_id"],
                reason="Private verification evidence accessed",
                metadata={"request_id": str(request_id), "evidence_kind": kind})
            filename = row["filename"]
    root = verification_storage_dir().resolve()
    path = (root / filename).resolve()
    if path.parent != root or not path.is_file():
        raise HTTPException(status_code=404, detail="Evidence file is unavailable")
    media_type = {
        ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png",
        ".mp4": "video/mp4", ".mov": "video/quicktime",
    }.get(path.suffix.lower(), "application/octet-stream")
    return FileResponse(
        path, media_type=media_type, filename=f"verification_{kind}{path.suffix}",
        headers={"Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff", "Pragma": "no-cache"},
    )


@app.post("/api/admin/verification/requests/{request_id}/review")
def review_verification_request(
    request_id: str,
    payload: VerificationReview,
    user: dict = Depends(current_user),
):
    decision = payload.decision.strip().lower()
    note = payload.notes.strip()
    if decision not in {"approve", "reject", "request_resubmission"}:
        raise HTTPException(status_code=400, detail="Select a valid review decision")
    if decision != "approve" and not note:
        raise HTTPException(status_code=400, detail="Enter a reason for this decision")
    if len(note) > 2000:
        raise HTTPException(status_code=400, detail="Review note is too long")
    status_value = {
        "approve": "approved",
        "reject": "rejected",
        "request_resubmission": "resubmission_required",
    }[decision]
    private_files: list[str | None] = []
    with database_connection() as connection:
        require_verification_admin(connection, user)
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT vr.id, vr.user_id, vr.guardian_id_file, vr.authority_proof_file,
                       vr.confirmation_video_file, vr.reviewer_gender_preference
                FROM verification_requests vr
                JOIN moderator_roles mr ON mr.user_id = %s
                WHERE vr.id = %s AND vr.status = 'pending'
                  AND mr.active AND mr.can_review_verification
                  AND (vr.reviewer_gender_preference = 'any'
                       OR vr.reviewer_gender_preference = mr.reviewer_gender)
                FOR UPDATE OF vr
                """,
                (user["id"], request_id),
            )
            request = cursor.fetchone()
            if request is None:
                raise HTTPException(status_code=409, detail="This request is no longer pending")
            if request["user_id"] == user["id"]:
                raise HTTPException(status_code=403, detail="Reviewers cannot review their own verification request")
            private_files = [
                request["guardian_id_file"],
                request["authority_proof_file"],
                request["confirmation_video_file"],
            ]
            if decision == "approve":
                cursor.execute(
                    """
                    SELECT p.date_of_birth,
                           p.date_of_birth <= CURRENT_DATE - INTERVAL '18 years' AS is_adult,
                           p.full_name, p.gender, p.country, p.city, p.photo_url,
                           EXISTS (SELECT 1 FROM profile_photos ph WHERE ph.user_id = p.user_id) AS has_photo,
                           u.account_status
                    FROM profiles p
                    JOIN users u ON u.id = p.user_id
                    WHERE p.user_id = %s
                    FOR UPDATE OF p, u
                    """,
                    (request["user_id"],),
                )
                applicant = cursor.fetchone()
                if (
                    applicant is None
                    or not applicant["is_adult"]
                    or not applicant["full_name"]
                    or not applicant["gender"]
                    or not applicant["country"]
                    or not applicant["city"]
                    or not (applicant["has_photo"] or applicant["photo_url"])
                    or applicant["account_status"] in ("disabled", "deleted")
                ):
                    raise HTTPException(
                        status_code=409,
                        detail="Applicant no longer meets profile and age requirements; do not approve this request",
                    )
            cursor.execute(
                """
                UPDATE verification_requests
                SET status = %s, reviewed_at = NOW(), reviewed_by = %s,
                    reviewer_notes = %s,
                    rejection_reason = CASE WHEN %s = 'approve' THEN NULL ELSE %s END,
                    guardian_id_file = NULL,
                    authority_proof_file = NULL,
                    confirmation_video_file = NULL
                WHERE id = %s
                """,
                (status_value, user["id"], note or None, decision, note or None, request_id),
            )
            if decision == "approve":
                cursor.execute("UPDATE profiles SET is_verified = TRUE, updated_at = NOW() WHERE user_id = %s", (request["user_id"],))
            elif decision == "reject":
                cursor.execute("UPDATE profiles SET is_verified = FALSE, updated_at = NOW() WHERE user_id = %s", (request["user_id"],))
            cursor.execute(
                "INSERT INTO verification_admin_audit (admin_user_id, request_id, subject_user_id, action, notes) VALUES (%s, %s, %s, %s, %s)",
                (user["id"], request_id, request["user_id"], decision, note or None),
            )
            _write_moderator_log(cursor, actor_id=user["id"],
                event_type=f"verification_{decision}", target_id=request["user_id"],
                reason=note or "Verification review decision",
                metadata={"request_id": str(request_id), "reviewer_gender_preference": request["reviewer_gender_preference"]})
    _delete_private_evidence(private_files)
    return {"ok": True, "status": status_value}
    return {"ok": True}


@app.get("/api/family/invitations/incoming")
def get_incoming_family_invitations(user: dict = Depends(current_user)):
    require_active_account(user)
    email = normalize_email(user.get("email") or "")
    if not email:
        return {"ok": True, "invitations": []}
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT id, owner_name, member_name, role, status, created_at
                FROM family_invitations
                WHERE invitee_email = %s
                  AND status IN ('pending', 'email_confirmed')
                ORDER BY created_at DESC
                """,
                (email,),
            )
            return {"ok": True, "invitations": cursor.fetchall()}


@app.post("/api/family/invitations/{invitation_id}/respond")
def respond_to_family_invitation(
    invitation_id: str,
    payload: FamilyInvitationResponse,
    user: dict = Depends(current_user),
):
    require_active_account(user)
    email = normalize_email(user.get("email") or "")
    if not email:
        raise HTTPException(status_code=403, detail="Your account needs a verified email")
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT id, family_member_id
                FROM family_invitations
                WHERE id = %s AND invitee_email = %s
                  AND status IN ('pending', 'email_confirmed')
                FOR UPDATE
                """,
                (invitation_id, email),
            )
            invitation = cursor.fetchone()
            if invitation is None:
                raise HTTPException(status_code=404, detail="Invitation not found or already answered")
            if invitation["family_member_id"] is None:
                raise HTTPException(status_code=404, detail="Invitation is no longer available")
            status_value = "accepted" if payload.accept else "declined"
            cursor.execute(
                """
                UPDATE family_invitations
                SET status = %s, invitee_user_id = %s, responded_at = NOW()
                WHERE id = %s
                RETURNING id, status, responded_at
                """,
                (status_value, user["id"], invitation_id),
            )
            result = cursor.fetchone()
            cursor.execute(
                """
                UPDATE family_members
                SET linked_user_id = %s, invitation_status = %s
                WHERE id = %s
                """,
                (
                    user["id"] if payload.accept else None,
                    status_value,
                    invitation["family_member_id"],
                ),
            )
    return {"ok": True, "invitation": result}


@app.get("/api/blocks")
def get_my_blocks(user: dict = Depends(current_user)):
    require_active_account(user)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    b.blocked_id,
                    b.created_at,
                    p.full_name AS blocked_name,
                    p.city AS blocked_city,
                    p.country AS blocked_country,
                    p.photo_url AS blocked_photo
                FROM blocks b
                LEFT JOIN profiles p ON p.user_id = b.blocked_id
                WHERE b.blocker_id = %s
                ORDER BY b.created_at DESC
                """,
                (user["id"],),
            )
            return {"ok": True, "blocks": cursor.fetchall()}


@app.post("/api/blocks/{blocked_id}")
def block_user(
    blocked_id: str,
    user: dict = Depends(current_user),
):
    require_active_account(user)
    if blocked_id == user["id"]:
        raise HTTPException(status_code=400, detail="You cannot block yourself")

    with database_connection() as connection:
        lock_user_pair(connection, user["id"], blocked_id)
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT id FROM users WHERE id = %s AND account_status = 'active'",
                (blocked_id,),
            )
            if cursor.fetchone() is None:
                raise HTTPException(status_code=404, detail="User is not available")

            cursor.execute(
                """
                INSERT INTO blocks (blocker_id, blocked_id)
                VALUES (%s, %s)
                ON CONFLICT (blocker_id, blocked_id) DO NOTHING
                RETURNING blocker_id, blocked_id, created_at
                """,
                (user["id"], blocked_id),
            )
            block = cursor.fetchone()
            if block is None:
                cursor.execute(
                    """
                    SELECT blocker_id, blocked_id, created_at
                    FROM blocks WHERE blocker_id = %s AND blocked_id = %s
                    """,
                    (user["id"], blocked_id),
                )
                block = cursor.fetchone()

    # Blocking is intentionally silent to the blocked account.
    return {"ok": True, "block": block}


@app.delete("/api/blocks/{blocked_id}")
def unblock_user(
    blocked_id: str,
    user: dict = Depends(current_user),
):
    require_active_account(user)
    with database_connection() as connection:
        lock_user_pair(connection, user["id"], blocked_id)
        with connection.cursor() as cursor:
            cursor.execute(
                "DELETE FROM blocks WHERE blocker_id = %s AND blocked_id = %s",
                (user["id"], blocked_id),
            )
    return {"ok": True}


@app.get("/api/blocks/{other_user_id}/status")
def block_status(
    other_user_id: str,
    user: dict = Depends(current_user),
):
    require_active_account(user)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    EXISTS (
                        SELECT 1 FROM blocks
                        WHERE blocker_id = %s AND blocked_id = %s
                    ) AS blocked_by_me,
                    EXISTS (
                        SELECT 1 FROM blocks
                        WHERE blocker_id = %s AND blocked_id = %s
                    ) AS blocked_me
                """,
                (user["id"], other_user_id, other_user_id, user["id"]),
            )
            result = cursor.fetchone()
    # Keep block direction private; clients only need to know interactions
    # between this pair are unavailable.
    return {
        "ok": True,
        "is_blocked_between": result["blocked_by_me"] or result["blocked_me"],
    }


@app.post("/api/reports/{reported_user_id}")
def create_user_report(
    reported_user_id: str,
    payload: ReportCreate,
    user: dict = Depends(current_user),
):
    require_active_account(user)
    allowed_reasons = {
        "Spam",
        "Inappropriate profile",
        "Fake or misleading information",
        "Harassment or disrespectful behavior",
        "Scam or suspicious activity",
        "Already married / dishonest status",
        "Other",
    }
    reason = payload.reason.strip()
    details = payload.details.strip()
    if reported_user_id == user["id"]:
        raise HTTPException(status_code=400, detail="You cannot report yourself")
    if reason not in allowed_reasons:
        raise HTTPException(status_code=400, detail="Select a valid report reason")
    if len(details) > 2000:
        raise HTTPException(status_code=400, detail="Report details are too long")
    if reason == "Other" and len(details) < 10:
        raise HTTPException(
            status_code=400,
            detail="Please explain the issue in at least 10 characters",
        )

    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT id FROM users WHERE id = %s AND account_status = 'active'",
                (reported_user_id,),
            )
            if cursor.fetchone() is None:
                raise HTTPException(status_code=404, detail="User is not available")
            cursor.execute(
                "SELECT pg_advisory_xact_lock(hashtext(%s), hashtext('report_submission'))",
                (user["id"],),
            )
            cursor.execute(
                "SELECT 1 FROM reports WHERE reporter_id = %s AND reported_user_id = %s AND status IN ('pending', 'reviewing') LIMIT 1",
                (user["id"], reported_user_id),
            )
            if cursor.fetchone() is not None:
                raise HTTPException(status_code=409, detail="You already have an open report for this member")
            cursor.execute(
                "SELECT COUNT(*) AS report_count FROM reports WHERE reporter_id = %s AND created_at > NOW() - INTERVAL '24 hours'",
                (user["id"],),
            )
            if cursor.fetchone()["report_count"] >= 10:
                raise HTTPException(status_code=429, detail="You have reached the report limit. Try again later.")
            triage_category = {
                "Spam": "spam",
                "Inappropriate profile": "profile_content",
                "Fake or misleading information": "identity_or_fraud",
                "Harassment or disrespectful behavior": "harassment",
                "Scam or suspicious activity": "scam",
                "Already married / dishonest status": "marital_status",
                "Other": "other",
            }[reason]
            priority = 3 if reason in {
                "Spam",
                "Harassment or disrespectful behavior",
                "Scam or suspicious activity",
            } else 2
            cursor.execute(
                """
                INSERT INTO reports (reporter_id, reported_user_id, reason, details,
                                     triage_category, priority)
                VALUES (%s, %s, %s, %s, %s, %s)
                RETURNING id, status, created_at
                """,
                (user["id"], reported_user_id, reason, details, triage_category, priority),
            )
            report = cursor.fetchone()
            cursor.execute(
                "UPDATE reports SET updated_at = NOW() WHERE id = %s",
                (report["id"],),
            )
            cursor.execute(
                """INSERT INTO report_moderation_audit
                   (admin_user_id, actor_type, actor_user_id, report_id,
                    reporter_id, reported_user_id, action, metadata)
                   VALUES (NULL, 'reporter', %s, %s, %s, %s,
                           'report_submitted', '{\"event\":\"report_submitted\"}'::jsonb)""",
                (user["id"], report["id"], user["id"], reported_user_id),
            )
    return {"ok": True, "report": report}


@app.get("/api/reports/mine")
def my_user_reports(user: dict = Depends(current_user)):
    require_active_account(user)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT r.id::text AS id, r.reason, r.status, r.created_at,
                       r.reviewed_at, r.appeal_status, r.appeal_submitted_at,
                       (r.status IN ('resolved', 'dismissed')
                         AND r.appeal_status = 'none'
                         AND r.reviewed_at >= NOW() - INTERVAL '30 days') AS appeal_allowed,
                       CASE
                         WHEN r.appeal_status = 'pending' THEN 'Your appeal is waiting for review.'
                         WHEN r.appeal_status = 'accepted' THEN 'Your appeal was accepted and the report is back under review.'
                         WHEN r.appeal_status = 'rejected' THEN 'Your appeal was reviewed and the case remains closed.'
                         WHEN r.status = 'pending' THEN 'Your report is received and waiting for review.'
                         WHEN r.status = 'reviewing' THEN 'Your report is being reviewed.'
                         WHEN r.status = 'resolved' THEN 'Your report was reviewed. For privacy, action details are not shared.'
                         ELSE 'Your report was reviewed and closed.'
                       END AS next_step,
                       p.full_name AS reported_name
                FROM reports r
                LEFT JOIN profiles p ON p.user_id = r.reported_user_id
                WHERE r.reporter_id = %s
                ORDER BY r.created_at DESC
                LIMIT 100
                """,
                (user["id"],),
            )
            return {"reports": cursor.fetchall()}


@app.get("/api/admin/reports/capability")
def report_admin_capability(user: dict = Depends(current_user)):
    require_active_account(user)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """SELECT 1 FROM report_admins ra JOIN moderator_roles mr ON mr.user_id = ra.user_id
                   WHERE ra.user_id = %s AND mr.active AND mr.can_review_reports""",
                (user["id"],),
            )
            return {"is_admin": cursor.fetchone() is not None}


@app.get("/api/admin/reports")
def report_moderation_queue(
    triage_category: str | None = None,
    user: dict = Depends(current_user),
):
    with database_connection() as connection:
        with connection.cursor() as cursor:
            require_report_moderator(connection, user)
            allowed_categories = {"profile_content", "identity_or_fraud", "harassment", "scam", "marital_status", "spam", "other"}
            if triage_category is not None and triage_category not in allowed_categories:
                raise HTTPException(status_code=400, detail="Select a valid triage category")
            cursor.execute(
                """
                SELECT r.id::text AS id, r.reporter_id, r.reported_user_id,
                       r.reporter_id AS reporter_user_id,
                       r.reported_user_id AS subject_user_id,
                       reporter.full_name AS reporter_name,
                       target.full_name AS reported_name,
                       r.reason, r.details, r.status, r.created_at,
                       r.triage_category, r.priority, r.appeal_status,
                       r.appeal_details, r.appeal_submitted_at,
                       (SELECT s.id::text FROM moderation_sanctions s
                        WHERE s.report_id = r.id
                          AND s.sanction_type = 'temporary_account_ban'
                          AND s.revoked_at IS NULL AND s.expires_at > NOW()
                        ORDER BY s.created_at DESC LIMIT 1) AS active_temporary_ban_id,
                       (SELECT s.id::text FROM moderation_sanctions s
                        WHERE s.report_id = r.id
                          AND s.sanction_type = 'pair_interaction_restriction'
                          AND s.revoked_at IS NULL AND s.expires_at > NOW()
                        ORDER BY s.created_at DESC LIMIT 1) AS active_messaging_restriction_id,
                       ROUND((EXTRACT(EPOCH FROM (NOW() - r.created_at)) / 3600.0)::numeric, 1) AS age_hours,
                       CASE WHEN NOW() - r.created_at >= INTERVAL '72 hours' THEN 'over_72h'
                            WHEN NOW() - r.created_at >= INTERVAL '24 hours' THEN 'over_24h'
                            ELSE 'under_24h' END AS age_bucket
                FROM reports r
                LEFT JOIN profiles reporter ON reporter.user_id = r.reporter_id
                LEFT JOIN profiles target ON target.user_id = r.reported_user_id
                WHERE (r.status IN ('pending', 'reviewing') OR r.appeal_status = 'pending')
                  AND (%s::text IS NULL OR r.triage_category = %s)
                ORDER BY (r.appeal_status = 'pending') DESC,
                         r.priority DESC, r.created_at ASC
                LIMIT 200
                """,
                (triage_category, triage_category),
            )
            reports = cursor.fetchall()
            cursor.execute(
                """INSERT INTO report_moderation_audit
                   (admin_user_id, actor_type, actor_user_id, action)
                   VALUES (%s, 'moderator', %s, 'view_queue')""",
                (user["id"], user["id"]),
            )
            for report in reports:
                cursor.execute(
                    """INSERT INTO report_moderation_audit
                       (admin_user_id, actor_type, actor_user_id, report_id,
                        reporter_id, reported_user_id, action)
                       VALUES (%s, 'moderator', %s, %s, %s, %s, 'view_report')""",
                    (user["id"], user["id"], report["id"], report["reporter_id"], report["reported_user_id"]),
                )
            public_reports = [
                {key: value for key, value in report.items() if key not in {"reporter_id", "reported_user_id"}}
                for report in reports
            ]
            return {"reports": public_reports}


@app.post("/api/admin/reports/{report_id}/decision")
def decide_user_report(
    report_id: str,
    payload: ReportModeration,
    user: dict = Depends(current_user),
):
    decision = payload.decision.strip().lower()
    notes = payload.notes.strip()
    if decision not in {"reviewing", "resolved", "dismissed"}:
        raise HTTPException(status_code=400, detail="Select a valid moderation decision")
    outcome_code = (payload.outcome_code or "").strip().lower()
    valid_outcomes = {"action_taken", "no_violation_found", "insufficient_information", "duplicate", "other"}
    if decision in {"resolved", "dismissed"} and outcome_code not in valid_outcomes:
        raise HTTPException(status_code=400, detail="Select a valid report outcome")
    if payload.priority is not None and payload.priority not in {1, 2, 3}:
        raise HTTPException(status_code=400, detail="Select a valid priority")
    if len(notes) > 2000:
        raise HTTPException(status_code=400, detail="Moderator notes are too long")
    try:
        report_uuid = uuid.UUID(report_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Report not found")

    with database_connection() as connection:
        with connection.cursor() as cursor:
            require_report_moderator(connection, user)
            cursor.execute(
                "SELECT reporter_id, reported_user_id, status, appeal_status FROM reports WHERE id = %s FOR UPDATE",
                (report_uuid,),
            )
            report = cursor.fetchone()
            if report is None:
                raise HTTPException(status_code=404, detail="Report not found")
            if user["id"] in {report["reporter_id"], report["reported_user_id"]}:
                raise HTTPException(status_code=403, detail="You cannot moderate a report involving your own account")
            if report["status"] not in {"pending", "reviewing"} or report["appeal_status"] == "pending":
                raise HTTPException(status_code=409, detail="This report has already been closed")
            cursor.execute(
                """UPDATE reports SET status = %s, reviewed_at = CASE
                       WHEN %s IN ('resolved', 'dismissed') THEN NOW() ELSE NULL END,
                       evidence_expires_at = CASE WHEN %s IN ('resolved', 'dismissed')
                           THEN NOW() + INTERVAL '180 days' ELSE NULL END,
                       reviewed_by = %s, outcome_code = CASE WHEN %s IN ('resolved', 'dismissed')
                           THEN %s ELSE NULL END,
                       priority = COALESCE(%s, priority), updated_at = NOW()
                   WHERE id = %s""",
                (decision, decision, decision, user["id"], decision, outcome_code or None,
                 payload.priority, report_uuid),
            )
            cursor.execute(
                """INSERT INTO report_moderation_audit
                   (admin_user_id, actor_type, actor_user_id, report_id,
                    reporter_id, reported_user_id, action, notes, metadata)
                   VALUES (%s, 'moderator', %s, %s, %s, %s, %s, %s, %s::jsonb)""",
                (user["id"], user["id"], report_uuid, report["reporter_id"], report["reported_user_id"],
                 "set_reviewing" if decision == "reviewing" else ("resolve" if decision == "resolved" else "dismiss"),
                 notes, json.dumps({"outcome_code": outcome_code or None, "priority": payload.priority})),
            )
            _write_moderator_log(cursor, actor_id=user["id"],
                event_type=f"report_{decision}", target_id=report["reported_user_id"],
                report_id=str(report_uuid), reason=notes or f"Report outcome: {outcome_code or 'under review'}",
                metadata={"outcome_code": outcome_code or None, "reporter_id": report["reporter_id"]})
            if decision in {"resolved", "dismissed"}:
                cursor.execute(
                    """INSERT INTO notifications
                       (recipient_id, actor_id, notification_type, title, body, target_screen, target_id)
                       SELECT u.id, NULL, 'report_resolved', 'Report update',
                              'A report you submitted was reviewed. Open My reports to view its status.',
                              'my_reports', %s
                       FROM users u
                       WHERE u.id = %s""",
                    (str(report_uuid), report["reporter_id"]),
                )
    return {"ok": True, "status": decision}


@app.post("/api/reports/{report_id}/appeal")
def appeal_user_report(
    report_id: str,
    payload: ReportAppeal,
    user: dict = Depends(current_user),
):
    require_active_account(user)
    details = payload.details.strip()
    if len(details) < 10 or len(details) > 1000:
        raise HTTPException(status_code=400, detail="Appeal details must be between 10 and 1000 characters")
    try:
        report_uuid = uuid.UUID(report_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Report not found")
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT reporter_id, reported_user_id, status, appeal_status, reviewed_at "
                "FROM reports WHERE id = %s FOR UPDATE",
                (report_uuid,),
            )
            report = cursor.fetchone()
            if report is None or report["reporter_id"] != user["id"]:
                raise HTTPException(status_code=404, detail="Report not found")
            if report["status"] not in {"resolved", "dismissed"} or report["appeal_status"] != "none":
                raise HTTPException(status_code=409, detail="This report is not eligible for an appeal")
            if report["reviewed_at"] is None or report["reviewed_at"] < datetime.now(timezone.utc) - timedelta(days=30):
                raise HTTPException(status_code=409, detail="The 30-day appeal period has ended")
            cursor.execute(
                """UPDATE reports SET appeal_status = 'pending', appeal_details = %s,
                          appeal_submitted_at = NOW(), appeal_reviewed_at = NULL,
                          appeal_reviewed_by = NULL, evidence_expires_at = NULL,
                          updated_at = NOW()
                   WHERE id = %s""",
                (details, report_uuid),
            )
            cursor.execute(
                """INSERT INTO report_moderation_audit
                   (actor_type, actor_user_id, report_id, reporter_id,
                    reported_user_id, action, metadata)
                   VALUES ('reporter', %s, %s, %s, %s, 'appeal_submitted',
                           '{\"appeal_window_days\":30}'::jsonb)""",
                (user["id"], report_uuid, user["id"], report["reported_user_id"]),
            )
    return {"ok": True, "appeal_status": "pending"}


@app.post("/api/admin/reports/{report_id}/appeal-decision")
def decide_report_appeal(
    report_id: str,
    payload: ReportAppealDecision,
    user: dict = Depends(current_user),
):
    require_active_account(user)
    decision = payload.decision.strip().lower()
    notes = payload.notes.strip()
    if decision not in {"reopen", "uphold"}:
        raise HTTPException(status_code=400, detail="Select reopen or uphold")
    if len(notes) > 2000:
        raise HTTPException(status_code=400, detail="Moderator notes are too long")
    try:
        report_uuid = uuid.UUID(report_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Report not found")
    with database_connection() as connection:
        with connection.cursor() as cursor:
            require_report_moderator(connection, user)
            cursor.execute(
                "SELECT reporter_id, reported_user_id, status, appeal_status "
                "FROM reports WHERE id = %s FOR UPDATE",
                (report_uuid,),
            )
            report = cursor.fetchone()
            if report is None:
                raise HTTPException(status_code=404, detail="Report not found")
            if user["id"] in {report["reporter_id"], report["reported_user_id"]}:
                raise HTTPException(status_code=403, detail="You cannot review an appeal involving your own account")
            if report["appeal_status"] != "pending":
                raise HTTPException(status_code=409, detail="This appeal has already been reviewed")
            accepted = decision == "reopen"
            cursor.execute(
                """UPDATE reports SET appeal_status = %s, appeal_reviewed_at = NOW(),
                          appeal_reviewed_by = %s,
                          status = CASE WHEN %s THEN 'reviewing' ELSE status END,
                          reviewed_at = CASE WHEN %s THEN NULL ELSE reviewed_at END,
                          reviewed_by = CASE WHEN %s THEN NULL ELSE reviewed_by END,
                          outcome_code = CASE WHEN %s THEN NULL ELSE outcome_code END,
                          evidence_expires_at = CASE WHEN %s THEN NULL
                              ELSE NOW() + INTERVAL '180 days' END,
                          updated_at = NOW()
                   WHERE id = %s""",
                ("accepted" if accepted else "rejected", user["id"], accepted,
                 accepted, accepted, accepted, accepted, report_uuid),
            )
            cursor.execute(
                """INSERT INTO report_moderation_audit
                   (admin_user_id, actor_type, actor_user_id, report_id,
                    reporter_id, reported_user_id, action, notes, metadata)
                   VALUES (%s, 'moderator', %s, %s, %s, %s, %s, %s, %s::jsonb)""",
                (user["id"], user["id"], report_uuid, report["reporter_id"], report["reported_user_id"],
                 "appeal_accepted" if accepted else "appeal_rejected", notes,
                 json.dumps({"decision": decision})),
            )
            _write_moderator_log(cursor, actor_id=user["id"],
                event_type=f"report_appeal_{decision}", target_id=report["reported_user_id"],
                report_id=str(report_uuid), reason=notes or f"Appeal decision: {decision}")
            cursor.execute(
                """INSERT INTO notifications
                   (recipient_id, actor_id, notification_type, title, body, target_screen, target_id)
                   VALUES (%s, NULL, 'report_appeal_update', 'Report update',
                           'An update is available for your report appeal. Open My reports to view it.',
                           'my_reports', %s)""",
                (report["reporter_id"], str(report_uuid)),
            )
    return {"ok": True, "appeal_status": "accepted" if accepted else "rejected"}


@app.get("/api/admin/reports/metrics")
def report_moderation_metrics(user: dict = Depends(current_user)):
    with database_connection() as connection:
        with connection.cursor() as cursor:
            require_report_moderator(connection, user)
            cursor.execute(
                """SELECT COUNT(*) FILTER (WHERE status IN ('pending', 'reviewing')) AS open_count,
                          COUNT(*) FILTER (WHERE status IN ('pending', 'reviewing')
                                           AND created_at < NOW() - INTERVAL '24 hours') AS older_24h,
                          COUNT(*) FILTER (WHERE status IN ('pending', 'reviewing')
                                           AND created_at < NOW() - INTERVAL '72 hours') AS older_72h,
                          COUNT(*) FILTER (WHERE appeal_status = 'pending') AS pending_appeals,
                          ROUND(AVG(EXTRACT(EPOCH FROM (reviewed_at - created_at)) / 3600.0)
                                FILTER (WHERE reviewed_at IS NOT NULL)::numeric, 1) AS avg_resolution_hours
                   FROM reports"""
            )
            metrics = cursor.fetchone()
            cursor.execute(
                """INSERT INTO report_moderation_audit
                   (admin_user_id, actor_type, actor_user_id, action)
                   VALUES (%s, 'moderator', %s, 'view_queue')""",
                (user["id"], user["id"]),
            )
            return {"metrics": metrics}


def _write_moderator_log(cursor, *, actor_id: str, event_type: str,
                         target_id: str | None = None, report_id: str | None = None,
                         sanction_id: str | None = None, proposal_id: str | None = None,
                         reason: str = "", metadata: dict | None = None) -> None:
    cursor.execute(
        """INSERT INTO moderator_action_logs
           (actor_user_id, target_user_id, report_id, sanction_id, proposal_id,
            event_type, reason, metadata)
           VALUES (%s, %s, %s, %s, %s, %s, %s, %s::jsonb)""",
        (actor_id, target_id, report_id, sanction_id, proposal_id,
         event_type, reason[:2000], json.dumps(metadata or {})),
    )


def _write_admin_user_management_audit(cursor, *, actor_id: str,
                                      action: str, target_id: str | None = None,
                                      reason: str = "",
                                      metadata: dict | None = None) -> None:
    """Store an append-only server-side record without copying searched PII."""
    cursor.execute(
        """INSERT INTO admin_user_management_audit
           (actor_user_id, target_user_id, action, reason, metadata)
           VALUES (%s, %s, %s, %s, %s::jsonb)""",
        (actor_id, target_id, action[:64], reason[:1000],
         json.dumps(metadata or {})),
    )


def _notify_moderation_admins(cursor, *, actor_id: str, title: str,
                              body: str, target_id: str) -> None:
    cursor.execute(
        """INSERT INTO notifications
           (recipient_id, actor_id, notification_type, title, body, target_screen, target_id)
           SELECT ma.user_id, %s, 'moderation_admin_review', %s, %s,
                  'moderator_requests', %s
           FROM moderation_platform_admins ma
           JOIN users u ON u.id = ma.user_id AND u.account_status = 'active'
           ON CONFLICT DO NOTHING""",
        (actor_id, title, body[:500], target_id),
    )


@app.post("/api/admin/moderation/sanctions")
def create_moderation_sanction(payload: ModerationSanctionCreate,
                               user: dict = Depends(current_user)):
    sanction_type = payload.sanction_type.strip().lower()
    reason_code = payload.reason_code.strip().lower()
    reason = payload.reason.strip()
    notice = payload.user_notice.strip()
    private_note = payload.private_note.strip()
    if reason_code not in {"profile_content", "identity_or_fraud", "harassment", "scam", "marital_status", "spam", "other"}:
        raise HTTPException(status_code=400, detail="Select a valid moderation reason category")
    if sanction_type not in {"temporary_account_ban", "pair_interaction_restriction"}:
        raise HTTPException(status_code=400, detail="Select a supported temporary restriction")
    if sanction_type == "pair_interaction_restriction" and not payload.other_user_id:
        raise HTTPException(status_code=400, detail="Select the second account for a messaging restriction")
    if sanction_type == "temporary_account_ban" and payload.other_user_id:
        raise HTTPException(status_code=400, detail="An account suspension cannot include a second account")
    if payload.target_user_id == user["id"]:
        raise HTTPException(status_code=403, detail="Moderators cannot sanction their own account")
    if payload.other_user_id == user["id"]:
        raise HTTPException(status_code=403, detail="A moderator cannot be the other party in a restriction")
    if payload.other_user_id == payload.target_user_id:
        raise HTTPException(status_code=400, detail="Choose two different accounts")
    report_uuid = None
    if payload.report_id:
        try:
            report_uuid = uuid.UUID(payload.report_id)
        except ValueError:
            raise HTTPException(status_code=404, detail="Report not found")
    with database_connection() as connection:
        with connection.cursor() as cursor:
            require_report_moderator(connection, user)
            cursor.execute("SELECT id, account_status FROM users WHERE id = %s FOR UPDATE", (payload.target_user_id,))
            target = cursor.fetchone()
            if target is None or target["account_status"] in {"disabled", "deleted"}:
                raise HTTPException(status_code=404, detail="Account is unavailable")
            if payload.other_user_id:
                cursor.execute("SELECT id FROM users WHERE id = %s AND account_status = 'active'", (payload.other_user_id,))
                if cursor.fetchone() is None:
                    raise HTTPException(status_code=404, detail="Second account is unavailable")
            if report_uuid:
                cursor.execute(
                    """SELECT r.reporter_id, r.reported_user_id,
                              COALESCE(NULLIF(BTRIM(p.full_name), ''),
                                       NULLIF(BTRIM(target.display_name), ''),
                                       'the reported member') AS reported_name
                       FROM reports r
                       LEFT JOIN profiles p ON p.user_id = r.reported_user_id
                       LEFT JOIN users target ON target.id = r.reported_user_id
                       WHERE r.id = %s""",
                    (report_uuid,),
                )
                report = cursor.fetchone()
                if report is None:
                    raise HTTPException(status_code=404, detail="Report not found")
                if payload.target_user_id != report["reported_user_id"]:
                    raise HTTPException(status_code=400, detail="The sanction target must match the reported account")
                if user["id"] in {report["reporter_id"], report["reported_user_id"]}:
                    raise HTTPException(status_code=403, detail="You cannot sanction a report involving your own account")
            cursor.execute(
                """INSERT INTO moderation_sanctions
                   (target_user_id, actor_user_id, sanction_type, other_user_id, report_id,
                    reason_code, user_notice, private_note, expires_at)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s, NOW() + (%s::int * INTERVAL '1 day'))
                   RETURNING id, expires_at""",
                (payload.target_user_id, user["id"], sanction_type, payload.other_user_id,
                 report_uuid, reason_code, notice, private_note, payload.duration_days),
            )
            sanction = cursor.fetchone()
            escalated = False
            ban_count = None
            if sanction_type == "temporary_account_ban":
                cursor.execute(
                    """SELECT COUNT(*) AS n FROM moderation_sanctions
                       WHERE target_user_id = %s AND sanction_type = 'temporary_account_ban'""",
                    (payload.target_user_id,),
                )
                ban_count = cursor.fetchone()["n"]
                if ban_count >= 3:
                    escalated = True
                    cursor.execute("UPDATE moderation_sanctions SET escalation_created = TRUE WHERE id = %s", (sanction["id"],))
                    cursor.execute(
                        """INSERT INTO moderation_admin_cases
                           (target_user_id, case_type, sanction_id, reason)
                           VALUES (%s, 'third_temporary_ban', %s, %s)
                           ON CONFLICT (sanction_id) WHERE case_type = 'third_temporary_ban' DO NOTHING
                           RETURNING id""",
                        (payload.target_user_id, sanction["id"], reason),
                    )
                    admin_case = cursor.fetchone()
                    _notify_moderation_admins(cursor, actor_id=user["id"],
                        title="Moderator escalation requires review",
                        body=f"A member has received temporary account ban {ban_count}; an administrator review is required.",
                        target_id=str(admin_case["id"]) if admin_case else str(sanction["id"]))
            _write_moderator_log(cursor, actor_id=user["id"], event_type=sanction_type,
                target_id=payload.target_user_id, report_id=str(report_uuid) if report_uuid else None,
                sanction_id=str(sanction["id"]), reason=reason,
                metadata={"reason_code": reason_code, "duration_days": payload.duration_days,
                          "escalated_to_admin": escalated, "ban_count": ban_count})
            cursor.execute(
                """INSERT INTO notifications
                   (recipient_id, actor_id, notification_type, title, body, target_screen, target_id)
                   VALUES (%s, %s, 'moderation_restriction', %s, %s, 'profile', %s)""",
                (payload.target_user_id, user["id"],
                 "Temporary account suspension" if sanction_type == "temporary_account_ban" else "Temporary messaging restriction",
                 notice, str(sanction["id"])),
            )
            if report_uuid:
                reported_name = " ".join(
                    str(report["reported_name"] or "the reported member").split()
                )[:120]
                action_label = (
                    "a temporary account suspension"
                    if sanction_type == "temporary_account_ban"
                    else "a temporary messaging restriction"
                )
                reporter_notice = (
                    f"We reviewed your report about {reported_name}. "
                    f"Action taken: {action_label}. "
                    "Open My reports to view its status."
                )
                cursor.execute(
                    """INSERT INTO notifications
                       (recipient_id, actor_id, notification_type, title, body, target_screen, target_id)
                       SELECT reporter_id, %s, 'report_action_taken', 'Report update', %s,
                              'my_reports', %s
                       FROM reports
                       WHERE id = %s AND reporter_id <> %s""",
                    (user["id"], reporter_notice, str(report_uuid), report_uuid,
                     payload.target_user_id),
                )
    return {"ok": True, "sanction_id": str(sanction["id"]),
            "expires_at": sanction["expires_at"], "temporary_ban_count": ban_count,
            "admin_review_required": escalated}


@app.post("/api/admin/moderation/sanctions/{sanction_id}/revoke")
def revoke_moderation_sanction(sanction_id: str, user: dict = Depends(current_user)):
    try:
        sanction_uuid = uuid.UUID(sanction_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Temporary restriction not found")
    with database_connection() as connection:
        with connection.cursor() as cursor:
            require_report_moderator(connection, user)
            cursor.execute(
                """SELECT id, target_user_id, other_user_id, report_id::text,
                          (SELECT reporter_id FROM reports WHERE id = moderation_sanctions.report_id) AS reporter_id,
                          (SELECT COALESCE(NULLIF(BTRIM(p.full_name), ''),
                                           NULLIF(BTRIM(target.display_name), ''),
                                           'the reported member')
                             FROM users target
                             LEFT JOIN profiles p ON p.user_id = target.id
                            WHERE target.id = moderation_sanctions.target_user_id) AS reported_name,
                          sanction_type, revoked_at, expires_at
                   FROM moderation_sanctions WHERE id = %s FOR UPDATE""",
                (sanction_uuid,),
            )
            sanction = cursor.fetchone()
            if sanction is None:
                raise HTTPException(status_code=404, detail="Temporary restriction not found")
            if sanction["sanction_type"] not in {
                "temporary_account_ban", "pair_interaction_restriction"
            } or sanction["report_id"] is None:
                raise HTTPException(status_code=403, detail="This action cannot be lifted from the report queue")
            if sanction["revoked_at"] is not None or sanction["expires_at"] <= datetime.now(timezone.utc):
                raise HTTPException(status_code=409, detail="This temporary restriction is no longer active")
            cursor.execute(
                """UPDATE moderation_sanctions
                   SET revoked_at = NOW(), revoked_by = %s
                   WHERE id = %s""",
                (user["id"], sanction_uuid),
            )
            event_type = f"{sanction['sanction_type']}_revoked"
            _write_moderator_log(
                cursor,
                actor_id=user["id"],
                event_type=event_type,
                target_id=sanction["target_user_id"],
                report_id=sanction["report_id"],
                sanction_id=str(sanction_uuid),
                reason="Moderator lifted the active temporary restriction.",
                metadata={"sanction_type": sanction["sanction_type"]},
            )
            cursor.execute(
                """INSERT INTO notifications
                   (recipient_id, actor_id, notification_type, title, body, target_screen, target_id)
                   VALUES (%s, %s, 'moderation_restriction', 'Temporary restriction lifted',
                           'A moderator has lifted this temporary restriction.', 'profile', %s)""",
                (sanction["target_user_id"], user["id"], sanction["target_user_id"]),
            )
            if (sanction["other_user_id"]
                    and sanction["other_user_id"] != sanction["target_user_id"]
                    and sanction["other_user_id"] != sanction["reporter_id"]):
                cursor.execute(
                    """INSERT INTO notifications
                       (recipient_id, actor_id, notification_type, title, body, target_screen, target_id)
                       VALUES (%s, %s, 'moderation_restriction', 'Temporary restriction lifted',
                               'A moderator has lifted this temporary restriction.', 'profile', %s)""",
                    (sanction["other_user_id"], user["id"], sanction["other_user_id"]),
                )
            reported_name = " ".join(
                str(sanction["reported_name"] or "the reported member").split()
            )[:120]
            lifted_action = (
                "temporary account suspension"
                if sanction["sanction_type"] == "temporary_account_ban"
                else "temporary messaging restriction"
            )
            reporter_notice = (
                f"We reviewed your report about {reported_name}. "
                f"The {lifted_action} was lifted by a moderator. "
                "Open My reports to view its status."
            )
            cursor.execute(
                """INSERT INTO notifications
                   (recipient_id, actor_id, notification_type, title, body, target_screen, target_id)
                   SELECT reporter_id, %s, 'report_action_taken', 'Report update', %s,
                          'my_reports', %s
                   FROM reports
                   WHERE id = %s AND reporter_id <> %s""",
                (user["id"], reporter_notice, sanction["report_id"],
                 sanction["report_id"], sanction["target_user_id"]),
            )
    return {"ok": True, "sanction_id": str(sanction_uuid), "revoked": True}


@app.post("/api/admin/moderation/permanent-ban-proposals")
def propose_permanent_ban(payload: PermanentBanProposalCreate,
                          user: dict = Depends(current_user)):
    reason = payload.reason.strip()
    report_uuid = None
    if payload.report_id:
        try:
            report_uuid = uuid.UUID(payload.report_id)
        except ValueError:
            raise HTTPException(status_code=404, detail="Report not found")
    with database_connection() as connection:
        with connection.cursor() as cursor:
            require_report_moderator(connection, user)
            cursor.execute(
                """SELECT mr.reviewer_gender FROM moderator_roles mr
                   WHERE mr.user_id = %s AND mr.active AND mr.can_review_reports""",
                (user["id"],),
            )
            role = cursor.fetchone()
            if role is None or role["reviewer_gender"] not in {"male", "female"}:
                raise HTTPException(status_code=403, detail="An administrator must assign your moderation gender before you can recommend permanent account action")
            if payload.target_user_id == user["id"]:
                raise HTTPException(status_code=403, detail="You cannot propose final action on your own account")
            cursor.execute("SELECT id FROM users WHERE id = %s AND account_status = 'active' FOR UPDATE", (payload.target_user_id,))
            if cursor.fetchone() is None:
                raise HTTPException(status_code=404, detail="Account is unavailable")
            if report_uuid:
                cursor.execute("SELECT reporter_id, reported_user_id FROM reports WHERE id = %s", (report_uuid,))
                report = cursor.fetchone()
                if report is None or report["reported_user_id"] != payload.target_user_id:
                    raise HTTPException(status_code=404, detail="Matching report not found")
                if user["id"] in {report["reporter_id"], report["reported_user_id"]}:
                    raise HTTPException(status_code=403, detail="You cannot propose action on a report involving your own account")
            witness_id = payload.witness_user_id.strip() if payload.witness_user_id else None
            proposal = None
            if payload.proposal_id:
                try:
                    proposal_uuid = uuid.UUID(payload.proposal_id)
                except ValueError:
                    raise HTTPException(status_code=404, detail="Proposal not found")
                cursor.execute("SELECT * FROM permanent_ban_proposals WHERE id = %s FOR UPDATE", (proposal_uuid,))
                proposal = cursor.fetchone()
                if proposal is None or proposal["target_user_id"] != payload.target_user_id or proposal["status"] != "collecting":
                    raise HTTPException(status_code=409, detail="This proposal is unavailable for voting")
                invited_witness = proposal.get("witness_user_id")
                if invited_witness and invited_witness != user["id"]:
                    raise HTTPException(status_code=403, detail="Only the invited witness can support this request")
                if invited_witness is None and payload.witness_user_id:
                    if proposal["opened_by"] != user["id"]:
                        raise HTTPException(status_code=403, detail="Only the request author can invite a witness")
                    if role["reviewer_gender"] != "female":
                        raise HTTPException(status_code=400, detail="Witness invitation is only needed for a female moderator request")
                    witness_id = payload.witness_user_id.strip()
                    if witness_id in {user["id"], payload.target_user_id}:
                        raise HTTPException(status_code=400, detail="Choose another eligible moderator as witness")
                    cursor.execute("SELECT 1 FROM moderator_roles WHERE user_id = %s AND active AND can_review_reports", (witness_id,))
                    if cursor.fetchone() is None:
                        raise HTTPException(status_code=404, detail="Eligible witness moderator not found")
                    cursor.execute("UPDATE permanent_ban_proposals SET witness_user_id = %s, witness_invited_at = NOW() WHERE id = %s", (witness_id, proposal["id"]))
                    cursor.execute(
                        """INSERT INTO notifications
                           (recipient_id, actor_id, notification_type, title, body, target_screen, target_id)
                           VALUES (%s, %s, 'moderation_witness_request', 'Witness review requested',
                                   'A moderator asked you to review and witness a permanent-action request.',
                                   'moderator_requests', %s)""",
                        (witness_id, user["id"], str(proposal["id"])),
                    )
            else:
                if role["reviewer_gender"] == "female" and not witness_id:
                    raise HTTPException(status_code=400, detail="Select Involve a witness and invite one eligible moderator")
                if witness_id:
                    if witness_id in {user["id"], payload.target_user_id}:
                        raise HTTPException(status_code=400, detail="Choose another eligible moderator as witness")
                    cursor.execute("SELECT 1 FROM moderator_roles WHERE user_id = %s AND active AND can_review_reports", (witness_id,))
                    if cursor.fetchone() is None:
                        raise HTTPException(status_code=404, detail="Eligible witness moderator not found")
                cursor.execute(
                    """SELECT id FROM permanent_ban_proposals
                       WHERE target_user_id = %s AND status = 'collecting'
                       ORDER BY created_at DESC LIMIT 1 FOR UPDATE""",
                    (payload.target_user_id,),
                )
                existing = cursor.fetchone()
                if existing:
                    raise HTTPException(status_code=409, detail=f"An active proposal already exists: {existing['id']}")
                cursor.execute(
                    """INSERT INTO permanent_ban_proposals
                       (target_user_id, opened_by, report_id, reason, witness_user_id,
                        witness_invited_at)
                       VALUES (%s, %s, %s, %s, %s, CASE WHEN %s::text IS NULL THEN NULL ELSE NOW() END)
                       RETURNING *""",
                    (payload.target_user_id, user["id"], report_uuid, reason, witness_id, witness_id),
                )
                proposal = cursor.fetchone()
                if witness_id:
                    cursor.execute(
                        """INSERT INTO notifications
                           (recipient_id, actor_id, notification_type, title, body, target_screen, target_id)
                           VALUES (%s, %s, 'moderation_witness_request', 'Witness review requested',
                                   'A moderator asked you to review and witness a permanent-action request.',
                                   'moderator_requests', %s)""",
                        (witness_id, user["id"], str(proposal["id"])),
                    )
            cursor.execute(
                """INSERT INTO permanent_ban_proposal_votes
                   (proposal_id, moderator_user_id, moderator_gender, vote, reason)
                   VALUES (%s, %s, %s, 'support', %s)
                   ON CONFLICT (proposal_id, moderator_user_id) DO NOTHING""",
                (proposal["id"], user["id"], role["reviewer_gender"], reason),
            )
            if cursor.rowcount == 0:
                raise HTTPException(status_code=409, detail="You have already voted on this proposal")
            cursor.execute(
                """SELECT COUNT(*) FILTER (WHERE moderator_gender = 'male') AS male_votes,
                          COUNT(*) FILTER (WHERE moderator_gender = 'female') AS female_votes
                   FROM permanent_ban_proposal_votes WHERE proposal_id = %s AND vote = 'support'""",
                (proposal["id"],),
            )
            votes = cursor.fetchone()
            qualified = votes["male_votes"] >= 1 or votes["female_votes"] >= 2
            if qualified:
                cursor.execute(
                    """UPDATE permanent_ban_proposals SET status = 'sent_to_admin', qualified_at = NOW()
                       WHERE id = %s AND status = 'collecting'""",
                    (proposal["id"],),
                )
                cursor.execute(
                    """INSERT INTO moderation_admin_cases
                       (target_user_id, case_type, proposal_id, reason)
                       VALUES (%s, 'permanent_ban_proposal', %s, %s)
                       RETURNING id""",
                    (payload.target_user_id, proposal["id"], proposal["reason"]),
                )
                admin_case = cursor.fetchone()
                _notify_moderation_admins(cursor, actor_id=user["id"],
                    title="Permanent account action requested",
                    body="Moderator support thresholds were met. An administrator must review and decide.",
                    target_id=str(admin_case["id"]))
            _write_moderator_log(cursor, actor_id=user["id"], event_type="permanent_ban_vote",
                target_id=payload.target_user_id, report_id=str(report_uuid) if report_uuid else None,
                proposal_id=str(proposal["id"]), reason=reason,
                metadata={"male_support": votes["male_votes"], "female_support": votes["female_votes"],
                          "qualified_for_admin_review": qualified})
    return {"ok": True, "proposal_id": str(proposal["id"]),
            "male_support": votes["male_votes"], "female_support": votes["female_votes"],
            "sent_to_admin": qualified}


@app.get("/api/admin/moderation/logs")
def get_moderator_logs(limit: int = 100, before_id: int | None = None,
                       user: dict = Depends(current_user)):
    limit = min(max(limit, 1), 200)
    with database_connection() as connection:
        require_platform_admin(connection, user)
        with connection.cursor() as cursor:
            cursor.execute(
                """SELECT l.id, l.actor_user_id, actor.display_name AS actor_name,
                          l.target_user_id, target.display_name AS target_name,
                          l.report_id::text, l.sanction_id::text, l.proposal_id::text,
                          l.event_type, l.reason, l.metadata, l.occurred_at,
                          s.expires_at AS sanction_expires_at,
                          s.revoked_at AS sanction_revoked_at,
                          (s.revoked_at IS NULL AND s.expires_at > NOW()) AS sanction_active,
                          o.id AS override_id, o.override_type
                   FROM moderator_action_logs l
                   JOIN users actor ON actor.id = l.actor_user_id
                   LEFT JOIN users target ON target.id = l.target_user_id
                   LEFT JOIN moderation_sanctions s ON s.id = l.sanction_id
                   LEFT JOIN moderation_decision_overrides o ON o.original_log_id = l.id
                   WHERE (%s::bigint IS NULL OR l.id < %s::bigint)
                   ORDER BY l.id DESC LIMIT %s""",
                (before_id, before_id, limit + 1),
            )
            rows = cursor.fetchall()
            has_more = len(rows) > limit
            rows = rows[:limit]
            next_before_id = rows[-1]["id"] if has_more and rows else None
            return {"logs": rows, "next_before_id": next_before_id}


@app.get("/api/admin/moderation/capability")
def moderation_admin_capability(user: dict = Depends(current_user)):
    require_active_account(user)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1 FROM moderation_platform_admins WHERE user_id = %s", (user["id"],))
            return {"is_admin": cursor.fetchone() is not None}


@app.get("/api/admin/moderation/cases")
def get_moderation_admin_cases(user: dict = Depends(current_user)):
    with database_connection() as connection:
        require_platform_admin(connection, user)
        with connection.cursor() as cursor:
            cursor.execute(
                """SELECT c.id::text, c.target_user_id, u.display_name AS target_name,
                          c.case_type, c.sanction_id::text, c.proposal_id::text,
                          c.status, c.reason, c.created_at,
                          (SELECT COUNT(*) FROM permanent_ban_proposal_votes v
                           WHERE v.proposal_id = c.proposal_id AND v.vote = 'support'
                             AND v.moderator_gender = 'male') AS male_support,
                          (SELECT COUNT(*) FROM permanent_ban_proposal_votes v
                           WHERE v.proposal_id = c.proposal_id AND v.vote = 'support'
                             AND v.moderator_gender = 'female') AS female_support
                   FROM moderation_admin_cases c JOIN users u ON u.id = c.target_user_id
                   WHERE c.status = 'pending' ORDER BY c.created_at ASC LIMIT 200"""
            )
            return {"cases": cursor.fetchall()}


@app.post("/api/admin/moderation/cases/{case_id}/decision")
def decide_moderation_admin_case(case_id: str, payload: AdminModerationDecision,
                                 user: dict = Depends(current_user)):
    decision = payload.decision.strip().lower()
    notes = payload.notes.strip()
    if decision not in {"reinstate", "permanent_ban", "delete_account", "dismiss"}:
        raise HTTPException(status_code=400, detail="Select a valid administrator decision")
    try:
        case_uuid = uuid.UUID(case_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Review case not found")
    verification_files_to_delete: list[str | None] = []
    photo_files_to_delete: list[str] = []
    with database_connection() as connection:
        with connection.cursor() as cursor:
            require_platform_admin(connection, user)
            cursor.execute(
                """SELECT c.*, u.email FROM moderation_admin_cases c
                   JOIN users u ON u.id = c.target_user_id
                   WHERE c.id = %s FOR UPDATE OF c, u""",
                (case_uuid,),
            )
            case = cursor.fetchone()
            if case is None or case["status"] != "pending":
                raise HTTPException(status_code=409, detail="This administrator review is already closed")
            if decision in {"permanent_ban", "delete_account"}:
                cursor.execute(
                    "SELECT 1 FROM moderation_platform_admins WHERE user_id = %s",
                    (case["target_user_id"],),
                )
                if cursor.fetchone() is not None:
                    raise HTTPException(
                        status_code=409,
                        detail="Platform administrator accounts require the separate operator recovery process",
                    )
            new_status = {"reinstate": "reinstated", "permanent_ban": "upheld",
                          "delete_account": "account_deleted", "dismiss": "dismissed"}[decision]
            cursor.execute(
                """UPDATE moderation_admin_cases SET status = %s, reviewed_at = NOW(),
                   reviewed_by = %s, decision_note = %s WHERE id = %s""",
                (new_status, user["id"], notes, case_uuid),
            )
            if decision == "reinstate":
                cursor.execute(
                    """UPDATE moderation_sanctions SET revoked_at = NOW(), revoked_by = %s
                       WHERE target_user_id = %s AND revoked_at IS NULL AND expires_at > NOW()""",
                    (user["id"], case["target_user_id"]),
                )
            elif decision in {"permanent_ban", "delete_account"}:
                if payload.deny_email:
                    if not case["email"]:
                        raise HTTPException(status_code=409, detail="There is no email identifier to denylist")
                    cursor.execute(
                        """INSERT INTO registration_identifier_denylist
                           (identifier_type, identifier_hmac, source_admin_case, added_by, reason)
                           VALUES ('email', %s, %s, %s, %s) ON CONFLICT DO NOTHING""",
                        (denylist_identifier_hmac("email", case["email"]), case_uuid, user["id"], notes),
                    )
                if payload.deny_phone:
                    cursor.execute(
                        """INSERT INTO registration_identifier_denylist
                           (identifier_type, identifier_hmac, source_admin_case, added_by, reason)
                           VALUES ('phone', %s, %s, %s, %s) ON CONFLICT DO NOTHING""",
                        (denylist_identifier_hmac("phone", payload.deny_phone), case_uuid, user["id"], notes),
                    )
                if decision == "permanent_ban":
                    cursor.execute("UPDATE users SET account_status = 'disabled' WHERE id = %s", (case["target_user_id"],))
                    cursor.execute("DELETE FROM verification_admins WHERE user_id = %s", (case["target_user_id"],))
                    cursor.execute("DELETE FROM report_admins WHERE user_id = %s", (case["target_user_id"],))
                    cursor.execute("UPDATE moderator_roles SET active = FALSE WHERE user_id = %s", (case["target_user_id"],))
                else:
                    # Privacy-preserving soft deletion keeps only the account key
                    # needed by incident/audit references. Private uploads are erased.
                    cursor.execute("SELECT file_path FROM profile_photos WHERE user_id = %s", (case["target_user_id"],))
                    photo_files_to_delete = [row["file_path"] for row in cursor.fetchall() if row["file_path"]]
                    cursor.execute("DELETE FROM profile_photos WHERE user_id = %s", (case["target_user_id"],))
                    cursor.execute("DELETE FROM matrimonial_preferences WHERE user_id = %s", (case["target_user_id"],))
                    cursor.execute("DELETE FROM profiles WHERE user_id = %s", (case["target_user_id"],))
                    cursor.execute("DELETE FROM verification_admins WHERE user_id = %s", (case["target_user_id"],))
                    cursor.execute("DELETE FROM report_admins WHERE user_id = %s", (case["target_user_id"],))
                    cursor.execute("DELETE FROM moderator_roles WHERE user_id = %s", (case["target_user_id"],))
                    cursor.execute("UPDATE users SET account_status = 'deleted', email = NULL, phone_number = NULL, display_name = 'Deleted member' WHERE id = %s", (case["target_user_id"],))
                    cursor.execute(
                        """SELECT guardian_id_file, authority_proof_file, confirmation_video_file
                           FROM verification_requests WHERE user_id = %s""",
                        (case["target_user_id"],),
                    )
                    for verification in cursor.fetchall():
                        verification_files_to_delete.extend((verification["guardian_id_file"],
                            verification["authority_proof_file"], verification["confirmation_video_file"]))
                    cursor.execute("DELETE FROM verification_requests WHERE user_id = %s", (case["target_user_id"],))
                    if case["email"]:
                        cursor.execute(
                            "DELETE FROM email_otps WHERE email = %s",
                            (normalize_email(case["email"]),),
                        )
                    cursor.execute(
                        "DELETE FROM api_password_credentials WHERE user_id = %s",
                        (case["target_user_id"],),
                    )
                    cursor.execute(
                        "DELETE FROM auth_identities WHERE user_id = %s",
                        (case["target_user_id"],),
                    )
            if case["proposal_id"]:
                cursor.execute(
                    "UPDATE permanent_ban_proposals SET status = %s WHERE id = %s",
                    ("approved" if decision in {"permanent_ban", "delete_account"} else "rejected", case["proposal_id"]),
                )
            _write_moderator_log(cursor, actor_id=user["id"], event_type=f"admin_{decision}",
                target_id=case["target_user_id"], sanction_id=str(case["sanction_id"]) if case["sanction_id"] else None,
                proposal_id=str(case["proposal_id"]) if case["proposal_id"] else None,
                reason=notes, metadata={"admin_case_id": str(case_uuid),
                    "deny_email": payload.deny_email, "deny_phone": bool(payload.deny_phone)})
            _write_admin_user_management_audit(
                cursor, actor_id=user["id"], target_id=case["target_user_id"],
                action=("account_permanently_banned" if decision == "permanent_ban"
                        else "account_deleted" if decision == "delete_account"
                        else "admin_case_decided"),
                reason=notes,
                metadata={"decision": decision, "admin_case_id": str(case_uuid),
                          "deny_email": payload.deny_email,
                          "deny_phone": bool(payload.deny_phone)},
            )
            cursor.execute(
                """INSERT INTO notifications
                   (recipient_id, actor_id, notification_type, title, body, target_screen, target_id)
                   VALUES (%s, %s, 'moderation_admin_decision', 'Account review update', %s, 'profile', %s)""",
                (case["target_user_id"], user["id"],
                 "An administrator completed a final review of your account." if decision != "reinstate"
                 else "An administrator restored your account access.", str(case_uuid)),
            )
    _delete_private_evidence(verification_files_to_delete)
    photo_root = profile_photo_storage_dir().resolve()
    for filename in photo_files_to_delete:
        if _PROFILE_PHOTO_NAME.fullmatch(filename or ""):
            (photo_root / filename).unlink(missing_ok=True)
    revoke_all_user_sessions(case["target_user_id"])
    return {"ok": True, "status": new_status}


@app.get("/api/account/restrictions")
def get_my_account_restrictions(user: dict = Depends(current_user)):
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """SELECT sanction_type, user_notice, reason_code, created_at, expires_at
                   FROM moderation_sanctions WHERE target_user_id = %s
                     AND revoked_at IS NULL AND expires_at > NOW()
                   ORDER BY created_at DESC""",
                (user["id"],),
            )
            restrictions = cursor.fetchall()
    return {"restrictions": restrictions}


class MatchmakerApply(BaseModel):
    business_name: str = Field(min_length=2, max_length=160)
    phone: str = Field(min_length=5, max_length=40)
    notes: str = Field(default="", max_length=2000)


class PartnerProfileImportItem(BaseModel):
    full_name: str = Field(min_length=2, max_length=160)
    gender: str = Field(min_length=4, max_length=6)
    age: int | None = Field(default=None, ge=18, le=100)
    city: str = Field(default="", max_length=120)
    country: str = Field(default="Pakistan", max_length=120)
    height: str = Field(default="", max_length=40)
    marital_status: str = Field(default="", max_length=80)
    education: str = Field(default="", max_length=200)
    profession: str = Field(default="", max_length=200)
    religion: str = Field(default="Islam", max_length=80)
    sect: str = Field(default="", max_length=80)
    phone: str = Field(default="", max_length=40)
    email: str = Field(default="", max_length=320)
    partner_preferences: str = Field(default="", max_length=3000)
    notes: str = Field(default="", max_length=3000)
    external_reference: str = Field(default="", max_length=160)
    source_type: str = Field(default="manual", max_length=40)


class PartnerProfileImportRequest(BaseModel):
    profiles: list[PartnerProfileImportItem] = Field(min_length=1, max_length=250)
    publish: bool = False


class MatchmakerReview(BaseModel):
    decision: str = Field(min_length=7, max_length=9)
    reason: str = Field(default="", max_length=1000)


class MatchmakerIntroductionCreate(BaseModel):
    requester_profile_id: str = Field(min_length=36, max_length=36)
    recipient_profile_id: str = Field(min_length=36, max_length=36)
    message: str = Field(default="", max_length=1000)


class MatchmakerIntroductionResponse(BaseModel):
    decision: str = Field(min_length=8, max_length=8)


def _matchmaker_account(cursor, user_id: str, *, approved: bool = False):
    cursor.execute("SELECT * FROM matchmaker_accounts WHERE user_id = %s", (user_id,))
    account = cursor.fetchone()
    if account is None:
        raise HTTPException(status_code=404, detail="Matchmaker account not found")
    if approved and account["status"] != "approved":
        raise HTTPException(status_code=403, detail="Approved matchmaker access required")
    return account


def _partner_source_hash(item: "PartnerProfileImportItem") -> str:
    normalized = "|".join([
        item.full_name.strip().casefold(), item.gender.strip().casefold(),
        (item.email or "").strip().casefold(), re.sub(r"\\D", "", item.phone or ""),
        (item.city or "").strip().casefold(), str(item.age or ""),
        (item.external_reference or "").strip().casefold(),
    ])
    return hmac.new(jwt_secret().encode(), normalized.encode(), hashlib.sha256).hexdigest()


def _safe_matchmaker_account(account: dict) -> dict:
    return {key: account.get(key) for key in (
        "id", "business_name", "phone", "notes", "status", "trust_score",
        "review_reason", "reviewed_at", "created_at", "updated_at"
    )}


@app.get("/api/matchmakers/me")
def get_my_matchmaker_account(user: dict = Depends(current_user)):
    require_active_account(user)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT * FROM matchmaker_accounts WHERE user_id = %s", (user["id"],))
            account = cursor.fetchone()
            if account is None:
                raise HTTPException(status_code=404, detail="Matchmaker account not found")
            return _safe_matchmaker_account(account)


@app.post("/api/matchmakers/apply", status_code=201)
def apply_as_matchmaker(body: MatchmakerApply, user: dict = Depends(current_user)):
    require_active_account(user)
    business_name = body.business_name.strip()
    phone = re.sub(r"[^0-9+]", "", body.phone.strip())
    if len(re.sub(r"\\D", "", phone)) < 7:
        raise HTTPException(status_code=400, detail="A valid business phone is required")
    with database_connection() as connection:
        with connection.cursor() as cursor:
            consume_rate_limit(cursor, "matchmaker_apply", user["id"], 3, 24 * 60 * 60)
            cursor.execute("SELECT * FROM matchmaker_accounts WHERE user_id = %s", (user["id"],))
            existing = cursor.fetchone()
            if existing is not None:
                if existing["status"] in {"pending", "approved", "suspended"}:
                    raise HTTPException(status_code=409, detail="A matchmaker application already exists")
                cursor.execute("""UPDATE matchmaker_accounts SET business_name=%s, phone=%s, notes=%s,
                                  status='pending', review_reason='', reviewed_by=NULL, reviewed_at=NULL, updated_at=NOW()
                                  WHERE id=%s RETURNING *""",
                               (business_name, phone, body.notes.strip(), existing["id"]))
            else:
                cursor.execute("""INSERT INTO matchmaker_accounts(user_id,business_name,phone,notes)
                                  VALUES (%s,%s,%s,%s) RETURNING *""",
                               (user["id"], business_name, phone, body.notes.strip()))
            account = cursor.fetchone()
            cursor.execute("""INSERT INTO matchmaker_audit_logs(matchmaker_id,actor_user_id,event_type,target_type,target_id)
                              VALUES (%s,%s,'application_submitted','matchmaker_account',%s)""",
                           (account["id"], user["id"], str(account["id"])))
            return _safe_matchmaker_account(account)


@app.get("/api/matchmakers/profiles")
def list_matchmaker_profiles(user: dict = Depends(current_user)):
    require_active_account(user)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            account = _matchmaker_account(cursor, user["id"], approved=True)
            cursor.execute("""SELECT id, external_reference, full_name, gender, age, city, country, height,
                              marital_status, education, profession, religion, sect, phone, email,
                              partner_preferences, notes, consent_status, verification_status, visibility,
                              source_type, claimed_user_id, created_at, updated_at
                              FROM partner_profiles WHERE matchmaker_id=%s ORDER BY created_at DESC""", (account["id"],))
            return cursor.fetchall()


@app.post("/api/matchmakers/profiles/import", status_code=201)
def import_matchmaker_profiles(body: PartnerProfileImportRequest, user: dict = Depends(current_user)):
    require_active_account(user)
    if body.publish:
        raise HTTPException(status_code=400, detail="Imported profiles must begin as private drafts")
    created, skipped, errors = 0, 0, []
    with database_connection() as connection:
        with connection.cursor() as cursor:
            account = _matchmaker_account(cursor, user["id"], approved=True)
            consume_rate_limit(cursor, "matchmaker_import", user["id"], 20, 60 * 60)
            for index, item in enumerate(body.profiles):
                gender = item.gender.strip().title()
                if gender not in {"Male", "Female"}:
                    errors.append({"row": index + 1, "error": "gender must be Male or Female"})
                    continue
                email = item.email.strip().lower()
                if email and ("@" not in email or len(email) > 320):
                    errors.append({"row": index + 1, "error": "invalid email"})
                    continue
                source_hash = _partner_source_hash(item)
                cursor.execute("SELECT id FROM partner_profiles WHERE matchmaker_id=%s AND source_hash=%s", (account["id"], source_hash))
                if cursor.fetchone() is not None:
                    skipped += 1
                    continue
                cursor.execute("""INSERT INTO partner_profiles(
                    matchmaker_id,external_reference,full_name,gender,age,city,country,height,marital_status,
                    education,profession,religion,sect,phone,email,partner_preferences,notes,source_type,source_hash,
                    consent_status,verification_status,visibility)
                    VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,'pending','unverified','private')
                    RETURNING id""", (account["id"], item.external_reference.strip(), item.full_name.strip(), gender,
                    item.age, item.city.strip(), item.country.strip() or "Pakistan", item.height.strip(),
                    item.marital_status.strip(), item.education.strip(), item.profession.strip(), item.religion.strip() or "Islam",
                    item.sect.strip(), item.phone.strip(), email, item.partner_preferences.strip(), item.notes.strip(),
                    item.source_type if item.source_type in {"manual","whatsapp_text","text","csv","json","xlsx","pdf","image","api"} else "manual",
                    source_hash))
                created += 1
            cursor.execute("""INSERT INTO matchmaker_audit_logs(matchmaker_id,actor_user_id,event_type,target_type,metadata)
                              VALUES (%s,%s,'profiles_imported','partner_profile_batch',%s::jsonb)""",
                           (account["id"], user["id"], json.dumps({"created":created,"skipped":skipped,"errors":len(errors)})))
    return {"created": created, "skipped": skipped, "errors": errors}


def _send_partner_consent_email_safely(email: str, profile_name: str, business_name: str, token: str) -> None:
    try:
        smtp_username = os.getenv("SMTP_USERNAME")
        if not smtp_username:
            raise RuntimeError("SMTP_USERNAME is not configured")
        smtp_password = read_secret(os.getenv("SMTP_PASSWORD_FILE", "/run/secrets/smtp_password"))
        base = os.getenv("NISA_CONSENT_BASE_URL", "https://api.nisaesakina.com").rstrip("/")
        action = f"{base}/api/partner-consent/review?token={token}" if base else f"Consent code: {token}"
        message = EmailMessage()
        message["Subject"] = "Review your Nisa matrimonial profile"
        message["From"] = smtp_username
        message["To"] = email
        message.set_content(f"""Assalamu alaikum {profile_name},\n\n{business_name} has asked to represent your matrimonial profile on Nisa. Nothing is published until you approve.\n\nReview/approve or decline: {action}\n\nThis request expires in 7 days. If you did not expect it, you can decline or ignore it.\n""")
        with smtplib.SMTP(os.getenv("SMTP_HOST", "smtp.gmail.com"), int(os.getenv("SMTP_PORT", "587")), timeout=30) as server:
            server.starttls(); server.login(smtp_username, smtp_password); server.send_message(message)
    except Exception:
        logging.exception("Unable to send partner profile consent email")


@app.post("/api/matchmakers/profiles/{profile_id}/request-consent")
def request_partner_profile_consent(profile_id: str, background_tasks: BackgroundTasks, user: dict = Depends(current_user)):
    require_active_account(user)
    try: pid = uuid.UUID(profile_id)
    except ValueError: raise HTTPException(status_code=404, detail="Partner profile not found")
    raw_token = token_secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(raw_token.encode()).hexdigest()
    with database_connection() as connection:
        with connection.cursor() as cursor:
            account = _matchmaker_account(cursor, user["id"], approved=True)
            consume_rate_limit(cursor, "matchmaker_consent", user["id"], 100, 24 * 60 * 60)
            cursor.execute("SELECT * FROM partner_profiles WHERE id=%s AND matchmaker_id=%s FOR UPDATE", (pid, account["id"]))
            profile = cursor.fetchone()
            if profile is None: raise HTTPException(status_code=404, detail="Partner profile not found")
            if not profile["email"]: raise HTTPException(status_code=400, detail="An email address is required for digital consent")
            if profile["consent_status"] == "approved": raise HTTPException(status_code=409, detail="Consent is already approved")
            cursor.execute("UPDATE partner_profile_consent_tokens SET used_at=NOW() WHERE partner_profile_id=%s AND used_at IS NULL", (pid,))
            cursor.execute("INSERT INTO partner_profile_consent_tokens(partner_profile_id,token_hash,expires_at) VALUES (%s,%s,NOW()+INTERVAL '7 days')", (pid, token_hash))
            cursor.execute("UPDATE partner_profiles SET consent_status='requested', visibility='private', updated_at=NOW() WHERE id=%s", (pid,))
            cursor.execute("INSERT INTO partner_profile_consent_events(partner_profile_id,event_type,channel,actor_user_id) VALUES (%s,'requested','email',%s)", (pid,user["id"]))
            cursor.execute("INSERT INTO matchmaker_audit_logs(matchmaker_id,actor_user_id,event_type,target_type,target_id) VALUES (%s,%s,'consent_requested','partner_profile',%s)", (account["id"],user["id"],profile_id))
            background_tasks.add_task(_send_partner_consent_email_safely, profile["email"], profile["full_name"], account["business_name"], raw_token)
    return {"status":"requested", "expires_in_days":7}


@app.get("/api/partner-consent/review", response_class=HTMLResponse)
def partner_consent_review(token: str):
    if len(token) < 32 or len(token) > 200:
        raise HTTPException(status_code=400, detail="Invalid consent token")
    token_hash = hashlib.sha256(token.encode()).hexdigest()
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("""SELECT t.expires_at,t.used_at,p.full_name,m.business_name
                              FROM partner_profile_consent_tokens t
                              JOIN partner_profiles p ON p.id=t.partner_profile_id
                              JOIN matchmaker_accounts m ON m.id=p.matchmaker_id
                              WHERE t.token_hash=%s""", (token_hash,))
            row=cursor.fetchone()
    if row is None or row["used_at"] is not None or row["expires_at"] <= datetime.now(timezone.utc):
        raise HTTPException(status_code=400, detail="Consent link is invalid or expired")
    safe_name=html.escape(row["full_name"]); safe_business=html.escape(row["business_name"]); safe_token=html.escape(token, quote=True)
    return HTMLResponse(f"""<!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1'><title>Nisa profile consent</title></head>
<body style='font-family:sans-serif;max-width:620px;margin:40px auto;padding:20px'><h2>Nisa matrimonial profile consent</h2>
<p><b>{safe_business}</b> has asked to represent the matrimonial profile for <b>{safe_name}</b> on Nisa.</p>
<p>Approving allows this profile to become visible inside the verified matchmaker network. It does not create a Nisa login account or reveal private contact details publicly.</p>
<form method='post' action='/api/partner-consent/{safe_token}/approve'><button style='padding:12px'>Approve representation</button></form><br>
<form method='post' action='/api/partner-consent/{safe_token}/decline'><button style='padding:12px'>Decline</button></form></body></html>""")


@app.post("/api/partner-consent/{token}/{decision}")
def respond_partner_consent(token: str, decision: str):
    if decision not in {"approve","decline"}: raise HTTPException(status_code=400, detail="Decision must be approve or decline")
    if len(token) < 32 or len(token) > 200: raise HTTPException(status_code=400, detail="Invalid consent token")
    token_hash = hashlib.sha256(token.encode()).hexdigest()
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("""SELECT t.*, p.matchmaker_id FROM partner_profile_consent_tokens t
                              JOIN partner_profiles p ON p.id=t.partner_profile_id
                              WHERE t.token_hash=%s FOR UPDATE""", (token_hash,))
            row=cursor.fetchone()
            if row is None or row["used_at"] is not None or row["expires_at"] <= datetime.now(timezone.utc):
                raise HTTPException(status_code=400, detail="Consent link is invalid or expired")
            new_status = "approved" if decision == "approve" else "declined"
            visibility = "network" if decision == "approve" else "private"
            cursor.execute("UPDATE partner_profile_consent_tokens SET used_at=NOW() WHERE id=%s", (row["id"],))
            cursor.execute("UPDATE partner_profiles SET consent_status=%s, visibility=%s, updated_at=NOW() WHERE id=%s", (new_status,visibility,row["partner_profile_id"]))
            cursor.execute("INSERT INTO partner_profile_consent_events(partner_profile_id,event_type,channel) VALUES (%s,%s,'email')", (row["partner_profile_id"],new_status))
            cursor.execute("INSERT INTO matchmaker_audit_logs(matchmaker_id,event_type,target_type,target_id) VALUES (%s,%s,'partner_profile',%s)", (row["matchmaker_id"],f"consent_{new_status}",str(row["partner_profile_id"])))
    return {"status":new_status}


@app.get("/api/admin/matchmakers")
def admin_list_matchmakers(status_filter: str = "pending", user: dict = Depends(current_user)):
    with database_connection() as connection:
        require_platform_admin(connection, user)
        with connection.cursor() as cursor:
            if status_filter not in {"pending","approved","rejected","suspended","all"}: raise HTTPException(status_code=400, detail="Invalid status filter")
            if status_filter == "all": cursor.execute("SELECT * FROM matchmaker_accounts ORDER BY created_at DESC LIMIT 500")
            else: cursor.execute("SELECT * FROM matchmaker_accounts WHERE status=%s ORDER BY created_at DESC LIMIT 500", (status_filter,))
            return [_safe_matchmaker_account(x) | {"user_id":x["user_id"]} for x in cursor.fetchall()]


@app.post("/api/admin/matchmakers/{matchmaker_id}/review")
def admin_review_matchmaker(matchmaker_id: str, body: MatchmakerReview, user: dict = Depends(current_user)):
    if body.decision not in {"approved","rejected","suspended"}: raise HTTPException(status_code=400, detail="Invalid decision")
    try: mid=uuid.UUID(matchmaker_id)
    except ValueError: raise HTTPException(status_code=404, detail="Matchmaker not found")
    with database_connection() as connection:
        require_platform_admin(connection, user)
        with connection.cursor() as cursor:
            cursor.execute("UPDATE matchmaker_accounts SET status=%s,review_reason=%s,reviewed_by=%s,reviewed_at=NOW(),updated_at=NOW() WHERE id=%s RETURNING *", (body.decision,body.reason.strip(),user["id"],mid))
            account=cursor.fetchone()
            if account is None: raise HTTPException(status_code=404, detail="Matchmaker not found")
            cursor.execute("INSERT INTO matchmaker_audit_logs(matchmaker_id,actor_user_id,event_type,target_type,target_id,metadata) VALUES (%s,%s,'application_reviewed','matchmaker_account',%s,%s::jsonb)", (mid,user["id"],matchmaker_id,json.dumps({"decision":body.decision})))
            cursor.execute("INSERT INTO notifications(recipient_id,actor_id,notification_type,title,body,target_screen,target_id) VALUES (%s,%s,'matchmaker_application_update','Matchmaker application updated',%s,'matchmaker',%s)", (account["user_id"],user["id"],f"Your matchmaker application was {body.decision}.",matchmaker_id))
            return _safe_matchmaker_account(account)


@app.get("/api/matchmakers/network")
def browse_matchmaker_network(gender: str | None = None, city: str | None = None, limit: int = 100, user: dict = Depends(current_user)):
    require_active_account(user)
    limit=max(1,min(limit,100))
    with database_connection() as connection:
        with connection.cursor() as cursor:
            account=_matchmaker_account(cursor,user["id"],approved=True)
            clauses=["p.matchmaker_id <> %s", "p.consent_status='approved'", "p.visibility IN ('network','active')", "m.status='approved'"]
            params=[account["id"]]
            if gender:
                normalized=gender.strip().title()
                if normalized not in {"Male","Female"}: raise HTTPException(status_code=400,detail="Invalid gender")
                clauses.append("p.gender=%s"); params.append(normalized)
            if city:
                clauses.append("LOWER(p.city)=LOWER(%s)"); params.append(city.strip()[:120])
            params.append(limit)
            cursor.execute(f"""SELECT p.id,p.full_name,p.gender,p.age,p.city,p.country,p.height,p.marital_status,
                               p.education,p.profession,p.religion,p.sect,p.partner_preferences,p.verification_status,
                               m.business_name AS represented_by
                               FROM partner_profiles p JOIN matchmaker_accounts m ON m.id=p.matchmaker_id
                               WHERE {' AND '.join(clauses)} ORDER BY p.created_at DESC LIMIT %s""",params)
            return cursor.fetchall()


@app.post("/api/matchmakers/introductions", status_code=201)
def create_matchmaker_introduction(body: MatchmakerIntroductionCreate, user: dict = Depends(current_user)):
    try: source_id, target_id = uuid.UUID(body.requester_profile_id), uuid.UUID(body.recipient_profile_id)
    except ValueError: raise HTTPException(status_code=400, detail="Invalid partner profile id")
    with database_connection() as connection:
        with connection.cursor() as cursor:
            account=_matchmaker_account(cursor,user["id"],approved=True)
            consume_rate_limit(cursor,"matchmaker_intro",user["id"],100,24*60*60)
            cursor.execute("SELECT * FROM partner_profiles WHERE id=%s AND matchmaker_id=%s AND consent_status='approved'",(source_id,account["id"]))
            source=cursor.fetchone()
            if source is None: raise HTTPException(status_code=404,detail="Your represented profile was not found or lacks consent")
            cursor.execute("SELECT * FROM partner_profiles WHERE id=%s AND consent_status='approved' AND visibility IN ('network','active')",(target_id,))
            target=cursor.fetchone()
            if target is None or target["matchmaker_id"]==account["id"]: raise HTTPException(status_code=404,detail="Eligible recipient profile not found")
            cursor.execute("""INSERT INTO matchmaker_introductions(requester_matchmaker_id,requester_profile_id,recipient_matchmaker_id,recipient_profile_id,message)
                              VALUES (%s,%s,%s,%s,%s) RETURNING id,status,created_at""",(account["id"],source_id,target["matchmaker_id"],target_id,body.message.strip()))
            return cursor.fetchone()


@app.get("/api/matchmakers/introductions")
def list_matchmaker_introductions(user: dict = Depends(current_user)):
    with database_connection() as connection:
        with connection.cursor() as cursor:
            account=_matchmaker_account(cursor,user["id"],approved=True)
            cursor.execute("""SELECT i.id,i.status,i.message,i.created_at,i.responded_at,
                              sp.full_name AS requester_name,rp.full_name AS recipient_name,
                              (i.requester_matchmaker_id=%s) AS outgoing
                              FROM matchmaker_introductions i
                              JOIN partner_profiles sp ON sp.id=i.requester_profile_id
                              JOIN partner_profiles rp ON rp.id=i.recipient_profile_id
                              WHERE i.requester_matchmaker_id=%s OR i.recipient_matchmaker_id=%s ORDER BY i.created_at DESC LIMIT 500""",(account["id"],account["id"],account["id"]))
            return cursor.fetchall()


@app.post("/api/matchmakers/introductions/{introduction_id}/respond")
def respond_matchmaker_introduction(introduction_id: str, body: MatchmakerIntroductionResponse, user: dict = Depends(current_user)):
    if body.decision not in {"accepted","declined"}: raise HTTPException(status_code=400,detail="Decision must be accepted or declined")
    try: iid=uuid.UUID(introduction_id)
    except ValueError: raise HTTPException(status_code=404,detail="Introduction not found")
    with database_connection() as connection:
        with connection.cursor() as cursor:
            account=_matchmaker_account(cursor,user["id"],approved=True)
            cursor.execute("UPDATE matchmaker_introductions SET status=%s,responded_at=NOW(),updated_at=NOW() WHERE id=%s AND recipient_matchmaker_id=%s AND status='pending' RETURNING id,status,responded_at",(body.decision,iid,account["id"]))
            row=cursor.fetchone()
            if row is None: raise HTTPException(status_code=404,detail="Pending introduction not found")
            return row


@app.get("/api/discovery/search")
def discovery_search(
    min_age: int = 18,
    max_age: int = 60,
    min_height_cm: int | None = None,
    max_height_cm: int | None = None,
    country: str | None = None,
    city: str | None = None,
    marital_status: str | None = None,
    minimum_education_rank: int | None = None,
    offset: int = 0,
    limit: int = 50,
    user: dict = Depends(current_user),
):
    require_active_account(user)
    limit = min(max(limit, 1), 100)
    offset = max(offset, 0)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT gender FROM profiles WHERE user_id = %s", (user["id"],))
            current_profile = cursor.fetchone()
    current_gender = (current_profile or {}).get("gender")
    if current_gender not in {"Male", "Female"}:
        raise HTTPException(status_code=400, detail="Complete your profile gender before discovery")
    required_gender = "Female" if current_gender == "Male" else "Male"

    conditions = [
        "u.account_status = 'active'",
        "u.id <> %s",
        "p.date_of_birth IS NOT NULL",
            """
            NOT EXISTS (
                SELECT 1 FROM blocks b
            WHERE (b.blocker_id = %s AND b.blocked_id = u.id)
               OR (b.blocker_id = u.id AND b.blocked_id = %s)
            )
            AND NOT EXISTS (
                SELECT 1 FROM moderation_sanctions ms
                WHERE ms.target_user_id = u.id AND ms.sanction_type = 'temporary_account_ban'
                  AND ms.revoked_at IS NULL AND ms.expires_at > NOW()
            )
            """,
    ]
    params: list = [user["id"]]
    params.extend([user["id"], user["id"]])
    conditions.append("p.gender = %s")
    params.append(required_gender)

    conditions.append(
        """
        EXTRACT(
            YEAR FROM AGE(CURRENT_DATE, p.date_of_birth)
        ) BETWEEN %s AND %s
        """
    )
    params.extend([min_age, max_age])

    if min_height_cm is not None:
        conditions.append("p.height_cm >= %s")
        params.append(min_height_cm)

    if max_height_cm is not None:
        conditions.append("p.height_cm <= %s")
        params.append(max_height_cm)

    if country and country.lower() not in (
        "any",
        "any country",
    ):
        conditions.append("LOWER(p.country) = LOWER(%s)")
        params.append(country)

    if city and city.lower() not in (
        "any",
        "any city",
    ):
        conditions.append("LOWER(p.city) = LOWER(%s)")
        params.append(city)

    if marital_status and marital_status.lower() not in (
        "any",
        "any marital status",
    ):
        conditions.append("p.marital_status = %s")
        params.append(marital_status)

    if minimum_education_rank is not None:
        conditions.append("COALESCE(p.education_rank, 0) >= %s")
        params.append(minimum_education_rank)

    where_clause = " AND ".join(conditions)

    query = f"""
        SELECT
            u.id,
            u.display_name,
            u.account_status,
            p.full_name,
            p.date_of_birth,
            EXTRACT(
                YEAR FROM AGE(CURRENT_DATE, p.date_of_birth)
            )::INTEGER AS age,
            p.gender,
            p.country,
            p.city,
            p.height_cm,
            p.marital_status,
            p.religion,
            p.sect,
            p.education,
            p.education_rank,
            p.profession,
            p.photo_url,
            p.is_verified
        FROM users u
        INNER JOIN profiles p ON p.user_id = u.id
        WHERE {where_clause}
        ORDER BY u.updated_at DESC
        LIMIT %s OFFSET %s
    """

    params.extend([limit, offset])

    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(query, params)
            profiles = cursor.fetchall()

    return {
        "ok": True,
        "count": len(profiles),
        "profiles": profiles,
    }
@app.get("/api/discovery/recommendations")
def recommendations(
    offset: int = 0,
    limit: int = 50,
    min_age: int | None = None,
    max_age: int | None = None,
    min_height_cm: int | None = None,
    max_height_cm: int | None = None,
    country_filter: str | None = None,
    city_filter: str | None = None,
    marital_status_filter: str | None = None,
    minimum_education_rank: int | None = None,
    education_filter: str | None = None,
    verified_only: bool = False,
    target_gender: str | None = None,
    prioritize_nearby: bool = False,
    max_distance_miles: int | None = None,
    user: dict = Depends(current_user),
):
    require_active_account(user)
    limit = min(max(limit, 1), 100)
    offset = max(offset, 0)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT gender FROM profiles WHERE user_id = %s", (user["id"],))
            current_profile = cursor.fetchone()
    current_gender = (current_profile or {}).get("gender")
    if current_gender not in {"Male", "Female"}:
        raise HTTPException(status_code=400, detail="Complete your profile gender before discovery")
    required_gender = "Female" if current_gender == "Male" else "Male"
    if target_gender is not None and target_gender.casefold() != required_gender.casefold():
        raise HTTPException(status_code=400, detail="Target gender does not match your profile")
    target_gender = required_gender
    if max_distance_miles is not None:
        max_distance_miles = min(max(max_distance_miles, 1), 500)

    query = """
        SELECT
            u.id,
            u.display_name,
            p.full_name,
            p.date_of_birth,
            EXTRACT(
                YEAR FROM AGE(CURRENT_DATE, p.date_of_birth)
            )::INTEGER AS age,
            p.gender,
            p.country,
            p.city,
            p.height_cm,
            p.marital_status,
            p.religion,
            p.sect,
            p.education,
            p.education_rank,
            p.profession,
            p.photo_url,
            p.is_verified,
            p.religious_practice,
            p.relocation_preference,
            CASE
                WHEN location_distance.distance_km IS NOT NULL
                 AND location_distance.distance_km <= 25
                THEN 'nearby'
                ELSE NULL
            END AS distance_band,
            EXISTS (
                SELECT 1
                FROM interests pending_interest
                WHERE pending_interest.status = 'pending'
                  AND (
                    (pending_interest.sender_id = %s AND pending_interest.receiver_id = u.id)
                    OR
                    (pending_interest.sender_id = u.id AND pending_interest.receiver_id = %s)
                  )
            ) AS has_existing_interest,
            (
                CASE WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, p.date_of_birth))
                    BETWEEN COALESCE(pref.min_age, 18) AND COALESCE(pref.max_age, 60)
                    THEN 30 ELSE 0 END
              + CASE WHEN NULLIF(TRIM(pref.preferred_country), '') IS NOT NULL
                    AND LOWER(TRIM(pref.preferred_country)) NOT IN ('any', 'any country')
                    AND LOWER(COALESCE(p.country, '')) = LOWER(TRIM(pref.preferred_country))
                    THEN 20 ELSE 0 END
              + CASE WHEN NULLIF(TRIM(pref.preferred_city), '') IS NOT NULL
                    AND LOWER(TRIM(pref.preferred_city)) NOT IN ('any', 'any city')
                    AND LOWER(COALESCE(p.city, '')) = LOWER(TRIM(pref.preferred_city))
                    THEN 15 ELSE 0 END
              + CASE WHEN NULLIF(TRIM(pref.preferred_marital_status), '') IS NOT NULL
                    AND LOWER(TRIM(pref.preferred_marital_status)) NOT IN ('any', 'any marital status')
                    AND CASE WHEN LOWER(TRIM(p.marital_status)) IN ('single', 'never married', 'single (never married)')
                             THEN 'never married' ELSE LOWER(TRIM(COALESCE(p.marital_status, ''))) END
                        = CASE WHEN LOWER(TRIM(pref.preferred_marital_status)) IN ('single', 'never married', 'single (never married)')
                               THEN 'never married' ELSE LOWER(TRIM(pref.preferred_marital_status)) END
                    THEN 15 ELSE 0 END
              + CASE WHEN COALESCE(p.education_rank, 0) >= COALESCE(pref.minimum_education_rank, 0)
                    THEN 10 ELSE 0 END
              + CASE WHEN p.is_verified IS TRUE THEN 8 ELSE 0 END
              + CASE WHEN LOWER(TRIM(COALESCE(p.relocation_preference, ''))) IN ('willing to relocate', 'willing', 'yes')
                    AND LOWER(TRIM(COALESCE(current_profile.relocation_preference, ''))) IN ('willing to relocate', 'willing', 'yes')
                    THEN 3 ELSE 0 END
              + CASE WHEN NULLIF(TRIM(COALESCE(p.religious_practice, '')), '') IS NOT NULL
                    THEN 2 ELSE 0 END
            ) AS compatibility_score,
            (ARRAY_REMOVE(ARRAY[
                CASE WHEN EXTRACT(YEAR FROM AGE(CURRENT_DATE, p.date_of_birth))
                    BETWEEN COALESCE(pref.min_age, 18) AND COALESCE(pref.max_age, 60)
                    THEN 'Preferred age range' END,
                CASE WHEN NULLIF(TRIM(pref.preferred_country), '') IS NOT NULL
                    AND LOWER(TRIM(pref.preferred_country)) NOT IN ('any', 'any country')
                    AND LOWER(COALESCE(p.country, '')) = LOWER(TRIM(pref.preferred_country))
                    THEN 'Preferred country' END,
                CASE WHEN NULLIF(TRIM(pref.preferred_city), '') IS NOT NULL
                    AND LOWER(TRIM(pref.preferred_city)) NOT IN ('any', 'any city')
                    AND LOWER(COALESCE(p.city, '')) = LOWER(TRIM(pref.preferred_city))
                    THEN 'Preferred city' END,
                CASE WHEN NULLIF(TRIM(pref.preferred_marital_status), '') IS NOT NULL
                    AND LOWER(TRIM(pref.preferred_marital_status)) NOT IN ('any', 'any marital status')
                    AND CASE WHEN LOWER(TRIM(p.marital_status)) IN ('single', 'never married', 'single (never married)')
                             THEN 'never married' ELSE LOWER(TRIM(COALESCE(p.marital_status, ''))) END
                        = CASE WHEN LOWER(TRIM(pref.preferred_marital_status)) IN ('single', 'never married', 'single (never married)')
                               THEN 'never married' ELSE LOWER(TRIM(pref.preferred_marital_status)) END
                    THEN 'Preferred marital status' END,
                CASE WHEN COALESCE(p.education_rank, 0) >= COALESCE(pref.minimum_education_rank, 0)
                    THEN 'Preferred education' END,
                CASE WHEN p.is_verified IS TRUE THEN 'Verified profile' END,
                CASE WHEN LOWER(TRIM(COALESCE(p.relocation_preference, ''))) IN ('willing to relocate', 'willing', 'yes')
                    AND LOWER(TRIM(COALESCE(current_profile.relocation_preference, ''))) IN ('willing to relocate', 'willing', 'yes')
                    THEN 'Both open to relocation' END
            ]::TEXT[], NULL))[1:3] AS recommendation_reasons
        FROM users u
        INNER JOIN profiles p ON p.user_id = u.id
        LEFT JOIN matrimonial_preferences pref
            ON pref.user_id = %s
        LEFT JOIN profiles current_profile
            ON current_profile.user_id = %s
        LEFT JOIN profile_locations viewer_location
            ON viewer_location.user_id = %s
        LEFT JOIN profile_locations candidate_location
            ON candidate_location.user_id = u.id
        LEFT JOIN LATERAL (
            SELECT CASE
                WHEN viewer_location.latitude IS NULL
                  OR candidate_location.latitude IS NULL
                THEN NULL
                ELSE 2 * 6371.0 * ASIN(SQRT(LEAST(
                    1.0,
                    POWER(SIN(RADIANS(
                        candidate_location.latitude - viewer_location.latitude
                    ) / 2), 2)
                    + COS(RADIANS(viewer_location.latitude))
                    * COS(RADIANS(candidate_location.latitude))
                    * POWER(SIN(RADIANS(
                        candidate_location.longitude - viewer_location.longitude
                    ) / 2), 2)
                )))
            END AS distance_km
        ) location_distance ON TRUE
        WHERE
            u.account_status = 'active'
            AND NOT EXISTS (SELECT 1 FROM moderation_sanctions ms
                WHERE ms.target_user_id = u.id AND ms.sanction_type = 'temporary_account_ban'
                  AND ms.revoked_at IS NULL AND ms.expires_at > NOW())
            AND u.id <> %s
            AND p.date_of_birth IS NOT NULL

            AND EXTRACT(
                YEAR FROM AGE(CURRENT_DATE, p.date_of_birth)
            ) BETWEEN
                COALESCE(%s, 18)
                AND COALESCE(%s, 100)

            AND (
                COALESCE(%s, pref.min_height_cm) IS NULL
                OR p.height_cm >= COALESCE(%s, pref.min_height_cm)
            )

            AND (
                COALESCE(%s, pref.max_height_cm) IS NULL
                OR p.height_cm <= COALESCE(%s, pref.max_height_cm)
            )

            AND (
                %s::TEXT IS NULL
                OR %s IN ('Any', 'Any country')
                OR LOWER(p.country) = LOWER(%s)
            )

            AND (
                %s::TEXT IS NULL
                OR %s IN ('Any', 'Any city')
                OR LOWER(p.city) = LOWER(%s)
            )

            AND (
                %s::TEXT IS NULL
                OR %s IN ('Any', 'Any marital status')
                OR CASE
                    WHEN LOWER(TRIM(p.marital_status)) IN (
                        'single', 'never married', 'single (never married)'
                    ) THEN 'never married'
                    ELSE LOWER(TRIM(p.marital_status))
                END = CASE
                    WHEN LOWER(TRIM(%s)) IN (
                        'single', 'never married', 'single (never married)'
                    ) THEN 'never married'
                    ELSE LOWER(TRIM(%s))
                END
            )

            AND COALESCE(p.education_rank, 0) >= COALESCE(
                %s,
                0
            )
            AND (%s::TEXT IS NULL OR LOWER(p.education) = LOWER(%s))

            AND (NOT %s OR p.is_verified IS TRUE)
            AND (%s::TEXT IS NULL OR LOWER(p.gender) = LOWER(%s))

            AND (
                %s::INTEGER IS NULL
                OR (
                    %s IS TRUE
                    AND location_distance.distance_km IS NOT NULL
                    AND location_distance.distance_km <= %s * 1.609344
                )
            )

            AND NOT EXISTS (
                SELECT 1
                FROM matches m
                WHERE
                    (m.user_a = %s AND m.user_b = u.id)
                    OR
                    (m.user_b = %s AND m.user_a = u.id)
            )

            AND NOT EXISTS (
                SELECT 1
                FROM interests accepted_interest
                WHERE accepted_interest.status = 'accepted'
                  AND (
                    (accepted_interest.sender_id = %s AND accepted_interest.receiver_id = u.id)
                    OR
                    (accepted_interest.sender_id = u.id AND accepted_interest.receiver_id = %s)
                  )
            )

            AND NOT EXISTS (
                SELECT 1
                FROM blocks b
                WHERE
                    (b.blocker_id = %s AND b.blocked_id = u.id)
                    OR
                    (b.blocker_id = u.id AND b.blocked_id = %s)
            )

        ORDER BY has_existing_interest ASC,
                 CASE WHEN %s THEN
                     CASE WHEN location_distance.distance_km IS NULL THEN 1 ELSE 0 END
                 ELSE 0 END ASC,
                 CASE WHEN %s THEN location_distance.distance_km END ASC,
                 compatibility_score DESC, p.is_verified DESC, u.updated_at DESC
        LIMIT %s OFFSET %s
    """

    params = [
        user["id"],
        user["id"],
        user["id"],
        user["id"],
        user["id"],
        user["id"],
        min_age,
        max_age,
        min_height_cm,
        min_height_cm,
        max_height_cm,
        max_height_cm,
        country_filter,
        country_filter,
        country_filter,
        city_filter,
        city_filter,
        city_filter,
        marital_status_filter,
        marital_status_filter,
        marital_status_filter,
        marital_status_filter,
        minimum_education_rank,
        education_filter,
        education_filter,
        verified_only,
        target_gender,
        target_gender,
        max_distance_miles,
        prioritize_nearby,
        max_distance_miles,
        user["id"],
        user["id"],
        user["id"],
        user["id"],
        user["id"],
        user["id"],
        prioritize_nearby,
        prioritize_nearby,
        limit,
        offset,
    ]

    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(query, params)
            profiles = cursor.fetchall()

    return {
        "ok": True,
        "count": len(profiles),
        "profiles": profiles,
    }
class InterestResponse(BaseModel):
    status: str


@app.post("/api/interests/{receiver_id}")
def send_interest(
    receiver_id: str,
    user: dict = Depends(current_user),
):
    require_active_account(user)
    if receiver_id == user["id"]:
        raise HTTPException(
            status_code=400,
            detail="You cannot send interest to yourself",
        )

    with database_connection() as connection:
        lock_user_pair(connection, user["id"], receiver_id)
        with connection.cursor() as cursor:
            consume_rate_limit(cursor, "send_interest", user["id"], 30, 24 * 60 * 60)
            cursor.execute(
                """
                SELECT users.id,
                       recipient_profile.gender AS receiver_gender,
                       sender_profile.gender AS sender_gender
                FROM users
                INNER JOIN profiles recipient_profile ON recipient_profile.user_id = users.id
                INNER JOIN profiles sender_profile ON sender_profile.user_id = %s
                WHERE users.id = %s
                  AND users.account_status = 'active'
                  AND NOT EXISTS (SELECT 1 FROM moderation_sanctions ms
                    WHERE ms.target_user_id = users.id AND ms.sanction_type = 'temporary_account_ban'
                      AND ms.revoked_at IS NULL AND ms.expires_at > NOW())
                """,
                (user["id"], receiver_id),
            )

            recipient = cursor.fetchone()
            if recipient is None:
                raise HTTPException(
                    status_code=404,
                    detail="Recipient is not available",
                )
            if (
                recipient["sender_gender"] not in {"Male", "Female"}
                or recipient["receiver_gender"] not in {"Male", "Female"}
                or recipient["sender_gender"] == recipient["receiver_gender"]
            ):
                raise HTTPException(
                    status_code=403,
                    detail="This profile is outside your eligible matching pool",
                )

            if users_are_blocked(connection, user["id"], receiver_id):
                raise HTTPException(
                    status_code=403,
                    detail="You cannot interact with this user",
                )

            cursor.execute(
                """
                SELECT *
                FROM interests
                WHERE sender_id = %s
                  AND receiver_id = %s
                """,
                (user["id"], receiver_id),
            )
            existing = cursor.fetchone()

            if existing is not None:
                if existing["status"] == "pending":
                    return existing
                if existing["updated_at"] > datetime.now(timezone.utc) - timedelta(hours=24):
                    raise HTTPException(
                        status_code=429,
                        detail="Wait 24 hours before sending this interest again",
                    )

                cursor.execute(
                    """
                    UPDATE interests
                    SET status = 'pending', updated_at = NOW()
                    WHERE id = %s
                    RETURNING *
                    """,
                    (existing["id"],),
                )
                interest = cursor.fetchone()
            else:
                cursor.execute(
                    """
                    INSERT INTO interests (sender_id, receiver_id)
                    VALUES (%s, %s)
                    RETURNING *
                    """,
                    (user["id"], receiver_id),
                )
                interest = cursor.fetchone()

            cursor.execute(
                """
                INSERT INTO notifications (
                    recipient_id,
                    actor_id,
                    notification_type,
                    title,
                    body,
                    target_screen,
                    target_id
                )
                VALUES (
                    %s,
                    %s,
                    'incoming_interest',
                    'New interest',
                    'Someone sent you a matrimonial interest.',
                    'incoming_interests',
                    %s
                )
                """,
                (receiver_id, user["id"], str(interest["id"])),
            )

    return interest


@app.get("/api/interests/incoming")
def incoming_interests(user: dict = Depends(current_user)):
    require_active_account(user)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    i.*,
                    p.full_name AS sender_name,
                    p.photo_url AS sender_photo,
                    p.country AS sender_country,
                    p.city AS sender_city,
                    p.education AS sender_education,
                    p.profession AS sender_profession
                FROM interests i
                INNER JOIN users u ON u.id = i.sender_id
                LEFT JOIN profiles p ON p.user_id = i.sender_id
                WHERE i.receiver_id = %s
                  AND u.account_status = 'active'
                  AND NOT EXISTS (
                      SELECT 1 FROM blocks b
                      WHERE (b.blocker_id = i.sender_id AND b.blocked_id = i.receiver_id)
                         OR (b.blocker_id = i.receiver_id AND b.blocked_id = i.sender_id)
                  )
                ORDER BY i.created_at DESC
                """,
                (user["id"],),
            )
            return {
                "ok": True,
                "interests": cursor.fetchall(),
            }


@app.get("/api/interests/sent")
def sent_interests(user: dict = Depends(current_user)):
    require_active_account(user)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    i.*,
                    p.full_name AS receiver_name,
                    p.photo_url AS receiver_photo,
                    p.country AS receiver_country,
                    p.city AS receiver_city
                FROM interests i
                INNER JOIN users u ON u.id = i.receiver_id
                LEFT JOIN profiles p ON p.user_id = i.receiver_id
                WHERE i.sender_id = %s
                  AND u.account_status = 'active'
                  AND NOT EXISTS (
                      SELECT 1 FROM blocks b
                      WHERE (b.blocker_id = i.sender_id AND b.blocked_id = i.receiver_id)
                         OR (b.blocker_id = i.receiver_id AND b.blocked_id = i.sender_id)
                  )
                ORDER BY i.created_at DESC
                """,
                (user["id"],),
            )
            return {
                "ok": True,
                "interests": cursor.fetchall(),
            }


@app.post("/api/interests/{interest_id}/respond")
def respond_to_interest(
    interest_id: str,
    payload: InterestResponse,
    user: dict = Depends(current_user),
):
    require_active_account(user)
    if payload.status not in ("accepted", "declined"):
        raise HTTPException(
            status_code=400,
            detail="Status must be accepted or declined",
        )

    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT *
                FROM interests
                WHERE id = %s
                  AND receiver_id = %s
                """,
                (interest_id, user["id"]),
            )
            interest = cursor.fetchone()

            if interest is None:
                raise HTTPException(
                    status_code=404,
                    detail="Interest not found",
                )

            lock_user_pair(connection, interest["sender_id"], user["id"])
            if users_are_blocked(connection, interest["sender_id"], user["id"]):
                raise HTTPException(
                    status_code=403,
                    detail="This interaction is unavailable",
                )

            cursor.execute(
                """
                UPDATE interests
                SET status = %s, updated_at = NOW()
                WHERE id = %s
                RETURNING *
                """,
                (payload.status, interest_id),
            )
            updated_interest = cursor.fetchone()
            match_id = None

            if payload.status == "accepted":
                cursor.execute(
                    """
                    INSERT INTO matches (user_a, user_b)
                    VALUES (
                        LEAST(%s, %s),
                        GREATEST(%s, %s)
                    )
                    ON CONFLICT (user_a, user_b) DO NOTHING
                    RETURNING id
                    """,
                    (
                        interest["sender_id"],
                        user["id"],
                        interest["sender_id"],
                        user["id"],
                    ),
                )
                created_match = cursor.fetchone()

                if created_match is not None:
                    match_id = created_match["id"]
                else:
                    cursor.execute(
                        """
                        SELECT id
                        FROM matches
                        WHERE user_a = LEAST(%s, %s)
                          AND user_b = GREATEST(%s, %s)
                        """,
                        (
                            interest["sender_id"],
                            user["id"],
                            interest["sender_id"],
                            user["id"],
                        ),
                    )
                    match_id = cursor.fetchone()["id"]

                cursor.execute(
                    """
                    INSERT INTO conversations (user_a, user_b)
                    VALUES (
                        LEAST(%s, %s),
                        GREATEST(%s, %s)
                    )
                    ON CONFLICT (user_a, user_b) DO NOTHING
                    """,
                    (
                        interest["sender_id"],
                        user["id"],
                        interest["sender_id"],
                        user["id"],
                    ),
                )

                cursor.execute(
                    """
                    INSERT INTO notifications (
                        recipient_id,
                        actor_id,
                        notification_type,
                        title,
                        body,
                        target_screen,
                        target_id
                    )
                    VALUES (
                        %s,
                        %s,
                        'interest_accepted',
                        'Interest accepted',
                        'Your matrimonial interest was accepted.',
                        'matches',
                        %s
                    )
                    """,
                    (
                        interest["sender_id"],
                        user["id"],
                        str(match_id),
                    ),
                )

    return {
        "ok": True,
        "interest": updated_interest,
        "match_id": match_id,
    }


@app.get("/api/notifications")
def get_notifications(user: dict = Depends(current_user)):
    require_active_account(user)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT *
                FROM notifications
                WHERE recipient_id = %s
                  AND (
                      actor_id IS NULL
                      OR NOT EXISTS (
                          SELECT 1 FROM blocks b
                          WHERE (b.blocker_id = notifications.recipient_id
                                 AND b.blocked_id = notifications.actor_id)
                             OR (b.blocker_id = notifications.actor_id
                                 AND b.blocked_id = notifications.recipient_id)
                      )
                  )
                ORDER BY created_at DESC
                LIMIT 100
                """,
                (user["id"],),
            )
            return {
                "ok": True,
                "notifications": cursor.fetchall(),
            }


@app.post("/api/notifications/{notification_id}/read")
def mark_notification_read(
    notification_id: str,
    user: dict = Depends(current_user),
):
    require_active_account(user)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                UPDATE notifications
                SET is_read = TRUE
                WHERE id = %s
                  AND recipient_id = %s
                  AND (
                      actor_id IS NULL
                      OR NOT EXISTS (
                          SELECT 1 FROM blocks b
                          WHERE (b.blocker_id = notifications.recipient_id
                                 AND b.blocked_id = notifications.actor_id)
                             OR (b.blocker_id = notifications.actor_id
                                 AND b.blocked_id = notifications.recipient_id)
                      )
                  )
                RETURNING *
                """,
                (notification_id, user["id"]),
            )
            notification = cursor.fetchone()

    if notification is None:
        raise HTTPException(
            status_code=404,
            detail="Notification not found",
        )

    return notification
class PrivacySettingsUpdate(BaseModel):
    show_online_status: bool
    share_read_receipts: bool


class PresenceUpdate(BaseModel):
    is_online: bool


def get_privacy_settings(connection, user_id: str) -> dict:
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT show_online_status, share_read_receipts
            FROM user_privacy_settings
            WHERE user_id = %s
            """,
            (user_id,),
        )
        settings = cursor.fetchone()
    return settings or {
        "show_online_status": True,
        "share_read_receipts": True,
    }


@app.get("/api/privacy/settings")
def get_my_privacy_settings(user: dict = Depends(current_user)):
    require_active_account(user)
    with database_connection() as connection:
        settings = get_privacy_settings(connection, user["id"])
    return {"ok": True, "settings": settings}


@app.put("/api/privacy/settings")
def update_my_privacy_settings(
    payload: PrivacySettingsUpdate,
    user: dict = Depends(current_user),
):
    require_active_account(user)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO user_privacy_settings (
                    user_id, show_online_status, share_read_receipts, updated_at
                )
                VALUES (%s, %s, %s, NOW())
                ON CONFLICT (user_id) DO UPDATE SET
                    show_online_status = EXCLUDED.show_online_status,
                    share_read_receipts = EXCLUDED.share_read_receipts,
                    updated_at = NOW()
                RETURNING show_online_status, share_read_receipts
                """,
                (
                    user["id"],
                    payload.show_online_status,
                    payload.share_read_receipts,
                ),
            )
            settings = cursor.fetchone()

            # Keep the recipient's private unread state while removing visible
            # read receipts already produced before this privacy change. Future
            # reads remain private until the member turns receipts back on.
            if not payload.share_read_receipts:
                cursor.execute(
                    """
                    UPDATE messages m
                    SET read_at = NULL
                    FROM conversations c
                    WHERE c.id = m.conversation_id
                      AND (c.user_a = %s OR c.user_b = %s)
                      AND m.sender_id <> %s
                    """,
                    (user["id"], user["id"], user["id"]),
                )
    return {"ok": True, "settings": settings}


@app.post("/api/presence")
def update_my_presence(
    payload: PresenceUpdate,
    user: dict = Depends(current_user),
):
    require_active_account(user)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                INSERT INTO user_presence (user_id, is_online, last_seen_at)
                VALUES (%s, %s, NOW())
                ON CONFLICT (user_id) DO UPDATE SET
                    is_online = EXCLUDED.is_online,
                    last_seen_at = NOW()
                """,
                (user["id"], payload.is_online),
            )
    return {"ok": True}


@app.get("/api/users/{target_user_id}/presence")
def get_user_presence(
    target_user_id: str,
    user: dict = Depends(current_user),
):
    require_active_account(user)
    if target_user_id == user["id"]:
        return {
            "ok": True,
            "presence": {"is_online": False, "last_seen_at": None, "visible": False},
        }

    with database_connection() as connection:
        if users_are_blocked(connection, user["id"], target_user_id):
            raise HTTPException(status_code=404, detail="Presence not found")
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT EXISTS (
                    SELECT 1 FROM matches
                    WHERE (user_a = %s AND user_b = %s)
                       OR (user_a = %s AND user_b = %s)
                ) AS is_matched
                """,
                (user["id"], target_user_id, target_user_id, user["id"]),
            )
            if not cursor.fetchone()["is_matched"]:
                raise HTTPException(status_code=404, detail="Presence not found")

            cursor.execute(
                """
                SELECT COALESCE(p.is_online, FALSE) AS is_online,
                       p.last_seen_at,
                       COALESCE(s.show_online_status, TRUE) AS visible
                FROM (SELECT %s::TEXT AS target_id) target
                LEFT JOIN user_presence p ON p.user_id = target.target_id
                LEFT JOIN user_privacy_settings s ON s.user_id = target.target_id
                """,
                (target_user_id,),
            )
            presence = cursor.fetchone()

    if not presence["visible"]:
        return {
            "ok": True,
            "presence": {"is_online": False, "last_seen_at": None, "visible": False},
        }

    last_seen = presence["last_seen_at"]
    fresh = last_seen is not None and last_seen >= datetime.now(timezone.utc) - timedelta(minutes=2)
    return {
        "ok": True,
        "presence": {
            "is_online": bool(presence["is_online"] and fresh),
            "last_seen_at": last_seen,
            "visible": True,
        },
    }


class MessageCreate(BaseModel):
    body: str


def get_conversation_for_user(
    connection,
    conversation_id: str,
    user_id: str,
):
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT
                c.*,
                CASE
                    WHEN c.user_a = %s THEN c.user_b
                    ELSE c.user_a
                END AS other_user_id
            FROM conversations c
            WHERE c.id = %s
              AND (c.user_a = %s OR c.user_b = %s)
            """,
            (
                user_id,
                conversation_id,
                user_id,
                user_id,
            ),
        )
        conversation = cursor.fetchone()

    if conversation is None:
        return None

    lock_user_pair(connection, user_id, conversation["other_user_id"])
    if users_are_blocked(connection, user_id, conversation["other_user_id"]):
        return None
    return conversation


@app.get("/api/conversations")
def get_conversations(user: dict = Depends(current_user)):
    require_active_account(user)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    c.id,
                    c.last_message_at,
                    CASE
                        WHEN c.user_a = %s THEN c.user_b
                        ELSE c.user_a
                    END AS other_user_id,
                    p.full_name AS other_user_name,
                    p.photo_url AS other_user_photo,
                    p.country AS other_user_country,
                    p.city AS other_user_city,
                    (
                        SELECT COUNT(*)
                        FROM messages m
                        WHERE m.conversation_id = c.id
                          AND m.sender_id <> %s
                          AND m.recipient_read_at IS NULL
                    ) AS unread_count,
                    (
                        SELECT m.body
                        FROM messages m
                        WHERE m.conversation_id = c.id
                        ORDER BY m.sent_at DESC
                        LIMIT 1
                    ) AS last_message
                FROM conversations c
                LEFT JOIN profiles p
                    ON p.user_id = CASE
                        WHEN c.user_a = %s THEN c.user_b
                        ELSE c.user_a
                    END
                WHERE (c.user_a = %s OR c.user_b = %s)
                  AND NOT EXISTS (
                      SELECT 1 FROM blocks b
                      WHERE (b.blocker_id = c.user_a AND b.blocked_id = c.user_b)
                         OR (b.blocker_id = c.user_b AND b.blocked_id = c.user_a)
                  )
                ORDER BY c.last_message_at DESC NULLS LAST
                """,
                (
                    user["id"],
                    user["id"],
                    user["id"],
                    user["id"],
                    user["id"],
                ),
            )

            return {
                "ok": True,
                "conversations": cursor.fetchall(),
            }


@app.get("/api/conversations/{conversation_id}/messages")
def get_messages(
    conversation_id: str,
    user: dict = Depends(current_user),
):
    require_active_account(user)
    with database_connection() as connection:
        conversation = get_conversation_for_user(
            connection,
            conversation_id,
            user["id"],
        )

        if conversation is None:
            raise HTTPException(
                status_code=404,
                detail="Conversation not found",
            )

        with connection.cursor() as cursor:
            cursor.execute(
                """
                UPDATE messages
                SET delivered_at = COALESCE(delivered_at, NOW())
                WHERE conversation_id = %s
                  AND sender_id <> %s
                """,
                (conversation_id, user["id"]),
            )

            cursor.execute(
                """
                SELECT m.id, m.conversation_id, m.sender_id, m.body,
                       m.sent_at, m.delivered_at,
                       CASE
                           WHEN COALESCE(rs.share_read_receipts, TRUE)
                           THEN m.read_at
                           ELSE NULL
                       END AS read_at
                FROM messages m
                JOIN conversations c ON c.id = m.conversation_id
                LEFT JOIN user_privacy_settings rs
                    ON rs.user_id = CASE
                        WHEN m.sender_id = c.user_a THEN c.user_b
                        ELSE c.user_a
                    END
                WHERE m.conversation_id = %s
                ORDER BY m.sent_at ASC
                """,
                (conversation_id,),
            )

            return {
                "ok": True,
                "messages": cursor.fetchall(),
            }


@app.post("/api/conversations/{conversation_id}/messages")
def send_message(
    conversation_id: str,
    payload: MessageCreate,
    user: dict = Depends(current_user),
):
    require_active_account(user)
    body = payload.body.strip()

    if not body:
        raise HTTPException(
            status_code=400,
            detail="Message cannot be empty",
        )

    if len(body) > 5000:
        raise HTTPException(
            status_code=400,
            detail="Message is too long",
        )

    with database_connection() as connection:
        conversation = get_conversation_for_user(
            connection,
            conversation_id,
            user["id"],
        )

        if conversation is None:
            raise HTTPException(
                status_code=404,
                detail="Conversation not found",
            )

        other_user_id = conversation["other_user_id"]

        with connection.cursor() as cursor:
            consume_rate_limit(cursor, "send_message", user["id"], 120, 60 * 60)
            if users_are_blocked(connection, user["id"], other_user_id):
                raise HTTPException(
                    status_code=403,
                    detail="Messaging is unavailable because an account restriction or block is active.",
                )
            cursor.execute(
                """SELECT EXISTS (SELECT 1 FROM moderation_sanctions
                   WHERE target_user_id = %s AND sanction_type = 'temporary_account_ban'
                     AND revoked_at IS NULL AND expires_at > NOW()) AS restricted""",
                (other_user_id,),
            )
            if cursor.fetchone()["restricted"]:
                raise HTTPException(status_code=403, detail="Messaging is unavailable while this account is restricted.")
            cursor.execute(
                """
                SELECT 1
                FROM matches
                WHERE
                    (user_a = %s AND user_b = %s)
                    OR
                    (user_a = %s AND user_b = %s)
                """,
                (
                    user["id"],
                    other_user_id,
                    other_user_id,
                    user["id"],
                ),
            )

            if cursor.fetchone() is None:
                raise HTTPException(
                    status_code=403,
                    detail="Messaging requires a mutual match",
                )

            cursor.execute(
                """
                INSERT INTO messages (
                    conversation_id,
                    sender_id,
                    body
                )
                VALUES (%s, %s, %s)
                RETURNING *
                """,
                (conversation_id, user["id"], body),
            )
            message = cursor.fetchone()

            cursor.execute(
                """
                UPDATE conversations
                SET last_message_at = NOW()
                WHERE id = %s
                """,
                (conversation_id,),
            )

            cursor.execute(
                """
                INSERT INTO notifications (
                    recipient_id,
                    actor_id,
                    notification_type,
                    title,
                    body,
                    target_screen,
                    target_id
                )
                VALUES (
                    %s,
                    %s,
                    'new_message',
                    'New message',
                    %s,
                    'messages',
                    %s
                )
                """,
                (
                    other_user_id,
                    user["id"],
                    body[:120],
                    conversation_id,
                ),
            )

            return {
                "ok": True,
                "message": message,
            }


@app.post("/api/conversations/{conversation_id}/read")
def mark_conversation_read(
    conversation_id: str,
    user: dict = Depends(current_user),
):
    require_active_account(user)
    with database_connection() as connection:
        conversation = get_conversation_for_user(
            connection,
            conversation_id,
            user["id"],
        )

        if conversation is None:
            raise HTTPException(
                status_code=404,
                detail="Conversation not found",
            )

        share_read_receipts = get_privacy_settings(
            connection, user["id"]
        )["share_read_receipts"]
        with connection.cursor() as cursor:
            cursor.execute(
                """
                UPDATE messages
                SET
                    delivered_at = COALESCE(delivered_at, NOW()),
                    recipient_read_at = COALESCE(recipient_read_at, NOW()),
                    read_at = CASE
                        WHEN %s THEN COALESCE(read_at, NOW())
                        ELSE NULL
                    END
                WHERE conversation_id = %s
                  AND sender_id <> %s
                """,
                (share_read_receipts, conversation_id, user["id"]),
            )

    return {"ok": True}


@app.get("/api/messages/unread-count")
def unread_message_count(user: dict = Depends(current_user)):
    require_active_account(user)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT COUNT(*) AS unread_count
                FROM messages m
                INNER JOIN conversations c
                    ON c.id = m.conversation_id
                WHERE
                    (c.user_a = %s OR c.user_b = %s)
                    AND m.sender_id <> %s
                    AND m.recipient_read_at IS NULL
                    AND NOT EXISTS (
                        SELECT 1 FROM blocks b
                        WHERE (b.blocker_id = c.user_a AND b.blocked_id = c.user_b)
                           OR (b.blocker_id = c.user_b AND b.blocked_id = c.user_a)
                    )
                """,
                (
                    user["id"],
                    user["id"],
                    user["id"],
                ),
            )

            return {
                "ok": True,
                "unread_count": cursor.fetchone()["unread_count"],
            }

@app.get("/api/admin/moderation/moderator-capability")
def moderator_ui_capability(user: dict = Depends(current_user)):
    require_active_account(user)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """SELECT reviewer_gender, can_review_verification, can_review_reports
                   FROM moderator_roles WHERE user_id = %s AND active""",
                (user["id"],),
            )
            role = cursor.fetchone()
    return {"is_moderator": role is not None,
            "reviewer_gender": role["reviewer_gender"] if role else None,
            "can_review_verification": bool(role and role["can_review_verification"]),
            "can_review_reports": bool(role and role["can_review_reports"])}


@app.get("/api/admin/moderation/witnesses")
def list_witness_moderators(user: dict = Depends(current_user)):
    with database_connection() as connection:
        with connection.cursor() as cursor:
            require_report_moderator(connection, user)
            cursor.execute(
                """SELECT mr.user_id, COALESCE(u.display_name, 'Moderator') AS display_name,
                          mr.reviewer_gender
                   FROM moderator_roles mr JOIN users u ON u.id = mr.user_id
                   WHERE mr.active AND mr.can_review_reports AND mr.user_id <> %s
                     AND mr.reviewer_gender IN ('male', 'female')
                   ORDER BY display_name, mr.user_id""",
                (user["id"],),
            )
            return {"moderators": cursor.fetchall()}


@app.get("/api/admin/moderation/my-requests")
def get_my_permanent_ban_requests(user: dict = Depends(current_user)):
    with database_connection() as connection:
        with connection.cursor() as cursor:
            require_report_moderator(connection, user)
            cursor.execute(
                """SELECT p.id::text, p.target_user_id, target.display_name AS target_name,
                          p.report_id::text, p.reason, p.status, p.witness_user_id,
                          witness.display_name AS witness_name, p.created_at, p.qualified_at,
                          COUNT(v.moderator_user_id) FILTER (WHERE v.vote = 'support' AND v.moderator_gender = 'male') AS male_support,
                          COUNT(v.moderator_user_id) FILTER (WHERE v.vote = 'support' AND v.moderator_gender = 'female') AS female_support,
                          BOOL_OR(v.moderator_user_id = %s AND v.vote = 'support') AS already_supported
                   FROM permanent_ban_proposals p
                   JOIN users target ON target.id = p.target_user_id
                   LEFT JOIN users witness ON witness.id = p.witness_user_id
                   LEFT JOIN permanent_ban_proposal_votes v ON v.proposal_id = p.id
                   WHERE p.opened_by = %s OR p.witness_user_id = %s
                   GROUP BY p.id, target.display_name, witness.display_name
                   ORDER BY p.created_at DESC LIMIT 100""",
                (user["id"], user["id"], user["id"]),
            )
            return {"requests": cursor.fetchall()}


@app.get("/api/admin/moderation/recommendations")
def get_moderation_recommendations(user: dict = Depends(current_user)):
    require_active_account(user)
    with database_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1 FROM moderation_platform_admins WHERE user_id = %s", (user["id"],))
            is_admin = cursor.fetchone() is not None
            if is_admin:
                cursor.execute(
                    """SELECT r.id::text, r.submitted_by, COALESCE(u.display_name, 'Moderator') AS author_name,
                              r.category, r.title, r.details, r.status, r.admin_note,
                              r.created_at, r.updated_at
                       FROM moderation_recommendations r JOIN users u ON u.id = r.submitted_by
                       ORDER BY CASE r.status WHEN 'new' THEN 0 WHEN 'reviewing' THEN 1 ELSE 2 END,
                                r.created_at DESC LIMIT 200"""
                )
            else:
                cursor.execute("SELECT 1 FROM moderator_roles WHERE user_id = %s AND active AND (can_review_reports OR can_review_verification)", (user["id"],))
                if cursor.fetchone() is None:
                    raise HTTPException(status_code=403, detail="An active moderator role is required")
                cursor.execute(
                    """SELECT r.id::text, r.submitted_by, COALESCE(u.display_name, 'Moderator') AS author_name,
                              r.category, r.title, r.details, r.status,
                              r.created_at, r.updated_at
                       FROM moderation_recommendations r JOIN users u ON u.id = r.submitted_by
                       WHERE r.submitted_by = %s ORDER BY r.created_at DESC LIMIT 100""",
                    (user["id"],),
                )
            return {"recommendations": cursor.fetchall()}


@app.post("/api/admin/moderation/recommendations", status_code=201)
def submit_moderation_recommendation(payload: ModeratorRecommendationCreate,
                                    user: dict = Depends(current_user)):
    category = payload.category.strip().lower()
    if category not in {"security", "member_safety", "verification", "workflow", "other"}:
        raise HTTPException(status_code=400, detail="Select a valid recommendation category")
    title, details = payload.title.strip(), payload.details.strip()
    if len(title) < 5 or len(details) < 10:
        raise HTTPException(status_code=400, detail="Add a clear title and at least 10 characters of detail")
    with database_connection() as connection:
        with connection.cursor() as cursor:
            require_active_account(user)
            cursor.execute(
                """SELECT 1 FROM moderator_roles WHERE user_id = %s AND active
                   AND (can_review_reports OR can_review_verification)""",
                (user["id"],),
            )
            if cursor.fetchone() is None:
                raise HTTPException(status_code=403, detail="An active moderator role is required")
            cursor.execute(
                """INSERT INTO moderation_recommendations (submitted_by, category, title, details)
                   VALUES (%s, %s, %s, %s) RETURNING id::text""",
                (user["id"], category, title, details),
            )
            row = cursor.fetchone()
            cursor.execute(
                """INSERT INTO notifications
                   (recipient_id, actor_id, notification_type, title, body, target_screen, target_id)
                   SELECT ma.user_id, %s, 'moderation_recommendation', 'Moderator recommendation received',
                          %s, 'moderator_recommendations', %s
                   FROM moderation_platform_admins ma
                   JOIN users u ON u.id = ma.user_id AND u.account_status = 'active'
                   ON CONFLICT DO NOTHING""",
                (user["id"], title[:200], row["id"]),
            )
            _write_moderator_log(cursor, actor_id=user["id"], event_type="recommendation_submitted",
                                 reason=title, metadata={"category": category, "recommendation_id": row["id"]})
            return {"ok": True, "id": row["id"]}


@app.put("/api/admin/moderation/recommendations/{recommendation_id}")
def decide_moderation_recommendation(recommendation_id: str,
                                     payload: ModeratorRecommendationDecision,
                                     user: dict = Depends(current_user)):
    if payload.status not in {"reviewing", "planned", "declined", "completed"}:
        raise HTTPException(status_code=400, detail="Select a valid recommendation status")
    try:
        recommendation_uuid = uuid.UUID(recommendation_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Recommendation not found")
    with database_connection() as connection:
        with connection.cursor() as cursor:
            require_platform_admin(connection, user)
            cursor.execute(
                """UPDATE moderation_recommendations SET status = %s, admin_note = %s,
                          updated_at = NOW(), reviewed_by = %s
                   WHERE id = %s RETURNING submitted_by, title""",
                (payload.status, payload.admin_note.strip(), user["id"], recommendation_uuid),
            )
            row = cursor.fetchone()
            if row is None:
                raise HTTPException(status_code=404, detail="Recommendation not found")
            cursor.execute(
                """INSERT INTO notifications
                   (recipient_id, actor_id, notification_type, title, body, target_screen, target_id)
                   VALUES (%s, %s, 'moderation_recommendation_update', 'Recommendation reviewed',
                           %s, 'moderator_recommendations', %s)""",
                (row["submitted_by"], user["id"], f"Your recommendation status is now {payload.status}.", str(recommendation_uuid)),
            )
            _write_moderator_log(cursor, actor_id=user["id"], event_type="recommendation_decided",
                                 reason=payload.admin_note.strip(), metadata={"status": payload.status,
                                 "recommendation_id": str(recommendation_uuid)})
    return {"ok": True, "status": payload.status}


@app.post("/api/admin/moderation/sanctions/{sanction_id}/override")
def admin_override_moderator_sanction(sanction_id: str, payload: SanctionOverrideCreate,
                                      user: dict = Depends(current_user)):
    try:
        sanction_uuid = uuid.UUID(sanction_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Temporary restriction not found")
    with database_connection() as connection:
        with connection.cursor() as cursor:
            require_platform_admin(connection, user)
            cursor.execute(
                """SELECT id, target_user_id, sanction_type, revoked_at, expires_at
                   FROM moderation_sanctions WHERE id = %s FOR UPDATE""",
                (sanction_uuid,),
            )
            sanction = cursor.fetchone()
            if sanction is None:
                raise HTTPException(status_code=404, detail="Temporary restriction not found")
            if sanction["revoked_at"] is not None or sanction["expires_at"] <= datetime.now(timezone.utc):
                raise HTTPException(status_code=409, detail="This moderator action is no longer active")
            cursor.execute("UPDATE moderation_sanctions SET revoked_at = NOW(), revoked_by = %s WHERE id = %s",
                           (user["id"], sanction_uuid))
            _write_moderator_log(cursor, actor_id=user["id"], event_type="admin_overrode_moderator_sanction",
                                 target_id=sanction["target_user_id"], sanction_id=str(sanction_uuid),
                                 reason=payload.reason.strip(), metadata={"sanction_type": sanction["sanction_type"]})
            cursor.execute(
                """INSERT INTO notifications
                   (recipient_id, actor_id, notification_type, title, body, target_screen, target_id)
                   VALUES (%s, %s, 'moderation_restriction', 'Account restriction lifted', %s, 'profile', %s)""",
                (sanction["target_user_id"], user["id"], payload.reason.strip()[:500], sanction["target_user_id"]),
            )
    return {"ok": True, "revoked": True}


@app.post("/api/admin/moderation/logs/{log_id}/override")
def admin_override_moderator_decision(log_id: int, payload: SanctionOverrideCreate,
                                      user: dict = Depends(current_user)):
    """Reverse supported moderator decisions with a separate immutable audit."""
    reason = payload.reason.strip()
    if len(reason) < 10:
        raise HTTPException(status_code=400, detail="Enter a reason with at least 10 characters")
    with database_connection() as connection:
        with connection.cursor() as cursor:
            require_platform_admin(connection, user)
            cursor.execute(
                """SELECT id, actor_user_id, target_user_id, report_id::text,
                          event_type, metadata
                   FROM moderator_action_logs WHERE id = %s""",
                (log_id,),
            )
            action = cursor.fetchone()
            if action is None:
                raise HTTPException(status_code=404, detail="Moderator action not found")

            if action["event_type"] in {"report_resolved", "report_dismissed"} and action["report_id"]:
                override_type = "reopen_report"
                cursor.execute(
                    """SELECT reporter_id, reported_user_id, status, appeal_status
                       FROM reports WHERE id = %s FOR UPDATE""",
                    (action["report_id"],),
                )
                report = cursor.fetchone()
                if report is None:
                    raise HTTPException(status_code=404, detail="Report no longer exists")
                if user["id"] in {report["reporter_id"], report["reported_user_id"]}:
                    raise HTTPException(status_code=403, detail="You cannot override a report involving your account")
                if report["status"] not in {"resolved", "dismissed"} or report["appeal_status"] == "pending":
                    raise HTTPException(status_code=409, detail="This report is not currently eligible to reopen")
                cursor.execute(
                    """SELECT MAX(id) AS latest_id FROM moderator_action_logs
                       WHERE report_id = %s AND event_type IN ('report_resolved', 'report_dismissed')""",
                    (action["report_id"],),
                )
                latest_action = cursor.fetchone()["latest_id"]
                if latest_action != action["id"]:
                    raise HTTPException(status_code=409, detail="A newer moderator decision exists for this report")
                cursor.execute(
                    """UPDATE reports SET status = 'pending', reviewed_at = NULL,
                              reviewed_by = NULL, outcome_code = NULL,
                              evidence_expires_at = NULL, updated_at = NOW()
                       WHERE id = %s""",
                    (action["report_id"],),
                )
                target_user_id = report["reported_user_id"]
                cursor.execute(
                    """INSERT INTO notifications
                       (recipient_id, actor_id, notification_type, title, body, target_screen, target_id)
                       VALUES (%s, %s, 'report_resolved', 'Report reopened for review', %s, 'my_reports', %s)""",
                    (report["reporter_id"], user["id"], reason[:500], action["report_id"]),
                )
            elif action["event_type"] == "verification_approve":
                override_type = "revoke_verification_approval"
                metadata = action["metadata"] or {}
                request_id = metadata.get("request_id") if isinstance(metadata, dict) else None
                try:
                    request_uuid = uuid.UUID(str(request_id))
                except (TypeError, ValueError):
                    raise HTTPException(status_code=409, detail="Verification audit reference is unavailable")
                cursor.execute(
                    """SELECT user_id, status, reviewed_by FROM verification_requests
                       WHERE id = %s FOR UPDATE""",
                    (request_uuid,),
                )
                request = cursor.fetchone()
                if request is None or request["user_id"] != action["target_user_id"]:
                    raise HTTPException(status_code=404, detail="Verification request no longer exists")
                if request["status"] != "approved" or request["reviewed_by"] != action["actor_user_id"]:
                    raise HTTPException(status_code=409, detail="This verification approval is no longer current")
                cursor.execute(
                    """SELECT MAX(id) AS latest_id FROM moderator_action_logs
                       WHERE target_user_id = %s AND event_type = 'verification_approve'
                         AND metadata->>'request_id' = %s""",
                    (request["user_id"], str(request_uuid)),
                )
                latest_action = cursor.fetchone()["latest_id"]
                if latest_action != action["id"]:
                    raise HTTPException(status_code=409, detail="A newer verification decision exists")
                if user["id"] == request["user_id"]:
                    raise HTTPException(status_code=403, detail="You cannot override your own verification")
                cursor.execute(
                    """UPDATE verification_requests SET status = 'resubmission_required',
                              reviewed_at = NOW(), reviewed_by = %s, reviewer_notes = %s,
                              rejection_reason = %s
                       WHERE id = %s""",
                    (user["id"], reason, reason, request_uuid),
                )
                cursor.execute(
                    "UPDATE profiles SET is_verified = FALSE, updated_at = NOW() WHERE user_id = %s",
                    (request["user_id"],),
                )
                target_user_id = request["user_id"]
                cursor.execute(
                    """INSERT INTO notifications
                       (recipient_id, actor_id, notification_type, title, body, target_screen, target_id)
                       VALUES (%s, %s, 'verification_rejected', 'Verification review updated', %s, 'profile', %s)""",
                    (target_user_id, user["id"], reason[:500], str(request_uuid)),
                )
            else:
                raise HTTPException(status_code=409, detail="This moderator action cannot be overridden here")

            cursor.execute(
                """INSERT INTO moderation_decision_overrides
                   (original_log_id, overridden_by, target_user_id, override_type, reason)
                   VALUES (%s, %s, %s, %s, %s) ON CONFLICT (original_log_id) DO NOTHING
                   RETURNING id""",
                (action["id"], user["id"], target_user_id, override_type, reason),
            )
            override = cursor.fetchone()
            if override is None:
                raise HTTPException(status_code=409, detail="This moderator decision was already overridden")
            _write_moderator_log(
                cursor, actor_id=user["id"], target_id=target_user_id,
                report_id=action["report_id"], event_type="admin_overrode_moderator_decision",
                reason=reason, metadata={"original_log_id": action["id"],
                                         "override_type": override_type,
                                         "override_id": override["id"]},
            )
    return {"ok": True, "override_type": override_type}


@app.get("/api/admin/users")
def search_admin_user_directory(query: str = "", offset: int = 0,
                                limit: int = 50,
                                user: dict = Depends(current_user)):
    """Search the account directory. Search terms are never written to audit."""
    term = query.strip()
    if offset < 0 or offset > 100000:
        raise HTTPException(status_code=400, detail="Invalid result offset")
    if limit < 1 or limit > 50:
        raise HTTPException(status_code=400, detail="Page size must be between 1 and 50")
    if term and len(term) < 2:
        raise HTTPException(status_code=400, detail="Enter at least two characters")
    escaped = term.replace("!", "!!").replace("%", "!%").replace("_", "!_")
    text_pattern = f"%{escaped}%" if term else "%"
    phone_digits = "".join(character for character in term if character.isdigit())
    phone_pattern = f"%{phone_digits}%" if len(phone_digits) >= 4 else ""

    with database_connection() as connection:
        with connection.cursor() as cursor:
            require_platform_admin(connection, user)
            cursor.execute(
                """SELECT u.id, u.email, u.display_name,
                          COALESCE(NULLIF(p.full_name, ''), u.display_name, '') AS full_name,
                          u.phone_number, u.account_status,
                          COALESCE(mr.reviewer_gender, '') AS reviewer_gender,
                          COALESCE(mr.can_review_verification, FALSE) AS can_review_verification,
                          COALESCE(mr.can_review_reports, FALSE) AS can_review_reports,
                          COALESCE(mr.active, FALSE) AS moderator_active,
                          EXISTS (SELECT 1 FROM moderation_platform_admins ma
                                  WHERE ma.user_id = u.id) AS platform_admin
                   FROM users u
                   LEFT JOIN profiles p ON p.user_id = u.id
                   LEFT JOIN moderator_roles mr ON mr.user_id = u.id
                   WHERE (%s = ''
                       OR COALESCE(u.email, '') ILIKE %s ESCAPE '!'
                       OR COALESCE(p.full_name, u.display_name, '') ILIKE %s ESCAPE '!'
                       OR (%s <> '' AND regexp_replace(
                             COALESCE(u.phone_number, ''), '[^0-9]', '', 'g') LIKE %s))
                   ORDER BY u.created_at DESC, u.id
                   LIMIT %s OFFSET %s""",
                (term, text_pattern, text_pattern, phone_pattern,
                 phone_pattern, limit + 1, offset),
            )
            rows = cursor.fetchall()
            has_more = len(rows) > limit
            rows = rows[:limit]
            _write_admin_user_management_audit(
                cursor, actor_id=user["id"], action="directory_search",
                metadata={"query_length": len(term), "offset": offset,
                          "result_count": len(rows)},
            )
            return {"users": rows, "offset": offset,
                    "next_offset": offset + len(rows) if has_more else None}


@app.put("/api/admin/users/{target_user_id}/moderator-role")
def set_admin_moderator_role(target_user_id: str,
                             payload: AdminModeratorRoleUpdate,
                             user: dict = Depends(current_user)):
    gender = payload.reviewer_gender.strip().lower()
    reason = payload.reason.strip()
    if gender not in {"male", "female"}:
        raise HTTPException(status_code=400, detail="Choose male or female reviewer gender")
    if not payload.can_review_verification and not payload.can_review_reports:
        raise HTTPException(status_code=400, detail="Enable at least one moderator capability")
    with database_connection() as connection:
        with connection.cursor() as cursor:
            require_platform_admin(connection, user)
            cursor.execute(
                "SELECT id, account_status FROM users WHERE id = %s FOR UPDATE",
                (target_user_id,),
            )
            target = cursor.fetchone()
            if target is None or target["account_status"] != "active":
                raise HTTPException(status_code=404, detail="Active account not found")
            cursor.execute(
                """INSERT INTO moderator_roles
                   (user_id, reviewer_gender, can_review_verification,
                    can_review_reports, active, added_by)
                   VALUES (%s, %s, %s, %s, TRUE, %s)
                   ON CONFLICT (user_id) DO UPDATE SET
                     reviewer_gender = EXCLUDED.reviewer_gender,
                     can_review_verification = EXCLUDED.can_review_verification,
                     can_review_reports = EXCLUDED.can_review_reports,
                     active = TRUE, added_by = EXCLUDED.added_by""",
                (target_user_id, gender, payload.can_review_verification,
                 payload.can_review_reports, user["id"]),
            )
            for enabled, table in ((payload.can_review_verification, "verification_admins"),
                                   (payload.can_review_reports, "report_admins")):
                if enabled:
                    cursor.execute(
                        f"INSERT INTO {table} (user_id, added_by) VALUES (%s, %s) "
                        "ON CONFLICT (user_id) DO NOTHING",
                        (target_user_id, user["id"]),
                    )
                else:
                    cursor.execute(f"DELETE FROM {table} WHERE user_id = %s",
                                   (target_user_id,))
            _write_admin_user_management_audit(
                cursor, actor_id=user["id"], target_id=target_user_id,
                action="moderator_role_set", reason=reason,
                metadata={"reviewer_gender": gender,
                          "can_review_verification": payload.can_review_verification,
                          "can_review_reports": payload.can_review_reports},
            )
            _write_moderator_log(
                cursor, actor_id=user["id"], target_id=target_user_id,
                event_type="admin_moderator_role_set", reason=reason,
                metadata={"reviewer_gender": gender,
                          "can_review_verification": payload.can_review_verification,
                          "can_review_reports": payload.can_review_reports},
            )
    return {"ok": True, "reviewer_gender": gender,
            "can_review_verification": payload.can_review_verification,
            "can_review_reports": payload.can_review_reports, "active": True}


@app.post("/api/admin/users/{target_user_id}/moderator-role/remove")
def remove_admin_moderator_role(target_user_id: str, payload: AdminReasonCreate,
                                user: dict = Depends(current_user)):
    reason = payload.reason.strip()
    if len(reason) < 10:
        raise HTTPException(status_code=400, detail="Enter a reason with at least 10 characters")
    with database_connection() as connection:
        with connection.cursor() as cursor:
            require_platform_admin(connection, user)
            cursor.execute("SELECT id FROM users WHERE id = %s FOR UPDATE", (target_user_id,))
            if cursor.fetchone() is None:
                raise HTTPException(status_code=404, detail="Account not found")
            cursor.execute("SELECT reviewer_gender, can_review_verification, can_review_reports, active "
                           "FROM moderator_roles WHERE user_id = %s FOR UPDATE", (target_user_id,))
            previous = cursor.fetchone()
            if previous is None:
                raise HTTPException(status_code=409, detail="This account is not a moderator")
            cursor.execute("DELETE FROM verification_admins WHERE user_id = %s", (target_user_id,))
            cursor.execute("DELETE FROM report_admins WHERE user_id = %s", (target_user_id,))
            cursor.execute("DELETE FROM moderator_roles WHERE user_id = %s", (target_user_id,))
            _write_admin_user_management_audit(
                cursor, actor_id=user["id"], target_id=target_user_id,
                action="moderator_role_removed", reason=reason,
                metadata={"previous_reviewer_gender": previous["reviewer_gender"],
                          "previous_verification": previous["can_review_verification"],
                          "previous_reports": previous["can_review_reports"],
                          "previous_active": previous["active"]},
            )
            _write_moderator_log(cursor, actor_id=user["id"], target_id=target_user_id,
                                 event_type="admin_moderator_role_removed", reason=reason)
    return {"ok": True, "moderator": False}


@app.get("/api/admin/users/{target_user_id}/activity")
def get_admin_user_activity(target_user_id: str, limit: int = 100,
                            user: dict = Depends(current_user)):
    if limit < 1 or limit > 200:
        raise HTTPException(status_code=400, detail="Activity page size must be between 1 and 200")
    with database_connection() as connection:
        with connection.cursor() as cursor:
            require_platform_admin(connection, user)
            cursor.execute("SELECT id FROM users WHERE id = %s", (target_user_id,))
            if cursor.fetchone() is None:
                raise HTTPException(status_code=404, detail="Account not found")
            _write_admin_user_management_audit(
                cursor, actor_id=user["id"], target_id=target_user_id,
                action="account_activity_viewed",
            )
            cursor.execute(
                """WITH events AS (
                     SELECT action AS event_type, occurred_at, actor_user_id,
                            target_user_id, reason
                     FROM admin_user_management_audit
                     WHERE target_user_id = %s OR actor_user_id = %s
                     UNION ALL
                     SELECT event_type, occurred_at, actor_user_id,
                            target_user_id, reason
                     FROM moderator_action_logs
                     WHERE target_user_id = %s OR actor_user_id = %s
                     UNION ALL
                     SELECT sanction_type AS event_type, created_at AS occurred_at,
                            actor_user_id, target_user_id, reason_code AS reason
                     FROM moderation_sanctions
                     WHERE target_user_id = %s OR actor_user_id = %s
                     UNION ALL
                     SELECT CASE WHEN reporter_id = %s THEN 'report_submitted'
                                 ELSE 'report_received' END AS event_type,
                            created_at AS occurred_at, reporter_id AS actor_user_id,
                            reported_user_id AS target_user_id, reason
                     FROM reports WHERE reporter_id = %s OR reported_user_id = %s
                   )
                   SELECT event_type, occurred_at, actor_user_id, target_user_id, reason
                   FROM events ORDER BY occurred_at DESC LIMIT %s""",
                (target_user_id, target_user_id,
                 target_user_id, target_user_id,
                 target_user_id, target_user_id,
                 target_user_id, target_user_id, target_user_id, limit),
            )
            return {"activities": cursor.fetchall()}


@app.post("/api/admin/users/{target_user_id}/delete")
def admin_delete_user_account(target_user_id: str, payload: AdminAccountDeleteCreate,
                              user: dict = Depends(current_user)):
    reason = payload.reason.strip()
    if len(reason) < 10:
        raise HTTPException(status_code=400, detail="Enter a reason with at least 10 characters")
    verification_files: list[str | None] = []
    photo_files: list[str] = []
    with database_connection() as connection:
        with connection.cursor() as cursor:
            require_platform_admin(connection, user)
            cursor.execute("SELECT id, email, account_status FROM users WHERE id = %s FOR UPDATE",
                           (target_user_id,))
            target = cursor.fetchone()
            if target is None or target["account_status"] == "deleted":
                raise HTTPException(status_code=404, detail="Account not found")
            if target_user_id == user["id"]:
                raise HTTPException(status_code=400, detail="You cannot delete your own administrator account")
            cursor.execute("SELECT 1 FROM moderation_platform_admins WHERE user_id = %s",
                           (target_user_id,))
            if cursor.fetchone() is not None:
                raise HTTPException(status_code=409, detail="Platform administrator accounts require the separate operator recovery process")
            if payload.deny_email:
                if not target["email"]:
                    raise HTTPException(status_code=409, detail="There is no email identifier to denylist")
                cursor.execute(
                    """INSERT INTO registration_identifier_denylist
                       (identifier_type, identifier_hmac, added_by, reason)
                       VALUES ('email', %s, %s, %s) ON CONFLICT DO NOTHING""",
                    (denylist_identifier_hmac("email", target["email"]), user["id"], reason),
                )
            if payload.deny_phone:
                cursor.execute(
                    """INSERT INTO registration_identifier_denylist
                       (identifier_type, identifier_hmac, added_by, reason)
                       VALUES ('phone', %s, %s, %s) ON CONFLICT DO NOTHING""",
                    (denylist_identifier_hmac("phone", payload.deny_phone), user["id"], reason),
                )
            cursor.execute("SELECT file_path FROM profile_photos WHERE user_id = %s", (target_user_id,))
            photo_files = [row["file_path"] for row in cursor.fetchall() if row["file_path"]]
            cursor.execute("DELETE FROM profile_photos WHERE user_id = %s", (target_user_id,))
            cursor.execute("DELETE FROM matrimonial_preferences WHERE user_id = %s", (target_user_id,))
            cursor.execute("DELETE FROM profiles WHERE user_id = %s", (target_user_id,))
            cursor.execute(
                """SELECT guardian_id_file, authority_proof_file, confirmation_video_file
                   FROM verification_requests WHERE user_id = %s""", (target_user_id,))
            for row in cursor.fetchall():
                verification_files.extend((row["guardian_id_file"], row["authority_proof_file"],
                                           row["confirmation_video_file"]))
            cursor.execute("DELETE FROM verification_requests WHERE user_id = %s", (target_user_id,))
            if target["email"]:
                cursor.execute(
                    "DELETE FROM email_otps WHERE email = %s",
                    (normalize_email(target["email"]),),
                )
            cursor.execute(
                "DELETE FROM api_password_credentials WHERE user_id = %s",
                (target_user_id,),
            )
            cursor.execute(
                "DELETE FROM auth_identities WHERE user_id = %s",
                (target_user_id,),
            )
            cursor.execute("DELETE FROM verification_admins WHERE user_id = %s", (target_user_id,))
            cursor.execute("DELETE FROM report_admins WHERE user_id = %s", (target_user_id,))
            cursor.execute("DELETE FROM moderator_roles WHERE user_id = %s", (target_user_id,))
            cursor.execute(
                """UPDATE users SET account_status = 'deleted', email = NULL,
                   phone_number = NULL, display_name = 'Deleted member' WHERE id = %s""",
                (target_user_id,),
            )
            _write_admin_user_management_audit(
                cursor, actor_id=user["id"], target_id=target_user_id,
                action="account_deleted", reason=reason,
                metadata={"deny_email": payload.deny_email,
                          "deny_phone": bool(payload.deny_phone)},
            )
            _write_moderator_log(cursor, actor_id=user["id"], target_id=target_user_id,
                                 event_type="admin_account_deleted", reason=reason,
                                 metadata={"deny_email": payload.deny_email,
                                           "deny_phone": bool(payload.deny_phone)})
    _delete_private_evidence(verification_files)
    photo_root = profile_photo_storage_dir().resolve()
    for filename in photo_files:
        if _PROFILE_PHOTO_NAME.fullmatch(filename or ""):
            (photo_root / filename).unlink(missing_ok=True)
    revoke_all_user_sessions(target_user_id)
    return {"ok": True, "account_status": "deleted"}


@app.post("/api/admin/moderation/users/{target_user_id}/permanent-ban")
def admin_permanently_ban_user(target_user_id: str, payload: AdminDirectBanCreate,
                               user: dict = Depends(current_user)):
    reason = payload.reason.strip()
    if len(reason) < 10:
        raise HTTPException(status_code=400, detail="Enter a reason with at least 10 characters")
    with database_connection() as connection:
        with connection.cursor() as cursor:
            require_platform_admin(connection, user)
            cursor.execute("SELECT id, email, account_status FROM users WHERE id = %s FOR UPDATE", (target_user_id,))
            target = cursor.fetchone()
            if target is None or target["account_status"] in {"deleted", "disabled"}:
                raise HTTPException(status_code=404, detail="Active account not found")
            if target_user_id == user["id"]:
                raise HTTPException(status_code=400, detail="You cannot ban your own administrator account")
            cursor.execute("SELECT 1 FROM moderation_platform_admins WHERE user_id = %s",
                           (target_user_id,))
            if cursor.fetchone() is not None:
                raise HTTPException(status_code=409, detail="Platform administrator accounts cannot be banned from this screen")
            cursor.execute("UPDATE users SET account_status = 'disabled' WHERE id = %s", (target_user_id,))
            cursor.execute("DELETE FROM verification_admins WHERE user_id = %s", (target_user_id,))
            cursor.execute("DELETE FROM report_admins WHERE user_id = %s", (target_user_id,))
            cursor.execute("UPDATE moderator_roles SET active = FALSE WHERE user_id = %s", (target_user_id,))
            if payload.deny_email:
                if not target["email"]:
                    raise HTTPException(status_code=409, detail="This account has no email to denylist")
                cursor.execute(
                    """INSERT INTO registration_identifier_denylist
                       (identifier_type, identifier_hmac, added_by, reason)
                       VALUES ('email', %s, %s, %s) ON CONFLICT DO NOTHING""",
                    (denylist_identifier_hmac("email", target["email"]), user["id"], reason),
                )
            if payload.deny_phone:
                cursor.execute(
                    """INSERT INTO registration_identifier_denylist
                       (identifier_type, identifier_hmac, added_by, reason)
                       VALUES ('phone', %s, %s, %s) ON CONFLICT DO NOTHING""",
                    (denylist_identifier_hmac("phone", payload.deny_phone), user["id"], reason),
                )
            _write_moderator_log(cursor, actor_id=user["id"], target_id=target_user_id,
                                 event_type="admin_direct_permanent_ban", reason=reason,
                                 metadata={"deny_email": payload.deny_email, "deny_phone": bool(payload.deny_phone)})
            _write_admin_user_management_audit(
                cursor, actor_id=user["id"], target_id=target_user_id,
                action="account_permanently_banned", reason=reason,
                metadata={"deny_email": payload.deny_email,
                          "deny_phone": bool(payload.deny_phone)},
            )
            cursor.execute(
                """INSERT INTO notifications
                   (recipient_id, actor_id, notification_type, title, body, target_screen, target_id)
                   VALUES (%s, %s, 'account_permanently_banned', 'Account permanently disabled', %s, 'profile', %s)""",
                (target_user_id, user["id"], reason[:500], target_user_id),
            )
    revoke_all_user_sessions(target_user_id)
    return {"ok": True, "account_status": "disabled"}
