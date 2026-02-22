from flask import Flask, render_template, request, redirect, url_for, flash, session, Response
from flask_bootstrap import Bootstrap
from flask_login import LoginManager, login_user, login_required, logout_user, current_user
from sqlalchemy import create_engine, text
from werkzeug.security import check_password_hash, generate_password_hash
import json
import io
import re
import os
from datetime import datetime, date
from decimal import Decimal

# Импорт внутренних модулей проекта
from config import Config
from service_routes import service_bp
from database import engine, execute_proc, conf
from models import User, get_user_by_id, get_user_for_auth

app = Flask(__name__)
app.secret_key = 'flask_very_secret_key'
app.config.from_object(Config)
app.register_blueprint(service_bp, url_prefix='/service')
Bootstrap(app)

login_manager = LoginManager(app)
login_manager.login_view = 'login'


@login_manager.user_loader
def load_user(uid):
    if session.get('service_mode'):
        return None
        
    try:
        return get_user_by_id(uid)
    except:
        return None


# Авторизация пользователей БД
@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        user_data = get_user_for_auth(username)
        
        if user_data:
            if not user_data[6]:
                flash('Учетная запись деактивирована', 'danger')
                return redirect(url_for('login'))
                
            if check_password_hash(user_data[2], password):
                user_obj = User(user_data[0], user_data[1], user_data[3], user_data[4], user_data[5])
                login_user(user_obj)
                return redirect(url_for('index'))
        
        flash('Неверный логин или пароль', 'danger')
    return render_template('login.html')

@app.route('/logout')
def logout():
    logout_user()
    return redirect(url_for('login'))

# Смена пользовательского пароля
@app.route('/change_password', methods=['GET', 'POST'])
@login_required
def change_password():
    if request.method == 'POST':
        o = request.form.get('old_password')
        n = request.form.get('new_password')
        c = request.form.get('confirm_password')
        if n != c:
            flash('Новые пароли не совпадают', 'danger')
        elif o == n:
            flash('Новый пароль совпадает со старым', 'warning')
        else:
            with engine.connect() as conn:
                r = conn.execute(text("SELECT password_hash FROM Users WHERE user_id = :id"), {"id": current_user.id}).fetchone()
                if r and check_password_hash(r[0], o):
                    conn.execute(text("UPDATE Users SET password_hash = :h WHERE user_id = :id"), {"h": generate_password_hash(n), "id": current_user.id})
                    conn.commit()
                    flash('Пароль успешно изменен', 'success')
                    return redirect(url_for('index'))
                flash('Неверный старый пароль', 'danger')
    return render_template('change_password.html')


# Поиск (обработка GET для предотвращения 405 ошибки)
@app.route('/search', methods=['GET', 'POST'])
@login_required
def search():
    if request.method == 'GET':
        return redirect(url_for('index'))
        
    query = request.form.get('search_query', '').strip()
    search_type = request.form.get('search_type') 
    if not query:
        return redirect(url_for('index'))
    
    proc_name = 'SearchByKKS' if search_type == 'kks' else 'SearchByName'
    h, d = execute_proc(proc_name, (query,))
    return render_template('dashboard.html', headers=h, data=d, report_title=f"Результаты поиска ({query})", user=current_user)


# Проверка, существует ли уже такая позиция в базе
@app.route('/check_kks/<kks>')
@login_required
def check_kks(kks):
    with engine.connect() as conn:
        result = conn.execute(text("SELECT 1 FROM Sensors WHERE item_id = :k"), {"k": kks}).fetchone()
        return {"exists": True if result else False}


# Старт
@app.route('/')
@login_required
def index():
    return render_template('dashboard.html', headers=[], data=[], report_title="Выберите отчет", user=current_user)

# Выводит все позиции в сводную таблицу
@app.route('/full_report')
@login_required
def full_report():
    h, d = execute_proc('FullReport')
    return render_template('dashboard.html', headers=h, data=d, report_title="Полный отчет", user=current_user)

# Выводит неисправные
@app.route('/small_report')
@login_required
def small_report():
    h, d = execute_proc('SmallReport')
    return render_template('dashboard.html', headers=h, data=d, report_title="Список неисправностей", user=current_user)

