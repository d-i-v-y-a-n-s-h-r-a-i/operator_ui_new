"""
lora_serial.py - Serial telemetry reader and bridge for TANDAV GCS.

Reads LoRa packets from USB serial (ESP32 receiver at 115200 baud).
Parses the HB:STM telemetry protocol:
  HB:STM:VS=2,HDG=0,SPD=0.0,FIX=0,LAT=0,LON=0,WP=0/0,CML=NONE,CAM=0/0,OBS=0,OID=0,ODIST=9999.0,OBRG=0
Packets are forwarded to the GCS via UDP (127.0.0.1:9001) or direct callback.
"""

import os
import sys
import time
import json
import struct
import socket
import threading

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    serial = None

MAGIC = 0x544E4456  # 'TNDV'


def find_lora_port(preferred_port=None):
    """Auto-detect the serial COM port for ESP32/LoRa."""
    if preferred_port:
        return preferred_port
    env_port = os.environ.get("TANDAV_LORA_PORT")
    if env_port:
        return env_port
    if not serial:
        return "COM3"

    ports = list(serial.tools.list_ports.comports())
    if not ports:
        return "COM3"

    # Look for known USB UART bridges (CP210x, CH340, FTDI)
    for p in ports:
        desc = (p.description or "").lower()
        hwid = (p.hwid or "").lower()
        if "cp210" in desc or "cp210" in hwid or "10c4:ea60" in hwid:
            return p.device
        if "ch340" in desc or "ch340" in hwid:
            return p.device
        if "ftdi" in desc or "usb serial" in desc:
            return p.device

    # Default to first available COM port
    return ports[0].device


def parse_lora_line(raw_line):
    """Parse text telemetry line into structured dict."""
    if isinstance(raw_line, (bytes, bytearray)):
        line_str = raw_line.decode("utf-8", errors="replace").strip()
    else:
        line_str = str(raw_line).strip()

    if not line_str:
        return None

    # Check for HB:STM: prefix
    idx = line_str.find("HB:STM:")
    if idx != -1:
        kv_part = line_str[idx + len("HB:STM:"):]
    elif "=" in line_str:
        kv_part = line_str
    else:
        # Check if line is raw JSON
        if line_str.startswith("{") and line_str.endswith("}"):
            try:
                return json.loads(line_str)
            except Exception:
                return None
        return None

    data = {}
    for token in kv_part.split(","):
        if "=" in token:
            k, v = token.split("=", 1)
            data[k.strip().upper()] = v.strip()

    if not data:
        return None

    parsed = {}
    parsed["raw"] = line_str

    # Vessel State / Mode
    vs = data.get("VS", "2")
    mode_map = {"0": "MANUAL", "1": "TELEOP", "2": "AUTO", "3": "LOITER", "4": "RTL"}
    parsed["mode"] = mode_map.get(str(vs), str(vs))
    parsed["mode_code"] = int(vs) if str(vs).isdigit() else 2

    # Heading & Speed
    try:
        parsed["heading"] = float(data.get("HDG", 0.0))
    except ValueError:
        parsed["heading"] = 0.0

    try:
        parsed["speed"] = float(data.get("SPD", 0.0))
    except ValueError:
        parsed["speed"] = 0.0

    # GPS Fix & Position
    try:
        parsed["fix"] = int(data.get("FIX", 0))
    except ValueError:
        parsed["fix"] = 0

    try:
        lat = float(data.get("LAT", 0.0))
        if abs(lat) > 90.0:
            lat = lat / 1e7
        parsed["lat"] = lat
    except ValueError:
        parsed["lat"] = 0.0

    try:
        lon = float(data.get("LON", 0.0))
        if abs(lon) > 180.0:
            lon = lon / 1e7
        parsed["lon"] = lon
    except ValueError:
        parsed["lon"] = 0.0

    # Waypoint
    wp_str = data.get("WP", "0/0")
    if "/" in wp_str:
        wp_parts = wp_str.split("/", 1)
        parsed["wp_cur"] = int(wp_parts[0]) if wp_parts[0].isdigit() else 0
        parsed["wp_tot"] = int(wp_parts[1]) if wp_parts[1].isdigit() else 0
    else:
        parsed["wp_cur"] = int(wp_str) if wp_str.isdigit() else 0
        parsed["wp_tot"] = 0

    parsed["cml"] = data.get("CML", "LORA")
    parsed["cam"] = data.get("CAM", "0/0")

    # Obstacles & Threats
    try:
        obs_count = int(data.get("OBS", 0))
    except ValueError:
        obs_count = 0
    parsed["obs"] = obs_count

    try:
        oid = int(data.get("OID", 0))
    except ValueError:
        oid = 0

    try:
        odist = float(data.get("ODIST", 9999.0))
    except ValueError:
        odist = 9999.0

    try:
        obrg = float(data.get("OBRG", 0.0))
    except ValueError:
        obrg = 0.0

    threats = []
    if obs_count > 0 or odist < 9000.0:
        threats.append({
            "id": oid,
            "distance": odist,
            "bearing": obrg,
            "type": "VESSEL"
        })
    parsed["threats"] = threats

    # Optional battery / engine telemetry if present
    parsed["bat_v"] = float(data.get("BAT_V", data.get("BV", 24.8))) if ("BAT_V" in data or "BV" in data) else 24.8
    parsed["bat_a"] = float(data.get("BAT_A", data.get("BA", 1.2))) if ("BAT_A" in data or "BA" in data) else 1.2
    parsed["bat_pct"] = int(data.get("BAT_PCT", data.get("BPCT", 95))) if ("BAT_PCT" in data or "BPCT" in data) else 95
    parsed["bat_temp"] = float(data.get("BAT_TEMP", data.get("BTMP", 28.0))) if ("BAT_TEMP" in data or "BTMP" in data) else 28.0
    parsed["pitch"] = float(data.get("PITCH", 0.0)) if "PITCH" in data else 0.0
    parsed["roll"] = float(data.get("ROLL", 0.0)) if "ROLL" in data else 0.0
    parsed["rpm"] = int(data.get("RPM", 0 if parsed["speed"] < 0.2 else int(2000 + parsed["speed"] * 120)))
    parsed["coolant"] = float(data.get("COOLANT", data.get("TEMP", 65.0))) if ("COOLANT" in data or "TEMP" in data) else 65.0
    parsed["depth"] = float(data.get("DEPTH", 2.4)) if "DEPTH" in data else 2.4
    parsed["link_q"] = int(data.get("LQ", 99)) if "LQ" in data else 99

    return parsed


