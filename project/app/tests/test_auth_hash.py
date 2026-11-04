"""口令摘要必须与 SQL 侧逐字节一致，否则迁移回填的凭据全都登不上。

定标值来自实测：`project/sql/11-migration/migration-02-login-credentials.sql`
对 ``salt='m1'``、``password='000001'`` 算出的摘要是
``1E1B7D0D6A69C96EEDFEA681049626ABEFD6E6FB20AFCD2C9AE1EB79F4EA4192``。
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

from service.auth import employee_salt, hash_password, member_salt  # noqa: E402


def test_hash_matches_sql_side():
    assert hash_password("m1", "000001") == (
        "1E1B7D0D6A69C96EEDFEA681049626ABEFD6E6FB20AFCD2C9AE1EB79F4EA4192"
    )


def test_salt_derivation():
    assert member_salt(1) == "m1"
    assert member_salt(80) == "m80"
    assert employee_salt(3) == "e3"


def test_hash_is_uppercase_hex_of_len_64():
    digest = hash_password("m2", "000002")
    assert len(digest) == 64
    assert digest == digest.upper()
    assert all(c in "0123456789ABCDEF" for c in digest)


def test_different_salt_changes_digest():
    assert hash_password("m1", "000001") != hash_password("m2", "000001")
