from sqlalchemy import create_engine, text
from config import Config

conf = Config()
engine = create_engine(conf.SQLALCHEMY_DATABASE_URI, pool_pre_ping=True)

def execute_proc(name, params=()):
    conn = None
    try:
        conn = engine.raw_connection()
        cursor = conn.cursor()
        cursor.callproc(name, params)
        conn.commit()
        
        headers, data = [], []
        for result in cursor.stored_results():
            if result.description:
                headers = [col[0] for col in result.description]
                raw_rows = result.fetchall()
                data = [[str(c).strip() if c is not None else "" for c in row] 
                        for row in raw_rows]
                break 
        return headers, data
    except Exception as e:
        if conn: conn.rollback()
        print(f"Database error in {name}: {e}")
        return [], []
    finally:
        if 'cursor' in locals() and cursor: cursor.close()
        if conn: conn.close()
