import socket
import struct
import time
import json
import threading
import sys
import os
import math

from pid_controller import PIDController, MarineActuatorMixer
from velocity_obstacle_planner import VelocityObstaclePlanner
from perception_pipeline import MaritimePerceptionPipeline

GCS_IP = os.environ.get("GCS_IP", "127.0.0.1")
GCS_TELEMETRY_PORT = int(os.environ.get("GCS_PORT", 9001))
VESSEL_LISTEN_PORT = 9000
CAN_INTERFACE = os.environ.get("CAN_IFACE", "can0")

MAGIC = 0x544E4456

vessel_state = {
    "pitch": 0.0,
    "roll": 0.0,
    "yaw": 0.0,
    "lat": 12.971600,
    "lon": 77.594600,
    "speed": 0.0,
    "heading": 0.0,
    "bat_v": 24.8,
    "bat_a": 0.0,
    "bat_pct": 95,
    "bat_temp": 28.5,
    "th_l": 0.0,
    "th_r": 0.0,
    "depth": 0.0,
    "w_temp": 24.0,
    "leak": 0,
    "armed": 0,
    "mode": 1,
    "link_q": 99,
    "rpm": 0,
    "coolant_temp": 25.0,
    "target_heading": 0.0,
    "target_speed": 0.0
}

lock = threading.Lock()
last_control_time = time.time()
running = True

heading_pid = PIDController(kp=1.8, ki=0.05, kd=0.4, out_min=-1.0, out_max=1.0)
speed_pid = PIDController(kp=1.2, ki=0.08, kd=0.15, out_min=0.0, out_max=1.0)
mixer = MarineActuatorMixer(deadzone=0.08)
planner = VelocityObstaclePlanner()
perception = MaritimePerceptionPipeline()

def can_receiver_loop():
    global vessel_state, running
    try:
        can_sock = socket.socket(socket.AF_CAN, socket.SOCK_RAW, socket.CAN_RAW)
        can_sock.bind((CAN_INTERFACE,))
    except Exception:
        return

    while running:
        try:
            cf, _ = can_sock.recvfrom(16)
            can_id, can_dlc, data = struct.unpack("=IB3x8s", cf)
            can_id &= 0x1FFFFFFF

            with lock:
                if can_id == 0x200:
                    rpm = (data[0] << 8) | data[1]
                    coolant = data[2] - 40
                    vessel_state["rpm"] = rpm
                    vessel_state["coolant_temp"] = coolant
                elif can_id == 0x208:
                    throttle_pct = data[3] * 0.4
                    vessel_state["speed"] = (throttle_pct / 100.0) * 32.0
                elif can_id == 0x300:
                    raw_v = (data[4] << 8) | data[5]
                    vessel_state["bat_v"] = raw_v * 0.01
                elif can_id == 0x18FF:
                    vessel_state["leak"] = 1 if (data[0] & 0x01) else 0
        except Exception:
            time.sleep(0.01)

def command_receiver_loop():
    global vessel_state, last_control_time, running, heading_pid, speed_pid
    cmd_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    cmd_sock.bind(("0.0.0.0", VESSEL_LISTEN_PORT))
    cmd_sock.settimeout(0.5)

    while running:
        try:
            data, _ = cmd_sock.recvfrom(4096)
            packet = json.loads(data.decode("utf-8"))
            last_control_time = time.time()
            pkt_type = packet.get("type")

            if pkt_type == "CONTROL":
                th_l = float(packet.get("th_l", 0.0))
                th_r = float(packet.get("th_r", 0.0))
                armed = 1 if packet.get("armed", False) else 0
                mode_str = packet.get("mode", "TELEOP")

                with lock:
                    vessel_state["armed"] = armed
                    if mode_str != "AUTO":
                        if armed:
                            vessel_state["th_l"] = th_l
                            vessel_state["th_r"] = th_r
                        else:
                            vessel_state["th_l"] = 0.0
                            vessel_state["th_r"] = 0.0

                    if mode_str == "TELEOP": vessel_state["mode"] = 2
                    elif mode_str == "AUTO": vessel_state["mode"] = 3
                    elif mode_str == "ESTOP": vessel_state["mode"] = 4
                    else: vessel_state["mode"] = 1

            elif pkt_type == "MISSION_UPLOAD":
                wps = packet.get("waypoints", [])
                with lock:
                    planner.set_waypoints(wps)

            elif pkt_type == "PID_CONFIG":
                with lock:
                    heading_pid.kp = float(packet.get("kp_hdg", heading_pid.kp))
                    heading_pid.ki = float(packet.get("ki_hdg", heading_pid.ki))
                    heading_pid.kd = float(packet.get("kd_hdg", heading_pid.kd))
                    speed_pid.kp = float(packet.get("kp_spd", speed_pid.kp))
                    speed_pid.ki = float(packet.get("ki_spd", speed_pid.ki))
                    speed_pid.kd = float(packet.get("kd_spd", speed_pid.kd))

            elif pkt_type == "SET_TARGET_SPEED":
                with lock:
                    vessel_state["target_speed"] = float(packet.get("speed", 0.0))

            elif pkt_type == "SET_TARGET_HEADING":
                with lock:
                    vessel_state["target_heading"] = float(packet.get("heading", 0.0))

            elif pkt_type == "ESTOP":
                with lock:
                    vessel_state["th_l"] = 0.0
                    vessel_state["th_r"] = 0.0
                    vessel_state["armed"] = 0
                    vessel_state["mode"] = 4

        except socket.timeout:
            if time.time() - last_control_time > 0.5:
                with lock:
                    if vessel_state["mode"] != 3 and vessel_state["armed"]:
                        vessel_state["th_l"] = 0.0
                        vessel_state["th_r"] = 0.0
        except Exception:
            pass

