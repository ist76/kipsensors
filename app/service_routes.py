from flask import Blueprint, render_template, request, redirect, url_for, flash, session, Response, abort
from sqlalchemy import create_engine, text
import json
import io
import re
import os
from datetime import datetime, date

# Импорт объектов из основного приложения
from config import Config
from database import engine, conf

service_bp = Blueprint('service', __name__)

# --- Вспомогательные функции ---
def json_serial(obj):
    from decimal import Decimal
    if isinstance(obj, (datetime, date)):
        return obj.isoformat()
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Type {type(obj)} not serializable")

def get_service_engine():
    if session.get('service_mode') and session.get('temp_db_user'):
        user = session.get('temp_db_user')
        pwd = session.get('temp_db_password')
        db = session.get('temp_db_name') or conf.DB_NAME 
        base_uri = Config.get_base_uri(user, pwd)
        full_uri = f"{base_uri}{db}"
        return create_engine(full_uri)
    return engine

def check_db_ready(current_engine):
    try:
        with current_engine.connect() as conn:
            result = conn.execute(text("SHOW TABLES LIKE 'Users'")).fetchone()
            return result is not None
    except:
        return False

# Маршруты авторизации и выбора БД
@service_bp.route('/auth', methods=['GET', 'POST'])
def auth():
    if request.method == 'POST':
        user = request.form.get('db_user')
        password = request.form.get('db_password')
        temp_uri = Config.get_base_uri(user, password)
        temp_engine = create_engine(temp_uri)
        
        try:
            with temp_engine.connect() as conn:
                result = conn.execute(text("SHOW DATABASES"))
                databases = [row[0] for row in result 
                             if row[0] not in ['information_schema', 'mysql', 'performance_schema', 'sys']]
            
            session.update({
                'service_mode': True,
                'temp_db_user': user,
                'temp_db_password': password,
                'available_dbs': databases
            })
            
            return render_template('service/db_select.html', databases=databases)
        except Exception:
            flash('Ошибка доступа к СУБД: проверьте логин/пароль или права доступа', 'danger')
        finally:
            temp_engine.dispose()
            
    return render_template('service/login.html')

@service_bp.route('/confirm_db', methods=['POST'])
def confirm_db():
    if not session.get('service_mode'): return abort(403)
    selected_db = request.form.get('selected_db')
    if selected_db:
        session['temp_db_name'] = selected_db
        flash(f"Рабочая база данных установлена: {selected_db}", "info")
    return redirect(url_for('service.panel'))

# Основная панель и действия
@service_bp.route('/panel')
def panel():
    if not session.get('service_mode'):
        return redirect(url_for('service.auth'))
    
    current_engine = get_service_engine()
    db_ready = check_db_ready(current_engine)
    roles, users = [], []

    if db_ready:
        try:
            with current_engine.connect() as conn:
                roles_res = conn.execute(text("SELECT role_name FROM Roles")).fetchall()
                roles = [r[0] for r in roles_res]
                
                raw_conn = current_engine.raw_connection()
                cursor = raw_conn.cursor()
                cursor.callproc('GetAllUsers')
                for result in cursor.stored_results():
                    users = result.fetchall()
                cursor.close()
                raw_conn.close()
        except Exception as e:
            flash(f"Ошибка чтения структуры: {e}", "warning")
            db_ready = False

    return render_template('service/panel.html', roles=roles, users=users, db_ready=db_ready)

@service_bp.route('/user_action', methods=['POST'])
def user_action():
    if not session.get('service_mode'): return abort(403)
    username = request.form.get('username')
    action = request.form.get('action')
    current_engine = get_service_engine()
    try:
        raw_conn = current_engine.raw_connection()
        cursor = raw_conn.cursor()
        if action == 'reset':
            cursor.callproc('ResetUserPassword', (username,))
            flash(f'Пароль пользователя {username} сброшен', 'success')
        elif action == 'deactivate':
            cursor.callproc('DeactivateUser', (username,))
            flash(f'Пользователь {username} отключен', 'warning')
        raw_conn.commit()
    except Exception as e:
        flash(f'Ошибка БД: {e}', 'danger')
    finally:
        if current_engine != engine: current_engine.dispose()
    return redirect(url_for('service.panel'))

@service_bp.route('/add_user', methods=['POST'])
def add_user():
    if not session.get('service_mode'): return abort(403)
    username = request.form.get('username', '').strip()
    full_name = request.form.get('full_name', '').strip()
    role_name = request.form.get('role_name')
    if not username or not full_name:
        flash("Все поля обязательны", "danger")
        return redirect(url_for('service.panel'))
    current_engine = get_service_engine()
    try:
        raw_conn = current_engine.raw_connection()
        cursor = raw_conn.cursor()
        cursor.callproc('AddUser', (username, full_name, role_name))
        result_msg = "Пользователь добавлен"
        for result in cursor.stored_results():
            row = result.fetchone()
            if row: result_msg = row[0]
        raw_conn.commit()
        flash(result_msg, "success")
    except Exception as e:
        flash(f"Ошибка: {e}", "danger")
    finally:
        if current_engine != engine: current_engine.dispose()
    return redirect(url_for('service.panel'))