# Добавляет новую модель
@app.route('/add_type', methods=['GET', 'POST'])
@login_required
def add_type():
    if current_user.role not in ['admpers', 'repair']:
        flash('Доступ запрещен', 'danger')
        return redirect(url_for('index'))

    if request.method == 'POST':
        manuf = request.form.get('manufacturer', '').strip()
        model_name = request.form.get('model', '').strip()
        conn = engine.raw_connection()
        try:
            cursor = conn.cursor()
            res_args = cursor.callproc('AddNewType', (manuf, model_name, 0))
            conn.commit()
            if res_args[2] > 0:
                flash(f'Модель {manuf} {model_name} добавлена', 'success')
                return redirect(url_for('index'))
            flash('Такая модель уже существует', 'warning')
        finally:
            cursor.close(); conn.close()
    return render_template('add_type.html')

# Добавляет новую позицию
@app.route('/add_sensor', methods=['GET', 'POST'])
@login_required
def add_sensor():
    if current_user.role != 'admpers':
        flash('Доступ запрещен', 'danger')
        return redirect(url_for('index'))

    if request.method == 'POST':
        f = request.form
        kks = f.get('kks', '').strip()
        # Собираем чистые параметры
        p = (
            kks, f.get('name_text', '').strip(), f.get('type_id'),
            f.get('row', '').strip(), f.get('axis', '').strip(), f.get('mark', '').strip(),
            f.get('unit_text', '').strip(), f.get('lower', 0), f.get('upper', 0),
            1 if f.get('is_protective') else 0, 0
        )
        conn = engine.raw_connection()
        try:
            cursor = conn.cursor()
            res_args = cursor.callproc('AddNewSensor', p)
            conn.commit()
            if res_args[10] > 0:
                flash(f"Датчик {kks} успешно добавлен", "success")
                return redirect(url_for('sensor_details', kks=kks))
            flash(f"Ошибка: KKS {kks} уже существует", "danger")
        except Exception as e:
            flash(f"Ошибка БД: {e}", "danger")
        finally:
            cursor.close(); conn.close()
           
           
    _, types = execute_proc('GetAllTypes')
    _, units = execute_proc('GetAllUnits')
    return render_template('add_sensor.html', types=types, units=units)

# Карточка датчика
@app.route('/sensor/<kks>')
@login_required
def sensor_details(kks):
    edit = request.args.get('edit') == '1'
    back = request.args.get('back_url') or (request.referrer if request.referrer and 'sensor' not in request.referrer else url_for('index'))
    _, d_det = execute_proc('GetSensorDetails', (kks,))
    _, h_his = execute_proc('GetSensorHistory', (kks,))
    _, all_t = execute_proc('GetAllTypes')
    _, all_s = execute_proc('GetAllStatuses')
    if not d_det: return redirect(url_for('index'))
    return render_template('sensor_card.html', sensor=d_det[0], history=h_his, all_types=all_t, all_statuses=all_s, edit_mode=edit, user=current_user, back_url=back)

# Изменение информации о датчике
@app.route('/update_sensor', methods=['POST'])
@login_required
def update_sensor():
    f = request.form
    kks = f.get('kks')
    back = f.get('back_url')
    sid = f.get('status_id')
    tid = f.get('type_id')
    stock = f.get('stock_count') or f.get('stock_count_hidden', 0)
    prot = 1 if f.get('is_protective') else f.get('is_protective_hidden', 0)
    
    execute_proc('UpdateSensorData', (kks, current_user.id, sid, tid, prot, stock))
    flash(f'Данные {kks} обновлены', 'success')
    return redirect(url_for('sensor_details', kks=kks, back_url=back))

# Удаление датчика
@app.route('/sensor/delete/<item_id>', methods=['POST'])
@login_required
def delete_sensor(item_id):
    if current_user.role != 'admpers':
        flash('Доступ запрещен: недостаточно прав для удаления', 'danger')
        return redirect(url_for('sensor_details', kks=item_id))

    conn = engine.raw_connection()
    try:
        cursor = conn.cursor()
        cursor.callproc('sp_delete_sensor', (item_id,))
        conn.commit()
        
        flash(f"Датчик {item_id} и связанные неиспользуемые данные удалены", "success")
        return redirect(url_for('index'))
    
    except Exception as e:
        conn.rollback()
        flash(f"Ошибка БД при удалении: {e}", "danger")
        return redirect(url_for('sensor_details', kks=item_id))
    
    finally:
        cursor.close()
        conn.close()


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