def autonomy_control_loop():
    global vessel_state, running
    rate_hz = 50.0
    dt = 1.0 / rate_hz

    while running:
        time.sleep(dt)
        with lock:
            mode = vessel_state["mode"]
            armed = vessel_state["armed"]
            curr_lat = vessel_state["lat"]
            curr_lon = vessel_state["lon"]
            curr_hdg = vessel_state["heading"]
            curr_spd = vessel_state["speed"]

        if mode == 3 and armed:
            threats = perception.threats
            target_hdg, target_spd, wp_idx = planner.plan_step(curr_lat, curr_lon, curr_hdg, curr_spd, threats)

            hdg_err = (target_hdg - curr_hdg + 540.0) % 360.0 - 180.0
            rudder_cmd = heading_pid.update(hdg_err, dt)

            spd_err = target_spd - curr_spd
            throttle_cmd = speed_pid.update(spd_err, dt)

            th_l, th_r = mixer.mix_differential(throttle_cmd, rudder_cmd)

            with lock:
                vessel_state["target_heading"] = target_hdg
                vessel_state["target_speed"] = target_spd
                vessel_state["th_l"] = th_l
                vessel_state["th_r"] = th_r

def perception_broadcast_loop():
    global vessel_state, running
    tx_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    while running:
        time.sleep(0.1)
        with lock:
            c_lat = vessel_state["lat"]
            c_lon = vessel_state["lon"]
            c_hdg = vessel_state["heading"]
            c_pitch = vessel_state["pitch"]
            c_roll = vessel_state["roll"]

        threats = perception.update_mock_tracks(c_lat, c_lon, c_hdg, c_pitch, c_roll)
        pkt = {
            "type": "THREATS",
            "timestamp": int(time.time() * 1000),
            "threats": threats
        }
        try:
            tx_sock.sendto(json.dumps(pkt).encode("utf-8"), (GCS_IP, GCS_TELEMETRY_PORT))
        except Exception:
            pass

def telemetry_transmitter_loop():
    global vessel_state, running
    tx_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    seq = 0

    while running:
        seq += 1
        with lock:
            bin_pkt = struct.pack(
                '<IIfffddffffBfffffBBBB',
                MAGIC, seq,
                float(vessel_state["pitch"]), float(vessel_state["roll"]), float(vessel_state["yaw"]),
                float(vessel_state["lat"]), float(vessel_state["lon"]),
                float(vessel_state["speed"]), float(vessel_state["heading"]),
                float(vessel_state["bat_v"]), float(vessel_state["bat_a"]),
                int(vessel_state["bat_pct"]), float(vessel_state["bat_temp"]),
                float(vessel_state["th_l"]), float(vessel_state["th_r"]),
                float(vessel_state["depth"]), float(vessel_state["w_temp"]),
                int(vessel_state["leak"]), int(vessel_state["armed"]),
                int(vessel_state["mode"]), int(vessel_state["link_q"])
            )

            rpm = vessel_state["rpm"]
            coolant = int(vessel_state["coolant_temp"])
            can_payload_200 = bytes([(rpm >> 8) & 0xFF, rpm & 0xFF, (coolant + 40) & 0xFF, 0, 0, 0, 0, 0])
            can_pkt_200 = struct.pack('<IB8sI', 0x200, 8, can_payload_200, int(time.time() * 1000) & 0xFFFFFFFF)

        try:
            tx_sock.sendto(bin_pkt, (GCS_IP, GCS_TELEMETRY_PORT))
            if seq % 2 == 0:
                tx_sock.sendto(can_pkt_200, (GCS_IP, GCS_TELEMETRY_PORT))
        except Exception:
            pass

        time.sleep(0.020)

if __name__ == "__main__":
    t_can = threading.Thread(target=can_receiver_loop, daemon=True)
    t_cmd = threading.Thread(target=command_receiver_loop, daemon=True)
    t_auto = threading.Thread(target=autonomy_control_loop, daemon=True)
    t_percep = threading.Thread(target=perception_broadcast_loop, daemon=True)
    t_tx = threading.Thread(target=telemetry_transmitter_loop, daemon=True)

    t_can.start()
    t_cmd.start()
    t_auto.start()
    t_percep.start()
    t_tx.start()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        running = False
