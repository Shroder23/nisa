import unittest
import sys
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import main


class PasswordLoginCredentialTests(unittest.TestCase):
    @patch("main.verify_password_hash", return_value=False)
    def test_missing_password_row_has_distinct_safe_code(self, verify_hash):
        row = {"id": "migrated-user", "salt_hex": None, "password_hash_hex": None}

        with self.assertRaises(HTTPException) as raised:
            main.password_login_failure(row, "entered-password")

        self.assertEqual(raised.exception.status_code, 409)
        self.assertEqual(
            raised.exception.detail["code"], "password_setup_required"
        )
        verify_hash.assert_called_once()

    @patch("main.verify_password_hash", return_value=False)
    def test_incorrect_password_keeps_generic_401(self, _verify_hash):
        row = {"id": "user", "salt_hex": "ab", "password_hash_hex": "cd"}

        with self.assertRaises(HTTPException) as raised:
            main.password_login_failure(row, "wrong-password")

        self.assertEqual(raised.exception.status_code, 401)
        self.assertEqual(raised.exception.detail, "Email or password is incorrect.")

    @patch("main.verify_password_hash", return_value=False)
    def test_unknown_email_keeps_generic_401(self, verify_hash):
        with self.assertRaises(HTTPException) as raised:
            main.password_login_failure(None, "entered-password")

        self.assertEqual(raised.exception.status_code, 401)
        self.assertEqual(raised.exception.detail, "Email or password is incorrect.")
        verify_hash.assert_called_once()

    @patch("main.verify_password_hash", return_value=True)
    def test_valid_password_has_no_failure(self, _verify_hash):
        row = {"id": "user", "salt_hex": "ab", "password_hash_hex": "cd"}
        self.assertIsNone(main.password_login_failure(row, "correct-password"))


if __name__ == "__main__":
    unittest.main()