# Экспорт данных
@service_bp.route('/export_data')
def export_data():
    if not session.get('service_mode'): 
        return abort(403)
        
    tables = ['Roles', 'Statuses', 'Names', 'Types', 'Places', 'Units', 'Parts', 'Users', 'Sensors', 'StatusLog']
    export_dict = {}
    current_engine = get_service_engine()
    
    raw_conn = None
    cursor = None
    
    try:
        raw_conn = current_engine.raw_connection()
        cursor = raw_conn.cursor(dictionary=True)
        cursor.execute("SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci")
        
        for table in tables:
            cursor.execute(f"SHOW TABLES LIKE '{table}'")
            if cursor.fetchone():
                cursor.execute(f"SELECT * FROM `{table}`")
                export_dict[table] = cursor.fetchall()
            else:
                export_dict[table] = []
        
        json_data = json.dumps(
            export_dict, 
            indent=4, 
            ensure_ascii=False, 
            default=json_serial
        )
        
        filename = f"kipsensors_v2.3_data_{date.today()}.json"
        
        return Response(
            json_data,
            mimetype="application/json",
            headers={"Content-disposition": f"attachment; filename={filename}"}
        )
        
    except Exception as e:
        flash(f"Ошибка формирования архива данных: {e}", "danger")
        return redirect(url_for('service.panel'))
    finally:
        if cursor: 
            cursor.close()
        if raw_conn: 
            raw_conn.close()
        if current_engine != engine: 
            current_engine.dispose()

# Экспорт схемы
@service_bp.route('/export_schema')
def export_schema():
    if not session.get('service_mode'): return abort(403)
    current_engine = get_service_engine()
    output = io.StringIO()
    try:
        raw_conn = current_engine.raw_connection()
        cursor = raw_conn.cursor(dictionary=True)
        cursor.execute("SET NAMES utf8mb4")
        output.write(f"-- KIPSensors Schema Export v2.3\n-- Date: {datetime.now()}\n\n")
        output.write("SET FOREIGN_KEY_CHECKS = 0;\n\n")
        
        cursor.execute("SHOW TABLES")
        tables = [list(t.values())[0] for t in cursor.fetchall()]
        for table in tables:
            cursor.execute(f"SHOW CREATE TABLE `{table}`")
            res = cursor.fetchone()
            output.write(f"-- Table: {table}\n{res['Create Table']};\n\n")

        cursor.execute("SHOW PROCEDURE STATUS WHERE Db = DATABASE()")
        procedures = [p['Name'] for p in cursor.fetchall()]
        for proc in procedures:
            cursor.execute(f"SHOW CREATE PROCEDURE `{proc}`")
            res = cursor.fetchone()
            f_body = res['Create Procedure']
            f_body_clean = re.sub(r'CREATE DEFINER=`.*?`@`.*?` PROCEDURE', 'CREATE PROCEDURE', f_body)
            output.write(f"DELIMITER //\nDROP PROCEDURE IF EXISTS `{proc}` //\n{f_body_clean} //\nDELIMITER ;\n\n")

        output.write("SET FOREIGN_KEY_CHECKS = 1;\n")
        return Response(output.getvalue(), mimetype="text/sql", 
                        headers={"Content-disposition": f"attachment; filename=kipsensors_schema_{date.today()}.sql"})
    except Exception as e:
        flash(f"Ошибка экспорта схемы: {e}", "danger")
        return redirect(url_for('service.panel'))
    finally:
        if current_engine != engine: current_engine.dispose()

