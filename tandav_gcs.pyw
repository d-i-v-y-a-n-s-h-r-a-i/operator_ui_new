v import tkinter as tk
from tkinter import ttk
import math
import time
import socket
import threading
import struct

class TandavGCS:
    def __init__(self, root):
        self.root = root
        self.root.title("TANDAV CI4 — Autonomous Maritime Ground Control Station")
        self.root.geometry("1300x840")
        self.root.minsize(1050, 700)
        self.root.configure(bg="#050811")

        self.pitch = 0.0
        self.roll = 0.0
        self.heading = 0.0
        self.speed = 0.0
        self.depth = 0.0
        self.water_temp = 23.2
        self.bat_v = 24.8
        self.bat_a = 0.0
        self.bat_pct = 96
        self.bat_temp = 28.5
        self.left_thruster = 0.0
        self.right_thruster = 0.0
        self.rpm = 0
        self.coolant_temp = 0.0
        self.throttle = 0.0
        self.rudder = 0.0
        self.armed = False
        self.leak_detected = False
        self.mode = "TELEOP"
        self.lat = 12.971600
        self.lon = 77.594600
        self.last_packet_time = 0.0
        self.packet_count = 0
        self.threats = []

        self.waypoints = [
            {"lat": 12.9730, "lon": 77.5960},
            {"lat": 12.9750, "lon": 77.5990},
            {"lat": 12.9710, "lon": 77.6010}
        ]

        self.setup_ui()
        self.root.bind("<Key>", self.on_key)
        self.start_udp_receiver()
        self.update_loop()

    def start_udp_receiver(self):
        t = threading.Thread(target=self.udp_listener_thread, daemon=True)
        t.start()

    def udp_listener_thread(self):
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.bind(("0.0.0.0", 9001))
            while True:
                data, _ = sock.recvfrom(2048)
                self.packet_count += 1
                self.last_packet_time = time.time()
                if len(data) >= 77:
                    magic, seq, p, r, y, lat, lon, spd, hdg, bv, ba, bp, bt, tl, tr, dep, wt, lk, arm, md, lq = struct.unpack('<IIfffddffffBfffffBBBB', data[:77])
                    if magic == 0x544E4456:
                        self.pitch = p
                        self.roll = r
                        self.heading = hdg
                        self.speed = spd
                        self.lat = lat
                        self.lon = lon
                        self.bat_v = bv
                        self.bat_a = ba
                        self.bat_pct = bp
                        self.bat_temp = bt
                        self.left_thruster = tl
                        self.right_thruster = tr
                        self.depth = dep
                        self.water_temp = wt
                        self.leak_detected = (lk != 0)
                        self.armed = (arm != 0)
                elif len(data) == 17:
                    can_id, dlc, payload, ts = struct.unpack('<IB8sI', data)
                    if can_id == 0x200:
                        self.rpm = (payload[0] << 8) | payload[1]
                        self.coolant_temp = payload[2] - 40
                    elif can_id == 0x300:
                        raw_v = (payload[4] << 8) | payload[5]
                        self.bat_v = raw_v * 0.01
                    elif can_id == 0x18FF:
                        self.leak_detected = (payload[0] & 0x01) != 0
                elif data.startswith(b'{'):
                    try:
                        obj = json.loads(data.decode('utf-8'))
                        if obj.get("type") == "THREATS":
                            self.threats = obj.get("threats", [])
                    except Exception:
                        pass
        except Exception:
            pass

    def setup_ui(self):
        header = tk.Frame(self.root, bg="#0a101d", height=42, highlightbackground="#1e293b", highlightthickness=1)
        header.pack(side=tk.TOP, fill=tk.X)

        h_left = tk.Frame(header, bg="#0a101d")
        h_left.pack(side=tk.LEFT, padx=12, pady=6)

        self.conn_dot = tk.Label(h_left, text="●", fg="#64748b", bg="#0a101d", font=("Consolas", 14))
        self.conn_dot.pack(side=tk.LEFT, padx=(0, 6))

        tk.Label(h_left, text="TANDAV CI4 GCS", fg="#ffffff", bg="#0a101d", font=("Consolas", 12, "bold")).pack(side=tk.LEFT)
        tk.Label(h_left, text="v1.0.0-HIL", fg="#64748b", bg="#0a101d", font=("Consolas", 9)).pack(side=tk.LEFT, padx=(4, 16))

        tk.Label(h_left, text="MODE:", fg="#94a3b8", bg="#0a101d", font=("Consolas", 10)).pack(side=tk.LEFT)
        self.mode_var = tk.StringVar(value="TELEOP")
        mode_menu = ttk.Combobox(h_left, textvariable=self.mode_var, values=["STANDBY", "MANUAL", "TELEOP", "AUTO", "LOITER", "RTL"], width=9, state="readonly")
        mode_menu.pack(side=tk.LEFT, padx=6)

        self.arm_btn = tk.Button(h_left, text="ARM VESSEL", bg="#10b981", fg="#ffffff", font=("Consolas", 9, "bold"), relief=tk.FLAT, padx=10, pady=2, command=self.toggle_arm)
        self.arm_btn.pack(side=tk.LEFT, padx=10)

        h_right = tk.Frame(header, bg="#0a101d")
        h_right.pack(side=tk.RIGHT, padx=12, pady=6)

        self.link_lbl = tk.Label(h_right, text="LINK: STANDBY", fg="#64748b", bg="#0a101d", font=("Consolas", 10, "bold"))
        self.link_lbl.pack(side=tk.LEFT, padx=8)

        self.rtt_lbl = tk.Label(h_right, text="UDP: 9001", fg="#00f0ff", bg="#0a101d", font=("Consolas", 10, "bold"))
        self.rtt_lbl.pack(side=tk.LEFT, padx=8)

        self.leak_badge = tk.Label(h_right, text="LEAK DETECTED", fg="#ffffff", bg="#ef4444", font=("Consolas", 9, "bold"), padx=6, pady=2)

        estop_btn = tk.Button(h_right, text="EMERGENCY STOP", bg="#b91c1c", fg="#ffffff", font=("Consolas", 9, "bold"), relief=tk.FLAT, padx=12, pady=2, command=self.emergency_stop)
        estop_btn.pack(side=tk.LEFT, padx=8)

        compass_frame = tk.Frame(self.root, bg="#0a101d", height=42, highlightbackground="#1e293b", highlightthickness=1)
        compass_frame.pack(side=tk.TOP, fill=tk.X, pady=(2, 6))

        self.compass_canvas = tk.Canvas(compass_frame, bg="#0a101d", height=40, highlightthickness=0)
        self.compass_canvas.pack(fill=tk.BOTH, expand=True)

        main_grid = tk.Frame(self.root, bg="#050811")
        main_grid.pack(side=tk.TOP, fill=tk.BOTH, expand=True, padx=8, pady=(0, 8))

        left_col = tk.Frame(main_grid, bg="#050811")
        left_col.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 4))

        fpv_box = tk.Frame(left_col, bg="#0a101d", highlightbackground="#1e293b", highlightthickness=1)
        fpv_box.pack(side=tk.TOP, fill=tk.BOTH, expand=True, pady=(0, 4))

        self.fpv_canvas = tk.Canvas(fpv_box, bg="#050811", highlightthickness=0)
        self.fpv_canvas.pack(fill=tk.BOTH, expand=True)

        self.fpv_stat_lbl = tk.Label(fpv_box, text="SPD: 0.0 kts  |  HDG: 000°  |  DEPTH: 0.0 m  |  BAT: 96% (24.8V)", bg="#070b14", fg="#00f0ff", font=("Consolas", 10, "bold"), pady=3)
        self.fpv_stat_lbl.pack(side=tk.BOTTOM, fill=tk.X)

        map_box = tk.Frame(left_col, bg="#0a101d", highlightbackground="#1e293b", highlightthickness=1)
        map_box.pack(side=tk.BOTTOM, fill=tk.BOTH, expand=True, pady=(4, 0))

        self.map_canvas = tk.Canvas(map_box, bg="#070b14", highlightthickness=0)
        self.map_canvas.pack(fill=tk.BOTH, expand=True)
        self.map_canvas.bind("<Button-3>", self.on_map_right_click)

        map_bar = tk.Frame(map_box, bg="#0a101d")
        map_bar.pack(side=tk.BOTTOM, fill=tk.X, padx=6, pady=3)
        self.map_stat_lbl = tk.Label(map_bar, text="LAT: 12.971600° N  |  LON: 77.594600° E  |  WP: 3", bg="#0a101d", fg="#00f0ff", font=("Consolas", 9, "bold"))
        self.map_stat_lbl.pack(side=tk.LEFT)
        tk.Button(map_bar, text="+ WP", bg="#1e293b", fg="#00f0ff", font=("Consolas", 8, "bold"), relief=tk.FLAT, command=self.add_waypoint).pack(side=tk.RIGHT, padx=2)
        tk.Button(map_bar, text="CLEAR", bg="#1e293b", fg="#94a3b8", font=("Consolas", 8), relief=tk.FLAT, command=self.clear_waypoints).pack(side=tk.RIGHT, padx=2)

        right_col = tk.Frame(main_grid, bg="#050811", width=420)
        right_col.pack(side=tk.RIGHT, fill=tk.BOTH, padx=(4, 0))

        hud_row = tk.Frame(right_col, bg="#050811")
        hud_row.pack(side=tk.TOP, fill=tk.X, pady=(0, 6))

        horizon_box = tk.Frame(hud_row, bg="#0a101d", highlightbackground="#1e293b", highlightthickness=1)
        horizon_box.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 3))
        tk.Label(horizon_box, text="ATTITUDE HORIZON", fg="#64748b", bg="#0a101d", font=("Consolas", 9, "bold")).pack(pady=4)
        self.horizon_canvas = tk.Canvas(horizon_box, bg="#0a101d", width=180, height=160, highlightthickness=0)
        self.horizon_canvas.pack(pady=2)
        self.pitch_roll_lbl = tk.Label(horizon_box, text="P: 0.0°  R: 0.0°", fg="#00f0ff", bg="#0a101d", font=("Consolas", 9, "bold"))
        self.pitch_roll_lbl.pack(pady=4)

        prop_box = tk.Frame(hud_row, bg="#0a101d", highlightbackground="#1e293b", highlightthickness=1)
        prop_box.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True, padx=(3, 0))
        tk.Label(prop_box, text="PROPULSION", fg="#64748b", bg="#0a101d", font=("Consolas", 9, "bold")).pack(pady=4)
        self.prop_canvas = tk.Canvas(prop_box, bg="#0a101d", width=150, height=160, highlightthickness=0)
        self.prop_canvas.pack(pady=2)
        self.thrust_lbl = tk.Label(prop_box, text="PORT: 0%  STBD: 0%", fg="#10b981", bg="#0a101d", font=("Consolas", 9, "bold"))
        self.thrust_lbl.pack(pady=4)

        tel_box = tk.Frame(right_col, bg="#0a101d", highlightbackground="#1e293b", highlightthickness=1, padx=8, pady=6)
        tel_box.pack(side=tk.TOP, fill=tk.X, pady=(0, 6))
        tk.Label(tel_box, text="SYSTEM SENSORS (UW-SUITE)", fg="#64748b", bg="#0a101d", font=("Consolas", 9, "bold"), anchor="w").pack(fill=tk.X, pady=(0, 4))
        
        tg = tk.Frame(tel_box, bg="#0a101d")
        tg.pack(fill=tk.X)
        self.tel_bat_lbl = tk.Label(tg, text="BAT: 24.8V (0.0A)", fg="#00f0ff", bg="#0a101d", font=("Consolas", 9, "bold"))
        self.tel_bat_lbl.grid(row=0, column=0, sticky="w", pady=2)
        self.tel_temp_lbl = tk.Label(tg, text="BAT TEMP: 28.5 °C", fg="#10b981", bg="#0a101d", font=("Consolas", 9, "bold"))
        self.tel_temp_lbl.grid(row=0, column=1, sticky="w", padx=12, pady=2)
        self.tel_depth_lbl = tk.Label(tg, text="DEPTH: 0.00 m", fg="#00f0ff", bg="#0a101d", font=("Consolas", 9, "bold"))
        self.tel_depth_lbl.grid(row=1, column=0, sticky="w", pady=2)
        self.tel_wtemp_lbl = tk.Label(tg, text="WATER: 23.2 °C", fg="#10b981", bg="#0a101d", font=("Consolas", 9, "bold"))
        self.tel_wtemp_lbl.grid(row=1, column=1, sticky="w", padx=12, pady=2)
        self.tel_leak_lbl = tk.Label(tg, text="BILGE: NOMINAL", fg="#10b981", bg="#0a101d", font=("Consolas", 9, "bold"))
        self.tel_leak_lbl.grid(row=2, column=0, sticky="w", pady=2)
        self.tel_rpm_lbl = tk.Label(tg, text="RPM: 0 | CLNT: 0°C", fg="#f59e0b", bg="#0a101d", font=("Consolas", 9, "bold"))
        self.tel_rpm_lbl.grid(row=2, column=1, sticky="w", padx=12, pady=2)

        ctrl_box = tk.Frame(right_col, bg="#0a101d", highlightbackground="#1e293b", highlightthickness=1, padx=8, pady=8)
        ctrl_box.pack(side=tk.TOP, fill=tk.BOTH, expand=True)
        tk.Label(ctrl_box, text="TELEOPERATION MIXER (KEYBOARD W/S A/D)", fg="#64748b", bg="#0a101d", font=("Consolas", 9, "bold"), anchor="w").pack(fill=tk.X)

        tk.Label(ctrl_box, text="THROTTLE", fg="#94a3b8", bg="#0a101d", font=("Consolas", 9)).pack(anchor="w", pady=(6, 0))
        self.throttle_scale = tk.Scale(ctrl_box, from_=-100, to=100, orient=tk.HORIZONTAL, bg="#0a101d", fg="#00f0ff", highlightthickness=0, troughcolor="#0f172a", activebackground="#00f0ff", command=self.on_throttle_slide)
        self.throttle_scale.pack(fill=tk.X)

        tk.Label(ctrl_box, text="RUDDER", fg="#94a3b8", bg="#0a101d", font=("Consolas", 9)).pack(anchor="w", pady=(4, 0))
        self.rudder_scale = tk.Scale(ctrl_box, from_=-100, to=100, orient=tk.HORIZONTAL, bg="#0a101d", fg="#00f0ff", highlightthickness=0, troughcolor="#0f172a", activebackground="#00f0ff", command=self.on_rudder_slide)
        self.rudder_scale.pack(fill=tk.X)

        btn_row = tk.Frame(ctrl_box, bg="#0a101d")
        btn_row.pack(fill=tk.X, pady=8)
        tk.Button(btn_row, text="ZERO THRUST", bg="#1e293b", fg="#ffffff", font=("Consolas", 9, "bold"), relief=tk.FLAT, command=self.zero_thrust).pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 4))
        tk.Button(btn_row, text="TEST LEAK ALARM", bg="#1e293b", fg="#f59e0b", font=("Consolas", 9, "bold"), relief=tk.FLAT, command=self.toggle_leak).pack(side=tk.RIGHT, fill=tk.X, expand=True, padx=(4, 0))

    def toggle_arm(self):
        self.armed = not self.armed
        if self.armed:
            self.arm_btn.config(text="DISARM VESSEL", bg="#ef4444")
        else:
            self.arm_btn.config(text="ARM VESSEL", bg="#10b981")
        self.calc_mixing()

    def emergency_stop(self):
        self.armed = False
        self.throttle = 0.0
        self.rudder = 0.0
        self.throttle_scale.set(0)
        self.rudder_scale.set(0)
        self.arm_btn.config(text="ARM VESSEL", bg="#10b981")
        self.mode_var.set("STANDBY")
        self.calc_mixing()

    def toggle_leak(self):
        self.leak_detected = not self.leak_detected
        if self.leak_detected:
            self.leak_badge.pack(side=tk.LEFT, padx=6)
            self.tel_leak_lbl.config(text="BILGE: LEAK DETECTED!", fg="#ef4444")
        else:
            self.leak_badge.pack_forget()
            self.tel_leak_lbl.config(text="BILGE: NOMINAL", fg="#10b981")

    def on_throttle_slide(self, val):
        self.throttle = float(val) / 100.0
        self.calc_mixing()

    def on_rudder_slide(self, val):
        self.rudder = float(val) / 100.0
        self.calc_mixing()

    def zero_thrust(self):
        self.throttle_scale.set(0)
        self.rudder_scale.set(0)
        self.throttle = 0.0
        self.rudder = 0.0
        self.calc_mixing()

    def calc_mixing(self):
        l = max(-1.0, min(1.0, self.throttle + self.rudder))
        r = max(-1.0, min(1.0, self.throttle - self.rudder))
        self.left_thruster = l if self.armed else 0.0
        self.right_thruster = r if self.armed else 0.0
        self.thrust_lbl.config(text=f"PORT: {int(self.left_thruster*100)}%  STBD: {int(self.right_thruster*100)}%")

    def on_key(self, event):
        k = event.keysym.lower()
        if k == 'w':
            self.throttle_scale.set(min(100, self.throttle_scale.get() + 10))
        elif k == 's':
            self.throttle_scale.set(max(-100, self.throttle_scale.get() - 10))
        elif k == 'a':
            self.rudder_scale.set(max(-100, self.rudder_scale.get() - 10))
        elif k == 'd':
            self.rudder_scale.set(min(100, self.rudder_scale.get() + 10))
        elif k == 'space':
            self.zero_thrust()

    def on_map_right_click(self, event):
        w = self.map_canvas.winfo_width()
        h = self.map_canvas.winfo_height()
        cx = w / 2
        cy = h / 2
        d_lon = (event.x - cx) / 10000.0
        d_lat = -(event.y - cy) / 10000.0
        self.waypoints.append({"lat": self.lat + d_lat, "lon": self.lon + d_lon})
        self.map_stat_lbl.config(text=f"LAT: {self.lat:.6f}° N  |  LON: {self.lon:.6f}° E  |  WP: {len(self.waypoints)}")

    def add_waypoint(self):
        last = self.waypoints[-1] if self.waypoints else {"lat": self.lat, "lon": self.lon}
        self.waypoints.append({"lat": last["lat"] + 0.002, "lon": last["lon"] + 0.002})
        self.map_stat_lbl.config(text=f"LAT: {self.lat:.6f}° N  |  LON: {self.lon:.6f}° E  |  WP: {len(self.waypoints)}")

    def clear_waypoints(self):
        self.waypoints.clear()
        self.map_stat_lbl.config(text=f"LAT: {self.lat:.6f}° N  |  LON: {self.lon:.6f}° E  |  WP: 0")

    def draw_compass(self):
        c = self.compass_canvas
        c.delete("all")
        w = c.winfo_width()
        h = c.winfo_height()
        if w <= 1: return
        cx = w / 2

        center = (self.heading % 360 + 360) % 360
        ppd = 5.0
        start = int(center - (w / 2 / ppd))
        end = int(center + (w / 2 / ppd))

        for deg in range(start, end + 1):
            norm = (deg % 360 + 360) % 360
            x = cx + (deg - center) * ppd
            if norm % 5 == 0:
                major = (norm % 30 == 0)
                y2 = 18 if major else 8
                color = "#00f0ff" if major else "#64748b"
                c.create_line(x, 2, x, y2, fill=color, width=1.5 if major else 1)
                if major:
                    lbl = str(norm)
                    if norm == 0: lbl = "N"
                    elif norm == 90: lbl = "E"
                    elif norm == 180: lbl = "S"
                    elif norm == 270: lbl = "W"
                    tcol = "#00f0ff" if lbl in ["N", "E", "S", "W"] else "#94a3b8"
                    c.create_text(x, 28, text=lbl, fill=tcol, font=("Consolas", 8, "bold"))

        c.create_line(cx, 0, cx, h, fill="#f59e0b", width=2)
        c.create_text(cx, 32, text=f"{int(center):03d}°", fill="#00f0ff", font=("Consolas", 9, "bold"))

    def draw_horizon(self):
        c = self.horizon_canvas
        c.delete("all")
        w = 180
        h = 160
        cx = w / 2
        cy = h / 2

        p_off = self.pitch * 2.0
        rad = math.radians(self.roll)
        cos_r = math.cos(rad)
        sin_r = math.sin(rad)

        c.create_rectangle(0, 0, w, cy + p_off, fill="#103965", outline="")
        c.create_rectangle(0, cy + p_off, w, h, fill="#2c1e0e", outline="")

        x1 = cx - 70 * cos_r
        y1 = (cy + p_off) - 70 * sin_r
        x2 = cx + 70 * cos_r
        y2 = (cy + p_off) + 70 * sin_r
        c.create_line(x1, y1, x2, y2, fill="#00f0ff", width=2)

        for p_line in [-20, -10, 10, 20]:
            y_base = cy + p_off - (p_line * 2.0)
            c.create_line(cx - 20, y_base, cx + 20, y_base, fill="#94a3b8", width=1)
            c.create_text(cx + 28, y_base, text=str(abs(p_line)), fill="#94a3b8", font=("Consolas", 7))

        c.create_line(cx - 30, cy, cx - 8, cy, fill="#f59e0b", width=2)
        c.create_line(cx + 8, cy, cx + 30, cy, fill="#f59e0b", width=2)
        c.create_oval(cx - 3, cy - 3, cx + 3, cy + 3, fill="#f59e0b", outline="")

    def draw_propulsion(self):
        c = self.prop_canvas
        c.delete("all")
        w = 150
        h = 160
        mid = h / 2

        c.create_rectangle(25, 10, 55, h - 10, fill="#0f172a", outline="#334155")
        c.create_line(25, mid, 55, mid, fill="#64748b", width=1)
        p_len = self.left_thruster * (mid - 15)
        p_col = "#10b981" if self.left_thruster >= 0 else "#ef4444"
        if self.left_thruster >= 0:
            c.create_rectangle(27, mid - p_len, 53, mid, fill=p_col, outline="")
        else:
            c.create_rectangle(27, mid, 53, mid - p_len, fill=p_col, outline="")

        c.create_rectangle(95, 10, 125, h - 10, fill="#0f172a", outline="#334155")
        c.create_line(95, mid, 125, mid, fill="#64748b", width=1)
        s_len = self.right_thruster * (mid - 15)
        s_col = "#10b981" if self.right_thruster >= 0 else "#ef4444"
        if self.right_thruster >= 0:
            c.create_rectangle(97, mid - s_len, 123, mid, fill=s_col, outline="")
        else:
            c.create_rectangle(97, mid, 123, mid - s_len, fill=s_col, outline="")

        c.create_text(40, h - 4, text="PORT", fill="#94a3b8", font=("Consolas", 7, "bold"))
        c.create_text(110, h - 4, text="STBD", fill="#94a3b8", font=("Consolas", 7, "bold"))

    def draw_fpv(self):
        c = self.fpv_canvas
        c.delete("all")
        w = c.winfo_width()
        h = c.winfo_height()
        if w <= 1 or h <= 1: return
        cx = w / 2
        cy = h / 2

        c.create_rectangle(0, 0, w, cy, fill="#060d19", outline="")
        c.create_rectangle(0, cy, w, h, fill="#02060e", outline="")

        t = time.time() * 2
        for i in range(4):
            y = cy + (i * 20)
            c.create_line(0, y + math.sin(t + i)*3, w, y + math.cos(t + i)*3, fill="#0e2338", width=1)

        c.create_line(cx - 30, cy, cx + 30, cy, fill="#00f0ff", width=1.5)
        c.create_line(cx, cy - 30, cx, cy + 30, fill="#00f0ff", width=1.5)
        c.create_oval(cx - 8, cy - 8, cx + 8, cy + 8, outline="#00f0ff", width=1.5)
        c.create_text(24, 16, text="LIVE FPV (30 FPS | H.265)", fill="#ef4444", anchor="w", font=("Consolas", 8, "bold"))

        for th in self.threats:
            tx = th.get("x", 0.5) * w
            ty = th.get("y", 0.5) * h
            tw = th.get("w", 0.1) * w
            th_h = th.get("h", 0.05) * h
            col = "#ef4444" if th.get("colregs") == "GIVE_WAY" else "#f59e0b"
            c.create_rectangle(tx, ty, tx + tw, ty + th_h, outline=col, width=2)
            lbl = f"{th.get('class','TARGET')} {int(th.get('range_m',0))}m [{th.get('colregs','STAND_ON')}]"
            c.create_text(tx, ty - 8, text=lbl, fill=col, anchor="w", font=("Consolas", 8, "bold"))

    def draw_map(self):
        c = self.map_canvas
        c.delete("all")
        w = c.winfo_width()
        h = c.winfo_height()
        if w <= 1 or h <= 1: return
        cx = w / 2
        cy = h / 2

        for r in [35, 75, 115, 155]:
            c.create_oval(cx - r, cy - r, cx + r, cy + r, outline="#1e293b", width=1)

        c.create_line(0, cy, w, cy, fill="#1e293b", width=1)
        c.create_line(cx, 0, cx, h, fill="#1e293b", width=1)

        prev_x, prev_y = cx, cy
        for idx, wp in enumerate(self.waypoints):
            wx = cx + (wp["lon"] - self.lon) * 10000.0
            wy = cy - (wp["lat"] - self.lat) * 10000.0
            c.create_line(prev_x, prev_y, wx, wy, fill="#f59e0b", dash=(3, 3), width=1.5)
            c.create_oval(wx - 4, wy - 4, wx + 4, wy + 4, fill="#f59e0b", outline="")
            c.create_text(wx + 10, wy, text=f"WP{idx+1}", fill="#ffffff", font=("Consolas", 8))
            prev_x, prev_y = wx, wy

        c.create_polygon([cx, cy - 12, cx + 8, cy + 8, cx, cy + 4, cx - 8, cy + 8], fill="#00f0ff", outline="#ffffff", width=1.5)

        for th in self.threats:
            rng = th.get("range_m", 50.0)
            brg = th.get("bearing", 0.0)
            ang = math.radians(self.heading + brg)
            ox = cx + math.sin(ang) * (rng * 0.4)
            oy = cy - math.cos(ang) * (rng * 0.4)
            col = "#ef4444" if th.get("colregs") == "GIVE_WAY" else "#f59e0b"
            c.create_oval(ox - 5, oy - 5, ox + 5, oy + 5, fill=col, outline="#ffffff")
            c.create_text(ox + 8, oy, text=f"{th.get('class','TGT')} ({int(rng)}m)", fill=col, font=("Consolas", 7))

    def update_loop(self):
        now = time.time()
        is_live = (now - self.last_packet_time) < 1.0

        if is_live:
            self.conn_dot.config(fg="#10b981")
            self.link_lbl.config(text=f"LINK: 50Hz LIVE ({self.packet_count})", fg="#10b981")
        else:
            self.conn_dot.config(fg="#ef4444")
            self.link_lbl.config(text="LINK: DISCONNECTED (FROZEN)", fg="#ef4444")

        self.pitch_roll_lbl.config(text=f"P: {self.pitch:.1f}°  R: {self.roll:.1f}°")
        self.fpv_stat_lbl.config(text=f"SPD: {self.speed:.1f} kts  |  HDG: {int(self.heading):03d}°  |  DEPTH: {self.depth:.1f} m  |  BAT: {self.bat_pct}% ({self.bat_v:.1f}V)")
        self.map_stat_lbl.config(text=f"LAT: {self.lat:.6f}° N  |  LON: {self.lon:.6f}° E  |  WP: {len(self.waypoints)}")
        self.tel_bat_lbl.config(text=f"BAT: {self.bat_v:.1f}V ({self.bat_a:.1f}A)")
        if self.rpm > 0:
            self.tel_rpm_lbl.config(text=f"RPM: {self.rpm} | CLNT: {self.coolant_temp:.1f}°C")

        if self.leak_detected:
            self.leak_badge.pack(side=tk.LEFT, padx=6)
            self.tel_leak_lbl.config(text="BILGE: LEAK DETECTED!", fg="#ef4444")
        else:
            self.leak_badge.pack_forget()
            self.tel_leak_lbl.config(text="BILGE: NOMINAL", fg="#10b981")

        self.draw_compass()
        self.draw_horizon()
        self.draw_propulsion()
        self.draw_fpv()
        self.draw_map()

        self.root.after(20, self.update_loop)

if __name__ == "__main__":
    root = tk.Tk()
    app = TandavGCS(root)
    root.mainloop()