def pack_binary_77(parsed, seq=1, fallback_lat=12.9716, fallback_lon=77.5946):
    """Pack parsed dict into the 77-byte binary telemetry format '<IIfffddffffBfffffBBBB'."""
    p = float(parsed.get("pitch", 0.0))
    r = float(parsed.get("roll", 0.0))
    y = float(parsed.get("heading", 0.0))

    lat = float(parsed.get("lat", 0.0))
    lon = float(parsed.get("lon", 0.0))
    if lat == 0.0 and lon == 0.0:
        lat = fallback_lat
        lon = fallback_lon

    spd = float(parsed.get("speed", 0.0))
    hdg = float(parsed.get("heading", 0.0))
    bv = float(parsed.get("bat_v", 24.8))
    ba = float(parsed.get("bat_a", 1.2))
    bpct = int(parsed.get("bat_pct", 95))
    btmp = float(parsed.get("bat_temp", 28.0))

    # thrusters estimate
    th = min(1.0, spd / 20.0) if spd > 0.1 else 0.0
    tl = th
    tr = th

    dpt = float(parsed.get("depth", 2.4))
    wt = 24.0
    lk = 0
    arm = 1
    md = int(parsed.get("mode_code", 2))
    lq = int(parsed.get("link_q", 99))

    return struct.pack(
        '<IIfffddffffBfffffBBBB',
        MAGIC,
        seq,
        p, r, y,
        lat, lon,
        spd, hdg,
        bv, ba, bpct, btmp,
        tl, tr,
        dpt, wt,
        lk, arm, md, lq
    )


def make_cluster_json(parsed, seq=1):
    """Generate JSON text for InstrumentCluster.qml."""
    spd = float(parsed.get("speed", 0.0))
    rpm = int(parsed.get("rpm", 0 if spd < 0.2 else int(2000 + spd * 120)))
    return json.dumps({
        "seq": int(seq),
        "speedKn": round(spd, 1),
        "speedKmh": round(spd * 1.852, 1),
        "rpm": rpm,
        "gear": "N" if spd < 0.2 else "F",
        "driveMode": "SPORT",
        "control": parsed.get("mode", "AUTO"),
        "fuelPct": 85,
        "coolantC": round(parsed.get("coolant", 65.0), 1),
        "battV": round(parsed.get("bat_v", 24.8), 1),
        "tripKm": round(seq * 0.001, 2),
        "engineHours": 328.2
    })


