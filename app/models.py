from flask_login import UserMixin
from database import engine

class User(UserMixin):
    def __init__(self, id, username, name, role, role_desc):
        self.id = id
        self.username = username
        self.full_name = name
        self.role = role
        self.role_desc = role_desc

def get_user_by_id(uid):
    conn = engine.raw_connection()
    try:
        cursor = conn.cursor()
        cursor.callproc('GetUserByID', (int(uid),))
        for result in cursor.stored_results():
            res = result.fetchone()
            if res:
                return User(res[0], res[1], res[2], res[3], res[4])
    finally:
        cursor.close()
        conn.close()
    return None

def get_user_for_auth(username):
    conn = engine.raw_connection()
    try:
        cursor = conn.cursor()
        cursor.callproc('GetUserForAuth', (username,))
        for result in cursor.stored_results():
            return result.fetchone()
    finally:
        cursor.close()
        conn.close()
    return None


