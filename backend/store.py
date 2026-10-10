import base64
from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import secrets
import sqlite3
import time
import uuid


def digest(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def challenge(verifier: str) -> str:
    return base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()


class Store:
    def __init__(self, directory: Path):
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.path = directory / "state.sqlite3"
        with self.connect() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS transactions (
                    id TEXT PRIMARY KEY, state TEXT, verifier TEXT, nonce TEXT,
                    mobile_challenge TEXT, mobile_state TEXT, expires REAL);
                CREATE TABLE IF NOT EXISTS tickets (
                    id TEXT PRIMARY KEY, user TEXT, challenge TEXT, expires REAL);
                CREATE TABLE IF NOT EXISTS sessions (
                    id TEXT PRIMARY KEY, user TEXT, expires REAL);
                CREATE TABLE IF NOT EXISTS jobs (
                    id TEXT PRIMARY KEY, owner TEXT, request_key TEXT, request_hash TEXT,
                    status TEXT, progress REAL, message TEXT, plan TEXT, manifest TEXT,
                    error TEXT, created REAL, updated REAL, UNIQUE(owner, request_key));
                CREATE TABLE IF NOT EXISTS plan_requests (owner TEXT, created REAL);
                CREATE INDEX IF NOT EXISTS plan_requests_owner ON plan_requests(owner, created);
            """)
        self.path.chmod(0o600)

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=15)
        db.row_factory = sqlite3.Row
        try:
            with db:
                yield db
        finally:
            db.close()

    def new_transaction(self, mobile_challenge: str, mobile_state: str) -> dict:
        transaction = {
            "id": secrets.token_urlsafe(32), "state": secrets.token_urlsafe(32),
            "verifier": secrets.token_urlsafe(48), "nonce": secrets.token_urlsafe(32),
            "mobile_challenge": mobile_challenge, "mobile_state": mobile_state,
            "expires": time.time() + 600,
        }
        with self.connect() as db:
            db.execute("DELETE FROM transactions WHERE expires < ?", (time.time(),))
            db.execute("INSERT INTO transactions VALUES (:id,:state,:verifier,:nonce,:mobile_challenge,:mobile_state,:expires)", transaction)
        return transaction

    def take_transaction(self, transaction_id: str, state: str) -> dict:
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT * FROM transactions WHERE id=?", (transaction_id,)).fetchone()
            db.execute("DELETE FROM transactions WHERE id=?", (transaction_id,))
        if row is None or row["expires"] <= time.time() or not secrets.compare_digest(row["state"], state):
            raise ValueError("Sign-in could not be verified. Please try again.")
        return dict(row)

    def new_ticket(self, user: dict, mobile_challenge: str) -> str:
        code = secrets.token_urlsafe(32)
        with self.connect() as db:
            db.execute("DELETE FROM tickets WHERE expires < ?", (time.time(),))
            db.execute("INSERT INTO tickets VALUES (?,?,?,?)", (digest(code), json.dumps(user), mobile_challenge, time.time() + 120))
        return code

    def exchange_ticket(self, code: str, verifier: str, session_seconds: int) -> tuple[str, dict]:
        token = secrets.token_urlsafe(48)
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT * FROM tickets WHERE id=?", (digest(code),)).fetchone()
            if row is None or row["expires"] <= time.time() or not secrets.compare_digest(row["challenge"], challenge(verifier)):
                raise ValueError("Sign-in expired or could not be verified. Please try again.")
            db.execute("DELETE FROM tickets WHERE id=?", (digest(code),))
            db.execute("DELETE FROM sessions WHERE expires < ?", (time.time(),))
            db.execute("INSERT INTO sessions VALUES (?,?,?)", (digest(token), row["user"], time.time() + session_seconds))
        return token, json.loads(row["user"])

    def session(self, token: str) -> dict | None:
        with self.connect() as db:
            row = db.execute("SELECT user FROM sessions WHERE id=? AND expires>?", (digest(token), time.time())).fetchone()
        return json.loads(row["user"]) if row else None

    def logout(self, token: str):
        with self.connect() as db:
            db.execute("DELETE FROM sessions WHERE id=?", (digest(token),))

    def reserve_plan(self, owner: str, hourly_limit: int):
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            db.execute("DELETE FROM plan_requests WHERE created<?", (time.time() - 3600,))
            count = db.execute("SELECT COUNT(*) FROM plan_requests WHERE owner=?", (owner,)).fetchone()[0]
            if count >= hourly_limit:
                raise ValueError("You have reached this service's hourly idea limit. Try again later.")
            db.execute("INSERT INTO plan_requests VALUES (?,?)", (owner, time.time()))

    def new_job(self, owner: str, request_key: str, request_payload: dict, daily_limit: int) -> tuple[dict, bool]:
        request_hash = digest(json.dumps(request_payload, sort_keys=True, ensure_ascii=False))
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            existing = db.execute("SELECT * FROM jobs WHERE owner=? AND request_key=?", (owner, request_key)).fetchone()
            if existing:
                if existing["request_hash"] != request_hash:
                    raise ValueError("This generation key already belongs to another video.")
                return self._job(existing), False
            count = db.execute("SELECT COUNT(*) FROM jobs WHERE owner=? AND created>?", (owner, time.time() - 86400)).fetchone()[0]
            if count >= daily_limit:
                raise ValueError("You have reached this service's daily video limit.")
            active = db.execute("SELECT COUNT(*) FROM jobs WHERE owner=? AND status IN ('queued','running')", (owner,)).fetchone()[0]
            if active >= 2:
                raise ValueError("Two of your videos are already being generated. Wait or cancel one.")
            job_id = uuid.uuid4().hex
            now = time.time()
            db.execute("INSERT INTO jobs VALUES (?,?,?,?,?,?,?,?,?,?,?,?)", (
                job_id, owner, request_key, request_hash, "queued", 0, "Waiting to generate", json.dumps(request_payload),
                None, None, now, now))
            row = db.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
            return self._job(row), True

    @staticmethod
    def _job(row) -> dict:
        value = dict(row)
        value["plan"] = json.loads(value["plan"])
        value["manifest"] = json.loads(value["manifest"]) if value["manifest"] else None
        return value

    def job(self, job_id: str, owner: str) -> dict | None:
        with self.connect() as db:
            row = db.execute("SELECT * FROM jobs WHERE id=? AND owner=?", (job_id, owner)).fetchone()
        return self._job(row) if row else None

    def jobs(self, owner: str) -> list[dict]:
        with self.connect() as db:
            rows = db.execute("SELECT * FROM jobs WHERE owner=? ORDER BY created DESC LIMIT 20", (owner,)).fetchall()
        return [self._job(row) for row in rows]

    def update_job(self, job_id: str, **values):
        if not values.keys() <= {"status", "progress", "message", "manifest", "error"}:
            raise ValueError("Unsupported job field")
        if "manifest" in values:
            values["manifest"] = json.dumps(values["manifest"])
        values["updated"] = time.time()
        assignments = ",".join(f"{key}=?" for key in values)
        with self.connect() as db:
            db.execute(f"UPDATE jobs SET {assignments} WHERE id=? AND status NOT IN ('cancelled','completed','failed')", (*values.values(), job_id))

    def recover_jobs(self):
        with self.connect() as db:
            interrupted = [row[0] for row in db.execute("SELECT id FROM jobs WHERE status IN ('queued','running')").fetchall()]
            db.execute("UPDATE jobs SET status='failed',error='The AI service restarted. Create a new generation to retry.',updated=? WHERE status IN ('queued','running')", (time.time(),))
        return interrupted
