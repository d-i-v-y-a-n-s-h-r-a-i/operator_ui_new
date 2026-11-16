import math
import time

class VelocityObstaclePlanner:
    def __init__(self, safe_distance=30.0, time_horizon=10.0):
        self.safe_distance = safe_distance
        self.time_horizon = time_horizon
        self.waypoints = []
        self.active_wp_index = 0
        self.acceptance_radius = 5.0

    def set_waypoints(self, wp_list):
        self.waypoints = wp_list
        self.active_wp_index = 0

    def compute_los_guidance(self, current_lat, current_lon, current_heading, current_speed):
        if not self.waypoints or self.active_wp_index >= len(self.waypoints):
            return current_heading, 0.0

        target_wp = self.waypoints[self.active_wp_index]
        t_lat = target_wp.get("lat", target_wp.get("latitude", 0.0))
        t_lon = target_wp.get("lon", target_wp.get("longitude", 0.0))
        target_speed = target_wp.get("speed", 12.0)
        radius = target_wp.get("radius", self.acceptance_radius)

        d_lat = (t_lat - current_lat) * 111320.0
        d_lon = (t_lon - current_lon) * (111320.0 * math.cos(math.radians(current_lat)))
        distance = math.hypot(d_lat, d_lon)

        if distance < radius:
            if self.active_wp_index + 1 < len(self.waypoints):
                self.active_wp_index += 1
                return self.compute_los_guidance(current_lat, current_lon, current_heading, current_speed)
            else:
                return current_heading, 0.0

        los_angle_rad = math.atan2(d_lon, d_lat)
        desired_heading = (math.degrees(los_angle_rad) + 360.0) % 360.0
        return desired_heading, target_speed

    def evaluate_colregs_evasion(self, current_heading, current_speed, threats):
        if not threats:
            return current_heading, current_speed

        best_heading = current_heading
        best_speed = current_speed
        most_critical_ttc = float('inf')

        for threat in threats:
            range_m = float(threat.get("range_m", 100.0))
            rel_bearing = float(threat.get("bearing", 0.0))
            threat_speed = float(threat.get("speed", 8.0))

            abs_threat_bearing = (current_heading + rel_bearing + 360.0) % 360.0

            closing_speed = max(0.5, current_speed * 0.5144 + threat_speed * 0.5144 * math.cos(math.radians(rel_bearing)))
            ttc = range_m / closing_speed

            if ttc < self.time_horizon and range_m < (self.safe_distance * 2.5):
                if ttc < most_critical_ttc:
                    most_critical_ttc = ttc

                    if abs(rel_bearing) < 15.0:
                        threat["colregs"] = "HEAD_ON"
                        best_heading = (current_heading + 35.0) % 360.0
                        best_speed = current_speed * 0.8
                    elif 15.0 <= rel_bearing <= 112.5:
                        threat["colregs"] = "GIVE_WAY"
                        best_heading = (current_heading + 45.0) % 360.0
                        best_speed = current_speed * 0.7
                    elif -112.5 <= rel_bearing <= -15.0:
                        threat["colregs"] = "STAND_ON"
                        best_heading = current_heading
                        best_speed = current_speed
                    else:
                        threat["colregs"] = "OVERTAKING"
                        if rel_bearing >= 0:
                            best_heading = (current_heading + 25.0) % 360.0
                        else:
                            best_heading = (current_heading - 25.0) % 360.0

        return best_heading, best_speed

    def plan_step(self, current_lat, current_lon, current_heading, current_speed, threats):
        los_heading, los_speed = self.compute_los_guidance(current_lat, current_lon, current_heading, current_speed)
        final_heading, final_speed = self.evaluate_colregs_evasion(los_heading, los_speed, threats)
        return final_heading, final_speed, self.active_wp_index

