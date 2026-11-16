import math
import time

class MaritimePerceptionPipeline:
    def __init__(self, camera_height_m=1.85, focal_length_px=1150.0):
        self.camera_height = camera_height_m
        self.focal_length = focal_length_px
        self.threats = []
        self.last_detection_time = time.time()

    def estimate_distance(self, horizon_y, bbox_y_bottom, frame_height=1080):
        pixel_offset = max(2, bbox_y_bottom - horizon_y)
        angle_rad = math.atan2(pixel_offset, self.focal_length)
        distance = self.camera_height / max(0.01, math.tan(angle_rad))
        return min(1500.0, max(5.0, distance))

    def detect_horizon(self, pitch_deg, roll_deg, frame_height=1080):
        pitch_rad = math.radians(pitch_deg)
        center_y = (frame_height / 2.0) + (pitch_rad * self.focal_length)
        return max(50.0, min(frame_height - 50.0, center_y))

    def generate_horizon_sahi_windows(self, horizon_y, frame_width=1920, frame_height=1080, slice_h=384, slice_w=384):
        slices = []
        band_top = max(0, int(horizon_y - (slice_h / 2)))
        band_bottom = min(frame_height, band_top + slice_h)

        step_x = int(slice_w * 0.75)
        for x in range(0, frame_width - slice_w + 1, step_x):
            slices.append((x, band_top, slice_w, slice_h))
        return slices

    def update_mock_tracks(self, current_lat, current_lon, current_heading, current_pitch, current_roll):
        now = time.time()
        dt = now - self.last_detection_time
        self.last_detection_time = now

        horizon_y = self.detect_horizon(current_pitch, current_roll)

        t = now * 0.3
        range_1 = 180.0 - (math.sin(t) * 40.0)
        bearing_1 = 32.0 + (math.cos(t * 0.8) * 8.0)
        dist_px_1 = max(10, int(self.camera_height * self.focal_length / max(1.0, range_1)))
        y_bot_1 = horizon_y + dist_px_1

        range_2 = 320.0 + (math.cos(t * 0.5) * 60.0)
        bearing_2 = -45.0 + (math.sin(t * 0.4) * 6.0)
        dist_px_2 = max(6, int(self.camera_height * self.focal_length / max(1.0, range_2)))
        y_bot_2 = horizon_y + dist_px_2

        threat_1 = {
            "id": 1,
            "class": "VESSEL",
            "confidence": 0.94,
            "bearing": bearing_1,
            "range_m": round(range_1, 1),
            "colregs": "GIVE_WAY" if (0.0 <= bearing_1 <= 112.5) else "STAND_ON",
            "x": 0.58 + (math.sin(t) * 0.05),
            "y": max(0.1, min(0.8, (y_bot_1 - 40) / 1080.0)),
            "w": 0.09,
            "h": 0.05
        }

        threat_2 = {
            "id": 2,
            "class": "BUOY",
            "confidence": 0.89,
            "bearing": bearing_2,
            "range_m": round(range_2, 1),
            "colregs": "STAND_ON",
            "x": 0.28 + (math.cos(t * 0.6) * 0.03),
            "y": max(0.1, min(0.8, (y_bot_2 - 25) / 1080.0)),
            "w": 0.04,
            "h": 0.04
        }

        self.threats = [threat_1, threat_2]
        return self.threats

