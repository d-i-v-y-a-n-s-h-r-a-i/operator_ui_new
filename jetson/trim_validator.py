import math
import sys
import os
import json

CONFIG_PATH = os.path.join(os.path.dirname(__file__), "..", "config", "hull_cg_metrology.json")

def load_metrology():
    with open(CONFIG_PATH, "r") as f:
        return json.load(f)

class StaticTrimValidator:
    def __init__(self):
        data = load_metrology()
        self.total_mass_kg = 222.3
        self.battery_mass_kg = 21.8
        self.lwl_m = 2.45
        self.gm_longitudinal_m = 3.20
        self.gm_transverse_m = data["hydrostatics"]["gm_metacentric_height_m"]
        self.target_pitch_min = 1.5
        self.target_pitch_max = 3.0
        self.target_roll_tolerance = 0.2

    def evaluate_static_attitude(self, pitch_deg, roll_deg):
        pitch_valid = (self.target_pitch_min <= pitch_deg <= self.target_pitch_max)
        roll_valid = (abs(roll_deg) <= self.target_roll_tolerance)

        pitch_status = "PASS"
        pitch_advisory = "Nominal bow-up static waterline."
        if pitch_deg < self.target_pitch_min:
            pitch_status = "CRITICAL: BOW-DOWN DANGER" if pitch_deg <= 0.0 else "WARNING: INSUFFICIENT BOW TRIM"
            delta_pitch = self.target_pitch_min + 0.5 - pitch_deg
            delta_rad = math.radians(delta_pitch)
            trim_moment_nm = self.total_mass_kg * 9.81 * self.gm_longitudinal_m * math.sin(delta_rad)
            shift_x_m = trim_moment_nm / (self.battery_mass_kg * 9.81)
            shift_x_cm = shift_x_m * 100.0
            pitch_advisory = f"Move 21.8kg aux battery aft by {abs(shift_x_cm):.1f} cm (from current X=1.350m toward transom)."
        elif pitch_deg > self.target_pitch_max:
            pitch_status = "WARNING: EXCESSIVE STERN SINK"
            delta_pitch = pitch_deg - 2.2
            delta_rad = math.radians(delta_pitch)
            trim_moment_nm = self.total_mass_kg * 9.81 * self.gm_longitudinal_m * math.sin(delta_rad)
            shift_x_m = trim_moment_nm / (self.battery_mass_kg * 9.81)
            shift_x_cm = shift_x_m * 100.0
            pitch_advisory = f"Move 21.8kg aux battery forward by {abs(shift_x_cm):.1f} cm (toward bow)."

        roll_status = "PASS"
        roll_advisory = "Zero transverse list. Keel balanced."
        if not roll_valid:
            list_side = "PORT" if roll_deg < 0 else "STARBOARD"
            opp_side = "STARBOARD" if roll_deg < 0 else "PORT"
            roll_status = f"WARNING: {list_side} LIST"
            roll_rad = math.radians(abs(roll_deg))
            heeling_moment_nm = self.total_mass_kg * 9.81 * self.gm_transverse_m * math.sin(roll_rad)
            shift_y_m = heeling_moment_nm / (self.battery_mass_kg * 9.81)
            shift_y_cm = shift_y_m * 100.0
            roll_advisory = f"Shift 21.8kg aux battery {shift_y_cm:.1f} cm toward {opp_side}."

        is_deployable = (pitch_valid and roll_valid)

        return {
            "pitch_deg": pitch_deg,
            "roll_deg": roll_deg,
            "pitch_status": pitch_status,
            "pitch_advisory": pitch_advisory,
            "roll_status": roll_status,
            "roll_advisory": roll_advisory,
            "is_deployable": is_deployable
        }

    def print_report(self, pitch_deg, roll_deg):
        res = self.evaluate_static_attitude(pitch_deg, roll_deg)
        print("=====================================================")
        print("   TANDAV CI4 — IN-WATER STATIC TRIM VERIFICATION    ")
        print("=====================================================")
        print(f"Measured Static Roll:   {res['roll_deg']:+05.2f} deg  [{res['roll_status']}]")
        print(f"Roll Action:            {res['roll_advisory']}")
        print("-----------------------------------------------------")
        print(f"Measured Static Pitch:  {res['pitch_deg']:+05.2f} deg  [{res['pitch_status']}]")
        print(f"Target Envelope:        +{self.target_pitch_min:.1f} deg to +{self.target_pitch_max:.1f} deg (Bow-Up)")
        print(f"Pitch Action:           {res['pitch_advisory']}")
        print("-----------------------------------------------------")
        print(f"Deployment Clearance:  {'APPROVED FOR IDLE CRUISE' if res['is_deployable'] else 'HOLD: ADJUST INTERNAL MASS FIRST'}")
        print("=====================================================")
        return res

if __name__ == "__main__":
    p = float(sys.argv[1]) if len(sys.argv) > 1 else 2.1
    r = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
    validator = StaticTrimValidator()
    validator.print_report(p, r)