# Сохранение связки login/password для доступа к БД
@service_bp.route('/save_config', methods=['POST'])
def save_config():
    if not session.get('service_mode') or not session.get('temp_db_user'): 
        return abort(403)
        
    config_data = {
        'DB_USER': session['temp_db_user'],
        'DB_PASSWORD': session['temp_db_password'],
        'DB_NAME': session.get('temp_db_name') or conf.DB_NAME,
        'DB_HOST': conf.DB_HOST
    }
    
    try:
        # basedir указывает на папку /app
        basedir = os.path.abspath(os.path.dirname(__file__))
        instance_path = os.path.join(basedir, 'instance')
        os.makedirs(instance_path, exist_ok=True)
        
        # 1. Сохраняем JSON-конфигурацию
        file_path = os.path.join(instance_path, 'db_params.json')
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(config_data, f, indent=4)
        
        # 2. УНИВЕРСАЛЬНЫЙ ПОИСК WSGI-ФАЙЛА (Ubuntu + РЕД ОС)
        # Сначала ищем внутри /app (Ubuntu style)
        wsgi_path = os.path.join(basedir, 'kipsensors.wsgi')
        
        # Если там нет, ищем уровнем выше (РЕД ОС style)
        if not os.path.exists(wsgi_path):
            wsgi_path = os.path.abspath(os.path.join(basedir, '..', 'kipsensors.wsgi'))
        
        # 3. ПОПЫТКА АВТО-РЕСТАРТА
        if os.path.exists(wsgi_path):
            try:
                # Пытаемся обновить время модификации (touch)
                os.utime(wsgi_path, None)
                flash("Конфигурация сохранена! Система автоматически перезагружена.", "success")
            except Exception as e:
                # Если прав недостаточно, уведомляем, но не роняем всё приложение
                flash(f"Конфигурация сохранена, но возникла ошибка прав при рестарте: {e}. Требуется ручной перезапуск Apache.", "warning")
        else:
            flash("Конфигурация сохранена, но файл kipsensors.wsgi не найден. Пожалуйста, перезапустите Apache вручную.", "warning")
            
    except Exception as e:
        # Ошибка записи самого JSON файла
        flash(f"Ошибка записи конфигурации: {e}", "danger")
        
    return redirect(url_for('service.panel'))

# Импорт схемы в файл
@service_bp.route('/import_schema', methods=['POST'])
def import_schema():
    if not session.get('service_mode'): return abort(403)
    file = request.files.get('schema_file')
    if not file or file.filename == '':
        flash("Файл схемы не выбран", "danger")
        return redirect(url_for('service.panel'))

    current_engine = get_service_engine()
    try:
        sql_script = file.read().decode('utf-8')
        raw_conn = current_engine.raw_connection()
        cursor = raw_conn.cursor()
        cursor.execute("SET NAMES utf8mb4")
        cursor.execute("SET FOREIGN_KEY_CHECKS = 0")

        sql_script = re.sub(r'--.*', '', sql_script)
        parts = re.split(r'(?i)DELIMITER\s+//|DELIMITER\s+;', sql_script)
        
        for part in parts:
            part = part.strip()
            if not part: continue
            if '//' in part:
                for sub in part.split('//'):
                    stmt = sub.strip()
                    if stmt: cursor.execute(stmt)
            else:
                for stmt in part.split(';'):
                    stmt = stmt.strip()
                    if stmt: cursor.execute(stmt)
        
        cursor.execute("SET FOREIGN_KEY_CHECKS = 1")
        raw_conn.commit()
        flash("Структура базы данных успешно развернута.", "success")
    except Exception as e:
        flash(f"Ошибка развертывания схемы: {e}", "danger")
    finally:
        if current_engine != engine: current_engine.dispose()
    return redirect(url_for('service.panel'))

# Импорт содержимого всех таблиц в файл
@service_bp.route('/import_data', methods=['POST'])
def import_data():
    if not session.get('service_mode'): return abort(403)
    file = request.files.get('backup_file')
    if not file or file.filename == '':
        flash("Файл не выбран", "danger")
        return redirect(url_for('service.panel'))

    tables_order = ['Roles', 'Statuses', 'Names', 'Types', 'Places', 'Units', 'Parts', 'Users', 'Sensors', 'StatusLog']
    current_engine = get_service_engine()
    try:
        data = json.load(file)
        raw_conn = current_engine.raw_connection()
        cursor = raw_conn.cursor()
        cursor.execute("SET FOREIGN_KEY_CHECKS = 0")
        
        for table in tables_order:
            cursor.execute(f"SHOW TABLES LIKE '{table}'")
            if not cursor.fetchone(): continue
            cursor.execute(f"TRUNCATE TABLE {table}")
            if table in data and data[table]:
                rows = data[table]
                columns = list(rows[0].keys())
                placeholders = ", ".join(["%s"] * len(columns))
                sql = f"INSERT INTO {table} ({', '.join(columns)}) VALUES ({placeholders})"
                values = [tuple(row.values()) for row in rows]
                cursor.executemany(sql, values)
        
        cursor.execute("SET FOREIGN_KEY_CHECKS = 1")
        raw_conn.commit()
        flash("Данные успешно синхронизированы.", "success")
    except Exception as e:
        flash(f"Ошибка импорта: {e}", "danger")
    finally:
        if current_engine != engine: current_engine.dispose()
    return redirect(url_for('service.panel'))

@service_bp.route('/logout')
def logout():
    session.pop('service_mode', None)
    session.pop('temp_db_user', None)
    session.pop('temp_db_password', None)
    flash('Сессия завершена', 'info')
    return redirect(url_for('login'))
