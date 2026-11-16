import time
import math

class PIDController:
    def __init__(self, kp=1.0, ki=0.0, kd=0.0, out_min=-1.0, out_max=1.0, anti_windup=True):
        self.kp = kp
        self.ki = ki
        self.kd = kd
        self.out_min = out_min
        self.out_max = out_max
        self.anti_windup = anti_windup

        self.integral = 0.0
        self.prev_error = 0.0
        self.last_time = None

    def reset(self):
        self.integral = 0.0
        self.prev_error = 0.0
        self.last_time = None

    def update(self, error, dt=None):
        now = time.time()
        if dt is None:
            if self.last_time is None:
                dt = 0.02
            else:
                dt = max(0.001, now - self.last_time)
        self.last_time = now

        p_term = self.kp * error

        self.integral += error * dt
        if self.anti_windup:
            i_limit = (self.out_max - self.out_min) / (2.0 * max(0.0001, self.ki))
            self.integral = max(-i_limit, min(i_limit, self.integral))
        i_term = self.ki * self.integral

        derivative = (error - self.prev_error) / dt
        d_term = self.kd * derivative
        self.prev_error = error

        output = p_term + i_term + d_term
        return max(self.out_min, min(self.out_max, output))

class MarineActuatorMixer:
    def __init__(self, deadzone=0.08):
        self.deadzone = deadzone

    def apply_deadzone(self, val):
        if abs(val) < self.deadzone:
            return 0.0
        sign = 1.0 if val > 0.0 else -1.0
        return sign * ((abs(val) - self.deadzone) / (1.0 - self.deadzone))

    def mix_differential(self, throttle, rudder):
        th = self.apply_deadzone(max(-1.0, min(1.0, throttle)))
        rd = self.apply_deadzone(max(-1.0, min(1.0, rudder)))

        left = max(-1.0, min(1.0, th + rd))
        right = max(-1.0, min(1.0, th - rd))
        return left, right