class LoraSerialReceiver:
    """Manages the background thread reading serial LoRa telemetry."""

    def __init__(self, port="COM3", baud=115200, on_telemetry=None, udp_target=("127.0.0.1", 9001)):
        self.port = port
        self.baud = baud
        self.on_telemetry = on_telemetry
        self.udp_target = udp_target
        self.running = False
        self.thread = None
        self.udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.seq = 0
        self.last_connected = False
        self.permission_warned = False

    def start(self):
        if self.running:
            return
        self.running = True
        self.thread = threading.Thread(target=self._run_loop, name="LoraSerialLoop", daemon=True)
        self.thread.start()

    def stop(self):
        self.running = False

    def _run_loop(self):
        while self.running:
            actual_port = find_lora_port(self.port)
            ser = None
            try:
                ser = serial.Serial(actual_port, self.baud, timeout=1.0)
                if not self.last_connected:
                    print(f"[LoRa Serial] Successfully connected to {actual_port} @ {self.baud} baud!", flush=True)
                    self.last_connected = True
                    self.permission_warned = False

                while self.running and ser.is_open:
                    line = ser.readline()
                    if not line:
                        continue
                    parsed = parse_lora_line(line)
                    if parsed:
                        self.seq += 1
                        bin_pkt = pack_binary_77(parsed, self.seq)
                        cluster_json = make_cluster_json(parsed, self.seq)

                        # Send via UDP to GCS
                        if self.udp_target:
                            try:
                                self.udp_sock.sendto(bin_pkt, self.udp_target)
                                self.udp_sock.sendto(cluster_json.encode("utf-8"), self.udp_target)
                                if parsed.get("threats"):
                                    threats_pkt = json.dumps({"type": "THREATS", "threats": parsed["threats"]}).encode("utf-8")
                                    self.udp_sock.sendto(threats_pkt, self.udp_target)
                            except Exception:
                                pass

                        # Call direct callback if registered
                        if self.on_telemetry:
                            try:
                                self.on_telemetry(parsed, bin_pkt, cluster_json)
                            except Exception:
                                pass

            except (serial.SerialException, PermissionError, OSError) as e:
                err_str = str(e)
                if "Access is denied" in err_str or "PermissionError" in err_str or "13" in err_str:
                    if not self.permission_warned:
                        print(f"\n[LoRa Serial] WARNING: Port {actual_port} is busy (locked by another application, such as Arduino IDE Serial Monitor)!", flush=True)
                        print(f"[LoRa Serial] PLEASE CLOSE THE SERIAL MONITOR IN ARDUINO IDE so the GCS can read from {actual_port}.", flush=True)
                        print(f"[LoRa Serial] Retrying every 2 seconds...\n", flush=True)
                        self.permission_warned = True
                else:
                    self.permission_warned = False

                self.last_connected = False
                time.sleep(2.0)
            except Exception as e:
                self.last_connected = False
                time.sleep(2.0)
            finally:
                if ser:
                    try:
                        ser.close()
                    except Exception:
                        pass


def main():
    import argparse
    parser = argparse.ArgumentParser(description="TANDAV LoRa Serial to UDP Bridge")
    parser.add_argument("--port", default="COM3", help="Serial port (e.g. COM3)")
    parser.add_argument("--baud", type=int, default=115200, help="Baud rate (default: 115200)")
    parser.add_argument("--udp-port", type=int, default=9001, help="Target UDP port (default: 9001)")
    args = parser.parse_args()

    print(f"=== TANDAV LoRa Serial Bridge ===")
    print(f"Connecting to: {args.port} @ {args.baud} baud")
    print(f"Target GCS UDP: 127.0.0.1:{args.udp_port}")
    print("Press Ctrl+C to stop.\n")

    receiver = LoraSerialReceiver(port=args.port, baud=args.baud, udp_target=("127.0.0.1", args.udp_port))
    receiver.start()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nStopping LoRa Serial Bridge...")
        receiver.stop()


if __name__ == "__main__":
    main()
